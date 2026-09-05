#!/usr/bin/env python3
"""Validate the captured rc.1 authenticated Host fixture and its privacy invariants."""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = ROOT / 'glass/Sources/Core/Resources/official-authenticated-host-fixtures.json'
BUILD = ROOT / 'glass/Sources/Spec/OfficialUISpec/official-ui-spec-build.json'
LOCK = ROOT / 'glass/ci/dsh-backend-payload/package-lock.json'
FORBIDDEN = [
    re.compile(r'(?i)(?:[?&]token=|set-cookie|\bcookie\b\s*[:=]|authorization\s*[:=]|bearer\s+)'),
    re.compile(r'(?i)deepseek_api_key\s*[:=]\s*[^\s,}\]]+'),
    re.compile(r'/(?:Users|home|mnt/data)/[^\s"\\]+'),
]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--fixture', type=Path, default=DEFAULT)
    args = parser.parse_args()
    fixture = json.loads(args.fixture.read_text(encoding='utf-8'))
    build = json.loads(BUILD.read_text(encoding='utf-8'))
    require(fixture.get('schemaVersion') == 1, 'schemaVersion must be 1')
    require(fixture.get('officialSourceCommit') == build['sourceCommit'], 'fixture source commit differs from locked rc.1')
    require(fixture.get('fixtureRevision') == 'official-a66e470-authenticated-host-r1', 'fixture revision is not rc.1')
    require(fixture.get('payload', {}).get('dshVersion') == '0.1.2-rc.1', 'fixture payload is not exact rc.1')
    expected_lock = 'sha256:' + hashlib.sha256(LOCK.read_bytes()).hexdigest()
    require(fixture.get('payload', {}).get('packageLockSHA256') == expected_lock, 'fixture payload lock digest drifted')
    policy = fixture.get('secretPolicy', {})
    for key in ('persistedLaunchToken', 'persistedCookie', 'persistedAuthorization', 'persistedUserCredentials', 'persistedRealWorkspacePath'):
        require(policy.get(key) is False, f'{key} must remain false')

    auth = fixture.get('authentication', {})
    require(auth == {'bootstrapStatus': 303, 'redirectLocation': '/', 'cookieInstalled': True, 'authenticatedRootStatus': 200}, 'auth bootstrap facts drifted')
    unary = fixture.get('unary', {})
    require(unary.get('endpoint') == 'session/list', 'unary fixture must use session/list')
    assert_remote_pair(unary, 'fixture-session-list', 'session/list', True)
    require(unary['response']['result']['value'] == {'items': []}, 'fresh session/list is not empty')

    opening = fixture.get('streamOpening', {})
    require(opening.get('eventRequest', {}).get('endpoint') == '$events', '$events opening missing')
    event_ready = opening.get('eventReady', {})
    require(event_ready.get('type') == 'item' and event_ready.get('streamId') == 'fixture-events', '$events mux carrier drifted')
    require(event_ready.get('value', {}).get('type') == 'ready', '$events first item must be ready')
    require(event_ready.get('value', {}).get('clientId') == '<fixture-client-id>', 'event client id was not normalized')
    require(event_ready.get('value', {}).get('host', {}).get('home') == '<fixture-home>', 'Host home was not normalized')
    baseline = opening.get('workspaceBaseline', {})
    require(baseline.get('value') == {'type': 'baseline', 'value': {'items': [], 'archivedSessionIds': []}}, 'workspace/follow opening baseline drifted')

    delta = fixture.get('streamDelta', {})
    frames = delta.get('frames', [])
    require([frame.get('value', {}).get('type') for frame in frames] == ['upsert', 'order'], 'workspace delta sequence must be upsert then order')
    require(frames[0]['value']['workspace']['workspaceId'] == '<fixture-workspace-id>', 'workspace id was not normalized')
    require(frames[0]['value']['workspace']['path'] == '<fixture-workspace>', 'workspace path was not normalized')
    require(frames[0]['value']['workspace']['createdAt'] == '<fixture-time>', 'workspace createdAt was not normalized')
    require(frames[0]['value']['workspace']['updatedAt'] == '<fixture-time>', 'workspace updatedAt was not normalized')
    require(frames[1]['value']['workspaceIds'] == ['<fixture-workspace-id>'], 'workspace order delta drifted')

    error = fixture.get('businessError', {})
    assert_remote_pair(error, 'fixture-business-error', 'session/cancel', False)
    require(error['response']['result']['error']['code'] == 'session/not-found', 'business error code drifted')

    download = fixture.get('download', {})
    require(download.get('request') == {'method': 'GET', 'path': '/api/session.export?sessionId=fixture-session'}, 'download request drifted')
    for mode in ('head', 'get'):
        facts = download.get(mode, {})
        require(facts.get('status') == 200, f'download {mode} status drifted')
        require(facts.get('contentType') == 'application/zip', f'download {mode} content type drifted')
        require(facts.get('contentDisposition') == 'attachment; filename="dsh-session-fixture-session.zip"', f'download {mode} disposition drifted')
    require(download['get'].get('zipMagicHex') == '504b0304', 'download is not a ZIP local-file stream')

    raw = args.fixture.read_text(encoding='utf-8')
    for pattern in FORBIDDEN:
        require(pattern.search(raw) is None, f'fixture leaked forbidden secret/path pattern {pattern.pattern!r}')
    require('token' not in raw.lower().replace('persistedlaunchtoken', ''), 'fixture contains unexpected token text')
    print('Authenticated rc.1 Host fixture OK: unary, stream opening/delta, business error, download, privacy')


def assert_remote_pair(record: dict, rpc_id: str, endpoint: str, ok: bool) -> None:
    require(record.get('httpStatus') == 200, f'{endpoint} HTTP status drifted')
    require(record.get('contentType') == 'application/json', f'{endpoint} content type drifted')
    request = record.get('request', {})
    response = record.get('response', {})
    require(request.get('type') == 'client-request' and request.get('rpcId') == rpc_id and request.get('method') == endpoint, f'{endpoint} request envelope drifted')
    require(response.get('type') == 'server-response' and response.get('rpcId') == rpc_id, f'{endpoint} response correlation drifted')
    require(response.get('result', {}).get('ok') is ok, f'{endpoint} Remote result drifted')


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit('authenticated Host fixture gate: ' + message)


if __name__ == '__main__':
    main()
