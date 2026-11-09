output "alb_dns_name" {
  description = "Public DNS name of the ALB"
  value       = module.alb.dns_name
}

output "api_url" {
  description = "URL of the order notifications API"
  value       = local.https_enabled ? "https://${coalesce(var.domain_name, module.alb.dns_name)}" : "http://${module.alb.dns_name}"
}

output "ops_instance_id" {
  description = "Instance ID of the ops host (connect with aws ssm start-session)"
  value       = module.ops.id
}

output "sns_topic_arn" {
  description = "ARN of the ops alerts topic"
  value       = module.sns.topic_arn
}
