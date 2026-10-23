"""CKV_SC_5: an aws_iam_policy_document that grants sts:AssumeRole* allows only Service principals.

Companion of CKV_SC_1: the repository builds trust policies with aws_iam_policy_document, which the resource-level
check cannot see through the `.json` reference. A Federated principal is accepted only for the GitHub OIDC provider
(identifier ending with oidc-provider/token.actions.githubusercontent.com) and sts:AssumeRoleWithWebIdentity, with
StringEquals on ':aud' = sts.amazonaws.com and on ':sub' values starting with "repo:smart-campus-ai/smart-campus-ai:"
(no wildcard). Unresolved interpolations in a value are accepted when the test is StringEquals.
"""

from __future__ import annotations

import re
from collections.abc import Iterator
from typing import Any

from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.common.util.type_forcers import force_list
from checkov.terraform.checks.data.base_check import BaseDataCheck

EXCLUDED_PATH = "/infra/modules/github-oidc/"

GITHUB_OIDC_HOST = "token.actions.githubusercontent.com"
GITHUB_OIDC_PROVIDER_SUFFIX = f"oidc-provider/{GITHUB_OIDC_HOST}"
GITHUB_OIDC_AUDIENCE = "sts.amazonaws.com"
REPO_SUB_PREFIX = "repo:smart-campus-ai/smart-campus-ai:"
REFERENCE = re.compile(r"(?:var|local|module|each|data)\.")


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


def _is_github_federated_principal(principal: dict[str, Any]) -> bool:
    """Return True if the principal is Federated and every identifier is the GitHub OIDC provider."""
    if not isinstance(principal, dict) or _first_strings(principal, "type") != ["Federated"]:
        return False
    identifiers = _first_strings(principal, "identifiers")
    return bool(identifiers) and all(i.endswith(GITHUB_OIDC_PROVIDER_SUFFIX) or _is_unresolved(i) or "aws_iam_openid_connect_provider." in i for i in identifiers)


def _is_web_identity_statement(statement: dict[str, Any]) -> bool:
    """Return True if the only action of the statement is sts:AssumeRoleWithWebIdentity."""
    actions = {a.lower() for a in _strings(statement.get("actions", []))}
    return actions == {"sts:assumerolewithwebidentity"}


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
        return True  # unresolved: accepted because the test is StringEquals (documented limit)
    if "${" in value:
        head = value.split("${", 1)[0]
        return head.startswith(REPO_SUB_PREFIX) or REPO_SUB_PREFIX.startswith(head)
    return value.startswith(REPO_SUB_PREFIX)


def _aud_value_ok(value: str) -> bool:
    return value == GITHUB_OIDC_AUDIENCE or _is_unresolved(value)


def _pins_github_claims(statement: dict[str, Any]) -> bool:
    """Return True if StringEquals conditions pin ':aud' and ':sub' to this repository.

    The ':aud' value must be sts.amazonaws.com and every ':sub' value must start with "repo:<org>/<repo>:" without
    wildcard. Checkov does not resolve locals or variables: a value that is an unresolved interpolation is accepted
    when the test is StringEquals, and so is the issuer part of the key ("${local.oidc_host}:sub").
    """
    found = {"sub": False, "aud": False}
    checks = {"sub": _sub_value_ok, "aud": _aud_value_ok}
    for block in force_list(statement.get("condition", [])):
        for condition in force_list(block):
            if not isinstance(condition, dict):
                return False
            for variable in _first_strings(condition, "variable"):
                for claim, value_ok in checks.items():
                    if not variable.endswith(f":{claim}"):
                        continue
                    values = _first_strings(condition, "values")
                    if _first_strings(condition, "test") != ["StringEquals"] or not _claim_key_ok(variable, claim):
                        return False
                    if not values or not all(value_ok(v) for v in values):
                        return False
                    found[claim] = True
    return all(found.values())


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
                oidc_trust = _is_web_identity_statement(statement) and _pins_github_claims(statement)
                for principal in principals:
                    if not (_is_service_principal(principal) or (oidc_trust and _is_github_federated_principal(principal))):
                        return CheckResult.FAILED

        return CheckResult.PASSED if found_trust_statement else CheckResult.UNKNOWN


check = TrustDocumentServiceOnly()
