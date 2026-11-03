"""Render an editor devfile, a DevWorkspaceTemplate, or a Che editor definition."""

import argparse
import os
from pathlib import Path
import re
import sys
import tempfile

try:
    import yaml
except ImportError:
    sys.exit("Install the devfile renderer dependency with: python3 -m pip install -r requirements.txt")


IMAGE_VARIABLES = {"T3_IMAGE", "OPENCHAMBER_IMAGE", "ORCA_IMAGE", "AGENT_HOST_IMAGE", "BOB_IMAGE", "OPENCLAW_IMAGE", "PASEO_IMAGE"}
DEFAULTS = {
    "OPENCHAMBER_UI_PASSWORD": "",
    "ORCA_PAIRING_ADDRESS": "",
    "BOB_OPENCODE_MODEL": "opencode/glm-5.3-flash-free",
    "PASEO_PASSWORD": "",
    "PASEO_HOSTNAMES": "",
    # Paseo trusts X-Forwarded-* only from these sources. Private ranges cover
    # cluster networks and host-network routers; narrow this when your router
    # uses a fixed address.
    "PASEO_TRUSTED_PROXIES": "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16",
    # OpenClaw rejects proxied requests unless the proxy source is trusted.
    # Private ranges cover cluster networks and host-network routers; narrow this
    # in config.env when your router uses a fixed address.
    "OPENCLAW_TRUSTED_PROXIES": "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16",
    "OPENCLAW_PUBLIC_ORIGIN": "",
    "OPENCLAW_GATEWAY_TOKEN": "",
}
PLACEHOLDER = re.compile(r"\$\{([A-Z_][A-Z0-9_]*)\}")
# Che builds an editor id as publisher/metadata.name/version and shows the editor
# in the dashboard picker. Upstream definitions keep these values in sync, so
# reject definitions the dashboard would silently drop or mislabel.
EDITOR_NAME = re.compile(r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$")
EDITOR_ARCHES = {"x86_64", "arm64", "s390x", "ppc64le"}


def substitute(value, environment):
    if isinstance(value, str):
        def replace(match):
            name = match[1]
            if name in IMAGE_VARIABLES:
                if not environment.get(name):
                    raise ValueError(f"Set {name} in config.env")
                return environment[name]
            if name in DEFAULTS:
                return environment.get(name) or DEFAULTS[name]
            return match[0]
        return PLACEHOLDER.sub(replace, value)
    if isinstance(value, list):
        return [substitute(item, environment) for item in value]
    if isinstance(value, dict):
        return {key: substitute(item, environment) for key, item in value.items()}
    return value


def editor_definition(document, configmap_name):
    """Wrap a rendered devfile in the ConfigMap Che reads editor definitions from."""
    metadata = document.get("metadata")
    attributes = metadata.get("attributes") if isinstance(metadata, dict) else None
    if not isinstance(attributes, dict):
        raise ValueError("Editor definitions need metadata.attributes")

    missing = [key for key in ("publisher", "version", "arch") if not attributes.get(key)]
    if missing:
        raise ValueError(f"Editor definitions need metadata.attributes.{', metadata.attributes.'.join(missing)}")

    name = metadata.get("name")
    if not isinstance(name, str) or not EDITOR_NAME.match(name):
        raise ValueError("Editor metadata.name must be lower case alphanumeric characters, '-' or '.'")

    arch = attributes["arch"]
    if not isinstance(arch, list) or not arch or set(arch) - EDITOR_ARCHES:
        raise ValueError(f"Editor metadata.attributes.arch must be a nonempty list of: {', '.join(sorted(EDITOR_ARCHES))}")

    return {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {
            "name": configmap_name,
            "labels": {
                "app.kubernetes.io/part-of": "che.eclipse.org",
                "app.kubernetes.io/component": "editor-definition",
            },
        },
        # The dashboard reads every value in data, so the key only needs to be
        # descriptive. devfile.yaml matches the upstream editor definitions.
        "data": {"devfile.yaml": yaml.safe_dump(document, sort_keys=False, allow_unicode=True)},
    }


def render(path, environment, template_name=None, configmap_name=None):
    if template_name and configmap_name:
        raise ValueError("Choose either a DevWorkspaceTemplate or an editor definition ConfigMap")
    document = yaml.safe_load(Path(path).read_text())
    if not isinstance(document, dict) or not isinstance(document.get("components"), list) or not document["components"]:
        raise ValueError("The devfile must contain a nonempty components list")
    document = substitute(document, environment)
    if template_name:
        document = {
            "apiVersion": "workspace.devfile.io/v1alpha2",
            "kind": "DevWorkspaceTemplate",
            "metadata": {"name": template_name},
            "spec": {key: value for key, value in document.items() if key not in ("schemaVersion", "metadata")},
        }
    elif configmap_name:
        document = editor_definition(document, configmap_name)
    return document


def write_output(path, text):
    path = Path(path)
    temporary = None
    try:
        # The rendered file can contain a UI password. Replace it only after success.
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=f".{path.name}.", delete=False) as output:
            temporary = Path(output.name)
            output.write(text)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("devfile", type=Path)
    parser.add_argument("--template", help="DevWorkspaceTemplate resource name")
    parser.add_argument("--configmap", metavar="NAME", help="Wrap the devfile in a Che editor definition ConfigMap")
    parser.add_argument("--output", type=Path, help="Write a private rendered file instead of stdout")
    parser.add_argument("--check", action="store_true", help="Validate the devfile and variables without writing output")
    args = parser.parse_args()
    try:
        document = render(args.devfile, os.environ, args.template, args.configmap)
        if args.check:
            return
        text = yaml.safe_dump(document, sort_keys=False, allow_unicode=True)
        if args.output:
            write_output(args.output, text)
        else:
            sys.stdout.write(text)
    except (OSError, ValueError, yaml.YAMLError) as error:
        sys.exit(f"render-devfile: {error}")


if __name__ == "__main__":
    main()
