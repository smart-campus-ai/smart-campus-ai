"""CKV_SC_5: an aws_iam_policy_document that grants sts:AssumeRole* allows only Service principals.

Companion of CKV_SC_1: the repository builds trust policies with aws_iam_policy_document, which the resource-level
check cannot see through the `.json` reference. The github-oidc module (Federated principals) is excluded.
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
                for principal in principals:
                    if _first_strings(principal, "type") != ["Service"]:
                        return CheckResult.FAILED

        return CheckResult.PASSED if found_trust_statement else CheckResult.UNKNOWN


check = TrustDocumentServiceOnly()
