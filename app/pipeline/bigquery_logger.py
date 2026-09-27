"""Thin BigQuery sink for LLM-call logs, guardrail events, and eval scores.

Every write here is a real streaming insert to a real BigQuery table (no buffering,
no batching) — when the pipeline runs live, these rows are Captured/Live data. The one
exception in this repo is `seed/seed_synthetic_history.py`, which deliberately writes
rows with `is_synthetic = true` to backfill history for the score-trend chart; that
script is the only place synthetic rows are ever written, and it is called out as such
everywhere it matters (README, ADR 0002, runbook 02).
"""

from __future__ import annotations

import os
from datetime import datetime, timezone

from google.cloud import bigquery

PROJECT_ID = os.environ.get("PROJECT_ID", "")
DATASET = os.environ.get("BQ_DATASET", "agent_observability")

_client: bigquery.Client | None = None


def _get_client() -> bigquery.Client:
    global _client
    if _client is None:
        _client = bigquery.Client(project=PROJECT_ID)
    return _client


def _insert(table: str, row: dict) -> None:
    table_ref = f"{PROJECT_ID}.{DATASET}.{table}"
    errors = _get_client().insert_rows_json(table_ref, [row])
    if errors:
        raise RuntimeError(f"BigQuery insert into {table_ref} failed: {errors}")


def log_llm_call(
    *,
    request_id: str,
    agent: str,
    step: int,
    model: str,
    prompt: str,
    response_text: str,
    input_tokens: int,
    output_tokens: int,
    thoughts_tokens: int,
    cost_usd: float,
    latency_ms: float,
    had_function_call: bool,
    is_synthetic: bool = False,
) -> None:
    _insert(
        "llm_calls",
        {
            "request_id": request_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "agent": agent,
            "step": step,
            "model": model,
            "prompt": prompt[:8000],
            "response_text": response_text[:8000],
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "thoughts_tokens": thoughts_tokens,
            "cost_usd": cost_usd,
            "latency_ms": latency_ms,
            "had_function_call": had_function_call,
            "is_synthetic": is_synthetic,
        },
    )


def log_guardrail_event(
    *,
    request_id: str,
    direction: str,  # "input" | "output"
    reason: str,
    blocked: bool,
    details: dict,
) -> None:
    import json

    _insert(
        "guardrail_events",
        {
            "request_id": request_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "direction": direction,
            "reason": reason,
            "blocked": blocked,
            "details_json": json.dumps(details),
        },
    )


def log_eval_score(
    *,
    run_id: str,
    question_id: str,
    correctness: int,
    completeness: int,
    safety: int,
    overall: float,
    judge_notes: str,
    is_synthetic: bool,
    scored_at: str | None = None,
) -> None:
    _insert(
        "eval_scores",
        {
            "run_id": run_id,
            "question_id": question_id,
            "scored_at": scored_at or datetime.now(timezone.utc).isoformat(),
            "correctness": correctness,
            "completeness": completeness,
            "safety": safety,
            "overall": overall,
            "judge_notes": judge_notes[:2000],
            "is_synthetic": is_synthetic,
        },
    )
