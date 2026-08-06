# SOPS helpers. Decrypt prints to stdout by default: decrypting in place
# writes cleartext into the working tree, one `git commit -a` from a leak.
alias sops-encrypt='sops -e -i'
alias sops-decrypt='sops -d'
alias sops-decrypt-inplace='sops -d -i'
alias sops-edit='sops edit'

# Safest usage: secrets only ever exist in the child process environment.
alias sops-env='sops exec-env'
alias sops-run='sops exec-file'
