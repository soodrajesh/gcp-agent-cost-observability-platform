"""The three-agent pipeline: planner -> worker (tool-using) -> reviewer.

Task: answer a question about the synthetic cloud-spend fixture in `spend_data.py`.
- planner decides which service/month slice(s) the question needs.
- worker calls the `query_spend` tool (real Gemini function calling, not a canned
  branch) to fetch those numbers, then drafts an answer.
- reviewer checks the draft against the tool's actual returned numbers and either
  approves it or corrects it — this is the check that catches the model asserting a
  number that doesn't match what the tool actually returned.

Every step's prompt/response/tokens/cost/latency is logged by `llm_client.call_gemini`.
"""

from __future__ import annotations

import json

from google.genai import types

from . import llm_client, spend_data

QUERY_SPEND_TOOL = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="query_spend",
            description=(
                "Look up synthetic cloud-spend fixture data: total USD and matching "
                "rows for a given service and/or month. Omit a parameter to match all "
                "values of that dimension."
            ),
            parameters=types.Schema(
                type="OBJECT",
                properties={
                    "service": types.Schema(
                        type="STRING",
                        description=f"One of: {', '.join(spend_data.SERVICES)}",
                    ),
                    "month": types.Schema(
                        type="STRING",
                        description=f"One of: {', '.join(spend_data.MONTHS)} (YYYY-MM)",
                    ),
                },
            ),
        )
    ]
)

PLANNER_INSTRUCTION = (
    "You are the planning agent for a FinOps question-answering pipeline over a fixed "
    "cloud-spend dataset (services: {services}; months: {months}). Given the user's "
    "question, output a short JSON object {{\"steps\": [\"...\"]}} listing 1-3 concrete "
    "lookups the worker agent should make with its query_spend(service, month) tool to "
    "answer it. Output only the JSON object, nothing else."
).format(services=", ".join(spend_data.SERVICES), months=", ".join(spend_data.MONTHS))

WORKER_INSTRUCTION = (
    "You are the worker agent. You have a query_spend(service, month) tool over a fixed "
    "synthetic cloud-spend dataset. Use it as needed to answer the user's question "
    "precisely, then give a concise final answer citing the exact dollar figures the "
    "tool returned. Do not invent numbers that did not come from the tool."
)

REVIEWER_INSTRUCTION = (
    "You are the reviewer agent. You are given the user's question, the worker's draft "
    "answer, and the exact tool call results the worker used (ground truth numbers). "
    "Check the draft's figures against the tool results. Respond with a JSON object: "
    "{\"approved\": true|false, \"final_answer\": \"...\", \"notes\": \"...\"}. If the "
    "draft's numbers match the tool results and the answer is clear, approve it "
    "verbatim as final_answer. If not, correct it using the tool results and set "
    "approved to false. Output only the JSON object."
)


def run_planner(question: str, request_id: str) -> dict:
    result = llm_client.call_gemini(
        request_id=request_id,
        agent="planner",
        step=1,
        contents=question,
        system_instruction=PLANNER_INSTRUCTION,
    )
    try:
        return json.loads(_strip_fences(result.text))
    except Exception:
        return {"steps": [question]}


def run_worker(question: str, plan: dict, request_id: str) -> dict:
    tool_calls_made = []
    contents: list = [
        types.Content(role="user", parts=[types.Part(text=(
            f"Question: {question}\nPlan: {json.dumps(plan)}"
        ))])
    ]

    for step_offset in range(3):  # at most 3 tool-call round trips
        result = llm_client.call_gemini(
            request_id=request_id,
            agent="worker",
            step=2,
            contents=contents,
            system_instruction=WORKER_INSTRUCTION,
            tools=[QUERY_SPEND_TOOL],
        )
        if not result.function_calls:
            return {"draft_answer": result.text, "tool_calls": tool_calls_made}

        candidate = result.response.candidates[0]
        contents.append(candidate.content)
        function_response_parts = []
        for fc in result.function_calls:
            args = dict(fc.args or {})
            tool_result = spend_data.query_spend(
                service=args.get("service"), month=args.get("month")
            )
            tool_calls_made.append({"args": args, "result": tool_result})
            function_response_parts.append(
                types.Part.from_function_response(name=fc.name, response=tool_result)
            )
        contents.append(types.Content(role="user", parts=function_response_parts))

    return {"draft_answer": "Could not resolve after multiple tool calls.", "tool_calls": tool_calls_made}


def run_reviewer(question: str, draft: dict, request_id: str) -> dict:
    prompt = (
        f"Question: {question}\n"
        f"Draft answer: {draft['draft_answer']}\n"
        f"Tool call results (ground truth): {json.dumps(draft['tool_calls'])}"
    )
    result = llm_client.call_gemini(
        request_id=request_id,
        agent="reviewer",
        step=3,
        contents=prompt,
        system_instruction=REVIEWER_INSTRUCTION,
    )
    try:
        parsed = json.loads(_strip_fences(result.text))
    except Exception:
        parsed = {"approved": False, "final_answer": draft["draft_answer"], "notes": "reviewer JSON parse failed"}
    parsed["_safety_ratings"] = llm_client.safety_ratings_of(result)
    return parsed


def _strip_fences(text: str) -> str:
    t = text.strip()
    if t.startswith("```"):
        t = t.split("\n", 1)[1] if "\n" in t else t
        t = t.rsplit("```", 1)[0]
    return t.strip()
