#!/bin/sh
# Copyright Roman Glos 2026
# v3 — SMTP-first, works with BusyBox find (no -printf), correct newlines, MISSING detection, source info

set -eu
umask 022
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
[ -f /scripts/lib_i18n.sh ] && . /scripts/lib_i18n.sh || [ -f "$SCRIPT_DIR/lib_i18n.sh" ] && . "$SCRIPT_DIR/lib_i18n.sh"
[ -f /scripts/lib_notify.sh ] && . /scripts/lib_notify.sh || [ -f "$SCRIPT_DIR/lib_notify.sh" ] && . "$SCRIPT_DIR/lib_notify.sh"
[ -f /scripts/lib_stack.sh ] && . /scripts/lib_stack.sh || [ -f "$SCRIPT_DIR/lib_stack.sh" ] && . "$SCRIPT_DIR/lib_stack.sh" || true

WATCHDOG_MAX_AGE_SECS="${WATCHDOG_MAX_AGE_SECS:-3600}"
RESTART_COOLDOWN_SECS="${RESTART_COOLDOWN_SECS:-1800}"
WATCHDOG_DRY_RUN="${WATCHDOG_DRY_RUN:-0}"
WATCHDOG_NOTIFY="${WATCHDOG_NOTIFY:-1}"
APPRISE_URL="${APPRISE_URL:-}"
NOTIFY_CHANNEL="${NOTIFY_CHANNEL:-auto}"
HOST_NAME="${HOST_NAME:-}"
DOCKER_HOST="unix:///var/run/docker.sock"
BACKUP_DIR="${BACKUP_DIR:-/backup}"
BACKUP_CONTAINER_NAME="${BACKUP_CONTAINER_NAME:-minecraftserver_backup}"

STATE_DIR="/tmp"
STATE_FILE="${STATE_DIR}/backup_watchdog_state"
RESTART_FILE="${STATE_DIR}/backup_watchdog_last_restart"
BOOT_MARK_FILE="${STATE_DIR}/backup_watchdog_boot_epoch"
WATCHDOG_BOOT_GRACE_SECS="${WATCHDOG_BOOT_GRACE_SECS:-300}"

now() { date +%s; }

pick_host() {
  if [ -n "$HOST_NAME" ]; then echo "$HOST_NAME"; return; fi
  hostname 2>/dev/null || echo "mc-host"
}

docker_cli_ok() {
  command -v docker >/dev/null 2>&1 || return 1
  DOCKER_HOST="$DOCKER_HOST" docker info >/dev/null 2>&1
}

restart_backup_container() {
  if [ "$WATCHDOG_DRY_RUN" = "1" ]; then
    if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
      echo "[watchdog] $(fmt_now_long) DRY-RUN: würde ${BACKUP_CONTAINER_NAME} neu starten"
    else
      echo "[watchdog] $(fmt_now_long) DRY-RUN: would restart ${BACKUP_CONTAINER_NAME}"
    fi
    return 0
  fi

  docker_cli_ok || return 1
  DOCKER_HOST="$DOCKER_HOST" docker restart "$BACKUP_CONTAINER_NAME" >/dev/null 2>&1
}

latest_epoch_local() {
  d="$BACKUP_DIR"
  find "$d" -maxdepth 1 -type f -name '*.mcworld' -exec sh -c '
for f in "$@"; do
  if stat -c %Y "$f" >/dev/null 2>&1; then
    stat -c %Y "$f"
  elif stat -f %m "$f" >/dev/null 2>&1; then
    stat -f %m "$f"
  elif date -r "$f" +%s >/dev/null 2>&1; then
    date -r "$f" +%s
  fi
done
' sh {} + 2>/dev/null \
  | awk 'BEGIN{m=0} {if($1>m){m=$1}} END{print int(m)}'
}

latest_epoch_via_exec() {
  docker_cli_ok || { echo 0; return; }
  DOCKER_HOST="$DOCKER_HOST" docker exec -i "$BACKUP_CONTAINER_NAME" sh -lc "
find /data -maxdepth 1 -type f -name '*.mcworld' -exec sh -c '
for f in \"\$@\"; do
  if stat -c %Y \"\$f\" >/dev/null 2>&1; then
    stat -c %Y \"\$f\"
  elif stat -f %m \"\$f\" >/dev/null 2>&1; then
    stat -f %m \"\$f\"
  elif date -r \"\$f\" +%s >/dev/null 2>&1; then
    date -r \"\$f\" +%s
  fi
done
' sh {} + 2>/dev/null | awk 'BEGIN{m=0} {if(\$1>m){m=\$1}} END{print int(m)}'
" 2>/dev/null
}

latest_backup_age() {
  nowts="$(now)"

  e_local="$(latest_epoch_local || echo 0)"
  if [ "${e_local:-0}" -gt 0 ]; then
    echo $(( nowts - e_local ))
    echo "local" > "${STATE_DIR}/backup_watchdog_source" 2>/dev/null || true
    return
  fi

  e_exec="$(latest_epoch_via_exec || echo 0)"
  if [ "${e_exec:-0}" -gt 0 ]; then
    echo $(( nowts - e_exec ))
    echo "exec_fallback" > "${STATE_DIR}/backup_watchdog_source" 2>/dev/null || true
    return
  fi

  echo -1
  echo "none" > "${STATE_DIR}/backup_watchdog_source" 2>/dev/null || true
}

