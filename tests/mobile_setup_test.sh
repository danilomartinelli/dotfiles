#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_ROOT=$(CDPATH='' cd -P -- "$TEST_DIR/.." && pwd)
# shellcheck source=tests/_support/shell-scenario.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/shell-scenario.sh"
# shellcheck source=tests/_support/stubs.sh
# shellcheck disable=SC1091
source "$TEST_DIR/_support/stubs.sh"
scenario_init dotfiles-mobile-setup-tests

MOBILE_SETUP=$REPOSITORY_ROOT/bin/mobile-setup

new_fixture() {
  local fixture

  fixture=$(scenario_tmpdir fixture)
  mkdir -p "$fixture/home" "$fixture/fake-bin"
  stub_uname "$fixture/fake-bin"
  stub_xcrun "$fixture/fake-bin"
  stub_xcodebuild "$fixture/fake-bin"
  ln -s "$REPOSITORY_ROOT/dotfiles-root.symlink" "$fixture/home/.dotfiles-root"

  scenario_write_executable "$fixture/fake-bin/open" <<'EOF'
#!/bin/sh
printf 'open %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
EOF

  printf '%s\n' "$fixture"
}

android_root() {
  printf '%s\n' "$1/home/Library/Android/sdk"
}

write_android_tools() {
  local fixture=$1
  local root

  root=$(android_root "$fixture")
  mkdir -p "$root/cmdline-tools/latest/bin"

  scenario_write_executable "$root/cmdline-tools/latest/bin/sdkmanager" <<'EOF'
#!/bin/sh
printf 'sdkmanager %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
if [ -n "${FAKE_EXPECT_JAVA_HOME:-}" ] && [ "${JAVA_HOME:-}" != "$FAKE_EXPECT_JAVA_HOME" ]; then
  printf 'sdkmanager unexpected JAVA_HOME: %s\n' "${JAVA_HOME:-unset}" >>"$SCENARIO_EVENT_LOG"
  exit 67
fi
sdk_root=
for argument in "$@"; do
  case "$argument" in
    --sdk_root=*) sdk_root=${argument#--sdk_root=} ;;
  esac
done

if [ "${FAKE_SDKMANAGER_INSTALL:-0}" -eq 1 ] && [ -n "$sdk_root" ]; then
  for package in "$@"; do
    case "$package" in
      platform-tools)
        mkdir -p "$sdk_root/platform-tools"
        : >"$sdk_root/platform-tools/adb"
        chmod +x "$sdk_root/platform-tools/adb"
        ;;
      emulator)
        mkdir -p "$sdk_root/emulator"
        : >"$sdk_root/emulator/emulator"
        chmod +x "$sdk_root/emulator/emulator"
        ;;
      'cmdline-tools;latest')
        mkdir -p "$sdk_root/cmdline-tools/latest/bin"
        ;;
      'platforms;android-36')
        mkdir -p "$sdk_root/platforms/android-36"
        : >"$sdk_root/platforms/android-36/android.jar"
        ;;
      'build-tools;36.0.0')
        mkdir -p "$sdk_root/build-tools/36.0.0"
        : >"$sdk_root/build-tools/36.0.0/aapt2"
        chmod +x "$sdk_root/build-tools/36.0.0/aapt2"
        ;;
      'system-images;android-36;google_apis;arm64-v8a')
        mkdir -p "$sdk_root/system-images/android-36/google_apis/arm64-v8a"
        : >"$sdk_root/system-images/android-36/google_apis/arm64-v8a/package.xml"
        ;;
    esac
  done
fi
if [ "${FAKE_SDKMANAGER_REMOVE_LICENSE:-0}" -eq 1 ] && [ -n "$sdk_root" ]; then
  rm -f "$sdk_root/licenses/android-sdk-license"
fi
if [ "${FAKE_SDKMANAGER_REJECT_STDIN:-0}" -eq 1 ]; then
  if IFS= read -r input; then
    printf 'sdkmanager read stdin: %s\n' "$input" >>"$SCENARIO_EVENT_LOG"
    exit 66
  fi
