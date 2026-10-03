"""Exercise editor scripts with local command stubs and temporary configuration."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
EDITORS = {
    "t3-code": ("t3-code-direct", 3773, "180s"),
    "openchamber": ("openchamber-direct", 3000, "180s"),
    "orca": ("orca-direct", 6768, "180s"),
    "vs-code-agent-host": ("agent-host-direct", 3773, "300s"),
}


class EditorScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="editor scripts ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "shared").mkdir()
        shutil.copyfile(REPO / "shared/deploy.sh", self.root / "shared/deploy.sh")
        for editor in EDITORS:
            (self.root / editor).mkdir()
            for name in ("deploy.sh", "teardown.sh"):
                shutil.copyfile(REPO / editor / name, self.root / editor / name)
        (self.root / "config.env").write_text(
            "NAMESPACE=test-workspaces\n"
            "T3_IMAGE=localhost/test-t3\n"
            "OPENCHAMBER_IMAGE=localhost/test-chamber\n"
            "ORCA_IMAGE=localhost/test-orca\n"
            "AGENT_HOST_IMAGE=localhost/test-vscode\n"
            "GOOGLE_CLOUD_PROJECT=test-project\n"
            "CLOUD_ML_REGION=test-region\n"
            "OPENCHAMBER_UI_PASSWORD=test-password\n"
            "REDHAT_AI_NAMESPACE=test-models\n"
        )
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.jsonl"
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            TEST_COMMAND_LOG=str(self.log),
        )
        stub = f"#!{sys.executable}\n" + '''
import json, os, sys
from pathlib import Path
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
entry = {"tool": tool, "args": args}
if tool == "oc" and args[0] == "apply":
    entry["manifest"] = sys.stdin.read()
with open(os.environ["TEST_COMMAND_LOG"], "a") as log:
    log.write(json.dumps(entry) + "\\n")
if tool == "oc":
    if args[:2] == ["get", "pods"]:
        print("cleanup-job 0/1 Completed 0 1m")
        print("old-pod 0/1 Completed 0 1m")
        print("workspace-pod 2/2 Running 0 1m")
        print("another-pod 2/2 Running 0 1m")
    elif args[:2] == ["get", "pod"]:
        print("workspace-id")
    elif args[:2] == ["get", "route"]:
        print("editor.test.example")
    elif args[0] == "exec":
        print("https://editor.test.example/paired" if "node" in args else "test-token")
    elif args[0] == "wait" and os.environ.get("TEST_WAIT_FAILURE"):
        sys.exit(1)
elif tool == "podman" and os.environ.get("TEST_BUILD_FAILURE"):
    sys.exit(1)
'''
        for tool in ("oc", "podman"):
            path = self.bin / tool
            path.write_text(stub)
            path.chmod(0o755)
        sleep = self.bin / "sleep"
        sleep.write_text("#!/bin/sh\nexit 0\n")
        sleep.chmod(0o755)

    def run_script(self, editor, name):
        self.log.unlink(missing_ok=True)
        result = subprocess.run(
            ["bash", str(self.root / editor / name)],
            cwd=self.bin,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=15,
        )
        commands = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, commands

    def test_all_deployments_keep_resource_names_ports_and_order(self):
        for editor, (route, port, timeout) in EDITORS.items():
            with self.subTest(editor=editor):
                result, commands = self.run_script(editor, "deploy.sh")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(commands[0]["args"][0], "build")
                self.assertEqual(commands[1]["args"][0], "push")
                manifests = [entry["manifest"] for entry in commands if "manifest" in entry]
                self.assertEqual(len(manifests), 3)
                template = next(value for value in manifests if "kind: DevWorkspaceTemplate\n" in value)
                workspace = next(value for value in manifests if "kind: DevWorkspace\n" in value)
                direct_route = next(value for value in manifests if "kind: Route\n" in value)
                self.assertIn(f"name: {editor}-editor\n", template)
                self.assertIn(f"name: {editor}-workspace\n", workspace)
                self.assertIn(f"name: {route}\n", direct_route)
                self.assertIn(f"targetPort: {port}\n", direct_route)
                self.assertIn("insecureEdgeTerminationPolicy: Redirect", direct_route)
                if editor == "orca":
                    self.assertIs(manifests[0], direct_route)
                    self.assertIn("wss://editor.test.example/", template)
                    self.assertIn('value: "test-models"', template)
                    self.assertIn("controller.devfile.io/devworkspace_name: orca-workspace", direct_route)
                else:
                    self.assertIs(manifests[-1], direct_route)
                    self.assertIn("controller.devfile.io/devworkspace_id: workspace-id", direct_route)
                waits = [entry["args"] for entry in commands if entry["tool"] == "oc" and entry["args"][0] == "wait"]
                self.assertEqual(len(waits), 1)
                self.assertIn("pod/workspace-pod", waits[0])
                self.assertIn(f"--timeout={timeout}", waits[0])
                for entry in commands:
                    if entry["tool"] == "oc":
                        self.assertEqual(entry["args"][entry["args"].index("-n") + 1], "test-workspaces")

    def test_all_teardowns_only_remove_their_own_resources(self):
        for editor, (route, _, _) in EDITORS.items():
            with self.subTest(editor=editor):
                result, commands = self.run_script(editor, "teardown.sh")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([entry["args"] for entry in commands], [
                    ["delete", kind, name, "-n", "test-workspaces", "--ignore-not-found"]
                    for kind, name in (
                        ("devworkspace", f"{editor}-workspace"),
                        ("devworkspacetemplate", f"{editor}-editor"),
                        ("service", route),
                        ("route", route),
                    )
                ])

    def test_missing_namespace_stops_before_external_commands(self):
        (self.root / "config.env").write_text("NAMESPACE=\n")
        for editor in EDITORS:
            for name in ("deploy.sh", "teardown.sh"):
                with self.subTest(editor=editor, script=name):
                    result, commands = self.run_script(editor, name)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(commands, [])

    def test_failed_build_does_not_push_or_create_resources(self):
        self.env["TEST_BUILD_FAILURE"] = "1"
        for editor in EDITORS:
            with self.subTest(editor=editor):
                result, commands = self.run_script(editor, "deploy.sh")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(commands), 1)
                self.assertEqual(commands[0]["args"][0], "build")

    def test_failed_readiness_stops_before_pairing(self):
        self.env["TEST_WAIT_FAILURE"] = "1"
        for editor in EDITORS:
            with self.subTest(editor=editor):
                result, commands = self.run_script(editor, "deploy.sh")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(commands[-1]["args"][0], "wait")

    def test_runtime_registers_bashrc_once_with_private_permissions(self):
        home = self.root / "home"
        home.mkdir()
        bashrc = self.root / "shared bashrc.sh"
        bashrc.write_text("export TEST_BASHRC_LOADED=yes\n")
        helper = self.root / "runtime.sh"
        helper.write_text((REPO / "shared/runtime.sh").read_text().replace("$HOME", "$TEST_USER_HOME"))
        env = dict(self.env, TEST_USER_HOME=str(home))
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; setup_runtime "$2"; setup_runtime "$2"; source "$TEST_USER_HOME/.bashrc"; echo "$TEST_BASHRC_LOADED"', "test", str(helper), str(bashrc)],
            env=env, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "yes")
        self.assertEqual(len((home / ".bashrc").read_text().splitlines()), 1)
        self.assertEqual((home / ".bashrc").stat().st_mode & 0o777, 0o600)
