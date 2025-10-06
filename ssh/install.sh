#!/bin/sh

echo "› setting up ssh configuration"

SSH_DIR="$HOME/.ssh"
DOTFILES_SSH="$HOME/.dotfiles/ssh"

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
    cp "$DOTFILES_SSH/config_local.example" "$SSH_DIR/config_local"
    chmod 600 "$SSH_DIR/config_local"
    echo "  → created ~/.ssh/config_local (customize it for your servers)"
fi

# Set correct permissions for SSH directory and files
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR"/config* 2>/dev/null || true
find "$SSH_DIR" -name "id_*" -not -name "*.pub" -exec chmod 600 {} \;
find "$SSH_DIR" -name "*.pub" -exec chmod 644 {} \;

# Generate SSH keys if they don't exist
generate_key() {
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
            ssh-keygen -t ed25519 -f "$key_file" -C "$comment"
        else
            # RSA fallback with 4096 bits for compatibility
            ssh-keygen -t rsa -b 4096 -f "$key_file" -C "$comment"
        fi

        chmod 600 "$key_file"
        chmod 644 "$key_file.pub"
        echo "    ✓ created $key_file"
    fi
}

# Get git email for key comments
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "$(whoami)@$(hostname)")

# Generate modern Ed25519 keys (recommended)
echo ""
echo "  Generating Ed25519 keys (recommended for security)..."
generate_key "id_ed25519" "$GIT_EMAIL" "ed25519"
generate_key "id_ed25519_personal" "$GIT_EMAIL (personal)" "ed25519"
generate_key "id_ed25519_work" "$GIT_EMAIL (work)" "ed25519"

# Generate RSA keys for legacy compatibility only if needed
echo ""
echo -n "  Do you need RSA keys for legacy system compatibility? (y/N): "
read -r need_rsa
if [ "$need_rsa" = "y" ] || [ "$need_rsa" = "Y" ]; then
    echo "  Generating RSA keys for compatibility..."
    generate_key "id_rsa" "$GIT_EMAIL" "rsa"
    generate_key "id_rsa_personal" "$GIT_EMAIL (personal)" "rsa"
    generate_key "id_rsa_work" "$GIT_EMAIL (work)" "rsa"
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