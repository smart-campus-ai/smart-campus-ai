terraform {
  required_version = "~> 1.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"

      # The us-east-1 alias is required for CloudFront-scope WAF alarms.
      configuration_aliases = [aws.us_east_1]
    }
  }
}
