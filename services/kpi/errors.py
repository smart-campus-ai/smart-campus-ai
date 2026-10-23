"""Shared HTTP/domain errors mapped to the contract Error envelope.

Error codes and shape come from packages/contracts/schemas/common.json#/$defs/Error.
Messages are safe to display and never contain personal data.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class ApiError(Exception):
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


def forbidden(message: str = "This operation is restricted to administrators.") -> ApiError:
    return ApiError(403, "forbidden", message)


def internal_error(message: str = "An unexpected error occurred.") -> ApiError:
    return ApiError(500, "internal_error", message)


def not_found_fallback(message: str = "Resource not found.") -> ApiError:
    return ApiError(404, "not_found", message)
