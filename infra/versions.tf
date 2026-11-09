terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
  }

  # bucket and region come from backend.hcl (make bootstrap writes it)
  backend "s3" {
    key          = "demo/infra.tfstate"
    use_lockfile = true
  }
}
