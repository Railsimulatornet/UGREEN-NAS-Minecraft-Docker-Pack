"""Registry failures and fixed-tag protection, using a local registry fixture."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("publish-maintenance-image.sh")
FAKE = r'''#!/usr/bin/env python3
import hashlib,json,os,pathlib,sys
a=sys.argv[1:]; scenario=os.environ['SCENARIO']; state=pathlib.Path(os.environ['PUSHES'])
with open(os.environ['CALLS'],'a') as f: f.write(json.dumps(a)+'\n')
if a[0]=='login': sys.stdin.read(); sys.exit(0)
if a[0]=='manifest-digest':
    print('sha256:'+hashlib.sha256(pathlib.Path(a[-1]).read_bytes()).hexdigest()); sys.exit(0)
if a[0]=='copy':
    with state.open('a') as f: f.write(a[-1]+'\n')
    sys.exit(1 if scenario=='copy-error' else 0)
if a[0]=='inspect':
    target=a[-1]
    if target.startswith('oci-archive:'): print('fixture-manifest'); sys.exit(0)
    pushed=state.read_text().splitlines() if state.exists() else []
    if target in pushed:
        print('changed' if scenario=='corrupt-transfer' else 'fixture-manifest'); sys.exit(0)
    if scenario=='auth-error': print('unauthorized',file=sys.stderr); sys.exit(1)
    if scenario=='network-error': print('connection timeout',file=sys.stderr); sys.exit(1)
    if scenario=='conflicting-version': print('old-manifest'); sys.exit(0)
    if scenario=='identical-version': print('fixture-manifest'); sys.exit(0)
    print('manifest unknown',file=sys.stderr); sys.exit(1)
sys.exit(2)
'''


class PublishTests(unittest.TestCase):
    def case(self, scenario, mode="release", version="1.0.3"):
        with tempfile.TemporaryDirectory(prefix="maintenance publish ") as tmp:
            root = Path(tmp)
            (root / "image.tar").write_text("fixture")
            (root / "skopeo").write_text(FAKE)
            (root / "skopeo").chmod(0o755)
            env = dict(os.environ, PATH=str(root) + ":" + os.environ["PATH"],
                       SCENARIO=scenario, CALLS=str(root / "calls"), PUSHES=str(root / "pushes"),
                       DOCKERHUB_USERNAME="fixture", DOCKERHUB_TOKEN="fixture")
            result = subprocess.run(
                ["bash", str(SCRIPT), str(root / "image.tar"), version, mode],
                env=env, capture_output=True, text=True, timeout=30
            )
            calls = [json.loads(line) for line in (root / "calls").read_text().splitlines()] if (root / "calls").exists() else []
            return result, calls

    def test_new_version_is_verified_before_moving_aliases(self):
        result, calls = self.case("new-version")
        self.assertEqual(result.returncode, 0, result.stderr)
        copies = [call for call in calls if call[0] == "copy"]
        self.assertEqual([call[-1].rsplit(":", 1)[1] for call in copies], ["1.0.3", "1.0", "latest"])
        for call in copies:
            self.assertIn("--all", call)
            self.assertIn("--preserve-digests", call)
            self.assertTrue(call[-2].startswith("oci-archive:"))

    def test_existing_identical_version_is_not_rewritten(self):
        result, calls = self.case("identical-version")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call[0] == "copy" and call[-1].endswith(":1.0.3") for call in calls))

    def test_conflicting_version_blocks_every_write(self):
        result, calls = self.case("conflicting-version")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[0] == "copy" for call in calls))

    def test_registry_errors_are_not_missing_releases(self):
        for scenario in ("auth-error", "network-error"):
            result, calls = self.case(scenario)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(any(call[0] == "copy" for call in calls))

    def test_failed_or_corrupt_copy_blocks_aliases(self):
        for scenario in ("copy-error", "corrupt-transfer"):
            result, calls = self.case(scenario)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(any(call[0] == "copy" and call[-1].endswith((":1.0", ":latest")) for call in calls))

    def test_weekly_build_changes_only_latest(self):
        result, calls = self.case("conflicting-version", mode="latest")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[-1].rsplit(":", 1)[1] for call in calls if call[0] == "copy"], ["latest"])

    def test_invalid_mode_or_version_never_contacts_registry(self):
        for mode, version in (("none", "1.0.3"), ("release", "latest"), ("release", "1.0.3\nother=value")):
            result, calls = self.case("new-version", mode=mode, version=version)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