fi
exit "${FAKE_SDKMANAGER_STATUS:-0}"
EOF

  scenario_write_executable "$root/cmdline-tools/latest/bin/avdmanager" <<'EOF'
#!/bin/sh
printf 'avdmanager %s\n' "$*" >>"$SCENARIO_EVENT_LOG"
if [ -n "${FAKE_EXPECT_JAVA_HOME:-}" ] && [ "${JAVA_HOME:-}" != "$FAKE_EXPECT_JAVA_HOME" ]; then
  printf 'avdmanager unexpected JAVA_HOME: %s\n' "${JAVA_HOME:-unset}" >>"$SCENARIO_EVENT_LOG"
  exit 67
fi
case "$1 ${2-}" in
  'list device')
    if [ "${FAKE_AVDMANAGER_LIST_STATUS:-0}" -ne 0 ]; then
      exit "$FAKE_AVDMANAGER_LIST_STATUS"
    fi
    cat <<'DEVICES'
id: 28 or "pixel"
Name: Pixel
OEM : Google
DEVICES
    ;;
  'create avd')
    avd_name=
    image=
    device=
    previous=
    for argument in "$@"; do
      case "$previous" in
        -n) avd_name=$argument ;;
        -k) image=$argument ;;
        --device) device=$argument ;;
      esac
      previous=$argument
    done
    mkdir -p "$HOME/.android/avd/$avd_name.avd"
    printf 'image.sysdir.1=%s\nhw.device.name=%s\n' "$image" "$device" \
      >"$HOME/.android/avd/$avd_name.avd/config.ini"
    printf 'path=%s\n' "$HOME/.android/avd/$avd_name.avd" \
      >"$HOME/.android/avd/$avd_name.ini"
    if [ "${FAKE_AVDMANAGER_REMOVE_PACKAGE:-0}" -eq 1 ]; then
      rm -f "$HOME/Library/Android/sdk/platforms/android-36/android.jar"
    fi
    ;;
esac
exit "${FAKE_AVDMANAGER_STATUS:-0}"
EOF

  mkdir -p "$root/licenses"
  : >"$root/licenses/android-sdk-license"
}

install_android_packages() {
  local fixture=$1
  local root

  root=$(android_root "$fixture")
  mkdir -p "$root/platform-tools" "$root/emulator" \
    "$root/platforms/android-36" "$root/build-tools/36.0.0" \
    "$root/system-images/android-36/google_apis/arm64-v8a"
  : >"$root/platform-tools/adb"
  : >"$root/emulator/emulator"
  : >"$root/platforms/android-36/android.jar"
  : >"$root/build-tools/36.0.0/aapt2"
  : >"$root/system-images/android-36/google_apis/arm64-v8a/package.xml"
  chmod +x "$root/platform-tools/adb" "$root/emulator/emulator" \
    "$root/build-tools/36.0.0/aapt2"
}

write_android_avd() {
  local fixture=$1
  local image=${2:-system-images/android-36/google_apis/arm64-v8a}
  local device=${3:-pixel}

  mkdir -p "$fixture/home/.android/avd/Pixel_API36.avd"
  printf 'image.sysdir.1=%s\nhw.device.name=%s\n' "$image" "$device" \
    >"$fixture/home/.android/avd/Pixel_API36.avd/config.ini"
  printf 'path=%s\n' "$fixture/home/.android/avd/Pixel_API36.avd" \
    >"$fixture/home/.android/avd/Pixel_API36.ini"
}

invoke_mobile() {
  local fixture=$1
  shift
  local -a overrides=()

  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
    overrides+=("$1")
    shift
  done
  [ "$#" -gt 0 ] || {
    scenario_fail 'invoke_mobile: missing -- before the command'
    return 1
  }
  shift

  scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    ${overrides[@]+"${overrides[@]}"} \
    "$MOBILE_SETUP" "$@"
}

invoke_topic() {
  local fixture=$1
  local topic=$2

  scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/$topic/install.sh"
}

