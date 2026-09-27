"""Cloud Run service entrypoint: the deployed agent pipeline API."""

from __future__ import annotations

import logging

from fastapi import FastAPI
from pydantic import BaseModel

from . import pipeline

logging.basicConfig(level=logging.INFO)
app = FastAPI(title="agent-cost-observability-pipeline")


class AskRequest(BaseModel):
    question: str
    request_id: str | None = None


@app.get("/livez")
def livez():
    # Not "/healthz": Google's front end intercepts that exact path for its own
    # infrastructure health checks and never forwards it to the container — found live
    # (every call to /healthz returned Google's generic 404 page, not this app's
    # response, even through an authenticated `gcloud run services proxy` tunnel). See
    # docs/runbooks/03-troubleshooting.md.
    return {"status": "ok"}


@app.post("/ask")
def ask(req: AskRequest):
    result = pipeline.run_pipeline(req.question, request_id=req.request_id)
    # Structured log line: the source for the log-based metrics Cloud Monitoring reads
    # (token spend, latency, guardrail violations) — see terraform/monitoring.tf.
    logging.info(
        "agent_pipeline_result",
        extra={"json_fields": {
            "request_id": result["request_id"],
            "blocked": result["blocked"],
            "block_stage": result.get("block_stage"),
        }},
    )
    return result
