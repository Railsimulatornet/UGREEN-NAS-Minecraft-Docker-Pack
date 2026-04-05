#!/bin/sh
# Copyright Roman Glos 2026
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
[ -f /scripts/lib_i18n.sh ] && . /scripts/lib_i18n.sh || [ -f "$SCRIPT_DIR/lib_i18n.sh" ] && . "$SCRIPT_DIR/lib_i18n.sh"
[ -f /scripts/lib_stack.sh ] && . /scripts/lib_stack.sh || [ -f "$SCRIPT_DIR/lib_stack.sh" ] && . "$SCRIPT_DIR/lib_stack.sh"

MC_CONTAINERS="${MC_CONTAINERS:-}"
[ -n "$MC_CONTAINERS" ] || MC_CONTAINERS="$(enabled_mc_containers 2>/dev/null || printf '%s' 'minecraftserver_creative minecraftserver_survival')"
BACKUP_CONTAINER_NAME="${BACKUP_CONTAINER_NAME:-minecraftserver_backup}"
DOCKER_SOCK="${DOCKER_SOCK:-/var/run/docker.sock}"
DOCKER_HOST="unix://${DOCKER_SOCK}"

for c in $MC_CONTAINERS; do
  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    echo "[restart] $(fmt_now_short) Uhr starte $c neu"
  else
    echo "[restart] $(fmt_now_long) restarting $c"
  fi
  DOCKER_HOST="$DOCKER_HOST" docker restart "$c" >/dev/null
 done

if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
  echo "[restart] $(fmt_now_short) Uhr starte $BACKUP_CONTAINER_NAME neu"
else
  echo "[restart] $(fmt_now_long) restarting $BACKUP_CONTAINER_NAME"
fi
DOCKER_HOST="$DOCKER_HOST" docker restart "$BACKUP_CONTAINER_NAME" >/dev/null

if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
  echo "[restart] $(fmt_now_short) Uhr abgeschlossen um $(fmt_now_long)"
else
  echo "[restart] $(fmt_now_long) completed"
fi
