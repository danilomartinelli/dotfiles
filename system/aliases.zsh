# Modern file listing: prefer eza, fall back to GNU coreutils gls.
if (( $+commands[eza] )); then
  alias ls="eza --icons"
  alias l="eza -lAh --icons"
  alias ll="eza -l --icons"
  alias la='eza -A --icons'
  alias lt='eza --tree --icons'
elif (( $+commands[gls] )); then
  alias ls="gls -F --color"
  alias l="gls -lAh --color"
  alias ll="gls -l --color"
  alias la='gls -A --color'
fi

if (( $+commands[bat] )); then
  alias cat='bat'
fi
