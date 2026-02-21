# OpenClaw AWS Deployment

Terraform configuration for deploying [OpenClaw](https://openclaw.ai) on AWS EC2 with a native Node.js install, secured with hardened SSH and optional Tailscale private networking. Connects to WhatsApp and/or Telegram for messaging.

## Architecture

- **EC2 t3.medium** (Ubuntu 24.04) running OpenClaw natively via Node.js 22 LTS
- **VPC** with public subnet, internet gateway, and restricted security groups
- **Elastic IP** for stable SSH access across instance stop/start cycles
- **SSH on port 2222** with key-only auth, root login disabled
- **UFW firewall** denying all inbound except custom SSH port
- **S3 backend** for Terraform state (versioned, encrypted, no public access)
- **GitHub Actions** CI/CD: plan on PR, apply via manual workflow_dispatch (OIDC auth)

## Prerequisites

1. **AWS account** with an IAM user that has EC2/VPC/S3/IAM permissions
2. **SSH key pair** (e.g. `ssh-keygen -t ed25519`)
3. **API key** from [Anthropic](https://console.anthropic.com/) or [OpenAI](https://platform.openai.com/api-keys)
4. **Terraform >= 1.5** installed locally (for initial bootstrap)
5. **GitHub repository** with these secrets configured (for CI/CD):
   - `PRODUCTION_GITHUB_ACTIONS_ROLE_ARN` (output from backend bootstrap)
   - `SSH_PUBLIC_KEY` (contents of your `.pub` file)
   - `ALLOWED_SSH_CIDRS` (JSON list, e.g. `'["1.2.3.4/32"]'`)

## Quick Start

### Step 1: Bootstrap the S3 State Bucket

This is a one-time step. Run locally:

```bash
cd terraform/backend

# Create a terraform.tfvars with your bucket name
echo 'state_bucket_name = "your-unique-bucket-name-openclaw-tfstate"' > terraform.tfvars

terraform init
terraform apply
```

### Step 2: Configure the S3 Backend

Edit `terraform/environments/prod-v2/providers.tf` and replace the bucket name with the one you created above.

### Step 3: Set Your Variables

```bash
cd terraform/environments/prod-v2
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### Step 4: Deploy

**Locally:**
```bash
cd terraform/environments/prod-v2
terraform init
terraform plan
terraform apply
```

**Via GitHub Actions:**
Push to a PR to see the plan as a PR comment. Trigger the `terraform-apply` workflow manually via `workflow_dispatch` to apply.

### Step 5: Note the Outputs

After apply, Terraform will print:
- `elastic_ip` -- the IP address of your instance
- `ssh_command` -- the exact SSH command to connect
- `dashboard_tunnel_command` -- the SSH tunnel command for the web dashboard

---

## Post-Terraform: OpenClaw Setup

After the infrastructure is up, SSH in and configure OpenClaw.

### 1. SSH into the Instance

```bash
ssh -p 2222 -i ~/.ssh/your-key openclaw@<elastic-ip>
```

The user data script has already installed Node.js, OpenClaw, and ClawHub. Verify:

```bash
node --version
openclaw --version
```

### 2. Run OpenClaw Onboarding

```bash
openclaw onboard
```

The onboarding wizard will prompt you for your API keys, chat channels, and gateway settings.

### 3. Set Up Environment Variables

Fill in your API keys and secrets:

```bash
vi ~/.openclaw/.env
```

### 4. Set Up WhatsApp (Optional)

```bash
openclaw channels login
```

1. A QR code will appear in the terminal
2. Open WhatsApp on your phone > Settings > Linked Devices > Link a Device
3. Scan the QR code
4. Add your phone number to the allowed list when prompted

**Important:** Use a spare phone number, not your personal one. WhatsApp sessions can disconnect and need re-pairing.

### 5. Set Up Telegram

1. Open Telegram and chat with `@BotFather`
2. Send `/newbot` and follow the prompts to create your bot
3. Copy the bot token BotFather gives you (format: `123456789:ABCdefGHI...`)
4. During the onboarding wizard (step 2), select **Telegram (Bot API)** and paste the token

If you need to add Telegram **after** initial setup:

```bash
openclaw channels add
```

Then restart the gateway:

```bash
systemctl --user restart openclaw-gateway
```

### 6. Set Up Google Workspace (gog)

The bootstrap script pre-installs [gog](https://github.com/rubiojr/gog) and creates the config directories. To connect your Google accounts:

1. **Add env vars** to `~/.openclaw/.env`:

```bash
GOG_ACCOUNT=you@example.com
GOG_KEYRING_PASSWORD=your-keyring-password
```

2. **Authenticate** on the EC2 host:

```bash
export GOG_KEYRING_PASSWORD="your-keyring-password"
gog auth add you@example.com --services gmail,calendar,drive
```

gog will print an OAuth URL with a callback port (e.g. `127.0.0.1:PORT`). Open an SSH tunnel for that port from your local machine:

```bash
ssh -p 2222 -i ~/.ssh/your-key -N -L PORT:127.0.0.1:PORT openclaw@<elastic-ip>
```

Then open the OAuth URL in your browser and complete sign-in.

> **Multiple accounts:** Repeat the `gog auth add` step for each Google account. Each auth generates a new callback port that needs its own SSH tunnel.

### 7. Access the Web Dashboard

From your local machine, set up an SSH tunnel:

```bash
ssh -p 2222 -i ~/.ssh/your-key -N -L 18789:127.0.0.1:18789 openclaw@<elastic-ip>
```

Then open this URL in your browser (replace `<token>` with your gateway token):

```
http://localhost:18789/#token=<token>
```

To retrieve the gateway token:

```bash
grep OPENCLAW_GATEWAY_TOKEN ~/.openclaw/.env
```

> **Note:** The bootstrap script pre-configures `controlUi.allowInsecureAuth: true` so the dashboard works over HTTP (the SSH tunnel encrypts traffic end-to-end). No manual config changes needed.

### 8. Verify Everything Works

1. Chat via the web dashboard at http://localhost:18789
2. Send a message via WhatsApp or Telegram
3. Check service health: `openclaw doctor`
4. View logs: `journalctl --user -u openclaw-gateway -f`

### 9. Daily Operations

```bash
# Start the gateway
systemctl --user start openclaw-gateway

# Stop the gateway
systemctl --user stop openclaw-gateway

# Restart after config changes
systemctl --user restart openclaw-gateway

# View live logs
journalctl --user -u openclaw-gateway -f

# Add a channel after initial setup
openclaw channels add

# Update OpenClaw to latest
npm update -g openclaw
systemctl --user restart openclaw-gateway
```

### 10. Post-Setup Hardening

- **Set API spend limits**: Go to your Anthropic/OpenAI console and set a monthly budget
- **Back up agent memory**: `tar -czvf openclaw-backup-$(date +%F).tar.gz ~/.openclaw/`
- **Monitor logs**: `journalctl --user -u openclaw-gateway -f`

---

## Cost Estimate

| Resource | Monthly Cost |
|---|---|
| EC2 t3.medium (on-demand) | ~$30 |
| EBS 30GB gp3 | ~$2.40 |
| Elastic IP (while attached) | $0 |
| S3 state bucket | ~$0 |
| **Total** | **~$33/month** |

Tips to reduce cost:
- Use a Reserved Instance or Savings Plan (~$12/month for t3.medium)
- Stop the instance when not in use (Elastic IP charges $0.005/hr when unattached)

## Tear Down

```bash
cd terraform/environments/prod-v2
terraform destroy
```

## Project Structure

```
terraform/
  backend/                    # S3 state bucket + OIDC role (one-time bootstrap)
  modules/
    networking/               # VPC, subnet, IGW, route tables
    security/                 # Security group, IAM, key pair
    compute/                  # EC2, EBS, Elastic IP, user_data
      scripts/user_data_native.sh  # Cloud-init bootstrap script
  environments/
    prod-v2/                  # Root module wiring everything together
.github/
  workflows/
    terraform-plan.yml        # Runs plan on PRs, posts output as PR comment
    terraform-apply.yml       # Runs apply on manual workflow_dispatch
```
