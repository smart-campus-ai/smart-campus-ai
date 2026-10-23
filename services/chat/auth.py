"""Authorization helpers for the native Cognito authorizer (EN-32, ADR-0005).

The REST API uses the native Cognito User Pool authorizer; claims arrive in
``event.requestContext.authorizer.claims``. A caller's identity is always the JWT
``sub`` (never taken from the request body or query, OWASP API1/BOLA). Chat
sessions are keyed by this ``sub`` so a student can never read or continue another
student's session (US02-AC6).
"""

from __future__ import annotations

from dataclasses import dataclass

from errors import unauthorized

ADMIN_GROUP = "admin"
STUDENT_GROUP = "student"


@dataclass(frozen=True)
class Caller:
    """The authenticated principal, derived exclusively from the JWT claims."""

    sub: str
    groups: tuple[str, ...]

    @property
    def is_admin(self) -> bool:
        return ADMIN_GROUP in self.groups

    @property
    def is_student(self) -> bool:
        return STUDENT_GROUP in self.groups


def _parse_groups(raw: object) -> tuple[str, ...]:
    """Normalise ``cognito:groups`` which may be a list or a bracketed string.

    API Gateway flattens the claim to a string such as ``"[admin student]"`` in the
    REST proxy payload; a JWT decoded as JSON yields a real list. Both are accepted.
    """

    if raw is None:
        return ()
    if isinstance(raw, (list, tuple)):
        return tuple(str(g) for g in raw if str(g))
    text = str(raw).strip()
    if not text:
        return ()
    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1]
    parts = [p for chunk in text.split(",") for p in chunk.split()]
    return tuple(p for p in parts if p)


def caller_from_event(event: dict) -> Caller:
    """Build the :class:`Caller` from a REST proxy event, or raise 401.

    The ``sub`` claim is mandatory: without it there is no verified identity.
    """

    request_context = event.get("requestContext") or {}
    authorizer = request_context.get("authorizer") or {}
    claims = authorizer.get("claims") or {}

    sub = claims.get("sub")
    if not sub or not isinstance(sub, str):
        raise unauthorized()

    groups = _parse_groups(claims.get("cognito:groups"))
    return Caller(sub=sub, groups=groups)
