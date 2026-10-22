terraform {
  required_version = "~> 1.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = "eu-west-3"
}

# Documentation account ID and placeholder key and policy identifiers.
module "lambda_service" {
  source = "../.."

  name_prefix   = "sc-dev"
  function_name = "tickets"
  description   = "Ticket use cases."
  runtime       = "python3.13"
  handler       = "app.handler"

  log_retention_in_days    = 14
  logs_kms_key_arn         = "arn:aws:kms:eu-west-3:123456789012:key/11111111-1111-1111-1111-111111111111"
  environment_kms_key_arn  = "arn:aws:kms:eu-west-3:123456789012:key/33333333-3333-3333-3333-333333333333"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/sc-dev-boundary"

  environment_variables = {
    TABLE_NAME = "sc-dev-tickets"
  }

  enable_dlq      = true
  dlq_kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:key/22222222-2222-2222-2222-222222222222"

  extra_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "TicketsTable"
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"]
      Resource = ["arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets", "arn:aws:dynamodb:eu-west-3:123456789012:table/sc-dev-tickets/index/*"]
    }]
  })
}

output "alias_arn" {
  value = module.lambda_service.alias_arn
}
