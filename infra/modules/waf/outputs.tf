output "web_acl_arn" {
  description = "ARN of the web ACL. Pass it to the CloudFront distribution web_acl_id for the CLOUDFRONT scope."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "ID of the web ACL."
  value       = aws_wafv2_web_acl.this.id
}

output "web_acl_name" {
  description = "Name of the web ACL (<prefix>-waf-<scope>), used by the WAF block alarms."
  value       = aws_wafv2_web_acl.this.name
}

output "log_group_name" {
  description = "Name of the WAF log group (aws-waf-logs-<prefix>-<scope>)."
  value       = aws_cloudwatch_log_group.waf.name
}

output "log_group_arn" {
  description = "ARN of the WAF log group."
  value       = aws_cloudwatch_log_group.waf.arn
}

output "ip_set_arns" {
  description = "ARNs of the IP sets, keyed by allow-ipv4, allow-ipv6, block-ipv4 and block-ipv6 (only the sets that have addresses)."
  value       = { for key, set in aws_wafv2_ip_set.this : key => set.arn }
}
