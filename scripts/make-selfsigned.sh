#!/usr/bin/env bash
###############################################################################
# make-selfsigned.sh — gera um certificado self-signed para testes locais
# Saída: certs/local/{fullchain.pem,privkey.pem}  (usado por localhost e default)
#
# Uso:  ./scripts/make-selfsigned.sh
###############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="certs/local"
DAYS=825
mkdir -p "$DEST"

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl não encontrado. No WSL/Ubuntu: sudo apt-get install -y openssl" >&2
  exit 1
fi

echo ">> Gerando certificado self-signed em $DEST (válido por $DAYS dias)..."
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$DEST/privkey.pem" \
  -out    "$DEST/fullchain.pem" \
  -days "$DAYS" \
  -subj "/C=BR/ST=Lab/L=Local/O=proxy-reverso/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,DNS:*.localhost,IP:127.0.0.1"

chmod 600 "$DEST/privkey.pem"
echo ">> Pronto:"
echo "   $DEST/fullchain.pem"
echo "   $DEST/privkey.pem"
echo ">> Agora rode:  docker compose up -d   e acesse  https://localhost"
