"""Formatter extras reconciliation against isolated Mise fixtures."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
EXTRAS_SPEC = importlib.util.spec_from_file_location(
    "mise_extras", ROOT / "mise/_extras.py"
)
extras = importlib.util.module_from_spec(EXTRAS_SPEC)
EXTRAS_SPEC.loader.exec_module(extras)


class FormatterExtrasTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-formatter-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("bin", "_scripts", "mise", "home"):
            (self.root / name).mkdir()
        for name in ("mise-policy", "trusted-roots"):
            shutil.copy2(ROOT / "_scripts" / name, self.root / "_scripts")
        (self.root / "mise/mise.lock").write_text('[[tools."pipx:mdformat"]]\nversion = "1.0.0"\n')
        self.config = self.root / "mise/config.toml"
        self.config.write_text(
            '[tools]\n"pipx:mdformat" = { version = "1.0.0", uvx_args = "--with mdformat-gfm==1.0.0 --with mdformat-frontmatter==2.1.2" }\n'
        )
        self.desired = {"mdformat-gfm": "1.0.0", "mdformat-frontmatter": "2.1.2"}
        self.versions = self.root / "versions.json"
        self.versions.write_text(
            json.dumps({"mdformat-gfm": "0.4.1", "mdformat-frontmatter": None})
        )
        environment = self.root / "mdformat/bin"
        environment.mkdir(parents=True)
        (environment / "mdformat").write_text("formatter entrypoint\n")
        (self.root / "bin/mdformat").symlink_to(environment / "mdformat")
        interpreter = environment / "python"
        interpreter.write_text(
            f"#!{sys.executable}\nfrom pathlib import Path\nprint((Path(__file__).resolve().parents[2] / 'versions.json').read_text())\n"
        )
        interpreter.chmod(0o755)
        installer = self.root / "bin/mise"
        installer.write_text(f"#!{sys.executable}\n" + (ROOT / "tests/_support/mise.py").read_text())
        installer.chmod(0o755)
        self.environment = patch.dict(
            os.environ,
            {
                "PATH": str(self.root / "bin") + ":/usr/bin:/bin",
                "HOME": str(self.root / "home"),
                "EVENTS": str(self.root / "install-args.json"),
                "FAKE_MISE_EXTRAS_FILE": str(self.versions),
                "FAKE_MISE_EXTRAS": json.dumps(self.desired),
            },
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_existing_formatter_refreshes_only_when_pinned_plugins_differ(self):
        extras.reconcile(self.root, self.root)
        self.assertEqual(self.desired, json.loads(self.versions.read_text()))
        marker = self.root / "install-args.json"
        self.assertEqual(
            ["mise", "install", "--force", "pipx:mdformat"],
            json.loads(marker.read_text()),
        )
        marker.unlink()
        extras.reconcile(self.root, self.root)
        self.assertFalse(marker.exists())

    def test_an_unpinned_plugin_fails_before_anything_is_installed(self):
        self.config.write_text(self.config.read_text().replace("==1.0.0", ""))
        with self.assertRaisesRegex(ValueError, "exact == version"):
            extras.reconcile(self.root, self.root)
        self.assertFalse((self.root / "install-args.json").exists())

    def test_failed_refresh_does_not_claim_matching_versions(self):
        with (
            patch.dict(os.environ, {"FAIL_MISE_INSTALL": "1"}),
            self.assertRaises(extras.subprocess.CalledProcessError),
        ):
            extras.reconcile(self.root, self.root)
        self.assertNotEqual(self.desired, json.loads(self.versions.read_text()))


if __name__ == "__main__":
    unittest.main()
