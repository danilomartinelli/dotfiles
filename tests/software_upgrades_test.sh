#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-software-upgrades-tests

scenario_run 'interactive software upgrades preserve selection and source boundaries' \
  python3 -B "$TEST_DIR/_support/software-upgrades.py"
scenario_finish
