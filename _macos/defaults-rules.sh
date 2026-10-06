#!/bin/sh
#
# What a macOS preference row must satisfy on its text alone.
#
# Sourced after _scripts/catalog.sh by _macos/set-defaults.sh, which checks the
# whole catalog before it writes the first preference, and by
# tests/catalog_rules_test.sh, which checks the tracked catalog without writing
# any.
#
# The value is checked against its type because `defaults write` does not:
# `-int abc` and `-float x1` both write 0 and `-int 1.5` writes 1, all with a
# zero exit status, so a typo becomes a wrong preference rather than an error.

# The placeholders a value honours, declared once. The applier expands through
# here and the rules reject through here, so no name can be accepted without
# also being expanded.
# Usage: defaults_placeholders <catalog_expand|catalog_reject_undeclared> <value>
defaults_placeholders() {
  "$1" "$2" HOME "$HOME"
}

# Usage: catalog_check <catalog> defaults_check_row
defaults_check_row() {
  [ -n "$2" ] || catalog_reject 'missing key'

  if [ -z "$4" ]; then
    catalog_reject 'missing value'
  fi

  case $3 in
    '') catalog_reject 'missing type' ;;
    bool)
      case $4 in
        '' | true | false) ;;
        *) catalog_reject "bool value is not true or false: '$4'" ;;
      esac
      ;;
    int)
      [ -z "$4" ] || _defaults_is_integer "$4" \
        || catalog_reject "int value is not an integer: '$4'"
      ;;
    float)
      [ -z "$4" ] || _defaults_is_number "$4" \
        || catalog_reject "float value is not a number: '$4'"
      ;;
    string)
      [ -z "$4" ] || defaults_placeholders catalog_reject_undeclared "$4"
      ;;
    *) catalog_reject "unknown type '$3'" ;;
  esac

  # -g is how `defaults` spells the global domain on the command line, so a
  # key declared under both names is declared twice.
  if [ -n "$2" ]; then
    case $1 in
      -g) catalog_reject_duplicate NSGlobalDomain "$2" ;;
      *) catalog_reject_duplicate "$1" "$2" ;;
    esac
  fi

  return 0
}

# An optional minus sign, then one or more digits.
_defaults_is_integer() {
  case ${1#-} in
    '' | *[!0-9]*) return 1 ;;
  esac
}

# An optional minus sign, then digits with at most one decimal point, and at
# least one digit somewhere.
_defaults_is_number() {
  _defaults_number=${1#-}
  case $_defaults_number in
    *.*.* | . | '' | *[!0-9.]*)
      unset _defaults_number
      return 1
      ;;
  esac
  unset _defaults_number
}
