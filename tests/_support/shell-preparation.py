"""Tool context observed through real Zsh startup and the shared Mise fake."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ShellPreparationTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="dotfiles-shell-preparation-")
        self.addCleanup(temporary.cleanup)
        self.fixture = Path(temporary.name)
        self.checkout = self.fixture / "checkout with spaces"
        for name in ("_scripts", "zsh", "mise", "android-studio", "pnpm", "homebrew", "functions", "bin"):
            (self.checkout / name).mkdir(parents=True)
        for name in (
            "_scripts/topic-catalog", "_scripts/mise-policy", "_scripts/trusted-roots",
            "zsh/zshrc.symlink", "zsh/_startup.zsh", "mise/mise.zsh",
            "mise/completion.zsh", "android-studio/env.zsh", "pnpm/path.zsh",
        ):
            shutil.copy2(ROOT / name, self.checkout / name)
        (self.checkout / "zsh/prompt.zsh").write_text(":\n")
        (self.checkout / "functions/compinit").write_text("compdef() { :; }\n")
        availability = self.checkout / "homebrew/_availability.sh"
        availability.write_text('#!/bin/sh\nprintf "%s\\n" "$FIXTURE_PREFIX"\n')
        availability.chmod(0o755)
        self.home = self.fixture / "home"
        self.home.mkdir()
        (self.home / ".zshrc").symlink_to(self.checkout / "zsh/zshrc.symlink")
        prefix = self.fixture / "prefix"
        (prefix / "bin").mkdir(parents=True)
        fake = prefix / "bin/mise"
        fake.write_text(f"#!{sys.executable}\n" + (ROOT / "tests/_support/mise.py").read_text())
        fake.chmod(0o755)
        self.trace = self.fixture / "trace.jsonl"
        self.env = {
            "HOME": str(self.home), "PATH": f"{prefix}/bin:/usr/bin:/bin",
            "FIXTURE_PREFIX": str(prefix), "FAKE_MISE_TRACE": str(self.trace),
            "FAKE_MISE_JAVA_HOME": str(self.fixture / "java"),
        }

    def shell(self, program, **overrides):
        result = subprocess.run(
            ["/bin/zsh", "-f", "-c", 'setopt extended_glob; source "$HOME/.zshrc"; ' + program],
            env={**self.env, **overrides}, text=True, capture_output=True,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        return result

    def events(self):
        return [json.loads(line) for line in self.trace.read_text().splitlines()] if self.trace.exists() else []

    def test_java_uses_the_prepared_context_instead_of_the_legacy_selector(self):
        result = self.shell(
            'printf "%s\\n" "$JAVA_HOME" "${MISE_GLOBAL_CONFIG_FILE-unset}"',
            MISE_GLOBAL_CONFIG_FILE=str(self.home / ".config/mise/config.toml"),
        )
        self.assertEqual([self.env["FAKE_MISE_JAVA_HOME"], "unset"], result.stdout.splitlines())
        self.assertEqual("", result.stderr)
        lookup = next(event for event in self.events() if event["args"] == ["where", "java"])
        self.assertIsNone(lookup["config"], "Java must use the normalized shell context")
        self.assertIn(str(self.home / "Workspace"), lookup["trust"].split(":"))

    def test_failed_activation_preserves_java_and_skips_dependent_lookups(self):
        legacy = str(self.home / ".config/mise/config.toml")
        result = self.shell(
            'printf "%s\\n" "$JAVA_HOME" "$MISE_GLOBAL_CONFIG_FILE" '
            '"$MISE_TRUSTED_CONFIG_PATHS" "${FAKE_MISE_ACTIVATED-unset}"',
            FAIL_MISE_ACTIVATE="1", JAVA_HOME="/previous/java",
            MISE_GLOBAL_CONFIG_FILE=legacy, MISE_TRUSTED_CONFIG_PATHS="/previous/trust",
        )
        self.assertEqual(["/previous/java", legacy, "/previous/trust", "unset"], result.stdout.splitlines())
        self.assertIn("activation failed", result.stderr)
        self.assertEqual([["activate", "zsh"]], [event["args"] for event in self.events()])

    def test_managed_commands_keep_precedence_after_activation_and_reload(self):
        tools = self.fixture / "runtime tools"
        tools.mkdir()
        for directory, word in ((tools, "foreign"), (self.checkout / "bin", "managed")):
            command = directory / "dot"
            command.write_text(f"#!/bin/sh\nprintf '%s\\n' {word}\n")
            command.chmod(0o755)
        result = self.shell(
            'dot; first_path=$PATH; source "$HOME/.zshrc"; dot; '
            '[[ $PATH == "$first_path" ]] || exit 1',
            FAKE_MISE_ACTIVATION_PATH=str(tools),
        )
        self.assertEqual(["managed", "managed"], result.stdout.splitlines())
        self.assertEqual("", result.stderr)

    def test_java_preserves_the_personal_selector_and_workspace(self):
        personal = str(self.fixture / "personal/config.toml")
        workspace = str(self.fixture / "personal workspace")
        result = self.shell('printf "%s\\n" "$JAVA_HOME" "$MISE_GLOBAL_CONFIG_FILE"',
                            MISE_GLOBAL_CONFIG_FILE=personal, WORKSPACE=workspace)
        self.assertEqual([self.env["FAKE_MISE_JAVA_HOME"], personal], result.stdout.splitlines())
        self.assertEqual("", result.stderr)
        lookup = next(event for event in self.events() if event["args"] == ["where", "java"])
        self.assertEqual(personal, lookup["config"])
        self.assertIn(workspace, lookup["trust"].split(":"))
        self.assertEqual(1, sum(event["args"] == ["activate", "zsh"] for event in self.events()))

    def test_failed_preparation_preserves_the_previous_java_environment(self):
        result = self.shell('printf "%s\\n" "$JAVA_HOME" "$MISE_TRUSTED_CONFIG_PATHS"',
                            WORKSPACE="/unrepresentable:path", JAVA_HOME="/previous/java",
                            MISE_TRUSTED_CONFIG_PATHS="/previous/trust")
        self.assertEqual(["/previous/java", "/previous/trust"], result.stdout.splitlines())
        self.assertIn("paths must not contain", result.stderr)
        self.assertEqual([], self.events())


if __name__ == "__main__":
    unittest.main()
