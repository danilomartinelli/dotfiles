#!/bin/sh

set -e

echo "› setting up ssh configuration"

# Validate ssh-keygen is available
if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "Error: ssh-keygen is required but not installed." >&2
  exit 1
fi

SSH_DIR="$HOME/.ssh"
DOTFILES_SSH="$HOME/.dotfiles/ssh"

# Validate source config exists
if [ ! -f "$DOTFILES_SSH/config" ]; then
  echo "Error: Source config file not found: $DOTFILES_SSH/config" >&2
  exit 1
fi

# Create SSH directory with correct permissions
if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi

# Remove existing files/links
[ -f "$SSH_DIR/config" ] && rm "$SSH_DIR/config"
[ -L "$SSH_DIR/config" ] && rm "$SSH_DIR/config"

# Create symlinks
ln -s "$DOTFILES_SSH/config" "$SSH_DIR/config"

# Create config_local if it doesn't exist
if [ ! -f "$SSH_DIR/config_local" ]; then
    if [ -f "$DOTFILES_SSH/config_local.example" ]; then
        cp "$DOTFILES_SSH/config_local.example" "$SSH_DIR/config_local"
        chmod 600 "$SSH_DIR/config_local"
        echo "  → created ~/.ssh/config_local (customize it for your servers)"
    else
        echo "Warning: config_local.example not found" >&2
    fi
fi

# Set correct permissions for SSH directory and files
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR"/config* 2>/dev/null || true
find "$SSH_DIR" -name "id_*" -not -name "*.pub" -exec chmod 600 {} \; 2>/dev/null || true
find "$SSH_DIR" -name "*.pub" -exec chmod 644 {} \; 2>/dev/null || true

# Generate SSH keys if they don't exist
# Note: set -e is disabled for this function due to interactive prompts
generate_key() {
    set +e
    local key_name="$1"
    local comment="$2"
    local key_type="$3"
    local key_file="$SSH_DIR/$key_name"

    if [ ! -f "$key_file" ]; then
        echo "  → generating SSH key: $key_name ($key_type)"

        # Prompt for passphrase (optional but recommended for security)
        echo "    Enter passphrase for $key_name (press Enter for no passphrase):"
        echo "    Note: Using a passphrase is strongly recommended for security"

        # Generate key based on type
        if [ "$key_type" = "ed25519" ]; then
            if ssh-keygen -t ed25519 -f "$key_file" -C "$comment"; then
                chmod 600 "$key_file"
                chmod 644 "$key_file.pub"
                echo "    ✓ created $key_file"
            else
                echo "    ✗ Failed to generate $key_name" >&2
                return 1
            fi
        else
            # RSA fallback with 4096 bits for compatibility
            if ssh-keygen -t rsa -b 4096 -f "$key_file" -C "$comment"; then
                chmod 600 "$key_file"
                chmod 644 "$key_file.pub"
                echo "    ✓ created $key_file"
            else
                echo "    ✗ Failed to generate $key_name" >&2
                return 1
            fi
        fi
    else
        echo "  → $key_name already exists, skipping"
    fi
    set -e
}

# Get git email for key comments
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "$(whoami)@$(hostname)")

# Generate modern Ed25519 keys (recommended)
echo ""
echo "  Generating Ed25519 keys (recommended for security)..."
generate_key "id_ed25519" "$GIT_EMAIL" "ed25519" || true
generate_key "id_ed25519_personal" "$GIT_EMAIL (personal)" "ed25519" || true
generate_key "id_ed25519_work" "$GIT_EMAIL (work)" "ed25519" || true

# Generate RSA keys for legacy compatibility only if needed
echo ""
echo -n "  Do you need RSA keys for legacy system compatibility? (y/N): "
read -r need_rsa || need_rsa=""
if [ "$need_rsa" = "y" ] || [ "$need_rsa" = "Y" ]; then
    echo "  Generating RSA keys for compatibility..."
    generate_key "id_rsa" "$GIT_EMAIL" "rsa" || true
    generate_key "id_rsa_personal" "$GIT_EMAIL (personal)" "rsa" || true
    generate_key "id_rsa_work" "$GIT_EMAIL (work)" "rsa" || true
fi

echo ""
echo "✓ ssh configuration complete"
echo ""
echo "📋 Next steps:"
echo "  1. Add your public keys to GitHub, servers, etc:"
echo "     cat ~/.ssh/id_ed25519.pub"
echo "  2. Customize ~/.ssh/config_local with your servers"
echo "  3. Test connections: ssh -T github.com"
echo ""
echo "🔐 Security Notes:"
echo "  - Ed25519 keys are more secure and faster than RSA"
echo "  - Always use passphrases for production keys"
echo "  - Consider using ssh-agent or keychain for passphrase management"
