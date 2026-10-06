#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-software-upgrades-tests

scenario_run 'interactive software upgrades preserve selection and source boundaries' \
  python3 -B "$TEST_DIR/_support/software-upgrades.py"
scenario_run 'production terminal and advisory adapters preserve their contracts' \
  python3 -B "$TEST_DIR/_support/upgrade-adapters.py"
scenario_run 'the controlled upgrade composes production adapters and Mise policy' \
  python3 -B "$TEST_DIR/_support/software-upgrade-smoke.py"
scenario_finish
