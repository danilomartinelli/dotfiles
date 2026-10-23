"""Controlled upgrade contracts using recorded replies and isolated files."""

import contextlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

from upgrade_recordings import Advisories, Commands, Interaction, Reply


ROOT = Path(__file__).resolve().parents[2]
LOADER = importlib.machinery.SourceFileLoader(
    "upgrades", str(ROOT / "_scripts/upgrade-software")
)
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
upgrades = importlib.util.module_from_spec(SPEC)
sys.modules[LOADER.name] = upgrades
LOADER.exec_module(upgrades)
CONFIG = ('[tools]\nnode = "lts" # LTS\n'
          '"npm:sample" = { version = "1.0.0", npm_args = "--ignore-scripts=false" } # CLI\n'
          '"npm:kept" = "1.0.0" # Unselected\n[settings]\nlockfile = true\n')
LOCK = ('[[tools.node]]\nversion = "24.0.0"\n'
        '[[tools."npm:sample"]]\nversion = "1.0.0"\n'
        '[tools."npm:sample".options]\nnpm_args = "--ignore-scripts=false"\n'
        '[[tools."npm:kept"]]\nversion = "1.0.0"\n')


class Manager:
    """An in-memory manager role; it knows no package-manager commands."""

    def __init__(self, label, candidates, events):
        self.label = label
        self.discoveries = [candidates]
        self.events = events
        self.error = None

    def discover(self):
        self.events.append(("discover", self.label))
        result = self.discoveries.pop(0) if len(self.discoveries) > 1 else self.discoveries[0]
        if isinstance(result, Exception):
            raise result
        return result

    def audit(self, candidates):
        return [f"{self.label} fixture coverage"]

    def apply(self, selected):
        self.events.append(("apply", self.label, selected))
        if self.error:
            raise self.error


