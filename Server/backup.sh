#!/bin/sh
# Dumps the TodayFlow database every BACKUP_EVERY_SECONDS (default: daily)
# into /backups, keeping the newest BACKUP_KEEP (default: 14) dumps.
# A file named "backup-now" in /control (written by the admin page) makes a
# dump within 15 seconds.
# Restore one with:
#   docker compose exec -T db pg_restore -U todayflow -d todayflow --clean < backups/<file>.dump
set -u
every="${BACKUP_EVERY_SECONDS:-86400}"
keep="${BACKUP_KEEP:-14}"
request=/control/backup-now

backup() {
  name="/backups/todayflow-$(date -u +%Y%m%d-%H%M%S).dump"
  if pg_dump -Fc -f "$name.tmp"; then
    mv "$name.tmp" "$name"
    chmod 644 "$name"
    echo "backup written: $name"
  else
    rm -f -- "$name.tmp"
    echo "backup FAILED"
  fi
  # Delete dumps beyond the newest $keep. Names have no spaces.
  count=0
  for file in $(ls -1t /backups/todayflow-*.dump 2>/dev/null); do
    count=$((count + 1))
    if [ "$count" -gt "$keep" ]; then
      rm -f -- "$file"
    fi
  done
}

mkdir -p /control
waited="$every"
while true; do
  if [ -f "$request" ]; then
    echo "backup requested from the admin page"
    backup
    rm -f -- "$request"
  elif [ "$waited" -ge "$every" ]; then
    backup
    waited=0
  fi
  sleep 15
  waited=$((waited + 15))
done
