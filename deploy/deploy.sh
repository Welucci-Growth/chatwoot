#!/usr/bin/env bash
# Deploy da branch `welucci` para a VPS de produção, a partir da máquina local.
# Uso: deploy/deploy.sh
set -euo pipefail

VPS="root@187.127.16.158"
LABEL="$(date +%Y%m%d-%H%M)"
COMMIT="$(git rev-parse HEAD)"

if [ "$(git branch --show-current)" != "welucci" ]; then
  echo "Erro: faça o deploy a partir da branch welucci." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Erro: há alterações não commitadas." >&2
  exit 1
fi

git push origin welucci

ssh "$VPS" LABEL="$LABEL" COMMIT="$COMMIT" bash -s <<'REMOTE'
set -euo pipefail
cd /root/chatwoot
# exec reads stdin, which here is this very script: without </dev/null it swallows the rest.
docker compose exec -T postgres pg_dump -U chatwoot chatwoot </dev/null > "/root/chatwoot-db-backup-$LABEL.sql"
docker tag chatwoot-welucci:latest "chatwoot-welucci:pre-$LABEL"

cd /root/chatwoot-src
git checkout welucci
git pull origin welucci
[ "$(git rev-parse HEAD)" = "$COMMIT" ] || { echo "Erro: a VPS não está no commit $COMMIT." >&2; exit 1; }
docker build -f docker/Dockerfile -t chatwoot-welucci:latest .

cd /root/chatwoot
# The containers do not migrate on boot, and new code reading a column that is not there yet
# takes the whole app down. Same stdin caveat as the backup above.
docker compose run --rm -T rails bundle exec rails db:migrate </dev/null
docker compose up -d --force-recreate
echo "DEPLOYED $COMMIT"
REMOTE

sleep 20
curl -s -o /dev/null -w 'HTTP %{http_code}\n' https://chatwoot.srv1779041.hstgr.cloud/
echo "Rollback: docker tag chatwoot-welucci:pre-$LABEL chatwoot-welucci:latest && cd /root/chatwoot && docker compose up -d --force-recreate"
