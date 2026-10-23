provider "aws" {
  region = "eu-west-3"

  default_tags {
    tags = {
      Project            = "smartcampus"
      Environment        = "dev"
      Owner              = "ops"
      ManagedBy          = "opentofu"
      Repository         = "smart-campus-ai"
      DataClassification = "internal"
    }
  }
}
