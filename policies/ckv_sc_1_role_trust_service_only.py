"""CKV_SC_1: the assume_role_policy of an aws_iam_role allows only Service principals.

A Federated principal is accepted only for the GitHub OIDC provider, with sts:AssumeRoleWithWebIdentity, StringEquals
on ':aud' = sts.amazonaws.com and StringEquals on ':sub' values starting with "repo:smart-campus-ai/smart-campus-ai:"
(no wildcard). Unresolved interpolations in a value are accepted when the operator is StringEquals: Checkov cannot
resolve them. The github-oidc module is excluded. A policy that is a reference
(data.aws_iam_policy_document.x.json) cannot be read at resource level: it is covered by CKV_SC_5.
"""

from __future__ import annotations

import json
import re
from typing import Any

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.common.util.type_forcers import force_list
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

EXCLUDED_PATH = "/infra/modules/github-oidc/"

GITHUB_OIDC_HOST = "token.actions.githubusercontent.com"
GITHUB_OIDC_PROVIDER_SUFFIX = f"oidc-provider/{GITHUB_OIDC_HOST}"
GITHUB_OIDC_AUDIENCE = "sts.amazonaws.com"
REPO_SUB_PREFIX = "repo:smart-campus-ai/smart-campus-ai:"
REFERENCE = re.compile(r"(?:var|local|module|each|data)\.")


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


def _strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, (list, tuple, set)):
        return [s for item in value for s in _strings(item)]
    return []


def _is_unresolved(value: str) -> bool:
    return "${" in value or REFERENCE.match(value) is not None


def _claim_key_ok(variable: str, claim: str) -> bool:
    """The key is the GitHub provider claim; the host may be an unresolved interpolation."""
    if variable == f"{GITHUB_OIDC_HOST}:{claim}":
        return True
    return _is_unresolved(variable) and variable.endswith(f":{claim}")


def _sub_value_ok(value: str) -> bool:
    if "*" in value or "?" in value:
        return False
    if REFERENCE.match(value):
        return True  # unresolved: accepted because the operator is StringEquals (documented limit)
    if "${" in value:
        head = value.split("${", 1)[0]
        return head.startswith(REPO_SUB_PREFIX) or REPO_SUB_PREFIX.startswith(head)
    return value.startswith(REPO_SUB_PREFIX)


def _aud_value_ok(value: str) -> bool:
    return value == GITHUB_OIDC_AUDIENCE or _is_unresolved(value)


def _pins_github_claims(entries: list[tuple[str, str, list[str]]]) -> bool:
    """Return True if (operator, key, values) entries pin ':aud' and ':sub' to this repository with StringEquals."""
    subs: list[list[str]] = []
    auds: list[list[str]] = []
    for operator, variable, values in entries:
        for claim, bucket, value_ok in (("sub", subs, _sub_value_ok), ("aud", auds, _aud_value_ok)):
            if not variable.endswith(f":{claim}"):
                continue
            if operator != "StringEquals" or not _claim_key_ok(variable, claim):
                return False
            if not values or not all(value_ok(v) for v in values):
                return False
            bucket.append(values)
    return bool(subs) and bool(auds)


def _github_oidc_only(statement: Any) -> bool:
    """Return True if the statement is a GitHub OIDC sts:AssumeRoleWithWebIdentity pinned on this repository.

    Requires the GitHub provider as Federated principal, StringEquals on ':aud' = sts.amazonaws.com and on ':sub'
    values that start with "repo:<org>/<repo>:" without wildcard.
    """
    if not isinstance(statement, dict):
        return False
    if statement.get("Effect", "Allow") != "Allow":
        return True
    if "NotPrincipal" in statement:
        return False
    principal = statement.get("Principal")
    if not isinstance(principal, dict) or set(principal) != {"Federated"}:
        return False
    providers = _strings(principal["Federated"])
    if not providers or not all(p.endswith(GITHUB_OIDC_PROVIDER_SUFFIX) for p in providers):
        return False
    if set(force_list(statement.get("Action", []))) != {"sts:AssumeRoleWithWebIdentity"}:
        return False
    condition = statement.get("Condition")
    if not isinstance(condition, dict):
        return False
    entries: list[tuple[str, str, list[str]]] = []
    for operator, mapping in condition.items():
        if not isinstance(mapping, dict):
            return False
        entries.extend((str(operator), str(key), _strings(values)) for key, values in mapping.items())
    return _pins_github_claims(entries)


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
