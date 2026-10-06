"""Read the software this repository declares in Brewfile and mise/config.toml.

Six readers used to decide what was declared, in shell, awk and Python, and
they did not share their rules: the documentation test opened [tools] on an
exact line where the renderer accepted a prefix, and an App Store line the
upgrade's expression missed dropped out of upgrades while the catalog still
listed it. This module is now the only reader of both files. It accepts the
closed literal shape docs/adr/0002 records and fails on any other line, naming
the file and line, so a declaration no consumer understands cannot pass
silently.

Python consumers import it. Shell consumers request taps or ready-to-render
catalog cells as tab-separated rows; declaration columns never cross the
process boundary:

  declared_software.py {taps|<catalog-region>} [repository-root]
"""

import sys

if sys.version_info < (3, 11):
    raise SystemExit(
        "declared_software.py: Python 3.11 or newer is required for tomllib; "
        "run it with the Mise-managed python3"
    )

from dataclasses import dataclass
import json
from pathlib import Path
import re
import shlex
import tomllib


class DeclarationError(ValueError):
    """A declaration cannot be read or published in the software catalog."""


@dataclass(frozen=True)
class Declaration:
    kind: str
    name: str
    description: str = ""
    group: str = ""
    identifier: str = ""
    version: str = ""
    options: tuple = ()
    extras: tuple = ()

    @property
    def selection(self):
        """Whether a Mise declaration names one release or a line of them."""
        if self.kind != "mise":
            return ""
        return "pin" if PIN.fullmatch(self.version) else "channel"


@dataclass(frozen=True)
class Brewfile:
    taps: tuple
    declarations: tuple


PIN = re.compile(r"v?\d+\.\d+\.\d+(?:[-+][\w.+-]+)?")

# A double-quoted Ruby string may hold an apostrophe; neither form may hold an
# escape or an interpolation, so the literal text is the name.
NAME = r"""(?:'(?P<name>[^'\\]+)'|"(?P<double>[^"\\#]+)")"""
COMMENT = r"[ \t]*(?:#(?P<comment>.*))?"
BREW_ENTRY = re.compile(rf"(?P<keyword>tap|brew|cask)[ \t]+{NAME}{COMMENT}")
MAS_ENTRY = re.compile(rf"mas[ \t]+{NAME}[ \t]*,[ \t]*id:[ \t]*(?P<id>\d+){COMMENT}")
CASK_ARGUMENT = r"""\w+:[ \t]*(?:'[^']*'|"[^"]*")"""
CASK_ARGS = re.compile(
    rf"cask_args[ \t]+{CASK_ARGUMENT}(?:[ \t]*,[ \t]*{CASK_ARGUMENT})*{COMMENT}"
)

# Strings hold no quote or backslash, so a pair can never hide inside a string.
TOML_KEY = r'(?:[A-Za-z0-9_-]+|"[^"\\]*")'
TOML_STRING = r'"[^"\\]*"'
TOML_PAIR = rf"(?P<key>{TOML_KEY})[ \t]*=[ \t]*" + r'"(?P<string>[^"\\]*)"'
INLINE_TABLE = (
    r"\{[ \t]*"
    + rf"{TOML_KEY}[ \t]*=[ \t]*{TOML_STRING}"
    + rf"(?:[ \t]*,[ \t]*{TOML_KEY}[ \t]*=[ \t]*{TOML_STRING})*"
    + r"[ \t]*\}"
)
TOOL_ENTRY = re.compile(
    rf"(?P<key>{TOML_KEY})[ \t]*=[ \t]*"
    rf"(?P<value>{TOML_STRING}|{INLINE_TABLE}){COMMENT}"
)
SECTION = re.compile(r"\[\[?[ \t]*(?P<name>[^\]]*?)[ \t]*\]\]?[ \t]*(?:#.*)?")


def _fail(source, number, reason):
    raise DeclarationError(f"{source}:{number}: {reason}")


def _quoted(match):
    return match["name"] if match["name"] is not None else match["double"]


