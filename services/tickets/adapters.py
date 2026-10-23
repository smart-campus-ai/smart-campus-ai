"""AWS-backed adapters (boto3). Imported only at runtime, inside the Lambda.

Configuration comes exclusively from environment variables set by the infra
(infra/app contract, section 2). No resource name, ARN, account or region is
hard-coded. Never performs a Scan.
"""

from __future__ import annotations

import json
import os

import boto3
from boto3.dynamodb.conditions import Key

import mapping


class DynamoTicketStore:
    def __init__(self, table_name: str, owner_index: str, status_index: str) -> None:
        self._table = boto3.resource("dynamodb").Table(table_name)
        self._owner_index = owner_index
        self._status_index = status_index

    def put_ticket(self, meta_item: dict, event_item: dict) -> None:
        client = self._table.meta.client
        client.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": self._table.name,
                        "Item": _to_dynamo(meta_item),
                        "ConditionExpression": "attribute_not_exists(pk)",
                    }
                },
                {"Put": {"TableName": self._table.name, "Item": _to_dynamo(event_item)}},
            ]
        )

    def get_meta(self, ticket_id: str) -> dict | None:
        resp = self._table.get_item(Key={"pk": mapping.ticket_pk(ticket_id), "sk": mapping.SK_META})
        return resp.get("Item")

    def get_detail(self, ticket_id: str) -> tuple[dict | None, list[dict]]:
        resp = self._table.query(
            KeyConditionExpression=Key("pk").eq(mapping.ticket_pk(ticket_id))
        )
        items = resp.get("Items", [])
        meta = next((i for i in items if i.get("sk") == mapping.SK_META), None)
        children = [i for i in items if i.get("sk") != mapping.SK_META]
        return meta, children

    def _query_index(self, index, key_cond, ascending, limit, cursor):
        kwargs = {
            "IndexName": index,
            "KeyConditionExpression": key_cond,
            "ScanIndexForward": ascending,
            "Limit": limit,
        }
        if cursor:
            kwargs["ExclusiveStartKey"] = json.loads(cursor)
        resp = self._table.query(**kwargs)
        last = resp.get("LastEvaluatedKey")
        next_cursor = json.dumps(last) if last else None
        return resp.get("Items", []), next_cursor

    def query_by_owner(self, owner_sub, *, status, ascending, limit, cursor):
        cond = Key("ownerSub").eq(owner_sub)
        items, next_cursor = self._query_index(self._owner_index, cond, ascending, limit, cursor)
        if status is not None:
            items = [i for i in items if i.get("status") == status]
        return items, next_cursor

    def query_by_status(self, status, *, ascending, limit, cursor):
        if status is None:
            # Admin "all" list without a status filter cannot use the status GSI key;
            # the handler passes a concrete status, or falls back to per-status queries.
            raise ValueError("query_by_status requires a status")
        cond = Key("status").eq(status)
        return self._query_index(self._status_index, cond, ascending, limit, cursor)

    def apply_update(self, ticket_id, updated_meta, event_items):
        transact = [
            {
                "Put": {
                    "TableName": self._table.name,
                    "Item": _to_dynamo(updated_meta),
                    "ConditionExpression": "attribute_exists(pk)",
                }
            }
        ]
        for ev in event_items:
            transact.append({"Put": {"TableName": self._table.name, "Item": _to_dynamo(ev)}})
        self._table.meta.client.transact_write_items(TransactItems=transact)


class SnsAdminAlerts:
    def __init__(self, topic_arn: str) -> None:
        self._topic_arn = topic_arn
        self._client = boto3.client("sns")

    def publish(self, subject: str, message: str) -> None:
        self._client.publish(TopicArn=self._topic_arn, Subject=subject, Message=message)


class EventBridgeSlaScheduler:
    def __init__(self, group_name: str, role_arn: str, target_arn: str, dlq_arn: str) -> None:
        self._group = group_name
        self._role_arn = role_arn
        self._target_arn = target_arn
        self._dlq_arn = dlq_arn
        self._client = boto3.client("scheduler")

    def schedule_escalation(self, ticket_id: str, fire_at_iso_utc: str) -> None:
        # ADR-0008: one-time schedule, deletes itself after completion, no PII in Input.
        expression = f"at({fire_at_iso_utc.rstrip('Z')})"
        self._client.create_schedule(
            Name=f"sla-{ticket_id}",
            GroupName=self._group,
            ScheduleExpression=expression,
            FlexibleTimeWindow={"Mode": "OFF"},
            ActionAfterCompletion="DELETE",
            Target={
                "Arn": self._target_arn,
                "RoleArn": self._role_arn,
                "Input": json.dumps({"ticketId": ticket_id}),
                "DeadLetterConfig": {"Arn": self._dlq_arn},
            },
        )


def _to_dynamo(item: dict) -> dict:
    """Drop None values; DynamoDB stores absence rather than null for optional attrs."""

    return {k: v for k, v in item.items() if v is not None}


def build_from_env() -> tuple:
    store = DynamoTicketStore(
        os.environ["TICKETS_TABLE"],
        os.environ["TICKETS_OWNER_INDEX"],
        os.environ["TICKETS_STATUS_INDEX"],
    )
    alerts = SnsAdminAlerts(os.environ["ADMINS_TOPIC_ARN"])
    scheduler = EventBridgeSlaScheduler(
        os.environ["SLA_SCHEDULE_GROUP"],
        os.environ["SLA_SCHEDULER_ROLE_ARN"],
        os.environ["SLA_TARGET_ARN"],
        os.environ["SLA_DLQ_ARN"],
    )
    return store, alerts, scheduler
