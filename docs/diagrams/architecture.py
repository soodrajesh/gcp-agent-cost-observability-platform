#!/usr/bin/env python3
"""Generates docs/img/architecture.svg (PNG via docs/diagrams/render.py).

    python3 docs/diagrams/architecture.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from archlib import Diagram  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "img", "architecture.svg")

W, H = 1820, 1300
d = Diagram(W, H, "Agent Cost & Observability Platform on Google Cloud",
            "Vertex AI (Gemini) 3-agent pipeline · logged to BigQuery · input/output guardrails · scheduled LLM-judge eval · Cloud Monitoring")

d.group(170, 100, 1520, 660, "Google Cloud project  ·  europe-west1 / global (Vertex AI)", "#1a73e8", dash=False, fill="#f8faff", label_w=460)

# ── row 1 (y=250): caller, service, guardrails, Vertex AI ──────────────────────────
d.node("caller", 60, 250, "Caller", "user", "actor", "operator / eval-runner\n(ID token, no keys)")
d.node("svc", 330, 250, "agent-pipeline", "run", "compute", "Cloud Run service\nplanner -> worker -> reviewer")
d.node("guard_in", 620, 190, "Input guardrail", "shield", "security", "heuristic injection\ncheck (no LLM call)")
d.node("guard_out", 620, 310, "Output guardrail", "shield", "security", "safety ratings +\nsecret-shaped-string check")
d.node("vertex", 920, 250, "Vertex AI", "sparkle", "ai", "gemini-2.5-flash\nglobal endpoint")
d.node("tool", 920, 420, "query_spend tool", "filter", "dev", "synthetic cloud-spend\nfixture (in-process)")
d.node("bq", 1250, 250, "BigQuery", "db", "data", "llm_calls ·\nguardrail_events ·\neval_scores")
d.node("dash", 1560, 250, "Dashboard + alerts", "chart", "ops", "cost/latency/violations/\neval-score trend")

# ── row 2 (y=470): eval loop ─────────────────────────────────────────────────────────
d.node("sched", 330, 560, "Cloud Scheduler", "filter", "ops", "daily cron\nOAuth token, no keys")
d.node("job", 620, 560, "agent-eval-runner", "run", "compute", "Cloud Run Job\ngolden set + LLM judge")
d.node("golden", 330, 700, "golden_set.json", "db", "data", "8 fixed questions,\nreference answers")

d.edge("caller", "svc", "h", num=1, label="POST /ask (authenticated)")
d.edge("svc", "guard_in", "vh", num=2, sides=("t", "l"), label="check_input()")
d.edge("guard_in", "vertex", "h", num=3, label="if not blocked -> planner call")
d.edge("vertex", "tool", "v", num=4, label="worker: function call\nquery_spend(service, month)")
d.edge("tool", "vertex", "v", dash=True, label="tool result -> reviewer call")
d.edge("vertex", "bq", "h", num=5, label="every call logged:\nprompt/response/tokens/\ncost/latency/agent+step")
d.edge("svc", "guard_out", "vh", num=6, sides=("b", "l"), label="check_output()\non final answer")
d.edge("guard_out", "bq", "h", dash=True, label="violations -> guardrail_events")
d.edge("bq", "dash", "h", num=7, label="log-based metrics")
d.edge("sched", "job", "h", num=8, label="POST jobs.run (OAuth token)")
d.edge("golden", "job", "v")
d.edge("job", "svc", "vh", num=9, sides=("t", "b"), label="calls the SAME deployed\nservice with an ID token")
d.path([(620, 530), (620, 500), (1250, 500), (1250, 320)], num=10, label="judge scores -> eval_scores (is_synthetic=false)", lab_at=(950, 495))

d.badge(230, 800, "11", "#1e8e3e")
d.text(250, 805, "Every SA is scoped to its job: pipeline may only touch its BigQuery dataset slice + Vertex AI; eval-runner may additionally invoke", 12, "#3c4043")
d.text(250, 823, "the pipeline service; the scheduler may only start the eval-runner job. No service-account keys anywhere; no project-level owner/editor.", 12, "#3c4043")

d.band(170, 850, 1520, 130, "HONESTY ABOUT THE DATA  ·  see docs/adr/0002", "#d93025", "#fff8f7")
d.text(200, 892, "The cloud-spend numbers the agent reasons about are a small, deterministic SYNTHETIC fixture (spend_data.py) — a demo dataset, not live billing data.", 12.5, "#3c4043")
d.text(200, 916, "eval_scores has 20 days of SYNTHETIC seed history (is_synthetic=true) so the trend chart has more than one point on day one, plus real judged runs (is_synthetic=false).", 12.5, "#3c4043")
d.text(200, 940, "Every Gemini call, every guardrail decision, and every token/cost/latency figure is Captured/Live — the pipeline makes real, billed Vertex AI calls.", 12.5, "#3c4043")

d.legend(1300, 1000, "Numbered flows", [
    ("1", "authenticated request in"),
    ("2", "input guardrail check"),
    ("3", "planner call (Vertex AI)"),
    ("4", "worker tool call"),
    ("5", "every call logged"),
    ("6", "output guardrail check"),
    ("7", "log-based metrics"),
    ("8", "scheduler triggers eval"),
    ("9", "eval-runner calls the live service"),
    ("10", "judge scores -> BigQuery"),
])
d.key(170, 1000)

d.save(OUT)
print("wrote", OUT)
