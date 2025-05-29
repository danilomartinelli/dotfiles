# Função para carregar secrets do Bitwarden no ambiente
load_bws_env() {
  local env_output
  env_output=$(bws secret list --output env 2>/dev/null)

  if [[ -n "$env_output" ]]; then
    # Exporta cada linha como variável de ambiente
    while IFS= read -r line; do
      eval "export $line"
    done <<< "$env_output"
  else
    echo "[WARN] Não foi possível carregar secrets do Bitwarden."
  fi
}

# Chama a função automaticamente ao abrir shell
load_bws_env
