#!/bin/sh
# Copyright Roman Glos 2026
# Daily backup report, Outlook-friendly HTML, BusyBox/ash safe

set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
[ -f /scripts/lib_i18n.sh ] && . /scripts/lib_i18n.sh || [ -f "$SCRIPT_DIR/lib_i18n.sh" ] && . "$SCRIPT_DIR/lib_i18n.sh"
[ -f /scripts/lib_notify.sh ] && . /scripts/lib_notify.sh || [ -f "$SCRIPT_DIR/lib_notify.sh" ] && . "$SCRIPT_DIR/lib_notify.sh"
[ -f /scripts/lib_stack.sh ] && . /scripts/lib_stack.sh || [ -f "$SCRIPT_DIR/lib_stack.sh" ] && . "$SCRIPT_DIR/lib_stack.sh"

APPRISE_URL="${APPRISE_URL:-}"
NOTIFY_CHANNEL="${NOTIFY_CHANNEL:-auto}"
NOTIFY_RETRIES="${NOTIFY_RETRIES:-5}"
NOTIFY_RETRY_DELAY="${NOTIFY_RETRY_DELAY:-5}"
NOTIFY_DRY_RUN="${NOTIFY_DRY_RUN:-0}"
BACKUP_DIR="${BACKUP_DIR:-/backup}"
HOST_NAME="${HOST_NAME:-Ugreen NAS}"
DISPLAY_LIMIT="${DISPLAY_LIMIT:-200}"
TZ="${TZ:-Europe/Berlin}"
: "${CREATIVE_WORLD:=${CREATIVE_LEVEL_NAME:-creative}}"
: "${SURVIVAL_WORLD:=${SURVIVAL_LEVEL_NAME:-Glosis}}"

parse_date() {
  if [ -n "${NOTIFY_DATE:-}" ]; then
    case "$NOTIFY_DATE" in
      [0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9])
        D="${NOTIFY_DATE%%.*}"
        rest="${NOTIFY_DATE#*.}"
        M="${rest%%.*}"
        Y="${NOTIFY_DATE##*.}"
        YDAY="${Y}${M}${D}"
        TITLE_DATE_ISO="${Y}-${M}-${D}"
        TITLE_DATE_DE="${D}.${M}.${Y}"
        TITLE_DATE_EN="${Y}-${M}-${D}"
        return 0
        ;;
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
        Y="${NOTIFY_DATE%????}"
        MD="${NOTIFY_DATE#????}"
        M="${MD%??}"
        D="${MD#??}"
        YDAY="$NOTIFY_DATE"
        TITLE_DATE_ISO="${Y}-${M}-${D}"
        TITLE_DATE_DE="${D}.${M}.${Y}"
        TITLE_DATE_EN="${Y}-${M}-${D}"
        return 0
        ;;
    esac
  fi
  if TZ="$TZ" date -d 'yesterday' +%Y%m%d >/dev/null 2>&1; then
    YDAY="$(TZ="$TZ" date -d 'yesterday' +%Y%m%d)"
    TITLE_DATE_ISO="$(TZ="$TZ" date -d 'yesterday' +%Y-%m-%d)"
    TITLE_DATE_DE="$(TZ="$TZ" date -d 'yesterday' +%d.%m.%Y)"
    TITLE_DATE_EN="$TITLE_DATE_ISO"
  else
    YDAY="$(TZ="$TZ" date -v-1d +%Y%m%d)"
    TITLE_DATE_ISO="$(TZ="$TZ" date -v-1d +%Y-%m-%d)"
    TITLE_DATE_DE="$(TZ="$TZ" date -v-1d +%d.%m.%Y)"
    TITLE_DATE_EN="$TITLE_DATE_ISO"
  fi
}
parse_date

human() {
  awk 'function human(x){s="BKMGTPE";i=1;while(x>=1024&&i<length(s)){x/=1024;i++} printf("%.1f%s",x,substr(s,i,1))} {human($1)}'
}
fmt_from_token() {
  if command -v fmt_backup_token >/dev/null 2>&1; then
    fmt_backup_token "$1"
  else
    t="$1"
    dd=$(echo "$t"|cut -c7-8); mm=$(echo "$t"|cut -c5-6); yyyy=$(echo "$t"|cut -c1-4)
    HH=$(echo "$t"|cut -c10-11); MM=$(echo "$t"|cut -c12-13)
    printf "%s.%s.%s %s:%s" "$dd" "$mm" "$yyyy" "$HH" "$MM"
  fi
}

