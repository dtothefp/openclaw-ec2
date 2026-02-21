# OpenClaw AWS Deployment

Terraform configuration for deploying [OpenClaw](https://openclaw.ai) on AWS EC2 with Docker, secured with hardened SSH and optional Tailscale private networking. Connects to WhatsApp and/or Telegram for messaging.

## Architecture

- **EC2 t3.medium** (Ubuntu 24.04) running OpenClaw in Docker containers
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

Edit `terraform/environments/prod/providers.tf` and replace `REPLACE_WITH_YOUR_BUCKET_NAME` with the bucket name you created above.

### Step 3: Set Your Variables

```bash
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### Step 4: Deploy

**Locally:**

```bash
cd terraform/environments/prod
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

The user data script has already installed Docker and cloned the OpenClaw repo. Verify:

```bash
docker --version
ls ~/openclaw
```

### 2. Run OpenClaw Docker Setup

```bash
cd ~/openclaw
./docker-setup.sh
```

The onboarding wizard will prompt you. Recommended selections:

| Prompt                       | Selection                                             |
| ---------------------------- | ----------------------------------------------------- |
| Gateway mode                 | Local gateway                                         |
| Gateway bind                 | **LAN (0.0.0.0)** -- required for Docker port mapping |
| Gateway auth                 | Token                                                 |
| Gateway token                | Press Enter to auto-generate                          |
| Tailscale exposure           | Off                                                   |
| Install daemon               | No                                                    |
| API key                      | Paste your Anthropic (or OpenAI) key                  |
| Configure chat channels      | Yes                                                   |
| Channel type                 | Telegram (Bot API), then paste your bot token         |
| Add another channel          | **Finish** (do NOT press ESC)                         |
| Configure DM access policies | No (default pairing is fine)                          |
| Configure skills             | No (can add later)                                    |
| Enable hooks                 | Skip for now                                          |

**Important:** Complete every prompt -- do not press ESC to exit early. The config file (`~/.openclaw/openclaw.json`) is only written when the wizard finishes.

### 3. Set Up WhatsApp (Optional)

```bash
docker compose run --rm openclaw-cli channels login
```

1. A QR code will appear in the terminal
2. Open WhatsApp on your phone > Settings > Linked Devices > Link a Device
3. Scan the QR code
4. Add your phone number to the allowed list when prompted

**Important:** Use a spare phone number, not your personal one. WhatsApp sessions can disconnect and need re-pairing.

### 4. Set Up Telegram

1. Open Telegram and chat with `@BotFather`
2. Send `/newbot` and follow the prompts to create your bot
3. Copy the bot token BotFather gives you (format: `123456789:ABCdefGHI...`)
4. During the onboarding wizard (step 2), select **Telegram (Bot API)** and paste the token

If you need to add Telegram **after** initial setup:

```bash
cd ~/openclaw
docker compose run --rm openclaw-cli channels add
```

Follow the interactive prompts, then restart the gateway:

```bash
docker compose restart openclaw-gateway
```

### 5. Set Up Google Workspace (gog)

The bootstrap script pre-installs [gog](https://github.com/rubiojr/gog) and creates the config directories. To connect your Google accounts:

1. **Add env vars** to `~/openclaw/.env`:

```bash
GOG_ACCOUNT=you@example.com
GOG_KEYRING_PASSWORD=your-keyring-password
OPENROUTER_API_KEY=your-openrouter-api-key
BRAVE_SEARCH_API_KEY=your-brave-search-api-key
```

> **Sub-agents & search:** The bootstrap config delegates sub-agent tasks to a free model via [OpenRouter](https://openrouter.ai) (Kimi K2.5, $0/token) and enables [Brave Search](https://api-dashboard.search.brave.com/) ($5/month free credit = ~1,000 searches/month). Both keys are optional -- the agent works without them but won't be able to spawn cheap sub-agents or do web searches.

2. **Authenticate** on the EC2 host (not inside Docker):

```bash
export GOG_KEYRING_PASSWORD="your-keyring-password"
gog auth add you@example.com --services gmail,calendar,drive
```

gog will print an OAuth URL with a callback port (e.g. `127.0.0.1:PORT`). Open an SSH tunnel for that port from your local machine:

```bash
ssh -p 2222 -i ~/.ssh/your-key -N -L PORT:127.0.0.1:PORT openclaw@<elastic-ip>
```

Then open the OAuth URL in your browser and complete sign-in.

3. **Fix token permissions** so the Docker container can read them:

```bash
sudo chmod 644 ~/.config/gogcli/keyring/token:*
```

4. **Test from the container**:

```bash
docker compose exec openclaw-gateway gog gmail search "is:unread" --max 3
```

> **Multiple accounts:** Repeat the `gog auth add` step for each Google account. Each auth generates a new callback port that needs its own SSH tunnel. To add accounts with many services, split into smaller batches (e.g. `gmail,calendar` then `drive,contacts`) to avoid URL truncation issues in the browser.

> **Permissions note:** The `~/.config/gogcli` directory is set to `777` so both the host user and Docker container (uid 1000) can access it. After each `gog auth add`, token files default to `600` (owner-only) -- the `chmod 644` step above is required after every new auth.

### 6. Access the Web Dashboard

From your local machine, set up an SSH tunnel:

```bash
ssh -p 2222 -i ~/.ssh/your-key -N -L 18789:127.0.0.1:18789 openclaw@<elastic-ip>
```

Then open this URL in your browser (replace `<token>` with your gateway token from the `.env` file):

```
http://localhost:18789/#token=<token>
```

To retrieve the gateway token:

```bash
grep OPENCLAW_GATEWAY_TOKEN ~/openclaw/.env
```

> **Note:** The `user_data.sh` bootstrap script pre-configures `controlUi.allowInsecureAuth: true` so the dashboard works over HTTP (the SSH tunnel encrypts traffic end-to-end). No manual config changes needed.

> **Token mismatch:** The `.env` file (used by the Docker container) and `~/.openclaw/openclaw.json` (used by the wizard) may have different tokens. The running gateway uses the `.env` token. If the dashboard shows "pairing required", verify the token in your URL matches the one in `.env`.

### 7. Verify Everything Works

1. Chat via the web dashboard at http://localhost:18789
2. Send a message via WhatsApp or Telegram
3. Check container health: `docker compose ps`
4. View logs: `docker compose logs -f`

### 8. Daily Operations

You only need to run `./docker-setup.sh` **once** for initial setup. After that:

```bash
cd ~/openclaw

# Start the gateway
docker compose up -d openclaw-gateway

# Stop the gateway
docker compose down

# Restart after config changes
docker compose restart openclaw-gateway

# View live logs
docker compose logs -f openclaw-gateway

# Add a channel after initial setup
docker compose run --rm openclaw-cli channels add

# Update OpenClaw to latest
cd ~/openclaw && git pull
docker compose down
./docker-setup.sh
```

### 9. Post-Setup Hardening

- **Set API spend limits**: Go to your Anthropic/OpenAI console and set a monthly budget
- **Enable sandbox mode**: OpenClaw defaults to sandboxed tool execution in Docker containers
- **Back up agent memory**: `tar -czvf openclaw-backup-$(date +%F).tar.gz ~/.openclaw/`
- **Monitor logs**: `docker compose logs -f`

---

## Cost Estimate

| Resource                    | Monthly Cost   |
| --------------------------- | -------------- |
| EC2 t3.medium (on-demand)   | ~$30           |
| EBS 30GB gp3                | ~$2.40         |
| Elastic IP (while attached) | $0             |
| S3 state bucket             | ~$0            |
| **Total**                   | **~$33/month** |

Tips to reduce cost:

- Use a Reserved Instance or Savings Plan (~$12/month for t3.medium)
- Stop the instance when not in use (Elastic IP charges $0.005/hr when unattached)
- Use t3.small ($15/month) if you don't need sandbox containers

## Tear Down

```bash
cd terraform/environments/prod
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
      scripts/user_data.sh    # Cloud-init bootstrap script
  environments/
    prod/                     # Root module wiring everything together
.github/
  workflows/
    terraform-plan.yml        # Runs plan on PRs, posts output as PR comment
    terraform-apply.yml       # Runs apply on manual workflow_dispatch
```
