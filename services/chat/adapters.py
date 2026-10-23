"""Runtime adapters: DynamoDB ``chat-sessions`` and Bedrock (KB + guarded model).

Imported only inside the Lambda (never by unit tests). Each adapter implements a
port from ``ports.py``. All AWS access is over TLS with the function's IAM role;
no secret is read here. Inference uses an EU cross-region inference profile and the
Guardrail attached to the model invocation (RF03); the model id, KB id, Guardrail
id/version and table name are configuration (environment variables).
"""

from __future__ import annotations

import json
import os

from ports import Generation, Passage


class DynamoSessionStore:
    """`chat-sessions` table access. Reads are always scoped to ``owner_sub``."""

    def __init__(self, table) -> None:
        self._table = table

    def get_session(self, owner_sub: str, session_id: str):
        resp = self._table.get_item(Key={"pk": f"SESSION#{session_id}"})
        item = resp.get("Item")
        if item is None or item.get("ownerSub") != owner_sub:
            return None
        return item

    def list_sessions(self, owner_sub: str, *, limit: int, cursor):
        kwargs = {
            "IndexName": "by-owner",
            "KeyConditionExpression": "ownerSub = :o",
            "ExpressionAttributeValues": {":o": owner_sub},
            "ScanIndexForward": False,
            "Limit": limit,
        }
        if cursor:
            kwargs["ExclusiveStartKey"] = json.loads(cursor)
        resp = self._table.query(**kwargs)
        last = resp.get("LastEvaluatedKey")
        next_cursor = json.dumps(last) if last else None
        return resp.get("Items", []), next_cursor

    def save_session(self, session: dict) -> None:
        item = dict(session)
        item["pk"] = f"SESSION#{session['id']}"
        self._table.put_item(Item=item)

    def delete_owner_sessions(self, owner_sub: str) -> int:
        removed = 0
        cursor = None
        while True:
            items, cursor = self.list_sessions(owner_sub, limit=100, cursor=cursor)
            for it in items:
                self._table.delete_item(Key={"pk": it["pk"]})
                removed += 1
            if not cursor:
                return removed


class BedrockKnowledgeBase:
    """Retrieves grounding passages from a Bedrock Knowledge Base (S3 Vectors)."""

    def __init__(self, agent_runtime, knowledge_base_id: str) -> None:
        self._client = agent_runtime
        self._kb_id = knowledge_base_id

    def retrieve(self, query: str, *, max_results: int):
        resp = self._client.retrieve(
            knowledgeBaseId=self._kb_id,
            retrievalQuery={"text": query},
            retrievalConfiguration={
                "vectorSearchConfiguration": {"numberOfResults": max_results}
            },
        )
        passages = []
        for r in resp.get("retrievalResults", []):
            loc = r.get("location", {})
            uri = (
                loc.get("s3Location", {}).get("uri")
                or loc.get("webLocation", {}).get("url")
            )
            meta = r.get("metadata", {}) or {}
            title = meta.get("title") or (uri.rsplit("/", 1)[-1] if uri else "source")
            passages.append(
                Passage(
                    title=str(title)[:255],
                    uri=uri,
                    text=r.get("content", {}).get("text", ""),
                    score=float(r.get("score", 0.0)),
                )
            )
        return passages


class BedrockAssistant:
    """Guarded generation via Bedrock Runtime with a Guardrail (RF03)."""

    def __init__(self, runtime, model_id: str, guardrail_id: str, guardrail_version: str) -> None:
        self._client = runtime
        self._model_id = model_id
        self._guardrail_id = guardrail_id
        self._guardrail_version = guardrail_version

    def generate(self, question: str, passages) -> Generation:
        context = "\n\n".join(f"[{p.title}] {p.text}" for p in passages)
        system = (
            "Tu es l'assistant du campus. Réponds uniquement à partir du CONTEXTE. "
            "Si le contexte ne contient pas la réponse, dis que tu ne sais pas."
        )
        resp = self._client.converse(
            modelId=self._model_id,
            system=[{"text": system}],
            messages=[{"role": "user", "content": [{"text": f"CONTEXTE:\n{context}\n\nQUESTION: {question}"}]}],
            guardrailConfig={
                "guardrailIdentifier": self._guardrail_id,
                "guardrailVersion": self._guardrail_version,
                "trace": "enabled",
            },
        )
        stop_reason = resp.get("stopReason")
        blocked = stop_reason == "guardrail_intervened"
        text = ""
        for block in resp.get("output", {}).get("message", {}).get("content", []):
            if "text" in block:
                text += block["text"]
        grounding, relevance = _grounding_scores(resp.get("trace", {}))
        return Generation(
            text=text,
            grounding=grounding,
            relevance=relevance,
            blocked=blocked,
            sources=tuple(passages),
        )


def _grounding_scores(trace: dict) -> tuple[float, float]:
    """Extract contextual grounding/relevance scores from the Guardrail trace."""
    grounding = relevance = 0.0
    assessments = (
        trace.get("guardrail", {})
        .get("outputAssessments", {})
    )
    for items in assessments.values():
        for item in items:
            cg = item.get("contextualGroundingPolicy", {})
            for f in cg.get("filters", []):
                if f.get("type") == "GROUNDING":
                    grounding = max(grounding, float(f.get("score", 0.0)))
                elif f.get("type") == "RELEVANCE":
                    relevance = max(relevance, float(f.get("score", 0.0)))
    return grounding, relevance


class CloudWatchMetrics:
    """Emits EMF counters. Never receives message content."""

    def __init__(self, namespace: str = "SmartCampus/Chat") -> None:
        self._namespace = namespace

    def incr(self, name: str, value: int = 1) -> None:
        # Embedded Metric Format: structured log the CloudWatch agent turns into a metric.
        print(  # noqa: T201 — EMF is emitted via stdout by design
            json.dumps(
                {
                    "_aws": {
                        "CloudWatchMetrics": [
                            {
                                "Namespace": self._namespace,
                                "Dimensions": [[]],
                                "Metrics": [{"Name": name, "Unit": "Count"}],
                            }
                        ]
                    },
                    name: value,
                }
            )
        )


def build_from_env():
    """Construct the concrete adapters from environment configuration."""
    import boto3

    region = os.environ["AWS_REGION"]
    table = boto3.resource("dynamodb", region_name=region).Table(
        os.environ["CHAT_SESSIONS_TABLE"]
    )
    agent_runtime = boto3.client("bedrock-agent-runtime", region_name=region)
    runtime = boto3.client("bedrock-runtime", region_name=region)

    store = DynamoSessionStore(table)
    kb = BedrockKnowledgeBase(agent_runtime, os.environ["KNOWLEDGE_BASE_ID"])
    assistant = BedrockAssistant(
        runtime,
        model_id=os.environ["MODEL_ID"],
        guardrail_id=os.environ["GUARDRAIL_ID"],
        guardrail_version=os.environ["GUARDRAIL_VERSION"],
    )
    metrics = CloudWatchMetrics()
    return store, kb, assistant, metrics
