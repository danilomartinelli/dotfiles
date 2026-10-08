"""One isolated CLI smoke: real adapters, policy, rendering, and installer."""

import errno
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[2]


class UpgradeSmokeTest(unittest.TestCase):
    def test_confirmed_selection_runs_through_the_production_composition(self):
        with tempfile.TemporaryDirectory(prefix="dotfiles-upgrade-smoke-") as temporary:
            root = Path(temporary).resolve()
            for directory in ("_scripts", "mise", "bin", "home"):
                (root / directory).mkdir()
            for name in (
                "upgrade-software", "upgrade_adapters.py", "source_staging.py",
                "declared_software.py", "mise-policy", "trusted-roots",
                "render-software-catalog", "markdown-table.sh", "generated-region.sh",
                "installer-preamble.sh", "installer-output.sh",
                "catalog.sh", "link-config",
            ):
                shutil.copy2(ROOT / "_scripts" / name, root / "_scripts" / name)
            for name in ("install.sh", "_configure-trust.sh", "_post-install.sh"):
                shutil.copy2(ROOT / "mise" / name, root / "mise" / name)
            (root / "Brewfile").write_text("brew 'git' # Git\nmas 'Example', id: 123 # Example\n")
            (root / "mise/config.toml").write_text('[tools]\nnode = "lts" # Node\n[settings]\nlockfile = true\n')
            (root / "mise/mise.lock").write_text('[[tools.node]]\nversion = "24.0.0"\n')
            (root / "README.md").write_text("Smoke catalog\n\n" + "\n\n".join(
                f"<!-- generated: {name} -->\n\nold\n\n<!-- generated-end -->"
                for name in ("homebrew-formulae", "homebrew-casks", "mac-app-store", "mise-tools")
            ) + "\n")
            prefix = '''import json, os, pathlib, sys
assert os.environ["HOMEBREW_NO_AUTO_UPDATE"] == "1"
assert os.environ["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == "1"
with open(os.environ["EVENTS"], "a") as log:
    log.write(json.dumps([pathlib.Path(sys.argv[0]).name, *sys.argv[1:]]) + "\\n")
'''
            scripts = {
                "brew": '''
if sys.argv[1] == "outdated":
    print('{"formulae": [{"name": "git", "installed_versions": ["1.0.0"], "current_version": "2.0.0"}]}')
    sys.exit(1)
if sys.argv[1] == "vulns":
    print('{"findings": [], "skipped_formulae": []}')
''',
                "mas": '''
if sys.argv[1] == "outdated":
    print("123 Example (1.0.0 -> 2.0.0)")
''',
                "fzf": '''
assert not os.environ.get("FZF_DEFAULT_OPTS")
assert not os.environ.get("FZF_DEFAULT_OPTS_FILE")
print(sys.stdin.read(), end="")
''',
                "sudo": "os.execv(sys.argv[1], sys.argv[1:])\n",
            }
            for name, body in scripts.items():
                path = root / "bin" / name
                path.write_text(f"#!{sys.executable}\n" + prefix + body)
                path.chmod(0o755)
            mise = root / "bin/mise"
            mise.write_text(f"#!{sys.executable}\n" + (ROOT / "tests/_support/mise.py").read_text())
            mise.chmod(0o755)
            (root / "bin/python3").symlink_to(sys.executable)
            env = {
                "HOME": str(root / "home"), "WORKSPACE": str(root / "home/Workspace"),
                "PATH": f"{root / 'bin'}:/usr/bin:/bin", "EVENTS": str(root / "events"),
                "TERM": "xterm", "FZF_DEFAULT_OPTS": "--query=untrusted",
                "FZF_DEFAULT_OPTS_FILE": "/must-not-read", "PYTHONDONTWRITEBYTECODE": "1",
            }
            master, slave = pty.openpty()
            output = bytearray()
            try:
                with subprocess.Popen(
                    [sys.executable, "-B", str(root / "_scripts/upgrade-software"), "--brew", str(root / "bin/brew")],
                    cwd=root, env=env, stdin=slave, stdout=slave, stderr=slave,
                ) as process:
                    os.close(slave)
                    slave = None
                    os.write(master, b"yes\n")
                    deadline = time.monotonic() + 30
                    try:
                        while True:
                            if time.monotonic() > deadline:
                                self.fail("upgrade smoke timed out: " + output.decode(errors="replace"))
                            if select.select([master], [], [], 0.1)[0]:
                                try:
                                    chunk = os.read(master, 65536)
                                except OSError as error:
                                    if error.errno == errno.EIO:
                                        break
                                    raise
                                if not chunk:
                                    break
                                output.extend(chunk)
                            elif process.poll() is not None:
                                break
                        status = process.wait(timeout=2)
                    finally:
                        if process.poll() is None:
                            process.kill()
                self.assertEqual(0, status, output.decode(errors="replace"))
            finally:
                os.close(master)
                if slave is not None:
                    os.close(slave)
            self.assertIn(b"Selected upgrades completed", output)
            self.assertIn(b"Apply selected upgrades? [y/N]", output)
            lock = tomllib.loads((root / "mise/mise.lock").read_text())
            self.assertEqual("24.1.0", lock["tools"]["node"][0]["version"])
            self.assertIn('node = "lts"', (root / "mise/config.toml").read_text())
            self.assertIn("`node`", (root / "README.md").read_text())
            self.assertEqual(root / "mise/mise.lock", (root / "home/.config/mise/mise.lock").resolve())
            events = [json.loads(line) for line in (root / "events").read_text().splitlines()]
            self.assertEqual([
                ["mise", "lock", "--global", "node"],
                ["mise", "lock", "--global", "node"],
                ["mise", "install", "node"], ["mise", "install"],
                ["brew", "upgrade", "--formula", "git"],
                ["mas", "upgrade", "--inaccurate", "123"],
            ], [event for event in events if event[0] != "sudo" and event[1] in ("lock", "install", "upgrade")])


if __name__ == "__main__":
    unittest.main()
