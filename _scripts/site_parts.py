"""Render the runners of the public page from the declared software.

The page at _site/index.html shows each declared tool as a numbered part on
one of three runners. A part's name and description come from Brewfile and
mise/config.toml through declared_software.py, the reading the README catalog
is rendered from, and the part links to the line that declares it.

Versions stay off the page. An upgrade rewrites them in place, so a page that
showed them would go stale with every upgrade; a line number only moves when
the file's lines do.

_scripts/render-software-catalog --page calls this once per generated region
and prints that runner's count and part lists as HTML:

  site_parts.py {command-line-tools|applications-and-fonts|runtimes-and-clis} [repository-root]
"""

from html import escape
from pathlib import Path
import sys

# Importing the declaration reader must not leave a __pycache__ in the checkout.
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import declared_software  # noqa: E402

DeclarationError = declared_software.DeclarationError

SOURCE_URL = "https://github.com/danilomartinelli/dotfiles/blob/main"
BREWFILE = "Brewfile"
MISE_CONFIG = "mise/config.toml"
# The App Store app has no cask group; it closes the runner under its own.
APP_STORE_GROUP = "Mac App Store"

# A region names its runner letter, its source file, and the declaration kinds
# it holds. The letter is the prefix of every part number on that runner.
RUNNERS = {
    "command-line-tools": ("A", BREWFILE, ("formula",)),
    "applications-and-fonts": ("B", BREWFILE, ("cask", "mas")),
    "runtimes-and-clis": ("C", MISE_CONFIG, ("mise",)),
}


def describe(declaration):
    """Return a description as HTML, with its backtick spans as code."""
    if not declaration.description:
        raise DeclarationError(f"{declaration.name} has no catalog description")
    pieces = declaration.description.split("`")
    if len(pieces) % 2 == 0:
        raise DeclarationError(
            f"{declaration.name} has an unclosed backtick in its description"
        )
    return "".join(
        f"<code>{escape(piece)}</code>" if index % 2 else escape(piece)
        for index, piece in enumerate(pieces)
    )


def name_of(declaration):
    """Return a name as HTML that may wrap after a path or backend separator."""
    return escape(declaration.name).replace("/", "/<wbr>").replace(":", ":<wbr>")


def group_of(declaration):
    if declaration.kind == "mas":
        return APP_STORE_GROUP
    if declaration.kind == "cask" and not declaration.group:
        raise DeclarationError(f"cask {declaration.name} has no catalog group")
    return declaration.group


def runner_lines(region, root):
    """Return the HTML lines of one runner: its count, then its part lists."""
    letter, source, kinds = RUNNERS[region]
    declarations = (
        declared_software.read_mise_config(root / source)
        if source == MISE_CONFIG
        else declared_software.read_brewfile(root / source).declarations
    )
    # Preserve first-seen group order and declaration order within a group.
    groups = {}
    for declaration in declarations:
        if declaration.kind in kinds:
            groups.setdefault(group_of(declaration), []).append(declaration)

    count = sum(len(members) for members in groups.values())
    lines = [
        f'<p class="runner-count"><b>{count}</b> parts</p>',
        '<div class="part-sets">',
    ]
    number = 0
    for group, members in groups.items():
        lines.append('<div class="part-set">')
        if group:
            lines.append(f'<h3 class="part-group">{escape(group)}</h3>')
        lines.append('<ul class="parts">')
        for declaration in members:
            number += 1
            # The name's length lets the page keep a part near its own width.
            lines.append(
                f'<li style="--name: {len(declaration.name)}">'
                f'<a class="part" href="{SOURCE_URL}/{source}#L{declaration.line}">'
                f'<span class="part-no">{letter}{number}</span> '
                f'<span class="part-name">{name_of(declaration)}</span></a> '
                f'<span class="part-use">{describe(declaration)}</span></li>'
            )
        lines.extend(("</ul>", "</div>"))
    lines.append("</div>")
    return lines


def main(argv):
    if len(argv) not in (1, 2):
        print(
            f"Usage: site_parts.py {{{'|'.join(RUNNERS)}}} [repository-root]",
            file=sys.stderr,
        )
        return 2
    if argv[0] not in RUNNERS:
        print(f"site_parts: unknown generated region: {argv[0]}", file=sys.stderr)
        return 1
    root = Path(argv[1]) if len(argv) == 2 else Path(__file__).resolve().parent.parent
    try:
        lines = runner_lines(argv[0], root)
    except (OSError, DeclarationError) as error:
        print(f"site_parts: {error}", file=sys.stderr)
        return 1
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
