variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "order-notifications"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_block_public_access" {
  description = "Turn on VPC Block Public Access (block-ingress). It applies to every VPC in the account and region, so use a dedicated demo account"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "NAT gateway for private subnet egress (image pulls, SSM). Off, the ECS task cannot start and the ALB returns 503"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Public DNS name of the API, used in the api_url output when HTTPS is on"
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the HTTPS listener. Null keeps the ALB HTTP only"
  type        = string
  default     = null
}

variable "container_image" {
  description = "Container image of the API"
  type        = string
  default     = "public.ecr.aws/nginx/nginx:stable-alpine"
}
