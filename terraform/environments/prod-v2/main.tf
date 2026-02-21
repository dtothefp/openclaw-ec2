module "networking" {
  source = "../../modules/networking"

  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  availability_zone  = var.availability_zone
}

module "security" {
  source = "../../modules/security"

  project_name      = var.project_name
  vpc_id            = module.networking.vpc_id
  ssh_port          = var.ssh_port
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  ssh_public_key    = var.ssh_public_key
  enable_ssm        = var.enable_ssm
}

module "compute" {
  source = "../../modules/compute"

  project_name          = var.project_name
  instance_type         = var.instance_type
  subnet_id             = module.networking.public_subnet_id
  security_group_id     = module.security.security_group_id
  key_pair_name         = module.security.key_pair_name
  instance_profile_name = module.security.instance_profile_name
  root_volume_size      = var.root_volume_size
  ssh_port              = var.ssh_port
  openclaw_user         = var.openclaw_user
  install_tailscale     = var.install_tailscale
}
