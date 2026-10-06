"""Recorded command replies; unexpected commands fail instead of running tools."""

from collections import deque
from dataclasses import dataclass
import subprocess


@dataclass
class Reply:
    args: list
    stdout: str = ""
    status: int = 0
    stderr: str = ""
    effect: object = None
    capture: bool = True


class Commands:
    def __init__(self, replies=()):
        self.replies = deque(replies)
        self.events = []
        self.executables = {"mas": "/fixture/bin/mas", "fzf": "/fixture/bin/fzf"}
        self.root_user = False

    def run(self, args, *, cwd=None, env, capture=True, input=None, timeout=None):
        if not self.replies:
            raise AssertionError(f"unexpected command: {args}")
        reply = self.replies.popleft()
        # A recording can name the temporary working directory by role.
        staged = any("<stage>" in arg for arg in reply.args)
        normalized = [arg.replace(str(cwd), "<stage>") for arg in args] if staged else args
        if normalized != reply.args or capture != reply.capture:
            raise AssertionError(f"expected {reply.args} capture={reply.capture}; got {normalized} capture={capture}")
        self.events.append((args, cwd, env, capture, input, timeout))
        if reply.effect:
            reply.effect(cwd)
        return subprocess.CompletedProcess(args, reply.status, reply.stdout, reply.stderr)

    def find(self, name, env):
        return self.executables.get(name)

    def is_root(self):
        return self.root_user


class Advisories:
    def __init__(self):
        self.queries = []
        self.results = None
        self.error = None

    def lookup(self, queries):
        self.queries.extend(queries)
        if self.error:
            raise self.error
        return self.results if self.results is not None else [{} for _ in queries]


class Interaction:
    def __init__(self, *, interactive=False, selected=(), answer="no"):
        self.has_terminal = interactive
        self.selected = selected
        self.answer = answer
        self.has_picker = True
        self.status = 0
        self.rows = None
        self.picks = 0

    def interactive(self):
        return self.has_terminal

    def available(self, env):
        return self.has_picker

    def pick(self, rows, env):
        self.picks += 1
        output = self.rows if self.rows is not None else "\n".join(rows[i] for i in self.selected)
        return subprocess.CompletedProcess(["fzf"], self.status, output, "picker failure")

    def confirm(self, prompt):
        return self.answer