if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
  TITLE_DATE_DISPLAY="$TITLE_DATE_DE"
  STATUS_OK_TEXT='Alle Backups OK ✅'
  STATUS_FAIL_TEXT='Backups unvollständig ❌'
  FILES_WORD='Dateien'
  TOTAL_WORD='gesamt'
  COL_WORLD='Welt'
  COL_FILE='Datei'
  COL_SIZE='Größe'
  COL_TIME='Zeit'
  RETRY_MSG='Wiederholung'
  NO_ACTIVE_MSG='Keine aktiven Backup-Ziele konfiguriert.'
else
  TITLE_DATE_DISPLAY="$TITLE_DATE_EN"
  STATUS_OK_TEXT='All backups OK ✅'
  STATUS_FAIL_TEXT='Backups incomplete ❌'
  FILES_WORD='files'
  TOTAL_WORD='total'
  COL_WORLD='World'
  COL_FILE='File'
  COL_SIZE='Size'
  COL_TIME='Time'
  RETRY_MSG='retry'
  NO_ACTIVE_MSG='No active backup targets configured.'
fi

FILES=$(ls -1 "${BACKUP_DIR}"/*.${YDAY}-*.mcworld 2>/dev/null || true)

COUNT_CREATIVE=0; COUNT_SURVIVAL=0
SUM_CREATIVE=0;   SUM_SURVIVAL=0
ROWS=""

for f in $FILES; do
  base=$(basename "$f")
  world=""
  if backup_creative_enabled && [ "${base#${CREATIVE_WORLD}.}" != "$base" ]; then
    world="Creative"
  elif backup_survival_enabled && [ "${base#${SURVIVAL_WORLD}.}" != "$base" ]; then
    world="Survival"
  else
    continue
  fi
  ts="${base#*.}"; ts="${ts%.mcworld}"
  size_bytes=$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null || echo 0)
  if [ "$world" = "Creative" ]; then
    COUNT_CREATIVE=$((COUNT_CREATIVE+1)); SUM_CREATIVE=$((SUM_CREATIVE+size_bytes))
  else
    COUNT_SURVIVAL=$((COUNT_SURVIVAL+1)); SUM_SURVIVAL=$((SUM_SURVIVAL+size_bytes))
  fi
  ROWS="${ROWS}${ts}|${world}|${base}|${size_bytes}|${ts}\n"
done

OK=1
BACKUP_TARGET_COUNT="$(enabled_backup_world_count 2>/dev/null || printf '0')"
if [ "$BACKUP_TARGET_COUNT" -gt 0 ]; then
  if backup_creative_enabled && [ "$COUNT_CREATIVE" -le 0 ]; then OK=0; fi
  if backup_survival_enabled && [ "$COUNT_SURVIVAL" -le 0 ]; then OK=0; fi
fi

SUM_CREATIVE_H=$(printf "%s" "$SUM_CREATIVE" | human)
SUM_SURVIVAL_H=$(printf "%s" "$SUM_SURVIVAL" | human)
TITLE="Minecraft Backup ${TITLE_DATE_DISPLAY} | Host: ${HOST_NAME}"
STATUS_HDR=$([ "$OK" -eq 1 ] && echo "$STATUS_OK_TEXT" || echo "$STATUS_FAIL_TEXT")

TMP_SRC="/tmp/_rows_src.$$"
TMP_HTML="/tmp/_rows_html.$$"
trap 'rm -f "$TMP_SRC" "$TMP_HTML"' EXIT

printf "%b" "$ROWS" | sort -t'|' -k1,1 > "$TMP_SRC"
LIMITED=$(tail -n "$DISPLAY_LIMIT" "$TMP_SRC" || true)

I=0
printf "%s\n" "$LIMITED" | while IFS='|' read -r _ world fname size ts2; do
  [ -n "${world:-}" ] || continue
  I=$((I+1))
  size_h=$(printf "%s" "$size" | human)
  when=$(fmt_from_token "$ts2")
  printf '<tr>\n    <td width="40" style="text-align:right;white-space:nowrap;padding:6px 8px;border:1px solid #D0D0D0">%s</td>\n    <td width="80" style="white-space:nowrap;padding:6px 8px;border:1px solid #D0D0D0">%s</td>\n    <td width="360" style="padding:6px 8px;border:1px solid #D0D0D0"><span style="font-family:Consolas,Menlo,Monaco,monospace">%s</span></td>\n    <td width="70" style="text-align:right;white-space:nowrap;padding:6px 8px;border:1px solid #D0D0D0">%s</td>\n    <td width="120" style="text-align:center;white-space:nowrap;padding:6px 8px;border:1px solid #D0D0D0">%s</td>\n  </tr>\n' "$I" "$world" "$fname" "$size_h" "$when"
done > "$TMP_HTML"
TABLE_HTML="$(cat "$TMP_HTML" 2>/dev/null || true)"

SUMMARY_ROWS=""
if backup_creative_enabled; then
SUMMARY_ROWS="${SUMMARY_ROWS}
  <tr>
    <td style=\"padding:0 16px 4px 0\"><b>Creative:</b></td><td style=\"padding:0 0 4px 0\">${COUNT_CREATIVE} ${FILES_WORD}, ${TOTAL_WORD} ${SUM_CREATIVE_H}</td>
  </tr>"
fi
if backup_survival_enabled; then
SUMMARY_ROWS="${SUMMARY_ROWS}
  <tr>
    <td style=\"padding:0 16px 4px 0\"><b>Survival:</b></td><td style=\"padding:0 0 4px 0\">${COUNT_SURVIVAL} ${FILES_WORD}, ${TOTAL_WORD} ${SUM_SURVIVAL_H}</td>
  </tr>"
fi
if [ -z "$SUMMARY_ROWS" ]; then
SUMMARY_ROWS="
  <tr><td colspan=\"2\" style=\"padding:0 0 4px 0\">${NO_ACTIVE_MSG}</td></tr>"
fi

BODY_HTML="$(cat <<EOF_BODY
<h3 style="margin:0 0 8px 0;font-family:Segoe UI,Arial,Helvetica,sans-serif;">${STATUS_HDR}</h3>
<table role="presentation" cellspacing="0" cellpadding="0" border="0" style="font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;margin:0 0 10px 0">${SUMMARY_ROWS}
</table>

<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;table-layout:fixed;font-family:Segoe UI,Arial,Helvetica,sans-serif;font-size:12px;border:1px solid #D0D0D0">
  <thead>
    <tr style="background:#F3F3F3">
      <th width="40"  align="right" style="text-align:right;white-space:nowrap;padding:6px 8px;border:1px solid #D0D0D0">#</th>
      <th width="80"  align="left"  style="text-align:left;white-space:nowrap;padding:6px 8px;border:1px solid #D0D0D0">${COL_WORLD}</th>
      <th width="360" align="left"  style="text-align:left;padding:6px 8px;border:1px solid #D0D0D0">${COL_FILE}</th>
      <th width="70"  align="right" style="text-align:right;white-space:nowrap;padding:6px 8px;border:1px solid #D0D0D0">${COL_SIZE}</th>
      <th width="120" align="center" style="text-align:center;white-space:nowrap;padding:6px 8px;border:1px solid #D0D0D0">${COL_TIME}</th>
    </tr>
  </thead>
  <tbody>
${TABLE_HTML}
  </tbody>
</table>
EOF_BODY
)"

if [ "$NOTIFY_DRY_RUN" = "1" ]; then
  if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
    echo "[notify] $(fmt_now_long) DRY-RUN -> Kanal ${NOTIFY_CHANNEL}, APPRISE_URL=${APPRISE_URL:-<leer>}"
  else
    echo "[notify] $(fmt_now_long) DRY-RUN -> channel ${NOTIFY_CHANNEL}, APPRISE_URL=${APPRISE_URL:-<empty>}"
  fi
  echo "$TITLE"
  printf "%s\n" "$BODY_HTML" | sed -n '1,80p'
  exit 0
fi

I=0
until [ "$I" -ge "$NOTIFY_RETRIES" ]; do
  if command -v notify_dispatch >/dev/null 2>&1 && notify_dispatch "$TITLE" "$BODY_HTML"; then
    channel_name="$(notify_channel_normalized 2>/dev/null || printf '%s' "$NOTIFY_CHANNEL")"
    echo "[notify] ${YDAY} OK (${channel_name} ok=$OK)"
    exit 0
  fi
  I=$((I+1))
  echo "[notify] ${RETRY_MSG} $I/${NOTIFY_RETRIES}..."
  sleep "$NOTIFY_RETRY_DELAY"
done

if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
  echo "[notify] $(fmt_now_long) SENDEFEHLER -> ${TITLE}"
else
  echo "[notify] $(fmt_now_long) SEND-FAIL -> ${TITLE}"
fi
exit 1
