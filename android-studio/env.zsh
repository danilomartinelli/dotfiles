# Prefer mise Temurin for React Native / Android Gradle builds.
# Startup prepares Mise before topic configuration. A failed activation leaves
# the previous Java environment intact instead of querying an unprepared one.
if [[ ${_dotfiles_mise_ready:-0} == 1 ]] && (( $+commands[mise] )); then
  _java_home=$(mise where java 2>/dev/null)
  if [[ -n $_java_home ]]; then
    export JAVA_HOME="$_java_home"
  fi
  unset _java_home
fi
