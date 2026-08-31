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

ANDROID_SDK_ROOT_PRESENT=false
ANDROID_SDKMANAGER_PRESENT=false
ANDROID_AVDMANAGER_PRESENT=false
ANDROID_LICENSES_ACCEPTED=false
ANDROID_AVD_STATE=absent
ANDROID_MISSING_PACKAGES=''
# The action the conditions above permit. install_android switches on this once
# instead of re-deriving the same conjunction from the six fields, which it did
# three further times and got wrong the last time: the case it ran after the
# readiness gate had an arm the gate has already ruled out.
ANDROID_NEXT_ACTION=manual-prerequisites

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
  local next_sdk_root_present=false
  local next_sdkmanager_present=false
  local next_avdmanager_present=false
  local next_licenses_accepted=false
  local next_avd_state
  local next_missing_packages

  ANDROID_SDK_ROOT_PRESENT=false
  ANDROID_SDKMANAGER_PRESENT=false
  ANDROID_AVDMANAGER_PRESENT=false
  ANDROID_LICENSES_ACCEPTED=false
  ANDROID_AVD_STATE=absent
  ANDROID_MISSING_PACKAGES=''

  [ -d "$sdk_root" ] && next_sdk_root_present=true
  [ -x "$sdkmanager" ] && next_sdkmanager_present=true
  [ -x "$avdmanager" ] && next_avdmanager_present=true
  [ -f "$sdk_root/licenses/android-sdk-license" ] && next_licenses_accepted=true
  if ! next_missing_packages=$(collect_android_missing_packages "$sdk_root"); then
    return 1
  fi
  if ! next_avd_state=$(android_avd_state); then
    return 1
  fi

  ANDROID_SDK_ROOT_PRESENT=$next_sdk_root_present
  ANDROID_SDKMANAGER_PRESENT=$next_sdkmanager_present
  ANDROID_AVDMANAGER_PRESENT=$next_avdmanager_present
  ANDROID_LICENSES_ACCEPTED=$next_licenses_accepted
  ANDROID_AVD_STATE=$next_avd_state
  ANDROID_MISSING_PACKAGES=$next_missing_packages
  ANDROID_NEXT_ACTION=$(android_permitted_action)
}

# The one place that turns the conditions into what may happen next. Ordered by
# what has to be true before the next thing can be: nothing can be installed
# without the tools and the licenses, and an incompatible AVD stops the run
# before any package work rather than after it.
android_permitted_action() {
  if [ "$ANDROID_SDK_ROOT_PRESENT" != true ] \
    || [ "$ANDROID_SDKMANAGER_PRESENT" != true ] \
    || [ "$ANDROID_AVDMANAGER_PRESENT" != true ] \
    || [ "$ANDROID_LICENSES_ACCEPTED" != true ]; then
    printf 'manual-prerequisites\n'
  elif [ "$ANDROID_AVD_STATE" = incompatible ]; then
    printf 'recover-avd\n'
  elif [ -n "$ANDROID_MISSING_PACKAGES" ]; then
    printf 'install-packages\n'
  elif [ "$ANDROID_AVD_STATE" = absent ]; then
    printf 'create-avd\n'
  else
    printf 'none\n'
  fi
}

android_state_is_ready() {
  [ "$ANDROID_SDK_ROOT_PRESENT" = true ] \
    && [ "$ANDROID_SDKMANAGER_PRESENT" = true ] \
    && [ "$ANDROID_AVDMANAGER_PRESENT" = true ] \
    && [ "$ANDROID_LICENSES_ACCEPTED" = true ] \
    && [ "$ANDROID_AVD_STATE" = compatible ] \
    && [ -z "$ANDROID_MISSING_PACKAGES" ]
}

