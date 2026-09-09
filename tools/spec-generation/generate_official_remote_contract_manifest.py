#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,subprocess
from pathlib import Path
from typing import Any
COMMIT='a66e4702047846cdaa10c66c9d3df3951f5ea70d'
REVISION='official-a66e470-remote-contract-r1'
EXTRACTOR=Path(__file__).with_name('extract_official_remote_contract_ast.mjs')
DEFAULT_SELECTION=Path(__file__).with_name('official-remote-procedure-selection.json')
CARRIER_SOURCES=('packages/api/gateway/src/stream-protocol.ts','packages/api/gateway/src/remote-error-codes.ts','packages/client/connection/src/client/rpc.ts','packages/session-query/session-log-export/src/index.ts')
def extract_ast_contract(root:Path):
 p=subprocess.run(['node',str(EXTRACTOR),str(root)],text=True,capture_output=True)
 if p.returncode: raise SystemExit('Remote AST extraction failed:\n'+p.stderr+p.stdout)
 d=json.loads(p.stdout); ps=d.get('procedures'); es=d.get('closedRemoteErrors')
 if not isinstance(ps,list) or any(not isinstance(x,dict) for x in ps): raise SystemExit('invalid procedures')
 if not isinstance(es,list) or any(not isinstance(x,dict) for x in es): raise SystemExit('invalid errors')
 return sorted(ps,key=lambda x:x['endpoint']),sorted(es,key=lambda x:x['code'])
def select_procedures(procedures:list[dict[str,Any]],selection_path:Path)->list[dict[str,Any]]:
 try: selection=json.loads(selection_path.read_text())
 except (OSError,json.JSONDecodeError) as e: raise SystemExit(f'cannot read Remote selection policy {selection_path}: {e}')
 if not isinstance(selection,dict) or selection.get('schemaVersion')!=1: raise SystemExit('Remote selection policy schemaVersion invalid')
 if selection.get('officialSourceCommit')!=COMMIT: raise SystemExit('Remote selection policy source commit drifted')
 if selection.get('scope')!='glass-consumed-rc1': raise SystemExit('Remote selection policy scope drifted')
 excluded=selection.get('excludedCurrentProcedures')
 if not isinstance(excluded,list) or any(not isinstance(x,dict) for x in excluded): raise SystemExit('Remote selection exclusions must be an array of objects')
 endpoints=[]
 for entry in excluded:
  endpoint=entry.get('endpoint'); reason=entry.get('reason')
  if not isinstance(endpoint,str) or not endpoint or not isinstance(reason,str) or not reason.strip(): raise SystemExit('Remote selection exclusion lacks endpoint/reason')
  endpoints.append(endpoint)
 if len(endpoints)!=len(set(endpoints)): raise SystemExit('Remote selection exclusions contain duplicate endpoints')
 current={p['endpoint']:p for p in procedures}
 missing=sorted(set(endpoints)-set(current))
 if missing: raise SystemExit('Remote selection excludes procedures absent from locked rc.1: '+', '.join(missing))
 excluded_set=set(endpoints)
 return [p for p in procedures if p['endpoint'] not in excluded_set]
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
 ap=argparse.ArgumentParser(); ap.add_argument('--official-root',required=True,type=Path); ap.add_argument('--output',required=True,type=Path); ap.add_argument('--selection',type=Path,default=DEFAULT_SELECTION); a=ap.parse_args(); root=a.official_root.resolve(); raw_ps,es=extract_ast_contract(root); ps=select_procedures(raw_ps,a.selection.resolve())
 m={'schemaVersion':1,'officialSourceCommit':COMMIT,'contractRevision':REVISION,'generation':'locked rc.1 Typert Remote AST and Gateway carrier manifest','procedures':ps,'closedRemoteErrors':es,'carrier':carrier(root)}
 a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(m,indent=2,ensure_ascii=False)+'\n')
if __name__=='__main__': main()
