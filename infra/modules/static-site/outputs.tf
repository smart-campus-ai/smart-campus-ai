output "bucket_name" {
  description = "Name of the SPA bucket, target of the front deployment pipeline."
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  description = "ARN of the SPA bucket, scoped in the front deployment role policy."
  value       = aws_s3_bucket.site.arn
}

output "distribution_id" {
  description = "ID of the CloudFront distribution (cache invalidation after a deployment)."
  value       = aws_cloudfront_distribution.site.id
}

output "distribution_arn" {
  description = "ARN of the CloudFront distribution, used in the aws:SourceArn condition of the KMS key policy."
  value       = aws_cloudfront_distribution.site.arn
}

output "distribution_domain_name" {
  description = "Domain name of the distribution (<id>.cloudfront.net), the public entry point while no custom domain exists."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_url" {
  description = "HTTPS URL of the site on the default CloudFront domain."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "response_headers_policy_id" {
  description = "ID of the security headers response policy."
  value       = aws_cloudfront_response_headers_policy.security.id
}
