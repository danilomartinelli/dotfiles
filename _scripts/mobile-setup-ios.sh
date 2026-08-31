#!/usr/bin/env bash
#
# Private iOS Simulator provisioning implementation for mobile-setup.

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

check_ios() {
  local sdk_version
  local runtime_listing

  if ! command -v xcrun >/dev/null 2>&1; then
    printf 'iOS: incomplete — xcrun is unavailable; select a full Xcode installation.\n'
    print_next_step 'Complete Xcode first launch and license setup, then run: mobile-setup ios'
    return 1
  fi

  if ! sdk_version=$(read_ios_sdk_version); then
    printf 'iOS: incomplete — the selected Xcode has no usable iPhone Simulator SDK.\n'
    print_next_step 'Select a full Xcode installation, finish its first launch, then run: mobile-setup ios'
    return 1
  fi

  if ! runtime_listing=$(read_ios_runtime_listing); then
    printf 'iOS: incomplete — Xcode could not list Simulator runtimes.\n'
    print_next_step 'Finish Xcode first launch and license setup, then run: mobile-setup ios'
    return 1
  fi

  if ios_runtime_is_available "$sdk_version" "$runtime_listing"; then
    printf 'iOS: ready — Simulator runtime matches iPhone SDK %s.\n' "$sdk_version"
    return 0
  fi

  printf 'iOS: incomplete — no available Simulator runtime matches iPhone SDK %s.\n' \
    "$sdk_version"
  print_next_step 'Run: mobile-setup ios'
  return 1
}

install_ios() {
  local sdk_version
  local runtime_listing

  if ! command -v xcrun >/dev/null 2>&1; then
    printf 'iOS: incomplete — xcrun is unavailable; select a full Xcode installation.\n'
    print_next_step 'Complete Xcode first launch and license setup, then run: mobile-setup ios'
    printf 'Error: the selected full Xcode installation is not ready for Simulator provisioning.\n' >&2
    printf '  → Finish Xcode first launch and accept its license manually, then rerun: mobile-setup ios\n' >&2
    return 1
  fi

  if ! sdk_version=$(read_ios_sdk_version); then
    printf 'iOS: incomplete — the selected Xcode has no usable iPhone Simulator SDK.\n'
    print_next_step 'Select a full Xcode installation, finish its first launch, then run: mobile-setup ios'
    printf 'Error: the selected full Xcode installation is not ready for Simulator provisioning.\n' >&2
    printf '  → Finish Xcode first launch and accept its license manually, then rerun: mobile-setup ios\n' >&2
    return 1
  fi

  if ! runtime_listing=$(read_ios_runtime_listing); then
    printf 'iOS: incomplete — Xcode could not list Simulator runtimes.\n'
    print_next_step 'Finish Xcode first launch and license setup, then run: mobile-setup ios'
    printf 'Error: the selected full Xcode installation is not ready for Simulator provisioning.\n' >&2
    printf '  → Finish Xcode first launch and accept its license manually, then rerun: mobile-setup ios\n' >&2
    return 1
  fi

  if ios_runtime_is_available "$sdk_version" "$runtime_listing"; then
    printf 'iOS: ready — Simulator runtime matches iPhone SDK %s.\n' "$sdk_version"
    printf 'iOS: matching runtime already exists; skipping download.\n'
    return 0
  fi

  printf 'iOS: incomplete — no available Simulator runtime matches iPhone SDK %s.\n' \
    "$sdk_version"
  print_next_step 'Run: mobile-setup ios'

  if ! command -v xcodebuild >/dev/null 2>&1; then
    printf 'Error: xcodebuild is unavailable for iOS Simulator provisioning.\n' >&2
    printf '  → Select a full Xcode installation, finish setup, then rerun: mobile-setup ios\n' >&2
    return 1
  fi

  printf 'iOS: downloading the latest runtime compatible with SDK %s.\n' "$sdk_version"
  if ! xcodebuild -downloadPlatform iOS; then
    printf 'Error: Xcode could not download the iOS Simulator runtime.\n' >&2
    printf '  → Finish Xcode first launch and accept its license manually, then rerun: mobile-setup ios\n' >&2
    return 1
  fi

  if check_ios; then
    return 0
  fi

  printf 'Error: Xcode finished without an available runtime matching SDK %s.\n' \
    "$sdk_version" >&2
  printf '  → Inspect Xcode Components, then rerun: mobile-setup ios\n' >&2
  return 1
}
