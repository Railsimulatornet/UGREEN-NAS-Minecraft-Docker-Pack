"""Check import boundaries without loading service setup or accessing game data."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "minecraft_server/maintenance/scripts/addons_update.sh").read_text()
VALID_UUID = "5772ca6e-ea65-417d-be87-c3e8203d941c"
INVALID_UUIDS = ["../../outside", "../../../outside", "/tmp/outside", "..", "",
                "not-a-uuid", VALID_UUID + "/child", VALID_UUID + "\n",
                "valid\t../../outside", 123, [VALID_UUID]]


def functions(*names):
    definitions = []
    for name in names:
        match = re.search(rf"(?ms)^{name}\(\) \{{.*?^\}}", SOURCE)
        if match:
            definitions.append(match.group())
        elif name != "valid_pack_uuid":
            raise AssertionError(f"Missing production function: {name}")
    return "\n".join(definitions)


class AddonImportTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.world = self.root / "target" / "world"
        self.world.mkdir(parents=True)
        self.audit = self.root / "transfer-calls"

    def manifest(self, uuid, kind="data", legacy=False):
        metadata = {"uuid": uuid, "name": "fixture", "version": [1, 2, 3]}
        payload = metadata if legacy else {"header": metadata}
        payload["modules"] = [{"type": kind}]
        path = self.source / "manifest.json"
        path.write_text(json.dumps(payload))
        return path

    def run_functions(self, names, commands, *args):
        setup = r'''
set -euo pipefail
LOG_PREFIX='test'; WARN_PREFIX='test'; ERR_PREFIX='test'
RSYNC_FLAGS_BASE='-a --delete --checksum --omit-dir-times'
RSYNC_PERM_FLAGS='--chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r'
data_root() { printf '%s\n' "$1"; }
bp_dir() { printf '%s/behavior_packs\n' "$1"; }
rp_dir() { printf '%s/resource_packs\n' "$1"; }
scan_pack_dir() { find "$1" -type f -iname manifest.json -print0; }
rsync_would_change() { return 0; }
rsync_chown_for_root() { :; }
chown() { :; }
chmod() { :; }
rsync() { printf '%s\n' "${@: -1}" >> "$TEST_AUDIT"; }
'''
        return subprocess.run(
            ["bash", "-c", functions(*names) + setup + commands, "test", *map(str, args)],
            env={**os.environ, "TEST_AUDIT": str(self.audit)},
            capture_output=True, text=True, timeout=5)

    def test_parser_rejects_invalid_identifiers(self):
        for uuid in INVALID_UUIDS:
            with self.subTest(uuid=uuid):
                result = self.run_functions(("parse_manifest",), 'parse_manifest "$1"', self.manifest(uuid))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(result.stdout.startswith("ERROR\t"), result.stdout)

    def test_parser_preserves_supported_identifiers_and_pack_kinds(self):
        for uuid in (VALID_UUID, VALID_UUID.upper()):
            for module, kind in (("data", "behavior"), ("script", "behavior"), ("resources", "resource")):
                for legacy in (False, True):
                    with self.subTest(uuid=uuid, module=module, legacy=legacy):
                        result = self.run_functions(("parse_manifest",), 'parse_manifest "$1"', self.manifest(uuid, module, legacy))
                        self.assertEqual(result.returncode, 0, result.stderr)
                        fields = result.stdout.rstrip("\n").split("\t")
                        self.assertEqual(fields[0], "OK")
                        self.assertEqual(fields[2:7], [kind, uuid, "1", "2", "3"])

    def test_copy_refuses_invalid_identifiers_before_writing(self):
        for uuid in INVALID_UUIDS:
            if not isinstance(uuid, str):
                continue
            with self.subTest(uuid=uuid):
                result = self.run_functions(("valid_pack_uuid", "copy_pack"),
                                            'copy_pack "$1" "$2" behavior "$3"',
                                            self.source, self.world, uuid)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.audit.exists())
                self.assertEqual(list(self.world.iterdir()), [])
                self.assertFalse((self.root / "outside").exists())

    def test_valid_copy_stays_in_the_selected_pack_directory(self):
        for kind in ("behavior", "resource"):
            with self.subTest(kind=kind):
                result = self.run_functions(("valid_pack_uuid", "copy_pack"),
                                            'copy_pack "$1" "$2" "$3" "$4"',
                                            self.source, self.world, kind, VALID_UUID)
                self.assertEqual(result.returncode, 0, result.stderr)
                target = self.world / f"{kind}_packs" / VALID_UUID
                self.assertTrue(target.is_dir())
                self.assertEqual(Path(self.audit.read_text().splitlines()[-1]).resolve(), target)

    def test_manifest_to_copy_chain_rejects_path_components(self):
        self.manifest("../../outside")
        result = self.run_functions(("parse_manifest", "valid_pack_uuid", "collect_packs", "copy_pack"), r'''
collect_packs "$1" both
for uuid in "${!found_b[@]}"; do
    IFS=: read -r a b c directory name <<< "${found_b[$uuid]}"
    copy_pack "$directory" "$2" behavior "$uuid"
done
''', self.source, self.world)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.audit.exists())
        self.assertEqual(list(self.world.iterdir()), [])

    def test_collector_revalidates_serialized_identifiers(self):
        self.manifest(VALID_UUID)
        result = self.run_functions(("valid_pack_uuid", "collect_packs"), r'''
parse_manifest() { printf 'OK\tfixture\tbehavior\t../../outside\t1\t0\t0\tfixture\n'; }
collect_packs "$1" both
printf 'count=%s\n' "${#found_b[@]}"
''', self.source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("count=0", result.stdout)


if __name__ == "__main__":
    unittest.main()
