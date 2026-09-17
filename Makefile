COMPOSE := docker compose

.PHONY: help up down build logs ps migrate revision test test-backend test-frontend lint fmt clean shell-backend shell-db deploy-backend destroy-backend logs-backend cert domain deploy-frontend destroy-frontend github-role

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up: ## Start the whole stack (detached)
	$(COMPOSE) up -d --build

down: ## Stop the stack
	$(COMPOSE) down

clean: ## Stop the stack and wipe the database volume
	$(COMPOSE) down -v

build: ## Rebuild images
	$(COMPOSE) build

logs: ## Tail all logs
	$(COMPOSE) logs -f

ps: ## Show service status
	$(COMPOSE) ps

migrate: ## Apply migrations
	$(COMPOSE) exec backend alembic upgrade head

revision: ## Autogenerate a migration: make revision m="add x"
	$(COMPOSE) exec backend alembic revision --autogenerate -m "$(m)"

test: test-backend test-frontend ## Run all tests

test-backend: ## Run backend tests
	$(COMPOSE) exec backend pytest

test-frontend: ## Run frontend tests
	$(COMPOSE) exec frontend pnpm test

lint: ## Lint both sides
	$(COMPOSE) exec backend ruff check .
	$(COMPOSE) exec frontend pnpm lint

fmt: ## Format both sides
	$(COMPOSE) exec backend ruff format .
	$(COMPOSE) exec frontend pnpm format

shell-backend: ## Shell into the backend container
	$(COMPOSE) exec backend bash

shell-db: ## psql into the database
	$(COMPOSE) exec db psql -U $${POSTGRES_USER:-peach} -d $${POSTGRES_DB:-peach}

deploy-backend: ## Build, push and roll the backend on ECS Fargate (ALB + RDS)
	./scripts/deploy-backend.sh

destroy-backend: ## Delete the backend stack, database included
	./scripts/destroy-backend.sh

logs-backend: ## Tail the deployed backend's CloudWatch logs
	aws logs tail /ecs/$${PROJECT_NAME:-peach}-backend --follow --since 10m

cert: ## Request + DNS-validate an HTTPS certificate: make cert DOMAIN=api.example.com
	./scripts/domain-backend.sh cert

domain: ## Put a custom domain with HTTPS in front: make domain DOMAIN=api.example.com
	./scripts/domain-backend.sh domain

deploy-frontend: ## Build the static export and ship it to S3 + CloudFront
	./scripts/deploy-frontend.sh

destroy-frontend: ## Delete the frontend stack (bucket + distribution)
	./scripts/destroy-frontend.sh

github-role: ## Create the IAM role GitHub Actions assumes to deploy (OIDC, no keys)
	./scripts/github-role.sh
