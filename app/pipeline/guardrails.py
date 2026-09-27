"""Input and output guardrails for the agent pipeline.

Input side: a heuristic prompt-injection / jailbreak check. This is deliberately a
fast, explainable, zero-extra-LLM-call regex/keyword screen, not a model call — it runs
on every request before any Vertex AI spend happens, so a malicious prompt is rejected
for ~free. See docs/adr/0003-heuristic-input-guardrail.md for the trade-off (recall vs.
an LLM-based classifier).

Output side: two checks that must both pass:
  1. Vertex AI's own safety ratings on the generated content (harassment, hate speech,
     sexually explicit, dangerous content) — HIGH or MEDIUM+HIGH probability blocks.
  2. An explicit data-exfiltration rubric check: does the answer contain something that
     looks like it echoed back a secret/credential-shaped string, or tried to include
     content it was never given (a sign of the model being steered by injected
     instructions in tool output). This is the control that specifically targets the
     "agent leaks data via tool output" STRIDE threat in docs/threat-model.md.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# --- Input guardrail -------------------------------------------------------

_INJECTION_PATTERNS = [
    r"ignore (all|any|the) (previous|prior|above) instructions",
    r"disregard (all|any|the) (previous|prior|above)",
    r"you are now (in )?(dan|developer mode|jailbreak)",
    r"reveal (your|the) (system prompt|instructions)",
    r"print (your|the) (system prompt|instructions)",
    r"act as if you (have no|had no) (restrictions|guardrails|filters)",
    r"pretend (you are|to be) .*(no rules|unfiltered|uncensored)",
    r"\bbegin system override\b",
    r"forget (everything|all) (you were told|above)",
    r"what (is|are) your (hidden|secret) (instructions|prompt)",
]
_INJECTION_RE = re.compile("|".join(_INJECTION_PATTERNS), re.IGNORECASE)

_SECRET_SHAPED_RE = re.compile(
    r"(AIza[0-9A-Za-z\-_]{35})"          # Google API key shape
    r"|(sk-[A-Za-z0-9]{20,})"            # generic secret-key shape
    r"|(-----BEGIN [A-Z ]+PRIVATE KEY-----)"
)


@dataclass
class GuardrailResult:
    blocked: bool
    reason: str | None = None
    details: dict = field(default_factory=dict)


def check_input(user_text: str) -> GuardrailResult:
    """Heuristic screen for prompt-injection / jailbreak attempts. Runs before any
    Vertex AI call, so a caught attempt costs nothing."""
    match = _INJECTION_RE.search(user_text)
    if match:
        return GuardrailResult(
            blocked=True,
            reason="prompt_injection_heuristic",
            details={"matched_pattern": match.group(0)},
        )
    return GuardrailResult(blocked=False)


def check_output(
    text: str,
    safety_ratings: list[dict] | None,
    tool_context: str | None = None,
) -> GuardrailResult:
    """Content-safety + data-exfiltration rubric check on a generated answer.

    `safety_ratings` is Gemini's own `candidates[].safetyRatings` (probability +
    blocked flag per harm category). `tool_context` is the raw tool-call output the
    worker agent was given, if any — used only to detect the answer echoing back a
    secret-shaped string that was never present in the tool output (a sign of
    fabrication/exfiltration rather than an injected secret actually being present).
    """
    for rating in safety_ratings or []:
        prob = rating.get("probability", "NEGLIGIBLE")
        if prob in ("HIGH", "MEDIUM"):
            return GuardrailResult(
                blocked=True,
                reason="vertex_safety_rating",
                details={"category": rating.get("category"), "probability": prob},
            )

    secret_match = _SECRET_SHAPED_RE.search(text)
    if secret_match:
        return GuardrailResult(
            blocked=True,
            reason="secret_shaped_output",
            details={"matched": secret_match.group(0)[:12] + "…"},
        )

    return GuardrailResult(blocked=False)
