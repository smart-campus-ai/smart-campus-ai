# Workshop exception of ADR-0014 (option B): the workshop account cannot call iam:PutRolePermissionsBoundary, so the
# project permissions boundary may be left off. The exception is fail-closed: the plan fails outside the listed
# accounts, after the expiry day, or when either input is missing.
data "aws_caller_identity" "current" {}

locals {
  # Passed as permissions_boundary_arn to every module that creates an IAM role: null when the exception is active.
  permissions_boundary_arn = var.enable_permissions_boundaries ? var.workload_boundary_arn : null
}

resource "terraform_data" "permissions_boundary_exception" {
  count = var.enable_permissions_boundaries ? 0 : 1

  lifecycle {
    precondition {
      condition     = var.boundary_exception_account_ids != null && contains(coalesce(var.boundary_exception_account_ids, []), data.aws_caller_identity.current.account_id)
      error_message = "ADR-0014: enable_permissions_boundaries = false is only allowed in the accounts listed in boundary_exception_account_ids (the workshop account). Set enable_permissions_boundaries = true and workload_boundary_arn in any other account."
    }

    # The exception ends at the end of boundary_exception_expires (UTC), a null or invalid date fails closed.
    precondition {
      condition     = try(timecmp(plantimestamp(), timeadd("${var.boundary_exception_expires}T00:00:00Z", "24h")) < 0, false)
      error_message = "ADR-0014: the permissions boundary exception has expired or boundary_exception_expires is not set (2026-10-31 at the latest). Set enable_permissions_boundaries = true and workload_boundary_arn."
    }
  }
}