test_usage_and_help_are_distinct() {
  local fixture status=0
  fixture=$(new_fixture)

  invoke_mobile "$fixture" -- --help
  assert_contains "$fixture/stdout.log" 'Usage: mobile-setup [--check] [ios|android|all]'

  invoke_mobile "$fixture" -- --not-a-target || status=$?
  assert_equal 2 "$status" 'invalid mobile-setup usage status'
  assert_contains "$fixture/stderr.log" 'Usage: mobile-setup [--check] [ios|android|all]'
}

test_check_is_local_and_reports_incomplete_targets() {
  local fixture status=0
  fixture=$(new_fixture)

  invoke_mobile "$fixture" -- --check || status=$?

  assert_equal 1 "$status" 'incomplete check status'
  assert_contains "$fixture/stdout.log" 'iOS: incomplete'
  assert_contains "$fixture/stdout.log" 'Android: incomplete'
  assert_contains "$fixture/stdout.log" 'mobile-setup ios'
  assert_contains "$fixture/stdout.log" 'mobile-setup android'
  assert_not_contains "$fixture/events.log" 'xcodebuild '
  assert_not_contains "$fixture/events.log" 'sdkmanager '
  assert_not_contains "$fixture/events.log" 'avdmanager '
  assert_not_contains "$fixture/events.log" 'open '
}

test_check_succeeds_only_for_ready_selected_targets() {
  local fixture
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  write_android_avd "$fixture"
  : >"$fixture/home/.ios-runtime-ready"

  invoke_mobile "$fixture" -- --check all

  assert_contains "$fixture/stdout.log" 'iOS: ready'
  assert_contains "$fixture/stdout.log" 'Android: ready'
  assert_not_contains "$fixture/events.log" 'sdkmanager '
  assert_not_contains "$fixture/events.log" 'avdmanager create'
}

test_ios_check_accepts_a_real_available_runtime_without_a_suffix() {
  local fixture
  local available_runtime=$'== Runtimes ==\niOS 26.5 (26.5 - 23F77) - com.apple.CoreSimulator.SimRuntime.iOS-26-5'
  fixture=$(new_fixture)

  invoke_mobile "$fixture" "FAKE_IOS_RUNTIMES=$available_runtime" -- --check ios

  assert_contains "$fixture/stdout.log" 'iOS: ready'
  assert_not_contains "$fixture/events.log" 'xcodebuild '
}

test_ios_check_rejects_a_same_version_unavailable_runtime() {
  local fixture status=0
  local unavailable_runtime=$'== Runtimes ==\niOS 26.5 (26.5 - 23F77) - com.apple.CoreSimulator.SimRuntime.iOS-26-5 (unavailable, runtime is not installed)'
  fixture=$(new_fixture)

  invoke_mobile "$fixture" "FAKE_IOS_RUNTIMES=$unavailable_runtime" -- --check ios || status=$?

  assert_equal 1 "$status" 'unavailable iOS runtime status'
  assert_contains "$fixture/stdout.log" 'matches iPhone SDK 26.5'
  assert_not_contains "$fixture/events.log" 'xcodebuild '
}

test_ios_check_rejects_a_different_version_stale_runtime() {
  local fixture status=0
  local stale_runtime=$'== Runtimes ==\niOS 26.4 (26.4 - 23E214) - com.apple.CoreSimulator.SimRuntime.iOS-26-4'
  fixture=$(new_fixture)

  invoke_mobile "$fixture" "FAKE_IOS_RUNTIMES=$stale_runtime" -- --check ios || status=$?

  assert_equal 1 "$status" 'stale iOS runtime status'
  assert_contains "$fixture/stdout.log" 'matches iPhone SDK 26.5'
  assert_not_contains "$fixture/events.log" 'xcodebuild '
}

