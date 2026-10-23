"""US06 — SSO Microsoft : trigger pre-token (offline). Named after the ACs.

The handler-level criteria are AC2 (approved-domain filtering) and AC3 (default
group mapping / profile reuse). AC1 (Entra sign-in → Cognito tokens), AC4 (native
authorizer accepts federated tokens) and AC5 (no OIDC IdP created when
`enable_entra_federation` is false) are infrastructure: the OIDC provider, the
authorizer and the feature flag live in OpenTofu and are covered by a `tofu test`
of the flag (tracked as infra / needs-decision).
"""

from __future__ import annotations

import domain
import pytest
from errors import DomainNotAllowedError

APPROVED = ("school.edu", "campus.fr")


def _event(email, groups=None):
    return {
        "request": {
            "userAttributes": {"email": email},
            "groupConfiguration": {"groupsToOverride": list(groups or [])},
        },
        "response": {},
    }


def _handler_with_domains(monkeypatch, value="school.edu campus.fr"):
    import app

    monkeypatch.setenv("APPROVED_EMAIL_DOMAINS", value)
    return app


# -- AC2: approved-domain filtering --------------------------------------------

def test_US06_AC2_outside_domain_refuses_token(monkeypatch):
    app = _handler_with_domains(monkeypatch)
    with pytest.raises(DomainNotAllowedError):
        app.handler(_event("intruder@gmail.com"), None)


def test_US06_AC2_approved_domain_is_allowed(monkeypatch):
    app = _handler_with_domains(monkeypatch)
    out = app.handler(_event("alice@school.edu"), None)
    groups = out["response"]["claimsOverrideDetails"]["groupOverrideDetails"]["groupsToOverride"]
    assert "student" in groups


def test_US06_AC2_no_approved_domain_configured_fails_closed(monkeypatch):
    import app

    monkeypatch.delenv("APPROVED_EMAIL_DOMAINS", raising=False)
    with pytest.raises(DomainNotAllowedError):
        app.handler(_event("alice@school.edu"), None)


def test_US06_AC2_malformed_email_refused(monkeypatch):
    app = _handler_with_domains(monkeypatch)
    for bad in ("", "no-at-sign", "a@@b", "@school.edu", "alice@"):
        with pytest.raises(DomainNotAllowedError):
            app.handler(_event(bad), None)


# -- AC3: default group mapping / profile reuse --------------------------------

def test_US06_AC3_first_login_maps_to_student(monkeypatch):
    app = _handler_with_domains(monkeypatch)
    out = app.handler(_event("bob@campus.fr", groups=[]), None)
    groups = out["response"]["claimsOverrideDetails"]["groupOverrideDetails"]["groupsToOverride"]
    assert groups == ["student"]


def test_US06_AC3_returning_user_keeps_existing_groups_plus_student(monkeypatch):
    app = _handler_with_domains(monkeypatch)
    out = app.handler(_event("carol@school.edu", groups=["admin"]), None)
    groups = out["response"]["claimsOverrideDetails"]["groupOverrideDetails"]["groupsToOverride"]
    assert "admin" in groups and "student" in groups
    # student is not duplicated when already present.
    out2 = app.handler(_event("carol@school.edu", groups=["student"]), None)
    g2 = out2["response"]["claimsOverrideDetails"]["groupOverrideDetails"]["groupsToOverride"]
    assert g2.count("student") == 1


# -- pure domain ----------------------------------------------------------------

def test_US06_domain_email_in_domain():
    assert domain.email_in_domain("a@school.edu", APPROVED) is True
    assert domain.email_in_domain("a@School.EDU", APPROVED) is True  # case-insensitive
    assert domain.email_in_domain("a@other.com", APPROVED) is False
    assert domain.email_in_domain("bad", APPROVED) is False
    assert domain.email_in_domain("a@school.edu", ()) is False  # fail closed


def test_US06_normalise_domains_accepts_list_and_string():
    assert domain.normalise_domains("school.edu, campus.fr") == ("school.edu", "campus.fr")
    assert domain.normalise_domains(["@School.edu"]) == ("school.edu",)
    assert domain.normalise_domains(None) == ()


def test_US06_email_not_in_exception_message(monkeypatch):
    app = _handler_with_domains(monkeypatch)
    try:
        app.handler(_event("secret.person@gmail.com"), None)
    except DomainNotAllowedError as exc:
        assert "secret.person" not in str(exc)
        assert "gmail.com" not in str(exc)
    else:
        pytest.fail("expected refusal")
