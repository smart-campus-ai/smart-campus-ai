"""Lambda entrypoint for the ``pre-token`` function (handler = ``app.handler``).

Cognito pre-token-generation trigger, invoked when a user authenticates (including
through the Entra ID OIDC provider). It enforces the approved email domain
(US06-AC2) and maps the user to the ``student`` group by default (US06-AC3).

Event shape (Cognito pre-token-generation v1/v2):
  event["request"]["userAttributes"]["email"]
  event["request"]["groupConfiguration"]["groupsToOverride"]  # existing groups
Response:
  event["response"]["claimsOverrideDetails"]["groupOverrideDetails"]["groupsToOverride"]

The approved domains come from the APPROVED_EMAIL_DOMAINS environment variable
(configuration). The email is never logged (US06 NFR).
"""

from __future__ import annotations

import logging
import os

import domain
from errors import DomainNotAllowedError

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _approved_domains() -> tuple[str, ...]:
    return domain.normalise_domains(os.environ.get("APPROVED_EMAIL_DOMAINS"))


def handler(event: dict, context: object) -> dict:
    event = event or {}
    request = event.get("request") or {}
    attributes = request.get("userAttributes") or {}
    email = attributes.get("email", "")

    approved = _approved_domains()
    if not domain.email_in_domain(email, approved):
        # Refuse token issuance. The message carries no email (US06 NFR).
        logger.warning("pre-token refused: email domain not approved")
        raise DomainNotAllowedError("Email domain is not approved for this application.")

    existing = request.get("groupConfiguration") or {}
    current = tuple(existing.get("groupsToOverride") or ())
    groups = domain.mapped_groups(current)

    response = event.setdefault("response", {})
    override = response.setdefault("claimsOverrideDetails", {})
    override.setdefault("groupOverrideDetails", {})["groupsToOverride"] = groups

    logger.info("pre-token issued", extra={"groupCount": len(groups)})
    return event
