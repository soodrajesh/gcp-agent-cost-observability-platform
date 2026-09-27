from pipeline import pricing


def test_compute_cost_known_model():
    cost = pricing.compute_cost_usd("gemini-2.5-flash", input_tokens=1_000_000, output_tokens=1_000_000)
    assert cost == 0.30 + 2.50


def test_thoughts_tokens_billed_as_output():
    a = pricing.compute_cost_usd("gemini-2.5-flash", input_tokens=0, output_tokens=0, thoughts_tokens=1_000_000)
    b = pricing.compute_cost_usd("gemini-2.5-flash", input_tokens=0, output_tokens=1_000_000, thoughts_tokens=0)
    assert a == b


def test_unknown_model_raises():
    import pytest
    with pytest.raises(ValueError):
        pricing.compute_cost_usd("not-a-real-model", 1, 1)
