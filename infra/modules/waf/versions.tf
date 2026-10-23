terraform {
  required_version = "~> 1.13.0"

  # No configuration_aliases: the module uses the default "aws" provider of the caller. For scope = "CLOUDFRONT" the
  # caller maps its us-east-1 provider: providers = { aws = aws.us_east_1 }.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
