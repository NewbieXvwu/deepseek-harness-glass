#!/usr/bin/env python3
"""Negative self-tests for authenticated Host fixture privacy/shape gate."""
from __future__ import annotations
import json, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / 'glass/ci/check-authenticated-host-fixtures.py'
BASE = ROOT / 'glass/Sources/Core/Resources/official-authenticated-host-fixtures.json'

def invoke(path: Path):
    return subprocess.run([sys.executable, str(CHECK), '--fixture', str(path)], text=True, capture_output=True, check=False)

def main() -> None:
    baseline = invoke(BASE)
    if baseline.returncode != 0: raise SystemExit('baseline fixture failed:\n' + baseline.stdout + baseline.stderr)
    original = json.loads(BASE.read_text(encoding='utf-8'))
    with tempfile.TemporaryDirectory(prefix='dsh-auth-fixture-gate-') as td:
        td = Path(td)
        cases = []
        leaked = json.loads(json.dumps(original)); leaked['leak'] = 'Cookie: dsh_session=secret'; cases.append(('cookie', leaked, 'forbidden'))
        wrong = json.loads(json.dumps(original)); wrong['officialSourceCommit'] = 'b150a55'; cases.append(('commit', wrong, 'source commit'))
        drift = json.loads(json.dumps(original)); drift['streamDelta']['frames'].reverse(); cases.append(('stream', drift, 'delta sequence'))
        for name, doc, needle in cases:
            path = td / f'{name}.json'; path.write_text(json.dumps(doc), encoding='utf-8')
            result = invoke(path)
            if result.returncode == 0 or needle not in (result.stdout + result.stderr):
                raise SystemExit(f'{name} negative fixture unexpectedly passed: {result.stdout}{result.stderr}')
    print('Authenticated Host fixture gate self-test passed.')

if __name__ == '__main__': main()
