"""Local discovery checks. Run with python3 -m unittest discover -s tests."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


class KServeDiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="kserve-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.output = self.root / "opencode.json"
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            REDHAT_AI_NAMESPACE="test-models",
            TEST_MODELS="isvc-code-model isvc-offline",
            TEST_OC_LOG=str(self.root / "oc.log"),
            TEST_CURL_LOG=str(self.root / "curl.log"),
        )
        self.stub(
            "oc",
            'printf "%s\\n" "$*" >> "$TEST_OC_LOG"\n'
            'if [ "$1" = get ]; then printf "%s" "$TEST_MODELS"; fi',
        )
        self.stub(
            "cat",
            'if [ "$1" = /run/secrets/kubernetes.io/serviceaccount/token ]; then\n'
            '  printf "%s\\n" test-service-token\n'
            'else\n'
            '  exec /bin/cat "$@"\n'
            'fi',
        )
        self.stub(
            "curl",
            'printf "%s\\n" "${*: -1}" >> "$TEST_CURL_LOG"\n'
            'case "${*: -1}" in\n'
            '  *isvc-code-model-predictor*) '
            "printf '%s\\n' "
            "'{\"data\":[{\"id\":\"served-model\",\"max_model_len\":32768}]}' ;;\n"
            '  *) exit 22 ;;\n'
            'esac',
        )

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(f"#!/bin/bash\n{body}\n")
        path.chmod(0o755)

    def discover(self, profile=None, vscode_output=None):
        args = ["bash", str(REPO / "shared/discover-models.sh"), str(self.output)]
        if profile is not None or vscode_output is not None:
            args.append(profile or "backend")
        if vscode_output is not None:
            args.append(str(vscode_output))
        return subprocess.run(args, env=self.env, capture_output=True, text=True)

    def test_backend_keeps_existing_tool_policy(self):
        result = self.discover()
        self.assertEqual(result.returncode, 0, result.stderr)
        config = json.loads(self.output.read_text())
        self.assertFalse(config["tools"]["bash"])
        self.assertFalse(config["tools"]["edit"])
        self.assertTrue(all(value is False for value in config["tools"].values()))

    def test_agent_discovers_models_without_overriding_tools_or_permissions(self):
        result = self.discover("agent")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = json.loads(self.output.read_text())
        self.assertNotIn("tools", config)
        self.assertNotIn("permission", config)
        self.assertEqual(config["model"], "redhat/code-model")
        provider = config["provider"]["redhat"]
        self.assertEqual(set(provider["models"]), {"code-model"})
        model = provider["models"]["code-model"]
        self.assertEqual(model["id"], "served-model")
        self.assertEqual(model["limit"]["context"], 32768)
        self.assertEqual(
            model["provider"]["api"],
            "https://isvc-code-model-predictor.test-models.svc.cluster.local:8443/v1",
        )
        self.assertEqual(
            provider["options"]["apiKey"],
            "{file:/run/secrets/kubernetes.io/serviceaccount/token}",
        )
        self.assertNotIn("test-service-token", self.output.read_text())
        self.assertNotIn("test-service-token", result.stdout + result.stderr)
        self.assertIn("-n test-models", (self.root / "oc.log").read_text())

    def test_agent_replaces_legacy_backend_tool_restrictions(self):
        self.assertEqual(self.discover().returncode, 0)
        self.assertIn("tools", json.loads(self.output.read_text()))
        self.assertEqual(self.discover("agent").returncode, 0)
        self.assertNotIn("tools", json.loads(self.output.read_text()))

    def test_missing_namespace_skips_cluster_access_and_preserves_configs(self):
        original = '{"provider":{"manual":{"name":"My provider"}}}\n'
        vscode_output = self.root / "chatLanguageModels.json"
        self.output.write_text(original)
        vscode_output.write_text('[{"name":"Manual"}]')
        for namespace in (None, ""):
            with self.subTest(namespace=namespace):
                if namespace is None:
                    self.env.pop("REDHAT_AI_NAMESPACE", None)
                else:
                    self.env["REDHAT_AI_NAMESPACE"] = namespace
                result = self.discover(vscode_output=vscode_output)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("REDHAT_AI_NAMESPACE not set, skipping", result.stdout)
                self.assertEqual(self.output.read_text(), original)
                self.assertEqual(vscode_output.read_text(), '[{"name":"Manual"}]')
                self.assertFalse((self.root / "oc.log").exists())
                self.assertFalse((self.root / "curl.log").exists())

    def test_no_services_preserves_existing_config(self):
        original = '{"provider":{"manual":{"name":"My provider"}}}\n'
        self.output.write_text(original)
        self.env["TEST_MODELS"] = ""
        result = self.discover("agent")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), original)

    def test_cluster_error_preserves_config_and_reports_access_failure(self):
        original = '{"provider":{"manual":{"name":"My provider"}}}\n'
        self.output.write_text(original)
        self.stub("oc", 'echo "server unavailable" >&2; exit 1')
        result = self.discover("agent")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), original)
        self.assertIn("cannot list InferenceServices in test-models", result.stderr)
        self.assertNotIn("no InferenceServices", result.stdout + result.stderr)

    def test_unreachable_services_do_not_create_config(self):
        self.env["TEST_MODELS"] = "isvc-offline"
        result = self.discover("agent")
        self.assertEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())

    def test_invalid_profile_fails_before_cluster_access(self):
        result = self.discover("invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertFalse((self.root / "oc.log").exists())

    def test_both_formats_share_one_probe_and_keep_credentials_separate(self):
        vscode_output = self.root / "chatLanguageModels.json"
        vscode_output.write_text("[]")
        vscode_output.chmod(0o644)
        result = self.discover(vscode_output=vscode_output)
        self.assertEqual(result.returncode, 0, result.stderr)
        opencode_model = json.loads(self.output.read_text())["provider"]["redhat"]["models"]["code-model"]
        vscode_provider = json.loads(vscode_output.read_text())[0]
        self.assertEqual(vscode_provider["apiKey"], "test-service-token")
        self.assertEqual(vscode_provider["vendor"], "customendpoint")
        vscode_model = vscode_provider["models"][0]
        self.assertEqual(vscode_model["id"], opencode_model["id"])
        self.assertEqual(vscode_model["name"], opencode_model["name"])
        self.assertEqual(vscode_model["url"], opencode_model["provider"]["api"] + "/chat/completions")
        self.assertEqual(vscode_model["maxInputTokens"], opencode_model["limit"]["context"])
        self.assertEqual(vscode_output.stat().st_mode & 0o777, 0o600)
        self.assertNotIn("test-service-token", self.output.read_text())
        self.assertNotIn("test-service-token", result.stdout + result.stderr)
        self.assertEqual(len((self.root / "curl.log").read_text().splitlines()), 2)
        self.assertEqual(len((self.root / "oc.log").read_text().splitlines()), 1)

    def test_cluster_error_preserves_both_configs(self):
        vscode_output = self.root / "chatLanguageModels.json"
        self.output.write_text('{"provider":{}}')
        vscode_output.write_text('[{"name":"Manual"}]')
        self.stub("oc", "exit 1")
        result = self.discover(vscode_output=vscode_output)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), '{"provider":{}}')
        self.assertEqual(vscode_output.read_text(), '[{"name":"Manual"}]')
        self.assertFalse((self.root / "curl.log").exists())


if __name__ == "__main__":
    unittest.main()
