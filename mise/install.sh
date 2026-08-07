#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_require_command mise

# Trust the linked global config so installs never prompt interactively.
MISE_CONFIG="${MISE_GLOBAL_CONFIG_FILE:-$HOME/.mise.toml}"
if [ -e "$MISE_CONFIG" ]; then
  mise trust "$MISE_CONFIG" >/dev/null 2>&1 || true
fi

installer_banner "Installing Mise runtimes"
if mise install; then
  installer_success "Mise runtimes installed successfully"
else
  installer_error "Failed to install Mise runtimes"
  exit 1
fi

# Remove runtimes no longer declared and stale patch versions.
mise prune --yes >/dev/null 2>&1 || true

# Run the claude-code postinstall to place the native arm64 binary.
# npm install -g does not run postinstall scripts automatically when mise
# shells out to npm (npm.shell_out = true), so we invoke install.cjs directly.
# The script is idempotent: it skips the copy when the binary is already present.
clause_install_cjs=$(mise where npm:@anthropic-ai/claude-code 2>/dev/null)/lib/node_modules/@anthropic-ai/claude-code/install.cjs
if [ -f "$clause_install_cjs" ]; then
  installer_banner "Running claude-code postinstall"
  if node "$clause_install_cjs" >/dev/null 2>&1; then
    installer_success "claude native binary installed"
  else
    installer_warn "claude postinstall failed — run manually: node $clause_install_cjs"
  fi
fi

# Fix opencode native binary when the aube installer leaves the stub in place.
# The postinstall.mjs calls npm internally which can fail when ~/.npm has
# root-owned files. We bypass it by hard-linking the platform binary directly.
opencode_install_dir=$(mise where npm:opencode-ai 2>/dev/null)
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
