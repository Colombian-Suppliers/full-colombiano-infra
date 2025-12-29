.PHONY: help init validate plan apply destroy fmt lint security-scan docs pre-commit-install bootstrap-vps clean

# Default environment
ENV ?= dev

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)Colombian Supply - Infrastructure Management$(NC)"
	@echo ""
	@echo "$(GREEN)Available commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Usage:$(NC)"
	@echo "  make init ENV=dev"
	@echo "  make plan ENV=stg"
	@echo "  make apply ENV=prod"

init: ## Initialize Terraform for specified environment
	@echo "$(BLUE)Initializing Terraform for $(ENV) environment...$(NC)"
	cd environments/$(ENV) && terraform init

validate: ## Validate Terraform configuration
	@echo "$(BLUE)Validating Terraform configuration for $(ENV)...$(NC)"
	cd environments/$(ENV) && terraform validate

plan: ## Show Terraform plan
	@echo "$(BLUE)Planning changes for $(ENV)...$(NC)"
	cd environments/$(ENV) && terraform plan

apply: ## Apply Terraform changes
	@echo "$(RED)Applying changes to $(ENV) environment...$(NC)"
	@echo "$(RED)Press Ctrl+C to cancel or Enter to continue$(NC)"
	@read -r
	cd environments/$(ENV) && terraform apply

destroy: ## Destroy infrastructure
	@echo "$(RED)⚠️  WARNING: This will DESTROY all infrastructure in $(ENV)!$(NC)"
	@echo "$(RED)Type 'yes' to continue:$(NC)"
	@read -r confirm && [ "$$confirm" = "yes" ] || (echo "Cancelled" && exit 1)
	cd environments/$(ENV) && terraform destroy

fmt: ## Format all Terraform files
	@echo "$(BLUE)Formatting Terraform files...$(NC)"
	terraform fmt -recursive .

fmt-check: ## Check if Terraform files are formatted
	@echo "$(BLUE)Checking Terraform formatting...$(NC)"
	terraform fmt -check -recursive .

lint: ## Run tflint on all modules
	@echo "$(BLUE)Running tflint...$(NC)"
	@for dir in modules/*/ environments/*/; do \
		echo "Linting $$dir"; \
		cd $$dir && tflint --init && tflint && cd - > /dev/null; \
	done

security-scan: ## Run security scan with tfsec
	@echo "$(BLUE)Running security scan...$(NC)"
	tfsec . --minimum-severity MEDIUM

security-scan-checkov: ## Run security scan with checkov
	@echo "$(BLUE)Running checkov security scan...$(NC)"
	checkov -d . --skip-check CKV_TF_1

docs: ## Generate documentation with terraform-docs
	@echo "$(BLUE)Generating module documentation...$(NC)"
	@for dir in modules/*/; do \
		echo "Documenting $$dir"; \
		terraform-docs markdown table --output-file README.md --output-mode inject $$dir; \
	done

pre-commit-install: ## Install pre-commit hooks
	@echo "$(BLUE)Installing pre-commit hooks...$(NC)"
	pre-commit install
	pre-commit install --hook-type commit-msg

pre-commit-run: ## Run pre-commit on all files
	@echo "$(BLUE)Running pre-commit checks...$(NC)"
	pre-commit run --all-files

bootstrap-vps: ## Bootstrap k3s on VPS (requires ENV variable)
	@echo "$(BLUE)Bootstrapping k3s on VPS for $(ENV)...$(NC)"
	@if [ ! -f "environments/$(ENV)/terraform.tfvars" ]; then \
		echo "$(RED)Error: terraform.tfvars not found in environments/$(ENV)$(NC)"; \
		exit 1; \
	fi
	cd environments/$(ENV) && terraform init && terraform apply -auto-approve

kubeconfig: ## Export kubeconfig path for environment
	@cd environments/$(ENV) && terraform output -raw kubeconfig_path 2>/dev/null || echo ".kube/$(ENV)-config.yaml"

switch-context: ## Switch kubectl context to environment
	@echo "$(BLUE)Switching to $(ENV) context...$(NC)"
	export KUBECONFIG=$$(cd environments/$(ENV) && terraform output -raw kubeconfig_path 2>/dev/null || echo "../../.kube/$(ENV)-config.yaml") && \
	kubectl config use-context $$(kubectl config get-contexts -o name | grep $(ENV) || echo "default")

verify-cluster: ## Verify cluster is working
	@echo "$(BLUE)Verifying cluster for $(ENV)...$(NC)"
	@KUBECONFIG=$$(cd environments/$(ENV) && terraform output -raw kubeconfig_path 2>/dev/null || echo "../../.kube/$(ENV)-config.yaml") && \
	kubectl get nodes && \
	kubectl get pods -n platform && \
	kubectl get pods -n apps

logs-platform: ## Show platform component logs
	@echo "$(BLUE)Platform component logs for $(ENV)...$(NC)"
	@KUBECONFIG=$$(cd environments/$(ENV) && terraform output -raw kubeconfig_path 2>/dev/null || echo "../../.kube/$(ENV)-config.yaml") && \
	kubectl logs -n platform -l app.kubernetes.io/name=cert-manager --tail=50

clean: ## Clean local artifacts
	@echo "$(BLUE)Cleaning local artifacts...$(NC)"
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.tfstate*" -delete 2>/dev/null || true
	find . -type f -name "crash.log" -delete 2>/dev/null || true
	rm -rf .kube/*.yaml 2>/dev/null || true
	@echo "$(GREEN)Cleaned!$(NC)"

install-tools: ## Install required tools (MacOS)
	@echo "$(BLUE)Installing required tools...$(NC)"
	@command -v brew >/dev/null 2>&1 || (echo "$(RED)Homebrew required$(NC)" && exit 1)
	brew install terraform kubectl helm tflint tfsec pre-commit terraform-docs
	@echo "$(GREEN)Tools installed!$(NC)"

install-tools-linux: ## Install required tools (Linux)
	@echo "$(BLUE)Installing required tools for Linux...$(NC)"
	@echo "Please run the appropriate commands for your distribution"
	@echo "See: https://developer.hashicorp.com/terraform/downloads"

cost-estimate: ## Estimate infrastructure costs (requires infracost)
	@echo "$(BLUE)Estimating costs for $(ENV)...$(NC)"
	@command -v infracost >/dev/null 2>&1 || (echo "$(RED)infracost not installed. Run: brew install infracost$(NC)" && exit 1)
	cd environments/$(ENV) && infracost breakdown --path .

outputs: ## Show Terraform outputs
	@echo "$(BLUE)Outputs for $(ENV):$(NC)"
	@cd environments/$(ENV) && terraform output

graph: ## Generate dependency graph
	@echo "$(BLUE)Generating dependency graph for $(ENV)...$(NC)"
	cd environments/$(ENV) && terraform graph | dot -Tsvg > ../../terraform-graph-$(ENV).svg
	@echo "$(GREEN)Graph saved to terraform-graph-$(ENV).svg$(NC)"

unlock: ## Unlock Terraform state (use carefully!)
	@echo "$(RED)⚠️  This will force unlock the state. Use only if lock is stuck!$(NC)"
	@echo "$(RED)Enter lock ID:$(NC)"
	@read -r lock_id && cd environments/$(ENV) && terraform force-unlock $$lock_id

.DEFAULT_GOAL := help

