#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-mise-post-install-tests

scenario_run 'post-install reconciliation preserves repair outcomes' \
  python3 -B "$TEST_DIR/_support/mise-post-install.py"
scenario_finish
