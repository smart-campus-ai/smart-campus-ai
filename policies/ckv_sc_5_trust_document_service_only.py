"""CKV_SC_5: an aws_iam_policy_document that grants sts:AssumeRole* allows only Service principals.

Companion of CKV_SC_1: the repository builds trust policies with aws_iam_policy_document, which the resource-level
check cannot see through the `.json` reference. A Federated principal is accepted only for
sts:AssumeRoleWithWebIdentity with StringEquals conditions on both a ':sub' and an ':aud' variable (GitHub OIDC).
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.common.util.type_forcers import force_list
from checkov.terraform.checks.data.base_check import BaseDataCheck

EXCLUDED_PATH = "/infra/modules/github-oidc/"


def _strings(value: Any) -> Iterator[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, (list, tuple, set)):
        for item in value:
            yield from _strings(item)


def _first_strings(block: Any, key: str) -> list[str]:
    return list(_strings(block.get(key, []))) if isinstance(block, dict) else []


def _is_trust_statement(statement: dict[str, Any]) -> bool:
    return any(a.lower().startswith("sts:assume") or a.lower() == "sts:*" for a in _strings(statement.get("actions", [])))


def _is_allow(statement: dict[str, Any]) -> bool:
    return all(effect in ("Allow", None) for effect in _strings(statement.get("effect", [])) or ["Allow"])


def _is_federated_principal(principal: dict[str, Any]) -> bool:
    return isinstance(principal, dict) and _first_strings(principal, "type") == ["Federated"]


def _is_web_identity_statement(statement: dict[str, Any]) -> bool:
    """Return True if the only action of the statement is sts:AssumeRoleWithWebIdentity."""
    actions = {a.lower() for a in _strings(statement.get("actions", []))}
    return actions == {"sts:assumerolewithwebidentity"}


def _pins_sub_and_aud(statement: dict[str, Any]) -> bool:
    """Return True if StringEquals conditions pin both the ':sub' and the ':aud' claims.

    Only the end of the variable is matched: Checkov does not resolve locals, so the issuer part may be an
    unresolved interpolation such as "${local.oidc_host}:sub".
    """
    variables: set[str] = set()
    for block in force_list(statement.get("condition", [])):
        for condition in force_list(block):
            if not isinstance(condition, dict) or _first_strings(condition, "test") != ["StringEquals"]:
                continue
            variables.update(_first_strings(condition, "variable"))
    return any(v.endswith(":sub") for v in variables) and any(v.endswith(":aud") for v in variables)


def _is_service_principal(principal: dict[str, Any]) -> bool:
    """Return True if the principal is a Service principal."""
    if not isinstance(principal, dict):
        return False
    return _first_strings(principal, "type") == ["Service"]


class TrustDocumentServiceOnly(BaseDataCheck):
    def __init__(self) -> None:
        super().__init__(
            name="Ensure IAM trust policy documents allow only Service principals",
            id="CKV_SC_5",
            categories=(CheckCategories.IAM,),
            supported_data=("aws_iam_policy_document",),
        )

    def scan_data_conf(self, conf: dict[str, list[Any]]) -> CheckResult:
        if EXCLUDED_PATH in self.entity_path.replace("\\", "/"):
            return CheckResult.UNKNOWN

        found_trust_statement = False
        for statements in conf.get("statement", []):
            for statement in force_list(statements):
                if not isinstance(statement, dict) or not _is_trust_statement(statement) or not _is_allow(statement):
                    continue
                found_trust_statement = True
                if statement.get("not_principals"):
                    return CheckResult.FAILED
                principals = [p for block in force_list(statement.get("principals", [])) for p in force_list(block)]
                if not principals:
                    return CheckResult.FAILED
                oidc_trust = _is_web_identity_statement(statement) and _pins_sub_and_aud(statement)
                for principal in principals:
                    if not (_is_service_principal(principal) or (oidc_trust and _is_federated_principal(principal))):
                        return CheckResult.FAILED

        return CheckResult.PASSED if found_trust_statement else CheckResult.UNKNOWN


check = TrustDocumentServiceOnly()
