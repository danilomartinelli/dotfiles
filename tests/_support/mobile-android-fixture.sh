#!/usr/bin/env bash

# Test-only Android layout construction. Keep vendor command behavior in the
# doubles below distinct from the seeded states that these helpers construct.

android_root() {
  printf '%s\n' "$1/home/Library/Android/sdk"
}

android_fixture_package_path() {
  local root=$1
  local package=$2

  case "$package" in
    platform-tools) printf '%s\n' "$root/platform-tools" ;;
    emulator) printf '%s\n' "$root/emulator" ;;
    'cmdline-tools;latest') printf '%s\n' "$root/cmdline-tools/latest" ;;
    'platforms;android-36') printf '%s\n' "$root/platforms/android-36" ;;
    'build-tools;36.0.0') printf '%s\n' "$root/build-tools/36.0.0" ;;
    'system-images;android-36;google_apis;arm64-v8a')
      printf '%s\n' "$root/system-images/android-36/google_apis/arm64-v8a"
      ;;
    *)
      printf 'unknown Android fixture package: %s\n' "$package" >&2
      return 1
      ;;
  esac
}

android_fixture_write_package() {
  local root=$1
  local package=$2
  local directory

  directory=$(android_fixture_package_path "$root" "$package")
  mkdir -p "$directory"
  case "$package" in
    platform-tools)
      : >"$directory/adb"
      chmod +x "$directory/adb"
      ;;
    emulator)
      : >"$directory/emulator"
      chmod +x "$directory/emulator"
      ;;
    'cmdline-tools;latest') ;;
    'platforms;android-36') : >"$directory/android.jar" ;;
    'build-tools;36.0.0')
      : >"$directory/aapt2"
      chmod +x "$directory/aapt2"
      ;;
    'system-images;android-36;google_apis;arm64-v8a')
      : >"$directory/package.xml"
      ;;
  esac
}

android_fixture_remove_package() {
  local root=$1
  local package=$2
  local directory

  directory=$(android_fixture_package_path "$root" "$package")
  case "$package" in
    platform-tools) rm -f "$directory/adb" ;;
    emulator) rm -f "$directory/emulator" ;;
    'cmdline-tools;latest')
      rm -f "$directory/bin/sdkmanager" "$directory/bin/avdmanager"
      ;;
    'platforms;android-36') rm -f "$directory/android.jar" ;;
    'build-tools;36.0.0') rm -f "$directory/aapt" "$directory/aapt2" ;;
    'system-images;android-36;google_apis;arm64-v8a')
      rm -f "$directory/package.xml"
      ;;
  esac
}

install_android_packages() {
  local fixture=$1
  local root
  local package

  root=$(android_root "$fixture")
  for package in \
    platform-tools \
    emulator \
    'cmdline-tools;latest' \
    'platforms;android-36' \
    'build-tools;36.0.0' \
    'system-images;android-36;google_apis;arm64-v8a'; do
    android_fixture_write_package "$root" "$package"
  done
}

write_android_avd() {
  local fixture=$1
  local image=${2:-system-images/android-36/google_apis/arm64-v8a}
  local device=${3:-pixel}
  local avd_directory="$fixture/home/.android/avd/Pixel_API36.avd"

  mkdir -p "$avd_directory"
  printf 'image.sysdir.1=%s\nhw.device.name=%s\n' "$image" "$device" \
    >"$avd_directory/config.ini"
  printf 'path=%s\n' "$avd_directory" >"$fixture/home/.android/avd/Pixel_API36.ini"
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
  if [ -z "${ANDROID_FIXTURE_HELPER:-}" ]; then
    exit 68
  fi
  # shellcheck source=tests/_support/mobile-android-fixture.sh
  . "$ANDROID_FIXTURE_HELPER"
  for package in "$@"; do
    case "$package" in
      --sdk_root=*) ;;
      *) android_fixture_write_package "$sdk_root" "$package" || exit $? ;;
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
    avd_directory="$HOME/.android/avd/$avd_name.avd"
    mkdir -p "$avd_directory"
    printf 'image.sysdir.1=%s\nhw.device.name=%s\n' "$image" "$device" \
      >"$avd_directory/config.ini"
    printf 'path=%s\n' "$avd_directory" >"$HOME/.android/avd/$avd_name.ini"
    if [ "${FAKE_AVDMANAGER_REMOVE_PACKAGE:-0}" -eq 1 ]; then
      if [ -z "${ANDROID_FIXTURE_HELPER:-}" ]; then
        exit 68
      fi
      # shellcheck source=tests/_support/mobile-android-fixture.sh
      . "$ANDROID_FIXTURE_HELPER"
      android_fixture_remove_package \
        "$HOME/Library/Android/sdk" 'platforms;android-36'
    fi
    ;;
esac
exit "${FAKE_AVDMANAGER_STATUS:-0}"
EOF

  mkdir -p "$root/licenses"
  : >"$root/licenses/android-sdk-license"
}
