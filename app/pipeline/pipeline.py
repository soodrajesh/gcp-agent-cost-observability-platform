"""Orchestrates planner -> worker -> reviewer with input/output guardrails around it."""

from __future__ import annotations

import json
import uuid

from . import agents, bigquery_logger, guardrails


def _log_guardrail_block(request_id: str, direction: str, reason: str | None) -> None:
    # Structured stdout log the "guardrail_block_count" log-based metric extracts
    # (terraform/monitoring.tf) for the violation-rate alert policy.
    print(json.dumps({
        "message": "guardrail_block",
        "request_id": request_id,
        "direction": direction,
        "reason": reason,
    }))


def run_pipeline(question: str, request_id: str | None = None) -> dict:
    request_id = request_id or str(uuid.uuid4())

    input_check = guardrails.check_input(question)
    if input_check.blocked:
        bigquery_logger.log_guardrail_event(
            request_id=request_id,
            direction="input",
            reason=input_check.reason or "unknown",
            blocked=True,
            details=input_check.details,
        )
        _log_guardrail_block(request_id, "input", input_check.reason)
        return {
            "request_id": request_id,
            "blocked": True,
            "block_stage": "input",
            "reason": input_check.reason,
            "answer": None,
        }

    plan = agents.run_planner(question, request_id)
    draft = agents.run_worker(question, plan, request_id)
    review = agents.run_reviewer(question, draft, request_id)

    final_answer = review.get("final_answer", draft["draft_answer"])
    output_check = guardrails.check_output(final_answer, review.get("_safety_ratings"))
    if output_check.blocked:
        bigquery_logger.log_guardrail_event(
            request_id=request_id,
            direction="output",
            reason=output_check.reason or "unknown",
            blocked=True,
            details=output_check.details,
        )
        _log_guardrail_block(request_id, "output", output_check.reason)
        return {
            "request_id": request_id,
            "blocked": True,
            "block_stage": "output",
            "reason": output_check.reason,
            "answer": None,
        }

    return {
        "request_id": request_id,
        "blocked": False,
        "answer": final_answer,
        "approved_by_reviewer": review.get("approved"),
        "reviewer_notes": review.get("notes"),
        "plan": plan,
        "tool_calls": draft["tool_calls"],
    }
