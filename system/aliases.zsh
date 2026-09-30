# Coding agents (Claude Code sets CLAUDECODE, Codex sets CODEX_SHELL) replay
# this startup into their tool shells and rely on the standard ls and cat flags
# and output, so these replacements are for a person's interactive shell only.
[[ -n ${CLAUDECODE-} || -n ${CODEX_SHELL-} ]] && return 0

# Modern file listing: prefer eza, fall back to GNU coreutils gls.
if (( $+commands[eza] )); then
  alias ls="eza --icons=auto"
  alias l="eza -lAh --icons=auto"
  alias ll="eza -l --icons=auto"
  alias la='eza -A --icons=auto'
  alias lt='eza --tree --icons=auto'
elif (( $+commands[gls] )); then
  alias ls="gls -F --color"
  alias l="gls -lAh --color"
  alias ll="gls -l --color"
  alias la='gls -A --color'
fi

if (( $+commands[bat] )); then
  alias cat='bat'
fi
