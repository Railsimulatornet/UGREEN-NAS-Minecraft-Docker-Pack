"""Verify the operational check using isolated files and a real local HTTP server."""
import http.server
import importlib.util
from pathlib import Path
import tempfile
import threading
import unittest

SOURCE = Path(__file__).resolve().parents[2] / 'minecraft_server/health/maintenance_health.py'
spec = importlib.util.spec_from_file_location('maintenance_health', SOURCE)
health = importlib.util.module_from_spec(spec)
spec.loader.exec_module(health)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name, content in {'proc/1/comm': 'crond\n', 'www/cgi-bin/metrics.cgi': '#!/bin/sh\n',
                              'etc/crontabs/root': 'TZ=Europe/Berlin\n' + '\n'.join(
                                  '* * * * * /bin/sh /scripts/' + name for name in health.REQUIRED_SCRIPTS),
                              **{'scripts/' + name: '#!/bin/sh\n' for name in health.REQUIRED_SCRIPTS}}.items():
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)

    def test_ready_runtime_uses_http_probe(self):
        called = []
        health.check_runtime(self.root, lambda: called.append(True))
        self.assertEqual(called, [True])

    def test_process_alone_is_not_enough(self):
        (self.root / 'etc/crontabs/root').write_text('* * * * * echo alive\n')
        with self.assertRaises(ValueError):
            health.check_runtime(self.root, lambda: None)

    def test_missing_script_or_status_page_blocks(self):
        for path in ('scripts/watchdog.sh', 'www/cgi-bin/metrics.cgi'):
            target = self.root / path
            text = target.read_text()
            target.unlink()
            with self.assertRaises(ValueError):
                health.check_runtime(self.root, lambda: None)
            target.write_text(text)

    def test_wrong_main_process_blocks(self):
        (self.root / 'proc/1/comm').write_text('sh\n')
        with self.assertRaises(ValueError):
            health.check_runtime(self.root, lambda: None)

    def test_http_failure_is_not_hidden_by_running_cron(self):
        def fail(): raise ConnectionRefusedError('fixture')
        with self.assertRaises(ConnectionRefusedError):
            health.check_runtime(self.root, fail)

    def test_cron_field_limits_are_checked(self):
        for value in ('60', '*/0', '2-1', 'x', '1/999'):
            self.assertFalse(health.valid_cron_field(value, 0, 59))
        for value in ('*', '*/20', '10,40', '5-25/5'):
            self.assertTrue(health.valid_cron_field(value, 0, 59))

    def test_invalid_crontab_fails(self):
        (self.root / 'etc/crontabs/root').write_text('invalid\n')
        with self.assertRaises(ValueError):
            health.check_runtime(self.root, lambda: None)


class HttpTests(unittest.TestCase):
    def test_expected_content_required(self):
        class Handler(http.server.BaseHTTPRequestHandler):
            status, body = 200, b'OK\n'
            def do_GET(self):
                self.send_response(type(self).status)
                self.end_headers()
                self.wfile.write(type(self).body)
            def log_message(self, *_args): pass
        server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            health.check_http(port=server.server_port)
            for status, body in ((500, b'OK'), (200, b'not ready'), (302, b'OK')):
                Handler.status, Handler.body = status, body
                with self.assertRaises(ValueError):
                    health.check_http(port=server.server_port)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