test_ios_observations_are_caller_owned() {
  local fixture
  fixture=$(new_fixture)
  : >"$fixture/home/.ios-runtime-ready"

  # shellcheck disable=SC2016 # The command is evaluated by the child Bash process.
  scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    bash -c '
      source "$1"
      sdk_version=$(read_ios_sdk_version)
      runtime_listing=$(read_ios_runtime_listing)
      ios_runtime_is_available "$sdk_version" "$runtime_listing"
      printf "sdk=%s\n%s\n" "$sdk_version" "$runtime_listing"
    ' bash "$REPOSITORY_ROOT/_scripts/mobile-setup-ios.sh"

  assert_contains "$fixture/stdout.log" 'sdk=26.5'
  assert_contains "$fixture/stdout.log" 'iOS 26.5 (26.5 - 23F77)'
}

test_target_selection_does_not_touch_the_other_platform() {
  local fixture
  fixture=$(new_fixture)
  : >"$fixture/home/.ios-runtime-ready"

  invoke_mobile "$fixture" -- --check ios
  assert_contains "$fixture/stdout.log" 'iOS: ready'
  assert_not_contains "$fixture/events.log" 'sdkmanager '
  assert_not_contains "$fixture/events.log" 'avdmanager '

  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  write_android_avd "$fixture"
  invoke_mobile "$fixture" -- --check android
  assert_contains "$fixture/stdout.log" 'Android: ready'
  assert_not_contains "$fixture/events.log" 'xcrun '
}

test_ios_install_skips_a_matching_runtime() {
  local fixture
  fixture=$(new_fixture)
  : >"$fixture/home/.ios-runtime-ready"

  invoke_mobile "$fixture" -- ios

  assert_contains "$fixture/stdout.log" 'iOS: ready'
  assert_not_contains "$fixture/events.log" 'xcodebuild '
}

test_ios_install_selects_the_latest_compatible_download() {
  local fixture
  fixture=$(new_fixture)

  invoke_mobile "$fixture" FAKE_XCODEBUILD_INSTALL=1 -- ios

  assert_contains "$fixture/events.log" 'xcodebuild -downloadPlatform iOS'
  assert_not_contains "$fixture/events.log" 'sdkmanager '
  assert_contains "$fixture/stdout.log" 'iOS: ready'
}

test_android_install_stops_for_manual_prerequisites() {
  local fixture status=0
  fixture=$(new_fixture)

  invoke_mobile "$fixture" \
    ANDROID_HOME=/custom/sdk \
    ANDROID_SDK_ROOT=/deprecated/sdk \
    -- android || status=$?

  assert_equal 1 "$status" 'missing Android prerequisites status'
  assert_contains "$fixture/stdout.log" \
    "canonical SDK root is absent: $fixture/home/Library/Android/sdk"
  assert_contains "$fixture/stderr.log" 'Android Studio Setup Wizard'
  assert_contains "$fixture/stderr.log" 'mobile-setup android'
  assert_not_contains "$fixture/events.log" 'sdkmanager '
  assert_not_contains "$fixture/events.log" '--licenses'
}

