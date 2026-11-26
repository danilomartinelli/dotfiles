#!/usr/bin/env bash

set -eu

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec node --test "$TEST_DIR/_support/herdr-panels.mjs" "$TEST_DIR/_support/herdr-findings.mjs"
