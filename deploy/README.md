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

**Importação de contatos (só lê o HubSpot e nunca envia mensagem):**
- O token do app privado precisa dos escopos `crm.objects.contacts.read`, `crm.schemas.contacts.read` e `crm.objects.owners.read`, além dos de negócios. Sem eles, a importação para com erro no log do Sidekiq em vez de importar pela metade.
- Todo contato do HubSpot que tem telefone entra no Chatwoot, cruzado por ID do HubSpot, depois e-mail, depois telefone (com ou sem o nono dígito). Nome, e-mail e telefone do Chatwoot são mantidos; o HubSpot só preenche o que falta.
- Os campos do HubSpot viram atributos filtráveis do contato e são sempre atualizados a partir do HubSpot: etapa do ciclo de vida, status do lead, vendedor, origem, origem Welucci (se existir no portal), cidade, estado e empresa.
- A primeira carga percorre o HubSpot inteiro e guarda o cursor a cada página (`contacts_import` nas configurações da integração), então retoma de onde parou se for interrompida. Depois, a cada hora, lê só o que mudou.
- A importação grava sem disparar eventos de contato: nenhum webhook (n8n) nem automação recebe os contatos importados.

**Escolher o público em Contatos:**
- Filtre pelos atributos do HubSpot e salve como **Segmento**, que é lido na hora do envio e inclui contatos importados depois.
- Ou marque contatos específicos (a seleção vale entre páginas) e aplique uma etiqueta. Com um filtro ou segmento ativo, a barra oferece **"Selecionar todos os N contatos do filtro"**; depois disso, desmarcar alguém o deixa de fora. Excluir por filtro é bloqueado.

**Segmentos do HubSpot:** em Configurações → Integrações → HubSpot, o painel **Segmentos do HubSpot** lista os segmentos de contato do portal; os marcados viram etiquetas `hs-<nome>` (fora do menu lateral) mantidas em sincronia a cada hora. Aparecem no filtro de Contatos (Etiquetas) e no público da campanha. Exige o escopo `crm.lists.read`.

**Envio (Campanhas → WhatsApp, só inbox WhatsApp Cloud):**
- O público são as etiquetas e segmentos escolhidos. Ficam de fora automaticamente: contatos sem telefone, bloqueados e com a etiqueta `nao-enviar` (opt-out).
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

## Monitoramento de grupos (ex.: financeiro)

**Conectar um número do Evolution como espelho (somente leitura):**
```bash
cd /root/chatwoot && docker compose exec -T rails bundle exec rake "evolution:connect_mirror[contas_a_pagar,Contas a Pagar,30]" </dev/null
```
A inbox nasce com o espelho pausado e sem distribuição automática. O `HistoryImportJob` importa os últimos N dias (grupos e conversas, com anexos e a data original), liga o espelho ao vivo e faz uma repassada para os minutos da importação. A importação não dispara eventos: nada chega ao n8n, automações ou notificações. Rodar de novo só preenche lacunas.

**Pré-configurar quem vai usar (antes do primeiro acesso pelo Hub):**
1. Configurações → Agentes → **Adicionar agente**: nome, e-mail @welucci.com, função **Agente** e **Perfil de acesso: Monitoramento de grupos**.
2. Configurações → Caixas de entrada → a inbox do número → **Colaboradores**: adicionar a pessoa.
3. Opcional: Configurações → Times → adicionar ao time.

No primeiro acesso pelo Hub a conta é adotada com tudo isso. O perfil de monitoramento mostra só **Grupos** (dos números das inboxes da pessoa) e **Conversas** dessas inboxes; o resto do painel fica fora do menu e das rotas. Ações que mudam um grupo (nome, convite, admins) e o botão de atualizar diretório continuam só para administradores.

**Organização no monitor de grupos:** painel por responsável (grupos e quantos aguardam), filtros *Meus grupos / Sem responsável / pessoa* e por etiqueta, colunas Responsável e Etiquetas, e alerta de espera: amarelo até 2h aguardando, vermelho depois. No painel do grupo dá para escolher o responsável e as etiquetas; quem tem o perfil de monitoramento só atribui entre colegas com o mesmo perfil naquela inbox (nem administradores, nem times, nem bots — o servidor recusa o resto). Notas internas funcionam na caixa de texto da conversa.

**Histórico completo de um número já conectado:**
```bash
cd /root/chatwoot && docker compose exec -T rails bundle exec rails runner "Whatsapp::Evolution::HistoryImportJob.perform_later(<inbox_id>, 3650)" </dev/null
```
Pode rodar com o espelho ligado: a paginação das mensagens segue a data de envio, então o histórico antigo aparece ao rolar mesmo tendo sido importado depois.

