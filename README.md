# proxy-reverso — NGINX reverse proxy para lab pessoal (Windows 11 + WSL2)

Reverse proxy NGINX em Docker, pensado para servir **várias aplicações** do seu
lab (em containers **ou** rodando direto no host/WSL), com:

- Limites de **CPU e memória** e monitoramento de uso
- **Fuso horário / data e hora** configuráveis
- **TLS** com **Let's Encrypt** (GoDaddy via DNS-01) e certificado self-signed para testes
- **Acesso externo** por **Cloudflare Tunnel** e **ngrok** (sem abrir o roteador) ou por **port forward**
- **Teste local** via `https://localhost`
- **Segurança** endurecida: TLS moderno, HSTS, headers, rate limiting, IP real da Cloudflare, container sem privilégios
- Tudo **documentado** e com atalhos via `make`

---

## 1. Visão geral da arquitetura

```
                         Internet
                            │
        ┌───────────────────┼────────────────────┐
        │                   │                     │
   Cloudflare Tunnel      ngrok            Port forward (roteador)
   (cloudflared)        (ngrok)              80/443 → WSL
        │                   │                     │
        └───────────────────┴─────────┬───────────┘
                                       ▼
                          ┌─────────────────────────┐
                          │   NGINX (este projeto)   │  ← TLS, headers, rate limit
                          │   container "lab-nginx"  │
                          └───────────┬──────────────┘
                          proxy_pass  │
              ┌───────────────────────┼───────────────────────┐
              ▼                       ▼                        ▼
     app em container          app no host/WSL          arquivos estáticos
   (nome:porta na rede      (host.docker.internal:porta)   (html/)
        "labnet")
```

O NGINX é o único ponto que escuta nas portas 80/443. Cada aplicação ganha um
arquivo em `nginx/conf.d/` apontando para o destino certo.

---

## 2. Estrutura de pastas

```
proxy-reverso/
├── docker-compose.yml          # serviços: nginx, acme, cloudflared, ngrok, cadvisor
├── .env.example                # modelo de variáveis (copie para .env)
├── Makefile                    # atalhos: make up / reload / cert-godaddy ...
├── nginx/
│   ├── Dockerfile              # imagem nginx:stable-alpine + tzdata/curl
│   ├── conf/nginx.conf         # config principal (http): logs, gzip, rate limit
│   ├── conf.d/
│   │   ├── 00-default.conf     # catch-all: ACME, healthz, redirect, rejeita SNI
│   │   ├── 10-local.conf       # site de teste https://localhost (ativo)
│   │   ├── app-container.conf.example   # TEMPLATE p/ app em container
│   │   └── app-host-wsl.conf.example    # TEMPLATE p/ app no host/WSL
│   ├── snippets/
│   │   ├── ssl.conf                  # TLS endurecido
│   │   ├── security-headers.conf     # HSTS, X-Frame-Options, CSP...
│   │   ├── proxy.conf                # headers de proxy + WebSocket
│   │   ├── cloudflare-realip.conf    # IP real do visitante
│   │   └── acme-challenge.conf       # desafio HTTP-01
│   └── html/                   # página de boas-vindas e 50x
├── scripts/
│   ├── make-selfsigned.sh      # cert local de teste
│   ├── issue-cert-godaddy.sh   # Let's Encrypt DNS-01 (GoDaddy) — recomendado
│   ├── issue-cert-http.sh      # Let's Encrypt HTTP-01 (precisa porta 80 pública)
│   ├── generate-dhparam.sh     # dhparam opcional
│   ├── wsl-portproxy.ps1       # PowerShell: expõe portas do WSL na rede
│   └── test-local.sh           # checagens rápidas
├── cloudflared/config.yml.example
├── ngrok/ngrok.yml.example
├── certs/                      # certificados (NÃO versionar) — criado no uso
├── data/                       # estado do acme.sh e webroot (NÃO versionar)
└── logs/nginx/                 # logs de acesso/erro
```

> Apenas arquivos `*.conf` em `conf.d/` são carregados. Os `*.conf.example` são
> templates — copie, renomeie para `.conf` e ajuste.

---

## 3. Pré-requisitos (Windows 11 + WSL2)

1. **WSL2** com uma distro (Ubuntu recomendado):
   ```powershell
   wsl --install -d Ubuntu
   wsl --set-default-version 2
   ```
2. **Docker** — duas opções:
   - **Docker Desktop** com integração WSL2 ativada (mais simples), ou
   - **Docker Engine** instalado dentro do WSL (`curl -fsSL https://get.docker.com | sh`).
3. Rode **todos os comandos abaixo de dentro do WSL**, na pasta do projeto.

Confirme:
```bash
docker --version
docker compose version
```

---

## 4. Início rápido (5 passos)

