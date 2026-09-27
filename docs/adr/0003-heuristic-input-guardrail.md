# 0003 — Heuristic (regex/keyword) input guardrail, not an LLM classifier

## Status
Accepted

## Context
Every request must be screened for prompt-injection / jailbreak attempts before it
reaches the planner. Two designs were considered: (a) call Gemini with a
classification prompt ("is this an injection attempt?"), or (b) a fast, explainable
heuristic (regex/keyword) screen with no model call.

## Decision
Use a heuristic screen (`app/pipeline/guardrails.py::check_input`) matching a curated
set of known injection/jailbreak phrasings ("ignore previous instructions", "reveal your
system prompt", "developer mode", etc.). It runs before any Vertex AI call.

## Trade-off called out
- **Recall is limited to known phrasings.** A novel or heavily obfuscated injection
  attempt (unusual phrasing, non-English, encoded text) can slip through a regex screen
  that an LLM classifier would likely catch. This repo's golden set (`q8`) exercises one
  canonical phrasing to prove the mechanism works, not to claim comprehensive coverage.
- **Zero extra cost/latency, and zero extra attack surface.** An LLM-based classifier is
  itself a Gemini call with its own prompt-injection exposure (the classifier's own
  system prompt could in principle be manipulated) and adds cost and latency to every
  request, including the vast majority that are legitimate.
- **The output-side guardrail is the backstop.** Anything that gets past the input
  screen and produces an unsafe or exfiltration-shaped answer is still caught by
  `check_output`'s Vertex AI safety-rating check and secret-shaped-string check before
  it's ever returned. Defense in depth, not reliance on one layer.

A production system with a larger threat surface should likely layer both: this repo's
choice optimizes for a demonstrable, zero-cost first line of defense.
