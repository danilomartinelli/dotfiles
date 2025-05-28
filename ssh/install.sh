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
find "$SSH_DIR" -type f -exec chmod 600 {} \;
find "$SSH_DIR" -type d -exec chmod 700 {} \;

# Generate SSH keys if they don't exist
generate_key() {
    local key_name="$1"
    local comment="$2"
    local key_file="$SSH_DIR/$key_name"
    
    if [ ! -f "$key_file" ]; then
        echo "  → generating SSH key: $key_name"
        ssh-keygen -t ed25519 -f "$key_file" -C "$comment" -N ""
        chmod 600 "$key_file"
        chmod 644 "$key_file.pub"
        echo "    ✓ created $key_file"
    fi
}

# Get git email for key comments
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "$(whoami)@$(hostname)")

# Generate common SSH keys
generate_key "id_rsa" "$GIT_EMAIL"
generate_key "id_rsa_personal" "$GIT_EMAIL (personal)"
generate_key "id_rsa_work" "$GIT_EMAIL (work)"

echo "✓ ssh configuration complete"
echo ""
echo "📋 Next steps:"
echo "  1. Add your public keys to GitHub, servers, etc:"
echo "     cat ~/.ssh/id_rsa.pub"
echo "  2. Customize ~/.ssh/config_local with your servers"
echo "  3. Test connections: ssh -T github.com"