report_android_readiness() {
  local sdk_root=$1
  local sdkmanager=$2
  local avdmanager=$3
  local failed=0

  if [ "$ANDROID_SDK_ROOT_PRESENT" != true ]; then
    printf 'Android: incomplete — canonical SDK root is absent: %s\n' "$sdk_root"
    failed=1
  fi

  if [ "$ANDROID_SDKMANAGER_PRESENT" != true ] || [ "$ANDROID_AVDMANAGER_PRESENT" != true ]; then
    printf 'Android: incomplete — SDK command-line tools are absent from %s.\n' "$sdk_root"
    if [ "$ANDROID_SDKMANAGER_PRESENT" != true ]; then
      printf '  → sdkmanager expected at %s.\n' "$sdkmanager"
    fi
    if [ "$ANDROID_AVDMANAGER_PRESENT" != true ]; then
      printf '  → avdmanager expected at %s.\n' "$avdmanager"
    fi
    print_next_step 'Complete the Android Studio Setup Wizard and install Command-line Tools (latest), then run: mobile-setup android'
    failed=1
  fi

  if [ "$ANDROID_LICENSES_ACCEPTED" != true ]; then
    printf 'Android: incomplete — Android SDK licenses are not accepted at %s.\n' "$sdk_root"
    print_next_step 'Accept Android SDK licenses manually, then run: mobile-setup android'
    failed=1
  fi

  if [ -n "$ANDROID_MISSING_PACKAGES" ]; then
    print_android_missing_packages "$ANDROID_MISSING_PACKAGES"
    failed=1
  fi

  case "$ANDROID_AVD_STATE" in
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

  sdk_root=$(android_sdk_root)
  sdkmanager=$(android_sdkmanager_path "$sdk_root")
  avdmanager=$(android_avdmanager_path "$sdk_root")
  if ! android_classify_state "$sdk_root" "$sdkmanager" "$avdmanager"; then
    return 1
  fi
  report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager"
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
  local pixel_device
  local package_name
  local -a missing_packages=()

  sdk_root=$(android_sdk_root)
  sdkmanager=$(android_sdkmanager_path "$sdk_root")
  avdmanager=$(android_avdmanager_path "$sdk_root")
  if ! android_classify_state "$sdk_root" "$sdkmanager" "$avdmanager"; then
    return 1
  fi
  if android_state_is_ready; then
    report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager"
    printf 'Android: %s AVD is ready; required packages exist, skipping changes.\n' \
      "$ANDROID_AVD_NAME"
    return 0
  fi
  report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager" || true

  case "$ANDROID_NEXT_ACTION" in
    manual-prerequisites)
      print_android_manual_prerequisites "$sdk_root" "$sdkmanager"
      return 1
      ;;
    recover-avd)
      refuse_incompatible_android_avd
      return 1
      ;;
  esac

  if [ "$ANDROID_NEXT_ACTION" = install-packages ]; then
    IFS=, read -r -a missing_packages <<<"$ANDROID_MISSING_PACKAGES"
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

    if ! android_classify_state "$sdk_root" "$sdkmanager" "$avdmanager"; then
      return 1
    fi
    case "$ANDROID_NEXT_ACTION" in
      create-avd | none) ;;
      *)
        printf 'Error: Android package installation left the readiness snapshot incomplete.\n' >&2
        report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager" || true
        return 1
        ;;
    esac
  fi

  # Installing packages is the only step that can leave the AVD already usable,
  # so this is the one place the run can end without creating one. Nothing
  # re-tests the prerequisites here: the action the record permits was decided
  # when the record was written.
  if [ "$ANDROID_NEXT_ACTION" = none ]; then
    printf 'Android: %s AVD is ready; skipping creation.\n' "$ANDROID_AVD_NAME"
    return 0
  fi

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

  if ! android_classify_state "$sdk_root" "$sdkmanager" "$avdmanager"; then
    return 1
  fi
  if ! android_state_is_ready; then
    printf 'Error: Android created %s but its final readiness snapshot is incomplete.\n' \
      "$ANDROID_AVD_NAME" >&2
    report_android_readiness "$sdk_root" "$sdkmanager" "$avdmanager" || true
    return 1
  fi

  printf 'Android: %s AVD is ready.\n' "$ANDROID_AVD_NAME"
}
