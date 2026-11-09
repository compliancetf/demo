# Lines tagged demo:* are toggled by scripts/demo-mode.sh for the live demo.
locals {
  # insecure on purpose: compliance.tf enforces cloudwatch_log_group_retention_period_365
  # demo:insecure log_retention_days = 7
  log_retention_days = 30 # demo:secure

  # insecure on purpose: compliance.tf enforces log_group_encryption_at_rest_enabled
  # demo:insecure log_kms_key_id = null
  log_kms_key_id = module.kms.key_arn # demo:secure
}

module "ecs" {
  source = "https://iso27001.compliance.tf/terraform-aws-modules/ecs/aws?version=7.6.1&disable=cloudwatch_log_group_retention_period_365"

  cluster_name = var.name

  cloudwatch_log_group_retention_in_days = local.log_retention_days
  cloudwatch_log_group_kms_key_id        = local.log_kms_key_id

  services = {
    api = {
      cpu           = 256
      memory        = 512
      desired_count = 1

      subnet_ids = module.vpc.private_subnets

      # insecure on purpose: compliance.tf enforces ecs_service_not_publicly_accessible
      # demo:insecure assign_public_ip = true

      container_definitions = {
        nginx = {
          image     = var.container_image
          essential = true
          # nginx writes its cache and pid files to the root filesystem
          readonlyRootFilesystem = false
          portMappings = [{
            name          = "http"
            containerPort = 80
            protocol      = "tcp"
          }]

          cloudwatch_log_group_retention_in_days = local.log_retention_days
          cloudwatch_log_group_kms_key_id        = local.log_kms_key_id
        }
      }

      load_balancer = {
        api = {
          target_group_arn = module.alb.target_groups["api"].arn
          container_name   = "nginx"
          container_port   = 80
        }
      }

      security_group_ingress_rules = {
        alb_http = {
          description                  = "HTTP from the ALB only"
          from_port                    = 80
          to_port                      = 80
          referenced_security_group_id = module.alb.security_group_id
        }
      }
      security_group_egress_rules = {
        all = {
          description = "Image pulls and outbound calls through the NAT gateway"
          ip_protocol = "-1"
          cidr_ipv4   = "0.0.0.0/0"
        }
      }
    }
  }
}
