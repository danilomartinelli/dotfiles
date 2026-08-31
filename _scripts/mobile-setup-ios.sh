#!/usr/bin/env bash
#
# Private iOS Simulator provisioning implementation for mobile-setup.

# The Mobile Readiness snapshot for the iOS target. ios_classify_state is the
# only writer, matching the shape the Android implementation already uses.
# install_ios reads this record rather than re-deriving it, which is what
# stopped it from carrying a second copy of check_ios's body and then calling
# check_ios as well.
#
# Two fields rather than Android's six, because iOS's conditions are sequential:
# no SDK without xcrun, no runtime listing without an SDK, no match without a
# listing. Exactly one of them can be the blocker, so the permitted action names
# it and separate condition flags would be write-only.
IOS_SDK_VERSION=''
IOS_NEXT_ACTION=select-full-xcode

read_ios_sdk_version() {
  local sdk_version

  if ! command -v xcrun >/dev/null 2>&1; then
    return 1
  fi

  sdk_version=$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null) \
    || return 1

  [ -n "$sdk_version" ] || return 1
  printf '%s\n' "$sdk_version"
}

read_ios_runtime_listing() {
  local runtime_listing

  runtime_listing=$(xcrun simctl list runtimes 2>/dev/null) || return 1
  printf '%s\n' "$runtime_listing"
}

ios_runtime_is_available() {
  local sdk_version=$1
  local runtime_listing=$2
  local runtime_line

  while IFS= read -r runtime_line; do
    case "$runtime_line" in
      "iOS ${sdk_version} "*)
        case "$runtime_line" in
          *'(unavailable'*) ;;
          *) return 0 ;;
        esac
        ;;
    esac
  done <<<"$runtime_listing"

  return 1
}

# Observe every condition, then commit the whole record at once, so a caller
# never reads a snapshot that is half this run and half the last one.
ios_classify_state() {
  local next_sdk_version=''
  local next_action
  local runtime_listing

  if ! command -v xcrun >/dev/null 2>&1; then
    next_action=select-full-xcode
  elif ! next_sdk_version=$(read_ios_sdk_version); then
    next_sdk_version=''
    next_action=select-full-xcode-sdk
  elif ! runtime_listing=$(read_ios_runtime_listing); then
    next_action=finish-xcode-setup
  elif ios_runtime_is_available "$next_sdk_version" "$runtime_listing"; then
    next_action=none
  else
    next_action=download-runtime
  fi

  IOS_SDK_VERSION=$next_sdk_version
  IOS_NEXT_ACTION=$next_action
}

# Print the verdict the record already decided. One place turns the snapshot
# into prose, so check and install cannot disagree about what a machine is.
report_ios_readiness() {
  case "$IOS_NEXT_ACTION" in
    none)
      printf 'iOS: ready — Simulator runtime matches iPhone SDK %s.\n' "$IOS_SDK_VERSION"
      return 0
      ;;
    select-full-xcode)
      printf 'iOS: incomplete — xcrun is unavailable; select a full Xcode installation.\n'
      print_next_step 'Complete Xcode first launch and license setup, then run: mobile-setup ios'
      ;;
    select-full-xcode-sdk)
      printf 'iOS: incomplete — the selected Xcode has no usable iPhone Simulator SDK.\n'
      print_next_step 'Select a full Xcode installation, finish its first launch, then run: mobile-setup ios'
      ;;
    finish-xcode-setup)
      printf 'iOS: incomplete — Xcode could not list Simulator runtimes.\n'
      print_next_step 'Finish Xcode first launch and license setup, then run: mobile-setup ios'
      ;;
    download-runtime)
      printf 'iOS: incomplete — no available Simulator runtime matches iPhone SDK %s.\n' \
        "$IOS_SDK_VERSION"
      print_next_step 'Run: mobile-setup ios'
      ;;
  esac
  return 1
}

check_ios() {
  ios_classify_state
  report_ios_readiness
}

install_ios() {
  ios_classify_state

  if [ "$IOS_NEXT_ACTION" = none ]; then
    report_ios_readiness
    printf 'iOS: matching runtime already exists; skipping download.\n'
    return 0
  fi

  # Everything except a missing runtime is a person's job in Xcode, so the
  # record decides in one comparison what used to be four repeated blocks.
  if [ "$IOS_NEXT_ACTION" != download-runtime ]; then
    report_ios_readiness
    printf 'Error: the selected full Xcode installation is not ready for Simulator provisioning.\n' >&2
    printf '  → Finish Xcode first launch and accept its license manually, then rerun: mobile-setup ios\n' >&2
    return 1
  fi

  if ! command -v xcodebuild >/dev/null 2>&1; then
    printf 'Error: xcodebuild is unavailable for iOS Simulator provisioning.\n' >&2
    printf '  → Select a full Xcode installation, finish setup, then rerun: mobile-setup ios\n' >&2
    return 1
  fi

  printf 'iOS: downloading the latest runtime compatible with SDK %s.\n' "$IOS_SDK_VERSION"
  if ! xcodebuild -downloadPlatform iOS; then
    printf 'Error: Xcode could not download the iOS Simulator runtime.\n' >&2
    printf '  → Finish Xcode first launch and accept its license manually, then rerun: mobile-setup ios\n' >&2
    return 1
  fi

  ios_classify_state
  if report_ios_readiness; then
    return 0
  fi

  printf 'Error: Xcode finished without an available runtime matching SDK %s.\n' \
    "$IOS_SDK_VERSION" >&2
  printf '  → Inspect Xcode Components, then rerun: mobile-setup ios\n' >&2
  return 1
}
