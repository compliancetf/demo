# Local workflow for the compliance.tf ISO 27001 demo. CI lives in .github/.
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

AWS_PROFILE ?= demo
AWS_REGION ?= eu-west-1
export AWS_PROFILE AWS_REGION

# Registry auth: Terraform reads the token for registry sources, .netrc for HTTPS sources
export TF_TOKEN_iso27001_compliance_tf := $(CTF_REGISTRY_TOKEN)
NETRC ?= $(CURDIR)/.netrc
export NETRC
TF_REGISTRY_CLIENT_TIMEOUT ?= 60
export TF_REGISTRY_CLIENT_TIMEOUT

TF := terraform -chdir=infra
PLAN_JSON := infra/plan.json
SWAP := scripts/swap-sources.sh
MODE := scripts/demo-mode.sh
# Variable validations: all reported by the first failing plan.
EXPECTED_CONTROLS := kms_cmk_rotation_enabled sns_topic_encrypted_at_rest vpc_subnet_auto_assign_public_ip_disabled \
  cloudwatch_log_group_retention_period_365 log_group_encryption_at_rest_enabled ec2_instance_uses_imdsv2
# Resource precondition: Terraform checks it only once validations pass, so it gets its own plan.
PRECONDITION_CONTROL := ecs_service_not_publicly_accessible

.PHONY: help check-tools login bootstrap init scan plan report baseline-branch apply-baseline scan-baseline verify verify-fail demo-pr demo-fix exception-pr record-exception destroy clean require-clean require-backend

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

check-tools: ## Check that terraform, jq, aws, gh and ctfkit are installed
	@missing=0; for t in terraform jq aws gh ctfkit; do \
	  if command -v $$t >/dev/null; then echo "ok       $$t"; else echo "missing  $$t"; missing=1; fi; \
	done; exit $$missing

login: ## Write .netrc for the ISO 27001 endpoint from CTF_REGISTRY_TOKEN
	@if [ -z "$(CTF_REGISTRY_TOKEN)" ]; then echo "CTF_REGISTRY_TOKEN is empty: export your compliance.tf registry token first" >&2; exit 1; fi
	@umask 077; printf 'machine iso27001.compliance.tf login token password %s\n' "$(CTF_REGISTRY_TOKEN)" > "$(NETRC)"
	@chmod 600 "$(NETRC)"
	@echo "wrote $(NETRC)"

bootstrap: ## Create the state bucket and GitHub plan role (local state), write infra/backend.hcl
	terraform -chdir=bootstrap init
	terraform -chdir=bootstrap apply
	@printf 'bucket = "%s"\nregion = "%s"\n' \
	  "$$(terraform -chdir=bootstrap output -raw state_bucket)" \
	  "$$(terraform -chdir=bootstrap output -raw region)" > infra/backend.hcl
	@echo "wrote infra/backend.hcl"
	@echo "Repository variables: AWS_REGION=$$(terraform -chdir=bootstrap output -raw region)" \
	  "TF_STATE_BUCKET=$$(terraform -chdir=bootstrap output -raw state_bucket)" \
	  "AWS_PLAN_ROLE_ARN=$$(terraform -chdir=bootstrap output -raw plan_role_arn)"

require-backend:
	@[ -f infra/backend.hcl ] || { echo "infra/backend.hcl is missing: run make bootstrap" >&2; exit 1; }

init: require-backend ## terraform init with the remote backend
	$(TF) init -reconfigure -backend-config=backend.hcl

scan: ## ctfkit scan of the Terraform code (before plan)
	ctfkit scan infra --stage pre_plan --exceptions .github/ctfkit/exceptions.yaml

plan: require-backend ## terraform plan, save plan.json and scan it with ctfkit
	$(TF) plan -out=tfplan
	$(TF) show -json tfplan > $(PLAN_JSON)
	ctfkit scan $(PLAN_JSON) --chdir infra --exceptions .github/ctfkit/exceptions.yaml

report: ## ctfkit compliance report for infra/
	ctfkit report --path infra --exceptions .github/ctfkit/exceptions.yaml

require-clean:
	@git diff --quiet && git diff --cached --quiet || { echo "working tree has changes: commit or stash first" >&2; exit 1; }

baseline-branch: require-clean ## Create or refresh branch baseline: master with upstream sources and insecure inputs
	git checkout -B baseline master
	$(SWAP) to-upstream
	$(MODE) insecure
	git add infra
	git diff --cached --quiet || git commit -m "chore: use upstream terraform-aws-modules with insecure inputs"
	git checkout master

apply-baseline: require-clean require-backend ## Check out baseline and apply it (asks for confirmation)
	git checkout baseline
	$(TF) init -reconfigure -backend-config=backend.hcl
	$(TF) apply

scan-baseline: ## Push branch baseline and run the CI scan on it: its findings become open alerts on the Security tab
	git push --force-with-lease origin baseline
	gh workflow run terraform.yml --ref baseline

