#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,subprocess
from pathlib import Path
from typing import Any
COMMIT='a66e4702047846cdaa10c66c9d3df3951f5ea70d'
REVISION='official-a66e470-remote-contract-r1'
EXTRACTOR=Path(__file__).with_name('extract_official_remote_contract_ast.mjs')
CARRIER_SOURCES=('packages/api/gateway/src/stream-protocol.ts','packages/api/gateway/src/remote-error-codes.ts','packages/client/connection/src/client/rpc.ts','packages/session-query/session-log-export/src/index.ts')
def extract_ast_contract(root:Path):
 p=subprocess.run(['node',str(EXTRACTOR),str(root)],text=True,capture_output=True)
 if p.returncode: raise SystemExit('Remote AST extraction failed:\n'+p.stderr+p.stdout)
 d=json.loads(p.stdout); ps=d.get('procedures'); es=d.get('closedRemoteErrors')
 if not isinstance(ps,list) or any(not isinstance(x,dict) for x in ps): raise SystemExit('invalid procedures')
 if not isinstance(es,list) or any(not isinstance(x,dict) for x in es): raise SystemExit('invalid errors')
 return sorted(ps,key=lambda x:x['endpoint']),sorted(es,key=lambda x:x['code'])
def carrier(root:Path)->dict[str,Any]:
 texts={p:(root/p).read_text() for p in CARRIER_SOURCES}; stream=texts[CARRIER_SOURCES[0]]
 if "REMOTE_STREAM_MUX_PATH = '/api/remote.mux'" not in stream: raise SystemExit('mux path drifted')
 if "REMOTE_EVENT_STREAM_ENDPOINT = '$events'" not in stream or "REMOTE_EVENT_RESULT_ENDPOINT = '$events/result'" not in stream: raise SystemExit('event endpoints drifted')
 if 'readonly home: string' not in stream: raise SystemExit('Host ready facts drifted')
 rpc=texts[CARRIER_SOURCES[2]]
 for token in ('client-request','server-response','rpcId'):
  if token not in rpc: raise SystemExit(f'unary carrier missing {token}')
 export=texts[CARRIER_SOURCES[3]]
 if "SESSION_LOG_EXPORT_PATH = '/api/session.export'" not in export or "methods: ['GET', 'HEAD']" not in export: raise SystemExit('session export drifted')
 return {'unary':{'pathTemplate':'/api/<namespace>/<method>','requestEnvelope':'client-request','responseEnvelope':'server-response','correlationField':'rpcId','sourcePath':CARRIER_SOURCES[2]},'streamMux':{'path':'/api/remote.mux','eventStreamEndpoint':'$events','eventResultEndpoint':'$events/result','readyHostFields':['home'],'sourcePath':CARRIER_SOURCES[0]},'nonJSONRoutes':[{'path':'/api/session.export','methods':['GET','HEAD'],'contentType':'application/zip','sourcePath':CARRIER_SOURCES[3]}],'sources':[{'path':p} for p in CARRIER_SOURCES]}
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--official-root',required=True,type=Path); ap.add_argument('--output',required=True,type=Path); a=ap.parse_args(); root=a.official_root.resolve(); ps,es=extract_ast_contract(root)
 m={'schemaVersion':1,'officialSourceCommit':COMMIT,'contractRevision':REVISION,'generation':'locked rc.1 Typert Remote AST and Gateway carrier manifest','procedures':ps,'closedRemoteErrors':es,'carrier':carrier(root)}
 a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(m,indent=2,ensure_ascii=False)+'\n')
if __name__=='__main__': main()
