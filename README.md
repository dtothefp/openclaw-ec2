# OpenClaw AWS Deployment

Terraform configuration for deploying [OpenClaw](https://openclaw.ai) on AWS EC2 with Docker, secured with hardened SSH and optional Tailscale private networking. Connects to WhatsApp and/or Telegram for messaging.

## Architecture

- **EC2 t3.medium** (Ubuntu 24.04) running OpenClaw in Docker containers
- **VPC** with public subnet, internet gateway, and restricted security groups
- **Elastic IP** for stable SSH access across instance stop/start cycles
- **SSH on port 2222** with key-only auth, root login disabled
- **UFW firewall** denying all inbound except custom SSH port
- **S3 backend** for Terraform state (versioned, encrypted, no public access)
- **GitHub Actions** CI/CD: plan on PR, apply on merge to main

## Prerequisites

1. **AWS account** with an IAM user that has EC2/VPC/S3/IAM permissions
2. **SSH key pair** (e.g. `ssh-keygen -t ed25519`)
3. **API key** from [Anthropic](https://console.anthropic.com/) or [OpenAI](https://platform.openai.com/api-keys)
4. **Terraform >= 1.5** installed locally (for initial bootstrap)
5. **GitHub repository** with these secrets configured (for CI/CD):
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
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
Push to a PR to see the plan. Merge to `main` to apply.

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

| Prompt | Selection |
|---|---|
| Accept risk warning | Yes |
| Onboarding mode | Manual |
| Gateway setup | Local gateway (this machine) |
| Workspace directory | Press Enter (accept default) |
| Model provider | Anthropic (or OpenAI) |
| API key | Paste your key |
| Default model | claude-sonnet-4-5 (or your preference) |
| Gateway port | 18789 (default) |
| Gateway bind | localhost (or Tailnet if using Tailscale) |
| Gateway auth | Token |
| Gateway token | Press Enter to auto-generate, then **save it** |
| Configure chat channels | Yes |
| Configure skills | No (can add later) |
| Enable hooks | Skip for now |

### 3. Set Up WhatsApp (Optional)

```bash
docker compose run --rm openclaw-cli channels login
```

1. A QR code will appear in the terminal
2. Open WhatsApp on your phone > Settings > Linked Devices > Link a Device
3. Scan the QR code
4. Add your phone number to the allowed list when prompted

**Important:** Use a spare phone number, not your personal one. WhatsApp sessions can disconnect and need re-pairing.

### 4. Set Up Telegram (Optional)

1. Open Telegram and chat with `@BotFather`
2. Send `/newbot` and follow the prompts to create your bot
3. Copy the bot token BotFather gives you
4. Add it to OpenClaw:

```bash
docker compose run --rm openclaw-cli channels add --channel telegram --token "YOUR_BOT_TOKEN"
```

5. Restart the gateway:

```bash
docker compose restart
```

6. Open Telegram, search for your bot, and send it a message

### 5. Access the Web Dashboard

From your local machine, set up an SSH tunnel:

```bash
ssh -p 2222 -i ~/.ssh/your-key -L 18789:localhost:18789 openclaw@<elastic-ip>
```

Then open http://localhost:18789 in your browser. Go to **Overview > Gateway Token**, paste the token from step 2, and click **Connect**.

### 6. Enable HTTP Auth (Required for Dashboard)

Since we access over HTTP (via SSH tunnel, which encrypts the traffic), we need to allow insecure auth:

```bash
# Install jq in the container
docker compose exec -u root openclaw-gateway bash -c "apt update && apt install -y jq"

# Enable insecure auth
docker compose exec -T openclaw-gateway bash -c '
jq ".gateway.controlUi.allowInsecureAuth = true" \
/home/node/.openclaw/openclaw.json > /home/node/.openclaw/tmp.json && \
mv /home/node/.openclaw/tmp.json /home/node/.openclaw/openclaw.json'

# Restart to apply
docker compose restart
```

This is safe because the SSH tunnel already encrypts all traffic end-to-end.

### 7. Verify Everything Works

1. Chat via the web dashboard at http://localhost:18789
2. Send a message via WhatsApp or Telegram
3. Check container health: `docker compose ps`
4. View logs: `docker compose logs -f`

### 8. Post-Setup Hardening

- **Set API spend limits**: Go to your Anthropic/OpenAI console and set a monthly budget
- **Enable sandbox mode**: OpenClaw defaults to sandboxed tool execution in Docker containers
- **Back up agent memory**: `tar -czvf openclaw-backup-$(date +%F).tar.gz ~/.openclaw/`
- **Monitor logs**: `docker compose logs -f`

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
- Use t3.small ($15/month) if you don't need sandbox containers

## Tear Down

```bash
cd terraform/environments/prod
terraform destroy
```

## Project Structure

```
terraform/
  backend/                    # S3 state bucket (one-time bootstrap)
  modules/
    networking/               # VPC, subnet, IGW, route tables
    security/                 # Security group, IAM, key pair
    compute/                  # EC2, EBS, Elastic IP, user_data
      scripts/user_data.sh    # Cloud-init bootstrap script
  environments/
    prod/                     # Root module wiring everything together
.github/
  workflows/
    terraform.yml             # CI/CD: plan on PR, apply on merge
```
