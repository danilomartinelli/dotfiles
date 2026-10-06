#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-mise-policy-tests

scenario_run 'Mise callers share configuration, trust, and lock policy' \
  python3 -B "$TEST_DIR/_support/mise-policy.py"

scenario_finish
