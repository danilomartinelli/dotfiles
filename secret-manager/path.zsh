# This script sets up the environment from the secret manager.
_bwsenv_output="$(bwsenv 2>/dev/null)"
if [ $? -eq 0 ] && [ -n "$_bwsenv_output" ]; then
  eval "$_bwsenv_output"
else
  echo "⚠️  BWS secrets não carregados (bwsenv falhou ou retornou vazio)." >&2
fi