def _description(match):
    return (match["comment"] or "").strip()


def parse_brewfile(text, source="Brewfile"):
    """Return the taps and declarations a Brewfile's text selects."""
    taps, declarations = [], []
    pending = group = ""
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            pending = group = ""
            continue
        if line.startswith("#"):
            # The comment directly above a cask block names its catalog group.
            pending = line[1:].strip()
            continue
        if CASK_ARGS.fullmatch(line):
            pending = group = ""
            continue
        match = BREW_ENTRY.fullmatch(line)
        if match and match["keyword"] == "tap":
            taps.append(_quoted(match))
            pending = group = ""
            continue
        if match:
            kind = "formula" if match["keyword"] == "brew" else "cask"
            if kind == "cask":
                if pending:
                    group, pending = pending, ""
            else:
                pending = group = ""
            declarations.append(
                Declaration(
                    kind,
                    _quoted(match),
                    _description(match),
                    group=group if kind == "cask" else "",
                )
            )
            continue
        match = MAS_ENTRY.fullmatch(line)
        if match:
            pending = group = ""
            declarations.append(
                Declaration(
                    "mas", _quoted(match), _description(match), identifier=match["id"]
                )
            )
            continue
        _fail(source, number, f"not a literal Brewfile declaration: {line.strip()}")
    return Brewfile(tuple(taps), tuple(declarations))


# uv identifies an installed tool by its own version, so an unpinned --with
# package could change under a declaration that did not.
def _extras(source, number, name, options):
    if not name.startswith("pipx:") or "uvx_args" not in options:
        return ()
    args = shlex.split(options["uvx_args"])
    extras = []
    for index, arg in enumerate(args):
        if arg == "--with":
            if index + 1 == len(args):
                _fail(source, number, f"{name} ends uvx_args with --with")
            requirement = args[index + 1]
        elif arg.startswith("--with="):
            requirement = arg.removeprefix("--with=")
        else:
            continue
        package, separator, version = requirement.partition("==")
        if not package or not separator or not version:
            _fail(
                source,
                number,
                f"{name} needs an exact == version for --with {requirement}",
            )
        extras.append((package, version))
    return tuple(extras)


def _tool_lines(text, source):
    """Yield (line number, match) for each declaration line in [tools]."""
    in_tools = seen_tools = False
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("["):
            section = SECTION.fullmatch(stripped)
            name = section["name"] if section else ""
            if name.startswith("tools.") or (name == "tools" and stripped[1] == "["):
                _fail(source, number, f"tools may not use sub-tables: {stripped}")
            in_tools = name == "tools"
            seen_tools = seen_tools or in_tools
            continue
        if not in_tools or not stripped or stripped.startswith("#"):
            continue
        match = TOOL_ENTRY.fullmatch(line)
        if match is None:
            _fail(
                source,
                number,
                f"not a one-line Mise declaration with a version string: {stripped}",
            )
        yield number, match
    if not seen_tools:
        raise DeclarationError(f"{source}: declares no [tools] table")


def parse_mise_config(text, source="mise/config.toml"):
    """Return the declarations in a Mise config's [tools] table."""
    try:
        document = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise DeclarationError(f"{source}: invalid TOML: {error}") from error
    declarations, values = [], {}
    for number, match in _tool_lines(text, source):
        entry = tomllib.loads(f"{match['key']} = {match['value']}")
        name, value = next(iter(entry.items()))
        options = {}
        if isinstance(value, dict):
            options = {key: item for key, item in value.items() if key != "version"}
            version = value.get("version")
            if version is None:
                _fail(source, number, f"{name} declares no version")
        else:
            version = value
        if not version:
            _fail(source, number, f"{name} declares an empty version")
        values[name] = value
        declarations.append(
            Declaration(
                "mise",
                name,
                _description(match),
                version=version,
                options=tuple(options.items()),
                extras=_extras(source, number, name, options),
            )
        )
    if values != document.get("tools"):
        raise DeclarationError(
            f"{source}: [tools] holds declarations outside its one-line entries"
        )
    return tuple(declarations)


