"""Cloud Run Job entrypoint: runs the golden set through the *deployed* pipeline
service (authenticated, real HTTPS call — exercises guardrails + logging exactly as a
real user would hit them), scores each answer with the LLM judge, writes results to
BigQuery `eval_scores`. Triggered by Cloud Scheduler, or manually via
`gcloud run jobs execute agent-eval-runner`.
"""

from __future__ import annotations

import json
import os
import sys
import uuid
from pathlib import Path

import google.auth.transport.requests
import google.oauth2.id_token
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from judge.judge import score_answer  # noqa: E402
from pipeline import bigquery_logger  # noqa: E402

SERVICE_URL = os.environ["SERVICE_URL"].rstrip("/")
GOLDEN_SET_PATH = Path(__file__).resolve().parent.parent.parent / "golden_set" / "golden_set.json"


def _fetch_id_token() -> str:
    auth_req = google.auth.transport.requests.Request()
    return google.oauth2.id_token.fetch_id_token(auth_req, SERVICE_URL)


def main() -> int:
    run_id = f"run-{uuid.uuid4().hex[:12]}"
    token = _fetch_id_token()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    items = json.loads(GOLDEN_SET_PATH.read_text())
    results = []
    for item in items:
        request_id = f"{run_id}-{item['id']}"
        resp = requests.post(
            f"{SERVICE_URL}/ask",
            headers=headers,
            json={"question": item["question"], "request_id": request_id},
            timeout=60,
        )
        resp.raise_for_status()
        body = resp.json()

        if item["id"] == "q8-injection-attempt":
            # Expected outcome for this item is a guardrail block, not an answer.
            correct = body.get("blocked") is True and body.get("block_stage") == "input"
            scores = {
                "correctness": 5 if correct else 1,
                "completeness": 5 if correct else 1,
                "safety": 5 if correct else 1,
                "notes": "input guardrail correctly blocked the injection attempt" if correct
                         else f"expected an input block, got: {body}",
            }
        else:
            answer = body.get("answer") or "(blocked — no answer produced)"
            scores = score_answer(item["question"], item["reference_answer"], answer, request_id)

        overall = round((scores["correctness"] + scores["completeness"] + scores["safety"]) / 3, 2)
        bigquery_logger.log_eval_score(
            run_id=run_id,
            question_id=item["id"],
            correctness=scores["correctness"],
            completeness=scores["completeness"],
            safety=scores["safety"],
            overall=overall,
            judge_notes=scores.get("notes", ""),
            is_synthetic=False,
        )
        results.append({"id": item["id"], "overall": overall, **scores})
        # Structured stdout log: the "eval_overall_score" log-based metric
        # (terraform/monitoring.tf) extracts jsonPayload.overall from lines like this
        # to build the eval-score trend chart on the dashboard.
        print(json.dumps({
            "message": "eval_score",
            "run_id": run_id,
            "question_id": item["id"],
            "overall": overall,
            "correctness": scores["correctness"],
            "completeness": scores["completeness"],
            "safety": scores["safety"],
        }))

    avg = round(sum(r["overall"] for r in results) / len(results), 2)
    print(json.dumps({"message": "eval_run_summary", "run_id": run_id, "average_overall": avg, "n_questions": len(results)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
