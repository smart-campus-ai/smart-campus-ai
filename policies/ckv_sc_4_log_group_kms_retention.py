"""CKV_SC_4: every aws_cloudwatch_log_group sets kms_key_id and a finite retention_in_days.

retention_in_days = 0 means "never expire" and is rejected. A value that is a reference counts as set.
"""

from __future__ import annotations

from typing import Any

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck


def _is_set(conf: dict[str, list[Any]], key: str) -> bool:
    value = conf.get(key, [None])[0]
    if value is None or isinstance(value, bool):
        return False
    if isinstance(value, str):
        return value.strip() not in ("", "null", "0")
    return value != 0


class LogGroupKmsRetention(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="Ensure every CloudWatch log group is KMS encrypted and has a finite retention",
            id="CKV_SC_4",
            categories=(CheckCategories.LOGGING,),
            supported_resources=("aws_cloudwatch_log_group",),
        )

    def scan_resource_conf(self, conf: dict[str, list[Any]]) -> CheckResult:
        self.evaluated_keys = ["kms_key_id", "retention_in_days"]
        if _is_set(conf, "kms_key_id") and _is_set(conf, "retention_in_days"):
            return CheckResult.PASSED
        return CheckResult.FAILED


check = LogGroupKmsRetention()
