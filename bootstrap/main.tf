# One-time setup with local state: the remote state bucket and the read-only role GitHub
# Actions uses to run terraform plan.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "compliance-tf-demo"
    }
  }
}

variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "eu-west-1"
}

variable "state_bucket_prefix" {
  description = "Name prefix of the state bucket; a random suffix keeps it globally unique"
  type        = string
  default     = "compliance-tf-demo-tfstate"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to assume the plan role"
  type        = string
  default     = "compliancetf/demo"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one"
  type        = bool
  default     = true
}

resource "random_id" "suffix" {
  byte_length = 4
}

module "state_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.17"

  bucket = "${var.state_bucket_prefix}-${random_id.suffix.hex}"

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  attach_deny_insecure_transport_policy = true
}

module "github_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = "~> 6.8"

  create = var.create_oidc_provider
}

module "plan_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "~> 6.8"

  name            = "compliance-tf-demo-plan"
  use_name_prefix = false
  description     = "Read-only terraform plan from GitHub Actions"

  enable_github_oidc = true
  oidc_subjects = [
    "${var.github_repository}:pull_request",
    "${var.github_repository}:ref:refs/heads/master",
  ]

  policies = {
    ReadOnlyAccess = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  }

  # Read state only: CI plans run with -lock=false, so no lock file writes.
  create_inline_policy = true
  inline_policy_permissions = {
    ListStateBucket = {
      actions   = ["s3:ListBucket"]
      resources = [module.state_bucket.s3_bucket_arn]
    }
    ReadState = {
      actions   = ["s3:GetObject"]
      resources = ["${module.state_bucket.s3_bucket_arn}/*"]
    }
  }

  depends_on = [module.github_oidc_provider]
}

# Resources created before the move to terraform-aws-modules keep their state.
moved {
  from = aws_s3_bucket.state
  to   = module.state_bucket.aws_s3_bucket.this[0]
}

moved {
  from = aws_s3_bucket_versioning.state
  to   = module.state_bucket.aws_s3_bucket_versioning.this[0]
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.state
  to   = module.state_bucket.aws_s3_bucket_server_side_encryption_configuration.this[0]
}

moved {
  from = aws_s3_bucket_public_access_block.state
  to   = module.state_bucket.aws_s3_bucket_public_access_block.this[0]
}

moved {
  from = aws_iam_role.plan
  to   = module.plan_role.aws_iam_role.this[0]
}

moved {
  from = aws_iam_role_policy_attachment.plan_read_only
  to   = module.plan_role.aws_iam_role_policy_attachment.this["ReadOnlyAccess"]
}

output "state_bucket" {
  description = "Name of the remote state bucket"
  value       = module.state_bucket.s3_bucket_id
}

output "plan_role_arn" {
  description = "Role ARN for the AWS_PLAN_ROLE_ARN repository secret"
  value       = module.plan_role.arn
}

output "region" {
  description = "Region of the state bucket"
  value       = var.region
}
