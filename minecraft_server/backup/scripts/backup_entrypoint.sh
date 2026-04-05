#!/bin/bash
# Copyright Roman Glos 2026
set -euo pipefail

CONFIG_FILE="${BACKUP_CONFIG_FILE:-/config/config.yml}"
WAIT_TIMEOUT="${BACKUP_READY_WAIT_TIMEOUT:-180}"
WAIT_INTERVAL="${BACKUP_READY_WAIT_INTERVAL:-2}"

log() {
  printf '[backup-wait] %s\n' "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

extract_world_paths() {
  awk '
    /^[[:space:]]*-[[:space:]]*\// {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      print line
    }
  ' "$CONFIG_FILE"
}


extract_ssh_hosts() {
  awk '''
    /^[[:space:]]*ssh:[[:space:]]*/ {
      line=$0
      sub(/^[[:space:]]*ssh:[[:space:]]*/, "", line)
      sub(/:[0-9]+$/, "", line)
      print line
    }
  ''' "$CONFIG_FILE"
}

purge_stale_host_keys() {
  local host="$1"
  local f
  for f in /config/.authorizedKeys /data/config/.authorizedKeys; do
    [ -f "$f" ] || continue
    if grep -qE "(^|[[:space:]])${host}([[:space:]]|:|$)" "$f" 2>/dev/null; then
      log "removing remembered SSH host key for ${host} from ${f}"
      grep -vE "(^|[[:space:]])${host}([[:space:]]|:|$)" "$f" > "${f}.tmp.$$" || true
      mv "${f}.tmp.$$" "$f"
    fi
  done
}
extract_password_files() {
  awk '
    /^[[:space:]]*passwordFile:[[:space:]]*\// {
      line=$0
      sub(/^[[:space:]]*passwordFile:[[:space:]]*/, "", line)
      print line
    }
  ' "$CONFIG_FILE"
}

wait_for_path() {
  local path="$1"
  local kind="$2"
  while true; do
    if [ -e "$path" ]; then
      return 0
    fi
    if [ "$SECONDS" -ge "$DEADLINE" ]; then
      log "timeout waiting for ${kind}: ${path}"
      return 1
    fi
    sleep "$WAIT_INTERVAL"
  done
}

wait_for_directory() {
  local path="$1"
  while true; do
    if [ -d "$path" ]; then
      return 0
    fi
    if [ "$SECONDS" -ge "$DEADLINE" ]; then
      log "timeout waiting for world directory: ${path}"
      return 1
    fi
    sleep "$WAIT_INTERVAL"
  done
}

if ! [[ "$WAIT_TIMEOUT" =~ ^[0-9]+$ ]]; then
  WAIT_TIMEOUT=180
fi
if ! [[ "$WAIT_INTERVAL" =~ ^[0-9]+$ ]] || [ "$WAIT_INTERVAL" -lt 1 ]; then
  WAIT_INTERVAL=2
fi

DEADLINE=$((SECONDS + WAIT_TIMEOUT))

if [ ! -f "$CONFIG_FILE" ]; then
  log "waiting for generated config: ${CONFIG_FILE}"
  wait_for_path "$CONFIG_FILE" "config file" || true
fi

if [ ! -f "$CONFIG_FILE" ]; then
  log "config still missing after wait window, continuing with image defaults"
  exec /usr/local/bin/entrypoint-demoter --match /data --debug --stdin-on-term stop /opt/bedrock/bedrockifierd
fi

mapfile -t WORLD_PATHS < <(extract_world_paths || true)
mapfile -t PASSWORD_FILES < <(extract_password_files || true)
mapfile -t SSH_HOSTS < <(extract_ssh_hosts || true)

for ssh_host in "${SSH_HOSTS[@]}"; do
  [ -n "$ssh_host" ] || continue
  purge_stale_host_keys "$ssh_host"
done

if [ "${#WORLD_PATHS[@]}" -eq 0 ]; then
  log "no world paths configured, starting backup service immediately"
else
  log "waiting for ${#WORLD_PATHS[@]} world path(s) and ${#PASSWORD_FILES[@]} password file(s)"
  for world_path in "${WORLD_PATHS[@]}"; do
    [ -n "$world_path" ] || continue
    wait_for_directory "$world_path" || true
  done
  for password_file in "${PASSWORD_FILES[@]}"; do
    [ -n "$password_file" ] || continue
    wait_for_path "$password_file" "password file" || true
  done
fi

log "startup prerequisites satisfied, launching Bedrockifier"
exec /usr/local/bin/entrypoint-demoter --match /data --debug --stdin-on-term stop /opt/bedrock/bedrockifierd
