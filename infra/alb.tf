locals {
  https_enabled = var.certificate_arn != null

  http_listener = {
    http = merge(
      { port = 80, protocol = "HTTP" },
      local.https_enabled ? {
        redirect = { port = "443", protocol = "HTTPS", status_code = "HTTP_301" }
      } : { forward = { target_group_key = "api" } },
    )
  }

  https_listener = local.https_enabled ? {
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = var.certificate_arn
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      forward         = { target_group_key = "api" }
    }
  } : {}

  alb_ingress = merge(
    {
      http = { from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0", description = "HTTP from the internet" }
    },
    local.https_enabled ? {
      https = { from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0", description = "HTTPS from the internet" }
    } : {},
  )
}

module "alb" {
  # Public entry point by design; exception recorded.
  # Compensating controls: access logs, security group allows only 80/443, targets stay private.
  source = "https://iso27001.compliance.tf/terraform-aws-modules/alb/aws?version=10.5.1&disable=elb_application_classic_network_lb_prohibit_public_access"

  name     = var.name
  internal = false
  vpc_id   = module.vpc.vpc_id
  subnets  = module.vpc.public_subnets

  # demo stack: make destroy must work
  enable_deletion_protection = false

  access_logs = {
    # reads the policy resource so the ALB waits until log delivery is allowed
    bucket = aws_s3_bucket_policy.alb_logs.bucket
    prefix = "alb"
  }

  security_group_ingress_rules = local.alb_ingress
  security_group_egress_rules = {
    vpc = {
      description = "To targets inside the VPC"
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  listeners = merge(local.http_listener, local.https_listener)

  target_groups = {
    api = {
      name_prefix       = "api-"
      protocol          = "HTTP"
      port              = 80
      target_type       = "ip"
      create_attachment = false # ECS registers the tasks

      health_check = {
        path    = "/"
        matcher = "200"
      }
    }
  }
}
