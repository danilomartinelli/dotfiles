alias list-secrets='bws secret list "$BWS_PROJECT_ID" -o json | jq -r ".[].key"'