get_source() {
  [ -f "${STATE_DIR}/backup_watchdog_source" ] && cat "${STATE_DIR}/backup_watchdog_source" || echo "unknown"
}

cooldown_due() {
  nowts="$(now)"
  last=0
  [ -f "$RESTART_FILE" ] && last="$(cat "$RESTART_FILE" 2>/dev/null || echo 0)"
  due=$(( last + RESTART_COOLDOWN_SECS ))
  [ "$nowts" -ge "$due" ]
}

boot_grace_active() {
  [ "${WATCHDOG_BOOT_GRACE_SECS:-0}" -gt 0 ] 2>/dev/null || return 1
  [ -f "$BOOT_MARK_FILE" ] || return 1
  boot_ts="$(cat "$BOOT_MARK_FILE" 2>/dev/null || echo 0)"
  [ "${boot_ts:-0}" -gt 0 ] 2>/dev/null || return 1
  nowts="$(now)"
  elapsed=$(( nowts - boot_ts ))
  [ "$elapsed" -lt "$WATCHDOG_BOOT_GRACE_SECS" ]
}

HOST="$(pick_host)"
BACKUP_TARGET_COUNT="$(enabled_backup_world_count 2>/dev/null || printf '0')"
if [ "$BACKUP_TARGET_COUNT" -le 0 ]; then
  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    echo "[watchdog] $(fmt_now_long) keine aktiven Backup-Ziele konfiguriert, überspringe Prüfung"
  else
    echo "[watchdog] $(fmt_now_long) no active backup targets configured, skipping check"
  fi
  echo "DISABLED" > "$STATE_FILE" 2>/dev/null || true
  exit 0
fi

if boot_grace_active; then
  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    echo "[watchdog] $(fmt_now_long) Bootstrap-Schutz aktiv (${WATCHDOG_BOOT_GRACE_SECS}s), überspringe Prüfung"
  else
    echo "[watchdog] $(fmt_now_long) bootstrap grace active (${WATCHDOG_BOOT_GRACE_SECS}s), skipping check"
  fi
  echo "BOOTSTRAP" > "$STATE_FILE" 2>/dev/null || true
  exit 0
fi

AGE="$(latest_backup_age)"
THRESH="$WATCHDOG_MAX_AGE_SECS"
SRC="$(get_source)"

STATE="OK"
if [ "$AGE" -lt 0 ]; then
  STATE="MISSING"
elif [ "$AGE" -ge "$THRESH" ]; then
  STATE="STALE"
fi

PREV="UNKNOWN"
[ -f "$STATE_FILE" ] && PREV="$(cat "$STATE_FILE" 2>/dev/null || echo UNKNOWN)"

if [ "$PREV" != "$STATE" ]; then
  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    echo "[watchdog] $(fmt_now_long) Statuswechsel: ${PREV} -> ${STATE} (Alter=${AGE}s, Schwellwert=${THRESH}s, Quelle=${SRC})"
  else
    echo "[watchdog] $(fmt_now_long) state change: ${PREV} -> ${STATE} (age=${AGE}s, threshold=${THRESH}s, source=${SRC})"
  fi
fi
echo "$STATE" > "$STATE_FILE" 2>/dev/null || true

if [ "$STATE" = "STALE" ] || [ "$STATE" = "MISSING" ]; then
  if cooldown_due; then
    if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
      reason="Neuestes Backup-Alter=${AGE}s ≥ ${THRESH}s"
      [ "$STATE" = "MISSING" ] && reason="Keine Backups gefunden (AGE=-1)"
      echo "[watchdog] $(fmt_now_long) ${STATE} erkannt -> starte Container ${BACKUP_CONTAINER_NAME} neu"
    else
      reason="Newest backup age=${AGE}s >= ${THRESH}s"
      [ "$STATE" = "MISSING" ] && reason="No backups found (AGE=-1)"
      echo "[watchdog] $(fmt_now_long) ${STATE} detected -> restarting container ${BACKUP_CONTAINER_NAME}"
    fi

    if restart_backup_container; then
      nowts="$(now)"
      echo "$nowts" > "$RESTART_FILE" 2>/dev/null || true
      if [ "$WATCHDOG_NOTIFY" = "1" ]; then
        if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
          subj="Minecraft Backup Watchdog: ${STATE}"
          html="<h3>Minecraft Backup Watchdog: ${STATE}</h3>
