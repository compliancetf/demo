module "zone" {
  source  = "iso27001.compliance.tf/terraform-aws-modules/route53/aws"
  version = "6.5.1"

  name    = "order.internal"
  comment = "Private names for the ${var.name} stack"

  vpc = {
    main = { vpc_id = module.vpc.vpc_id }
  }

  records = {
    ops = {
      name    = "ops"
      type    = "A"
      ttl     = 300
      records = [module.ops.private_ip]
    }
    api = {
      name = "api"
      type = "A"
      alias = {
        name    = module.alb.dns_name
        zone_id = module.alb.zone_id
      }
    }
  }
}
