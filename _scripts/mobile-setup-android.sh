#!/usr/bin/env bash
#
# Private Android Emulator provisioning implementation for mobile-setup.

ANDROID_SYSTEM_IMAGE='system-images;android-36;google_apis;arm64-v8a'
ANDROID_SYSTEM_IMAGE_PATH=${ANDROID_SYSTEM_IMAGE//;/\/}
ANDROID_AVD_NAME='Pixel_API36'
ANDROID_PACKAGES=(
  'platform-tools'
  'emulator'
  'cmdline-tools;latest'
  'platforms;android-36'
  'build-tools;36.0.0'
  "$ANDROID_SYSTEM_IMAGE"
)
ANDROID_MISSING_PACKAGES=()

android_sdk_root() {
  printf '%s\n' "$HOME/Library/Android/sdk"
}

android_sdkmanager_path() {
  printf '%s/cmdline-tools/latest/bin/sdkmanager\n' "$1"
}

android_avdmanager_path() {
  printf '%s/cmdline-tools/latest/bin/avdmanager\n' "$1"
}

android_java_home() {
  local mise_java_home

  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    printf '%s\n' "$JAVA_HOME"
    return 0
  fi

  if command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v mise >/dev/null 2>&1; then
    return 0
  fi

  mise_java_home=$(mise where java 2>/dev/null) || return 0
  if [ -x "$mise_java_home/bin/java" ]; then
    printf '%s\n' "$mise_java_home"
  fi
}

run_android_tool() {
  local java_home

  java_home=$(android_java_home)
  if [ -n "$java_home" ]; then
    JAVA_HOME="$java_home" "$@"
    return
  fi

  if [ -n "${JAVA_HOME:-}" ] && [ ! -x "$JAVA_HOME/bin/java" ]; then
    env -u JAVA_HOME "$@"
    return
  fi

  "$@"
}

android_package_is_installed() {
  local sdk_root=$1
  local package_name=$2

  case "$package_name" in
    platform-tools)
      [ -x "$sdk_root/platform-tools/adb" ]
      ;;
    emulator)
      [ -x "$sdk_root/emulator/emulator" ]
      ;;
    'cmdline-tools;latest')
      [ -x "$sdk_root/cmdline-tools/latest/bin/sdkmanager" ] \
        && [ -x "$sdk_root/cmdline-tools/latest/bin/avdmanager" ]
      ;;
    'platforms;android-36')
      [ -f "$sdk_root/platforms/android-36/android.jar" ]
      ;;
    'build-tools;36.0.0')
      [ -x "$sdk_root/build-tools/36.0.0/aapt" ] \
        || [ -x "$sdk_root/build-tools/36.0.0/aapt2" ]
      ;;
    "$ANDROID_SYSTEM_IMAGE")
      [ -f "$sdk_root/system-images/android-36/google_apis/arm64-v8a/package.xml" ]
      ;;
    *)
      printf 'Error: unknown Android package declaration: %s\n' "$package_name" >&2
      return 1
      ;;
  esac
}

collect_android_missing_packages() {
  local sdk_root=$1
  local package_name

  ANDROID_MISSING_PACKAGES=()
  for package_name in "${ANDROID_PACKAGES[@]}"; do
    if ! android_package_is_installed "$sdk_root" "$package_name"; then
      ANDROID_MISSING_PACKAGES+=("$package_name")
    fi
  done
}

android_avd_state() {
  local avd_root=$HOME/.android/avd
  local avd_directory=$avd_root/$ANDROID_AVD_NAME.avd
  local avd_ini=$avd_root/$ANDROID_AVD_NAME.ini
  local config_file=$avd_directory/config.ini
  local image_path
  local device_name

  if [ ! -e "$avd_directory" ] && [ ! -e "$avd_ini" ]; then
    printf 'absent\n'
    return 0
  fi

  if [ ! -f "$config_file" ]; then
    printf 'incompatible\n'
    return 0
  fi

  image_path=$(sed -n 's/^image\.sysdir\.1=//p' "$config_file")
  image_path=${image_path#./}
  image_path=${image_path%/}
  device_name=$(sed -n 's/^hw\.device\.name=//p' "$config_file")

  if [ "$image_path" != "$ANDROID_SYSTEM_IMAGE" ] \
    && [ "$image_path" != "$ANDROID_SYSTEM_IMAGE_PATH" ]; then
    printf 'incompatible\n'
    return 0
  fi

  case "$device_name" in
    *[Pp][Ii][Xx][Ee][Ll]*) printf 'compatible\n' ;;
    *) printf 'incompatible\n' ;;
  esac
}

