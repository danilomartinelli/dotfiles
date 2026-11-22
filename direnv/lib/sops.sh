# shellcheck shell=bash
#
# `use sops [file]` for an .envrc: load a project's secrets from a
# SOPS-encrypted dotenv file, by default secrets.sops.env beside the .envrc.
#
# The secrets exist decrypted only in the environment direnv builds for that
# directory, and leave it when the shell does. direnv reloads when the file
# changes. direnv/install.sh links this file into ~/.config/direnv/lib, which
# direnv's stdlib sources.

use_sops() {
  local file=${1:-secrets.sops.env}
  local secrets

  watch_file "$file"
  if [ ! -f "$file" ]; then
    log_error "use sops: $file does not exist"
    return 1
  fi
  if ! secrets=$(sops decrypt --input-type dotenv --output-type dotenv "$file"); then
    log_error "use sops: could not decrypt $file"
    return 1
  fi
  eval "$(printf '%s\n' "$secrets" | direnv dotenv bash /dev/stdin)"
}
