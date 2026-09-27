#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_command mise

MISE_CONFIG_DIR=$(installer_config_dir mise)
MISE_GLOBAL_CONFIG_FILE=$MISE_CONFIG_DIR/config.toml
export MISE_CONFIG_DIR MISE_GLOBAL_CONFIG_FILE

installer_link_tool_config mise "Mise config" config.toml
installer_link_tool_config mise "Mise lock" mise.lock

remove_legacy_link() {
  legacy_path=$1
  legacy_source=$2

  [ -L "$legacy_path" ] || return 0

  legacy_target=$(readlink "$legacy_path") || return 0
  case "$legacy_target" in
    /*) ;;
    *) legacy_target=$(dirname -- "$legacy_path")/$legacy_target ;;
  esac

  legacy_target_dir=$(CDPATH='' cd -P -- "$(dirname -- "$legacy_target")" 2>/dev/null && pwd) || return 0
  legacy_target=$legacy_target_dir/$(basename -- "$legacy_target")
  legacy_source_dir=$(CDPATH='' cd -P -- "$(dirname -- "$legacy_source")" 2>/dev/null && pwd) || return 0
  legacy_source=$legacy_source_dir/$(basename -- "$legacy_source")

  if [ "$legacy_target" = "$legacy_source" ]; then
    rm -f "$legacy_path"
    installer_note "Removed legacy Mise link $legacy_path"
  fi
}

remove_legacy_link "$HOME/.mise.toml" "$TOPIC_DIR/mise.toml.symlink"
remove_legacy_link "$HOME/.mise.lock" "$TOPIC_DIR/mise.lock.symlink"

# Trust the linked global config so installs never prompt interactively.
mise trust "$MISE_CONFIG_DIR/config.toml" >/dev/null 2>&1 || true

# Install exactly what the lock records and never write it. A plain install
# rewrites the lock into a shape `mise lock` does not produce, so every run
# dirtied the tree; see docs/adr/0020-dot-installs-what-the-mise-lock-records.md.
installer_banner "Installing Mise runtimes"
if mise install --locked; then
  installer_success "Mise runtimes installed successfully"
else
  installer_error "Failed to install Mise runtimes"
  installer_hint "If a declaration changed, run 'mise lock --global' from $DOTFILES_ROOT and commit mise/mise.lock."
  exit 1
fi

# Remove runtimes no longer declared and stale patch versions.
mise prune --yes >/dev/null 2>&1 || true

# Run the claude-code postinstall to place the native arm64 binary.
# npm install -g does not run postinstall scripts automatically when mise
# shells out to npm (npm.shell_out = true), so we invoke install.cjs directly.
# The script is idempotent: it skips the copy when the binary is already present.
# `mise where` fails for a tool that is not installed, and under `set -e` a
# failed substitution would end the run here without a word, so an absent tool
# resolves to no directory and its step is skipped.
claude_install_dir=$(mise where npm:@anthropic-ai/claude-code 2>/dev/null) || claude_install_dir=''
claude_install_cjs=$claude_install_dir/lib/node_modules/@anthropic-ai/claude-code/install.cjs
if [ -n "$claude_install_dir" ] && [ -f "$claude_install_cjs" ]; then
  installer_banner "Running claude-code postinstall"
  if node "$claude_install_cjs" >/dev/null 2>&1; then
    installer_success "claude native binary installed"
  else
    installer_warn "claude postinstall failed — run manually: node $claude_install_cjs"
  fi
fi

# Fix opencode native binary when the aube installer leaves the stub in place.
# The postinstall.mjs calls npm internally which can fail when ~/.npm has
# root-owned files. We bypass it by hard-linking the platform binary directly.
opencode_install_dir=$(mise where npm:opencode-ai 2>/dev/null) || opencode_install_dir=''
if [ -n "$opencode_install_dir" ]; then
  opencode_exe=$(find "$opencode_install_dir" \
    -name opencode.exe -path "*/opencode-ai/bin/opencode.exe" 2>/dev/null | head -1)
  opencode_native=$(find "$opencode_install_dir" \
    -name opencode -path "*/opencode-darwin-arm64/bin/opencode" 2>/dev/null | head -1)
  if [ -f "$opencode_exe" ] && [ -f "$opencode_native" ] && ! file "$opencode_exe" | grep -q 'Mach-O'; then
    installer_banner "Fixing opencode native binary"
    if ln -f "$opencode_native" "$opencode_exe" 2>/dev/null || cp "$opencode_native" "$opencode_exe"; then
      chmod +x "$opencode_exe"
      installer_success "opencode native binary installed"
    else
      installer_warn "opencode binary fix failed — run: mise reinstall npm:opencode-ai"
    fi
  fi
fi
