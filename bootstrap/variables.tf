variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "eu-west-1"
  nullable    = false
}

variable "state_bucket_prefix" {
  description = "Name prefix of the state bucket; a random suffix keeps it globally unique"
  type        = string
  default     = "compliance-tf-demo-tfstate"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{2,53}$", var.state_bucket_prefix))
    error_message = "state_bucket_prefix must be 3-54 lowercase letters, digits or hyphens (the suffix adds 9 characters)."
  }
}

variable "github_repository" {
  description = "GitHub repository (owner/name) allowed to assume the plan role"
  type        = string
  default     = "compliancetf/demo"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one"
  type        = bool
  default     = true
  nullable    = false
}
