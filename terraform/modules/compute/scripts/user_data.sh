#!/bin/bash
set -euo pipefail

# Log all output for debugging via `sudo cat /var/log/user-data.log`
exec > >(tee /var/log/user-data.log) 2>&1
echo "=== OpenClaw EC2 bootstrap started at $(date) ==="

SSH_PORT="${ssh_port}"
OPENCLAW_USER="${openclaw_user}"
INSTALL_TAILSCALE="${install_tailscale}"

# --- System Updates ---
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# --- Create OpenClaw User ---
adduser --disabled-password --gecos "" "$OPENCLAW_USER"
usermod -aG sudo "$OPENCLAW_USER"

# Allow passwordless sudo for the openclaw user
echo "$OPENCLAW_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$OPENCLAW_USER"
chmod 440 "/etc/sudoers.d/$OPENCLAW_USER"

# Copy SSH authorized keys from default ubuntu user
mkdir -p "/home/$OPENCLAW_USER/.ssh"
cp /home/ubuntu/.ssh/authorized_keys "/home/$OPENCLAW_USER/.ssh/"
chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "/home/$OPENCLAW_USER/.ssh"
chmod 700 "/home/$OPENCLAW_USER/.ssh"
chmod 600 "/home/$OPENCLAW_USER/.ssh/authorized_keys"

# --- SSH Hardening ---
cat > /etc/ssh/sshd_config.d/99-openclaw.conf <<SSHEOF
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
SSHEOF

# Disable systemd socket activation (Ubuntu 24.04 holds port 22 open otherwise)
systemctl stop ssh.socket || true
systemctl disable ssh.socket || true
systemctl restart ssh

# --- UFW Firewall ---
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp"
ufw --force enable

# --- Install Docker ---
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add openclaw user to docker group
usermod -aG docker "$OPENCLAW_USER"

# --- Install Tailscale (optional) ---
if [ "$INSTALL_TAILSCALE" = "true" ]; then
  curl -fsSL https://tailscale.com/install.sh | sh
  echo "Tailscale installed. Run 'sudo tailscale up' to authenticate."
fi

# --- Clone OpenClaw ---
su - "$OPENCLAW_USER" -c "git clone https://github.com/openclaw/openclaw.git /home/$OPENCLAW_USER/openclaw"

# --- Prepare OpenClaw directories ---
su - "$OPENCLAW_USER" -c "mkdir -p /home/$OPENCLAW_USER/.openclaw/workspace"
# Docker container runs as 'node' (uid 1000) -- must match ownership
chown -R 1000:1000 "/home/$OPENCLAW_USER/.openclaw"
chmod -R 775 "/home/$OPENCLAW_USER/.openclaw"
chmod -R 775 "/home/$OPENCLAW_USER/openclaw"

# Pre-seed config to allow dashboard access over HTTP (SSH tunnel)
cat > "/home/$OPENCLAW_USER/.openclaw/openclaw.json" <<'CFGEOF'
{
  "gateway": {
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true
    }
  }
}
CFGEOF
chown 1000:1000 "/home/$OPENCLAW_USER/.openclaw/openclaw.json"

echo "=== OpenClaw EC2 bootstrap completed at $(date) ==="
echo "SSH into this instance on port $SSH_PORT as user '$OPENCLAW_USER'"
echo "Then run: cd ~/openclaw && ./docker-setup.sh"