```bash
# 1) Crie o .env e o certificado local de teste
make init                # = cp .env.example .env + gera certs/local/

# 2) Edite o .env (domínio, TZ, limites, tokens) — veja a seção 5
nano .env

# 3) Suba o nginx
make up                  # docker compose up -d --build

# 4) Teste local
curl -k https://localhost/healthz      # -> ok
#   ou abra https://localhost no navegador (aviso de cert é esperado no self-signed)

# 5) Veja uso de CPU/memória
make stats
```

Sem `make`? Os equivalentes:
```bash
cp .env.example .env
bash scripts/make-selfsigned.sh
docker compose up -d --build
```

---

## 5. Configuração (.env)

| Variável | Para que serve |
|---|---|
| `TZ` | Fuso horário (data/hora) do container. Ex.: `America/Sao_Paulo` |
| `DOMAIN` / `ACME_EMAIL` | Domínio na GoDaddy e e-mail do Let's Encrypt |
| `HTTP_PORT` / `HTTPS_PORT` | Portas publicadas no host (padrão 80/443) |
| `NGINX_CPUS` | Limite de CPU (ex.: `0.5`, `1.0`, `2.0` núcleos) |
| `NGINX_MEM_LIMIT` / `NGINX_MEM_RESERVATION` | Teto e reserva de memória |
| `GD_KEY` / `GD_SECRET` | API da GoDaddy para o DNS-01 |
| `CLOUDFLARE_TUNNEL_TOKEN` | Token do Cloudflare Tunnel |
| `NGROK_AUTHTOKEN` | Token do ngrok |

---

## 6. CPU, memória e monitoramento

Os limites ficam no `.env` e são aplicados no `docker-compose.yml`:

```yaml
cpus: ${NGINX_CPUS:-1.0}             # nº de núcleos
mem_limit: ${NGINX_MEM_LIMIT:-256m}  # teto rígido
mem_reservation: ${NGINX_MEM_RESERVATION:-128m}
pids_limit: 200
```

Essas chaves de nível superior são respeitadas diretamente por
`docker compose up` (Compose V2). O bloco `deploy.resources` equivalente também
está presente para quem usa Swarm ou `docker compose --compatibility up`.

**Ver o consumo:**
```bash
docker stats                       # tempo real
make stats                         # snapshot único
```

**Dashboard visual (cAdvisor):**
```bash
make monitor                       # docker compose --profile monitoring up -d
# abra http://localhost:8080  -> gráficos de CPU, memória, rede por container
```

---

## 7. Data e hora

Configurado de duas formas combinadas:

1. Variável `TZ` no `.env` (passada ao container e usada pelo `tzdata`).
2. Montagem de `/etc/localtime:/etc/localtime:ro`, que herda o relógio do host WSL.

Conferir:
```bash
docker compose exec nginx date
```

Para mudar o fuso, edite `TZ` no `.env` e rode `docker compose up -d` de novo.

---

## 8. Certificados TLS

### 8.1 Teste local (self-signed) — já incluso
`make init` (ou `scripts/make-selfsigned.sh`) gera `certs/local/`. É o que faz
`https://localhost` funcionar. O navegador mostra aviso de certificado — normal.

### 8.2 Let's Encrypt via GoDaddy (DNS-01) — recomendado para o lab
Funciona **atrás de NAT** (não precisa abrir a porta 80) e emite **wildcard**.

1. Gere a API key em https://developer.godaddy.com/keys (ambiente **Production**)
   e preencha `GD_KEY` / `GD_SECRET` no `.env`.
2. Emita:
   ```bash
   make cert-godaddy          # = scripts/issue-cert-godaddy.sh
   ```
   Isso cria `certs/<DOMAIN>/fullchain.pem` e `privkey.pem` (cobre `*.DOMAIN`).
3. Nos virtual hosts, aponte para esses arquivos (os templates já vêm assim).
4. **Renovação automática:** mantenha o serviço `acme` rodando:
   ```bash
   docker compose --profile certs up -d acme
   ```
   Ele renova sozinho. Após renovar, recarregue o nginx (`make reload`) — você
   pode automatizar isso com um agendamento diário simples.

### 8.3 Let's Encrypt via HTTP-01 (alternativa)
Use só se a **porta 80 estiver pública** (port forward). Não faz wildcard.
```bash
bash scripts/issue-cert-http.sh app1.meudominio.com.br
```

> **DNS na GoDaddy vs. Cloudflare:** o DNS-01 acima usa a API da GoDaddy e **não
> exige** mover o DNS. Já o **Cloudflare Tunnel** (seção 9.1) exige adicionar o
> domínio à Cloudflare (trocar os nameservers na GoDaddy — é grátis). São
> caminhos independentes; você pode usar os dois.

---

## 9. Acesso externo

### 9.1 Cloudflare Tunnel (recomendado — túnel permanente, sem abrir o roteador)
1. Adicione o domínio à Cloudflare (mude os nameservers na GoDaddy para os da
   Cloudflare).
2. Em https://one.dash.cloudflare.com → **Networks → Tunnels → Create tunnel**,
   copie o **token** para `CLOUDFLARE_TUNNEL_TOKEN` no `.env`.
