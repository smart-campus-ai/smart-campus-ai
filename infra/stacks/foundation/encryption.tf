# Client-side encryption of state and plan files (EN-12 AC4), on top of the SSE-KMS of the state bucket.
# The key ARN comes from the bootstrap output; it is not a secret. Variables are allowed here (OpenTofu early evaluation).
terraform {
  encryption {
    key_provider "aws_kms" "state" {
      kms_key_id = var.state_kms_key_arn
      region     = var.aws_region
      key_spec   = "AES_256"
    }

    method "aes_gcm" "state" {
      keys = key_provider.aws_kms.state
    }

    state {
      method   = method.aes_gcm.state
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }
}
