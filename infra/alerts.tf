# Lines tagged demo:* are toggled by scripts/demo-mode.sh for the live demo.
module "sns" {
  source  = "iso27001.compliance.tf/terraform-aws-modules/sns/aws"
  version = "7.2.0"

  name = local.ops_alerts_topic_name

  # insecure on purpose: compliance.tf enforces sns_topic_encrypted_at_rest
  # demo:insecure kms_master_key_id = null
  kms_master_key_id = module.kms.key_arn # demo:secure
}