print_android_missing_packages() {
  local package_name

  printf 'Android: incomplete — missing packages:'
  for package_name in "${ANDROID_MISSING_PACKAGES[@]}"; do
    printf ' %s' "$package_name"
  done
  printf '\n'
  print_next_step 'Run: mobile-setup android'
}

print_android_manual_prerequisites() {
  local sdk_root=$1
  local sdkmanager

  sdkmanager=$(android_sdkmanager_path "$sdk_root")
  printf '  → Open Android Studio Setup Wizard and complete it.\n' >&2
  printf '  → Install Android SDK Command-line Tools (latest) under %s.\n' "$sdk_root" >&2
  printf '  → Run the SDK manager interactive license flow yourself: %s --licenses\n' "$sdkmanager" >&2
  printf '    Answer each vendor prompt manually; never pipe answers.\n' >&2
  printf '  → Rerun: mobile-setup android\n' >&2
}

check_android() {
  local sdk_root
  local sdkmanager
  local avdmanager
  local avd_state
  local failed=0

  sdk_root=$(android_sdk_root)
  sdkmanager=$(android_sdkmanager_path "$sdk_root")
  avdmanager=$(android_avdmanager_path "$sdk_root")

  if [ ! -d "$sdk_root" ]; then
    printf 'Android: incomplete — canonical SDK root is absent: %s\n' "$sdk_root"
    failed=1
  fi

  if [ ! -x "$sdkmanager" ] || [ ! -x "$avdmanager" ]; then
    printf 'Android: incomplete — SDK command-line tools are absent from %s.\n' "$sdk_root"
    print_next_step 'Complete the Android Studio Setup Wizard and install Command-line Tools (latest), then run: mobile-setup android'
    failed=1
  fi

  if [ ! -f "$sdk_root/licenses/android-sdk-license" ]; then
    printf 'Android: incomplete — Android SDK licenses are not accepted at %s.\n' "$sdk_root"
    print_next_step 'Accept Android SDK licenses manually, then run: mobile-setup android'
    failed=1
  fi

  collect_android_missing_packages "$sdk_root"
  if [ "${#ANDROID_MISSING_PACKAGES[@]}" -gt 0 ]; then
    print_android_missing_packages
    failed=1
  fi

  avd_state=$(android_avd_state)
  case "$avd_state" in
    absent)
      printf 'Android: incomplete — %s AVD is absent.\n' "$ANDROID_AVD_NAME"
      print_next_step 'Run: mobile-setup android'
      failed=1
      ;;
    incompatible)
      printf 'Android: incomplete — %s AVD exists with incompatible state.\n' "$ANDROID_AVD_NAME"
      print_next_step 'Recover the AVD manually without deleting existing state, then run: mobile-setup android'
      failed=1
      ;;
  esac

  if [ "$failed" -eq 0 ]; then
    printf 'Android: ready — %s is configured for API 36 google_apis arm64-v8a.\n' "$ANDROID_AVD_NAME"
    return 0
  fi
  return 1
}