test_android_freezes_resolved_paths_for_each_invocation() {
  local fixture status=0
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  write_android_avd "$fixture"

  # shellcheck disable=SC2016 # The command is evaluated by the child Bash process.
  scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    bash -c '
      source "$1"
      print_next_step() { :; }
      android_sdk_root() {
        printf "resolve sdk_root\\n" >>"$SCENARIO_EVENT_LOG"
        printf "%s\\n" "$HOME/Library/Android/sdk"
      }
      android_sdkmanager_path() {
        printf "resolve sdkmanager\\n" >>"$SCENARIO_EVENT_LOG"
        printf "%s/cmdline-tools/latest/bin/sdkmanager\\n" "$1"
      }
      android_avdmanager_path() {
        printf "resolve avdmanager\\n" >>"$SCENARIO_EVENT_LOG"
        printf "%s/cmdline-tools/latest/bin/avdmanager\\n" "$1"
      }
      check_android
    ' bash "$REPOSITORY_ROOT/_scripts/mobile-setup-android.sh"

  assert_count "$fixture/events.log" 'resolve sdk_root' 1
  assert_count "$fixture/events.log" 'resolve sdkmanager' 1
  assert_count "$fixture/events.log" 'resolve avdmanager' 1

  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  root=$(android_root "$fixture")
  rm -rf "$root/platforms/android-36" "$root/build-tools/36.0.0" \
    "$root/system-images/android-36/google_apis/arm64-v8a"

  # shellcheck disable=SC2016 # The command is evaluated by the child Bash process.
  scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    FAKE_SDKMANAGER_INSTALL=1 \
    bash -c '
      source "$1"
      print_next_step() { :; }
      android_sdk_root() {
        printf "resolve sdk_root\\n" >>"$SCENARIO_EVENT_LOG"
        printf "%s\\n" "$HOME/Library/Android/sdk"
      }
      android_sdkmanager_path() {
        printf "resolve sdkmanager\\n" >>"$SCENARIO_EVENT_LOG"
        printf "%s/cmdline-tools/latest/bin/sdkmanager\\n" "$1"
      }
      android_avdmanager_path() {
        printf "resolve avdmanager\\n" >>"$SCENARIO_EVENT_LOG"
        printf "%s/cmdline-tools/latest/bin/avdmanager\\n" "$1"
      }
      install_android
    ' bash "$REPOSITORY_ROOT/_scripts/mobile-setup-android.sh" || status=$?

  assert_equal 0 "$status" 'post-package-install with frozen Android paths status'
  assert_count "$fixture/events.log" 'resolve sdk_root' 1
  assert_count "$fixture/events.log" 'resolve sdkmanager' 1
  assert_count "$fixture/events.log" 'resolve avdmanager' 1

  fixture=$(new_fixture)
  # shellcheck disable=SC2016 # The command is evaluated by the child Bash process.
  scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    bash -c '
      source "$1"
      print_next_step() { :; }
      android_sdk_root() {
        printf "resolve sdk_root\\n" >>"$SCENARIO_EVENT_LOG"
        printf "%s\\n" "$HOME/Library/Android/sdk"
      }
      android_sdkmanager_path() {
        printf "resolve sdkmanager\\n" >>"$SCENARIO_EVENT_LOG"
        printf "%s/cmdline-tools/latest/bin/sdkmanager\\n" "$1"
      }
      android_avdmanager_path() {
        printf "resolve avdmanager\\n" >>"$SCENARIO_EVENT_LOG"
        printf "%s/cmdline-tools/latest/bin/avdmanager\\n" "$1"
      }
      install_android
    ' bash "$REPOSITORY_ROOT/_scripts/mobile-setup-android.sh" || status=$?

  assert_equal 1 "$status" 'missing prerequisites with frozen Android paths status'
  assert_count "$fixture/events.log" 'resolve sdk_root' 1
  assert_count "$fixture/events.log" 'resolve sdkmanager' 1
  assert_count "$fixture/events.log" 'resolve avdmanager' 1
}

test_android_install_reconciles_only_missing_packages_and_creates_an_absent_avd() {
  local fixture root
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  root=$(android_root "$fixture")
  rm -rf "$root/platforms/android-36" "$root/build-tools/36.0.0" \
    "$root/system-images/android-36/google_apis/arm64-v8a"

  invoke_mobile "$fixture" FAKE_SDKMANAGER_INSTALL=1 -- android

  assert_contains "$fixture/events.log" \
    "sdkmanager --sdk_root=$root platforms;android-36 build-tools;36.0.0 system-images;android-36;google_apis;arm64-v8a"
  assert_contains "$fixture/events.log" \
    'avdmanager create avd -n Pixel_API36 -k system-images;android-36;google_apis;arm64-v8a --device pixel'
  assert_not_contains "$fixture/events.log" '--licenses'
  assert_not_contains "$fixture/events.log" '--force'
  [[ -f $fixture/home/.android/avd/Pixel_API36.avd/config.ini ]] \
    || scenario_fail 'Android install did not create the absent AVD'
}

