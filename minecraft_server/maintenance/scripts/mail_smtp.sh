#!/bin/sh
# Copyright Roman Glos 2026
# maintenance/scripts/mail_smtp.sh
# Send mail via SMTP using Python3 (STARTTLS/SMTPS)
# Usage:  mail_smtp.sh "Subject" < body.html

set -eu
[ -f /scripts/lib_i18n.sh ] && . /scripts/lib_i18n.sh

if command -v lang_is_de >/dev/null 2>&1 && lang_is_de; then
  DEFAULT_SUBJECT="Minecraft Benachrichtigung"
  ERR_SMTP_HOST='[mail_smtp] SMTP_HOST fehlt'
  ERR_MAIL_FROM='[mail_smtp] MAIL_FROM fehlt'
  ERR_MAIL_TO='[mail_smtp] MAIL_TO fehlt'
else
  DEFAULT_SUBJECT="Minecraft Notification"
  ERR_SMTP_HOST='[mail_smtp] SMTP_HOST missing'
  ERR_MAIL_FROM='[mail_smtp] MAIL_FROM missing'
  ERR_MAIL_TO='[mail_smtp] MAIL_TO missing'
fi

SUBJECT="${1:-$DEFAULT_SUBJECT}"

SMTP_HOST="${SMTP_HOST:-}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-}"
SMTP_PASS="${SMTP_PASS:-}"
SMTP_USE_TLS="${SMTP_USE_TLS:-0}"
SMTP_STARTTLS="${SMTP_STARTTLS:-1}"

MAIL_FROM="${MAIL_FROM:-}"
MAIL_TO_RAW="${MAIL_TO:-}"
MAIL_REPLY_TO="${MAIL_REPLY_TO:-}"

[ -n "$SMTP_HOST" ] || { echo "$ERR_SMTP_HOST" >&2; exit 2; }
[ -n "$MAIL_FROM" ] || { echo "$ERR_MAIL_FROM" >&2; exit 2; }
[ -n "$MAIL_TO_RAW" ] || { echo "$ERR_MAIL_TO" >&2; exit 2; }

MAIL_TO_NORM="$(printf "%s" "$MAIL_TO_RAW" | tr ';' ',' | tr ' ' ',')"

TMP_BODY="$(mktemp /tmp/mail_body.XXXXXX)"
cat > "$TMP_BODY" 2>/dev/null || true

export PYTHONUNBUFFERED=1
export MAIL_SUBJECT="$SUBJECT"
export MAIL_TO="$MAIL_TO_NORM"
export MAINTENANCE_LANG_NORM="${MAINTENANCE_LANG_NORM:-de}"

python3 - "$TMP_BODY" <<'PY'
import os, sys, ssl, smtplib, re
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.header import Header
from html import unescape

lang = (os.environ.get("MAINTENANCE_LANG_NORM") or "de").lower()
host = os.environ.get("SMTP_HOST","")
port = int(os.environ.get("SMTP_PORT","587"))
user = os.environ.get("SMTP_USER") or None
password = os.environ.get("SMTP_PASS") or None
use_tls = os.environ.get("SMTP_USE_TLS","0").lower() in ("1","true","yes","y")
starttls = os.environ.get("SMTP_STARTTLS","1").lower() in ("1","true","yes","y")

mail_from = os.environ.get("MAIL_FROM","")
rcpts_raw = os.environ.get("MAIL_TO","")
reply_to = os.environ.get("MAIL_REPLY_TO","") or ""
subject = os.environ.get("MAIL_SUBJECT","Minecraft Notification")

rcpts = [r.strip() for r in rcpts_raw.replace(';',',').split(',') if r.strip()]
if not host or not mail_from or not rcpts:
    msg = "[mail_smtp] ERR: fehlender Host/Absender/Empfänger" if lang == "de" else "[mail_smtp] ERR: missing host/from/recipients"
    print(msg, file=sys.stderr)
    sys.exit(2)

body_path = sys.argv[1] if len(sys.argv) > 1 else ""
try:
    raw = open(body_path, "rb").read()
except Exception:
    raw = b""

body = raw.decode("utf-8", errors="replace").strip()
if not body:
    body = "(leerer E-Mail-Text)\n" if lang == "de" else "(empty email body)\n"

is_html = bool(re.search(r"<\s*[a-z][a-z0-9]*\b[^>]*>", body, flags=re.I))

if is_html and "<html" not in body.lower():
    body_html = (
        "<html><body style=\"font-family:Segoe UI,Arial,Helvetica,sans-serif;"
        "font-size:13px;color:#111;background:#fff;\">"
        + body +
        "</body></html>"
    )
else:
    body_html = body if is_html else None

if is_html:
    txt = re.sub(r"(?is)<(script|style).*?>.*?</\1>", "", body_html or body)
    txt = re.sub(r"(?s)<br\s*/?>", "\n", txt)
    txt = re.sub(r"(?s)</p\s*>", "\n\n", txt)
    txt = re.sub(r"(?s)<[^>]+>", "", txt)
    txt = unescape(txt)
    plain = re.sub(r"\n{3,}", "\n\n", txt).strip() + "\n"
else:
    plain = body if body.endswith("\n") else (body + "\n")

msg = MIMEMultipart("alternative")
msg["From"] = mail_from
msg["To"] = ", ".join(rcpts)
msg["Subject"] = str(Header(subject, "utf-8"))
if reply_to:
    msg["Reply-To"] = reply_to

msg.attach(MIMEText(plain, "plain", "utf-8"))
if is_html and body_html:
    msg.attach(MIMEText(body_html, "html", "utf-8"))

ctx = ssl.create_default_context()

try:
    if use_tls:
        s = smtplib.SMTP_SSL(host, port, timeout=20, context=ctx)
        s.ehlo()
    else:
        s = smtplib.SMTP(host, port, timeout=20)
        s.ehlo()
        if starttls:
            s.starttls(context=ctx)
            s.ehlo()
    if user and password:
        s.login(user, password)
    s.sendmail(mail_from, rcpts, msg.as_string())
    s.quit()
except Exception as e:
    prefix = "[mail_smtp] FEHLER:" if lang == "de" else "[mail_smtp] ERR:"
    print(prefix, e, file=sys.stderr)
    sys.exit(1)
else:
    print("[mail_smtp] OK")
PY

rm -f "$TMP_BODY"
