"""Runtime adapter for kpi: read-only DynamoDB access to the daily-aggregate table.

Imported only inside the Lambda. The role is read-only on the ``kpi`` table and
has no access to ``tickets``. Reads are keyed by date (Query per day), so the cost
is O(days) — never a Scan, never the tickets table (US05-AC4).
"""

from __future__ import annotations

import datetime as _dt
import os


class DynamoKpiStore:
    def __init__(self, table) -> None:
        self._table = table

    def read_range(self, from_date: _dt.date, to_date: _dt.date) -> list[dict]:
        rows: list[dict] = []
        day = from_date
        while day <= to_date:
            key = day.strftime("%Y-%m-%d")
            # One Query per day partition: all (status, category) slices of that day.
            resp = self._table.query(
                KeyConditionExpression="#d = :d",
                ExpressionAttributeNames={"#d": "date"},
                ExpressionAttributeValues={":d": key},
            )
            rows.extend(resp.get("Items", []))
            cursor = resp.get("LastEvaluatedKey")
            while cursor:
                resp = self._table.query(
                    KeyConditionExpression="#d = :d",
                    ExpressionAttributeNames={"#d": "date"},
                    ExpressionAttributeValues={":d": key},
                    ExclusiveStartKey=cursor,
                )
                rows.extend(resp.get("Items", []))
                cursor = resp.get("LastEvaluatedKey")
            day += _dt.timedelta(days=1)
        return rows


def build_from_env():
    import boto3

    region = os.environ["AWS_REGION"]
    table = boto3.resource("dynamodb", region_name=region).Table(os.environ["KPI_TABLE"])
    return DynamoKpiStore(table)
