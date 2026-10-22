<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.13.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.70.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudfront_distribution.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_origin_access_control.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_cloudfront_origin_request_policy.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_request_policy) | resource |
| [aws_cloudfront_response_headers_policy.security](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_response_headers_policy) | resource |
| [aws_s3_bucket.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_ownership_controls.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_abort_incomplete_multipart_upload_days"></a> [abort\_incomplete\_multipart\_upload\_days](#input\_abort\_incomplete\_multipart\_upload\_days) | Number of days after which an incomplete multipart upload is aborted. | `number` | `7` | no |
| <a name="input_acm_certificate_arn"></a> [acm\_certificate\_arn](#input\_acm\_certificate\_arn) | ARN of the ACM certificate (us-east-1) for aliases. Null keeps the default CloudFront certificate, for which CloudFront enforces its own TLS floor and ignores the minimum protocol version; with a certificate the minimum is TLSv1.2\_2021. | `string` | `null` | no |
| <a name="input_aliases"></a> [aliases](#input\_aliases) | Alternate domain names (CNAMEs) of the distribution. Empty while no custom domain exists (ADR-0003); requires acm\_certificate\_arn when set. | `list(string)` | `[]` | no |
| <a name="input_api_origin_domain_name"></a> [api\_origin\_domain\_name](#input\_api\_origin\_domain\_name) | Domain name of the API Gateway REST API origin (for example "abc123.execute-api.eu-west-3.amazonaws.com", EN-33). When set, the "/api/*" behaviour is created with caching disabled and the Authorization header forwarded. Null serves the SPA only. | `string` | `null` | no |
| <a name="input_api_origin_path"></a> [api\_origin\_path](#input\_api\_origin\_path) | Stage path prepended to the requests sent to the API origin (for example "/live"). Empty for none. | `string` | `""` | no |
| <a name="input_content_security_policy"></a> [content\_security\_policy](#input\_content\_security\_policy) | Value of the Content-Security-Policy response header, aligned with SE (SPA sources, Cognito endpoint). It must contain frame-ancestors 'none'. | `string` | n/a | yes |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the customer-managed KMS key (EN-14, data domain) used for the default SSE-KMS encryption of the bucket. Its key policy must let the CloudFront service principal (cloudfront.amazonaws.com) call kms:Decrypt and kms:GenerateDataKey* with an aws:SourceArn condition on the distribution, otherwise OAC reads fail. | `string` | n/a | yes |
| <a name="input_logging_bucket_name"></a> [logging\_bucket\_name](#input\_logging\_bucket\_name) | Name of an existing bucket that receives the CloudFront standard logs and the S3 server access logs of the site bucket. Null disables both. The bucket must be encrypted, have a log retention and allow the CloudFront and S3 logging services to write to it (CloudFront standard logging needs ACLs enabled on the target). | `string` | `null` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix of every resource name, in the form sc-<env> (for example "sc-dev"). | `string` | n/a | yes |
| <a name="input_noncurrent_version_expiration_days"></a> [noncurrent\_version\_expiration\_days](#input\_noncurrent\_version\_expiration\_days) | Number of days after which noncurrent object versions (previous SPA builds) are permanently deleted. | `number` | `30` | no |
| <a name="input_price_class"></a> [price\_class](#input\_price\_class) | CloudFront price class. PriceClass\_100 (North America and Europe) is enough for a campus audience in France. | `string` | `"PriceClass_100"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags applied to every taggable resource, merged with the provider default\_tags. | `map(string)` | `{}` | no |
| <a name="input_web_acl_id"></a> [web\_acl\_id](#input\_web\_acl\_id) | ARN of the CLOUDFRONT-scope WAFv2 web ACL (us-east-1, RF04) attached to the distribution. Null leaves the distribution without WAF. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the SPA bucket, scoped in the front deployment role policy. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the SPA bucket, target of the front deployment pipeline. |
| <a name="output_distribution_arn"></a> [distribution\_arn](#output\_distribution\_arn) | ARN of the CloudFront distribution, used in the aws:SourceArn condition of the KMS key policy. |
| <a name="output_distribution_domain_name"></a> [distribution\_domain\_name](#output\_distribution\_domain\_name) | Domain name of the distribution (<id>.cloudfront.net), the public entry point while no custom domain exists. |
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | ID of the CloudFront distribution (cache invalidation after a deployment). |
| <a name="output_response_headers_policy_id"></a> [response\_headers\_policy\_id](#output\_response\_headers\_policy\_id) | ID of the security headers response policy. |
| <a name="output_site_url"></a> [site\_url](#output\_site\_url) | HTTPS URL of the site on the default CloudFront domain. |
<!-- END_TF_DOCS -->