verify: require-backend login ## On master (ISO sources, secure inputs): plan, assert in-place changes only, report
	@grep -q 'iso27001.compliance.tf' infra/*.tf || { echo "infra/ does not use compliance.tf sources: check out master" >&2; exit 1; }
	@! grep -q '# demo:insecure$$' infra/*.tf || { echo "infra/ has active demo:insecure lines: run $(MODE) secure" >&2; exit 1; }
	$(TF) init -reconfigure -upgrade -backend-config=backend.hcl
	$(TF) plan -out=tfplan
	$(TF) show -json tfplan > $(PLAN_JSON)
	scripts/check-plan.sh $(PLAN_JSON)
	ctfkit scan $(PLAN_JSON) --chdir infra --exceptions .github/ctfkit/exceptions.yaml
	ctfkit report --path infra --exceptions .github/ctfkit/exceptions.yaml || echo "WARN: ctfkit report failed (coverage table only, plan checks passed)" >&2

verify-fail: login ## Plan a temp copy with ISO sources and insecure inputs; assert every expected control blocks it
	@tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
	cp infra/*.tf infra/.terraform.lock.hcl "$$tmp"/; \
	printf 'terraform {\n  backend "local" {}\n}\n' > "$$tmp"/backend_override.tf; \
	$(SWAP) to-iso "$$tmp" >/dev/null; $(MODE) insecure "$$tmp" >/dev/null; \
	terraform -chdir="$$tmp" init -input=false >/dev/null; \
	if terraform -chdir="$$tmp" plan -input=false -lock=false -no-color > "$$tmp"/plan.log 2>&1; then \
	  echo "FAIL: plan succeeded, expected compliance.tf control errors" >&2; exit 1; fi; \
	missing=0; for id in $(EXPECTED_CONTROLS); do \
	  if grep -q "Control '$$id'" "$$tmp"/plan.log; then echo "blocked  $$id"; else echo "MISSING  $$id"; missing=1; fi; \
	done; \
	if [ $$missing -ne 0 ]; then echo "plan output:" >&2; cat "$$tmp"/plan.log >&2; exit 1; fi; \
	$(MODE) secure "$$tmp" >/dev/null; \
	perl -i -pe 's/^(\s*)# demo:insecure (assign_public_ip = true)/$$1$$2/' "$$tmp"/ecs.tf; \
	terraform -chdir="$$tmp" plan -input=false -lock=false -no-color > "$$tmp"/plan2.log 2>&1; \
	if grep -q "Control '$(PRECONDITION_CONTROL)'" "$$tmp"/plan2.log; then echo "blocked  $(PRECONDITION_CONTROL) (precondition)"; \
	else echo "MISSING  $(PRECONDITION_CONTROL)"; cat "$$tmp"/plan2.log >&2; exit 1; fi; \
	echo "OK: plan fails on every expected control"

demo-pr: require-clean ## Branch demo/iso27001 from baseline, switch to ISO sources, open a PR
	git checkout -B demo/iso27001 baseline
	$(SWAP) to-iso
	git add infra
	git commit -m "feat: use compliance.tf ISO 27001 modules"
	git push --force-with-lease -u origin demo/iso27001
	gh pr create --base baseline --head demo/iso27001 \
	  --title "feat: use compliance.tf ISO 27001 modules" \
	  --body "Switches every terraform-aws-modules source to the compliance.tf ISO/IEC 27001:2022 endpoint and changes nothing else. The plan fails: each Control error names an insecure input and how to fix it."

demo-fix: require-clean ## On demo/iso27001: apply the remediations (secure inputs), push to the open PR
	git checkout demo/iso27001
	$(MODE) secure
	git add infra
	git commit -m "fix: apply compliance.tf remediations"
	git push origin demo/iso27001

exception-pr: require-clean ## After demo-fix: branch demo/log-retention-exception, 30-day logs with the retention control disabled, open a PR
	git checkout -B demo/log-retention-exception demo/iso27001
	perl -0777 -pi -e 's{^([ \t]*)source[ \t]*=[ \t]*"iso27001\.compliance\.tf/terraform-aws-modules/ecs/aws"[ \t]*\n[ \t]*version[ \t]*=[ \t]*"([^"]+)"[ \t]*\n}{$$1source = "https://iso27001.compliance.tf/terraform-aws-modules/ecs/aws?version=$$2&disable=cloudwatch_log_group_retention_period_365"\n}m; s{^([ \t]*log_retention_days[ \t]*=[ \t]*)\d+}{$${1}30}m' infra/ecs.tf
	git add infra/ecs.tf
	git commit -m "dev: keep 30-day container logs for cost"
	git push --force-with-lease -u origin demo/log-retention-exception
	gh pr create --base demo/iso27001 --head demo/log-retention-exception \
	  --title "dev: keep 30-day container logs for cost" \
	  --body "Keeps container logs for 30 days instead of 365 by disabling cloudwatch_log_group_retention_period_365 on the ecs module. ctfkit fails the check until the exception is recorded."

record-exception: require-clean ## On demo/log-retention-exception: record the exception in the ctfkit registry, push to the open PR
	git checkout demo/log-retention-exception
	printf '%s\n' \
	  '' \
	  '  - id: demo-ecs-log-retention' \
	  '    control: cloudwatch_log_group_retention_period_365' \
	  '    resource: module.ecs' \
	  '    justification: >-' \
	  '      Dev environment keeps container logs for 30 days for cost. Production keeps the 365-day' \
	  '      retention the control requires.' \
	  '    owner: antonbabenko' \
	  '    approved_by: antonbabenko' \
	  '    review_date: "2027-06-30"' >> .github/ctfkit/exceptions.yaml
	git add .github/ctfkit/exceptions.yaml
	git commit -m "chore: record the 30-day log retention exception"
	git push origin demo/log-retention-exception

destroy: require-backend ## Destroy the demo stack (asks for confirmation)
	$(TF) destroy

clean: ## Remove local Terraform caches, plan files and .netrc (never state)
	rm -rf infra/.terraform bootstrap/.terraform infra/tfplan $(PLAN_JSON) "$(NETRC)"
