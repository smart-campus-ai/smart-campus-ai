provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project            = "smartcampus"
      Environment        = "shared"
      Owner              = var.owner
      ManagedBy          = "opentofu"
      Repository         = var.repository
      DataClassification = var.data_classification
    }
  }
}
