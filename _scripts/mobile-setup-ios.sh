#!/usr/bin/env bash
#
# Private iOS Simulator provisioning implementation for mobile-setup.

IOS_SDK_VERSION=''
IOS_RUNTIME_LISTING=''

read_ios_sdk_version() {
  if ! command -v xcrun >/dev/null 2>&1; then
    return 1
  fi

  IOS_SDK_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null) || {
    IOS_SDK_VERSION=''
    return 1
  }

  [ -n "$IOS_SDK_VERSION" ]
}

read_ios_runtime_listing() {
  IOS_RUNTIME_LISTING=$(xcrun simctl list runtimes 2>/dev/null) || {
    IOS_RUNTIME_LISTING=''
    return 1
  }
}

ios_runtime_is_available() {
  local runtime_line

  while IFS= read -r runtime_line; do
    case "$runtime_line" in
      "iOS ${IOS_SDK_VERSION} "*)
        case "$runtime_line" in
          *'(unavailable'*) ;;
          *) return 0 ;;
        esac
        ;;
    esac
  done <<<"$IOS_RUNTIME_LISTING"

  return 1
}

check_ios() {
  if ! command -v xcrun >/dev/null 2>&1; then
    printf 'iOS: incomplete — xcrun is unavailable; select a full Xcode installation.\n'
    print_next_step 'Complete Xcode first launch and license setup, then run: mobile-setup ios'
    return 1
  fi

  if ! read_ios_sdk_version; then
    printf 'iOS: incomplete — the selected Xcode has no usable iPhone Simulator SDK.\n'
    print_next_step 'Select a full Xcode installation, finish its first launch, then run: mobile-setup ios'
    return 1
  fi

  if ! read_ios_runtime_listing; then
    printf 'iOS: incomplete — Xcode could not list Simulator runtimes.\n'
    print_next_step 'Finish Xcode first launch and license setup, then run: mobile-setup ios'
    return 1
  fi

  if ios_runtime_is_available; then
    printf 'iOS: ready — Simulator runtime matches iPhone SDK %s.\n' "$IOS_SDK_VERSION"
    return 0
  fi

  printf 'iOS: incomplete — no available Simulator runtime matches iPhone SDK %s.\n' \
    "$IOS_SDK_VERSION"
  print_next_step 'Run: mobile-setup ios'
  return 1
}

install_ios() {
  if check_ios; then
    printf 'iOS: matching runtime already exists; skipping download.\n'
    return 0
  fi

  if [ -z "$IOS_SDK_VERSION" ]; then
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

  if check_ios; then
    return 0
  fi

  printf 'Error: Xcode finished without an available runtime matching SDK %s.\n' \
    "$IOS_SDK_VERSION" >&2
  printf '  → Inspect Xcode Components, then rerun: mobile-setup ios\n' >&2
  return 1
}
