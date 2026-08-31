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
  local missing_packages=''

  for package_name in "${ANDROID_PACKAGES[@]}"; do
    if ! android_package_is_installed "$sdk_root" "$package_name"; then
      if [ -n "$missing_packages" ]; then
        missing_packages+=,
      fi
      missing_packages+=$package_name
    fi
  done

  printf '%s\n' "$missing_packages"
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
  local missing_packages=$1
  local -a package_names=()
  local package_name

  printf 'Android: incomplete — missing packages:'
  IFS=, read -r -a package_names <<<"$missing_packages"
  for package_name in "${package_names[@]}"; do
    printf ' %s' "$package_name"
  done
  printf '\n'
  print_next_step 'Run: mobile-setup android'
}

print_android_manual_prerequisites() {
  local sdk_root=$1
  local sdkmanager=$2

  printf '  → Open Android Studio Setup Wizard and complete it.\n' >&2
  printf '  → Install Android SDK Command-line Tools (latest) under %s.\n' "$sdk_root" >&2
  printf '  → Run the SDK manager interactive license flow yourself: %s --licenses\n' "$sdkmanager" >&2
  printf '    Answer each vendor prompt manually; never pipe answers.\n' >&2
  printf '  → Rerun: mobile-setup android\n' >&2
}

refuse_incompatible_android_avd() {
  printf 'Warning: %s exists but is incompatible; refusing to overwrite it.\n' "$ANDROID_AVD_NAME" >&2
  printf '  → recovery: inspect or rename the existing AVD manually, then rerun: mobile-setup android\n' >&2
  return 1
}

android_classify_state() {
  local sdk_root=$1
  local sdkmanager=$2
  local avdmanager=$3
  local avd_state
  local sdk_root_present=false
  local sdkmanager_present=false
  local avdmanager_present=false
  local licenses_accepted=false
  local missing_packages

  [ -d "$sdk_root" ] && sdk_root_present=true
  [ -x "$sdkmanager" ] && sdkmanager_present=true
  [ -x "$avdmanager" ] && avdmanager_present=true
  [ -f "$sdk_root/licenses/android-sdk-license" ] && licenses_accepted=true
  missing_packages=$(collect_android_missing_packages "$sdk_root")
  avd_state=$(android_avd_state)

  printf '%s|%s|%s|%s|%s|%s\n' \
    "$sdk_root_present" "$sdkmanager_present" "$avdmanager_present" \
    "$licenses_accepted" "$avd_state" "$missing_packages"
}

android_state_is_ready() {
  local state=$1
  local sdk_root_present
  local sdkmanager_present
  local avdmanager_present
  local licenses_accepted
  local avd_state
  local missing_packages

  IFS='|' read -r sdk_root_present sdkmanager_present avdmanager_present \
    licenses_accepted avd_state missing_packages <<<"$state"

  [ "$sdk_root_present" = true ] \
    && [ "$sdkmanager_present" = true ] \
    && [ "$avdmanager_present" = true ] \
    && [ "$licenses_accepted" = true ] \
    && [ "$avd_state" = compatible ] \
    && [ -z "$missing_packages" ]
}

android_state_is_ready_for_avd_creation() {
  local state=$1
  local sdk_root_present
  local sdkmanager_present
  local avdmanager_present
  local licenses_accepted
  local avd_state
  local missing_packages

  IFS='|' read -r sdk_root_present sdkmanager_present avdmanager_present \
    licenses_accepted avd_state missing_packages <<<"$state"

  [ "$sdk_root_present" = true ] \
    && [ "$sdkmanager_present" = true ] \
    && [ "$avdmanager_present" = true ] \
    && [ "$licenses_accepted" = true ] \
    && [ -z "$missing_packages" ] \
    && { [ "$avd_state" = absent ] || [ "$avd_state" = compatible ]; }
}

