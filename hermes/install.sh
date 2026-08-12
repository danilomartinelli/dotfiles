#!/bin/sh

set -e

# shellcheck disable=SC1091
. "$(CDPATH='' cd -P -- "$(dirname -- "$0")/../_scripts" && pwd)/installer-preamble.sh"

installer_banner "setting up Hermes Agent"

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_DEFAULT_MODEL="${HERMES_DEFAULT_MODEL:-anthropic/claude-opus-5}"

mkdir -p "$HERMES_HOME"

if ! command -v hermes >/dev/null 2>&1; then
  installer_note "Install Hermes with: brew install hermes-agent"
  installer_note "Put provider API keys in ~/.localrc (see .localrc.example)"
  installer_success "Hermes Agent configured"
  exit 0
fi

installer_success "hermes CLI available"

# Set a default model only when none is configured. Forcing it on every run
# would silently undo a model picked interactively with `hermes model`.
current_model=$(hermes config get model 2>/dev/null | tail -1 || true)
case "$current_model" in
"" | *"not set"* | *"(auto)"*)
  hermes config set model "$HERMES_DEFAULT_MODEL" >/dev/null 2>&1 &&
    installer_success "Default model set to $HERMES_DEFAULT_MODEL"
  ;;
*)
  installer_note "Model already set to $current_model"
  ;;
esac

installer_note "Put provider API keys in ~/.localrc (see .localrc.example)"
installer_note "Change provider/model interactively with: hermes model"
installer_success "Hermes Agent configured"
