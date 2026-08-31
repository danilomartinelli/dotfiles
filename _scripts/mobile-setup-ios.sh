#!/usr/bin/env bash
#
# The iOS Mobile Target adapter for mobile-setup.
#
# It fills a Mobile Readiness record and prints nothing. Everything a person
# reads is composed into the record and printed by mobile_readiness_report.

# iOS's own detail, not part of the record: the SDK version appears in the
# verdict prose and in the download message, and no other target has one.
IOS_SDK_VERSION=''

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

# Observe every condition, then commit the record whole. iOS's conditions are
# sequential — no SDK without xcrun, no runtime listing without an SDK, no match
# without a listing — so exactly one of them can be the blocker and the
# permitted action names it.
ios_readiness() {
  local sdk_version=''
  local runtime_listing

  mobile_readiness_begin ios

  if ! command -v xcrun >/dev/null 2>&1; then
    IOS_SDK_VERSION=''
    mobile_readiness_line 'iOS: incomplete — xcrun is unavailable; select a full Xcode installation.'
    mobile_readiness_next_step 'Complete Xcode first launch and license setup, then run: mobile-setup ios'
    mobile_readiness_commit select-full-xcode
    return 0
  fi

  if ! sdk_version=$(read_ios_sdk_version); then
    IOS_SDK_VERSION=''
    mobile_readiness_line 'iOS: incomplete — the selected Xcode has no usable iPhone Simulator SDK.'
    mobile_readiness_next_step 'Select a full Xcode installation, finish its first launch, then run: mobile-setup ios'
    mobile_readiness_commit select-full-xcode-sdk
    return 0
  fi

  IOS_SDK_VERSION=$sdk_version

  if ! runtime_listing=$(read_ios_runtime_listing); then
    mobile_readiness_line 'iOS: incomplete — Xcode could not list Simulator runtimes.'
    mobile_readiness_next_step 'Finish Xcode first launch and license setup, then run: mobile-setup ios'
    mobile_readiness_commit finish-xcode-setup
    return 0
  fi

  if ios_runtime_is_available "$sdk_version" "$runtime_listing"; then
    mobile_readiness_line \
      "iOS: ready — Simulator runtime matches iPhone SDK $sdk_version."
    mobile_readiness_commit none
    return 0
  fi

  mobile_readiness_line \
    "iOS: incomplete — no available Simulator runtime matches iPhone SDK $sdk_version."
  mobile_readiness_next_step 'Run: mobile-setup ios'
  mobile_readiness_commit download-runtime
}

check_ios() {
  ios_readiness
  mobile_readiness_report
}

install_ios() {
  ios_readiness

  if mobile_readiness_is_ready; then
    mobile_readiness_report
    printf 'iOS: matching runtime already exists; skipping download.\n'
    return 0
  fi

  # Everything except a missing runtime is a person's job in Xcode, so the
  # record decides in one comparison what used to be four repeated blocks.
  if [ "$MOBILE_READINESS_ACTION" != download-runtime ]; then
    mobile_readiness_report || true
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

  ios_readiness
  if mobile_readiness_report; then
    return 0
  fi

  printf 'Error: Xcode finished without an available runtime matching SDK %s.\n' \
    "$IOS_SDK_VERSION" >&2
  printf '  → Inspect Xcode Components, then rerun: mobile-setup ios\n' >&2
  return 1
}
