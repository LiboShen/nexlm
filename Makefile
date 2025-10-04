APP_NAME = nexlm
BUILD ?= `git rev-parse --short HEAD`

.PHONY: help
help:
	@echo "$(APP_NAME):$(BUILD)"
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'


.PHONY: test
test: ## Run tests
	mix test --exclude integration:true --warnings-as-errors --max-failures 3

.PHONY: test.integration
test.integration: ## Run integration tests
	source .env.local && mix test --only integration:true

.PHONY: bump
bump: ## Bump version and create git tag (usage: make bump VERSION=patch|minor|major)
	@if [ -z "$(VERSION)" ]; then \
		echo "Usage: make bump VERSION=patch|minor|major"; \
		exit 1; \
	fi
	@current_version=$$(grep '@version' mix.exs | sed 's/.*"\(.*\)".*/\1/'); \
	echo "Current version: $$current_version"; \
	new_version=$$(echo $$current_version | awk -F. -v type=$(VERSION) '{ \
		if (type == "major") { print ($$1+1) ".0.0" } \
		else if (type == "minor") { print $$1 "." ($$2+1) ".0" } \
		else if (type == "patch") { print $$1 "." $$2 "." ($$3+1) } \
		else { print "Invalid version type" > "/dev/stderr"; exit 1 } \
	}'); \
	echo "New version: $$new_version"; \
	sed -i '' "s/@version \".*\"/@version \"$$new_version\"/" mix.exs; \
	git add mix.exs; \
	git commit -m "release $$new_version"; \
	git tag "v$$new_version"; \
	echo "Created tag v$$new_version"
