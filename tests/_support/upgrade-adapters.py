"""Production adapter contracts at the terminal and HTTP boundaries."""

import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "_scripts"))
from upgrade_adapters import OsvAdvisories, TerminalInteraction
from upgrade_recordings import Commands, Reply


class UpgradeAdaptersTest(unittest.TestCase):
    def test_either_redirected_stream_disables_interaction(self):
        terminal = TerminalInteraction(Commands())
        for stdin, stdout in ((False, True), (True, False), (False, False), (True, True)):
            with self.subTest(stdin=stdin, stdout=stdout):
                with patch.object(sys.stdin, "isatty", return_value=stdin), patch.object(sys.stdout, "isatty", return_value=stdout):
                    self.assertEqual(stdin and stdout, terminal.interactive())

    def test_picker_preserves_rows_and_clears_inherited_options(self):
        commands = Commands([Reply([
            "fzf", "--multi", "--delimiter=\t", "--with-nth=2..", "--no-sort", "--wrap",
            "--bind=space:toggle,ctrl-a:select-all,ctrl-d:deselect-all",
            "--header=Upgrades | Tab/Space: select | Ctrl-A: all | Enter: review | Esc: skip",
            "--prompt=Upgrade> ",
        ], "0\tcandidate")])
        terminal = TerminalInteraction(commands)
        result = terminal.pick(["0\tcandidate"], {"FZF_DEFAULT_OPTS": "untrusted", "FZF_DEFAULT_OPTS_FILE": "untrusted"})
        self.assertEqual("0\tcandidate", result.stdout)
        _, _, env, capture, stdin, timeout = commands.events[0]
        self.assertEqual("", env["FZF_DEFAULT_OPTS"])
        self.assertEqual("", env["FZF_DEFAULT_OPTS_FILE"])
        self.assertEqual("0\tcandidate", stdin)
        self.assertTrue(capture)
        self.assertIsNone(timeout)

    def test_osv_posts_version_queries_with_a_timeout_and_returns_results(self):
        queries = [{"package": {"ecosystem": "npm", "name": "sample"}, "version": "2.0.0"}]
        results = [{"vulns": [{"id": "GHSA-fixture"}]}]
        with patch("urllib.request.urlopen", return_value=io.BytesIO(json.dumps({"results": results}).encode())) as request:
            self.assertEqual(results, OsvAdvisories().lookup(queries))
        args, kwargs = request.call_args
        self.assertEqual("https://api.osv.dev/v1/querybatch", args[0].full_url)
        self.assertEqual("POST", args[0].get_method())
        self.assertEqual({"queries": queries}, json.loads(args[0].data))
        self.assertEqual(30, kwargs["timeout"])


if __name__ == "__main__":
    unittest.main()
