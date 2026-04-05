#!/bin/sh
# Copyright Roman Glos 2026
# Prometheus Text Exposition (Alpine + lighttpd/mod_cgi via /bin/sh)
set -eu
umask 022

[ -f /scripts/lib_i18n.sh ] && . /scripts/lib_i18n.sh

# -------- HTTP Header --------
printf 'Content-Type: text/plain\r\n\r\n'

# -------- Defaults / ENV --------
APPRISE_URL="${APPRISE_URL:-}"
APPRISE_BASE="${APPRISE_URL%/notify}"
BACKUP_DIR="${BACKUP_DIR:-/backup}"
BACKUP_CONTAINER_NAME="${BACKUP_CONTAINER_NAME:-minecraftserver_backup}"
BACKUP_HEALTH_METRIC_NAME="backup_container_healthy"
WATCHDOG_MAX_AGE_SECS="${WATCHDOG_MAX_AGE_SECS:-5400}"
DOCKER_SOCK="/var/run/docker.sock"
DOCKER_HOST_URI="unix://$DOCKER_SOCK"
NOW="$(date +%s)"

# Debug per Header oder ENV
DEBUG="${DEBUG_METRICS:-}"
[ "${HTTP_X_DEBUG:-}" = "1" ] && DEBUG=1
log(){ [ -n "${DEBUG:-}" ] && printf '# %s\n' "$*"; }

# Sichere PATH für CGI
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# -------- Helper --------
http_code(){ curl -m 2 -sS -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo 000; }

docker_rest_ping(){
  [ -S "$DOCKER_SOCK" ] || { log "no docker sock $DOCKER_SOCK"; return 1; }
  resp="$(curl -m 2 -sS --unix-socket "$DOCKER_SOCK" http://localhost/_ping 2>/dev/null || true)"
  [ "$resp" = "OK" ]
}

docker_cli_ok(){
  command -v docker >/dev/null 2>&1 || { log "docker cli missing"; return 1; }
  DOCKER_HOST="$DOCKER_HOST_URI" docker info >/dev/null 2>&1
}

docker_cli_health(){ # $1=container
  DOCKER_HOST="$DOCKER_HOST_URI" docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo unknown
}

inspect_health(){ # via REST → "healthy"/"unhealthy"/"starting"/"unknown"
  json="$(curl -m 2 -sS --unix-socket "$DOCKER_SOCK" "http://localhost/containers/$1/json" 2>/dev/null || true)"
  [ -n "$json" ] || { echo unknown; return; }
  printf '%s' "$json" | tr -d '\n' | sed 's/.*"Health":{"Status":"\([^"]*\)".*/\1/' 2>/dev/null || echo unknown
}

list_mcworlds_local(){ # prints: "<epoch> <file>"
  [ -d "$BACKUP_DIR" ] || return 1
  find "$BACKUP_DIR" -maxdepth 1 -type f -name "*.mcworld" -printf "%T@ %f\n" 2>/dev/null || true
}

list_mcworlds_via_exec(){ # prints: "<epoch> <file>" from backup container:/data
  command -v docker >/dev/null 2>&1 || return 1
  DOCKER_HOST="$DOCKER_HOST_URI" docker exec -i "$BACKUP_CONTAINER_NAME" sh -lc \
    'find /data -maxdepth 1 -type f -name "*.mcworld" -printf "%T@ %f\n" 2>/dev/null' 2>/dev/null || true
}

calc_ages(){ # in: lines "<ts> <file>"; out: echo LATEST_AGE + per-world to stdout (metrics later)
  ts_max=0
  # per-world latest ts in tmp file (name -> ts)
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT INT TERM
  printf '%s\n' "$1" | while IFS=' ' read -r ts name; do
    [ -n "${ts:-}" ] || continue
    base="$name"; base="${base%%.*}"
    # track per world
    cur="$(grep -E "^${base} " "$tmp" 2>/dev/null | awk '{print $2}' || true)"
    if [ -z "$cur" ] || awk -v a="$ts" -v b="$cur" 'BEGIN{exit !(a>b)}'; then
      # replace/add line
      grep -v -E "^${base} " "$tmp" 2>/dev/null > "${tmp}.n" || true
      mv "${tmp}.n" "$tmp"
      printf '%s %s\n' "$base" "$ts" >>"$tmp"
    fi
    # latest overall
    if awk -v a="$ts" -v b="$ts_max" 'BEGIN{exit !(a>b)}'; then ts_max="$ts"; fi
  done

  if awk -v m="$ts_max" 'BEGIN{exit !(m>0)}'; then
    LATEST_AGE=$(( NOW - ${ts_max%.*} ))
  else
    LATEST_AGE=-1
  fi

  # export globals by printing to fd3 (caller captures)
  echo "$LATEST_AGE"

  # also print per-world lines to fd4 (caller captures)
  if [ -s "$tmp" ]; then
    awk -v now="$NOW" '{printf "%s %d\n",$1, (now-int($2)) }' "$tmp"
  fi
}

# -------- Gauges: apprise_up / cron_up / docker_up --------
apprise_up=0
if [ -n "$APPRISE_URL" ]; then
  apprise_http="$(http_code "${APPRISE_BASE}/")"
  [ "$apprise_http" = "200" ] && apprise_up=1
fi

cron_up=0
# BusyBox-kompatibel: direkt in /proc lesen; Fallback pgrep
if [ -r /proc/1/comm ] && grep -q 'crond' /proc/1/comm; then
  cron_up=1
elif command -v pgrep >/dev/null 2>&1 && pgrep -x crond >/dev/null 2>&1; then
  cron_up=1
fi

