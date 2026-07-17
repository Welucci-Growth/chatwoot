# Deploy — Welucci Chatwoot (produção)

Configuração da stack de produção na VPS Hostinger. Espelha o que roda em
`/root/chatwoot` na VPS (`root@srv1779041.hstgr.cloud`). O código-fonte fica em
`/root/chatwoot-src` (este repositório, branch `welucci`).

## Arquivos

- `docker-compose.prod.yaml` — stack de produção (Rails, Sidekiq, Postgres/pgvector,
  Redis) atrás do Traefik. Usa a imagem custom `chatwoot-welucci:latest`.
- `.env.example` — template das variáveis de ambiente. **Segredos redigidos** (`CHANGE_ME`).
  O `.env` real **não** vai pro Git (contém senhas/chaves).

## Fluxo de deploy (na VPS)

```bash
# 1. Atualizar o código-fonte
cd /root/chatwoot-src && git checkout welucci && git pull origin welucci

# 2. Buildar a imagem custom
docker build -f docker/Dockerfile -t chatwoot-welucci:latest .

# 3. Subir a stack (usa /root/chatwoot/docker-compose.yaml == este prod)
cd /root/chatwoot && docker compose up -d --force-recreate
```

## Branding (dados no banco — reaplicar se recriar o banco)

Logo/nome ficam em `InstallationConfig` (Postgres), não em arquivo. Os arquivos de
imagem estão versionados em `public/brand-assets/` e nos favicons em `public/`.
Para (re)apontar a config:

```bash
cd /root/chatwoot && docker compose exec -T rails bundle exec rails runner "
{
  'LOGO' => '/brand-assets/welucci_logo.png',
  'LOGO_DARK' => '/brand-assets/welucci_logo_dark.png',
  'LOGO_THUMBNAIL' => '/brand-assets/welucci_thumbnail.png',
  'INSTALLATION_NAME' => 'Welucci',
  'BRAND_NAME' => 'Welucci'
}.each { |n,v| c = InstallationConfig.find_or_initialize_by(name: n); c.value = v; c.save! }
GlobalConfig.clear_cache
"
```

## Recriar a VPS do zero

1. Clonar o repo em `/root/chatwoot-src` (branch `welucci`).
2. Criar `/root/chatwoot/`, copiar `deploy/docker-compose.prod.yaml` → `docker-compose.yaml`.
3. Copiar `deploy/.env.example` → `/root/chatwoot/.env` e preencher os segredos reais.
4. Rodar o fluxo de deploy acima.
5. Reaplicar o branding (comando acima).
6. Traefik: a rede externa `n8n_default` precisa existir (já usada por n8n/Evolution).