class UpgradePolicyTest(unittest.TestCase):
    def setUp(self):
        self.events = []
        self.git = upgrades.Candidate("brew-formula", "git", "1.0.0", "2.0.0")
        self.app = upgrades.Candidate("mas", "123", "1.0.0", "2.0.0", "Example")
        self.node = upgrades.Candidate("mise", "node", "24.0.0", "24.1.0")
        self.homebrew = Manager("Homebrew", [self.git], self.events)
        self.app_store = Manager("App Store", [self.app], self.events)
        self.mise = Manager("Mise", [self.node], self.events)
        self.interaction = Interaction(interactive=True, selected=(2, 0, 1), answer="yes")

    def invoke(self):
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = upgrades.upgrade(self.homebrew, self.app_store, self.mise, {},
                                      interaction=self.interaction)
        return status, output.getvalue(), errors.getvalue()

    def test_requeries_every_selection_before_applying_mise_then_brew_then_app_store(self):
        status, output, errors = self.invoke()
        self.assertEqual(0, status)
        self.assertIn("Selected upgrades completed", output)
        self.assertFalse(errors)
        self.assertEqual([
            ("discover", "Homebrew"), ("discover", "App Store"), ("discover", "Mise"),
            ("discover", "Homebrew"), ("discover", "App Store"), ("discover", "Mise"),
            ("apply", "Mise", [self.node]), ("apply", "Homebrew", [self.git]),
            ("apply", "App Store", [self.app]),
        ], self.events)

    def test_unattended_execution_reports_without_selection_or_application(self):
        self.interaction.has_terminal = False
        status, output, errors = self.invoke()
        self.assertEqual(0, status)
        self.assertIn("Non-interactive run", output)
        self.assertIn("24.0.0 -> 24.1.0", output)
        self.assertFalse(errors)
        self.assertEqual(0, self.interaction.picks)
        self.assertEqual(3, len(self.events))

    def test_cancellation_and_default_no_stop_before_requery_or_application(self):
        for status, answer in ((130, "yes"), (1, "yes"), (0, ""), (0, "no")):
            with self.subTest(status=status, answer=answer):
                self.events.clear()
                self.interaction.status, self.interaction.answer = status, answer
                result, output, _ = self.invoke()
                self.assertEqual(0, result)
                self.assertIn("No upgrades selected", output)
                self.assertEqual(3, len(self.events))

    def test_only_selected_managers_are_requeried_and_applied(self):
        self.interaction.selected = (1,)
        self.invoke()
        self.assertEqual([
            ("discover", "Homebrew"), ("discover", "App Store"), ("discover", "Mise"),
            ("discover", "App Store"), ("apply", "App Store", [self.app]),
        ], self.events)

    def test_changed_candidates_abort_before_any_application(self):
        for result in ([], [upgrades.Candidate("mise", "node", "24.0.0", "24.2.0")]):
            with self.subTest(result=result):
                self.events.clear()
                self.mise.discoveries = [[self.node], result]
                with self.assertRaisesRegex(RuntimeError, "candidates changed"):
                    self.invoke()
                self.assertTrue(all(event[0] == "discover" for event in self.events))

    def test_failed_requery_stops_before_any_application(self):
        self.mise.discoveries.append(RuntimeError("requery unavailable"))
        with self.assertRaisesRegex(RuntimeError, "requery unavailable"):
            self.invoke()
        self.assertTrue(all(event[0] == "discover" for event in self.events))

    def test_an_apply_failure_stops_later_managers_without_claiming_completion(self):
        for manager, applied in ((self.mise, ["Mise"]),
                                 (self.homebrew, ["Mise", "Homebrew"])):
            with self.subTest(manager=manager.label):
                self.events.clear()
                manager.error = RuntimeError("apply failed")
                output = io.StringIO()
                with contextlib.redirect_stdout(output), self.assertRaisesRegex(RuntimeError, "apply failed"):
                    upgrades.upgrade(self.homebrew, self.app_store, self.mise, {},
                                     interaction=self.interaction)
                self.assertNotIn("Selected upgrades completed", output.getvalue())
                self.assertEqual(applied, [event[1] for event in self.events if event[0] == "apply"])
                manager.error = None

    def test_missing_picker_and_empty_selection_stop_without_requery(self):
        for available, selected in ((False, (0,)), (True, ())):
            with self.subTest(available=available):
                self.events.clear()
                self.interaction.has_picker, self.interaction.selected = available, selected
                _, output, errors = self.invoke()
                self.assertIn("No upgrades selected" if available else "fzf unavailable", output + errors)
                self.assertEqual(3, len(self.events))

    def test_unknown_picker_rows_and_picker_failures_stop_before_requery(self):
        self.interaction.rows = "999\tunknown"
        with self.assertRaisesRegex(ValueError, "unknown candidate"):
            self.invoke()
        self.assertEqual(3, len(self.events))
        self.events.clear()
        self.interaction.status = 2
        with self.assertRaisesRegex(RuntimeError, "picker failed"):
            self.invoke()
        self.assertEqual(3, len(self.events))

    def test_a_failed_manager_does_not_hide_other_upgrade_candidates(self):
        self.homebrew.discoveries = [ValueError("invalid declarations")]
        self.interaction.selected = (1,)
        _, output, errors = self.invoke()
        self.assertIn("Homebrew update discovery unavailable", errors)
        self.assertIn("invalid declarations", errors)
        self.assertIn("Selected upgrades completed", output)
        self.assertEqual([("apply", "Mise", [self.node])],
                         [event for event in self.events if event[0] == "apply"])

    def test_no_candidates_reports_without_opening_the_picker(self):
        for manager in (self.homebrew, self.app_store, self.mise):
            manager.discoveries = [[]]
        status, output, errors = self.invoke()
        self.assertEqual(0, status)
        self.assertIn("No upgrade candidates found", output)
        self.assertEqual(0, self.interaction.picks)
        self.assertFalse(errors)
        self.assertEqual(3, len(self.events))


class ManagerContractTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-upgrade-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "mise").mkdir()
        (self.root / "Brewfile").write_text("brew 'git' # Git\ncask 'example' # App\nmas 'Example', id: 123 # Example\n")
        (self.root / "README.md").write_text("original\n")
        (self.root / "mise/config.toml").write_text(CONFIG)
        (self.root / "mise/mise.lock").write_text(LOCK)
        self.env = {"PATH": "/never-run-tools", "FZF_DEFAULT_OPTS": "--query=untrusted"}
        self.brew = "/fixture/bin/brew"
        self.commands = Commands()
        self.advisories = Advisories()
        self.before = self.sources()

    def sources(self):
        return {name: (self.root / name).read_bytes() for name in ("mise/config.toml", "mise/mise.lock", "README.md", "Brewfile")}

    def policy(self, *args, stage=False):
        prefix = [str(self.root / "_scripts/mise-policy"), str(self.root)]
        if stage:
            prefix += ["--declarations", "<stage>/mise"]
        return [*prefix, *args]

    def brew_discovery(self):
        return [Reply([self.brew, "outdated", "--json=v2", "--formula", "git"],
                      json.dumps({"formulae": [{"name": "git", "installed_versions": ["1.0.0"], "current_version": "2.0.0", "pinned": False}]}), 1),
                Reply([self.brew, "outdated", "--json=v2", "--cask", "--greedy", "example"],
                      json.dumps({"casks": [{"name": "example", "installed_versions": ["1.0.0"], "current_version": "2.0.0"}]}), 1)]

    def mas_discovery(self):
        return [Reply(["mas", "outdated", "--inaccurate", "123"], "123 Example (1.0.0 -> 2.0.0)\n999 Undeclared (1.0.0 -> 9.0.0)\n")]

    def mise_discovery(self):
        return [Reply(self.policy("run", "outdated", "--json", "node"), '{"node": {"current": "24.0.0", "latest": "24.1.0"}}'),
                Reply(self.policy("run", "outdated", "--json", "--bump", "npm:sample", "npm:kept"), '{"npm:sample": {"current": "1.0.0", "latest": "2.0.0"}}')]

    def mise_apply(self, names, lock_text, versions, install_effect=None):
        def write_lock(stage):
            (stage / "mise/mise.lock").write_text(lock_text)

        self.commands.replies.extend([
            Reply(self.policy("lock", *names, stage=True), effect=write_lock),
            Reply(self.policy("lock", *names, stage=True), effect=write_lock),
        ])
        for name in sorted(names):
            self.commands.replies.append(Reply(self.policy("run", "ls", "--json", "--current", name, stage=True),
                                              json.dumps([{"version": versions[name]}])))
        self.commands.replies.extend([
            Reply([str(self.root / "_scripts/render-software-catalog"), "<stage>"], effect=lambda stage: (stage / "README.md").write_text("rendered\n")),
            Reply(self.policy("run", "install", *names, stage=True), capture=False, effect=install_effect),
            Reply([str(self.root / "mise/install.sh")], capture=False),
        ])

    def test_selected_mise_persists_only_approved_versions_and_keeps_options(self):
        self.mise_apply(["npm:sample"], LOCK.replace('version = "1.0.0"', 'version = "2.0.0"', 1), {"npm:sample": "2.0.0"})
        upgrades.Mise(self.root, self.env, self.commands, self.advisories).apply(
            [upgrades.Candidate("mise", "npm:sample", "1.0.0", "2.0.0")])
        config = upgrades.read_toml(self.root / "mise/config.toml")
        self.assertEqual("lts", config["tools"]["node"])
        self.assertEqual({"version": "2.0.0", "npm_args": "--ignore-scripts=false"}, config["tools"]["npm:sample"])
        self.assertEqual("1.0.0", config["tools"]["npm:kept"])
        self.assertIn("# CLI", (self.root / "mise/config.toml").read_text())
        self.assertEqual("rendered\n", (self.root / "README.md").read_text())
        self.assertFalse(self.commands.replies)

    def test_discovery_preserves_lts_and_bumps_exact_pins(self):
        self.commands.replies.extend(self.mise_discovery())
        candidates = upgrades.Mise(self.root, self.env, self.commands, self.advisories).discover()
        self.assertEqual([
            upgrades.Candidate("mise", "node", "24.0.0", "24.1.0"),
            upgrades.Candidate("mise", "npm:sample", "1.0.0", "2.0.0"),
        ], candidates)
        self.assertFalse(self.commands.replies)

    def test_homebrew_only_applies_the_selected_declaration(self):
        self.commands.replies.extend(self.brew_discovery())
        manager = upgrades.Homebrew(self.root, self.brew, self.env, self.commands)
        selected = manager.discover()[:1]
        self.commands.replies.append(Reply([self.brew, "upgrade", "--formula", "git"], capture=False))
        manager.apply(selected)
        self.assertFalse(self.commands.replies)
        self.assertEqual(self.before, self.sources())

    def test_app_store_only_applies_the_declared_id_with_required_privilege(self):
        self.commands.replies.extend(self.mas_discovery())
        manager = upgrades.AppStore(self.root, self.env, self.commands)
        selected = manager.discover()
        self.assertEqual(["123"], [candidate.name for candidate in selected])
        self.commands.replies.append(Reply(["sudo", "/fixture/bin/mas", "upgrade", "--inaccurate", "123"], capture=False))
        manager.apply(selected)
        self.assertFalse(self.commands.replies)
        self.assertEqual(self.before, self.sources())

    def test_homebrew_audit_reports_findings_and_keeps_failures_advisory(self):
        for status, report, message in (
            (1, '{"findings": [{"formula": "git", "version": "1.0.0", "vulnerabilities": [{"id": "GHSA-fixture"}]}], "skipped_formulae": ["private-source"]}', "GHSA-fixture"),
            (2, "", "coverage unavailable"),
        ):
            with self.subTest(status=status):
                self.commands.replies.append(Reply([
                    self.brew, "vulns", f"--brewfile={self.root / 'Brewfile'}",
                    "--deps", "--list-skipped", "--json",
                ], report, status, "scanner unavailable" if status == 2 else ""))
                output, errors = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                    gaps = upgrades.Homebrew(self.root, self.brew, self.env, self.commands).audit([])
                self.assertEqual(["casks"], gaps)
                self.assertIn(message, output.getvalue() + errors.getvalue())
                if status == 1:
                    self.assertIn("private-source", output.getvalue())
                self.assertFalse(self.commands.replies)

    def test_osv_audits_direct_installed_and_candidate_versions(self):
        self.advisories.results = [{"vulns": [{"id": "GHSA-sample"}]}, {}, {}]
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            gaps = upgrades.Mise(self.root, self.env, self.commands, self.advisories).audit(
                [upgrades.Candidate("mise", "npm:sample", "1.0.0", "2.0.0")])
        self.assertIn("GHSA-sample", output.getvalue())
        self.assertEqual([
            {"package": {"ecosystem": "npm", "name": "sample"}, "version": "1.0.0"},
            {"package": {"ecosystem": "npm", "name": "sample"}, "version": "2.0.0"},
            {"package": {"ecosystem": "npm", "name": "kept"}, "version": "1.0.0"},
        ], self.advisories.queries)
        self.assertIn("transitive Mise dependencies", gaps)

    def test_osv_errors_and_incomplete_reports_remain_advisory(self):
        for error, results, message in (
            (OSError("offline"), None, "coverage unavailable"),
            (None, [], "incomplete OSV response"),
            (None, [{"next_page_token": "next"}, {}], "report is incomplete"),
        ):
            with self.subTest(message=message):
                self.advisories.error, self.advisories.results = error, results
                errors = io.StringIO()
                with contextlib.redirect_stderr(errors):
                    upgrades.Mise(self.root, self.env, self.commands, self.advisories).audit([])
                self.assertIn(message, errors.getvalue())

    def test_rejected_brewfile_lines_do_not_prevent_mise_discovery(self):
        with (self.root / "Brewfile").open("a") as stream:
            stream.write("brew 'git', args: ['HEAD']\n")
        for manager in (upgrades.Homebrew(self.root, self.brew, self.env, self.commands),
                        upgrades.AppStore(self.root, self.env, self.commands)):
            with self.assertRaisesRegex(ValueError, "Brewfile:4:"):
                manager.discover()
        self.commands.replies.extend(self.mise_discovery())
        candidates = upgrades.Mise(self.root, self.env, self.commands, self.advisories).discover()
        self.assertIn(upgrades.Candidate("mise", "node", "24.0.0", "24.1.0"), candidates)
        self.assertFalse(self.commands.replies)

    def test_query_warnings_are_reported_and_queries_have_a_timeout(self):
        self.commands.replies.extend(self.brew_discovery())
        self.commands.replies[0].stderr = "catalog warning"
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            upgrades.Homebrew(self.root, self.brew, self.env, self.commands).discover()
        self.assertIn("catalog warning", errors.getvalue())
        self.assertTrue(all(event[5] == 180 for event in self.commands.events))
        self.assertFalse(self.commands.replies)

    def test_install_failure_or_unselected_lock_drift_preserves_source(self):
        for failure in ("lock", "install", "drift"):
            with self.subTest(failure=failure):
                self.commands = Commands()
                selected_lock = LOCK.replace('version = "1.0.0"', 'version = "2.0.0"', 1)
                if failure == "drift":
                    selected_lock = selected_lock.replace('version = "1.0.0"', 'version = "9.0.0"')
                self.mise_apply(["npm:sample"], selected_lock, {"npm:sample": "2.0.0"})
                if failure in ("lock", "install"):
                    self.commands.replies[0 if failure == "lock" else -2].status = 1
                with self.assertRaises((RuntimeError, ValueError)):
                    upgrades.Mise(self.root, self.env, self.commands, self.advisories).apply(
                        [upgrades.Candidate("mise", "npm:sample", "1.0.0", "2.0.0")])
                self.assertEqual(self.before, self.sources())
                self.assertTrue(self.commands.replies, "later steps must remain unexecuted")

    def test_ruby_backend_defaults_do_not_freeze_its_macos_resolution(self):
        config = self.root / "mise/config.toml"
        config.write_text(CONFIG.replace("[settings]", 'ruby = "4.0"\n[settings]'))
        lock = self.root / "mise/mise.lock"
        ruby_lock = ('[[tools.ruby]]\nversion = "4.0.7"\n'
                     '[[tools.ruby]]\nversion = "4.0.8"\n'
                     '[tools.ruby.options]\ncompile = "false"\nprecompiled_url = "jdx/ruby"\n')
        lock.write_text(LOCK + ruby_lock.replace("4.0.8", "4.0.7"))
        self.mise_apply(["ruby"], LOCK + ruby_lock, {"ruby": "4.0.8"})
        upgrades.Mise(self.root, self.env, self.commands, self.advisories).apply(
            [upgrades.Candidate("mise", "ruby", "4.0.7", "4.0.8")])
        self.assertEqual("4.0.8", upgrades.read_toml(lock)["tools"]["ruby"][-1]["version"])
        self.assertEqual("4.0", upgrades.read_toml(config)["tools"]["ruby"])
        self.assertFalse(self.commands.replies)

    def test_concurrent_source_edit_is_preserved(self):
        self.mise_apply(["node"], LOCK.replace("24.0.0", "24.1.0"), {"node": "24.1.0"},
                        install_effect=lambda stage: (self.root / "README.md").write_text("owner edit\n"))
        with self.assertRaisesRegex(RuntimeError, "source changed"):
            upgrades.Mise(self.root, self.env, self.commands, self.advisories).apply(
                [upgrades.Candidate("mise", "node", "24.0.0", "24.1.0")])
        self.assertEqual("owner edit\n", (self.root / "README.md").read_text())
        self.assertEqual(self.before["mise/config.toml"], (self.root / "mise/config.toml").read_bytes())
        self.assertEqual(1, len(self.commands.replies), "post-publication installer must not run")

    def test_homebrew_holds_and_unknown_candidates_are_never_applied(self):
        replies = self.brew_discovery()
        for reply in replies:
            data = json.loads(reply.stdout)
            next(iter(data.values()))[0]["pinned"] = True
            reply.stdout = json.dumps(data)
        self.commands.replies.extend(replies)
        self.assertEqual([], upgrades.Homebrew(self.root, self.brew, self.env, self.commands).discover())
        reply = self.brew_discovery()[0]
        reply.stdout = reply.stdout.replace('"name": "git"', '"name": "undeclared"')
        self.commands.replies.append(reply)
        with self.assertRaisesRegex(ValueError, "undeclared"):
            upgrades.Homebrew(self.root, self.brew, self.env, self.commands).discover()

    def test_post_publication_installer_failure_keeps_published_sources(self):
        self.mise_apply(["node"], LOCK.replace("24.0.0", "24.1.0"), {"node": "24.1.0"})
        self.commands.replies[-1].status = 1
        with self.assertRaisesRegex(RuntimeError, "earlier upgrades may already have completed"):
            upgrades.Mise(self.root, self.env, self.commands, self.advisories).apply(
                [upgrades.Candidate("mise", "node", "24.0.0", "24.1.0")])
        self.assertFalse(self.commands.replies)
        self.assertEqual("24.1.0", upgrades.read_toml(self.root / "mise/mise.lock")["tools"]["node"][0]["version"])

    def test_brewfile_edit_during_install_prevents_stale_catalog_publication(self):
        self.mise_apply(["node"], LOCK.replace("24.0.0", "24.1.0"), {"node": "24.1.0"},
                        install_effect=lambda stage: (self.root / "Brewfile").write_text("brew 'other' # Owner edit\n"))
        with self.assertRaisesRegex(RuntimeError, "source changed"):
            upgrades.Mise(self.root, self.env, self.commands, self.advisories).apply(
                [upgrades.Candidate("mise", "node", "24.0.0", "24.1.0")])
        self.assertEqual("brew 'other' # Owner edit\n", (self.root / "Brewfile").read_text())
        for name in ("README.md", "mise/config.toml", "mise/mise.lock"):
            self.assertEqual(self.before[name], (self.root / name).read_bytes())
        self.assertEqual(1, len(self.commands.replies))

    def test_app_store_rechecks_executable_and_privilege_when_applying(self):
        manager = upgrades.AppStore(self.root, self.env, self.commands)
        self.commands.replies.extend(self.mas_discovery())
        candidates = manager.discover()
        self.commands.executables["mas"] = "/new/bin/mas"
        self.commands.root_user = True
        self.commands.replies.append(Reply(["/new/bin/mas", "upgrade", "--inaccurate", "123"], capture=False))
        manager.apply(candidates)
        self.commands.executables.pop("mas")
        with self.assertRaisesRegex(RuntimeError, "mas became unavailable"):
            manager.apply(candidates)
        self.assertFalse(self.commands.replies)


if __name__ == "__main__":
    unittest.main()
