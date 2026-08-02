# GRC colorizes nifty unix tools all over the place
if (( $+commands[grc] )) && [[ -r "$HOMEBREW_PREFIX/etc/grc.bashrc" ]]
then
  source "$HOMEBREW_PREFIX/etc/grc.bashrc"
fi
