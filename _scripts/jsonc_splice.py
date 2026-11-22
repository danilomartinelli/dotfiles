#!/usr/bin/env python3
"""Replace one member's value in a JSONC document, leaving the rest as it is.

Usage: jsonc_splice.py <file> <key>[.<key>...] < value.json

Prints the document with the member at that path replaced by the JSON read
from stdin. Everything outside the member's value is preserved byte for byte,
comments included, which a parse and re-serialise could not do. The new value
is written the way the editors here format JSON: objects one member per line,
an array on one line when it fits in 80 columns.

Exits 1 when the path does not name a member of nested objects.
"""

import json
import sys

WIDTH = 80


def skip_trivia(text, index):
    """Return the index of the next character that is not space or comment."""
    while index < len(text):
        if text[index].isspace():
            index += 1
        elif text.startswith("//", index):
            end = text.find("\n", index)
            index = len(text) if end == -1 else end
        elif text.startswith("/*", index):
            end = text.find("*/", index)
            index = len(text) if end == -1 else end + 2
        else:
            break
    return index


def skip_string(text, index):
    """Return the index after the string starting at index."""
    index += 1
    while text[index] != '"':
        index += 2 if text[index] == "\\" else 1
    return index + 1


def skip_value(text, index):
    """Return the index after the value starting at index."""
    if text[index] == '"':
        return skip_string(text, index)
    if text[index] in "{[":
        depth = 0
        while True:
            index = skip_trivia(text, index)
            if text[index] == '"':
                index = skip_string(text, index)
                continue
            if text[index] in "{[":
                depth += 1
            elif text[index] in "}]":
                depth -= 1
                if depth == 0:
                    return index + 1
            index += 1
    while text[index] not in ",}] \t\r\n/":
        index += 1
    return index


def find_member(text, index, key):
    """Return (start, end) of the value of key in the object at index."""
    if text[index] != "{":
        raise KeyError(key)
    index = skip_trivia(text, index + 1)
    while text[index] != "}":
        name_end = skip_string(text, index)
        name = json.loads(text[index:name_end])
        index = skip_trivia(text, name_end)
        index = skip_trivia(text, index + 1)
        value_end = skip_value(text, index)
        if name == key:
            return index, value_end
        index = skip_trivia(text, value_end)
        if text[index] == ",":
            index = skip_trivia(text, index + 1)
    raise KeyError(key)


def render(value, indent):
    """Serialise value, with nested lines indented by indent spaces."""
    pad = " " * (indent + 2)
    if isinstance(value, dict):
        if not value:
            return "{}"
        members = [
            f"{pad}{json.dumps(name)}: {render(member, indent + 2)}"
            for name, member in value.items()
        ]
        return "{\n" + ",\n".join(members) + "\n" + " " * indent + "}"
    if isinstance(value, list):
        inline = "[" + ", ".join(json.dumps(item) for item in value) + "]"
        if all(not isinstance(item, (dict, list)) for item in value) and (
            indent + len(inline) <= WIDTH
        ):
            return inline
        items = [f"{pad}{render(item, indent + 2)}" for item in value]
        return "[\n" + ",\n".join(items) + "\n" + " " * indent + "]"
    return json.dumps(value)


def main(arguments):
    if len(arguments) != 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    path, keys = arguments[0], arguments[1].split(".")
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    value = json.load(sys.stdin)

    start, end = skip_trivia(text, 0), None
    try:
        for key in keys:
            start, end = find_member(text, start, key)
    except (KeyError, IndexError):
        print(f"jsonc_splice: no member {arguments[1]} in {path}", file=sys.stderr)
        return 1

    line_start = text.rfind("\n", 0, start) + 1
    indent = len(text[line_start:start]) - len(text[line_start:start].lstrip(" "))
    sys.stdout.write(text[:start] + render(value, indent) + text[end:])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
