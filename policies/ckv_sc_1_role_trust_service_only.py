"""CKV_SC_1: the assume_role_policy of an aws_iam_role allows only Service principals.

Federated (OIDC) trust belongs to the github-oidc module, which is excluded. A policy that is a reference
(data.aws_iam_policy_document.x.json) cannot be read at resource level: it is covered by CKV_SC_5.
"""

from __future__ import annotations

import json
from typing import Any

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.common.util.type_forcers import force_list
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

EXCLUDED_PATH = "/infra/modules/github-oidc/"


def _parse_policy(raw: Any) -> dict[str, Any] | None:
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
        except ValueError:
            return None
        return parsed if isinstance(parsed, dict) else None
    return None


def _service_only(statement: Any) -> bool:
    if not isinstance(statement, dict):
        return False
    if statement.get("Effect", "Allow") != "Allow":
        return True
    if "NotPrincipal" in statement:
        return False
    principal = statement.get("Principal")
    return isinstance(principal, dict) and set(principal) == {"Service"}


def _github_oidc_only(statement: Any) -> bool:
    """Return True if the statement is a Federated sts:AssumeRoleWithWebIdentity pinned on ':sub' and ':aud'."""
    if not isinstance(statement, dict):
        return False
    if statement.get("Effect", "Allow") != "Allow":
        return True
    if "NotPrincipal" in statement:
        return False
    principal = statement.get("Principal")
    if not isinstance(principal, dict) or set(principal) != {"Federated"}:
        return False
    if set(force_list(statement.get("Action", []))) != {"sts:AssumeRoleWithWebIdentity"}:
        return False
    condition = statement.get("Condition")
    if not isinstance(condition, dict):
        return False
    string_equals = condition.get("StringEquals", {})
    if not isinstance(string_equals, dict):
        return False
    # Only the end of the key is matched: the issuer part may be an unresolved interpolation ("${local.oidc_host}:sub").
    return any(str(k).endswith(":sub") for k in string_equals) and any(str(k).endswith(":aud") for k in string_equals)


class RoleTrustServiceOnly(BaseResourceCheck):
    def __init__(self) -> None:
        super().__init__(
            name="Ensure the trust policy of an IAM role allows only Service principals",
            id="CKV_SC_1",
            categories=(CheckCategories.IAM,),
            supported_resources=("aws_iam_role",),
        )

    def scan_resource_conf(self, conf: dict[str, list[Any]]) -> CheckResult:
        if EXCLUDED_PATH in self.entity_path.replace("\\", "/"):
            return CheckResult.UNKNOWN

        raw = conf.get("assume_role_policy", [None])[0]
        policy = _parse_policy(raw)
        if policy is None:
            # A reference or an expression that cannot be resolved.
            return CheckResult.UNKNOWN

        self.evaluated_keys = ["assume_role_policy"]
        statements = force_list(policy.get("Statement", []))
        if statements and all(_service_only(s) or _github_oidc_only(s) for s in statements):
            return CheckResult.PASSED
        return CheckResult.FAILED


check = RoleTrustServiceOnly()
