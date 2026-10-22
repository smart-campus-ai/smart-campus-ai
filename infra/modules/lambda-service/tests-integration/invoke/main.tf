terraform {
  required_version = "~> 1.13.0"
}

variable "function_name" {
  description = "Name of the function to invoke."
  type        = string
}

variable "qualifier" {
  description = "Alias or version to invoke."
  type        = string
}

variable "region" {
  description = "AWS region of the function."
  type        = string
}

# Synchronous invocation through the AWS CLI. The call fails when Lambda cannot assume the execution role. A function
# error (the placeholder code has no handler) still returns HTTP 200 and is accepted.
resource "terraform_data" "invoke" {
  input = "${var.function_name}:${var.qualifier}"

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = "status=$(aws lambda invoke --function-name \"$FUNCTION_NAME\" --qualifier \"$QUALIFIER\" --payload '{}' --cli-binary-format raw-in-base64-out --query StatusCode --output text /dev/null) && [ \"$status\" = \"200\" ]"

    environment = {
      FUNCTION_NAME = var.function_name
      QUALIFIER     = var.qualifier
      AWS_REGION    = var.region
    }
  }
}
