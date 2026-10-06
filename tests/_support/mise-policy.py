"""Exercise Mise policy through its executable, without a real Mise."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[2]


class MisePolicyTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-mise-policy-")
        self.addCleanup(self.temporary.cleanup)
        self.fixture = Path(self.temporary.name).resolve()
        self.checkout = self.fixture / "checkout with spaces"
        for name in ("mise", "_scripts"):
            (self.checkout / name).mkdir(parents=True)
        for name in ("home", "bin", "outside"):
            (self.fixture / name).mkdir()
        shutil.copy2(ROOT / "_scripts/trusted-roots", self.checkout / "_scripts")
        shutil.copy2(ROOT / "_scripts/mise-policy", self.checkout / "_scripts")
        for name in ("mise.zsh", "completion.zsh"):
            shutil.copy2(ROOT / "mise" / name, self.checkout / "mise")
        self.config = self.checkout / "mise/config.toml"
        self.config.write_text('[tools]\nnode = "lts" # Runtime\n')
        self.lock = self.checkout / "mise/mise.lock"
        self.lock.write_text('[[tools.node]]\nversion = "24.0.0"\n')
        fake = self.fixture / "bin/mise"
        fake.write_text(f"#!{sys.executable}\n" + (ROOT / "tests/_support/mise.py").read_text())
        fake.chmod(0o755)
        self.trace = self.fixture / "trace"
        self.env = {
            "HOME": str(self.fixture / "home"),
            "PATH": f"{self.fixture / 'bin'}:/usr/bin:/bin",
            "WORKSPACE": str(self.fixture / "workspace"),
            "FAKE_MISE_TRACE": str(self.trace),
        }

    def invoke(self, *args, **overrides):
        return subprocess.run(
            [str(ROOT / "_scripts/mise-policy"), str(self.checkout), *args],
            cwd=self.fixture / "outside", env={**self.env, **overrides},
            text=True, capture_output=True,
        )

    def calls(self):
        return [json.loads(line) for line in self.trace.read_text().splitlines()]

    def test_maintenance_uses_the_explicit_checkout_with_full_trust_and_locked_versions(self):
        before = self.lock.read_bytes()
        result = self.invoke("run", "install", MISE_GLOBAL_CONFIG_FILE="/wrong/config.toml",
                             MISE_NODE_VERSION="99", MISE_LOCKED="false")
        self.assertEqual(result.returncode, 0, result.stderr)
        call = self.calls()[-1]
        self.assertEqual(call["config"], str(self.config))
        self.assertEqual(call["cwd"], str(self.checkout))
        self.assertTrue(call["locked"])
        self.assertEqual(call["selectors"], {})
        self.assertEqual(call["trust"].split(":"), [str(self.checkout),
                         str(self.fixture / "workspace"), str(self.fixture / "home/conductor")])
        self.assertEqual(self.lock.read_bytes(), before)

    def test_only_selected_regeneration_can_write_and_stage_trust_does_not_escape(self):
        stage = self.fixture / "stage"
        stage.mkdir()
        (stage / "config.toml").write_text('[tools]\nnode = "24.1.0" # Runtime\n')
        shutil.copy2(self.lock, stage / "mise.lock")
        before = self.lock.read_bytes()
        result = self.invoke("--declarations", str(stage), "lock", "node")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('version = "24.1.0"', (stage / "mise.lock").read_text())
        self.assertFalse(self.calls()[-1]["locked"])
        self.assertIn(str(stage), self.calls()[-1]["trust"].split(":"))
        result = self.invoke("--declarations", str(stage), "run", "install", "node")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.calls()[-1]["locked"])
        self.assertEqual(self.lock.read_bytes(), before)
        result = self.invoke("run", "install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(str(stage), self.calls()[-1]["trust"].split(":"))

    def test_reconciliation_refuses_missing_and_incompatible_locks(self):
        self.lock.unlink()
        result = self.invoke("run", "install")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.trace.exists())
        self.assertIn("regenerate selected tools", result.stderr)
        self.lock.write_text('[[tools.node]]\nversion = "24.0.0"\n')
        self.config.write_text('[tools]\nnode = "24.1.0" # Runtime\n')
        before = self.lock.read_bytes()
        result = self.invoke("run", "install")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.lock.read_bytes(), before)

    def test_regeneration_requires_a_selection_and_is_not_a_generic_run_command(self):
        for args in (("lock",), ("lock", "--bump"), ("lock", "--bump", "--bump"),
                     ("run", "lock", "--global"), ("run", "upgrade")):
            result = self.invoke(*args)
            self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.trace.exists())

    def shell(self, **overrides):
        return subprocess.run(
            ["/bin/zsh", "-f", "-c", 'source "$1/mise/mise.zsh"; '
             'source "$1/mise/completion.zsh"; '
             'printf "%s\\n" "${MISE_GLOBAL_CONFIG_FILE-unset}" "$MISE_TRUSTED_CONFIG_PATHS" '
             '"${FAKE_MISE_ACTIVATED-unset}" "${_fake_mise_completion-unset}"',
             "zsh", str(self.checkout)], cwd=self.fixture / "outside",
            env={**self.env, "DOTFILES_ROOT": "/wrong", **overrides},
            text=True, capture_output=True,
        )

    def test_shell_preserves_personal_selection_and_quotes_trust_paths(self):
        workspace = str(self.fixture / "owner's workspace")
        result = self.shell(MISE_GLOBAL_CONFIG_FILE="/personal/config.toml", WORKSPACE=workspace)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        lines = result.stdout.splitlines()
        self.assertEqual(lines[0], "/personal/config.toml")
        self.assertIn(workspace, lines[1].split(":"))
        self.assertEqual(lines[2:], ["1", "1"])

    def test_shell_discards_partial_activation_and_preserves_previous_environment(self):
        legacy = str(self.fixture / "home/.config/mise/config.toml")
        result = self.shell(MISE_GLOBAL_CONFIG_FILE=legacy, MISE_TRUSTED_CONFIG_PATHS="/previous",
                            FAIL_MISE_ACTIVATE="1")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines(), [legacy, "/previous", "unset", "unset"])
        self.assertIn("activation failed", result.stderr)
        self.assertEqual([c["args"][0] for c in self.calls()], ["activate"])

    def test_shell_removes_only_the_legacy_default_selector_after_success(self):
        result = self.shell(MISE_GLOBAL_CONFIG_FILE=str(self.fixture / "home/.config/mise/config.toml"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], "unset")
        self.assertEqual(result.stdout.splitlines()[2:], ["1", "1"])

    def test_shell_trust_failure_keeps_shell_usable_without_activation_or_completion(self):
        (self.checkout / "_scripts/trusted-roots").write_text('#!/bin/sh\necho /partial\nexit 1\n')
        result = self.shell(MISE_TRUSTED_CONFIG_PATHS="/previous")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.splitlines(), ["unset", "/previous", "unset", "unset"])
        self.assertIn("cannot prepare trusted roots", result.stderr)
        self.assertFalse(self.trace.exists())

    def test_trust_failure_emits_nothing_and_never_starts_mise(self):
        (self.checkout / "_scripts/trusted-roots").write_text('#!/bin/sh\necho /partial\nexit 1\n')
        for operation in ("ci", "shell", "run"):
            args = (operation, "install") if operation == "run" else (operation,)
            result = self.invoke(*args)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
        self.assertFalse(self.trace.exists())

    def test_ci_consumes_the_same_policy_and_local_file_matches_its_owner(self):
        result = self.invoke("ci")
        self.assertEqual(result.returncode, 0, result.stderr)
        ci_env = dict(line.split("=", 1) for line in result.stdout.splitlines())
        direct = subprocess.run([str(self.fixture / "bin/mise"), "install"],
                                cwd=self.checkout, env={**self.env, **ci_env},
                                text=True, capture_output=True)
        self.assertEqual(direct.returncode, 0, direct.stderr)
        ci_call = self.calls()[-1]
        self.assertEqual(self.invoke("run", "install").returncode, 0)
        self.assertEqual(ci_call, self.calls()[-1])
        local = self.invoke("local")
        self.assertEqual(local.returncode, 0, local.stderr)
        self.assertEqual(local.stdout, (ROOT / ".mise.toml").read_text())
        self.assertEqual(tomllib.loads(local.stdout), {"settings": {"locked": True, "lockfile": True}})
        workflow = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertLess(workflow.index('_scripts/mise-policy "$GITHUB_WORKSPACE" ci'),
                        workflow.index("uses: jdx/mise-action@"))
        self.assertIn('printf \'%s\\n\' "$policy" >> "$GITHUB_ENV"', workflow)
        self.assertNotIn("MISE_GLOBAL_CONFIG_FILE:", workflow)

    def test_persistent_trust_uses_the_same_roots_as_managed_calls(self):
        result = self.invoke("trust")
        self.assertEqual(result.returncode, 0, result.stderr)
        persistent = tomllib.loads(result.stdout)["settings"]["trusted_config_paths"]
        self.assertEqual(self.invoke("run", "install").returncode, 0)
        self.assertEqual(persistent, self.calls()[-1]["trust"].split(":"))

    def test_unrepresentable_paths_fail_before_any_output_or_command(self):
        for workspace in ("relative", "/unsafe:path", "/unsafe\npath"):
            result = self.invoke("ci", WORKSPACE=workspace)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
        self.assertFalse(self.trace.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
