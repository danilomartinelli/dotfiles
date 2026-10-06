"""Reconcile pinned mdformat extras when Mise reuses an existing tool version."""

import json
from pathlib import Path
import subprocess
import sys

# Importing the declaration reader must not leave a __pycache__ in the checkout.
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "_scripts"))
import declared_software  # noqa: E402


def desired_extras(config):
    # The module refuses a --with that does not name an exact == version.
    for declaration in declared_software.read_mise_config(config):
        if declaration.name == "pipx:mdformat":
            return dict(declaration.extras)
    raise KeyError("pipx:mdformat is not declared")


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


def reconcile(checkout, directory):
    desired = desired_extras(checkout / "mise/config.toml")
    if installed_extras(directory, list(desired)) == desired:
        print("Mise formatter extras match their declared pins")
        return
    print("Refreshing mdformat to apply its declared plugin versions")
    subprocess.run(
        [str(checkout / "_scripts/mise-policy"), str(checkout),
         "run", "install", "--force", "pipx:mdformat"], check=True
    )
    if installed_extras(directory, list(desired)) != desired:
        raise RuntimeError("mdformat extras still differ from their declared pins")


if __name__ == "__main__":
    try:
        reconcile(Path(__file__).resolve().parent.parent, Path(sys.argv[1]))
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
