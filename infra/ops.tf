# Lines tagged demo:* are toggled by scripts/demo-mode.sh for the live demo.
module "ops" {
  source  = "iso27001.compliance.tf/terraform-aws-modules/ec2-instance/aws"
  version = "6.4.1"

  name              = "${var.name}-ops"
  instance_type     = "t4g.micro"
  ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
  # a newer AMI must not replace the host on every plan
  ignore_ami_changes = true

  subnet_id                   = module.vpc.private_subnets[0]
  associate_public_ip_address = false

  # SSM Session Manager only: no key pair, no inbound rules
  create_iam_instance_profile = true
  iam_role_description        = "SSM access for the ${var.name} ops host"
  iam_role_policies = {
    ssm = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  security_group_ingress_rules = {}

  root_block_device = {
    encrypted = true
    type      = "gp3"
  }

  # insecure on purpose: compliance.tf enforces ec2_instance_uses_imdsv2
  # demo:insecure metadata_options = { http_tokens = "optional" }
}
