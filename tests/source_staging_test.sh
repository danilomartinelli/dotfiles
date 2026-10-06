#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-source-staging-tests

scenario_run 'source publication preserves edits and recovers from write failures' \
  python3 -B "$TEST_DIR/_support/source-staging.py"
scenario_finish