test_android_install_skips_a_compatible_avd() {
  local fixture
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  write_android_avd "$fixture"

  invoke_mobile "$fixture" -- android

  assert_not_contains "$fixture/events.log" 'sdkmanager '
  assert_not_contains "$fixture/events.log" 'avdmanager create'
  assert_contains "$fixture/stdout.log" 'Pixel_API36 AVD is ready'
}

test_android_install_refuses_to_overwrite_an_incompatible_avd() {
  local fixture config_before config_after status=0
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  write_android_avd "$fixture" 'system-images/android-35/google_apis/arm64-v8a'
  config_before=$(cat "$fixture/home/.android/avd/Pixel_API36.avd/config.ini")

  invoke_mobile "$fixture" -- android || status=$?
  config_after=$(cat "$fixture/home/.android/avd/Pixel_API36.avd/config.ini")

  assert_equal 1 "$status" 'incompatible AVD status'
  assert_contains "$fixture/stderr.log" 'refusing to overwrite'
  assert_contains "$fixture/stderr.log" 'recovery'
  assert_not_contains "$fixture/events.log" 'avdmanager create'
  assert_equal "$config_before" "$config_after" 'incompatible AVD config'
}

test_android_install_refuses_incompatible_avd_before_missing_package_install() {
  local fixture root config_before config_after status=0
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  root=$(android_root "$fixture")
  rm -rf "$root/platforms/android-36" "$root/build-tools/36.0.0" \
    "$root/system-images/android-36/google_apis/arm64-v8a"
  write_android_avd "$fixture" 'system-images/android-35/google_apis/arm64-v8a'
  config_before=$(cat "$fixture/home/.android/avd/Pixel_API36.avd/config.ini")

  invoke_mobile "$fixture" -- android || status=$?
  config_after=$(cat "$fixture/home/.android/avd/Pixel_API36.avd/config.ini")

  assert_equal 1 "$status" 'incompatible AVD with missing packages status'
  assert_contains "$fixture/stdout.log" 'missing packages'
  assert_contains "$fixture/stderr.log" 'refusing to overwrite'
  assert_not_contains "$fixture/events.log" 'sdkmanager '
  assert_not_contains "$fixture/events.log" 'avdmanager create'
  assert_equal "$config_before" "$config_after" \
    'incompatible AVD with missing packages config'
}

test_android_install_rejects_an_unready_snapshot_after_package_install() {
  local fixture root status=0
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  root=$(android_root "$fixture")
  rm -rf "$root/platforms/android-36" "$root/build-tools/36.0.0" \
    "$root/system-images/android-36/google_apis/arm64-v8a"

  invoke_mobile "$fixture" \
    FAKE_SDKMANAGER_INSTALL=1 \
    FAKE_SDKMANAGER_REMOVE_LICENSE=1 \
    -- android || status=$?

  assert_equal 1 "$status" 'unready post-package-install snapshot status'
  assert_contains "$fixture/stderr.log" 'readiness snapshot incomplete'
  assert_contains "$fixture/stdout.log" 'licenses are not accepted'
  assert_not_contains "$fixture/events.log" 'avdmanager create'
}

test_android_install_requires_full_readiness_after_avd_creation() {
  local fixture status=0
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"

  invoke_mobile "$fixture" FAKE_AVDMANAGER_REMOVE_PACKAGE=1 -- android || status=$?

  assert_equal 1 "$status" 'unready post-AVD-creation snapshot status'
  assert_contains "$fixture/stderr.log" \
    'final readiness snapshot is incomplete'
  assert_contains "$fixture/stdout.log" 'missing packages'
  assert_contains "$fixture/events.log" 'avdmanager create'
  [[ -f $fixture/home/.android/avd/Pixel_API36.avd/config.ini ]] \
    || scenario_fail 'Android install did not retain the created AVD'
}

