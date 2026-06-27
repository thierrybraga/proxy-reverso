#!/usr/bin/env bash
###############################################################################
# test-local.sh — checagens rápidas do ambiente
###############################################################################
set -uo pipefail
cd "$(dirname "$0")/.."

echo "== 1) Validando sintaxe do nginx =="
docker compose exec -T nginx nginx -t || echo "  (suba o nginx antes: docker compose up -d)"

echo "== 2) Healthcheck HTTP (porta 80) =="
curl -fsS http://localhost/healthz && echo "  -> OK" || echo "  -> FALHOU"

echo "== 3) HTTPS local (self-signed, -k ignora a CA) =="
curl -ksS https://localhost/healthz && echo "  -> OK" || echo "  -> FALHOU"

echo "== 4) Uso de CPU/memória dos containers =="
docker stats --no-stream --format \
  "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" \
  | grep -E "NAME|lab-" || true

echo "== 5) Data/hora dentro do container nginx =="
docker compose exec -T nginx date
