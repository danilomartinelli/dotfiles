"""Behavioral fixtures: real subprocess adapters, isolated files, no network."""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
LOADER = importlib.machinery.SourceFileLoader(
    "upgrades", str(ROOT / "_scripts/upgrade-software")
)
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
upgrades = importlib.util.module_from_spec(SPEC)
sys.modules[LOADER.name] = upgrades
LOADER.exec_module(upgrades)
EXTRAS_SPEC = importlib.util.spec_from_file_location(
    "mise_extras", ROOT / "mise/_extras.py"
)
extras = importlib.util.module_from_spec(EXTRAS_SPEC)
EXTRAS_SPEC.loader.exec_module(extras)

MANAGER = r"""
import json, os, pathlib, sys, tomllib
command = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["EVENTS"], "a") as log:
    log.write(json.dumps([command, *args]) + "\n")
if command == "brew":
    if args[0] == "outdated":
        kind = "formulae" if "--formula" in args else "casks"
        name = "git" if kind == "formulae" else "example"
        if os.environ.get("OUTSIDER"): name = "undeclared"
        if os.environ.get("DRIFT"):
            with open(os.environ["EVENTS"]) as log:
                queries = [line for line in log if json.loads(line)[:2] == ["brew", "outdated"]]
            if len(queries) > 2:
                print(json.dumps({kind: []}))
                sys.exit(0)
        print(json.dumps({kind: [{"name": name, "installed_versions": ["1.0.0"],
             "current_version": "2.0.0", "pinned": bool(os.environ.get("PINNED"))}]}))
        sys.exit(1)
    elif args[0] == "vulns":
        if os.environ.get("AUDIT_FAILURE"):
            print("scanner unavailable", file=sys.stderr)
            sys.exit(2)
        print(json.dumps({"findings": [{"formula": "git", "version": "1.0.0",
              "vulnerabilities": [{"id": "GHSA-fixture"}]}], "skipped_formulae": ["private-source"]}))
        sys.exit(1)
elif command == "mas":
    if args[0] == "outdated":
        print("123 Example (1.0.0 -> 2.0.0)")
        print("999 Undeclared (1.0.0 -> 9.0.0)")
elif command == "fzf":
    if os.environ.get("FZF_DEFAULT_OPTS"): sys.exit(2)
    rows = sys.stdin.read().splitlines()
    if os.environ.get("CANCEL"): sys.exit(130)
    if os.environ.get("BAD_PICKER"):
        print("999\tunknown")
    else:
        for index in os.environ.get("PICK", "0").split(","): print(rows[int(index)])
elif command == "mise":
    config = pathlib.Path(os.environ["MISE_GLOBAL_CONFIG_FILE"])
    tools = tomllib.loads(config.read_text())["tools"]
    lock = config.parent / "mise.lock"
    entries = tomllib.loads(lock.read_text())["tools"]
    if args[0] == "outdated":
        result = {}
        for name in tools:
            if name not in args or name == "npm:kept": continue
            version = tools[name]
            version = version["version"] if isinstance(version, dict) else version
            latest = "24.1.0" if name == "node" else "2.0.0"
            if name == "node" and "--bump" in args: latest = "26.0.0"
            result[name] = {"requested": version, "current": entries[name][-1]["version"], "latest": latest}
        print(json.dumps(result))
    elif args[0] == "ls":
        print(json.dumps([{"version": entries[args[-1]][-1]["version"], "active": True}]))
    elif args[0] == "lock":
        if os.environ.get("FAIL_LOCK"): sys.exit(1)
        for name in args[2:]:
            value = tools[name]
            version = value.get("version") if isinstance(value, dict) else value
            if version in ("lts", "4.0"): version = entries[name][-1]["version"]
            options = {k: v for k, v in value.items() if k != "version"} if isinstance(value, dict) else {}
            if name == "ruby": options = {"compile": "false", "precompiled_url": "jdx/ruby"}
            entries[name] = [e for e in entries[name] if e.get("options", {}) != options]
            entries[name].append({"version": version, "options": options})
        if os.environ.get("LOCK_DRIFT"): entries["npm:kept"][0]["version"] = "9.0.0"
        with lock.open("w") as out:
            for name, versions in entries.items():
                for entry in versions:
                    out.write(f"[[tools.{json.dumps(name)}]]\nversion = {json.dumps(entry['version'])}\n")
                    if entry.get("options"):
                        out.write(f"[tools.{json.dumps(name)}.options]\n")
                        for k, v in entry["options"].items(): out.write(f"{k} = {json.dumps(v)}\n")
    elif args[0] == "install":
        if os.environ.get("FAIL_INSTALL"): sys.exit(1)
        if os.environ.get("CONCURRENT_EDIT"):
            pathlib.Path(os.environ["CONCURRENT_EDIT"]).write_text("concurrent user edit\n")
"""


class UpgradesTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-upgrade-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("mise", "_scripts", "fake-bin", "home"):
            (self.root / name).mkdir()
        self.env = {
            **os.environ,
            "HOME": str(self.root / "home"),
            "EVENTS": str(self.root / "events"),
            "PATH": f"{self.root / 'fake-bin'}:/usr/bin:/bin",
            "HOMEBREW_NO_AUTO_UPDATE": "1",
        }
        self.brew = str(self.root / "fake-bin/brew")
        for command in ("brew", "mise", "mas", "fzf"):
            self.executable(self.root / "fake-bin" / command, MANAGER)
        self.executable(
            self.root / "fake-bin/sudo",
            "import os, sys\nos.execv(sys.argv[1], sys.argv[1:])",
        )
        self.executable(
            self.root / "_scripts/render-software-catalog",
            'import pathlib, sys\n(pathlib.Path(sys.argv[1]) / "README.md").write_text("rendered\\n")',
        )
        self.executable(self.root / "mise/install.sh", 'print("agent repairs")')
        (self.root / "Brewfile").write_text(
            "brew 'git'\ncask 'example'\nmas 'Example', id: 123 # Example\n"
        )
        (self.root / "README.md").write_text("original\n")
        (self.root / "mise/config.toml").write_text(
            '[tools]\nnode = "lts" # LTS\n'
            '"npm:sample" = { version = "1.0.0", npm_args = "--ignore-scripts=false" } # CLI\n'
            '"npm:kept" = "1.0.0" # Unselected\n[settings]\nlockfile = true\n'
        )
        (self.root / "mise/mise.lock").write_text(
            '[[tools.node]]\nversion = "24.0.0"\n'
            '[[tools."npm:sample"]]\nversion = "1.0.0"\n'
            '[tools."npm:sample".options]\nnpm_args = "--ignore-scripts=false"\n'
            '[[tools."npm:kept"]]\nversion = "1.0.0"\n'
        )
        self.before = self.sources()

    def executable(self, path, body):
        path.write_text(f"#!{sys.executable}\n" + body)
        path.chmod(0o755)

    def sources(self):
        return {
            name: (self.root / name).read_bytes()
            for name in ("mise/config.toml", "mise/mise.lock", "README.md")
        }

    def events(self):
        path = self.root / "events"
        return (
            [json.loads(line) for line in path.read_text().splitlines()]
            if path.exists()
            else []
        )

    def osv(self, request, **kwargs):
        queries = json.loads(request.data)["queries"]
        self.assertTrue(all(q["package"]["ecosystem"] == "npm" for q in queries))
        return io.BytesIO(json.dumps({"results": [{} for _ in queries]}).encode())

    def invoke(self, interactive=False, answer="no", **overrides):
        output, errors = io.StringIO(), io.StringIO()
        with (
            patch.dict(os.environ, {**self.env, **overrides}, clear=True),
            patch.object(
                upgrades, "__file__", str(self.root / "_scripts/upgrade-software")
            ),
            patch.object(sys, "argv", ["upgrade-software", "--brew", self.brew]),
            patch.object(sys.stdin, "isatty", return_value=interactive),
            patch.object(output, "isatty", return_value=interactive),
            patch("builtins.input", return_value=answer),
            patch.object(upgrades.urllib.request, "urlopen", side_effect=self.osv),
            contextlib.redirect_stdout(output),
            contextlib.redirect_stderr(errors),
        ):
            status = upgrades.main()
        return status, output.getvalue(), errors.getvalue()

    def test_noninteractive_reports_without_installs_or_source_changes(self):
        status, output, errors = self.invoke()
        self.assertEqual(0, status)
        self.assertIn("Non-interactive run", output)
        self.assertIn("GHSA-fixture", output)
        self.assertIn("private-source", output)
        self.assertEqual(self.before, self.sources())
        self.assertFalse(
            any(e[1] in ("upgrade", "install", "lock") for e in self.events())
        )
        self.assertIn(["mas", "outdated", "--inaccurate", "123"], self.events())
        self.assertFalse(any("999" in e for e in self.events()))
        # Discovery names the Brewfile's own declarations; Homebrew never
        # evaluates the file to list them.
        self.assertIn(
            ["brew", "outdated", "--json=v2", "--formula", "git"], self.events()
        )
        self.assertFalse(any(e[:2] == ["brew", "bundle"] for e in self.events()))

    def test_a_rejected_brewfile_line_leaves_mise_discovery_available(self):
        with (self.root / "Brewfile").open("a") as stream:
            stream.write("brew 'git', args: ['HEAD']\n")
        status, output, errors = self.invoke()
        self.assertEqual(0, status)
        self.assertIn("Homebrew update discovery unavailable", errors)
        self.assertIn("App Store update discovery unavailable", errors)
        self.assertIn("Brewfile:4: ", errors)
        self.assertIn("node  24.0.0 -> 24.1.0", output)
        self.assertFalse(
            any(e[0] in ("brew", "mas") and e[1] == "outdated" for e in self.events())
        )

    def test_cancel_and_default_no_do_not_mutate(self):
        for overrides in ({"CANCEL": "1"}, {}):
            self.invoke(interactive=True, **overrides)
        self.assertEqual(self.before, self.sources())
        self.assertFalse(
            any(e[1] in ("upgrade", "install", "lock") for e in self.events())
        )

    def test_selected_brew_only_and_audit_failure_is_advisory(self):
        _, output, errors = self.invoke(
            interactive=True,
            answer="yes",
            PICK="0",
            AUDIT_FAILURE="1",
            FZF_DEFAULT_OPTS="--query=untrusted",
        )
        mutations = [e for e in self.events() if e[1] in ("upgrade", "install", "lock")]
        self.assertEqual([["brew", "upgrade", "--formula", "git"]], mutations)
        self.assertIn("coverage unavailable", errors)
        self.assertIn("Selected upgrades completed", output)

    def test_discovery_preserves_lts_and_bumps_exact_pins(self):
        candidates = upgrades.Mise(self.root, self.env).discover()
        self.assertIn(
            upgrades.Candidate("mise", "node", "24.0.0", "24.1.0"), candidates
        )
        self.assertIn(["mise", "outdated", "--json", "node"], self.events())
        self.assertIn(
            ["mise", "outdated", "--json", "--bump", "npm:sample", "npm:kept"],
            self.events(),
        )

    def test_selected_app_store_upgrade_only_targets_its_declared_id(self):
        with patch.object(upgrades.os, "geteuid", return_value=501):
            self.invoke(interactive=True, answer="yes", PICK="2")
        mutations = [e for e in self.events() if e[1] in ("upgrade", "install", "lock")]
        self.assertEqual([["mas", "upgrade", "--inaccurate", "123"]], mutations)

    def test_selected_mise_persists_only_approved_versions_and_keeps_options(self):
        selected = [
            upgrades.Candidate("mise", "node", "24.0.0", "24.1.0"),
            upgrades.Candidate("mise", "npm:sample", "1.0.0", "2.0.0"),
        ]
        upgrades.Mise(self.root, self.env).apply(selected)
        config = upgrades.read_toml(self.root / "mise/config.toml")
        self.assertEqual("lts", config["tools"]["node"])
        self.assertEqual(
            {"version": "2.0.0", "npm_args": "--ignore-scripts=false"},
            config["tools"]["npm:sample"],
        )
        self.assertEqual("1.0.0", config["tools"]["npm:kept"])
        self.assertIn("# CLI", (self.root / "mise/config.toml").read_text())
        self.assertEqual(
            "24.1.0",
            upgrades.read_toml(self.root / "mise/mise.lock")["tools"]["node"][0][
                "version"
            ],
        )
        self.assertEqual("rendered\n", (self.root / "README.md").read_text())
        self.assertIn(
            ["mise", "install", "--locked", "node", "npm:sample"], self.events()
        )

    def test_install_failure_or_unselected_lock_drift_preserves_source(self):
        selected = [upgrades.Candidate("mise", "npm:sample", "1.0.0", "2.0.0")]
        for failure in ("FAIL_LOCK", "FAIL_INSTALL", "LOCK_DRIFT"):
            with self.assertRaises((RuntimeError, ValueError)):
                upgrades.Mise(self.root, {**self.env, failure: "1"}).apply(selected)
            self.assertEqual(self.before, self.sources())

    def test_ruby_backend_defaults_do_not_freeze_its_macos_resolution(self):
        config = self.root / "mise/config.toml"
        config.write_text(
            config.read_text().replace("[settings]", 'ruby = "4.0"\n[settings]')
        )
        lock = self.root / "mise/mise.lock"
        lock.write_text(
            lock.read_text() + '[[tools.ruby]]\nversion = "4.0.7"\n'
            '[[tools.ruby]]\nversion = "4.0.7"\n'
            '[tools.ruby.options]\ncompile = "false"\nprecompiled_url = "jdx/ruby"\n'
        )
        upgrades.Mise(self.root, self.env).apply(
            [upgrades.Candidate("mise", "ruby", "4.0.7", "4.0.8")]
        )
        self.assertEqual(
            "4.0.8", upgrades.read_toml(lock)["tools"]["ruby"][-1]["version"]
        )
        self.assertEqual("4.0", upgrades.read_toml(config)["tools"]["ruby"])

    def test_concurrent_source_edit_is_preserved(self):
        # The fake install edits the checkout's README while the staged
        # upgrade is still unpublished.
        env = {**self.env, "CONCURRENT_EDIT": str(self.root / "README.md")}
        with self.assertRaises(RuntimeError):
            upgrades.Mise(self.root, env).apply(
                [upgrades.Candidate("mise", "node", "24.0.0", "24.1.0")]
            )
        self.assertEqual(
            "concurrent user edit\n", (self.root / "README.md").read_text()
        )
        self.assertEqual(
            self.before["mise/config.toml"],
            (self.root / "mise/config.toml").read_bytes(),
        )

    def test_pins_and_unknown_candidates_are_never_applied(self):
        self.assertEqual(
            [],
            upgrades.Homebrew(
                self.root, self.brew, {**self.env, "PINNED": "1"}
            ).discover(),
        )
        with self.assertRaises(ValueError):
            upgrades.Homebrew(
                self.root, self.brew, {**self.env, "OUTSIDER": "1"}
            ).discover()
        with self.assertRaises(ValueError):
            self.invoke(interactive=True, answer="yes", BAD_PICKER="1")

    def test_changed_candidates_abort_before_any_install(self):
        # The fake Homebrew reports no outdated formula on the requery.
        with self.assertRaises(RuntimeError):
            self.invoke(interactive=True, answer="yes", DRIFT="1")
        self.assertFalse(
            any(e[1] in ("upgrade", "install", "lock") for e in self.events())
        )

    def test_managers_apply_mise_first_then_homebrew_then_app_store(self):
        # Selected as App Store, Mise, Homebrew; applied in manager order.
        self.invoke(interactive=True, answer="yes", PICK="2,3,0")
        mutations = [
            e[:2] for e in self.events() if e[1] in ("upgrade", "install", "lock")
        ]
        self.assertEqual(
            [
                ["mise", "lock"],
                ["mise", "lock"],
                ["mise", "install"],
                ["brew", "upgrade"],
                ["mas", "upgrade"],
            ],
            mutations,
        )


class FormatterExtrasTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-formatter-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "bin").mkdir()
        self.config = self.root / "config.toml"
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
        installer.write_text(
            f"#!{sys.executable}\n"
            + """
import json, os, sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
(root / "install-args.json").write_text(json.dumps(sys.argv[1:]))
if os.environ.get("FAIL_EXTRA_INSTALL"): sys.exit(1)
(root / "versions.json").write_text(os.environ["DESIRED_EXTRAS"])
"""
        )
        installer.chmod(0o755)
        self.environment = patch.dict(
            os.environ,
            {
                "PATH": str(self.root / "bin") + ":/usr/bin:/bin",
                "DESIRED_EXTRAS": json.dumps(self.desired),
            },
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_existing_formatter_refreshes_only_when_pinned_plugins_differ(self):
        extras.reconcile(self.config, self.root)
        self.assertEqual(self.desired, json.loads(self.versions.read_text()))
        marker = self.root / "install-args.json"
        self.assertEqual(
            ["install", "--force", "--locked", "pipx:mdformat"],
            json.loads(marker.read_text()),
        )
        marker.unlink()
        extras.reconcile(self.config, self.root)
        self.assertFalse(marker.exists())

    def test_an_unpinned_plugin_fails_before_anything_is_installed(self):
        self.config.write_text(self.config.read_text().replace("==1.0.0", ""))
        with self.assertRaisesRegex(ValueError, "exact == version"):
            extras.reconcile(self.config, self.root)
        self.assertFalse((self.root / "install-args.json").exists())

    def test_failed_refresh_does_not_claim_matching_versions(self):
        with (
            patch.dict(os.environ, {"FAIL_EXTRA_INSTALL": "1"}),
            self.assertRaises(extras.subprocess.CalledProcessError),
        ):
            extras.reconcile(self.config, self.root)
        self.assertNotEqual(self.desired, json.loads(self.versions.read_text()))


if __name__ == "__main__":
    unittest.main()
