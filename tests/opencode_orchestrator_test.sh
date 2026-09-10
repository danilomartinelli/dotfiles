#!/usr/bin/env bash

set -u

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
scenario_init dotfiles-opencode-orchestrator-tests

test_module_contracts() {
  bun test "$TEST_DIR"/opencode_*.test.ts
}

test_module_types() {
  bun run --cwd "$REPOSITORY_ROOT/opencode/orchestrator" check
}

scenario_run 'orchestrator behavior in isolated fixtures' test_module_contracts
scenario_run 'orchestrator types against the pinned OpenCode SDK' test_module_types
scenario_finish
