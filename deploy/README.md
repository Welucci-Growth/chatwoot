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

## HubSpot → contatos e campanhas de WhatsApp

**Sincronização (só lê o HubSpot e nunca envia mensagem):**
- No app privado do HubSpot, o token precisa dos escopos `crm.objects.contacts.read` e `crm.lists.read`.
- Em Configurações → Integrações → HubSpot, preencha **Listas de contatos** com os IDs das listas, separados por vírgula. O ID é o número que aparece na URL da lista.
- Cada lista vira uma etiqueta `hs-<nome-da-lista>`. Os membros entram como contatos, cruzados por ID do HubSpot, depois e-mail, depois telefone (com ou sem o nono dígito). Quando o contato já existe, o HubSpot só preenche o que estiver em branco no Chatwoot.
- A sincronização roda a cada hora e logo depois de salvar a configuração. Quem sai da lista perde a etiqueta. Uma lista tirada da configuração tem a etiqueta removida de todos os contatos.

**Envio (Campanhas → WhatsApp, só inbox WhatsApp Cloud):**
- O público são as etiquetas escolhidas. Ficam de fora automaticamente: contatos sem telefone, bloqueados e com a etiqueta `nao-enviar` (opt-out).
- Antes de criar a campanha, o formulário mostra quantos contatos vão receber e quantos ficam de fora.
- Cada destinatário vira uma mensagem numa conversa **adiada** (não notifica os atendentes). Quando o cliente responde, ela reabre com a campanha no histórico. O card da campanha mostra enviadas, entregues, lidas e falhas.
- O envio é feito em lotes de 100 e não repete um contato que já recebeu, mesmo se um lote for reprocessado.

**Modo de teste (recomendado antes da primeira campanha real):**
```bash
# /root/chatwoot/.env — só estes números recebem campanhas enquanto a variável existir
CAMPAIGN_TEST_PHONE_NUMBERS=+5511999990000,+5511988880000
cd /root/chatwoot && docker compose up -d --force-recreate rails sidekiq
```
Os contatos de teste precisam ter uma das etiquetas do público. Para liberar os envios reais, apague a linha e recrie os containers do mesmo jeito.
