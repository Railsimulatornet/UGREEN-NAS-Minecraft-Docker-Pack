"""Test fail-closed scan orchestration with a mocked Docker/Trivy command."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('scan-maintenance-image.sh')
FAKE_SKOPEO = r'''#!/usr/bin/env python3
import hashlib,json,os,pathlib,sys
a=sys.argv[1:]; mode=os.environ['SCENARIO']
with open(os.environ['SELECTION_CALLS'],'a') as log: log.write(json.dumps(a)+'\n')
if 'copy' in a:
    if mode=='selection-error': sys.exit(1)
    arch=a[a.index('--override-arch')+1]
    if mode=='wrong-selection': arch='amd64' if arch=='arm64' else 'arm64'
    destination=pathlib.Path(a[-1].removeprefix('oci:')); destination.mkdir(parents=True)
    config=json.dumps({'os':'linux','architecture':arch}).encode()
    digest='sha256:'+hashlib.sha256(config).hexdigest()
    (destination/'config.json').write_bytes(config)
    (destination/'manifest.json').write_text(json.dumps({'schemaVersion':2,'config':{'digest':digest}}))
    sys.exit(0)
if a[0]=='inspect':
    destination=pathlib.Path(a[-1].removeprefix('oci:'))
    if '--raw' in a:
        if mode=='index-selection': print(json.dumps({'schemaVersion':2,'manifests':[]}))
        else: print((destination/'manifest.json').read_text())
    elif '--config' in a: print((destination/'config.json').read_text())
    else: sys.exit(2)
    sys.exit(0)
sys.exit(2)
'''
FAKE = r'''#!/usr/bin/env python3
import json,os,pathlib,sys
a=sys.argv[1:]
p=next(x for x in a if x.startswith('type=bind,src=') and x.endswith(',dst=/out'))
out=pathlib.Path(p[len('type=bind,src='):-len(',dst=/out')])
i=next(x for x in a if x.startswith('type=bind,src=') and x.endswith(',dst=/image,readonly'))
image=pathlib.Path(i[len('type=bind,src='):-len(',dst=/image,readonly')])
with open(os.environ['CALLS'],'a') as log: log.write(json.dumps(a)+'\n')
mode=os.environ['SCENARIO']; gate='--exit-code' in a; convert='convert' in a
if mode=='scan-error' and not gate and not convert: sys.exit(1)
if mode=='convert-error' and convert: sys.exit(1)
if mode!='missing-report' and not (mode=='missing-gate-report' and gate):
    path=out/pathlib.Path(a[a.index('--output')+1]).name
    config=json.loads((image/'config.json').read_text())
    digest=json.loads((image/'manifest.json').read_text())['config']['digest']
    if mode=='wrong-scan-architecture': config['architecture']='amd64' if config['architecture']=='arm64' else 'arm64'
    if mode=='wrong-scan-image': digest='sha256:'+('0'*64)
    data={'SchemaVersion':2,'Metadata':{'OS':{'Family':'alpine'},'ImageConfig':config,'ImageID':digest},'Results':[{'Type':'alpine'}]}
    if mode=='unknown-os': data['Metadata']={}
    path.write_text(json.dumps(data) if path.suffix=='.json' else 'test report\n')
if gate: sys.exit({'findings':42,'eol':43,'gate-error':1}.get(mode,0))
'''


class GateTests(unittest.TestCase):
    def case(self, mode, platform='linux/amd64'):
        with tempfile.TemporaryDirectory(prefix='maintenance gate ') as tmp:
            root=Path(tmp); (root/'image').mkdir()
            for f in ('index.json','oci-layout'): (root/'image'/f).write_text('{}')
            # An unselected multi-platform input exposes its first (AMD64) image.
            config=json.dumps({'os':'linux','architecture':'amd64'}).encode()
            (root/'image/config.json').write_bytes(config)
            (root/'image/manifest.json').write_text(json.dumps({
                'schemaVersion':2,'config':{'digest':'sha256:'+hashlib.sha256(config).hexdigest()}}))
            (root/'docker').write_text(FAKE); (root/'docker').chmod(0o755)
            (root/'skopeo').write_text(FAKE_SKOPEO); (root/'skopeo').chmod(0o755)
            env=dict(os.environ, PATH=str(root)+':'+os.environ['PATH'], SCENARIO=mode,
                     CALLS=str(root/'calls'), SELECTION_CALLS=str(root/'selection-calls'),
                     TRIVY_CACHE_DIR=str(root/'cache'))
            p=subprocess.run(['bash',str(SCRIPT),str(root/'image'),platform,str(root/'out')],
                             env=env,capture_output=True,text=True,timeout=30)
            calls=[json.loads(x) for x in (root/'calls').read_text().splitlines()] if (root/'calls').exists() else []
            selections=[json.loads(x) for x in (root/'selection-calls').read_text().splitlines()] if (root/'selection-calls').exists() else []
            return p,calls,selections

    def test_clean_both_platforms(self):
        for platform in ('linux/amd64','linux/arm64'):
            p,calls,selections=self.case('clean',platform)
            self.assertEqual(p.returncode,0,p.stderr)
            self.assertEqual(len(calls),4)
            self.assertNotIn('--ignore-unfixed',calls[0])
            self.assertIn('--exit-code',calls[-1])
            self.assertIn('--skip-db-update',calls[-1])
            self.assertIn(platform,calls[-1])
            self.assertTrue(all(not any('docker.sock' in x for x in c) for c in calls))
            copies=[call for call in selections if 'copy' in call]
            self.assertEqual(len(copies),1)
            self.assertEqual(copies[0][copies[0].index('--override-arch')+1],platform.split('/')[1])
            self.assertEqual(copies[0][copies[0].index('--override-os')+1],'linux')
            self.assertIn('--preserve-digests',copies[0])
            self.assertNotIn('--all',copies[0])
            self.assertTrue(copies[0][-2].startswith('oci:'))
            selected=copies[0][-1].removeprefix('oci:')
            self.assertTrue(all('type=bind,src='+selected+',dst=/image,readonly' in call for call in calls))

    def test_failed_or_wrong_platform_selection_never_scans(self):
        for mode in ('selection-error','wrong-selection','index-selection'):
            for platform in ('linux/amd64','linux/arm64'):
                with self.subTest(mode=mode,platform=platform):
                    p,calls,_=self.case(mode,platform)
                    self.assertNotEqual(p.returncode,0)
                    self.assertEqual(calls,[])

    def test_scanner_must_report_selected_architecture_and_image(self):
        for mode in ('wrong-scan-architecture','wrong-scan-image'):
            for platform in ('linux/amd64','linux/arm64'):
                with self.subTest(mode=mode,platform=platform):
                    p,calls,_=self.case(mode,platform)
                    self.assertNotEqual(p.returncode,0)
                    self.assertEqual(len(calls),1)

    def test_findings_block(self): self.assertEqual(self.case('findings')[0].returncode,42)
    def test_eol_blocks(self): self.assertEqual(self.case('eol')[0].returncode,43)
    def test_scan_failure_blocks(self): self.assertNotEqual(self.case('scan-error')[0].returncode,0)
    def test_conversion_failure_blocks(self): self.assertNotEqual(self.case('convert-error')[0].returncode,0)
    def test_gate_failure_blocks(self): self.assertNotEqual(self.case('gate-error')[0].returncode,0)
    def test_missing_report_blocks(self): self.assertNotEqual(self.case('missing-report')[0].returncode,0)
    def test_missing_gate_report_blocks(self): self.assertNotEqual(self.case('missing-gate-report')[0].returncode,0)
    def test_unknown_os_blocks(self): self.assertNotEqual(self.case('unknown-os')[0].returncode,0)
    def test_unknown_platform_blocks(self): self.assertNotEqual(self.case('clean','linux/386')[0].returncode,0)


if __name__=='__main__': unittest.main()
