#!/bin/sh
# Copyright Roman Glos 2026

notify_channel_normalized() {
  ch="${NOTIFY_CHANNEL:-auto}"
  printf '%s' "$ch" | tr '[:upper:]' '[:lower:]'
}

notify_smtp_configured() {
  [ -n "${SMTP_HOST:-}" ] && [ -n "${MAIL_TO:-}" ] && [ -n "${MAIL_FROM:-}" ] && [ -x /scripts/mail_smtp.sh ]
}

notify_apprise_configured() {
  [ -n "${APPRISE_URL:-}" ] && command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1
}

notify_try_smtp_html() {
  subj="$1"
  html="$2"
  notify_smtp_configured || return 1
  printf '%s' "$html" | /scripts/mail_smtp.sh "$subj" >/dev/null 2>&1
}

notify_try_apprise_html() {
  subj="$1"
  html="$2"
  notify_apprise_configured || return 1
  payload="$(jq -rn --arg title "$subj" --arg body "$html" --arg format "html" '{title:$title, body:$body, format:$format}')" || return 1
  curl -fsSL -H 'Content-Type: application/json' -d "$payload" "$APPRISE_URL" >/dev/null 2>&1
}

notify_try_apprise_text() {
  subj="$1"
  body="$2"
  notify_apprise_configured || return 1
  payload="$(jq -rn --arg title "$subj" --arg body "$body" '{title:$title, body:$body}')" || return 1
  curl -fsSL -H 'Content-Type: application/json' -d "$payload" "$APPRISE_URL" >/dev/null 2>&1
}

notify_dispatch() {
  subj="$1"
  html="$2"
  plain="${3:-}"
  ch="$(notify_channel_normalized)"

  case "$ch" in
    none|off|disabled)
      return 0
      ;;
    smtp)
      notify_try_smtp_html "$subj" "$html"
      ;;
    apprise)
      if [ -n "$plain" ]; then
        notify_try_apprise_text "$subj" "$plain"
      else
        notify_try_apprise_html "$subj" "$html"
      fi
      ;;
    auto|*)
      notify_try_smtp_html "$subj" "$html" && return 0
      if [ -n "$plain" ]; then
        notify_try_apprise_text "$subj" "$plain"
      else
        notify_try_apprise_html "$subj" "$html"
      fi
      ;;
  esac
}


notify() {
  subj="$1"
  html="$2"
  plain="${3:-}"
  notify_dispatch "$subj" "$html" "$plain"
}
