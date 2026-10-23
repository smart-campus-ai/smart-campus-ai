"""CKV_SC_2: every aws_kms_key carries the Environment tag.

The apply roles manage KMS keys through aws:ResourceTag/Environment (EN-13): an untagged key is unreachable.

Limitation: provider `default_tags` are not visible to Checkov. The rule is therefore decided on the `tags` argument:
  - missing, empty, or fully known without an Environment key  -> FAILED;
  - an Environment key written in the expression (merge(var.tags, { Environment = ... })) -> PASSED;
  - an expression Checkov cannot resolve (var.tags, local.tags) -> UNKNOWN (not reported). The stack that supplies the
    value is expected to set Environment, either in its default_tags or in the tags it passes down.

Exclusion: resources under modules/state-backend/ or bootstrap/ are excluded because the state backend KMS key is
shared by dev and prod (ADR-0011) and legitimately has no Environment tag.
"""

from __future__ import annotations

import os
import re
from typing import Any

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

ENVIRONMENT_KEY = re.compile(r"(?<![\w/:])\"?Environment\"?\s*[=:]")
REFERENCE = re.compile(r"\b(?:var|local|module|each|data)\.")


class KmsKeyEnvironmentTag(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="Ensure every KMS key has the Environment tag",
            id="CKV_SC_2",
            categories=(CheckCategories.GENERAL_SECURITY,),
            supported_resources=("aws_kms_key",),
        )

    def scan_resource_conf(self, conf: dict[str, list[Any]], **kwargs) -> CheckResult:
        self.evaluated_keys = ["tags"]
        
        # Exclude resources under modules/state-backend/ or bootstrap/
        # Checkov does not pass the file path to resource checks: rely on the resource address.
        address = str(conf.get("__address__", ""))
        if "module.state_backend." in address or address.startswith("aws_kms_key.") and "state-backend" in str(conf.get("__file__", "")):
            return CheckResult.PASSED
        
        tags = conf.get("tags", [None])[0]

        if not tags:
            return CheckResult.FAILED
        if isinstance(tags, dict):
            return CheckResult.PASSED if "Environment" in tags else CheckResult.FAILED
        if isinstance(tags, str):
            if ENVIRONMENT_KEY.search(tags):
                return CheckResult.PASSED
            if REFERENCE.search(tags):
                return CheckResult.UNKNOWN
        return CheckResult.FAILED


check = KmsKeyEnvironmentTag()
