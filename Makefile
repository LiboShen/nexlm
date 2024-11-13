APP_NAME = nexlm
BUILD ?= `git rev-parse --short HEAD`

.PHONY: help
help:
	@echo "$(APP_NAME):$(BUILD)"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'


.PHONY: test
test: ## Run tests
	mix test --exclude integration:true

.PHONY: test.integration

test.integration: ## Run integration tests
	source .env.local && mix test --only integration:true
