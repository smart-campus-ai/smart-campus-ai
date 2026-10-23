"""pre-token domain: approved-email-domain filtering and group mapping (US06).

Pure logic, no AWS. Used by the Cognito pre-token-generation trigger when a user
authenticates through the Entra ID OIDC identity provider. Two rules:

- **Approved domain (US06-AC2)**: the user's email must belong to one of the
  approved domains, otherwise the trigger refuses to issue a token (the handler
  raises, which makes Cognito fail the sign-in).
- **Default group (US06-AC3)**: a federated user is mapped to the ``student``
  group by default. A returning user keeps their existing groups plus ``student``.

The email is only compared here; it is never returned in a claim or logged
(US06 NFR).
"""

from __future__ import annotations

DEFAULT_GROUP = "student"


def normalise_domains(raw: str | list[str] | None) -> tuple[str, ...]:
    """Parse the approved-domains configuration (comma/space list or real list)."""
    if raw is None:
        return ()
    if isinstance(raw, (list, tuple)):
        values = [str(v) for v in raw]
    else:
        values = [p for chunk in str(raw).split(",") for p in chunk.split()]
    return tuple(d.strip().lower().lstrip("@") for d in values if d.strip())


def email_domain(email: str) -> str | None:
    """Return the lower-cased domain part of an email, or None if malformed."""
    if not isinstance(email, str) or email.count("@") != 1:
        return None
    local, _, domain = email.partition("@")
    if not local or not domain:
        return None
    return domain.strip().lower()


def email_in_domain(email: str, approved_domains: tuple[str, ...]) -> bool:
    """True when the email's domain is one of the approved domains (US06-AC2).

    With no approved domain configured, nothing is approved (fail closed).
    """
    domain = email_domain(email)
    if domain is None or not approved_domains:
        return False
    return domain in approved_domains


def mapped_groups(existing: tuple[str, ...]) -> list[str]:
    """Groups to assign a federated user: their existing groups plus the default
    ``student`` group, deduplicated and order-stable (US06-AC3)."""
    out: list[str] = []
    for g in (*existing, DEFAULT_GROUP):
        if g and g not in out:
            out.append(g)
    return out
