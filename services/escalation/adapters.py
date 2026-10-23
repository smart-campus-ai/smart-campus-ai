"""AWS-backed adapters for the escalation function. Imported only at runtime."""

from __future__ import annotations

import os

import boto3
from botocore.exceptions import ClientError

from service import ESCALATION_MARKER


class DynamoEscalationStore:
    def __init__(self, table_name: str) -> None:
        self._table = boto3.resource("dynamodb").Table(table_name)

    def get_meta(self, ticket_id: str) -> dict | None:
        resp = self._table.get_item(Key={"pk": f"TICKET#{ticket_id}", "sk": "META"})
        return resp.get("Item")

    def escalate(self, ticket_id, new_priority, escalated_at, event_item) -> bool:
        client = self._table.meta.client
        try:
            client.transact_write_items(
                TransactItems=[
                    {
                        "Update": {
                            "TableName": self._table.name,
                            "Key": {"pk": {"S": f"TICKET#{ticket_id}"}, "sk": {"S": "META"}},
                            # Idempotency (RF01-AC4/AC5): still "Ouvert" and not escalated yet.
                            "ConditionExpression": "#s = :open AND attribute_not_exists(#m)",
                            "UpdateExpression": "SET #p = :p, #m = :at, updatedAt = :at",
                            "ExpressionAttributeNames": {
                                "#s": "status",
                                "#p": "priority",
                                "#m": ESCALATION_MARKER,
                            },
                            "ExpressionAttributeValues": {
                                ":open": {"S": "Ouvert"},
                                ":p": {"S": new_priority},
                                ":at": {"S": escalated_at},
                            },
                        }
                    },
                    {"Put": {"TableName": self._table.name, "Item": _to_dynamo(event_item)}},
                ]
            )
            return True
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in ("TransactionCanceledException", "ConditionalCheckFailedException"):
                return False
            raise


class SnsAdminAlerts:
    def __init__(self, topic_arn: str) -> None:
        self._topic_arn = topic_arn
        self._client = boto3.client("sns")

    def publish(self, subject: str, message: str) -> None:
        self._client.publish(TopicArn=self._topic_arn, Subject=subject, Message=message)


def _to_dynamo(item: dict) -> dict:
    return {k: {"S": str(v)} for k, v in item.items() if v is not None}


def build_from_env():
    store = DynamoEscalationStore(os.environ["TICKETS_TABLE"])
    alerts = SnsAdminAlerts(os.environ["ADMINS_TOPIC_ARN"])
    return store, alerts
