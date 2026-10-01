"""Reconcile pinned mdformat extras when Mise reuses an existing tool version."""

import json
from pathlib import Path
import shlex
import subprocess
import sys
import tomllib


def desired_extras(config):
    declaration = tomllib.loads(config.read_text())["tools"]["pipx:mdformat"]
    args = shlex.split(declaration.get("uvx_args", ""))
    extras = {}
    for index, arg in enumerate(args):
        if arg == "--with":
            package, separator, version = args[index + 1].partition("==")
            if not separator or not version:
                raise ValueError("mdformat extras must have explicit == version pins")
            extras[package] = version
    return extras


def installed_extras(directory, packages):
    # Use the formatter environment's interpreter, not the caller's Python:
    # importlib.metadata must see that tool's installed distributions.
    program = """
import importlib.metadata, json, sys
versions = {}
for package in json.loads(sys.argv[1]):
    try:
        versions[package] = importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
        versions[package] = None
print(json.dumps(versions))
"""
    interpreter = (directory / "bin/mdformat").resolve().parent / "python"
    result = subprocess.run(
        [str(interpreter), "-c", program, json.dumps(packages)],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise RuntimeError("could not inspect the installed mdformat environment")
    return json.loads(result.stdout)


def reconcile(config, directory):
    desired = desired_extras(config)
    if installed_extras(directory, list(desired)) == desired:
        print("Mise formatter extras match their declared pins")
        return
    print("Refreshing mdformat to apply its declared plugin versions")
    subprocess.run(
        ["mise", "install", "--force", "--locked", "pipx:mdformat"], check=True
    )
    if installed_extras(directory, list(desired)) != desired:
        raise RuntimeError("mdformat extras still differ from their declared pins")


if __name__ == "__main__":
    try:
        reconcile(Path(sys.argv[1]), Path(sys.argv[2]))
    except (
        OSError,
        ValueError,
        KeyError,
        IndexError,
        RuntimeError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"Mise formatter reconciliation failed: {error}", file=sys.stderr)
        sys.exit(1)
