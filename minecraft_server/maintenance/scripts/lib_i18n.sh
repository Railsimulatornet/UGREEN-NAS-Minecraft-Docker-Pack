#!/bin/sh
# Copyright Roman Glos 2026

MAINTENANCE_LANG_RAW="${MAINTENANCE_LANG:-de}"
case "$MAINTENANCE_LANG_RAW" in
  de|de_*|DE|DE_*) MAINTENANCE_LANG_NORM="de" ;;
  en|en_*|EN|EN_*) MAINTENANCE_LANG_NORM="en" ;;
  *) MAINTENANCE_LANG_NORM="de" ;;
esac

lang_is_de() { [ "$MAINTENANCE_LANG_NORM" = "de" ]; }
lang_is_en() { [ "$MAINTENANCE_LANG_NORM" = "en" ]; }

fmt_now_short() {
  if lang_is_de; then
    TZ="${TZ:-Europe/Berlin}" date '+%d.%m.%Y %H:%M'
  else
    TZ="${TZ:-Europe/Berlin}" date '+%Y-%m-%d %H:%M'
  fi
}

fmt_now_long() {
  if lang_is_de; then
    TZ="${TZ:-Europe/Berlin}" date '+%d.%m.%Y %H:%M Uhr'
  else
    TZ="${TZ:-Europe/Berlin}" date '+%Y-%m-%d %H:%M %Z'
  fi
}

fmt_backup_token() {
  token="$1"
  dd=$(printf '%s' "$token" | cut -c7-8)
  mm=$(printf '%s' "$token" | cut -c5-6)
  yyyy=$(printf '%s' "$token" | cut -c1-4)
  HH=$(printf '%s' "$token" | cut -c10-11)
  MM=$(printf '%s' "$token" | cut -c12-13)
  if lang_is_de; then
    printf '%s.%s.%s %s:%s' "$dd" "$mm" "$yyyy" "$HH" "$MM"
  else
    printf '%s-%s-%s %s:%s' "$yyyy" "$mm" "$dd" "$HH" "$MM"
  fi
}
