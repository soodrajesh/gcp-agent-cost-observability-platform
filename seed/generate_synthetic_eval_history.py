"""Generates SYNTHETIC eval-score history as newline-delimited JSON for `bq load`.

Every row has `is_synthetic = true` and a `run_id` prefixed `synthetic-`. The real
golden-set run(s) made by `scripts/test.sh` / `app/judge/run_golden_set.py` during a
live build are the only `is_synthetic = false` rows ever written to this table — see
docs/adr/0002-synthetic-seed-data-for-eval-history.md. Pure stdlib, no GCP calls, no
cost: it only writes a local file that `scripts/up.sh` then loads with `bq load`.
"""

from __future__ import annotations

import json
import random
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

QUESTION_IDS = [
    "q1-bigquery-aug", "q2-vertex-growth", "q3-cloudrun-jul", "q4-jul-total",
    "q5-storage-total", "q6-compute-aug", "q7-most-expensive-total", "q8-injection-attempt",
]

OUT_PATH = Path(__file__).resolve().parent / "synthetic_eval_history.jsonl"


def main() -> None:
    rng = random.Random(7)
    now = datetime.now(timezone.utc)
    n_days = 20
    rows = []
    for day_offset in range(n_days, 0, -1):
        run_id = f"synthetic-day-{day_offset}"
        scored_at = (now - timedelta(days=day_offset)).isoformat()
        dip = day_offset in (7, 8, 9)  # a deliberate, honestly-labelled synthetic regression
        for qid in QUESTION_IDS:
            base = 3 if dip else rng.choice([4, 4, 5])
            correctness = max(1, min(5, base + rng.choice([-1, 0, 0, 1])))
            completeness = max(1, min(5, base + rng.choice([-1, 0, 1])))
            safety = 5
            overall = round((correctness + completeness + safety) / 3, 2)
            rows.append({
                "run_id": run_id,
                "question_id": qid,
                "scored_at": scored_at,
                "correctness": correctness,
                "completeness": completeness,
                "safety": safety,
                "overall": overall,
                "judge_notes": "SYNTHETIC seed row for dashboard history — not a real judged run.",
                "is_synthetic": True,
            })
    OUT_PATH.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    print(f"wrote {len(rows)} synthetic eval_scores rows to {OUT_PATH}")


if __name__ == "__main__":
    main()
