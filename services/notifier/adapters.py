"""Runtime adapters for the notifier: Cognito directory, SES mailer, stream
deserialisation. Imported only inside the Lambda (never by unit tests). No secret
is read; all access is over TLS with the function's IAM role. Addresses and bodies
are never logged (US09 NFR).
"""

from __future__ import annotations

import json
import os


def deserialise_image(image: dict | None) -> dict:
    """Convert a DynamoDB stream image (attribute-value map) into a plain dict.

    Handles the subset of types used by the tickets table (S, N, BOOL, NULL, and
    shallow M/L). boto3's TypeDeserializer is used when available.
    """
    if not image:
        return {}
    try:
        from boto3.dynamodb.types import TypeDeserializer

        d = TypeDeserializer()
        return {k: d.deserialize(v) for k, v in image.items()}
    except Exception:  # pragma: no cover - fallback for minimal runtimes
        out: dict = {}
        for k, v in image.items():
            if "S" in v:
                out[k] = v["S"]
            elif "N" in v:
                out[k] = v["N"]
            elif "BOOL" in v:
                out[k] = v["BOOL"]
            elif "NULL" in v:
                out[k] = None
        return out


class CognitoEmailDirectory:
    """Resolves a sub to a verified email via the Cognito user pool."""

    def __init__(self, client, user_pool_id: str) -> None:
        self._client = client
        self._pool = user_pool_id

    def email_for(self, sub: str) -> str | None:
        # Query by sub; the pool is configured so sub maps to the username or a filter.
        resp = self._client.list_users(
            UserPoolId=self._pool,
            Filter=f'sub = "{sub}"',
            Limit=1,
        )
        for user in resp.get("Users", []):
            verified = None
            email = None
            for attr in user.get("Attributes", []):
                if attr["Name"] == "email":
                    email = attr["Value"]
                elif attr["Name"] == "email_verified":
                    verified = attr["Value"] == "true"
            if email and verified:
                return email
        return None


class SesMailer:
    """Sends email via SES v2. Raises on failure (retried, then DLQ)."""

    def __init__(self, client, sender: str) -> None:
        self._client = client
        self._sender = sender

    def send(self, to_address: str, subject: str, body: str) -> None:
        self._client.send_email(
            FromEmailAddress=self._sender,
            Destination={"ToAddresses": [to_address]},
            Content={
                "Simple": {
                    "Subject": {"Data": subject, "Charset": "UTF-8"},
                    "Body": {"Text": {"Data": body, "Charset": "UTF-8"}},
                }
            },
        )


class CloudWatchMetrics:
    def __init__(self, namespace: str = "SmartCampus/Notifier") -> None:
        self._namespace = namespace

    def incr(self, name: str, value: int = 1) -> None:
        print(  # noqa: T201 — EMF via stdout by design
            json.dumps(
                {
                    "_aws": {
                        "CloudWatchMetrics": [
                            {"Namespace": self._namespace, "Dimensions": [[]], "Metrics": [{"Name": name, "Unit": "Count"}]}
                        ]
                    },
                    name: value,
                }
            )
        )


def build_from_env():
    import boto3

    region = os.environ["AWS_REGION"]
    cognito = boto3.client("cognito-idp", region_name=region)
    ses = boto3.client("sesv2", region_name=region)

    directory = CognitoEmailDirectory(cognito, os.environ["USER_POOL_ID"])
    mailer = SesMailer(ses, os.environ["SES_SENDER"])
    base_url = os.environ["APP_BASE_URL"]  # CloudFront URL (US09-AC3)
    return directory, mailer, base_url, CloudWatchMetrics()
