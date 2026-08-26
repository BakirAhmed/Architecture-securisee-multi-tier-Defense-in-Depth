output "vpc_id" {
  value = aws_vpc.this.id
}

output "kms_key_arn" {
  value = aws_kms_key.app_key.arn
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_secret.arn
}

output "guardduty_detector_id" {
  value = aws_guardduty_detector.this.id
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.this.arn
}
