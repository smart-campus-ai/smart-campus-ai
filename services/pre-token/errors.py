"""Errors for the pre-token trigger. Raising from the handler makes Cognito fail
the sign-in and refuse to issue a token (US06-AC2). The exception message never
contains the email (US06 NFR)."""

from __future__ import annotations


class DomainNotAllowedError(Exception):
    """Raised when the authenticating user's email is outside the approved
    domain. Cognito surfaces this as a failed sign-in; no token is issued."""
