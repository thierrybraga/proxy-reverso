# Makefile — atalhos para o proxy-reverso (rode no WSL)
# Uso:  make <alvo>     |     make help

.DEFAULT_GOAL := help
SHELL := /bin/bash

help: ## Lista os comandos disponíveis
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n",$$1,$$2}'

init: ## Cria .env e o certificado local (primeiro uso)
	@test -f .env || cp .env.example .env
	@bash scripts/make-selfsigned.sh
	@echo ">> Edite o .env e rode: make up"

up: ## Sobe só o nginx
	docker compose up -d --build

down: ## Derruba tudo
	docker compose --profile certs --profile cloudflare --profile ngrok --profile monitoring down

reload: ## Valida e recarrega a config do nginx (sem downtime)
	docker compose exec nginx nginx -t && docker compose exec nginx nginx -s reload

logs: ## Acompanha os logs do nginx
	docker compose logs -f nginx

cert-godaddy: ## Emite certificado Let's Encrypt via DNS-01 (GoDaddy)
	bash scripts/issue-cert-godaddy.sh

cloudflare: ## Sobe o Cloudflare Tunnel
	docker compose --profile cloudflare up -d cloudflared

ngrok: ## Sobe o túnel ngrok
	docker compose --profile ngrok up -d ngrok

monitor: ## Sobe o cAdvisor (http://localhost:8080)
	docker compose --profile monitoring up -d cadvisor

stats: ## Mostra CPU/memória dos containers
	docker stats --no-stream

test: ## Roda as checagens locais
	bash scripts/test-local.sh
