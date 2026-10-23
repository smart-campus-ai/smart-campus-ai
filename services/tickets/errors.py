"""Shared HTTP/domain errors mapped to the contract Error envelope.

Error codes and shape come from packages/contracts/schemas/common.json#/$defs/Error.
Messages are safe to display and never contain ticket content (infra/app contract, section 7).
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class ApiError(Exception):
    """An error that maps to a non-2xx response with the contract Error envelope."""

    status_code: int
    code: str
    message: str
    details: list[dict[str, str]] = field(default_factory=list)

    def to_body(self, request_id: str | None = None) -> dict:
        body: dict = {"code": self.code, "message": self.message}
        if self.details:
            body["details"] = self.details
        if request_id:
            body["requestId"] = request_id
        return body


def validation_error(message: str, details: list[dict[str, str]] | None = None) -> ApiError:
    return ApiError(400, "validation_error", message, details or [])


def unauthorized(message: str = "Missing or invalid access token.") -> ApiError:
    return ApiError(401, "unauthorized", message)


def forbidden(message: str = "You are not allowed to perform this action.") -> ApiError:
    return ApiError(403, "forbidden", message)


def not_found(message: str = "Resource not found.") -> ApiError:
    return ApiError(404, "not_found", message)


def conflict(message: str = "The resource is in a conflicting state.") -> ApiError:
    return ApiError(409, "conflict", message)


def internal_error(message: str = "An unexpected error occurred.") -> ApiError:
    return ApiError(500, "internal_error", message)
