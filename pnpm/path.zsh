# pnpm keeps globally installed packages in PNPM_HOME and links their
# executables there. Without the variable, `pnpm add -g` and `pnpm setup`
# fail with ERR_PNPM_NO_GLOBAL_BIN_DIR, because pnpm refuses to guess a
# location that may not be on PATH.
#
# ~/Library/pnpm is pnpm's own default on macOS, so this matches what
# `pnpm setup` would have written to the shell profile — declared here
# instead, so the setting is tracked and survives a fresh machine.
#
# Lives in path.zsh rather than env.zsh because path.zsh is sourced first:
# the PATH entry below depends on PNPM_HOME already being exported.
export PNPM_HOME="${PNPM_HOME:-$HOME/Library/pnpm}"

export PATH="$PNPM_HOME:$PATH"
