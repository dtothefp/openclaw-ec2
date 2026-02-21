#!/bin/bash
set -euo pipefail

# Log all output for debugging via `sudo cat /var/log/user-data.log`
exec > >(tee /var/log/user-data.log) 2>&1
echo "=== OpenClaw EC2 bootstrap (native) started at $(date) ==="

SSH_PORT="${ssh_port}"
OPENCLAW_USER="${openclaw_user}"
INSTALL_TAILSCALE="${install_tailscale}"
HOME_DIR="/home/$OPENCLAW_USER"

# --- System Updates ---
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# --- Create OpenClaw User ---
adduser --disabled-password --gecos "" "$OPENCLAW_USER"
usermod -aG sudo "$OPENCLAW_USER"

echo "$OPENCLAW_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$OPENCLAW_USER"
chmod 440 "/etc/sudoers.d/$OPENCLAW_USER"

# Copy SSH authorized keys from default ubuntu user
mkdir -p "$HOME_DIR/.ssh"
cp /home/ubuntu/.ssh/authorized_keys "$HOME_DIR/.ssh/"
chown -R "$OPENCLAW_USER:$OPENCLAW_USER" "$HOME_DIR/.ssh"
chmod 700 "$HOME_DIR/.ssh"
chmod 600 "$HOME_DIR/.ssh/authorized_keys"

# --- SSH Hardening ---
cat > /etc/ssh/sshd_config.d/99-openclaw.conf <<SSHEOF
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
SSHEOF

systemctl stop ssh.socket || true
systemctl disable ssh.socket || true
systemctl restart ssh

# --- UFW Firewall ---
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT/tcp"
ufw --force enable

# --- Install Node.js 22 LTS ---
apt-get install -y ca-certificates curl gnupg
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
  | tee /etc/apt/sources.list.d/nodesource.list

apt-get update -y
apt-get install -y nodejs

# --- Install system utilities ---
apt-get install -y tmux jq git build-essential

# --- Install GitHub CLI ---
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | tee /etc/apt/sources.list.d/github-cli.list

apt-get update -y
apt-get install -y gh

# --- Install uv (Python package manager) ---
curl -LsSf https://astral.sh/uv/install.sh | sh
ln -sf /root/.local/bin/uv /usr/local/bin/uv || true

# --- Install gog (Google Workspace CLI) ---
GOG_VERSION="0.11.0"
curl -fsSL "https://github.com/rubiojr/gog/releases/download/v$GOG_VERSION/gog_$${GOG_VERSION}_linux_amd64.tar.gz" \
  | tar -xz -C /usr/local/bin gog
chmod 755 /usr/local/bin/gog

# --- Install Tailscale (optional) ---
if [ "$INSTALL_TAILSCALE" = "true" ]; then
  curl -fsSL https://tailscale.com/install.sh | sh
  echo "Tailscale installed. Run 'sudo tailscale up' to authenticate."
fi

# --- Install OpenClaw + ClawHub globally ---
npm install -g openclaw@latest
npm install -g clawhub

# --- Prepare OpenClaw directories ---
su - "$OPENCLAW_USER" -c "mkdir -p $HOME_DIR/.openclaw/workspace"
su - "$OPENCLAW_USER" -c "mkdir -p $HOME_DIR/.openclaw/skills"
su - "$OPENCLAW_USER" -c "mkdir -p $HOME_DIR/.openclaw/agents"

# --- Prepare gog directories ---
GOG_CONFIG="$HOME_DIR/.config/gogcli"
su - "$OPENCLAW_USER" -c "mkdir -p $GOG_CONFIG/keyring"

# --- Pre-seed openclaw.json ---
cat > "$HOME_DIR/.openclaw/openclaw.json" <<'CFGEOF'
{
  "gateway": {
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-5"
      },
      "subagents": {
        "model": "openrouter/moonshotai/kimi-k2.5"
      }
    }
  },
  "skills": {
    "entries": {
      "brave-search": { "enabled": true },
      "gog": { "enabled": true },
      "github": { "enabled": true },
      "clawhub": { "enabled": true },
      "skill-creator": { "enabled": true },
      "healthcheck": { "enabled": true },
      "weather": { "enabled": true },
      "summarize": { "enabled": true },
      "session-logs": { "enabled": true }
    },
    "install": {
      "nodeManager": "npm"
    }
  },
  "tools": {
    "allow": [
      "read", "write", "edit", "apply_patch",
      "exec", "process",
      "web_search", "web_fetch", "browser", "image",
      "memory_search", "memory_get",
      "sessions_list", "sessions_history", "sessions_send", "sessions_spawn", "session_status",
      "message", "cron", "gateway", "agents_list"
    ],
    "deny": ["nodes", "canvas", "llm_task", "lobster"]
  },
  "approvals": {
    "exec": { "enabled": true }
  }
}
CFGEOF
chown "$OPENCLAW_USER:$OPENCLAW_USER" "$HOME_DIR/.openclaw/openclaw.json"

# --- Create placeholder env file ---
cat > "$HOME_DIR/.openclaw/.env" <<'ENVEOF'
# OpenClaw environment variables
# Fill these in after SSH'ing into the instance.

OPENCLAW_GATEWAY_TOKEN=
ANTHROPIC_API_KEY=
OPENROUTER_API_KEY=
BRAVE_SEARCH_API_KEY=
BRAVE_API_KEY=
LINEAR_API_KEY=
LINEAR_DEFAULT_TEAM=
GOG_ACCOUNT=
GOG_KEYRING_PASSWORD=
ENVEOF
chown "$OPENCLAW_USER:$OPENCLAW_USER" "$HOME_DIR/.openclaw/.env"
chmod 600 "$HOME_DIR/.openclaw/.env"

# --- Install OpenClaw daemon (systemd user service) ---
# Enable lingering so the user's systemd services run without an active login session
loginctl enable-linger "$OPENCLAW_USER"

su - "$OPENCLAW_USER" -c "openclaw onboard --install-daemon" || {
  echo "WARNING: openclaw onboard --install-daemon failed. Set up the daemon manually after SSH."
}

echo ""
echo "=== OpenClaw EC2 bootstrap (native) completed at $(date) ==="
echo "SSH into this instance on port $SSH_PORT as user '$OPENCLAW_USER'"
echo ""
echo "Post-deploy steps:"
echo "  1. Restore migration archive if applicable"
echo "  2. Set up auth: openclaw models auth paste-token --provider anthropic"
echo "  3. Fill in env vars: vi ~/.openclaw/.env"
echo "  4. Start gateway: openclaw gateway --port 18789 --verbose"
echo "  5. Verify: openclaw doctor"
