.PHONY: lint test role-tests deploy verify check caprover-check caprover-deploy caprover-verify scan bootstrap setup update-pins update-pins-dry orchestrator smoke-test help

lint:                          ## Run all linters in parallel (yamllint + ansible-lint + shellcheck + syntax check)
	@echo "Running linters in parallel…" && \
	fail=0; \
	yamllint . & p1=$$!; \
	ansible-lint & p2=$$!; \
	(ansible-playbook playbook.yml --syntax-check && ansible-playbook caprover-playbook.yml --syntax-check) & p3=$$!; \
	(bash -n bootstrap.sh && shellcheck bootstrap.sh && \
	 bash -n scripts/update-pins.sh && shellcheck scripts/update-pins.sh && \
	 bash -n scripts/caprover-bootstrap-keys.sh && shellcheck scripts/caprover-bootstrap-keys.sh && \
	 bash -n scripts/smoke-test-models.sh && shellcheck scripts/smoke-test-models.sh) & p4=$$!; \
	wait $$p1 || fail=1; wait $$p2 || fail=1; wait $$p3 || fail=1; wait $$p4 || fail=1; \
	[ $$fail -eq 0 ] && echo "All linters passed" || (echo "Lint failed" && exit 1)

test:                          ## Run all Molecule tests (project + CapRover + role-level)
	molecule test -s default && molecule test -s caprover && $(MAKE) role-tests

role-tests:                    ## Run Molecule tests for template-bearing roles (parallel)
	@fail=0; \
	(cd roles/base && molecule test) & p1=$$!; \
	(cd roles/openclaw-config && molecule test) & p2=$$!; \
	(cd roles/openclaw-harden && molecule test) & p3=$$!; \
	(cd roles/reverse-proxy && molecule test) & p4=$$!; \
	(cd roles/maintenance && molecule test) & p5=$$!; \
	(cd roles/convenience && molecule test) & p6=$$!; \
	wait $$p1 || fail=1; wait $$p2 || fail=1; wait $$p3 || fail=1; \
	wait $$p4 || fail=1; wait $$p5 || fail=1; wait $$p6 || fail=1; \
	[ $$fail -eq 0 ] && echo "All role tests passed" || (echo "Role tests failed" && exit 1)

update-pins:                   ## Fetch latest commit SHAs for all pinned dependencies
	bash scripts/update-pins.sh

update-pins-dry:               ## Show what update-pins would change (no modifications)
	bash scripts/update-pins.sh --dry-run

deploy: update-pins            ## Deploy OpenClaw to target server (updates pins first)
	ansible-playbook playbook.yml -i inventory/hosts.yml --ask-vault-pass

verify:                        ## Run verification tasks only
	ansible-playbook playbook.yml -i inventory/hosts.yml --tags verify --ask-vault-pass

caprover-bootstrap:            ## Distribute SSH keys to fresh CapRover servers (one-time)
	bash scripts/caprover-bootstrap-keys.sh

caprover-deploy:               ## Deploy CapRover monitoring swarm (3 nodes)
	ansible-playbook caprover-playbook.yml -i inventory/caprover-hosts.yml -e @group_vars/caprover/vars.deploy.yml --ask-vault-pass

caprover-verify:               ## Verify CapRover swarm deployment
	ansible-playbook caprover-playbook.yml -i inventory/caprover-hosts.yml -e @group_vars/caprover/vars.deploy.yml --tags verify --ask-vault-pass

caprover-check:                ## Lint + test CapRover monitoring config only
	yamllint caprover-playbook.yml && ansible-lint caprover-playbook.yml && ansible-playbook caprover-playbook.yml --syntax-check && molecule test -s caprover

scan:                          ## Scan for secret leaks (requires gitleaks)
	@if command -v gitleaks >/dev/null 2>&1; then \
		gitleaks detect --source . -v; \
	else \
		echo "SKIP scan: gitleaks not found — install with 'brew install gitleaks'"; \
	fi

smoke-test:                    ## Smoke-test all LLM models via LiteLLM (~$0.02)
	ansible-playbook playbook.yml -i inventory/hosts.yml --tags smoke-test --ask-vault-pass

orchestrator:                  ## Open agent orchestrator dashboard via SSH tunnel
	@echo "\n\033[36m🔗 Agent Orchestrator: http://localhost:3000"
	@ssh -L 3000:127.0.0.1:3000 deploy@38.49.214.92 -p 9922

check: lint test scan          ## Run lint + test + scan (full CI equivalent)

bootstrap:                     ## Run bootstrap script (pass ARGS="--config deploy.yml" for flags)
	bash bootstrap.sh $(ARGS)

setup:                         ## Install pre-commit hooks (run once after clone)
	pip install pre-commit && pre-commit install

audit:
	claude -p "Run a full audit: 1) yamllint on all .yml files 2) check for hardcoded secrets 3) verify molecule scenarios exist for all roles. Output results as a markdown table." --allowedTools "Bash,Read,Glob,Grep"

help:                          ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
