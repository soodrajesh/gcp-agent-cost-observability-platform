"""Every Vertex AI Gemini call in this repo goes through `call_gemini` so that the
logging middleware (prompt, response, tokens, cost, latency, agent/step identity) is
applied uniformly. Model is fixed to gemini-2.5-flash on the *global* endpoint — the
only model/endpoint combination verified to work reliably in this GCP project (checked
live 2026-09-27; see docs/adr/0001-gemini-2.5-flash-global-endpoint.md).
"""

from __future__ import annotations

import json
import os
import time

from google import genai
from google.genai import types

from . import bigquery_logger, pricing

PROJECT_ID = os.environ.get("PROJECT_ID", "")
MODEL = "gemini-2.5-flash"
LOCATION = "global"

_client: genai.Client | None = None


def _get_client() -> genai.Client:
    global _client
    if _client is None:
        # Two things had to be forced explicitly, both found live (see
        # docs/runbooks/03-troubleshooting.md): (1) api_version="v1" — this SDK
        # version's Vertex AI default is v1beta1, which 404s against the global
        # endpoint; (2) base_url="https://aiplatform.googleapis.com" — with
        # location="global" the SDK's default host-building logic produces
        # "global-aiplatform.googleapis.com", which doesn't exist (global is not a
        # regional host prefix); the earlier direct REST verification (ADR 0001) used
        # the un-prefixed host successfully.
        _client = genai.Client(
            vertexai=True,
            project=PROJECT_ID,
            location=LOCATION,
            http_options=types.HttpOptions(
                api_version="v1",
                base_url="https://aiplatform.googleapis.com",
            ),
        )
    return _client


class GeminiCallResult:
    def __init__(self, response, text: str, function_calls: list):
        self.response = response
        self.text = text
        self.function_calls = function_calls


def call_gemini(
    *,
    request_id: str,
    agent: str,
    step: int,
    contents,
    system_instruction: str | None = None,
    tools: list | None = None,
    is_synthetic: bool = False,
) -> GeminiCallResult:
    """One logged Gemini call. `contents` follows the google-genai `Content` shape
    (a string, or a list of `types.Content`). Returns text + any function calls the
    model asked for so the caller can execute them and continue the loop."""
    config_kwargs: dict = {}
    if system_instruction:
        config_kwargs["system_instruction"] = system_instruction
    if tools:
        config_kwargs["tools"] = tools
    config = types.GenerateContentConfig(**config_kwargs) if config_kwargs else None

    start = time.monotonic()
    response = _get_client().models.generate_content(
        model=MODEL,
        contents=contents,
        config=config,
    )
    latency_ms = (time.monotonic() - start) * 1000

    usage = response.usage_metadata
    input_tokens = getattr(usage, "prompt_token_count", 0) or 0
    output_tokens = getattr(usage, "candidates_token_count", 0) or 0
    thoughts_tokens = getattr(usage, "thoughts_token_count", 0) or 0
    cost = pricing.compute_cost_usd(MODEL, input_tokens, output_tokens, thoughts_tokens)

    text = ""
    function_calls: list = []
    try:
        text = response.text or ""
    except Exception:
        text = ""
    candidate = response.candidates[0] if response.candidates else None
    if candidate and candidate.content and candidate.content.parts:
        for part in candidate.content.parts:
            if getattr(part, "function_call", None):
                function_calls.append(part.function_call)

    prompt_repr = contents if isinstance(contents, str) else str(contents)
    bigquery_logger.log_llm_call(
        request_id=request_id,
        agent=agent,
        step=step,
        model=MODEL,
        prompt=prompt_repr,
        response_text=text,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        thoughts_tokens=thoughts_tokens,
        cost_usd=cost,
        latency_ms=latency_ms,
        had_function_call=bool(function_calls),
        is_synthetic=is_synthetic,
    )

    # Structured stdout log line: Cloud Run/Cloud Logging auto-parses JSON stdout as
    # jsonPayload, which is what the Cloud Monitoring log-based metrics in
    # terraform/monitoring.tf extract (token spend, latency by agent/model).
    print(json.dumps({
        "message": "llm_call",
        "request_id": request_id,
        "agent": agent,
        "step": step,
        "model": MODEL,
        "cost_usd": cost,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "thoughts_tokens": thoughts_tokens,
        "latency_ms": latency_ms,
        "is_synthetic": is_synthetic,
    }))

    return GeminiCallResult(response=response, text=text, function_calls=function_calls)


def safety_ratings_of(result: GeminiCallResult) -> list[dict]:
    candidate = result.response.candidates[0] if result.response.candidates else None
    ratings = getattr(candidate, "safety_ratings", None) if candidate else None
    if not ratings:
        return []
    out = []
    for r in ratings:
        out.append({
            "category": str(getattr(r, "category", "")),
            "probability": str(getattr(r, "probability", "NEGLIGIBLE")),
        })
    return out
