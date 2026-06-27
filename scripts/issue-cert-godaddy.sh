#!/usr/bin/env bash
###############################################################################
# issue-cert-godaddy.sh — emite certificado Let's Encrypt via DNS-01 (GoDaddy)
#
# Vantagem do DNS-01: funciona ATRÁS DE NAT (não precisa abrir a porta 80) e
# permite certificado WILDCARD (*.seudominio).
#
# Pré-requisitos no .env:
#   DOMAIN, ACME_EMAIL, GD_KEY, GD_SECRET
#   (gere a chave/secret em https://developer.godaddy.com/keys — Production)
#
# Uso:  ./scripts/issue-cert-godaddy.sh
###############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { echo "Arquivo .env não encontrado. Copie de .env.example."; exit 1; }
set -a; . ./.env; set +a

: "${DOMAIN:?defina DOMAIN no .env}"
: "${ACME_EMAIL:?defina ACME_EMAIL no .env}"
: "${GD_KEY:?defina GD_KEY no .env}"
: "${GD_SECRET:?defina GD_SECRET no .env}"

mkdir -p "certs/$DOMAIN" data/acme

echo ">> Registrando conta ACME (Let's Encrypt)..."
docker compose --profile certs run --rm acme \
  --register-account --accountemail "$ACME_EMAIL" --server letsencrypt || true

echo ">> Emitindo certificado para $DOMAIN e *.$DOMAIN (DNS-01 GoDaddy)..."
docker compose --profile certs run --rm acme \
  --issue --dns dns_gd \
  -d "$DOMAIN" -d "*.$DOMAIN" \
  --keylength ec-256 \
  --server letsencrypt

echo ">> Instalando certificado em certs/$DOMAIN/ ..."
docker compose --profile certs run --rm acme \
  --install-cert -d "$DOMAIN" --ecc \
  --key-file       "/certs/$DOMAIN/privkey.pem" \
  --fullchain-file "/certs/$DOMAIN/fullchain.pem"

echo ">> Recarregando o nginx..."
docker compose exec nginx nginx -t && docker compose exec nginx nginx -s reload || \
  echo "   (nginx não está rodando ainda — suba com 'docker compose up -d')"

echo ">> Certificado pronto em certs/$DOMAIN/"
echo "   Renovação automática: mantenha o serviço 'acme' rodando"
echo "   ->  docker compose --profile certs up -d acme"
