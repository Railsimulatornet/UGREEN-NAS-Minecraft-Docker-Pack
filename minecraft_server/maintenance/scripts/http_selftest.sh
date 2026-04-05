#!/bin/sh
# Copyright Roman Glos 2026
set -eu

[ -f /scripts/lib_i18n.sh ] && . /scripts/lib_i18n.sh
WEB_PORT="8081"

if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
  H1='=== BENUTZER & DATUM'
  H2='=== PAKETE'
  H3='=== PROZESSE'
  H4='=== PORTS'
  H5='=== DATEISYSTEM: /www & CGI'
  H6='=== LOKALER HTTP-TEST (HEADER)'
  H7='=== FERTIG'
  NO_LIGHTTPD='KEIN lighttpd gefunden'
  CGI_LABEL='---- CGI ----'
  STATIC_LABEL='---- ROOT / INDEX ----'
else
  H1='=== WHOAMI & DATE'
  H2='=== PACKAGES'
  H3='=== PROCESSES'
  H4='=== PORTS'
  H5='=== FILESYSTEM: /www & CGI'
  H6='=== LOCAL HTTP TEST (HEADERS)'
  H7='=== DONE'
  NO_LIGHTTPD='NO lighttpd'
  CGI_LABEL='---- CGI ----'
  STATIC_LABEL='---- ROOT / INDEX ----'
fi

echo "$H1"
id; date

echo "$H2"
command -v lighttpd || echo "$NO_LIGHTTPD"
lighttpd -v || true

echo "$H3"
ps -ef | sed -n '1,120p'

echo "$H4"
(ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null || true) | sed -n '1,120p'

echo "$H5"
ls -ld /www /www/cgi-bin || true
ls -l /www/cgi-bin || true
head -n 3 /www/cgi-bin/metrics.cgi || true

echo "$H6"
(printf '%s\n' "$CGI_LABEL"; (wget -S -O - http://127.0.0.1:${WEB_PORT}/cgi-bin/metrics.cgi 2>&1 | sed -n '1,20p') || true)
(printf '%s\n' "$STATIC_LABEL"; (wget -S -O - http://127.0.0.1:${WEB_PORT}/ 2>&1 | sed -n '1,20p') || true)

echo "$H7"
