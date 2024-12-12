#!/usr/bin/env bash
### ----------------- Bootstrap post-installation scripts ----------------- ###
# Run by run_dotfile_scripts in bootstrap.sh
# Scripts must be executable (chmod +x)
echo "-> Running strap-after-setup. Some steps may require password entry."

### Configure macOS
if [ "${MACOS:-0}" -gt 0 ] || [ "$(uname)" = "Darwin" ]; then
  if [ "$STRAP_ADMIN" -gt 0 ]; then
    "$HOME"/.dotfiles/scripts/macos.sh
  else
    echo "Not admin. Skipping macos.sh. Set \$STRAP_ADMIN to run macos.sh."
  fi
fi

### Set shell
if [ "$STRAP_SUDO" -gt 0 ]; then
  case $SHELL in
  *zsh) echo "Shell is already set to Zsh." ;;
  *)
    if type zsh &>/dev/null; then
      echo "--> Changing shell to Zsh. Sudo required."
      [ "${LINUX:-0}" -gt 0 ] || [ "$(uname)" = "Linux" ] &&
        type -P zsh | sudo tee -a /etc/shells
      sudo chsh -s "$(type -P zsh)" "$USER"
    else
      echo "Zsh not found."
    fi
    ;;
  esac
else
  echo "Not sudo. Shell not changed. Set \$STRAP_SUDO to change shell."
fi