# >>> NEU: Debug sofort hier ausgeben (früh im Output sichtbar)
[ -n "${DEBUG:-}" ] && printf '# cron_debug: pid1_comm=%s\n' "$(cat /proc/1/comm 2>/dev/null || echo -)"

dbg_cli=0; dbg_rest=0
if docker_cli_ok; then dbg_cli=1; fi
if docker_rest_ping; then dbg_rest=1; fi
docker_up=0; [ $dbg_cli -eq 1 ] || [ $dbg_rest -eq 1 ] && docker_up=1

# -------- backup container health --------
mb_health="unknown"
if [ $dbg_cli -eq 1 ]; then
  mb_health="$(docker_cli_health "$BACKUP_CONTAINER_NAME")"
elif [ $dbg_rest -eq 1 ]; then
  mb_health="$(inspect_health "$BACKUP_CONTAINER_NAME")"
fi
mb_gauge=0; [ "$mb_health" = "healthy" ] && mb_gauge=1

# -------- Backup-Ages (local → fallback exec) --------
SOURCE="local"
perm="$(stat -c '%U:%G %a' "$BACKUP_DIR" 2>/dev/null || echo 'UNKNOWN:UNKNOWN ---')"
local_list="$(list_mcworlds_local || true)"

if [ -n "$local_list" ]; then
  :
else
  SOURCE="exec_fallback"
  local_list="$(list_mcworlds_via_exec || true)"
fi

LATEST_AGE=-1
WORLD_AGES=""
if [ -n "$local_list" ]; then
  LATEST_AGE="$(printf '%s\n' "$local_list" | awk -v now="$NOW" '
    BEGIN{m=0}
    NF>=2 {
      ts=$1+0
      if (ts>m) m=ts
    }
    END{
      if (m>0) print int(now-m); else print -1
    }')"

  WORLD_AGES="$(printf '%s\n' "$local_list" | awk -v now="$NOW" '
    NF>=2 {
      ts=$1+0
      file=$2
      base=file
      sub(/\..*/,"",base)
      if (!(base in latest) || ts>latest[base]) latest[base]=ts
    }
    END{
      for (b in latest) printf "%s %d\n", b, int(now-latest[b])
    }')"
fi

# -------- Prometheus Output --------
[ -n "$DEBUG" ] && printf '# backup_dir=%s perm=%s total_mcworld=%s\n' \
  "$BACKUP_DIR" "$perm" "$(printf '%s\n' "$local_list" | wc -l | awk '{print $1}')"

printf '# HELP apprise_up Apprise HTTP endpoint up (200=1)\n# TYPE apprise_up gauge\napprise_up %d\n' "$apprise_up"
printf '# HELP cron_up BusyBox crond running (1=yes)\n# TYPE cron_up gauge\ncron_up %d\n' "$cron_up"
printf '# HELP docker_up Docker client can talk to daemon (1=yes)\n# TYPE docker_up gauge\ndocker_up %d\n' "$docker_up"
printf '# HELP %s docker health status of backup container (1=healthy)\n# TYPE %s gauge\n%s{container="%s"} %d\n' "$BACKUP_HEALTH_METRIC_NAME" "$BACKUP_HEALTH_METRIC_NAME" "$BACKUP_HEALTH_METRIC_NAME" "$BACKUP_CONTAINER_NAME" "$mb_gauge"

printf '# HELP backup_latest_age_seconds age of the newest .mcworld (seconds)\n# TYPE backup_latest_age_seconds gauge\n'
printf 'backup_latest_age_seconds %d\n' "${LATEST_AGE:- -1}"

printf '# HELP backup_age_seconds age of newest .mcworld by world (seconds, -1 if none)\n# TYPE backup_age_seconds gauge\n'
if [ -n "$WORLD_AGES" ]; then
  printf '%s\n' "$WORLD_AGES" | while read -r w age; do
    printf 'backup_age_seconds{world="%s"} %s\n' "$w" "$age"
  done
fi

printf '# HELP watchdog_threshold_seconds watchdog threshold for staleness (seconds)\n# TYPE watchdog_threshold_seconds gauge\n'
printf 'watchdog_threshold_seconds %s\n' "$WATCHDOG_MAX_AGE_SECS"

# -------- Watchdog state (metrics only, no notifications from CGI) --------
WATCHDOG_ALERT=0
if [ "${LATEST_AGE:- -1}" -ge 0 ] && [ "${WATCHDOG_MAX_AGE_SECS:-0}" -gt 0 ] &&    [ "${LATEST_AGE:-0}" -ge "${WATCHDOG_MAX_AGE_SECS:-0}" ]; then
  WATCHDOG_ALERT=1
fi

printf '# HELP watchdog_alert Backup freshness watchdog alert (1=stale)
# TYPE watchdog_alert gauge
'
printf 'watchdog_alert %d
' "$WATCHDOG_ALERT"

# -------- Debug Tail --------
if [ -n "$DEBUG" ]; then
  printf '# source=%s\n' "$SOURCE"
  printf '# cgi_user=%s groups=%s\n' "$(id -un)" "$(id -Gn)"
  printf '# PATH=%s\n' "$PATH"
  printf '# curl: %s\n' "$(curl -V | head -n1)"
  if command -v docker >/dev/null 2>&1; then
    printf '# docker: %s\n' "$(DOCKER_HOST="$DOCKER_HOST_URI" docker -v)"
  fi
  if [ -S "$DOCKER_SOCK" ]; then
    printf '# docker_sock: %s %s socket\n' "$(stat -c '%U:%G %a' "$DOCKER_SOCK" 2>/dev/null || echo '?')" ""
  fi
  printf '# docker_debug: cli=%d rest=%d\n' "$dbg_cli" "$dbg_rest"
fi
