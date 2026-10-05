---
status: accepted
---

# Classify shells by who reads their output

Conductor parses Git diagnostics and coding agents rely on the standard output
of commands such as `ls` and `cat`, so a shell's locale and command replacements
depend on whether a person or a program reads its output. Each Zsh shell is
classified once, in `~/.zshenv`, the one startup file read by every shell not
started with `-f`, including agent command shells that skip `~/.zshrc`. A shell
whose standard output is a terminal is a person's shell and gets the pt-BR
locale and the interactive replacements; any other shell is a tool shell and
gets an English locale with C messages and the standard commands. Later startup
files read the classification instead of deciding for themselves, and it is
never exported, so no shell inherits another shell's answer.

## Considered options

Markers set by the app or agent that opened a shell, such as
`__CFBundleIdentifier`, `CLAUDECODE`, `CODEX_SHELL` and `OPENCODE`, name who
opened it, not who reads it. Conductor's integrated terminal carries the same
bundle identifier as the shell Conductor runs to capture its environment,
OpenCode's integrated terminal inherits `OPENCODE`, and Codex never set
`CODEX_SHELL`, so its tool shells received the replacements that marker was
meant to withhold.

## Consequences

A person's subshells without a terminal, such as command substitutions and
launchd jobs, get the tool locale. A shell that skipped `~/.zshenv` is treated
as a person's shell. `~/.localrc` does not set the locale, because the shell
Conductor captures runs it after the classification. Kimi Code runs its tool
shells in Bash, outside this policy.
