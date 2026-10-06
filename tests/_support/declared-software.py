"""The declared-software reader at its own seam: text in, declarations out."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
COMMAND = ROOT / "_scripts/declared_software.py"
sys.path.insert(0, str(COMMAND.parent))
import declared_software  # noqa: E402

DeclarationError = declared_software.DeclarationError


def brewfile(*lines):
    return declared_software.parse_brewfile("\n".join(lines) + "\n")


def mise_config(*lines):
    return declared_software.parse_mise_config("\n".join(lines) + "\n")


class BrewfileTest(unittest.TestCase):
    def test_literal_lines_become_taps_and_declarations(self):
        result = brewfile(
            "# Header prose",
            "",
            "cask_args appdir: '/Applications', fontdir: \"/Library/Fonts\"",
            "tap 'vendor/tap'                # Vendor formulae",
            "brew 'git'                      # Version control",
            'brew "vendor/tap/tool"',
            "mas 'Xcode', id: 497799835      # Apple IDE",
            'mas "Logic Pro\'s",id:634148309',
        )
        self.assertEqual(("vendor/tap",), result.taps)
        self.assertEqual(
            (
                declared_software.Declaration("formula", "git", "Version control"),
                declared_software.Declaration("formula", "vendor/tap/tool"),
                declared_software.Declaration(
                    "mas", "Xcode", "Apple IDE", identifier="497799835"
                ),
                declared_software.Declaration(
                    "mas", "Logic Pro's", identifier="634148309"
                ),
            ),
            result.declarations,
        )

    def test_the_comment_opening_a_cask_block_is_its_group(self):
        result = brewfile(
            "# Development",
            "cask 'zed'",
            "cask 'lens'",
            "# Browsers",
            "cask 'dia'",
            "",
            "cask 'orphan'",
            "# Fonts",
            "brew 'git'",
            "cask 'after-formula'",
        )
        self.assertEqual(
            [
                ("zed", "Development"),
                ("lens", "Development"),
                ("dia", "Browsers"),
                ("orphan", ""),
                ("after-formula", ""),
            ],
            [(d.name, d.group) for d in result.declarations if d.kind == "cask"],
        )

    def test_lines_outside_the_grammar_are_rejected_by_line(self):
        for line in (
            "if OS.mac?",
            "brew 'git', args: ['HEAD']",
            "  brew 'indented'",
            "  # indented comment",
            "brew git",
            'brew "interpolated#{name}"',
            "brew 'escaped\\'quote'",
            "mas 'App', id: abc",
            "mas 'App'",
            "whalebrew 'image'",
            "cask_args appdir: /Applications",
        ):
            with self.subTest(line=line):
                with self.assertRaisesRegex(DeclarationError, r"^Brewfile:2: "):
                    brewfile("brew 'git'", line)


class MiseConfigTest(unittest.TestCase):
    def test_one_line_declarations_carry_versions_options_and_descriptions(self):
        result = mise_config(
            "# Rationale above the table",
            "[tools]",
            'node = "lts"                         # Node.js',
            "# Rationale between declarations",
            '"npm:tool" = { version = "1.0.0", npm_args = "--x" } # Tool',
            '"go:example.com/cmd" = "latest"',
            "",
            "[settings]",
            'enabled = ["node", "bun"]',
        )
        self.assertEqual(
            (
                declared_software.Declaration("mise", "node", "Node.js", version="lts"),
                declared_software.Declaration(
                    "mise",
                    "npm:tool",
                    "Tool",
                    version="1.0.0",
                    options=(("npm_args", "--x"),),
                ),
                declared_software.Declaration(
                    "mise", "go:example.com/cmd", version="latest"
                ),
            ),
            result,
        )

    def test_an_exact_release_is_a_pin_and_anything_else_a_channel(self):
        for version, selection in (
            ("1.27.1", "pin"),
            ("v1.2.3", "pin"),
            ("2.0.0-rc.1", "pin"),
            ("latest", "channel"),
            ("lts", "channel"),
            ("1.20", "channel"),
            ("29", "channel"),
            ("temurin-25", "channel"),
        ):
            with self.subTest(version=version):
                (declaration,) = mise_config("[tools]", f'tool = "{version}"')
                self.assertEqual(selection, declaration.selection)

    def test_lines_outside_the_grammar_are_rejected_by_line(self):
        for lines, number in (
            (('node = ["20", "22"]',), 2),
            (('node = """', 'lts"""'), 2),
            (('node.version = "20"',), 2),
            (('node = ""',), 2),
            (('node = { npm_args = "--x" }',), 2),
            (('node = { version = "20", compile = false }',), 2),
            (("node = 'lts'",), 2),
            (('  node = "lts"',), 2),
            (('node = "lts"', "[tools.other]", 'version = "20"'), 3),
            (('node = "lts"', "[[tools.extra]]", 'name = "x"'), 3),
        ):
            with self.subTest(lines=lines):
                with self.assertRaisesRegex(
                    DeclarationError, rf"^mise/config.toml:{number}: "
                ):
                    mise_config("[tools]", *lines)

    def test_a_config_without_tools_or_valid_toml_is_rejected(self):
        for lines in (("[settings]", "lockfile = true"), ("[tools", 'node = "lts"')):
            with self.subTest(lines=lines):
                with self.assertRaisesRegex(DeclarationError, "^mise/config.toml: "):
                    mise_config(*lines)

    def test_every_uv_with_package_names_an_exact_version(self):
        (declaration,) = mise_config(
            "[tools]",
            '"pipx:tool" = { version = "1.0.0", uvx_args = "--with a==1.0 --with=b[x]==2" }',
        )
        self.assertEqual((("a", "1.0"), ("b[x]", "2")), declaration.extras)
        for args in ("--with a", "--with a>=1.0", "--with a==", "--with"):
            with self.subTest(args=args):
                with self.assertRaisesRegex(DeclarationError, r"^mise/config.toml:2: "):
                    mise_config(
                        "[tools]",
                        f'"pipx:tool" = {{ version = "1.0.0", uvx_args = "{args}" }}',
                    )
        (other,) = mise_config(
            "[tools]", '"npm:tool" = { version = "1.0.0", uvx_args = "--with a" }'
        )
        self.assertEqual((), other.extras)


class RewriteTest(unittest.TestCase):
    CONFIG = (
        "# Header\n"
        "[tools]\n"
        'node = "lts"            # Node.js\n'
        '"npm:tool" = { npm_args = "--version=x", version = "1.0.0" } # Tool\n'
        'kept = "1.0.0"\n'
        "[settings]\n"
        "lockfile = true\n"
    )

    def test_only_the_selected_version_values_change(self):
        rewritten = declared_software.rewrite_versions(
            self.CONFIG, {"node": "24.1.0", "npm:tool": "2.0.0"}
        )
        self.assertEqual(
            self.CONFIG.replace('"lts"', '"24.1.0"').replace(
                'version = "1.0.0"', 'version = "2.0.0"'
            ),
            rewritten,
        )
        self.assertEqual(
            {"node": "24.1.0", "npm:tool": "2.0.0", "kept": "1.0.0"},
            {d.name: d.version for d in declared_software.parse_mise_config(rewritten)},
        )

    def test_a_missing_declaration_or_unwritable_version_is_refused(self):
        for versions in ({"absent": "1.0.0"}, {"node": 'bad"quote'}, {"node": ""}):
            with self.subTest(versions=versions):
                with self.assertRaises(DeclarationError):
                    declared_software.rewrite_versions(self.CONFIG, versions)


class CommandTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="dotfiles-declared-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "mise").mkdir()
        (self.root / "Brewfile").write_text(
            "tap 'vendor/tap' # Taps\n"
            "brew 'git' # Version control\n"
            "# Editors\n"
            "cask 'zed' # Editor\n"
            "mas 'Xcode', id: 497799835 # IDE\n"
        )
        (self.root / "mise/config.toml").write_text(
            '[tools]\nnode = "lts" # Node.js\ngo = "1.27.1"\n'
        )

    def command(self, *args):
        return subprocess.run(
            [sys.executable, str(COMMAND), *args],
            capture_output=True,
            text=True,
        )

    def test_taps_are_reported_without_catalog_formatting(self):
        result = self.command("taps", str(self.root))
        self.assertEqual(
            (0, "vendor/tap\n", ""),
            (result.returncode, result.stdout, result.stderr),
        )

    def test_each_catalog_region_prints_ready_to_render_cells(self):
        with (self.root / "Brewfile").open("a") as stream:
            stream.write(
                "brew 'vendor/tap/tool' # Vendor CLI\n"
                "# Browsers\n"
                "cask 'dia' # Browser\n"
                "# Editors\n"
                "cask 'emacs' # Extensible editor\n"
                'mas "Logic Pro\'s", id: 634148309 # Music\n'
            )
        (self.root / "mise/config.toml").write_text(
            '[tools]\n'
            'node = "lts" # Node.js\n'
            'go = "1.27.1" # Go\n'
            '"npm:tool" = { version = "latest", npm_args = "--x" } # CLI\n'
        )
        for region, rows in (
            (
                "homebrew-formulae",
                "`git`\tVersion control\n`vendor/tap/tool`\tVendor CLI\n",
            ),
            ("homebrew-casks", "Editors\t`zed`, `emacs`\nBrowsers\t`dia`\n"),
            (
                "mac-app-store",
                "`Xcode`\t`497799835`\tIDE\n`Logic Pro's`\t`634148309`\tMusic\n",
            ),
            (
                "mise-tools",
                "`node`\t`lts`\tNode.js\n`go`\t`1.27.1`\tGo\n"
                "`npm:tool`\t`latest`\tCLI\n",
            ),
        ):
            with self.subTest(region=region):
                result = self.command(region, str(self.root))
                self.assertEqual(
                    (0, rows, ""), (result.returncode, result.stdout, result.stderr)
                )

    def test_usage_and_rejections_are_distinct_failures(self):
        for args in ((), ("unknown", str(self.root)), ("taps", "a", "b")):
            with self.subTest(args=args):
                self.assertEqual(2, self.command(*args).returncode)
        with (self.root / "Brewfile").open("a") as stream:
            stream.write("brew 'git', args: ['HEAD']\n")
        result = self.command("homebrew-formulae", str(self.root))
        self.assertEqual(1, result.returncode)
        self.assertEqual("", result.stdout)
        self.assertIn("Brewfile:6: ", result.stderr)

    def test_every_catalog_declaration_needs_a_description_before_rows_are_printed(self):
        for region, source, prefix, declaration, name in (
            (
                "homebrew-formulae",
                "Brewfile",
                "brew 'git' # Version control\n",
                "brew 'undescribed-formula'",
                "undescribed-formula",
            ),
            (
                "homebrew-casks",
                "Brewfile",
                "# Editors\ncask 'zed' # Editor\n",
                "cask 'undescribed-cask'",
                "undescribed-cask",
            ),
            (
                "mac-app-store",
                "Brewfile",
                "mas 'Xcode', id: 497799835 # IDE\n",
                "mas 'Undescribed App', id: 123",
                "Undescribed App",
            ),
            (
                "mise-tools",
                "mise/config.toml",
                '[tools]\nnode = "lts" # Node.js\n',
                '"npm:undescribed" = "latest"',
                "npm:undescribed",
            ),
        ):
            for comment in ("", " #", " #   "):
                with self.subTest(region=region, comment=comment):
                    (self.root / source).write_text(prefix + declaration + comment + "\n")
                    result = self.command(region, str(self.root))
                    self.assertEqual(
                        (1, "", f"declared_software: {name} has no catalog description\n"),
                        (result.returncode, result.stdout, result.stderr),
                    )

    def test_a_tab_cannot_reach_a_row(self):
        (self.root / "Brewfile").write_text("brew 'git' # Version\tcontrol\n")
        result = self.command("homebrew-formulae", str(self.root))
        self.assertEqual((1, ""), (result.returncode, result.stdout))
        self.assertIn("tab", result.stderr)

    def test_casks_still_need_a_group(self):
        (self.root / "Brewfile").write_text(
            "# Editors\ncask 'zed' # Editor\n\ncask 'orphan' # Described app\n"
        )
        result = self.command("homebrew-casks", str(self.root))
        self.assertEqual(
            (1, "", "declared_software: cask orphan has no catalog group\n"),
            (result.returncode, result.stdout, result.stderr),
        )


if __name__ == "__main__":
    unittest.main()
