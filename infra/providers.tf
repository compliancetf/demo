provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "compliance-tf-demo"
      Framework = "iso27001"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
}
