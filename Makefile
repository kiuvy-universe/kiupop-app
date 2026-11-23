# KiuPop — developer commands. Run `make help`.
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

ENV_FILE := $(if $(wildcard .env),.env,.env.example)
-include $(ENV_FILE)
WEB_PORT     ?= 3000
API_BASE_URL ?= http://localhost:8080
AUTH_EMULATOR ?= localhost:$(or $(AUTH_EMULATOR_HOST_PORT),9199)
WEB_DEFINES  := --dart-define=API_BASE_URL=$(API_BASE_URL) --dart-define=AUTH_EMULATOR_HOST=$(AUTH_EMULATOR) \
                --dart-define=FIREBASE_PROJECT_ID=$(or $(FIREBASE_PROJECT_ID),demo-kiupop) \
                --dart-define=FACEBOOK_AUTH_ENABLED=$(or $(FACEBOOK_AUTH_ENABLED),false)
COMPOSE      := docker compose --env-file $(ENV_FILE) -f infra/compose.yaml
DEV_DB_URL   := postgres://$(or $(POSTGRES_USER),kiupop):$(or $(POSTGRES_PASSWORD),kiupop_local_only)@127.0.0.1:$(or $(POSTGRES_HOST_PORT),5433)/$(or $(POSTGRES_DB),kiupop)?sslmode=disable
TEST_DB_URL  := postgres://$(or $(POSTGRES_USER),kiupop):$(or $(POSTGRES_PASSWORD),kiupop_local_only)@127.0.0.1:$(or $(POSTGRES_HOST_PORT),5433)/kiupop_test?sslmode=disable

.PHONY: help setup up down restart logs ps web android dev api-host test test-go test-web test-integration lint fmt smoke ai-smoke build ci reset-db

help: ## Show this help
	@echo "KiuPop — comandos de desarrollo"; echo
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo; echo "Flujo típico: make setup && make dev"

setup: ## Check tools, create .env (never overwrites), fetch deps, build images
	@scripts/setup.sh

up: ## Start PostgreSQL + API and wait until healthy
	@$(COMPOSE) up -d --build --wait
	@echo "API:        http://localhost:$(or $(API_HOST_PORT),8080)/healthz"
	@echo "PostgreSQL: 127.0.0.1:$(or $(POSTGRES_HOST_PORT),5433) (db $(or $(POSTGRES_DB),kiupop))"
	@echo "Auth (emulador): http://localhost:$(or $(AUTH_EMULATOR_HOST_PORT),9199)"

down: ## Stop KiuPop services only (keeps the database volume)
	@$(COMPOSE) down

restart: ## Restart KiuPop services (keeps data)
	@$(COMPOSE) restart && $(COMPOSE) up -d --wait

logs: ## Follow API and PostgreSQL logs
	@$(COMPOSE) logs -f --tail=100

ps: ## Show KiuPop containers
	@$(COMPOSE) ps

web: ## Run Flutter Web in Chrome with hot reload (port 3000)
	@cd apps/web && flutter run -d chrome --web-port=$(WEB_PORT) $(WEB_DEFINES)

android: ## Run the native Android app on the USB phone (debug, hot reload; the phone reaches the local stack through adb reverse)
	@serial=$$(adb get-serialno 2>/dev/null); [ -n "$$serial" ] && [ "$$serial" != "unknown" ] || { echo "No hay un teléfono Android autorizado (adb devices)."; exit 1; }; \
	 for p in $(WEB_PORT) $(or $(API_HOST_PORT),8080) $(or $(AUTH_EMULATOR_HOST_PORT),9199); do adb -s $$serial reverse tcp:$$p tcp:$$p >/dev/null; done; \
	 cd apps/web && flutter run -d $$serial $(WEB_DEFINES) --dart-define=PUBLIC_WEB_BASE=http://localhost:$(WEB_PORT)

dev: ## up + web. Ctrl+C stops Flutter only; data is kept (make down to stop services)
	@scripts/dev.sh

api-host: ## Run the Go API on the host against Compose PostgreSQL (no Docker rebuild)
	@cd backend && APP_ENV=local MOCK_MODE=true API_PORT=$(or $(API_PORT),8080) DATABASE_URL='$(DEV_DB_URL)' UPLOAD_DIR=../.data/uploads \
		AUTH_PROVIDER=emulator FIREBASE_AUTH_EMULATOR_HOST=$(AUTH_EMULATOR) go run ./cmd/server

test: test-go test-web ## Run Go and Flutter tests

test-go: ## Go unit + contract tests
	@cd backend && go test -race ./...

test-web: ## Flutter widget + contract tests
	@cd apps/web && flutter test

test-integration: ## Go tests against a separate kiupop_test DB in the Compose PostgreSQL (make up first)
	@$(COMPOSE) exec -T postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -tAc "SELECT 1 FROM pg_database WHERE datname='"'"'kiupop_test'"'"'" | grep -q 1 || createdb -U "$$POSTGRES_USER" kiupop_test'
	@cd backend && KIUPOP_TEST_DATABASE_URL='$(TEST_DB_URL)' go test -count=1 -run Postgres -v ./... | grep -E '^(=== RUN|--- |ok|FAIL|PASS)'

lint: ## gofmt, go vet, flutter analyze, compose config, secret scan
	@scripts/lint.sh

fmt: ## Format Go and Dart code
	@cd backend && gofmt -w .
	@cd apps/web && dart format lib test

smoke: ## Verify running services: health, readiness, real PostgreSQL read, CORS
	@scripts/smoke.sh

ai-smoke: ## Prove a REAL KiuPop AI call (needs AI_ENABLED=true + ANTHROPIC_API_KEY in .env, then make up)
	@scripts/ai-smoke.sh

build: ## Build API image and Flutter Web release bundle
	@$(COMPOSE) build api
	@cd apps/web && flutter build web --release $(WEB_DEFINES)

ci: lint test build ## Everything CI runs, locally

reset-db: ## DESTRUCTIVE (local only): delete the KiuPop database volume, then start fresh
	@read -r -p "Esto borra el volumen local kiupop_pgdata. Escribe 'borrar' para continuar: " ans; \
	 [ "$$ans" = "borrar" ] || { echo "Cancelado."; exit 1; }
	@$(COMPOSE) down -v && $(COMPOSE) up -d --build --wait
