"""Post-install reconciliation through its executable, with isolated packages."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]

# These command adapters keep real link/copy/mode effects inside the fixture.
# The native payload is textual so the file probe needs no host architecture.
REPAIR_COMMAND = '''import json
import os
from pathlib import Path
import subprocess
import sys

command = Path(sys.argv[0]).name
with open(os.environ["EVENTS"], "a") as stream:
    stream.write(json.dumps([command, *sys.argv[1:]]) + "\\n")
status = int(os.environ.get("FAIL_" + command.upper(), "0"))
if command == "node":
    print("package installer output")
    print("package installer diagnostic", file=sys.stderr)
    sys.exit(status)
if status:
    print("fixture " + command + " failure", file=sys.stderr)
    sys.exit(status)
if command == "file":
    payload = Path(sys.argv[1]).read_text()
    print("Mach-O 64-bit executable arm64" if payload == "native payload\\n" else "ASCII text")
else:
    sys.exit(subprocess.run(["/bin/" + command, *sys.argv[1:]]).returncode)
'''


class PostInstallTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-post-install-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.checkout = self.root / "fixture checkout"
        for name in ("_scripts", "mise"):
            (self.checkout / name).mkdir(parents=True)
        for name in ("mise-policy", "trusted-roots", "installer-output.sh",
                     "declared_software.py"):
            shutil.copy2(ROOT / "_scripts" / name, self.checkout / "_scripts")
        for name in ("_post-install.sh", "_extras.py"):
            shutil.copy2(ROOT / "mise" / name, self.checkout / "mise")
        (self.checkout / "mise/config.toml").write_text(
            '[tools]\npython = "1.0.0"\n'
            '"pipx:mdformat" = { version = "1.0.0", '
            'uvx_args = "--with mdformat-gfm==1.0.0" }\n'
        )
        self.lock = self.checkout / "mise/mise.lock"
        self.lock.write_text('[[tools.python]]\nversion = "1.0.0"\n'
                             '[[tools."pipx:mdformat"]]\nversion = "1.0.0"\n')
        self.original_lock = self.lock.read_bytes()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.root / "home").mkdir()
        self.write_executable(self.bin / "mise", (ROOT / "tests/_support/mise.py").read_text())
        self.events = self.root / "events.jsonl"
        self.trace = self.root / "trace.jsonl"
        self.environment = {
            "HOME": str(self.root / "home"),
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "EVENTS": str(self.events),
            "FAKE_MISE_TRACE": str(self.trace),
            "DOTFILES_ROOT": "/unrelated-checkout",
        }
        for command in ("node", "file", "ln", "cp", "chmod"):
            self.write_executable(self.bin / command, REPAIR_COMMAND)

    def write_executable(self, path, program):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"#!{sys.executable}\n" + program)
        path.chmod(0o755)

    def invoke(self, **overrides):
        self.events.write_text("")
        self.trace.write_text("")
        return subprocess.run(
            ["/bin/sh", str(self.checkout / "mise/_post-install.sh")],
            cwd=self.root, env={**self.environment, **overrides},
            capture_output=True, text=True,
        )

    def commands(self):
        return [json.loads(line) for line in self.events.read_text().splitlines()]

    def claude_package(self):
        directory = self.root / "claude package"
        script = directory / "lib/node_modules/@anthropic-ai/claude-code/install.cjs"
        script.parent.mkdir(parents=True)
        script.write_text("fixture package installer\n")
        self.environment["FAKE_MISE_CLAUDE_HOME"] = str(directory)
        return script

    def opencode_package(self):
        directory = self.root / "opencode package"
        stub = directory / "lib/node_modules/opencode-ai/bin/opencode.exe"
        native = directory / "lib/node_modules/opencode-darwin-arm64/bin/opencode"
        for path, payload in ((stub, "stub payload\n"), (native, "native payload\n")):
            path.parent.mkdir(parents=True)
            path.write_text(payload)
            path.chmod(0o644)
        self.environment["FAKE_MISE_OPENCODE_HOME"] = str(directory)
        return stub, native

    def formatter_package(self, versions):
        directory = self.root / "formatter package"
        environment = directory / "venv/bin"
        environment.mkdir(parents=True)
        (environment / "mdformat").write_text("fixture formatter\n")
        (directory / "bin").mkdir()
        (directory / "bin/mdformat").symlink_to(environment / "mdformat")
        self.versions = directory / "versions.json"
        self.versions.write_text(json.dumps(versions))
        self.write_executable(environment / "python", '''import os
from pathlib import Path
import sys
status = int(os.environ.get("FAIL_PYTHON_INSPECTION", "0"))
if status:
    sys.exit(status)
print((Path(__file__).resolve().parents[2] / "versions.json").read_text())
''')
        (self.bin / "python3").symlink_to(sys.executable)
        self.environment.update({
            "FAKE_MISE_MDFORMAT_HOME": str(directory),
            "FAKE_MISE_EXTRAS_FILE": str(self.versions),
            "FAKE_MISE_EXTRAS": '{"mdformat-gfm": "1.0.0"}',
        })

    def test_absent_packages_skip_repairs_without_installing_or_linking(self):
        result = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual([
            ["mise", "where", "pipx:mdformat"],
            ["mise", "prune", "--yes"],
            ["mise", "where", "npm:@anthropic-ai/claude-code"],
            ["mise", "where", "npm:opencode-ai"],
        ], self.commands())
        self.assertEqual("", result.stdout + result.stderr)
        self.assertFalse((self.root / "home/.config").exists())
        self.assertEqual(self.original_lock, self.lock.read_bytes())
        for line in self.trace.read_text().splitlines():
            call = json.loads(line)
            self.assertTrue(call["locked"])
            self.assertEqual(str(self.checkout / "mise/config.toml"), call["config"])
            self.assertEqual(str(self.checkout), call["cwd"])

    def test_formatter_refresh_precedes_prune_and_agent_repairs(self):
        self.formatter_package({"mdformat-gfm": "0.4.1"})
        script = self.claude_package()
        stub, native = self.opencode_package()
        result = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual({"mdformat-gfm": "1.0.0"}, json.loads(self.versions.read_text()))
        commands = self.commands()
        self.assertLess(commands.index(["mise", "install", "--force", "pipx:mdformat"]),
                        commands.index(["mise", "prune", "--yes"]))
        self.assertLess(commands.index(["mise", "prune", "--yes"]),
                        commands.index(["node", str(script)]))
        self.assertLess(commands.index(["node", str(script)]),
                        commands.index(["ln", "-f", str(native), str(stub)]))
        self.assertEqual(self.original_lock, self.lock.read_bytes())
        self.assertTrue(stub.samefile(native))
        self.assertEqual("", result.stderr)

    def test_matching_formatter_pins_need_no_refresh(self):
        self.formatter_package({"mdformat-gfm": "1.0.0"})
        result = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("extras match their declared pins", result.stdout)
        self.assertFalse(any(call[:2] == ["mise", "install"] for call in self.commands()))

    def test_formatter_failures_stop_before_prune_and_native_repairs(self):
        self.formatter_package({"mdformat-gfm": "0.4.1"})
        self.claude_package()
        stub, _ = self.opencode_package()
        cases = (
            ({"FAIL_PYTHON_INSPECTION": "7"}, "could not inspect"),
            ({"FAIL_MISE_INSTALL": "1"}, "Mise formatter reconciliation failed"),
            ({"FAKE_MISE_EXTRAS": '{"mdformat-gfm": "0.4.1"}'}, "still differ"),
        )
        for overrides, diagnostic in cases:
            with self.subTest(overrides=overrides):
                result = self.invoke(**overrides)
                self.assertEqual(1, result.returncode)
                self.assertIn(diagnostic, result.stderr)
                self.assertIn("Failed to reconcile Mise formatter plugins", result.stderr)
                self.assertNotIn(["mise", "prune", "--yes"], self.commands())
                self.assertFalse(any(call[0] == "node" for call in self.commands()))
                self.assertEqual("stub payload\n", stub.read_text())

    def test_prune_failure_still_allows_native_repairs(self):
        stub, native = self.opencode_package()
        result = self.invoke(FAIL_MISE_PRUNE="7")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("", result.stderr)
        self.assertTrue(stub.samefile(native))

    def test_lookup_errors_skip_present_packages(self):
        self.claude_package()
        stub, _ = self.opencode_package()
        result = self.invoke(FAIL_MISE_WHERE="7")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("", result.stdout + result.stderr)
        self.assertEqual("stub payload\n", stub.read_text())
        self.assertFalse(any(call[0] == "node" for call in self.commands()))

    def test_claude_package_installer_runs_again_and_hides_its_output(self):
        script = self.claude_package()
        for _ in range(2):
            result = self.invoke()
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn(["node", str(script)], self.commands())
            self.assertIn("claude native binary installed", result.stdout)
            self.assertNotIn("package installer output", result.stdout)
            self.assertEqual("", result.stderr)

    def test_missing_claude_installer_still_reaches_opencode(self):
        self.claude_package().unlink()
        stub, native = self.opencode_package()
        result = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(any(call[0] == "node" for call in self.commands()))
        self.assertTrue(stub.samefile(native))

    def test_claude_failure_warns_and_still_repairs_opencode(self):
        script = self.claude_package()
        stub, native = self.opencode_package()
        result = self.invoke(FAIL_NODE="7")
        self.assertEqual(0, result.returncode)
        self.assertIn(f"claude postinstall failed — run manually: node {script}", result.stderr)
        self.assertNotIn("package installer diagnostic", result.stderr)
        self.assertNotIn("claude native binary installed", result.stdout)
        self.assertTrue(stub.samefile(native))

    def test_opencode_repair_links_native_payload_and_skips_a_repeat(self):
        stub, native = self.opencode_package()
        result = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertTrue(stub.samefile(native))
        self.assertTrue(stub.stat().st_mode & 0o111)
        self.assertIn("opencode native binary installed", result.stdout)
        result = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(any(call[0] in ("ln", "cp", "chmod") for call in self.commands()))
        self.assertNotIn("opencode native binary installed", result.stdout)

    def test_opencode_copies_when_a_hard_link_fails(self):
        stub, native = self.opencode_package()
        result = self.invoke(FAIL_LN="7")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(stub.samefile(native))
        self.assertEqual(native.read_bytes(), stub.read_bytes())
        self.assertTrue(stub.stat().st_mode & 0o111)
        self.assertIn("opencode native binary installed", result.stdout)
        self.assertEqual("", result.stderr)

    def test_failed_link_and_copy_warn_without_claiming_success(self):
        stub, _ = self.opencode_package()
        result = self.invoke(FAIL_LN="7", FAIL_CP="8")
        self.assertEqual(0, result.returncode)
        self.assertIn("opencode binary fix failed — run: mise reinstall npm:opencode-ai", result.stderr)
        self.assertIn("fixture cp failure", result.stderr)
        self.assertNotIn("fixture ln failure", result.stderr)
        self.assertNotIn("opencode native binary installed", result.stdout)
        self.assertEqual("stub payload\n", stub.read_text())

    def test_failed_chmod_is_fatal_after_linking_or_copying(self):
        stub, native = self.opencode_package()
        for link_status in ("0", "7"):
            with self.subTest(link_status=link_status):
                stub.unlink()
                stub.write_text("stub payload\n")
                result = self.invoke(FAIL_LN=link_status, FAIL_CHMOD="9")
                self.assertEqual(9, result.returncode)
                self.assertEqual(native.read_bytes(), stub.read_bytes())
                self.assertIn("fixture chmod failure", result.stderr)
                self.assertNotIn("opencode native binary installed", result.stdout)

    def test_existing_native_destination_is_preserved_even_without_execute_permission(self):
        stub, native = self.opencode_package()
        stub.write_bytes(native.read_bytes())
        result = self.invoke()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(stub.samefile(native))
        self.assertFalse(stub.stat().st_mode & 0o111)
        self.assertFalse(any(call[0] in ("ln", "cp", "chmod") for call in self.commands()))

    def test_missing_opencode_file_skips_repair(self):
        stub, native = self.opencode_package()
        for missing in (stub, native):
            with self.subTest(missing=missing):
                contents = missing.read_bytes()
                missing.unlink()
                result = self.invoke()
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual("", result.stdout + result.stderr)
                self.assertFalse(any(call[0] in ("ln", "cp", "chmod") for call in self.commands()))
                self.assertFalse(missing.exists())
                missing.write_bytes(contents)

    def test_file_probe_failure_still_attempts_repair(self):
        stub, native = self.opencode_package()
        result = self.invoke(FAIL_FILE="7")
        self.assertEqual(0, result.returncode)
        self.assertIn("fixture file failure", result.stderr)
        self.assertIn("opencode native binary installed", result.stdout)
        self.assertTrue(stub.samefile(native))


if __name__ == "__main__":
    unittest.main()
