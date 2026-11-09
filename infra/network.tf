# Lines tagged demo:* are toggled by scripts/demo-mode.sh for the live demo.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 1)]
  public_subnets  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 8, i + 101)]

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = true

  # insecure on purpose: compliance.tf enforces vpc_subnet_auto_assign_public_ip_disabled
  map_public_ip_on_launch = true # demo:insecure

  # Account-and-region wide setting: deploy into a dedicated demo account.
  # block-ingress keeps NAT egress working for the private subnets.
  vpc_block_public_access_options = var.enable_block_public_access ? {
    internet_gateway_block_mode = "block-ingress"
  } : {}

  # The public subnets hold the ALB and the NAT gateway, so they stay reachable
  vpc_block_public_access_exclusions = {
    for i in range(length(local.azs)) : "public-${i}" => {
      exclude_subnet                  = true
      subnet_type                     = "public"
      subnet_index                    = i
      internet_gateway_exclusion_mode = "allow-bidirectional"
    }
  }
}
