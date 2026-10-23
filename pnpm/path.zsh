# pnpm v11+ links global executables below PNPM_HOME/bin. PNPM_HOME itself
# can still hold the standalone pnpm executable and legacy global commands.
# Declare both here so `pnpm add -g` works without `pnpm setup` rewriting
# the managed ~/.zshrc link.
#
# ~/Library/pnpm is pnpm's own default on macOS, so this matches what
# `pnpm setup` would have written to the shell profile — declared here
# instead, so the setting is tracked and survives a fresh machine.
#
# Lives in path.zsh rather than env.zsh because path.zsh is sourced first:
# the PATH entries below depend on PNPM_HOME already being exported.
export PNPM_HOME="${PNPM_HOME:-$HOME/Library/pnpm}"

# Startup owns global command precedence and makes path unique.
path=("$PNPM_HOME/bin" "$PNPM_HOME" "${path[@]}")
