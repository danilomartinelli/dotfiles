#!/bin/sh
# Reconcile installed packages after the installer's locked installation.

set -e

DOTFILES_ROOT=$(CDPATH='' cd -P -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=_scripts/installer-output.sh
# shellcheck disable=SC1091
. "$DOTFILES_ROOT/_scripts/installer-output.sh"
mise_policy=$DOTFILES_ROOT/_scripts/mise-policy

# Mise's installation identity is the main package version, so changed extras
# can otherwise remain stale even though the generated lock has new options.
mdformat_install_dir=$("$mise_policy" "$DOTFILES_ROOT" run where pipx:mdformat 2>/dev/null) || mdformat_install_dir=''
if [ -n "$mdformat_install_dir" ]; then
  installer_banner "Reconciling Mise formatter plugins"
  if ! "$mise_policy" "$DOTFILES_ROOT" run exec python -- python3 "$DOTFILES_ROOT/mise/_extras.py" \
    "$mdformat_install_dir"; then
    installer_error "Failed to reconcile Mise formatter plugins"
    exit 1
  fi
fi

# Pruning shares the same locked policy as installation and lookups.
"$mise_policy" "$DOTFILES_ROOT" run prune --yes >/dev/null 2>&1 || true

# Run the claude-code postinstall to place the native arm64 binary.
# npm install -g does not run postinstall scripts automatically when mise
# shells out to npm (npm.shell_out = true), so we invoke install.cjs directly.
# Repeat runs still invoke the package script; it owns its own idempotence.
# `mise where` fails for a tool that is not installed, and under `set -e` a
# failed substitution would end the run here without a word, so an absent tool
# resolves to no directory and its step is skipped.
claude_install_dir=$("$mise_policy" "$DOTFILES_ROOT" run where npm:@anthropic-ai/claude-code 2>/dev/null) || claude_install_dir=''
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
opencode_install_dir=$("$mise_policy" "$DOTFILES_ROOT" run where npm:opencode-ai 2>/dev/null) || opencode_install_dir=''
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