def read_brewfile(path):
    return parse_brewfile(Path(path).read_text(), str(path))


def read_mise_config(path):
    return parse_mise_config(Path(path).read_text(), str(path))


def rewrite_versions(text, versions, source="mise/config.toml"):
    """Change only the selected declarations' version values in config text."""
    parse_mise_config(text, source)
    for name, version in versions.items():
        if not version or re.search(r'["\\\n]', version):
            raise DeclarationError(
                f"{source}: {name} cannot declare version {version!r}"
            )
    lines = text.splitlines(keepends=True)
    found = set()
    for number, match in _tool_lines(text, source):
        key = match["key"]
        name = json.loads(key) if key.startswith('"') else key
        if name not in versions:
            continue
        value = match["value"]
        if value.startswith("{"):
            pair = next(
                pair
                for pair in re.finditer(TOML_PAIR, value)
                if pair["key"] == "version"
            )
            start, end = pair.span("string")
        else:
            start, end = 1, len(value) - 1
        value = value[:start] + versions[name] + value[end:]
        line = lines[number - 1]
        lines[number - 1] = (
            line[: match.start("value")] + value + line[match.end("value") :]
        )
        found.add(name)
    missing = set(versions) - found
    if missing:
        raise DeclarationError(
            f"{source}: selected declarations are missing: {', '.join(sorted(missing))}"
        )
    rewritten = "".join(lines)
    current = {d.name: d.version for d in parse_mise_config(rewritten, source)}
    if any(current[name] != version for name, version in versions.items()):
        raise DeclarationError(f"{source}: a version rewrite did not take effect")
    return rewritten


CATALOG_KINDS = {
    "homebrew-formulae": "formula",
    "homebrew-casks": "cask",
    "mac-app-store": "mas",
    "mise-tools": "mise",
}
COMMANDS = ("taps", *CATALOG_KINDS)


def catalog_rows(region, root):
    """Build a region's table cells directly from named declaration fields."""
    kind = CATALOG_KINDS[region]
    declarations = (
        read_mise_config(root / "mise/config.toml")
        if kind == "mise"
        else read_brewfile(root / "Brewfile").declarations
    )
    rows, groups = [], {}
    for declaration in declarations:
        if declaration.kind != kind:
            continue
        if not declaration.description:
            raise DeclarationError(f"{declaration.name} has no catalog description")
        name = f"`{declaration.name}`"
        if kind == "formula":
            rows.append((name, declaration.description))
        elif kind == "mas":
            rows.append((name, f"`{declaration.identifier}`", declaration.description))
        elif kind == "mise":
            rows.append((name, f"`{declaration.version}`", declaration.description))
        else:
            if not declaration.group:
                raise DeclarationError(f"cask {declaration.name} has no catalog group")
            groups.setdefault(declaration.group, []).append(name)
    if kind == "cask":
        # Preserve first-seen group order and declaration order within a group.
        return [(group, ", ".join(names)) for group, names in groups.items()]
    return rows


def main(argv):
    if len(argv) not in (1, 2) or argv[0] not in COMMANDS:
        print(
            f"Usage: declared_software.py {{{'|'.join(COMMANDS)}}} [repository-root]",
            file=sys.stderr,
        )
        return 2
    root = Path(argv[1]) if len(argv) == 2 else Path(__file__).resolve().parent.parent
    try:
        rows = (
            [(tap,) for tap in read_brewfile(root / "Brewfile").taps]
            if argv[0] == "taps"
            else catalog_rows(argv[0], root)
        )
        for row in rows:
            if any("\t" in field for field in row):
                raise DeclarationError(f"a field holds a tab: {row[0]}")
    except (OSError, DeclarationError) as error:
        print(f"declared_software: {error}", file=sys.stderr)
        return 1
    for row in rows:
        print("\t".join(row))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
