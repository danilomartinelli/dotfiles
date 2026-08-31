# shellcheck shell=sh
#
# The envelope every explicit key-creation command shares.
#
# ssh/create-key and sops/create-key differ in three things: which role maps to
# which paths, which generator runs, and what to tell a person afterwards.
# Everything around that — the usage and help guards, the refusal to touch
# existing key material, the private directory, and propagating the generator's
# own exit status — is one contract, and it is the contract that must not drift
# between two commands that both create credentials.
#
# This is a set of guards rather than one entry point on purpose. The two
# commands agree on every invariant below and disagree on their order: sops
# derives a second file from what its generator printed, ssh derives a comment
# from the Git identity before its generator runs. An entry point covering both
# would take a callback per step, which is a wider interface than the guards it
# replaced. POSIX sh has no closures, so a generator is passed by name and
# invoked through "$@".
#
# Every variable here carries the _kp_ prefix. POSIX sh has no function locals,
# so an unprefixed name would assign into the sourcing script: key_path is the
# name both callers already use for the private key, and a loop over it left
# ssh/create-key running chmod against its own public key.

# Report a usage error against the caller's program name and stop.
# Usage: key_usage_error <program> <usage-function> <message>...
key_usage_error() {
  _kp_program=$1
  _kp_usage_fn=$2
  shift 2
  echo "$_kp_program: $*" >&2
  "$_kp_usage_fn" >&2
  exit 2
}

# Answer -h/--help, and reject a help flag carrying extra arguments, so every
# key command answers the same way.
# Usage: key_handle_help <program> <usage-function> "$@"
key_handle_help() {
  _kp_help_program=$1
  _kp_help_usage_fn=$2
  shift 2

  case ${1:-} in
    -h | --help)
      [ "$#" -eq 1 ] \
        || key_usage_error "$_kp_help_program" "$_kp_help_usage_fn" \
          '--help does not accept additional arguments'
      "$_kp_help_usage_fn"
      exit 0
      ;;
  esac
}

# Stop unless the generator this command needs is on PATH.
# Usage: key_require_generator <program> <tool> [install-hint]
key_require_generator() {
  # An `&&` list would carry the probe's own nonzero status out of the
  # function, and every caller runs under set -e, so the script would die here
  # without printing why.
  if command -v "$2" >/dev/null 2>&1; then
    return 0
  fi

  echo "$1: $2 is required but was not found" >&2
  [ "$#" -lt 3 ] || echo "  Install with: $3" >&2
  exit 1
}

# Refuse when any named path already exists. This repository never rotates
# credentials, so a command that would overwrite one stops before its generator
# runs rather than after. A symlink counts: what matters is that something is
# already there, not what it is.
# Usage: key_refuse_existing <program> <noun> <path>...
key_refuse_existing() {
  _kp_refuse_program=$1
  _kp_refuse_noun=$2
  shift 2

  for _kp_refuse_path in "$@"; do
    if [ -e "$_kp_refuse_path" ] || [ -L "$_kp_refuse_path" ]; then
      echo "$_kp_refuse_program: refusing to overwrite existing $_kp_refuse_noun for $_kp_refuse_path" >&2
      exit 1
    fi
  done
}

# Create the directory key material lands in, private from the moment it exists.
# Usage: key_prepare_dir <directory>
key_prepare_dir() {
  umask 077
  mkdir -p "$1"
  chmod 700 "$1"
}

# Run one generator and stop with the generator's own status when it fails,
# rather than flattening it to 1: a caller reading the failure wants to know
# what ssh-keygen or age-keygen actually returned. The generator reports its own
# diagnostics, because only it knows whether it captured them.
# Usage: key_run_generator <program> <tool> <path> <generator-fn> [arg]...
key_run_generator() {
  _kp_run_program=$1
  _kp_run_tool=$2
  _kp_run_path=$3
  shift 3

  _kp_run_status=0
  "$@" || _kp_run_status=$?
  if [ "$_kp_run_status" -ne 0 ]; then
    echo "$_kp_run_program: $_kp_run_tool failed for $_kp_run_path" >&2
    exit "$_kp_run_status"
  fi
}
