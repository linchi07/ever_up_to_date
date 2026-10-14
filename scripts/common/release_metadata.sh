#!/usr/bin/env bash
set -euo pipefail
# Emit a single normalized version/build for every build and the manifest.
python3 - <<'PY'
import os, re
version = os.environ.get('INPUT_VERSION') or os.environ.get('RELEASE_TAG', '')
version = version.removeprefix('v')
if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?', version):
    raise SystemExit('Provide a semantic version or push a v<version> tag')
if '-' in version.split('+')[0] and any(re.fullmatch(r'0\d+', p) for p in version.split('+')[0].split('-', 1)[1].split('.')):
    raise SystemExit('Invalid prerelease number')
build = os.environ.get('INPUT_BUILD_NUMBER') or os.environ['GITHUB_RUN_NUMBER']
if not build.isdigit() or int(build) < 1:
    raise SystemExit('Build number must be positive')
channel = os.environ.get('INPUT_CHANNEL') or ('beta' if '-' in version.split('+')[0] else 'stable')
if channel not in ('stable', 'beta'):
    raise SystemExit('Channel must be stable or beta')
with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
    output.write(f'version={version}\nbuild_number={build}\nchannel={channel}\n')
PY
