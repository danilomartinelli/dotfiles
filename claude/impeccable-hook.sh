#!/bin/sh
#
# Run Impeccable's hook only in a project that has opted in.
#
# Claude Code has no way to limit a user-level hook to certain projects, so
# every Edit, Write and Stop in every project would otherwise start the design
# detector. A root DESIGN.md is the file Impeccable itself keeps a project's
# design system in, so its presence is the opt-in. The hook's input arrives on
# stdin and is passed through untouched.
#
# claude/install.sh links this file to ~/.claude/impeccable-hook.sh, the path
# the hooks in claude/settings.json name.

set -eu

impeccable=$HOME/.claude/skills/impeccable/scripts/impeccable
project=${CLAUDE_PROJECT_DIR:-$PWD}

[ -f "$project/DESIGN.md" ] || exit 0
[ -x "$impeccable" ] || exit 0

exec "$impeccable" hook
