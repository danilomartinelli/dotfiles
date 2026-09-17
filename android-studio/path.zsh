# `_sdk.sh` owns where the SDK is; this file only puts it on PATH.
# bin/opencode-profile asks the same script, so a GUI host and a login shell
# cannot disagree about which tools exist.
export ANDROID_HOME="$("$DOTFILES_ROOT/android-studio/_sdk.sh" root)"
unset ANDROID_SDK_ROOT

_android_path="$("$DOTFILES_ROOT/android-studio/_sdk.sh" path 2>/dev/null)"
if [[ -n $_android_path ]]; then
  export PATH="$PATH:$_android_path"
fi
unset _android_path
