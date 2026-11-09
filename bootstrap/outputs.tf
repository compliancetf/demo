output "state_bucket" {
  description = "Name of the remote state bucket (repository variable TF_STATE_BUCKET)"
  value       = module.state_bucket.s3_bucket_id
}

output "plan_role_arn" {
  description = "ARN of the GitHub Actions plan role (repository variable AWS_PLAN_ROLE_ARN)"
  value       = module.plan_role.arn
}

output "region" {
  description = "Region of the state bucket (repository variable AWS_REGION)"
  value       = var.region
}
