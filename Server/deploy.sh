#!/bin/sh
# Builds the server for the NAS and installs or updates it.
#
#   ./deploy.sh          build, copy, and create or update the TrueNAS app
#
# Settings come from deploy.env (copy deploy.env.example; never committed).
set -eu
cd "$(dirname "$0")"
[ -f deploy.env ] || { echo "Missing deploy.env: copy deploy.env.example and fill it in." >&2; exit 1; }
. ./deploy.env
: "${NAS_SSH:?set NAS_SSH in deploy.env}" "${TODAYFLOW_BASE:?set TODAYFLOW_BASE in deploy.env}"

docker buildx build --platform linux/amd64 --target export --output type=local,dest=out .
APP="$TODAYFLOW_BASE/app"
scp -q out/TodayFlowServer "$NAS_SSH:$APP/TodayFlowServer.new"
scp -q backup.sh truenas-install.py deploy.env "$NAS_SSH:$APP/"
ssh "$NAS_SSH" "cd '$APP' && chmod 600 deploy.env && \
  { [ -f TodayFlowServer ] && mv TodayFlowServer TodayFlowServer.prev || true; } && \
  mv TodayFlowServer.new TodayFlowServer && chmod 755 TodayFlowServer && \
  python3 truenas-install.py && midclt call -j app.redeploy todayflow >/dev/null"
echo "Deployed. Check: curl ${TODAYFLOW_URL:-http://<nas>:8787}/health"