<table border=\"1\" cellpadding=\"6\" cellspacing=\"0\">
<tr><td><b>Host</b></td><td>${HOST}</td></tr>
<tr><td><b>Grund</b></td><td>${reason}</td></tr>
<tr><td><b>Cooldown</b></td><td>${RESTART_COOLDOWN_SECS}s</td></tr>
<tr><td><b>Quelle</b></td><td>${SRC}</td></tr>
</table>
<p>Aktion: <b>${BACKUP_CONTAINER_NAME}</b> wurde neu gestartet.</p>"
          plain="$(printf 'Host: %s\nGrund: %s\nCooldown: %ss\nQuelle: %s' "$HOST" "$reason" "$RESTART_COOLDOWN_SECS" "$SRC")"
          [ "$WATCHDOG_DRY_RUN" = "1" ] && html="${html}<p><b>DRY-RUN</b> - kein echter Neustart durchgeführt.</p>"
        else
          subj="Minecraft Backup Watchdog: ${STATE}"
          html="<h3>Minecraft Backup Watchdog: ${STATE}</h3>
<table border=\"1\" cellpadding=\"6\" cellspacing=\"0\">
<tr><td><b>Host</b></td><td>${HOST}</td></tr>
<tr><td><b>Reason</b></td><td>${reason}</td></tr>
<tr><td><b>Cooldown</b></td><td>${RESTART_COOLDOWN_SECS}s</td></tr>
<tr><td><b>Source</b></td><td>${SRC}</td></tr>
</table>
<p>Action: restarted <b>${BACKUP_CONTAINER_NAME}</b>.</p>"
          plain="$(printf 'Host: %s\nReason: %s\nCooldown: %ss\nSource: %s' "$HOST" "$reason" "$RESTART_COOLDOWN_SECS" "$SRC")"
          [ "$WATCHDOG_DRY_RUN" = "1" ] && html="${html}<p><b>DRY-RUN</b> - no actual restart performed.</p>"
        fi
        notify "$subj" "$html" "$plain"
      fi
    else
      if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
        echo "[watchdog] $(fmt_now_long) Neustart FEHLGESCHLAGEN"
      else
        echo "[watchdog] $(fmt_now_long) restart FAILED"
      fi
      if [ "$WATCHDOG_NOTIFY" = "1" ]; then
        if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
          subj="Minecraft Backup Watchdog: RESTART FEHLGESCHLAGEN"
          html="<h3>Minecraft Backup Watchdog: RESTART FEHLGESCHLAGEN</h3><p>Host: <b>${HOST}</b></p><p>${BACKUP_CONTAINER_NAME} konnte nicht neu gestartet werden.</p><p>Quelle: ${SRC}</p>"
          plain="$(printf 'Host: %s\n%s konnte nicht neu gestartet werden.\nQuelle: %s' "$HOST" "$BACKUP_CONTAINER_NAME" "$SRC")"
        else
          subj="Minecraft Backup Watchdog: RESTART FAILED"
          html="<h3>Minecraft Backup Watchdog: RESTART FAILED</h3><p>Host: <b>${HOST}</b></p><p>Could not restart ${BACKUP_CONTAINER_NAME}.</p><p>Source: ${SRC}</p>"
          plain="$(printf 'Host: %s\nCould not restart %s.\nSource: %s' "$HOST" "$BACKUP_CONTAINER_NAME" "$SRC")"
        fi
        notify "$subj" "$html" "$plain"
      fi
    fi
  else
    if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
      echo "[watchdog] $(fmt_now_long) ${STATE}, aber Cooldown aktiv (${RESTART_COOLDOWN_SECS}s)"
    else
      echo "[watchdog] $(fmt_now_long) ${STATE}, but cooldown is active (${RESTART_COOLDOWN_SECS}s)"
    fi
  fi
else
  if [ "$WATCHDOG_NOTIFY" = "1" ] && [ "$PREV" != "OK" ]; then
    if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
      subj="Minecraft Backup Watchdog: OK"
      html="<h3>Minecraft Backup Watchdog: OK</h3>
<table border=\"1\" cellpadding=\"6\" cellspacing=\"0\">
<tr><td><b>Host</b></td><td>${HOST}</td></tr>
<tr><td><b>Neuestes Backup-Alter</b></td><td>${AGE}s</td></tr>
<tr><td><b>Schwellwert</b></td><td>${THRESH}s</td></tr>
<tr><td><b>Quelle</b></td><td>${SRC}</td></tr>
</table>"
      plain="$(printf 'Host: %s\nNeuestes Backup-Alter=%ss < %ss\nQuelle: %s' "$HOST" "$AGE" "$THRESH" "$SRC")"
    else
      subj="Minecraft Backup Watchdog: OK"
      html="<h3>Minecraft Backup Watchdog: OK</h3>
<table border=\"1\" cellpadding=\"6\" cellspacing=\"0\">
<tr><td><b>Host</b></td><td>${HOST}</td></tr>
<tr><td><b>Newest backup age</b></td><td>${AGE}s</td></tr>
<tr><td><b>Threshold</b></td><td>${THRESH}s</td></tr>
<tr><td><b>Source</b></td><td>${SRC}</td></tr>
</table>"
      plain="$(printf 'Host: %s\nNewest backup age=%ss < %ss\nSource: %s' "$HOST" "$AGE" "$THRESH" "$SRC")"
    fi
    notify "$subj" "$html" "$plain"
  fi
fi

exit 0
