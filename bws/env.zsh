# Function to load secrets from Bitwarden into environment
load_bws_env() {
  local env_output
  env_output=$(~/.dotfiles/bin/bws secret list --output env 2>/dev/null)

  if [[ -n "$env_output" ]]; then
    # Export each line as environment variable
    while IFS= read -r line; do
      eval "export $line"
    done <<< "$env_output"
  else
    echo "[WARN] Unable to load secrets from Bitwarden."
  fi
}

# Automatically call function when opening shell
# TODO: Before active this We need to improve profile sessions by terminal commands
# Currently all envs are exposed at every terminal session, It is a issue :(
# load_bws_env
