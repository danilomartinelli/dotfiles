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


class UpgradesTest(unittest.TestCase):
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
        self.interaction = Interaction()
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

    def discovery_and_audit(self):
        self.commands.replies.extend(self.brew_discovery() + self.mas_discovery() + self.mise_discovery())
        self.commands.replies.append(Reply([self.brew, "vulns", f"--brewfile={self.root / 'Brewfile'}", "--deps", "--list-skipped", "--json"],
                                          '{"findings": [{"formula": "git", "version": "1.0.0", "vulnerabilities": [{"id": "GHSA-fixture"}]}], "skipped_formulae": ["private-source"]}', 1))

    def invoke(self):
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = upgrades.upgrade(self.root, self.brew, self.env, commands=self.commands,
                                      advisories=self.advisories, interaction=self.interaction)
        self.assertFalse(self.commands.replies, "unused command replies")
        return status, output.getvalue(), errors.getvalue()

    def test_noninteractive_reports_without_installs_or_source_changes(self):
        self.discovery_and_audit()
        status, output, errors = self.invoke()
        self.assertEqual(0, status)
        self.assertIn("Non-interactive run", output)
        self.assertIn("GHSA-fixture", output)
        self.assertIn("private-source", output)
        self.assertEqual(self.before, self.sources())
        self.assertEqual(0, self.interaction.picks)
        self.assertEqual(3, len(self.advisories.queries))
        self.assertFalse(errors)

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

    def test_a_rejected_brewfile_line_leaves_mise_discovery_available(self):
        with (self.root / "Brewfile").open("a") as stream:
            stream.write("brew 'git', args: ['HEAD']\n")
        self.discovery_and_audit()
        for _ in range(3):
            self.commands.replies.popleft()
        _, output, errors = self.invoke()
        self.assertIn("Homebrew update discovery unavailable", errors)
        self.assertIn("App Store update discovery unavailable", errors)
        self.assertIn("Brewfile:4: ", errors)
        self.assertIn("node  24.0.0 -> 24.1.0", output)

    def test_cancel_and_default_no_do_not_mutate(self):
        for status, answer in ((130, "yes"), (1, "yes"), (0, ""), (0, "no")):
            with self.subTest(status=status, answer=answer):
                self.discovery_and_audit()
                self.interaction = Interaction(interactive=True, selected=(0,), answer=answer)
                self.interaction.status = status
                self.invoke()
                self.assertEqual(self.before, self.sources())

    def test_selected_brew_only_and_audit_failure_is_advisory(self):
        self.discovery_and_audit()
        self.commands.replies[-1].status = 2
        self.commands.replies[-1].stderr = "scanner unavailable"
        self.commands.replies.extend(self.brew_discovery())
        self.commands.replies.append(Reply([self.brew, "upgrade", "--formula", "git"], capture=False))
        self.interaction = Interaction(interactive=True, selected=(0,), answer="yes")
        _, output, errors = self.invoke()
        self.assertIn("coverage unavailable", errors)
        self.assertIn("Selected upgrades completed", output)
        self.assertTrue(all(event[2]["HOMEBREW_NO_AUTO_UPDATE"] == "1" and
                            event[2]["HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK"] == "1"
                            for event in self.commands.events))

    def test_discovery_preserves_lts_and_bumps_exact_pins(self):
        self.commands.replies.extend(self.mise_discovery())
        candidates = upgrades.Mise(self.root, self.env, self.commands, self.advisories).discover()
        self.assertEqual([
            upgrades.Candidate("mise", "node", "24.0.0", "24.1.0"),
            upgrades.Candidate("mise", "npm:sample", "1.0.0", "2.0.0"),
        ], candidates)
        self.assertFalse(self.commands.replies)

    def test_selected_app_store_upgrade_only_targets_its_declared_id(self):
        self.discovery_and_audit()
        self.commands.replies.extend(self.mas_discovery())
        self.commands.replies.append(Reply(["sudo", "/fixture/bin/mas", "upgrade", "--inaccurate", "123"], capture=False))
        self.interaction = Interaction(interactive=True, selected=(2,), answer="yes")
        self.invoke()
        self.assertEqual(self.before, self.sources())

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

    def test_pins_and_unknown_candidates_are_never_applied(self):
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
        self.discovery_and_audit()
        self.interaction = Interaction(interactive=True)
        self.interaction.rows = "999\tunknown"
        with self.assertRaisesRegex(ValueError, "unknown candidate"):
            self.invoke()

    def test_changed_candidates_abort_before_any_install(self):
        self.discovery_and_audit()
        requery = self.brew_discovery()
        requery[0].stdout = '{"formulae": []}'
        self.commands.replies.extend(requery)
        self.interaction = Interaction(interactive=True, selected=(0,), answer="yes")
        with self.assertRaisesRegex(RuntimeError, "candidates changed"):
            self.invoke()
        self.assertFalse(self.commands.replies)

    def test_managers_apply_mise_first_then_homebrew_then_app_store(self):
        self.discovery_and_audit()
        self.commands.replies.extend(self.brew_discovery() + self.mas_discovery() + self.mise_discovery())
        self.mise_apply(["node"], LOCK.replace("24.0.0", "24.1.0"), {"node": "24.1.0"})
        self.commands.replies.extend([
            Reply([self.brew, "upgrade", "--formula", "git"], capture=False),
            Reply(["sudo", "/fixture/bin/mas", "upgrade", "--inaccurate", "123"], capture=False),
        ])
        self.interaction = Interaction(interactive=True, selected=(2, 3, 0), answer="yes")
        self.invoke()
        self.assertEqual("lts", upgrades.read_toml(self.root / "mise/config.toml")["tools"]["node"])

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

    def test_missing_picker_and_empty_selection_do_not_requery(self):
        for available, selected in ((False, (0,)), (True, ())):
            with self.subTest(available=available):
                self.discovery_and_audit()
                self.interaction = Interaction(interactive=True, selected=selected, answer="yes")
                self.interaction.has_picker = available
                _, output, errors = self.invoke()
                self.assertIn("No upgrades selected" if available else "fzf unavailable", output + errors)
                self.assertEqual(self.before, self.sources())

    def test_osv_errors_and_incomplete_reports_remain_advisory(self):
        for error, results, message in (
            (OSError("offline"), None, "coverage unavailable"),
            (None, [], "incomplete OSV response"),
            (None, [{"vulns": [{"id": "GHSA-sample"}], "next_page_token": "next"}, {}, {}], "report is incomplete"),
        ):
            with self.subTest(message=message):
                self.discovery_and_audit()
                self.advisories.error, self.advisories.results = error, results
                _, output, errors = self.invoke()
                self.assertIn(message, errors)
                self.assertIn("Non-interactive run", output)

    def test_requery_failure_stops_before_any_install(self):
        self.discovery_and_audit()
        reply = self.brew_discovery()[0]
        reply.status, reply.stderr = 2, "requery unavailable"
        self.commands.replies.append(reply)
        self.interaction = Interaction(interactive=True, selected=(0,), answer="yes")
        with self.assertRaisesRegex(RuntimeError, "requery unavailable"):
            self.invoke()
        self.assertFalse(self.commands.replies)
        self.assertEqual(self.before, self.sources())

    def test_post_publication_installer_failure_keeps_published_sources_and_stops_brew(self):
        self.discovery_and_audit()
        self.commands.replies.extend(self.brew_discovery() + self.mise_discovery())
        self.mise_apply(["node"], LOCK.replace("24.0.0", "24.1.0"), {"node": "24.1.0"})
        self.commands.replies[-1].status = 1
        self.interaction = Interaction(interactive=True, selected=(0, 3), answer="yes")
        with self.assertRaisesRegex(RuntimeError, "earlier upgrades may already have completed"):
            self.invoke()
        self.assertFalse(self.commands.replies)
        self.assertEqual("24.1.0", upgrades.read_toml(self.root / "mise/mise.lock")["tools"]["node"][0]["version"])

    def test_mise_preparation_failure_stops_other_managers(self):
        self.discovery_and_audit()
        self.commands.replies.extend(self.brew_discovery() + self.mas_discovery() + self.mise_discovery())
        self.commands.replies.append(Reply(self.policy("lock", "node", stage=True), status=1, stderr="lock failed"))
        self.interaction = Interaction(interactive=True, selected=(0, 2, 3), answer="yes")
        with self.assertRaisesRegex(RuntimeError, "lock failed"):
            self.invoke()
        self.assertFalse(self.commands.replies)
        self.assertEqual(self.before, self.sources())

    def test_query_warnings_are_reported_and_queries_have_a_timeout(self):
        self.discovery_and_audit()
        self.commands.replies[0].stderr = "catalog warning"
        _, output, errors = self.invoke()
        self.assertIn("catalog warning", errors)
        self.assertTrue(all(event[5] == 180 for event in self.commands.events))

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
