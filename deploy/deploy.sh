#!/usr/bin/env bash
# Deploy da branch `welucci` para a VPS de produção, a partir da máquina local.
# Uso: deploy/deploy.sh
set -euo pipefail

VPS="root@187.127.16.158"
LABEL="$(date +%Y%m%d-%H%M)"

if [ "$(git branch --show-current)" != "welucci" ]; then
  echo "Erro: faça o deploy a partir da branch welucci." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Erro: há alterações não commitadas." >&2
  exit 1
fi

git push origin welucci

ssh "$VPS" LABEL="$LABEL" bash -s <<'REMOTE'
set -euo pipefail
cd /root/chatwoot
docker compose exec -T postgres pg_dump -U chatwoot chatwoot > "/root/chatwoot-db-backup-$LABEL.sql"
docker tag chatwoot-welucci:latest "chatwoot-welucci:pre-$LABEL"

cd /root/chatwoot-src
git checkout welucci
git pull origin welucci
docker build -f docker/Dockerfile -t chatwoot-welucci:latest .

cd /root/chatwoot
docker compose up -d --force-recreate
REMOTE

sleep 20
curl -s -o /dev/null -w 'HTTP %{http_code}\n' https://chatwoot.srv1779041.hstgr.cloud/
echo "Rollback: docker tag chatwoot-welucci:pre-$LABEL chatwoot-welucci:latest && cd /root/chatwoot && docker compose up -d --force-recreate"
