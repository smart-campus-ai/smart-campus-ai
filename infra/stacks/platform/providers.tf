provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project            = "smartcampus"
      Environment        = var.env
      Owner              = var.owner
      ManagedBy          = "opentofu"
      Repository         = var.repository
      DataClassification = var.data_classification
    }
  }
}

# Pinned to us-east-1: CloudFront-scoped WAF and ACM only exist there. Kept even when aws_region is us-east-1
# so the stack stays portable to another primary region. Used by the CLOUDFRONT-scope web ACL (waf.tf) through
# providers = { aws = aws.us_east_1 }.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project            = "smartcampus"
      Environment        = var.env
      Owner              = var.owner
      ManagedBy          = "opentofu"
      Repository         = var.repository
      DataClassification = var.data_classification
    }
  }
}
