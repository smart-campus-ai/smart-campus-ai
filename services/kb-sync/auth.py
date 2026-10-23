"""Authorization for the admin resync endpoint (native Cognito authorizer, EN-32).

Manual resync is admin-only (US07-AC3): the handler checks the ``admin`` group in
``cognito:groups`` and returns 403 otherwise. Identity comes from the JWT claims.
"""

from __future__ import annotations

from dataclasses import dataclass

from errors import forbidden, unauthorized

ADMIN_GROUP = "admin"


@dataclass(frozen=True)
class Caller:
    sub: str
    groups: tuple[str, ...]

    @property
    def is_admin(self) -> bool:
        return ADMIN_GROUP in self.groups


def _parse_groups(raw: object) -> tuple[str, ...]:
    if raw is None:
        return ()
    if isinstance(raw, (list, tuple)):
        return tuple(str(g) for g in raw if str(g))
    text = str(raw).strip()
    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1]
    parts = [p for chunk in text.split(",") for p in chunk.split()]
    return tuple(p for p in parts if p)


def caller_from_event(event: dict) -> Caller:
    claims = ((event.get("requestContext") or {}).get("authorizer") or {}).get("claims") or {}
    sub = claims.get("sub")
    if not sub or not isinstance(sub, str):
        raise unauthorized()
    return Caller(sub=sub, groups=_parse_groups(claims.get("cognito:groups")))


def require_admin(caller: Caller) -> None:
    if not caller.is_admin:
        raise forbidden()
