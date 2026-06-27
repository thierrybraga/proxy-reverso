#!/usr/bin/env bash
###############################################################################
# issue-cert-http.sh — emite Let's Encrypt via HTTP-01 (webroot)
#
# Use SOMENTE se a porta 80 do seu host estiver acessível pela internet
# (port forward no roteador apontando 80 -> WSL). NÃO emite wildcard.
# Para lab atrás de NAT, prefira o DNS-01 (issue-cert-godaddy.sh).
#
# Pré-requisitos: nginx no ar (docker compose up -d) e DNS do subdomínio
# apontando para o seu IP público.
#
# Uso:  ./scripts/issue-cert-http.sh app1.meudominio.com.br
###############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "Arquivo .env não encontrado."; exit 1; }
set -a; . ./.env; set +a

HOST="${1:?informe o host. Ex.: ./scripts/issue-cert-http.sh app1.meudominio.com.br}"
: "${ACME_EMAIL:?defina ACME_EMAIL no .env}"

mkdir -p "certs/$HOST" data/acme data/acme-webroot

echo ">> Registrando conta ACME..."
docker compose --profile certs run --rm acme \
  --register-account --accountemail "$ACME_EMAIL" --server letsencrypt || true

echo ">> Emitindo certificado para $HOST (HTTP-01 webroot)..."
docker compose --profile certs run --rm acme \
  --issue --webroot /var/www/acme \
  -d "$HOST" \
  --keylength ec-256 \
  --server letsencrypt

echo ">> Instalando certificado em certs/$HOST/ ..."
docker compose --profile certs run --rm acme \
  --install-cert -d "$HOST" --ecc \
  --key-file       "/certs/$HOST/privkey.pem" \
  --fullchain-file "/certs/$HOST/fullchain.pem"

echo ">> Recarregando o nginx..."
docker compose exec nginx nginx -t && docker compose exec nginx nginx -s reload

echo ">> Pronto. Aponte o server_name para certs/$HOST/{fullchain,privkey}.pem"
