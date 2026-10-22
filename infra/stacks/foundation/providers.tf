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
# so the stack stays portable to another primary region. Pass it to modules that need CloudFront-scoped
# resources with providers = { aws.us_east_1 = aws.us_east_1 }.
# tflint-ignore: terraform_unused_declarations # kept for portability (ADR-0013); used by CloudFront-scoped resources once the stack is composed
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
