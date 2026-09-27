"""Published Vertex AI pricing for the models this repo uses.

Source: https://cloud.google.com/vertex-ai/generative-ai/pricing (checked 2026-09-27).
Prices are USD per 1,000,000 tokens, on-demand, text modality, <=200k context tier.
gemini-2.5-flash: $0.30 / 1M input tokens, $2.50 / 1M output tokens.
Thinking tokens are billed as output tokens (Vertex AI bills them under
candidatesTokenCount + thoughtsTokenCount at the output rate).

Keeping this as a plain dict (not a live pricing API call — Google does not publish one)
means the cost figures in this repo are computed, not fabricated, but will drift if
Google changes prices; see docs/runbooks/04-cost.md.
"""

from __future__ import annotations

USD_PER_1M_INPUT_TOKENS = {
    "gemini-2.5-flash": 0.30,
}
USD_PER_1M_OUTPUT_TOKENS = {
    "gemini-2.5-flash": 2.50,
}


def compute_cost_usd(model: str, input_tokens: int, output_tokens: int, thoughts_tokens: int = 0) -> float:
    """Cost in USD for one Gemini call, per published Vertex AI pricing.

    Thoughts tokens (Gemini 2.5's internal reasoning tokens) are billed at the
    output rate, same as candidate tokens.
    """
    in_rate = USD_PER_1M_INPUT_TOKENS.get(model)
    out_rate = USD_PER_1M_OUTPUT_TOKENS.get(model)
    if in_rate is None or out_rate is None:
        raise ValueError(f"no published pricing recorded for model {model!r}")
    billed_output = output_tokens + thoughts_tokens
    return (input_tokens / 1_000_000) * in_rate + (billed_output / 1_000_000) * out_rate
