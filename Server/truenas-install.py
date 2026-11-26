#!/usr/bin/env python3
"""Creates the TodayFlow custom app on TrueNAS SCALE via midclt.

Secrets are generated here, on the NAS, and saved to app/secrets.env (mode 600).
Re-running keeps existing secrets.
"""
import json
import os
import secrets
import subprocess
import sys

# Where things live on this NAS comes from deploy.env next to this script
# (copied by deploy.sh; never committed). See deploy.env.example.
HERE = os.path.dirname(os.path.abspath(__file__))
config = dict(os.environ)
deploy_env = os.path.join(HERE, "deploy.env")
if os.path.exists(deploy_env):
    for line in open(deploy_env):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            config.setdefault(key.strip(), value.strip().strip('"'))
missing = [k for k in ("TODAYFLOW_BASE", "TODAYFLOW_BACKUPS") if not config.get(k)]
if missing:
    sys.exit(f"Set {', '.join(missing)} in {deploy_env} (see deploy.env.example).")

BASE = config["TODAYFLOW_BASE"]            # dataset folder: app/, postgres/, blobs/, control/
APP = f"{BASE}/app"
SECRETS = f"{APP}/secrets.env"
BACKUPS = config["TODAYFLOW_BACKUPS"]      # daily dumps, ideally on another disk
CONTROL = f"{BASE}/control"   # "back up now" requests; owned by uid 10001

values = {}
if os.path.exists(SECRETS):
    for line in open(SECRETS):
        if "=" in line:
            key, value = line.strip().split("=", 1)
            values[key] = value
values.setdefault("POSTGRES_PASSWORD", secrets.token_hex(24))
# Single-user leftover: users now have their own pairing codes.
values.pop("TODAYFLOW_PAIRING_CODE", None)
values.setdefault("TODAYFLOW_ADMIN_PASSWORD", "-".join(secrets.token_hex(4) for _ in range(4)))
fd = os.open(SECRETS, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    for key, value in values.items():
        f.write(f"{key}={value}\n")

health = (
    "exec 3<>/dev/tcp/127.0.0.1/8787 && "
    "printf 'GET /health HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n' >&3 && "
    "timeout 3 grep -q ok <&3"
)

compose = {
    "services": {
        "db": {
            "image": "postgres:17-alpine",
            "restart": "unless-stopped",
            "environment": {
                "POSTGRES_USER": "todayflow",
                "POSTGRES_PASSWORD": values["POSTGRES_PASSWORD"],
                "POSTGRES_DB": "todayflow",
            },
            "volumes": [f"{BASE}/postgres:/var/lib/postgresql/data"],
            "healthcheck": {
                "test": ["CMD-SHELL", "pg_isready -U todayflow -d todayflow"],
                "interval": "5s", "timeout": "3s", "retries": 20,
            },
            "mem_limit": "512m",
        },
        "server": {
            "image": "ubuntu:22.04",
            "restart": "unless-stopped",
            "user": "10001:10001",
            "depends_on": {"db": {"condition": "service_healthy"}},
            "command": ["/app/TodayFlowServer"],
            "environment": {
                "PGHOST": "db",
                "PGUSER": "todayflow",
                "PGPASSWORD": values["POSTGRES_PASSWORD"],
                "PGDATABASE": "todayflow",
                "TODAYFLOW_BLOB_DIR": "/data/blobs",
                "TODAYFLOW_ADMIN_PASSWORD": values["TODAYFLOW_ADMIN_PASSWORD"],
                "TODAYFLOW_BACKUP_DIR": "/backups",
                "TODAYFLOW_CONTROL_DIR": "/control",
                # Shown in the admin page's restore instructions.
                "TODAYFLOW_HOST_BACKUP_DIR": BACKUPS,
                # The sync address devices use, shown on the admin page.
                "TODAYFLOW_PUBLIC_URL": config.get("TODAYFLOW_PUBLIC_URL") or config.get("TODAYFLOW_URL", ""),
            },
            "volumes": [
                f"{APP}/TodayFlowServer:/app/TodayFlowServer:ro",
                f"{BASE}/blobs:/data/blobs",
                f"{BACKUPS}:/backups:ro",
                f"{CONTROL}:/control",
            ],
            # 8787: sync (may be shared through Tailscale).
            # 8788: admin page (keep it on the home network).
            "ports": ["8787:8787", "8788:8788"],
            "healthcheck": {
                "test": ["CMD", "bash", "-c", health],
                "interval": "30s", "timeout": "3s", "start_period": "10s",
            },
            "mem_limit": "256m",
        },
        "backup": {
            "image": "postgres:17-alpine",
            "restart": "unless-stopped",
            "depends_on": {"db": {"condition": "service_healthy"}},
            "entrypoint": ["/bin/sh", "/backup.sh"],
            "environment": {
                "PGHOST": "db",
                "PGUSER": "todayflow",
                "PGPASSWORD": values["POSTGRES_PASSWORD"],
                "PGDATABASE": "todayflow",
                "BACKUP_EVERY_SECONDS": "86400",
                "BACKUP_KEEP": "14",
            },
            "volumes": [f"{BACKUPS}:/backups", f"{CONTROL}:/control", f"{APP}/backup.sh:/backup.sh:ro"],
            "mem_limit": "128m",
        },
    }
}

exists = subprocess.run(
    ["midclt", "call", "app.query", json.dumps([["name", "=", "todayflow"]])],
    capture_output=True, text=True,
).stdout.strip() not in ("", "[]")
if exists:
    args = ["midclt", "call", "-j", "app.update", "todayflow",
            json.dumps({"custom_compose_config": compose})]
else:
    args = ["midclt", "call", "-j", "app.create",
            json.dumps({"app_name": "todayflow", "custom_app": True, "custom_compose_config": compose})]
result = subprocess.run(args, capture_output=True, text=True)
print(args[3], "exit", result.returncode)
print((result.stderr or "")[-1500:])
print((result.stdout or "")[-300:])
