#!/bin/zsh
# Generates iOS/TodayFlowPhone.xcodeproj from project.yml.
# Signing: put DEVELOPMENT_TEAM=<your team id> in iOS/signing.env (ignored).
set -euo pipefail
cd "${0:A:h}"
if [[ -f signing.env ]]; then
  set -a; source signing.env; set +a
fi
export DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
xcodegen generate --spec project.yml
