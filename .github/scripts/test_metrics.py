"""Check backup-age calculation without contacting Docker or other services."""
from pathlib import Path
import re
import subprocess
import unittest

METRICS = Path(__file__).resolve().parents[2] / "minecraft_server/maintenance/www/cgi-bin/metrics.cgi"


class BackupAgeTests(unittest.TestCase):
    def ages(self, entries):
        # Load only the existing calculation function; the CGI's service probes
        # are outside this deterministic test and are never executed.
        source = METRICS.read_text()
        function = re.search(r"(?ms)^calc_ages\(\)\{.*?^\}", source)
        self.assertIsNotNone(function)
        result = subprocess.run(
            ["sh", "-c", function.group() + '\nNOW=1700000000\ncalc_ages "$1"\n', "metrics-test", entries],
            capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def test_recent_backup_reports_its_age(self):
        self.assertEqual(self.ages("1699999900 Survival.mcworld")[0], "100")

    def test_overall_age_uses_newest_world(self):
        result = self.ages("1699999970.0 First.mcworld\n1699999995.5 Second.mcworld")
        self.assertEqual(result[0], "5")
        self.assertEqual(set(result[1:]), {"First 30", "Second 5"})

    def test_empty_backup_list_is_unknown(self):
        self.assertEqual(self.ages(""), ["-1"])


if __name__ == "__main__":
    unittest.main()