report_android_readiness() {
  local sdk_root=$1
  local sdkmanager=$2
  local avdmanager=$3
  local state=$4
  local sdk_root_present
  local sdkmanager_present
  local avdmanager_present
  local licenses_accepted
  local avd_state
  local missing_packages
  local failed=0

  IFS='|' read -r sdk_root_present sdkmanager_present avdmanager_present \
    licenses_accepted avd_state missing_packages <<<"$state"

  if [ "$sdk_root_present" != true ]; then
    printf 'Android: incomplete — canonical SDK root is absent: %s\n' "$sdk_root"
    failed=1
  fi

  if [ "$sdkmanager_present" != true ] || [ "$avdmanager_present" != true ]; then
    printf 'Android: incomplete — SDK command-line tools are absent from %s.\n' "$sdk_root"
    if [ "$sdkmanager_present" != true ]; then
      printf '  → sdkmanager expected at %s.\n' "$sdkmanager"
    fi
    if [ "$avdmanager_present" != true ]; then
      printf '  → avdmanager expected at %s.\n' "$avdmanager"
    fi
    print_next_step 'Complete the Android Studio Setup Wizard and install Command-line Tools (latest), then run: mobile-setup android'
    failed=1
  fi

  if [ "$licenses_accepted" != true ]; then
    printf 'Android: incomplete — Android SDK licenses are not accepted at %s.\n' "$sdk_root"
    print_next_step 'Accept Android SDK licenses manually, then run: mobile-setup android'
    failed=1
  fi

  if [ -n "$missing_packages" ]; then
    print_android_missing_packages "$missing_packages"
    failed=1
  fi

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

check_android() {
  local sdk_root
  local sdkmanager
  local avdmanager
  local state

  sdk_root=$(android_sdk_root)
  sdkmanager=$(android_sdkmanager_path "$sdk_root")
  avdmanager=$(android_avdmanager_path "$sdk_root")
  state=$(android_classify_state "$sdk_root" "$sdkmanager" "$avdmanager")
  report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager" "$state"
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
  local state
  local avd_state
  local pixel_device
  local package_name
  local sdk_root_present
  local sdkmanager_present
  local avdmanager_present
  local licenses_accepted
  local missing_packages_csv
  local -a missing_packages=()

  sdk_root=$(android_sdk_root)
  sdkmanager=$(android_sdkmanager_path "$sdk_root")
  avdmanager=$(android_avdmanager_path "$sdk_root")
  state=$(android_classify_state "$sdk_root" "$sdkmanager" "$avdmanager")
  if android_state_is_ready "$state"; then
    report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager" "$state"
    printf 'Android: %s AVD is ready; required packages exist, skipping changes.\n' \
      "$ANDROID_AVD_NAME"
    return 0
  fi
  report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager" "$state" || true

  IFS='|' read -r sdk_root_present sdkmanager_present avdmanager_present \
    licenses_accepted avd_state missing_packages_csv <<<"$state"

  if [ "$sdk_root_present" != true ] || [ "$sdkmanager_present" != true ] \
    || [ "$avdmanager_present" != true ] || [ "$licenses_accepted" != true ]; then
    print_android_manual_prerequisites "$sdk_root" "$sdkmanager"
    return 1
  fi

  if [ "$avd_state" = incompatible ]; then
    refuse_incompatible_android_avd
    return 1
  fi

  if [ -n "$missing_packages_csv" ]; then
    IFS=, read -r -a missing_packages <<<"$missing_packages_csv"
    printf 'Android: installing missing packages:'
    for package_name in "${missing_packages[@]}"; do
      printf ' %s' "$package_name"
    done
    printf '\n'

    if ! run_android_tool "$sdkmanager" --sdk_root="$sdk_root" \
      "${missing_packages[@]}" </dev/null; then
      printf 'Error: Android SDK package installation failed; a required license may still be missing.\n' >&2
      print_android_manual_prerequisites "$sdk_root" "$sdkmanager"
      return 1
    fi

    state=$(android_classify_state "$sdk_root" "$sdkmanager" "$avdmanager")
    IFS='|' read -r sdk_root_present sdkmanager_present avdmanager_present \
      licenses_accepted avd_state missing_packages_csv <<<"$state"
    if ! android_state_is_ready_for_avd_creation "$state"; then
      printf 'Error: Android package installation left the readiness snapshot incomplete.\n' >&2
      report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager" "$state" || true
      return 1
    fi
  fi

  if ! android_state_is_ready_for_avd_creation "$state"; then
    printf 'Error: Android cannot create an AVD from the current readiness snapshot.\n' >&2
    report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager" "$state" || true
    return 1
  fi

  case "$avd_state" in
    compatible)
      printf 'Android: %s AVD is ready; skipping creation.\n' "$ANDROID_AVD_NAME"
      return 0
      ;;
    incompatible)
      refuse_incompatible_android_avd
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

  state=$(android_classify_state "$sdk_root" "$sdkmanager" "$avdmanager")
  if ! android_state_is_ready "$state"; then
    printf 'Error: Android created %s but its final readiness snapshot is incomplete.\n' \
      "$ANDROID_AVD_NAME" >&2
    report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager" "$state" || true
    return 1
  fi

  printf 'Android: %s AVD is ready.\n' "$ANDROID_AVD_NAME"
}
