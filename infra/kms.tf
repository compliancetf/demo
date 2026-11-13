# Lines tagged demo:* are toggled by scripts/demo-mode.sh for the live demo.
locals {
  ops_alerts_topic_name = "${var.name}-ops-alerts"
  # Built from parts, not from the module output, so the key policy does not depend on the topic
  ops_alerts_topic_arn = "arn:${local.partition}:sns:${local.region}:${local.account_id}:${local.ops_alerts_topic_name}"
}

module "kms" {
  source  = "iso27001.compliance.tf/terraform-aws-modules/kms/aws"
  version = "4.2.2"

  description             = "${var.name} CMK for logs and alerts"
  aliases                 = [var.name]
  deletion_window_in_days = 7

  # insecure on purpose: compliance.tf enforces kms_cmk_rotation_enabled
  # demo:insecure enable_key_rotation = false

  # Default policy (account root delegation) stays on; these add the service grants.
  key_statements = [
    {
      sid       = "CloudWatchLogs"
      actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      resources = ["*"]
      principals = [{
        type        = "Service"
        identifiers = ["logs.${local.region}.amazonaws.com"]
      }]
      condition = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*"]
      }]
    },
    {
      sid       = "SNSOpsAlerts"
      actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
      resources = ["*"]
      principals = [{
        type        = "Service"
        identifiers = ["sns.amazonaws.com"]
      }]
      condition = [
        {
          test     = "StringEquals"
          variable = "aws:SourceAccount"
          values   = [local.account_id]
        },
        {
          test     = "ArnLike"
          variable = "aws:SourceArn"
          values   = [local.ops_alerts_topic_arn]
        },
      ]
    },
  ]
}
