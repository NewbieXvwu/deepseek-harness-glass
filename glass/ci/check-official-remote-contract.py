#!/usr/bin/env python3
"""Reject drift from the locked rc.1 Typert Remote and Gateway contract."""
from __future__ import annotations
import argparse,json,subprocess,sys,tempfile
from pathlib import Path
from typing import Any
ROOT=Path(__file__).resolve().parents[2]
GENERATOR=ROOT/'tools/spec-generation/generate_official_remote_contract_manifest.py'
DEFAULT_MANIFEST=ROOT/'glass/Sources/Spec/Fixtures/official-remote-contract-manifest.json'
COMMIT='a66e4702047846cdaa10c66c9d3df3951f5ea70d'
REVISION='official-a66e470-remote-contract-r1'
FORBIDDEN_LEGACY={'session.history','session.models','events.mux','events.host','session/history','session/models','events/mux','events/host'}
REQUIRED_NAMESPACES={'session','workspace','settings','credentials','llm','subagents','messageFeedback','goals','agentPresets','commands','skills'}
def fail(message:str)->None: raise SystemExit(f'official Remote contract check failed: {message}')
def official_head(root:Path)->str:
 try: return subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True,stderr=subprocess.STDOUT).strip()
 except subprocess.CalledProcessError as e: fail(f'cannot resolve official source commit: {e.output.strip()}')
def load(path:Path)->dict[str,Any]:
 try: d=json.loads(path.read_text())
 except (OSError,json.JSONDecodeError) as e: fail(f'cannot read manifest {path}: {e}')
 if not isinstance(d,dict) or d.get('schemaVersion')!=1: fail('manifest root/schemaVersion invalid')
 if d.get('officialSourceCommit')!=COMMIT: fail('officialSourceCommit does not match rc.1 lock')
 if d.get('contractRevision')!=REVISION: fail('contractRevision does not match reviewed rc.1 revision')
 return d
def validate_type_syntax(value:str,context:str)->None:
 if not isinstance(value,str) or not value.strip(): fail(f'{context}: empty type declaration')
 pairs={'{':'}','[':']','(':')'}; stack=[]; quote=None; escaped=False
 for ch in value.strip():
  if escaped: escaped=False; continue
  if ch=='\\': escaped=True; continue
  if quote:
   if ch==quote: quote=None
   continue
  if ch in "'\"`": quote=ch; continue
  if ch in pairs: stack.append(pairs[ch])
  elif ch in pairs.values():
   if not stack or stack[-1]!=ch: fail(f"{context}: unbalanced bracket '{ch}'")
   stack.pop()
 if stack: fail(f"{context}: unclosed bracket expecting '{stack[-1]}'")
def validate_shape(m:dict[str,Any])->None:
 procedures=m.get('procedures')
 if not isinstance(procedures,list) or not procedures: fail('procedures must be a non-empty list')
 endpoints=[]
 for p in procedures:
  if not isinstance(p,dict) or not isinstance(p.get('endpoint'),str): fail('procedure entry lacks endpoint')
  endpoint=p['endpoint']; endpoints.append(endpoint)
  if p.get('mode') not in {'unary','stream'}: fail(f'{endpoint}: invalid invocation mode')
  if not isinstance(p.get('parameters'),list) or not isinstance(p.get('injected'),list): fail(f'{endpoint}: parameters/injected must be arrays')
  if not isinstance(p.get('sourcePath'),str) or not p['sourcePath']: fail(f'{endpoint}: missing sourcePath')
  for param in p['parameters']:
   if not isinstance(param,dict) or 'type' not in param: fail(f'{endpoint}: invalid parameter entry')
   validate_type_syntax(param['type'],f"{endpoint} parameter '{param.get('name')}'")
  validate_type_syntax(p.get('returnType'),f'{endpoint} returnType')
 if len(endpoints)!=len(set(endpoints)): fail('duplicate Remote endpoint')
 if set(endpoints)&FORBIDDEN_LEGACY: fail('legacy APIProxy endpoint is present')
 namespaces={e.split('/',1)[0] for e in endpoints if '/' in e}; missing=REQUIRED_NAMESPACES-namespaces
 if missing: fail('missing required Remote namespaces: '+', '.join(sorted(missing)))
 if {'settings/update','settings/replace'}&set(endpoints): fail('unreviewed settings whole-section mutation escaped into contract')
 errors=m.get('closedRemoteErrors')
 if not isinstance(errors,list) or not errors: fail('closedRemoteErrors must be a non-empty list')
 codes=[]
 for e in errors:
  if not isinstance(e,dict) or not isinstance(e.get('code'),str) or not isinstance(e.get('sourcePath'),str): fail('invalid closedRemoteErrors entry')
  codes.append(e['code']); validate_type_syntax(e.get('detailsType'),f"error '{e['code']}' detailsType")
 if len(codes)!=len(set(codes)): fail('closedRemoteErrors contains duplicates')
 for code in ('gateway/bad-request','gateway/cancelled','gateway/internal','gateway/method-unavailable','gateway/service-unavailable'):
  if code not in codes: fail(f'missing reviewed Gateway Remote error {code}')
 carrier=m.get('carrier'); unary=carrier.get('unary') if isinstance(carrier,dict) else None; stream=carrier.get('streamMux') if isinstance(carrier,dict) else None; routes=carrier.get('nonJSONRoutes') if isinstance(carrier,dict) else None
 if not isinstance(unary,dict) or unary.get('pathTemplate')!='/api/<namespace>/<method>' or unary.get('requestEnvelope')!='client-request' or unary.get('responseEnvelope')!='server-response' or unary.get('correlationField')!='rpcId': fail('unary Connection carrier drifted')
 if not isinstance(stream,dict) or stream.get('path')!='/api/remote.mux' or stream.get('eventStreamEndpoint')!='$events' or stream.get('eventResultEndpoint')!='$events/result' or stream.get('readyHostFields')!=['home']: fail('Gateway Remote mux/Host facts drifted')
 if not isinstance(routes,list) or len(routes)!=1 or routes[0].get('path')!='/api/session.export' or routes[0].get('methods')!=['GET','HEAD'] or routes[0].get('contentType')!='application/zip': fail('session export route drifted')
def main()->None:
 ap=argparse.ArgumentParser(); ap.add_argument('--official-root',required=True,type=Path); ap.add_argument('--manifest',type=Path,default=DEFAULT_MANIFEST); a=ap.parse_args(); root=a.official_root.resolve()
 if official_head(root)!=COMMIT: fail(f'official root must be locked at {COMMIT}')
 baseline=load(a.manifest.resolve()); validate_shape(baseline)
 with tempfile.TemporaryDirectory(prefix='dsh-remote-contract-') as tmp:
  candidate_path=Path(tmp)/'candidate.json'; r=subprocess.run([sys.executable,str(GENERATOR),'--official-root',str(root),'--output',str(candidate_path)],text=True,capture_output=True)
  if r.returncode: fail('fresh rc.1 generation failed:\n'+r.stderr+r.stdout)
  candidate=load(candidate_path); validate_shape(candidate)
 if candidate!=baseline: fail('checked-in manifest differs from fresh rc.1 AST/carrier generation')
 print(f"official Remote contract OK: {len(baseline['procedures'])} procedures, {len(baseline['closedRemoteErrors'])} closed errors at {COMMIT[:12]}")
if __name__=='__main__': main()
