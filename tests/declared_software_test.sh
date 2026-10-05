#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-declared-software-tests

scenario_run 'declared software is read from closed literal declarations' \
  python3 -B "$TEST_DIR/_support/declared-software.py"
scenario_finish
