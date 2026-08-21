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
