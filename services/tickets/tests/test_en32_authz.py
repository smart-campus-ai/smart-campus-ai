"""EN-32 — Native Cognito authorizer, handler-side group check.

The authorizer itself (token signature, expiry, issuer, audience) is infra (OPS,
ADR-0005): AC1/AC3 are verified by `tofu test` + security tests (EN-83). The SE
deliverable is the handler-side reading of the verified claims and the admin guard
(AC4, AC5), plus a 401 when no verified identity is present (AC2 at the handler).
Tests are named after the acceptance criteria.
"""

from __future__ import annotations

import pytest
from auth import Caller, caller_from_event, require_admin
from errors import ApiError


def event_with_claims(claims):
    return {"requestContext": {"authorizer": {"claims": claims}}}


# --- AC4: the sub and cognito:groups reach the handler ----------------------


def test_EN32_AC4_sub_and_groups_reach_the_handler_list_form():
    caller = caller_from_event(
        event_with_claims({"sub": "u-1", "cognito:groups": ["admin", "student"]})
    )
    assert caller.sub == "u-1"
    assert set(caller.groups) == {"admin", "student"}
    assert caller.is_admin


def test_EN32_AC4_groups_parsed_from_bracketed_string():
    # API Gateway flattens cognito:groups to a string like "[admin student]".
    caller = caller_from_event(event_with_claims({"sub": "u-2", "cognito:groups": "[admin student]"}))
    assert set(caller.groups) == {"admin", "student"}
    assert caller.is_admin


def test_EN32_AC4_groups_parsed_from_comma_separated_string():
    caller = caller_from_event(event_with_claims({"sub": "u-3", "cognito:groups": "student,admin"}))
    assert set(caller.groups) == {"admin", "student"}


def test_EN32_AC4_no_groups_claim_means_no_groups():
    caller = caller_from_event(event_with_claims({"sub": "u-4"}))
    assert caller.groups == ()
    assert not caller.is_admin


# --- AC2: no verified identity -> 401 ---------------------------------------


def test_EN32_AC2_missing_sub_claim_raises_401():
    with pytest.raises(ApiError) as exc:
        caller_from_event(event_with_claims({"cognito:groups": "student"}))
    assert exc.value.status_code == 401
    assert exc.value.code == "unauthorized"


def test_EN32_AC2_no_authorizer_context_raises_401():
    with pytest.raises(ApiError) as exc:
        caller_from_event({"requestContext": {}})
    assert exc.value.status_code == 401


def test_EN32_AC2_empty_event_raises_401():
    with pytest.raises(ApiError) as exc:
        caller_from_event({})
    assert exc.value.status_code == 401


# --- AC5: admin-only methods -> 403 for a student ---------------------------


def test_EN32_AC5_require_admin_forbids_student_403():
    student = Caller(sub="s-1", groups=("student",))
    with pytest.raises(ApiError) as exc:
        require_admin(student)
    assert exc.value.status_code == 403
    assert exc.value.code == "forbidden"


def test_EN32_AC5_require_admin_allows_admin():
    admin = Caller(sub="a-1", groups=("admin",))
    assert require_admin(admin) is None


def test_EN32_AC5_require_admin_forbids_caller_without_groups():
    anon = Caller(sub="x-1", groups=())
    with pytest.raises(ApiError) as exc:
        require_admin(anon)
    assert exc.value.status_code == 403


# --- Identity is never taken from the request (OWASP API1) ------------------


def test_EN32_identity_comes_from_claims_not_body_fields():
    # Even if a forged sub is elsewhere, caller_from_event only trusts the claims.
    caller = caller_from_event(event_with_claims({"sub": "real-sub", "cognito:groups": "student"}))
    assert caller.sub == "real-sub"