test_all_install_continues_after_an_ios_failure() {
  local fixture root status=0
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  root=$(android_root "$fixture")
  rm -rf "$root/platforms/android-36" "$root/build-tools/36.0.0" \
    "$root/system-images/android-36/google_apis/arm64-v8a"

  invoke_mobile "$fixture" \
    FAKE_XCODEBUILD_STATUS=1 \
    FAKE_SDKMANAGER_INSTALL=1 \
    -- all || status=$?

  assert_equal 1 "$status" 'all aggregate status after iOS failure'
  assert_before "$fixture/events.log" 'xcodebuild -downloadPlatform iOS' 'sdkmanager '
  assert_contains "$fixture/events.log" 'avdmanager create'
}

test_android_install_reports_an_avdmanager_list_failure() {
  local fixture status=0
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"

  invoke_mobile "$fixture" FAKE_AVDMANAGER_LIST_STATUS=1 -- android || status=$?

  assert_equal 1 "$status" 'avdmanager list failure status'
  assert_contains "$fixture/stderr.log" \
    'avdmanager could not list available Pixel hardware profiles'
  assert_contains "$fixture/stderr.log" 'mobile-setup android'
  assert_not_contains "$fixture/events.log" 'avdmanager create'
}

test_android_package_install_closes_stdin() {
  local fixture root
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  root=$(android_root "$fixture")
  rm -rf "$root/platforms/android-36" "$root/build-tools/36.0.0" \
    "$root/system-images/android-36/google_apis/arm64-v8a"

  printf '%s\n' 'unexpected license input' | scenario_capture "$fixture" env \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    FAKE_SDKMANAGER_INSTALL=1 \
    FAKE_SDKMANAGER_REJECT_STDIN=1 \
    "$MOBILE_SETUP" android

  assert_contains "$fixture/events.log" \
    "sdkmanager --sdk_root=$root platforms;android-36 build-tools;36.0.0 system-images;android-36;google_apis;arm64-v8a"
  assert_not_contains "$fixture/events.log" 'sdkmanager read stdin'
  assert_not_contains "$fixture/events.log" '--licenses'
}

test_android_tools_use_mise_java_outside_an_initialized_shell() {
  local fixture root java_home status=0
  fixture=$(new_fixture)
  write_android_tools "$fixture"
  install_android_packages "$fixture"
  root=$(android_root "$fixture")
  rm -rf "$root/platforms/android-36" "$root/build-tools/36.0.0" \
    "$root/system-images/android-36/google_apis/arm64-v8a"

  java_home=$fixture/mise-java
  mkdir -p "$java_home/bin"
  : >"$java_home/bin/java"
  chmod +x "$java_home/bin/java"
  scenario_write_executable "$fixture/fake-bin/java" <<'EOF'
#!/bin/sh
exit 1
EOF
  stub_mise "$fixture/fake-bin"

  invoke_mobile "$fixture" \
    JAVA_HOME= \
    "FAKE_MISE_JAVA_HOME=$java_home" \
    "FAKE_EXPECT_JAVA_HOME=$java_home" \
    FAKE_SDKMANAGER_INSTALL=1 \
    -- android || status=$?

  assert_equal 0 "$status" 'Mise Java fallback status'
  assert_not_contains "$fixture/events.log" 'unexpected JAVA_HOME'
}

test_topic_installers_warn_without_provisioning() {
  local fixture
  fixture=$(new_fixture)

  invoke_topic "$fixture" xcode
  assert_contains "$fixture/stderr.log" 'Run: mobile-setup ios'
  assert_not_contains "$fixture/events.log" 'xcodebuild '

  fixture=$(new_fixture)
  invoke_topic "$fixture" android-studio
  assert_contains "$fixture/stderr.log" 'Run: mobile-setup android'
  assert_not_contains "$fixture/events.log" 'sdkmanager '
  assert_not_contains "$fixture/events.log" 'avdmanager '
}

