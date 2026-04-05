#!/bin/sh
# Copyright Roman Glos 2026
set -eu

# --- runtime prerequisites are installed in the image at build time ---
# ensure /bin/bash exists for scripts that expect it
[ -x /bin/bash ] || ln -sf /usr/bin/bash /bin/bash || true

# --- prepare script locations ---
SRC_SCRIPTS="/scripts_ro"
[ -d "$SRC_SCRIPTS" ] || SRC_SCRIPTS="/scripts"
mkdir -p /opt/scripts /etc/crontabs /www /var/log/lighttpd /etc/lighttpd

# copy scripts from read-only mount into writable location
if [ "$(ls -A "$SRC_SCRIPTS" 2>/dev/null || true)" ]; then
  cp -r "$SRC_SCRIPTS"/* /opt/scripts/ 2>/dev/null || true
fi

# --- crontab: prefer maintenance/cron/root, fall back to /crontab_ro ---
if [ -f /maintenance/cron/root ]; then
  install -m 600 /maintenance/cron/root /etc/crontabs/root
elif [ -f /crontab_ro ]; then
  install -m 600 /crontab_ro /etc/crontabs/root
fi

# --- normalize line endings & permissions BEFORE starting cron ---
for f in /opt/scripts/*.sh; do
  [ -e "$f" ] || continue
  sed -i 's/\r$//' "$f" || true
  chmod +x "$f" || true
done
[ -f /etc/crontabs/root ] && sed -i 's/\r$//' /etc/crontabs/root || true
if [ -f /etc/crontabs/root ]; then
  if grep -q '^TZ=' /etc/crontabs/root; then
    sed -i "s#^TZ=.*#TZ=${TZ:-Europe/Berlin}#" /etc/crontabs/root || true
  else
    printf "TZ=%s\n" "${TZ:-Europe/Berlin}" | cat - /etc/crontabs/root > /etc/crontabs/root.new && mv /etc/crontabs/root.new /etc/crontabs/root
  fi
fi

# keep legacy path
ln -snf /opt/scripts /scripts

# generate managed Bedrockifier config
[ -x /scripts/generate_backup_config.sh ] && /scripts/generate_backup_config.sh || true

# load i18n helper when available
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
[ -f /scripts/lib_i18n.sh ] && . /scripts/lib_i18n.sh || [ -f "$SCRIPT_DIR/lib_i18n.sh" ] && . "$SCRIPT_DIR/lib_i18n.sh"
[ -f /scripts/lib_stack.sh ] && . /scripts/lib_stack.sh || [ -f "$SCRIPT_DIR/lib_stack.sh" ] && . "$SCRIPT_DIR/lib_stack.sh"

# --- grant lighttpd access to docker.sock and /backup groups (unchanged logic) ---
SOCK="/var/run/docker.sock"
if [ -S "$SOCK" ]; then
  GID="$(stat -c %g "$SOCK" 2>/dev/null || echo 0)"
  if [ "$GID" -ne 0 ]; then
    GNAME="$(getent group | awk -F: -v g="$GID" '$3==g{print $1;exit}')"
    if [ -n "${GNAME:-}" ]; then
      addgroup lighttpd "$GNAME" 2>/dev/null || true
    else
      addgroup -S -g "$GID" dockersock 2>/dev/null || true
      addgroup lighttpd dockersock 2>/dev/null || true
    fi
  fi
fi

BACKUP_DIR="/backup"
if [ -d "$BACKUP_DIR" ]; then
  BGID="$(stat -c %g "$BACKUP_DIR" 2>/dev/null || echo 0)"
  if [ "$BGID" -ne 0 ]; then
    BGRP="$(getent group | awk -F: -v g="$BGID" '$3==g{print $1;exit}')"
    if [ -n "${BGRP:-}" ]; then
      addgroup lighttpd "$BGRP" 2>/dev/null || true
    else
      addgroup -S -g "$BGID" backupshare 2>/dev/null || true
      addgroup lighttpd backupshare 2>/dev/null || true
    fi
  fi
fi

# --- lighttpd minimal config (unchanged) ---
printf '%s\n' \
  'server.document-root = "/www"' \
  "server.port = 8081" \
  'server.modules = ( "mod_accesslog", "mod_dirlisting", "mod_cgi" )' \
  'index-file.names      = ( "index.html" )' \
  'dir-listing.activate  = "enable"' \
  'cgi.assign = ( ".cgi" => "/bin/sh" )' \
  'accesslog.filename = "/var/log/lighttpd/access.log"' \
  'server.errorlog    = "/var/log/lighttpd/error.log"' \
  'server.username  = "lighttpd"' \
  'server.groupname = "lighttpd"' \
  | tee /etc/lighttpd/lighttpd.conf >/dev/null

if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
  echo "[init] $(su lighttpd -s /bin/sh -c 'echo -n lighttpd groups: ; id -Gn')"
  echo "[init] $(fmt_now_short) Uhr lighttpd startet auf :${MAINTENANCE_WEB_PORT:-8081}"
else
  echo "[init] $(su lighttpd -s /bin/sh -c 'echo -n lighttpd groups: ; id -Gn')"
  echo "[init] $(fmt_now_long) lighttpd is starting on :${MAINTENANCE_WEB_PORT:-8081}"
fi
ENABLED_MC="$(enabled_mc_containers 2>/dev/null || printf '%s' '')"
BACKUP_TARGETS_EFFECTIVE="$(enabled_backup_targets 2>/dev/null || printf '%s' 'none')"
if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
  echo "[init] aktive Minecraft-Profile: ${COMPOSE_PROFILES:-creative,survival}"
  echo "[init] aktive Minecraft-Container: ${ENABLED_MC:-keine}"
  echo "[init] aktive Backup-Ziele: ${BACKUP_TARGETS_EFFECTIVE}"
else
  echo "[init] active Minecraft profiles: ${COMPOSE_PROFILES:-creative,survival}"
  echo "[init] active Minecraft containers: ${ENABLED_MC:-none}"
  echo "[init] active backup targets: ${BACKUP_TARGETS_EFFECTIVE}"
fi
lighttpd -f /etc/lighttpd/lighttpd.conf

if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
  echo "[init] $(fmt_now_short) Uhr Sockets im Container:"
else
  echo "[init] $(fmt_now_long) sockets in container:"
fi
(ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null || true)

# --- mark maintenance startup for watchdog bootstrap grace ---
WATCHDOG_BOOT_MARK_FILE="/tmp/backup_watchdog_boot_epoch"
date +%s > "$WATCHDOG_BOOT_MARK_FILE" 2>/dev/null || true

# --- start cron in BACKGROUND early so self-test reports cron_up=1 ---
crond -b -l 8 || true

# optional self-test (kept as-is)
[ -x /scripts/http_selftest.sh ] && /scripts/http_selftest.sh || true

# --- replace background crond with FOREGROUND crond for PID1 cleanliness ---
pkill -x crond 2>/dev/null || true

# final: run cron in foreground (keeps container alive), loglevel 8
exec crond -f -l 8
