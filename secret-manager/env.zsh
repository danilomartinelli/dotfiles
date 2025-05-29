# This function gets environment variables from Bitwarden secrets
# Ensure the BWS_PROJECT_ID is set
function bwsenv() {
  local project_id="${BWS_PROJECT_ID}"

  if [ -z "$project_id" ]; then
    echo "echo '❌ BWS_PROJECT_ID não está definido.'" >&2
    return 1
  fi

  bws secret list "$project_id" -o json | jq -r '.[] | "export \(.key | gsub(" "; "_"))=\"\(.value)\""' || {
    echo "echo '❌ Falha ao carregar secrets.'" >&2
    return 1
  }
}

# Load the environment variables from Bitwarden secrets output
_bwsenv_output="$(bwsenv 2>/dev/null)"
if [ $? -eq 0 ] && [ -n "$_bwsenv_output" ]; then
  eval "$_bwsenv_output"
else
  echo "⚠️  BWS secrets não carregados." >&2
fi
