# Credentials Workflow

This document explains how to manage AWS and Kubernetes credentials in your dotfiles setup.

## Overview

Credentials are stored as base64-encoded environment variables in `~/.localrc` (which is gitignored for security). The system provides helper functions to activate these credentials in your shell session using temporary files.

## Adding New Credentials

### Using the Helper Script (Recommended)

The `add-credential` command simplifies adding new credentials:

```bash
# Add AWS credentials
add-credential aws prod ~/.aws/credentials-prod

# Add Kubernetes config
add-credential kube staging ~/kubeconfig-staging.yaml

# List all stored credentials
add-credential list
```

### Manual Method

If you prefer to add credentials manually:

1. **Encode your credential file:**
```bash
# For AWS credentials
base64 < ~/.aws/credentials > /tmp/encoded.txt

# For Kubernetes config
base64 < ~/kubeconfig.yaml > /tmp/encoded.txt
```

2. **Add to ~/.localrc:**
```bash
# AWS Profile (name in uppercase)
export AWS_PROFILE_PROD="<base64-encoded-content>"

# Kubernetes Config (name in uppercase)
export KUBECONFIG_STAGING="<base64-encoded-content>"
```

3. **Reload your shell:**
```bash
source ~/.zshrc
```

## Using Credentials

### AWS Profiles

```bash
# Activate a profile
use_aws_profile prod

# List available profiles
list_aws_profiles

# Show current profile
current_aws_profile

# Clear active profile
clear_aws_profile

# Interactive selection with fzf
aws_profile

# Validate credentials
validate_aws
```

### Kubernetes Configs

```bash
# Activate a config
use_kubeconfig staging

# List available configs
list_kubeconfigs

# Show current config
current_kubeconfig

# Clear active config
clear_kubeconfig

# Interactive selection with fzf
kubeconfig

# Validate connection
validate_kubeconfig
```

## How It Works

1. **Storage**: Credentials are base64-encoded and stored in `~/.localrc` as environment variables
2. **Activation**: When you use `use_aws_profile` or `use_kubeconfig`, the function:
   - Creates a temporary file/directory
   - Decodes the credentials into the temp location
   - Sets the appropriate environment variables to point to the temp file
3. **Security**: Temporary files are created with secure permissions and cleaned up when you clear the profile or start a new session

## Security Considerations

- **Never commit `.localrc`**: This file contains sensitive credentials and is gitignored
- **Temporary files**: Credentials are decoded to temporary files that are:
  - Created with restricted permissions (600)
  - Stored in system temp directory
  - Cleaned up when profile is cleared
- **Base64 is not encryption**: It's encoding for storage convenience, not security. Protect your `.localrc` file!

## Example Workflow

### Setting up AWS credentials for multiple environments

```bash
# Add credentials for different environments
add-credential aws dev ~/.aws/credentials-dev
add-credential aws staging ~/.aws/credentials-staging
add-credential aws prod ~/.aws/credentials-prod

# List what's available
add-credential list

# Switch between environments as needed
use_aws_profile dev    # Work on development
use_aws_profile prod   # Switch to production

# Check current identity
current_aws_profile
```

### Managing multiple Kubernetes clusters

```bash
# Add configs for different clusters
add-credential kube minikube ~/.kube/config-minikube
add-credential kube eks-prod ~/Downloads/kubeconfig-eks.yaml
add-credential kube gke-staging ~/Downloads/kubeconfig-gke.yaml

# Switch between clusters
use_kubeconfig minikube   # Local development
use_kubeconfig eks-prod   # Production cluster

# Use kubectl normally - it will use the active config
kubectl get nodes
kubectl get pods --all-namespaces
```

## Troubleshooting

### "Variable not found" error
- Check that the credential was added correctly with `add-credential list`
- Ensure you've reloaded your shell after adding credentials: `source ~/.zshrc`
- Verify the variable name format: `AWS_PROFILE_<NAME>` or `KUBECONFIG_<NAME>` (uppercase)

### "Failed to decode" error
- The stored credential might be corrupted
- Re-add the credential using `add-credential`

### AWS credentials not working
- Ensure the credentials file has the correct format
- Check if credentials have expired (for temporary/session tokens)
- Run `validate_aws` to test the credentials

### Kubectl connection issues
- Verify the cluster is accessible from your network
- Check if the kubeconfig has the correct server URL
- Run `validate_kubeconfig` to test the connection

## Related Functions

All helper functions are defined in:
- `/functions/use_aws_profile` - Core AWS profile switching
- `/functions/use_kubeconfig` - Core kubeconfig switching
- `/functions/aws_helpers` - Additional AWS utilities
- `/functions/kubeconfig_helpers` - Additional Kubernetes utilities
- `/functions/kubectl_helpers` - Kubectl command shortcuts