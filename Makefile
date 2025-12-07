PYTHON ?= python3.13
VENV ?= .venv

# Extract add-on version from rsync-backup/config.yaml (expects a line like: version: "0.1.0")
VERSION := $(shell sed -n 's/^version: "\(.*\)"/\1/p' rsync-backup/config.yaml)
TAG := v$(VERSION)

.PHONY: help venv dev-install lint format typecheck pre-commit-install addon-build release shellcheck

help: ## Show this help message
	@printf "Home Assistant rsync backup add-on repo\n"
	@printf "Usage: make [target]\n\n"
	@printf "Available targets:\n"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
		sed -E 's/^([a-zA-Z0-9_-]+):.*?## (.*)$$/  \1\t\2/'

venv: ## Create local Python virtualenv for tooling
	$(PYTHON) -m venv $(VENV)
	. $(VENV)/bin/activate && pip install --upgrade pip && pip install -r requirements-dev.txt

dev-install: venv ## Ensure venv exists and dev tools installed

lint: ## Placeholder lint target (extend as needed)
	@echo "No Python sources to lint yet."

format: ## Placeholder format target (extend as needed)
	@echo "No Python sources to format yet."

typecheck: ## Placeholder typecheck target (extend as needed)
	@echo "No Python sources to typecheck yet."

shellcheck: ## Run shellcheck on shell scripts
	. $(VENV)/bin/activate && shellcheck rsync-backup/run.sh

pre-commit-install: ## Install pre-commit hooks
	. $(VENV)/bin/activate && pre-commit install

addon-build: ## Build the rsync-backup add-on image locally for amd64
	cd rsync-backup && docker build --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:latest -t rsync-backup-addon:local .

release: addon-build ## Tag current commit with add-on version and push tag for GitHub Actions
	@if [ -z "$(VERSION)" ]; then \
		echo "ERROR: Could not determine version from rsync-backup/config.yaml"; \
		exit 1; \
	fi
	@if ! git diff --quiet || ! git diff --cached --quiet; then \
		echo "ERROR: Working tree not clean; commit or stash changes before releasing"; \
		exit 1; \
	fi
	@if git rev-parse "$(TAG)" >/dev/null 2>&1; then \
		echo "ERROR: Tag $(TAG) already exists"; \
		exit 1; \
	fi
	@git tag -a "$(TAG)" -m "Release $(TAG)"
	@git push origin "$(TAG)"
