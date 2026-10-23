"""Errors for kb-sync. The admin resync path is HTTP (maps to the contract Error
envelope); the S3-event path raises to trigger the DLQ. Codes come from
common.json#/$defs/Error.
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


def unauthorized(message: str = "Missing or invalid access token.") -> ApiError:
    return ApiError(401, "unauthorized", message)


def forbidden(message: str = "This operation is restricted to administrators.") -> ApiError:
    return ApiError(403, "forbidden", message)


def internal_error(message: str = "An unexpected error occurred.") -> ApiError:
    return ApiError(500, "internal_error", message)


class IngestionError(Exception):
    """A recoverable failure starting/reading an ingestion job. On the S3-event
    path it propagates so the record goes to the DLQ (US07-AC5)."""
