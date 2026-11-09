# One-time setup with local state: the remote state bucket and the read-only role GitHub
# Actions uses to run terraform plan.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "compliance-tf-demo"
    }
  }
}

resource "random_id" "state_bucket_suffix" {
  byte_length = 4
}

module "state_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.17.0"

  bucket = "${var.state_bucket_prefix}-${random_id.state_bucket_suffix.hex}"

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
  version = "6.8.2"

  create = var.create_oidc_provider
}

module "plan_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

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
