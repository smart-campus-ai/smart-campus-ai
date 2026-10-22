"""CKV_SC_3: every aws_iam_role sets permissions_boundary.

The CI apply role can only create roles that carry the workload boundary: a role without one cannot be applied.
A value that is a reference (var.workload_boundary_arn) counts as set; an empty string or null does not.
"""

from __future__ import annotations

from typing import Any

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck


class RolePermissionsBoundary(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="Ensure every IAM role has a permissions boundary",
            id="CKV_SC_3",
            categories=(CheckCategories.IAM,),
            supported_resources=("aws_iam_role",),
        )

    def scan_resource_conf(self, conf: dict[str, list[Any]]) -> CheckResult:
        self.evaluated_keys = ["permissions_boundary"]
        value = conf.get("permissions_boundary", [None])[0]
        if value is None or (isinstance(value, str) and value.strip() in ("", "null")):
            return CheckResult.FAILED
        return CheckResult.PASSED


check = RolePermissionsBoundary()
