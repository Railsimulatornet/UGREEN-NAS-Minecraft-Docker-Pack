#!/usr/bin/env python3
"""Read-only local checks; never restart containers or execute maintenance jobs."""
import http.client
from pathlib import Path
import re
import sys

REQUIRED_SCRIPTS = ('notify.sh', 'restart_daily.sh', 'addons_update.sh', 'watchdog.sh')


def check_http(host='127.0.0.1', port=8081):
    connection = http.client.HTTPConnection(host, port, timeout=3)
    try:
        connection.request('GET', '/health.txt', headers={'Connection': 'close'})
        response = connection.getresponse()
        body = response.read(128)
        if response.status != 200 or len(body) >= 128 or body.strip() != b'OK':
            raise ValueError('Der lokale Statusdienst antwortet nicht wie erwartet.')
    finally:
        connection.close()


def valid_cron_field(value, lower, upper):
    if len(value) > 64:
        return False
    for part in value.split(','):
        base, separator, step = part.partition('/')
        if separator and (not step.isascii() or not step.isdigit() or not 1 <= int(step) <= upper + 1):
            return False
        if base == '*':
            continue
        limits = base.split('-')
        if len(limits) not in (1, 2) or any(not n.isascii() or not n.isdigit() for n in limits):
            return False
        numbers = [int(n) for n in limits]
        if any(n < lower or n > upper for n in numbers) or numbers != sorted(numbers):
            return False
    return True


def check_runtime(root=Path('/'), http_check=check_http):
    if (root / 'proc/1/comm').read_text().strip() != 'crond':
        raise ValueError('Die Zeitsteuerung läuft nicht als Hauptprozess.')
    cron_file = root / 'etc/crontabs/root'
    if not cron_file.is_file() or cron_file.stat().st_size > 65536:
        raise ValueError('Die geladene Zeitplanung fehlt oder ist ungültig.')
    entries = []
    for line in cron_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#') or re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', line):
            continue
        fields = line.split(None, 5)
        ranges = ((0, 59), (0, 23), (1, 31), (1, 12), (0, 7))
        if len(fields) != 6 or not all(valid_cron_field(value, *limits)
                                       for value, limits in zip(fields[:5], ranges)):
            raise ValueError('Ein Wartungstermin ist ungültig.')
        entries.append(fields[5])
    for name in REQUIRED_SCRIPTS:
        script = root / 'scripts' / name
        if not script.is_file() or not script.stat().st_size:
            raise ValueError('Ein benötigtes Wartungsskript fehlt.')
        if not any(re.search(r'(?:^|\s)/scripts/' + re.escape(name) + r'(?:\s|$)', entry)
                   for entry in entries):
            raise ValueError('Ein benötigter Wartungstermin fehlt.')
    if not (root / 'www/cgi-bin/metrics.cgi').is_file():
        raise ValueError('Die lokale Statusausgabe fehlt.')
    http_check()


def main():
    try:
        check_runtime()
    except (OSError, ValueError, http.client.HTTPException):
        print('Die Betriebsprüfung der Minecraft-Wartung ist fehlgeschlagen.', file=sys.stderr)
        return 1
    print('Zeitsteuerung, Wartungsskripte und lokaler Statusdienst sind erreichbar.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
