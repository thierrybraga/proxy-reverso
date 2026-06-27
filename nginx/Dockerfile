# ─────────────────────────────────────────────────────────────────────────
# NGINX para o lab — base estável Alpine (leve e segura)
# Linha "stable" atual = 1.30.x. Para fixar versão troque por: nginx:1.30-alpine
# ─────────────────────────────────────────────────────────────────────────
FROM nginx:stable-alpine

LABEL org.opencontainers.image.title="proxy-reverso-nginx" \
      org.opencontainers.image.description="Reverse proxy NGINX para lab pessoal (WSL2)" \
      org.opencontainers.image.source="https://desktop/proxy-reverso"

# tzdata -> data/hora correta;  curl -> usado pelo HEALTHCHECK;  ca-certificates -> TLS
RUN apk add --no-cache tzdata curl ca-certificates \
    && rm -rf /var/cache/apk/*

# Fuso horário padrão (sobrescrito por TZ no docker-compose)
ENV TZ=America/Sao_Paulo

# Copia as configs para dentro da imagem (fallback caso não sejam montadas).
# No docker-compose elas são montadas como volume :ro para edição ao vivo.
COPY conf/nginx.conf      /etc/nginx/nginx.conf
COPY conf.d/              /etc/nginx/conf.d/
COPY snippets/            /etc/nginx/snippets/
COPY html/                /usr/share/nginx/html/

# Diretórios de runtime (logs, webroot do ACME, pasta de certs)
RUN mkdir -p /var/log/nginx /var/www/acme /etc/nginx/certs

# Verificação de saúde (também definida no compose)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD curl -fsS http://127.0.0.1/healthz || exit 1

EXPOSE 80 443

STOPSIGNAL SIGQUIT
CMD ["nginx", "-g", "daemon off;"]
