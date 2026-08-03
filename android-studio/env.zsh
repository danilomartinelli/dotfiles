# Prefer mise Temurin for React Native / Android Gradle builds.
# Loaded with other topic *.zsh files after mise activation.
if (( $+commands[mise] )); then
  _java_home=$(mise where java 2>/dev/null)
  if [[ -n $_java_home ]]; then
    export JAVA_HOME="$_java_home"
  fi
  unset _java_home
fi
