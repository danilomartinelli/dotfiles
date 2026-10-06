#!/bin/sh
# File-type claims for topics with an _associations.tsv catalog.
# Source after installer-preamble.sh, only in topics that claim file types.

# shellcheck source=_scripts/file-associations-rules.sh
. "$DOTFILES_ROOT/_scripts/file-associations-rules.sh"

# Check even an already-claimed catalog, before the run-once gate. Derive the
# key from the topic so installers never spell it. The run-once module records
# success and returns control to the installer.
# Usage: installer_claim_file_types <name> <bundle> <applied>
installer_claim_file_types() {
  _installer_assoc_catalog=$TOPIC_DIR/_associations.tsv

  if [ ! -r "$_installer_assoc_catalog" ]; then
    installer_fail "association catalog not readable: $_installer_assoc_catalog"
  fi

  if ! catalog_check "$_installer_assoc_catalog" associations_check_row; then
    installer_fail "invalid association catalog: $_installer_assoc_catalog"
  fi

  unset _installer_assoc_catalog

  installer_run_once "$(basename -- "$TOPIC_DIR")-associations" 'file associations' \
    _installer_apply_associations "$@"
  installer_success "$1 configured"
}

# Apply the checked catalog. A "report" row names and counts its failure; an
# "ignore" row is best-effort because Launch Services does not recognise every
# identifier on every macOS version. A "-" label falls back to the identifier.
_installer_apply_associations() {
  # Missing duti leaves the step armed. A previously applied claim does not
  # need duti just to report its marker.
  installer_optional_command duti \
    "duti is required to set $1 as the default app for its declared file types"

  _installer_assoc_name=$1
  _installer_assoc_bundle=$2
  _installer_assoc_success=$3
  _installer_assoc_failed=0

  catalog_each_row "$TOPIC_DIR/_associations.tsv" _installer_apply_association

  if [ "$_installer_assoc_failed" -eq 0 ]; then
    installer_success "$_installer_assoc_success"
  else
    installer_warn \
      "Some $_installer_assoc_name file associations could not be configured ($_installer_assoc_failed failed)"
  fi

  unset _installer_assoc_name _installer_assoc_bundle _installer_assoc_success \
    _installer_assoc_failed
}

# One association row, already checked. Counts into _installer_assoc_failed,
# which the caller owns, and always returns zero so a reported failure does not
# stop the run.
_installer_apply_association() {
  _installer_assoc_id=$1
  _installer_assoc_role=$2
  _installer_assoc_failure=$3
  _installer_assoc_label=$4

  if duti -s "$_installer_assoc_bundle" "$_installer_assoc_id" \
    "$_installer_assoc_role" 2>/dev/null; then
    return 0
  fi

  [ "$_installer_assoc_failure" = report ] || return 0

  if [ "$_installer_assoc_label" = '-' ]; then
    _installer_assoc_label=$_installer_assoc_id
  fi
  installer_warn \
    "Failed to set $_installer_assoc_name as default for $_installer_assoc_label"
  _installer_assoc_failed=$((_installer_assoc_failed + 1))
  return 0
}
