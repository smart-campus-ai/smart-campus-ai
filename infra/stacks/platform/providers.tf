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

# The us-east-1 alias (CloudFront-scoped WAF and ACM) is added with the first resource that needs it (EN-21).
