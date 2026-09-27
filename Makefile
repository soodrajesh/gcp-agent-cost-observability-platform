.PHONY: help up down plan test lint app-test diagram eval
help: ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'
up: ## build EVERYTHING end to end and prove it works
	./scripts/up.sh
down: ## delete EVERYTHING this repo created (PURGE=1 also drops the state)
	./scripts/down.sh $(if $(PURGE),--purge,)
plan: ## terraform plan (phase 1)
	./scripts/up.sh --plan
test: ## live test suite against the running platform
	./scripts/test.sh
eval: ## run the golden set once, on demand, against the deployed service
	gcloud run jobs execute agent-eval-runner --region europe-west1 --wait
app-test: ## unit tests for pricing + guardrails
	PYTHONPATH=app pytest app/pipeline/tests -q
lint: ## ruff, terraform fmt + validate, shellcheck
	ruff check app
	terraform -chdir=terraform fmt -check -recursive && terraform -chdir=terraform validate
	shellcheck -S warning -x scripts/*.sh
diagram: ## regenerate docs/img/architecture.{svg,png}
	python3 docs/diagrams/architecture.py && python3 docs/diagrams/render.py docs/img/architecture.svg docs/img/architecture.png
