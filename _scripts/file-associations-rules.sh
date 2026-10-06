#!/bin/sh
# Sourced after catalog.sh by file-associations.sh and the tracked-catalog
# rules suite, which validates catalogs without loading an installer.

# What an association row must satisfy on its text alone. Whether Launch
# Services knows the identifier is a fact about this machine, which is what the
# failure mode is for. Roles are duti's.
# Usage: catalog_check <catalog> associations_check_row
associations_check_row() {
  case $2 in
    '') catalog_reject 'missing role' ;;
    all | viewer | editor | shell | none) ;;
    *) catalog_reject "unknown role '$2'" ;;
  esac

  # An unknown mode is a catalog bug, and defaulting it either way would
  # decide silently whether a failure is heard.
  case $3 in
    '') catalog_reject 'missing failure mode' ;;
    report | ignore) ;;
    *) catalog_reject "unknown failure mode '$3'" ;;
  esac

  [ -n "$4" ] || catalog_reject "missing label (use '-' for the identifier)"
  [ -z "$2" ] || catalog_reject_duplicate "$1" "$2"

  return 0
}