find_pixel_device() {
  local avdmanager=$1
  local device_listing

  if ! device_listing=$(run_android_tool "$avdmanager" list device 2>/dev/null); then
    printf 'Error: avdmanager could not list available Pixel hardware profiles.\n' >&2
    printf '  → Verify Command-line Tools and Java, then rerun: mobile-setup android\n' >&2
    return 1
  fi

  printf '%s\n' "$device_listing" | awk '
    tolower($1) == "id:" && tolower($0) ~ /pixel/ {
      value = $0
      sub(/^[^:]*:[[:space:]]*/, "", value)
      if (value ~ /[[:space:]]or[[:space:]]/) {
        prefix = value
        sub(/[[:space:]]+or.*$/, "", prefix)
        if (prefix ~ /^[0-9]+$/) {
          sub(/^.*[[:space:]]or[[:space:]]*"/, "", value)
          sub(/".*$/, "", value)
        } else {
          value = prefix
        }
      }
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  '
}

install_android() {
  local sdk_root
  local sdkmanager
  local avdmanager
  local avd_state
  local pixel_device
  local package_name

  if check_android; then
    printf 'Android: %s AVD is ready; required packages exist, skipping changes.\n' \
      "$ANDROID_AVD_NAME"
    return 0
  fi

  sdk_root=$(android_sdk_root)
  sdkmanager=$(android_sdkmanager_path "$sdk_root")
  avdmanager=$(android_avdmanager_path "$sdk_root")

  if [ ! -d "$sdk_root" ] || [ ! -x "$sdkmanager" ] || [ ! -x "$avdmanager" ] \
    || [ ! -f "$sdk_root/licenses/android-sdk-license" ]; then
    print_android_manual_prerequisites "$sdk_root"
    return 1
  fi

  avd_state=$(android_avd_state)
  if [ "$avd_state" = incompatible ]; then
    printf 'Warning: %s exists but is incompatible; refusing to overwrite it.\n' "$ANDROID_AVD_NAME" >&2
    printf '  → recovery: inspect or rename the existing AVD manually, then rerun: mobile-setup android\n' >&2
    return 1
  fi

  collect_android_missing_packages "$sdk_root"
  if [ "${#ANDROID_MISSING_PACKAGES[@]}" -gt 0 ]; then
    printf 'Android: installing missing packages:'
    for package_name in "${ANDROID_MISSING_PACKAGES[@]}"; do
      printf ' %s' "$package_name"
    done
    printf '\n'

    if ! run_android_tool "$sdkmanager" --sdk_root="$sdk_root" \
      "${ANDROID_MISSING_PACKAGES[@]}" </dev/null; then
      printf 'Error: Android SDK package installation failed; a required license may still be missing.\n' >&2
      print_android_manual_prerequisites "$sdk_root"
      return 1
    fi

    collect_android_missing_packages "$sdk_root"
    if [ "${#ANDROID_MISSING_PACKAGES[@]}" -gt 0 ]; then
      printf 'Error: Android package installation did not provide every required package.\n' >&2
      print_android_missing_packages >&2
      return 1
    fi
  fi

  avd_state=$(android_avd_state)
  case "$avd_state" in
    compatible)
      printf 'Android: %s AVD is ready; skipping creation.\n' "$ANDROID_AVD_NAME"
      return 0
      ;;
    incompatible)
      printf 'Warning: %s exists but is incompatible; refusing to overwrite it.\n' "$ANDROID_AVD_NAME" >&2
      printf '  → recovery: inspect or rename the existing AVD manually, then rerun: mobile-setup android\n' >&2
      return 1
      ;;
  esac

  if ! pixel_device=$(find_pixel_device "$avdmanager"); then
    return 1
  fi
  if [ -z "$pixel_device" ]; then
    printf 'Error: no available Pixel hardware profile was found.\n' >&2
    printf '  → Install an available Pixel device profile in Android Studio, then rerun: mobile-setup android\n' >&2
    return 1
  fi

  printf 'Android: creating %s with Pixel profile %s.\n' "$ANDROID_AVD_NAME" "$pixel_device"
  if ! run_android_tool "$avdmanager" create avd \
    -n "$ANDROID_AVD_NAME" \
    -k "$ANDROID_SYSTEM_IMAGE" \
    --device "$pixel_device"; then
    printf 'Error: Android could not create %s.\n' "$ANDROID_AVD_NAME" >&2
    printf '  → Resolve the vendor tooling error without deleting an existing AVD, then rerun: mobile-setup android\n' >&2
    return 1
  fi

  if [ "$(android_avd_state)" != compatible ]; then
    printf 'Error: Android created %s but its state is not compatible with this declaration.\n' \
      "$ANDROID_AVD_NAME" >&2
    return 1
  fi

  printf 'Android: %s AVD is ready.\n' "$ANDROID_AVD_NAME"
}
