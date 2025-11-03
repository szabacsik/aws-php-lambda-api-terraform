# Simple Makefile for local dev. Run from infra/local/

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: up down restart logs app-logs php-logs ping curl db-cli

up:
	docker compose up -d --build

down:
	docker compose down -v

restart: down up

logs:
	docker compose logs -f --tail=200

# Tail only the PHP application logs (service: api)
app-logs:
	docker compose logs -f --tail=200 api

# Alias for app-logs
php-logs: app-logs

ping:
	curl -sS http://localhost:8000/hello | jq . || true

curl:
	curl -sS http://localhost:8000/ | jq . || true

db-cli:
	docker compose exec -e PGPASSWORD=app_pass db psql -U app_user -d $(shell awk -F': ' '/DB_NAME:/{print $$2}' docker-compose.yml | tr -d '"')
