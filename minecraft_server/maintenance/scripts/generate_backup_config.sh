#!/bin/sh
# Copyright Roman Glos 2026
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
[ -f /scripts/lib_i18n.sh ] && . /scripts/lib_i18n.sh || [ -f "$SCRIPT_DIR/lib_i18n.sh" ] && . "$SCRIPT_DIR/lib_i18n.sh" || true
[ -f /scripts/lib_stack.sh ] && . /scripts/lib_stack.sh || [ -f "$SCRIPT_DIR/lib_stack.sh" ] && . "$SCRIPT_DIR/lib_stack.sh" || true

BACKUP_CONFIG_ROOT="${BACKUP_CONFIG_ROOT:-/backup_config}"
OUT_FILE="${BACKUP_CONFIG_ROOT}/config.yml"
TMP_FILE="${OUT_FILE}.tmp"

CREATIVE_NAME="${CREATIVE_CONTAINER_NAME:-minecraftserver_creative}"
SURVIVAL_NAME="${SURVIVAL_CONTAINER_NAME:-minecraftserver_survival}"
CREATIVE_SSH_HOST="${CREATIVE_BACKUP_SSH_HOST:-creative-server}"
SURVIVAL_SSH_HOST="${SURVIVAL_BACKUP_SSH_HOST:-survival-server}"
CREATIVE_LEVEL="${CREATIVE_LEVEL_NAME:-creative}"
SURVIVAL_LEVEL="${SURVIVAL_LEVEL_NAME:-Glosis}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-30m}"
BACKUP_STARTUP_DELAY="${BACKUP_STARTUP_DELAY:-2m}"
BACKUP_MIN_INTERVAL="${BACKUP_MIN_INTERVAL:-30m}"
BACKUP_RUN_INITIAL="${BACKUP_RUN_INITIAL:-true}"
BACKUP_TRIM_DAYS="${BACKUP_TRIM_DAYS:-7}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"
BACKUP_MIN_KEEP="${BACKUP_MIN_KEEP:-7}"

mkdir -p "$BACKUP_CONFIG_ROOT"

added=0
cat > "$TMP_FILE" <<CFG
# This file is generated automatically by the maintenance container.
# Manual changes will be overwritten on the next maintenance start.
containers:
CFG

if command -v backup_creative_enabled >/dev/null 2>&1 && backup_creative_enabled; then
  cat >> "$TMP_FILE" <<CFG
    - name: ${CREATIVE_NAME}
      ssh: ${CREATIVE_SSH_HOST}:2222
      passwordFile: /creative/.remote-console.yaml
      worlds:
        - /creative/worlds/${CREATIVE_LEVEL}
CFG
  added=1
fi

if command -v backup_survival_enabled >/dev/null 2>&1 && backup_survival_enabled; then
  cat >> "$TMP_FILE" <<CFG

    - name: ${SURVIVAL_NAME}
      ssh: ${SURVIVAL_SSH_HOST}:2222
      passwordFile: /survival/.remote-console.yaml
      worlds:
        - /survival/worlds/${SURVIVAL_LEVEL}
CFG
  added=1
fi

if [ "$added" -eq 0 ]; then
  cat >> "$TMP_FILE" <<CFG
  bedrock: []
CFG
else
  # indent block header only when entries exist
  sed -i '/^containers:$/a\  bedrock:' "$TMP_FILE"
fi

cat >> "$TMP_FILE" <<CFG

schedule:
  interval: ${BACKUP_INTERVAL}
  startupDelay: ${BACKUP_STARTUP_DELAY}
  minInterval: ${BACKUP_MIN_INTERVAL}
  runInitialBackup: ${BACKUP_RUN_INITIAL}

trim:
  trimDays: ${BACKUP_TRIM_DAYS}
  keepDays: ${BACKUP_KEEP_DAYS}
  minKeep: ${BACKUP_MIN_KEEP}
CFG

mv -f "$TMP_FILE" "$OUT_FILE"

if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
  if [ "$added" -eq 0 ]; then
    echo "[backup-config] Warnung: Keine aktiven Backup-Ziele erkannt, Konfiguration enthält keine Welten: ${OUT_FILE}"
  else
    echo "[backup-config] Bedrockifier-Konfiguration wurde erzeugt: ${OUT_FILE}"
  fi
else
  if [ "$added" -eq 0 ]; then
    echo "[backup-config] Warning: No active backup targets detected, configuration contains no worlds: ${OUT_FILE}"
  else
    echo "[backup-config] Bedrockifier configuration generated: ${OUT_FILE}"
  fi
fi
