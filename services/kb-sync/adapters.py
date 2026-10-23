"""Runtime adapters for kb-sync: Bedrock Agent ingestion. Imported only inside the
Lambda. IAM role limited to the ingestion APIs on one KB + data source.
"""

from __future__ import annotations

import json
import os

from ports import IngestionJob


class BedrockIngestion:
    def __init__(self, client, knowledge_base_id: str, data_source_id: str) -> None:
        self._client = client
        self._kb = knowledge_base_id
        self._ds = data_source_id

    def latest_status(self) -> str | None:
        resp = self._client.list_ingestion_jobs(
            knowledgeBaseId=self._kb,
            dataSourceId=self._ds,
            sortBy={"attribute": "STARTED_AT", "order": "DESCENDING"},
            maxResults=1,
        )
        jobs = resp.get("ingestionJobSummaries", [])
        return jobs[0]["status"] if jobs else None

    def start(self) -> IngestionJob:
        resp = self._client.start_ingestion_job(
            knowledgeBaseId=self._kb,
            dataSourceId=self._ds,
        )
        job = resp.get("ingestionJob", {})
        stats = job.get("statistics", {}) or {}
        return IngestionJob(
            job_id=job.get("ingestionJobId", ""),
            status=job.get("status", "STARTING"),
            indexed=int(stats.get("numberOfDocumentsScanned", 0)),
            failed=int(stats.get("numberOfDocumentsFailed", 0)),
        )


class CloudWatchMetrics:
    def __init__(self, namespace: str = "SmartCampus/KbSync") -> None:
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
    client = boto3.client("bedrock-agent", region_name=region)
    ingestion = BedrockIngestion(
        client,
        knowledge_base_id=os.environ["KNOWLEDGE_BASE_ID"],
        data_source_id=os.environ["DATA_SOURCE_ID"],
    )
    return ingestion, CloudWatchMetrics()