test_shell_environment_uses_the_canonical_android_root() {
  local fixture
  fixture=$(new_fixture)

  # shellcheck disable=SC2016 # The command is evaluated by the child Zsh process.
  scenario_capture "$fixture" env \
    ANDROID_HOME=/custom/sdk \
    ANDROID_SDK_ROOT=/deprecated/sdk \
    HOME="$fixture/home" \
    PATH="$fixture/fake-bin:/usr/bin:/bin" \
    zsh -d -f -c '
      source "$1/.commonrc"
      source "$1/android-studio/path.zsh"
      printf "ANDROID_HOME=%s\n" "$ANDROID_HOME"
      printf "ANDROID_SDK_ROOT=%s\n" "${ANDROID_SDK_ROOT-unset}"
      printf "PATH=%s\n" "$PATH"
    ' zsh "$REPOSITORY_ROOT"

  assert_contains "$fixture/stdout.log" \
    "ANDROID_HOME=$fixture/home/Library/Android/sdk"
  assert_contains "$fixture/stdout.log" 'ANDROID_SDK_ROOT=unset'
  assert_contains "$fixture/stdout.log" "/Library/Android/sdk/cmdline-tools/latest/bin"
  assert_contains "$fixture/stdout.log" "/Library/Android/sdk/emulator"
  assert_contains "$fixture/stdout.log" "/Library/Android/sdk/platform-tools"
  assert_not_contains "$fixture/stdout.log" '/tools/bin'
  assert_not_contains "$fixture/stdout.log" '/tools:'
}

scenario_run 'usage and help have distinct statuses and streams' test_usage_and_help_are_distinct
scenario_run 'local checks report incomplete state without provisioning' \
  test_check_is_local_and_reports_incomplete_targets
scenario_run 'checks succeed only when selected targets are ready' \
  test_check_succeeds_only_for_ready_selected_targets
scenario_run 'iOS checks accept a real available runtime without a suffix' \
  test_ios_check_accepts_a_real_available_runtime_without_a_suffix
scenario_run 'iOS checks reject a same-version unavailable runtime' \
  test_ios_check_rejects_a_same_version_unavailable_runtime
scenario_run 'iOS checks reject a different-version stale runtime' \
  test_ios_check_rejects_a_different_version_stale_runtime
scenario_run 'iOS observations remain caller-owned values' \
  test_ios_observations_are_caller_owned
scenario_run 'target selection isolates the other platform' \
  test_target_selection_does_not_touch_the_other_platform
scenario_run 'iOS install skips a matching runtime' test_ios_install_skips_a_matching_runtime
scenario_run 'iOS install selects the compatible runtime download' \
  test_ios_install_selects_the_latest_compatible_download
scenario_run 'Android install stops for manual prerequisites' \
  test_android_install_stops_for_manual_prerequisites
scenario_run 'Android freezes resolved paths for each invocation' \
  test_android_freezes_resolved_paths_for_each_invocation
scenario_run 'Android install reconciles packages and creates an absent AVD' \
  test_android_install_reconciles_only_missing_packages_and_creates_an_absent_avd
scenario_run 'Android install skips a compatible AVD' test_android_install_skips_a_compatible_avd
scenario_run 'Android install protects incompatible AVD state' \
  test_android_install_refuses_to_overwrite_an_incompatible_avd
scenario_run 'Android protects incompatible AVDs before package installation' \
  test_android_install_refuses_incompatible_avd_before_missing_package_install
scenario_run 'Android rejects an unready snapshot after package installation' \
  test_android_install_rejects_an_unready_snapshot_after_package_install
scenario_run 'Android requires full readiness after AVD creation' \
  test_android_install_requires_full_readiness_after_avd_creation
scenario_run 'all targets continue after an earlier target fails' \
  test_all_install_continues_after_an_ios_failure
scenario_run 'Android install reports an avdmanager list failure' \
  test_android_install_reports_an_avdmanager_list_failure
scenario_run 'Android package installation closes stdin' \
  test_android_package_install_closes_stdin
scenario_run 'Android tools use Mise Java outside an initialized shell' \
  test_android_tools_use_mise_java_outside_an_initialized_shell
scenario_run 'topic installers warn without provisioning' test_topic_installers_warn_without_provisioning
scenario_run 'shell startup uses one canonical Android root' \
  test_shell_environment_uses_the_canonical_android_root
scenario_finish
