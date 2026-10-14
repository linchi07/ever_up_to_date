"""Exercise the real publisher with a local AWS substitute and real Go signing."""
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

MOCK_AWS = r'''#!/usr/bin/env python3
import hashlib,json,os,sys
from pathlib import Path
args=sys.argv[1:]
root=Path(os.environ['MOCK_S3'])
with (root/'calls.jsonl').open('a') as f: f.write(json.dumps(args)+'\n')
def arg(name): return args[args.index(name)+1]
def obj(key): return root/'objects'/key
def metadata(path):
 return json.loads(Path(str(path)+'.metadata').read_text()) if Path(str(path)+'.metadata').exists() else {}
if args[:2]==['s3api','head-object']:
 path=obj(arg('--key'))
 if not path.exists(): print('404 Not Found',file=sys.stderr);sys.exit(1)
 print(json.dumps({'ETag':'"'+hashlib.md5(path.read_bytes()).hexdigest()+'"','Metadata':metadata(path)}))
elif args[:2]==['s3','cp']:
 source,dest=args[2:4]
 if source.startswith('s3://'): source=obj(source.split('/',3)[3])
 if dest.startswith('s3://'): dest=obj(dest.split('/',3)[3])
 Path(dest).parent.mkdir(parents=True,exist_ok=True)
 Path(dest).write_bytes(Path(source).read_bytes())
elif args[:2]==['s3api','put-object']:
 path=obj(arg('--key'))
 if path.name=='appcast.json' and os.environ.get('MOCK_CONFLICT'):
  print('412 Precondition Failed',file=sys.stderr);sys.exit(1)
 if '--if-none-match' in args and path.exists(): print('412 Precondition Failed',file=sys.stderr);sys.exit(1)
 if '--if-match' in args:
  etag='"'+hashlib.md5(path.read_bytes()).hexdigest()+'"' if path.exists() else ''
  if arg('--if-match')!=etag: print('412 Precondition Failed',file=sys.stderr);sys.exit(1)
 path.parent.mkdir(parents=True,exist_ok=True)
 path.write_bytes(Path(arg('--body')).read_bytes())
 if '--metadata' in args:
  key,value=arg('--metadata').split('=',1);Path(str(path)+'.metadata').write_text(json.dumps({key:value}))
 print('{}')
else: print('Unsupported mock command',args,file=sys.stderr);sys.exit(1)
'''

class ReleasePipelineTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        binary = self.directory / 'bin'
        binary.mkdir()
        (binary / 'aws').write_text(MOCK_AWS)
        (binary / 'aws').chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(PATH=f'{binary}{os.pathsep}{self.env["PATH"]}', MOCK_S3=str(self.directory),
            S3_BUCKET='test-bucket', S3_ENDPOINT_URL='https://storage.example.com',
            S3_PREFIX='updates', MANIFEST_URL='https://cdn.example.com/updates/appcast.json',
            APP_ID='com.example.app', BUILD_NAME='2.0.0', BUILD_NUMBER='20', RELEASE_CHANNEL='stable',
            ENABLE_ANDROID='true', ENABLE_WINDOWS='true', ENABLE_MACOS='true', ENABLE_IOS='true',
            IOS_STORE_URL='https://testflight.apple.com/join/test', IOS_PACKAGE_TYPE='testflight',
            PRIVATE_KEY=base64.b64encode(bytes(range(32))).decode())
        self.artifacts = self.directory / 'artifacts'
        for name, suffix in [('android-apk','apk'), ('windows-installer','exe'), ('macos-dmg','dmg')]:
            folder = self.artifacts / name
            folder.mkdir(parents=True)
            (folder / f'app.{suffix}').write_bytes(f'fixture-{name}'.encode())

    def publish(self, expected=0):
        result = subprocess.run(['bash', str(ROOT / 'scripts/common/publish_release.sh'), str(self.artifacts)],
            cwd=ROOT, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_complete_signed_release_and_idempotent_retry(self):
        self.publish()
        manifest_path = self.directory/'objects/updates/appcast.json'
        manifest = json.loads(manifest_path.read_text())
        channel = manifest['channels']['stable']
        self.assertEqual(channel['version'], '2.0.0')
        self.assertEqual(channel['build_number'], 20)
        self.assertEqual(set(channel['platforms']), {'android','windows','macos','ios'})
        for name in ('android','windows','macos'):
            target=channel['platforms'][name]
            obj=self.directory/'objects'/target['url'].split('https://cdn.example.com/',1)[1]
            self.assertTrue(obj.exists())
            self.assertEqual(target['sha256'],hashlib.sha256(obj.read_bytes()).hexdigest())
            self.assertEqual(len(base64.b64decode(target['signature_ed25519'])),64)
        calls=[json.loads(line) for line in (self.directory/'calls.jsonl').read_text().splitlines()]
        self.assertEqual(calls[-1][:2], ['s3api','put-object'])
        self.assertIn('--if-none-match',calls[-1])
        for call in calls: self.assertIn('--endpoint-url',call)
        self.publish()
        self.assertEqual(json.loads(manifest_path.read_text()),manifest)
        calls=[json.loads(line) for line in (self.directory/'calls.jsonl').read_text().splitlines()]
        self.assertIn('--if-match',calls[-1])

    def test_bad_key_or_failed_publication_does_not_change_discovery(self):
        self.publish()
        path=self.directory/'objects/updates/appcast.json'
        original=path.read_bytes()
        self.env['BUILD_NAME']='3.0.0'
        self.env['PRIVATE_KEY']='invalid'
        self.publish(expected=1)
        self.assertEqual(path.read_bytes(),original)
        self.env['PRIVATE_KEY']=base64.b64encode(bytes(range(32))).decode()
        self.env['MOCK_CONFLICT']='true'
        self.publish(expected=1)
        self.assertEqual(path.read_bytes(),original)

    def test_manual_and_tag_versions_are_consistent(self):
        for tag, version, channel in [('v1.2.3','1.2.3','stable'),('v1.2.3-beta.1','1.2.3-beta.1','beta')]:
            output=self.directory/'outputs'
            if output.exists(): output.unlink()
            self.env.update(RELEASE_TAG=tag,GITHUB_RUN_NUMBER='45',GITHUB_OUTPUT=str(output))
            result=subprocess.run(['bash',str(ROOT/'scripts/common/release_metadata.sh')],env=self.env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(output.read_text(),f'version={version}\nbuild_number=45\nchannel={channel}\n')

if __name__ == '__main__': unittest.main()
