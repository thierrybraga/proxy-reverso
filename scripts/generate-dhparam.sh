#!/usr/bin/env bash
###############################################################################
# generate-dhparam.sh — gera parâmetros Diffie-Hellman (opcional)
# Depois, descomente a linha ssl_dhparam em nginx/snippets/ssl.conf
#
# Uso:  ./scripts/generate-dhparam.sh        # 2048 bits (rápido)
#       ./scripts/generate-dhparam.sh 4096    # mais forte, demora alguns min
###############################################################################
set -euo pipefail
cd "$(dirname "$0")/.."

BITS="${1:-2048}"
mkdir -p certs
echo ">> Gerando dhparam de $BITS bits (isto pode demorar)..."
openssl dhparam -out certs/dhparam.pem "$BITS"
echo ">> Pronto: certs/dhparam.pem"
echo ">> Agora descomente 'ssl_dhparam' em nginx/snippets/ssl.conf e recarregue o nginx."
