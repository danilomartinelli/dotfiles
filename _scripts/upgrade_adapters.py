"""External effects used by the controlled upgrade."""

import json
import os
import shutil
import subprocess
import sys
import urllib.request


class SubprocessCommands:
    def run(self, args, *, cwd=None, env, capture=True, input=None, timeout=None):
        return subprocess.run(
            args, cwd=cwd, env=env, text=True, capture_output=capture,
            input=input, timeout=timeout,
        )

    def find(self, name, env):
        return shutil.which(name, path=env.get("PATH"))

    def is_root(self):
        return os.geteuid() == 0


class OsvAdvisories:
    def lookup(self, queries):
        request = urllib.request.Request(
            "https://api.osv.dev/v1/querybatch",
            data=json.dumps({"queries": queries}).encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)["results"]


class TerminalInteraction:
    def __init__(self, commands):
        self.commands = commands

    def interactive(self):
        return sys.stdin.isatty() and sys.stdout.isatty()

    def available(self, env):
        return self.commands.find("fzf", env) is not None

    def pick(self, rows, env):
        return self.commands.run(
            [
                "fzf",
                "--multi",
                "--delimiter=\t",
                "--with-nth=2..",
                "--no-sort",
                "--wrap",
                "--bind=space:toggle,ctrl-a:select-all,ctrl-d:deselect-all",
                "--header=Upgrades | Tab/Space: select | Ctrl-A: all | Enter: review | Esc: skip",
                "--prompt=Upgrade> ",
            ],
            input="\n".join(rows),
            env={**env, "FZF_DEFAULT_OPTS": "", "FZF_DEFAULT_OPTS_FILE": ""},
        )

    def confirm(self, prompt):
        return input(prompt)