3. Em **Public Hostnames**, aponte cada subdomínio para **HTTPS → `nginx:443`**
   (marque *No TLS Verify*).
4. Suba:
   ```bash
   make cloudflare        # docker compose --profile cloudflare up -d
   ```
Detalhes e o modo por arquivo de config em `cloudflared/config.yml.example`.

### 9.2 ngrok (rápido para demos / URL temporária)
1. Coloque o token em `NGROK_AUTHTOKEN` no `.env`.
2. Suba:
   ```bash
   make ngrok             # docker compose --profile ngrok up -d
   ```
3. Veja a URL pública nos logs: `docker compose logs -f ngrok`
   (ou no painel http://localhost:4040 se publicar a porta).

Config avançada (vários túneis, domínio fixo, basic-auth) em `ngrok/ngrok.yml.example`.

### 9.3 Port forward direto (controle total)
1. No Windows (PowerShell **como Admin**), exponha as portas do WSL na LAN:
   ```powershell
   .\scripts\wsl-portproxy.ps1
   ```
2. No roteador, encaminhe `80` e `443` para o **IP do Windows**.
3. Aponte o DNS (GoDaddy) do subdomínio para seu **IP público**.

> O IP do WSL muda ao reiniciar — rode o script de novo após reboot, ou prefira
> Cloudflare Tunnel/ngrok, que não dependem disso.

---

## 10. Adicionando uma aplicação

### App em container Docker
1. Garanta que o container alvo está na rede `labnet`.
2. Copie o template:
   ```bash
   cp nginx/conf.d/app-container.conf.example nginx/conf.d/portainer.conf
   ```
3. Ajuste `server_name`, o `upstream` (`nome-do-container:porta`) e o caminho do certificado.
4. Aplique:
   ```bash
   make reload            # nginx -t && nginx -s reload
   ```

### App no host / WSL
1. Copie `app-host-wsl.conf.example` para `minhaapp.conf`.
2. Ajuste a porta em `host.docker.internal:PORTA`.
3. `make reload`.

---

## 11. Segurança aplicada

- **TLS moderno:** apenas TLS 1.2/1.3, cifras fortes, OCSP stapling (`snippets/ssl.conf`).
- **Headers:** HSTS, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`,
  `Permissions-Policy` e CSP (comentado, pronto para ativar) — `snippets/security-headers.conf`.
- **Rate limiting / conn limiting** por IP (`nginx.conf` + uso nos vhosts) — mitiga abuso/DoS leve.
- **`server_tokens off`** e ocultação de headers da origem.
- **IP real da Cloudflare** para logs e rate limit corretos (`snippets/cloudflare-realip.conf`).
- **Catch-all 444** para hosts/SNI desconhecidos (não responde a scanners).
- **Container endurecido:** `no-new-privileges`, `cap_drop: ALL` (só capacidades mínimas),
  `pids_limit`, configs montadas como **read-only**.
- **Segredos fora do Git:** `.env`, `certs/` e `data/` no `.gitignore`.

Recomendações extras: restrinja o painel de apps sensíveis por IP, ative a CSP
aos poucos, e considere o **Cloudflare Access** (Zero Trust) para apps privadas.

---

## 12. Comandos úteis

```bash
make help            # lista os atalhos
make up              # sobe o nginx
make reload          # valida + recarrega config
make logs            # logs do nginx
make stats           # CPU/memória
make test            # checagens rápidas
docker compose ps    # status dos serviços
docker compose down  # derruba
```

---

## 13. Troubleshooting

| Sintoma | Causa provável / solução |
|---|---|
| `nginx -t` falha por cert ausente | Rode `make init` (gera `certs/local/`) antes do `up`. |
| `https://localhost` dá erro de cert | Esperado no self-signed. Use `-k` no curl ou aceite no navegador. |
| Porta 80/443 "já em uso" | Outro serviço no Windows ocupa a porta. Mude `HTTP_PORT/HTTPS_PORT` no `.env`. |
| App no host não responde | Verifique a porta e se o serviço escuta em `0.0.0.0` (não só `127.0.0.1`). |
| LAN não acessa o WSL | Rode `scripts/wsl-portproxy.ps1` (Admin); o IP do WSL muda após reboot. |
| Cert GoDaddy falha (DNS-01) | Confira `GD_KEY/GD_SECRET` (Production) e propagação do TXT. |
| Cloudflare Tunnel não conecta | Verifique o token e se o domínio está na Cloudflare. |
| Mudou config e não aplicou | `make reload` (configs são montadas; basta recarregar). |

---

## 14. Notas

- Imagem base: `nginx:stable-alpine` (linha estável atual 1.30.x). Para fixar a
  versão, troque no `Dockerfile` por algo como `nginx:1.30-alpine`.
- Os túneis (`ngrok`, `cloudflared`) e o monitor (`cadvisor`) usam **profiles** do
  Compose: só sobem quando você pede (`--profile ...`), mantendo o lab leve.
