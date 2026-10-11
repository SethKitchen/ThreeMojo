"""Package the separate completed v29 focused qualification; source/data only.

No candidate imports, tests, native execution, candidate writes or uploads.
Only one specified completed handoff record is selected from the ongoing v28
continuation. No mutable continuation file or later diagnostic result is copied.
"""
from pathlib import Path
from datetime import datetime, timezone
import ast, base64, gzip, hashlib, json, re
R=Path(__file__).resolve().parent; PHASE='frozen-arc-public-diagnostic-focused-v29';E=R/'evidence'/PHASE;S=R/'candidate-v29';B=R/'candidate-v28';O=R/'validation-evidence-frozen-arc-focused-v29-packet'
SEAL='d344962d1b0cf829f3d5cc7ea017ddf8d7abea4c3da4749c5ad04002d8dd2196';BASE='fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596';RESULT='3de0c52b6db36a767efcaee1c62021179b1c37a20a0fde6cfa259fe1d0b46515';MANIFEST='62bcd52e392561266bb13f3fb4502ae83b340e443d9ab7422c1377453d80afc9';SDK='7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207';SUP='6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032'
SHA=lambda b:hashlib.sha256(b).hexdigest();JSON=lambda x:(json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def need(x,m):
 if not x:raise ValueError(m)
def raw(p):
 need(p.is_file() and not p.is_symlink(),'Nonregular '+str(p));return p.read_bytes()
def read(p):return json.loads(raw(p))
def bind(p,h):
 b=raw(p);need(SHA(b)==h,'Hash '+str(p));return b
need(not O.exists(),'Never overwrite completed evidence')
r=json.loads(bind(E/'RESULT.json',RESULT));config=read(R/(PHASE+'.json'));window=read(E/'WINDOW-START.json')
seal=json.loads(bind(R/'CANDIDATE-V29-SOURCE-SEAL.json',SEAL));baseline=json.loads(bind(R/'CANDIDATE-V28-SOURCE-SEAL.json',BASE));source_manifest_path=R/'frozen-arc-public-diagnostic-implementation-v29/PUBLISHABLE-SOURCE-MANIFEST.json';source_manifest=json.loads(bind(source_manifest_path,MANIFEST))
need(bind(E/'SOURCE-SEAL.json',SEAL)==raw(R/'CANDIDATE-V29-SOURCE-SEAL.json'),'Exact executed source seal')
need(r['sequence_completed'] is True and r['failure'] is None and r['source_seal_unchanged'] is True and r['sdk_identity_unchanged'] is True and r['remaining_owned_descendants']==[] and len(r['stages'])==2,'Completed focused qualification')
need(r['finished']=='2026-10-11T06:20:21.950702+00:00' and r['elapsed_seconds']==66.71838693900645,'Exact original completion')
need(config['scope']==r['scope'] and config['source']==str(S) and config['source_seal_sha256']==SEAL and config['additional_sources']==[dict(source=str(B),seal=str(R/'CANDIDATE-V28-SOURCE-SEAL.json'))],'Primary and baseline config binding')
need(window['source_seal_sha256']==SEAL and window['supervisor_sha256']==SHA(raw(R/'run_checkpoint_matrix.py'))==SUP and window['python_optimize']==0 and window['runtime_gate_seconds']==5 and window['whole_window_seconds']==config['window_seconds']==10800,'Unchanged supervisor and caps')
need(bind(E/'SDK-BEFORE.json',SDK)==raw(E/'SDK-AFTER.json'),'SDK before/after')
need(source_manifest['base_source_seal_sha256']==BASE and source_manifest['source_seal_sha256']==SEAL and source_manifest['base_commit']=='031f9f726edb6e9409853fd777af966c8ebba88d' and source_manifest['delta_count']==2,'Source-only repair manifest')
delta={p for p in seal.keys()|baseline.keys() if seal.get(p)!=baseline.get(p)};need(set(seal)==set(baseline) and len(seal)==3837 and delta=={x['path'] for x in source_manifest['files']} and len(delta)==2,'Exact two-file seal delta')
for row in source_manifest['files']:
 b=bind(S/row['path'],row['sha256']);need(SHA(raw(B/row['path']))==row['before_sha256']==baseline[row['path']] and SHA(b)==seal[row['path']] and len(b)==row['bytes'],'Actual before/after source bytes')
 need(hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==row['git_blob'] and row['mode']=='100644' and (S/row['path']).stat().st_mode&0o111==0,'Exact source blob/mode')
need(all(seal[p]==baseline[p] for p in seal if p.endswith('.mojo')) and seal['docs/validation/anatomy-template-report.json']==baseline['docs/validation/anatomy-template-report.json'],'Mojo/genuine report unchanged in seal')
console=[json.loads(b) for b in raw(R/(PHASE+'.supervisor.log')).splitlines()];need(len(console)==3 and console[-1]==r,'Original supervisor aggregate console')
expected_files={'RESULT.json','SOURCE-SEAL.json','SDK-BEFORE.json','SDK-AFTER.json','WINDOW-START.json','PROCESSES.jsonl','LATEST.json'};methods=[]
for i,(mode,stage,planned) in enumerate(zip(('normal','optimized'),r['stages'],config['stages'])):
 label=mode+'-frozen-arc-public-diagnostic';need(stage['label']==planned['label']==label and stage==read(E/(label+'-RESULT.json')),'Exact stage/order')
 need(all(stage.get(k)==v for k,v in read(E/(label+'-START.json')).items()),'START/result')
 command=[str(R.parent/'restored-toolchain/official-venv/bin/python')]+(['-O'] if i else [])+['-B','-m','unittest','discover','-s','tools/carla_lane_oracle','-p','test_frozen_arc_producer_contracts.py','-v']
 need(stage['argv']==command and planned['command']==['{python}']+command[1:] and stage['cwd']==str(S),'Maintained exact command')
 need(stage['source_seal_sha256']==SEAL and stage['stage_timeout_seconds']==planned['seconds']==1800 and stage['returncode']==0 and not stage['timed_out'] and stage['leader_reaped'] and stage['remaining_owned_descendants']==[],'Stage source/cap/cleanup')
 need(stage['test_count']==stage['expected_tests']==planned['expected_tests']==9 and stage['skipped_test_count']==0,'Stage count/zero skips')
 need(console[i]=={k:v for k,v in stage.items() if k not in ('test_count','expected_tests','skipped_test_count')},'Actual pre-annotation console')
 log=bind(E/(label+'.log'),stage['log_sha256']).decode();need(re.findall(r'^Ran (\d+) tests? in ',log,re.M)==['9'] and log.rstrip().endswith('OK') and ' ... skipped ' not in log and not re.search(r'^(FAIL|ERROR): ',log,re.M),'Raw unittest results')
 names=re.findall(r'^(test_\w+) \(test_frozen_arc_producer_contracts\.([A-Za-z_]+)\.',log,re.M);need(len(names)==9,'Nine actual named test methods');methods.append(sorted(cls+'.'+name for name,cls in names));expected_files.update((label+'-START.json',label+'-RESULT.json',label+'.log'))
need(methods[0]==methods[1],'Same normal/optimized methods')
need({p.name for p in E.iterdir()}==expected_files and len(expected_files)==13,'All and only completed phase originals')
processes=[json.loads(b) for b in raw(E/'PROCESSES.jsonl').splitlines()];need(processes and read(E/'LATEST.json')==processes[-1],'Process census latest binding')
# Static source preservation, without importing the test module.
test='tools/carla_lane_oracle/test_frozen_arc_producer_contracts.py';old=raw(B/test);new=raw(S/test)
def methods_ast(b):
 t=ast.parse(b);lines=b.splitlines(keepends=True);d={}
 for cls in t.body:
  if isinstance(cls,ast.ClassDef):
   for n in cls.body:
    if isinstance(n,ast.FunctionDef) and n.name.startswith('test_'):d[cls.name+'.'+n.name]=(b''.join(lines[n.lineno-1:n.end_lineno]),ast.dump(n,include_attributes=False))
 return d
old_methods=methods_ast(old);new_methods=methods_ast(new);need(len(old_methods)==5 and len(new_methods)==9 and set(old_methods)<=set(new_methods),'Five original/four appended methods')
need(all(new_methods[k]==v for k,v in old_methods.items()) and set(methods[0])==set(new_methods),'Original method byte/AST preservation and executed names')
# Copy only the specific completed pause/resume line; never copy mutable continuation files.
handoff_source=R/'evidence/full-python-diagnostic-continuation-v28/LANE-HANDOFFS.jsonl';observed=raw(handoff_source);lines=observed.splitlines(keepends=True)
selected=[(i,b,json.loads(b)) for i,b in enumerate(lines) if json.loads(b).get('started')=='2026-10-11T06:18:53.100067+00:00']
need(len(selected)==1,'Unique completed handoff');index,handoff_raw,handoff=selected[0]
need(handoff['paused'] is False and handoff['resumed']=='2026-10-11T06:20:58.105114+00:00' and handoff['next_stage']=='13-normal-test_lane_control_contracts' and handoff['source_seal_sha256']==BASE and handoff['remaining_owned_descendants']==[],'Exact completed handoff')
need(datetime.fromisoformat(handoff['started'])<datetime.fromisoformat(window['started'])<datetime.fromisoformat(r['finished'])<datetime.fromisoformat(handoff['resumed']),'Focused window wholly inside handoff')
handoff_meta=dict(schema=1,kind='specific-completed-record-byte-exact-extraction',original_stream=str(handoff_source),line_number=index+1,byte_offset=sum(map(len,lines[:index])),record_bytes=len(handoff_raw),record_sha256=SHA(handoff_raw),observed_stream_bytes=len(observed),observed_stream_sha256=SHA(observed),snapshot_observed_utc=datetime.now(timezone.utc).isoformat(),record='actual/completed-v28-handoff/COMPLETED-HANDOFF.jsonl',boundary='Only the exact completed record is preserved. The source stream is mutable and its observed hash is timestamped provenance, not an assertion of final continuation state. No other continuation files or results are included.')
originals=[]
def add(p,name,kind,readable=False):originals.append(dict(path=name,data=raw(p),kind=kind,original_source=str(p),readable=readable))
for name in sorted(expected_files):add(E/name,'actual/'+PHASE+'/'+name,'original-completed-focused-phase',name in ('RESULT.json','WINDOW-START.json','SDK-BEFORE.json','SDK-AFTER.json') or name.endswith('.log'))
for name in (PHASE+'.json',PHASE+'.supervisor.log','run_checkpoint_matrix.py','CANDIDATE-V29-SOURCE-SEAL.json','CANDIDATE-V28-SOURCE-SEAL.json','PUBLISHED-V28-QUALIFICATION-BINDING.json'):
 add(R/name,'reproduce/'+name,'exact-command-supervisor-console-or-source-baseline-binding',name in (PHASE+'.json','run_checkpoint_matrix.py','PUBLISHED-V28-QUALIFICATION-BINDING.json'))
need(SHA(raw(R/'PUBLISHED-V28-QUALIFICATION-BINDING.json'))=='0df492bd6c870ecb2e8a6d3cb66167c2d5042aa7ba0a70d4b42f02f71eef8bdf','Published baseline binding')
add(source_manifest_path,'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json','original-source-only-manifest-before-focused-run',True)
for path in sorted(delta):
 add(S/path,'reproduce/source-v29/'+path,'exact-reviewed-source-after-repair',True);add(B/path,'reproduce/source-v28/'+path,'exact-sealed-source-before-repair')
for path in ('tools/coverage_toolchain_identity.py','tools/carla_lane_oracle/full_audit_cleanup_contracts.py','tools/carla_lane_oracle/_full_audit_test_fixtures.py','tools/carla_lane_oracle/runtime-source-pins.json'):
 bind(S/path,seal[path]);add(S/path,'reproduce/unchanged-source/'+path,'exact-unchanged-related-source')
originals.append(dict(path='actual/completed-v28-handoff/COMPLETED-HANDOFF.jsonl',data=handoff_raw,kind='byte-exact-completed-record-selected-from-mutable-stream',original_source=str(handoff_source),source_selection=dict(line_number=index+1,byte_offset=handoff_meta['byte_offset'],bytes=len(handoff_raw)),readable=True))
summary=dict(schema=1,status='PASS_SEPARATE_V29_FROZEN_ARC_FOCUSED_QUALIFICATION_ONLY',scope='Both normal and optimized runs of the complete nine-method frozen ARC module passed, zero skips: eighteen focused test executions. This is a separate isolated two-file v29 repair qualification, not a complete v29 Python matrix or native/coverage qualification.',source_seal_sha256=SEAL,baseline_source_seal_sha256=BASE,baseline_published_commit=source_manifest['base_commit'],result_sha256=RESULT,source_only_repair_manifest_sha256=MANIFEST,config_sha256=SHA(raw(R/(PHASE+'.json'))),actual_console_sha256=SHA(raw(R/(PHASE+'.supervisor.log'))),supervisor_sha256=SUP,sdk_receipt_sha256=SDK,finished=r['finished'],whole_window_seconds=r['elapsed_seconds'],stage_cap_seconds=1800,window_cap_seconds=10800,stage_results=[{k:s[k] for k in ('label','seconds','returncode','timed_out','test_count','expected_tests','skipped_test_count','leader_reaped','remaining_owned_descendants','log_sha256')} for s in r['stages']],source_sdk_unchanged=True,additional_baseline_binding='The exact config adds candidate-v28 with its full seal. The unchanged executed supervisor verifies both primary and additional baseline trees at its verification points; receipt source_seal_unchanged is not a separately named baseline flag.',remaining_owned_descendants=[],original_methods_byte_ast_unchanged=sorted(old_methods),new_control_methods=sorted(set(new_methods)-set(old_methods)),executed_methods_per_mode=methods[0],control_scope='Original five functional/mutation methods plus real current-gate causal rejection, other-bound-input rejection, physical historical-layer rejection, and separately labeled synthetic exception/private-forwarding dispatch. Synthetic dispatch does not establish real owner admission.',repair_source_boundary='Exactly two seal entries change; all other 3835 entries, all Mojo sources and the genuine report are unchanged. This packet compares seals and exact changed/support source bytes, without rerunning the producer or rehashing the full installed SDK.',completed_lane_handoff_record_sha256=SHA(handoff_raw),handoff_scope='The entire focused window lies within the completed v28 pause/resume interval. Only that completed record is included; no live continuation state or result is credited.',prior_failure_boundary='The original v28 full-matrix failure remains in its own packet unchanged. This focused pass neither rewrites it nor establishes any later continuation result.',source_manifest_time_boundary='The source manifest is preserved exactly with its earlier source-only/pending-execution status. This later passing result remains separately timestamped.',qualification_limit='No full v29 matrix, full native suite, maintained coverage, hosted CI or issue completion is claimed.',reproduction_boundary='Contains all13 focused phase originals, exact config and actual console, executed supervisor, both full source seals, baseline publication binding, exact before/after repair source and unchanged gate/fixture/SDK-support/runtime-record source. The entire unchanged repository and SDK executable image are not distributed.',evidence_policy='Original bytes with separately labeled derived summary, command index and one completed-record extraction. No internal review/design notes, candidate changes, project imports, tests/native reruns or uploads.')
commands=dict(schema=1,kind='derived-actual-command-and-source-baseline-binding',phase=PHASE,source_seal_sha256=SEAL,baseline_source_seal_sha256=BASE,config_sha256=SHA(raw(R/(PHASE+'.json'))),result_sha256=RESULT,stages=r['stages'],start_receipt_sha256={s['label']:SHA(raw(E/(s['label']+'-START.json'))) for s in r['stages']},actual_supervisor_console_sha256=SHA(raw(R/(PHASE+'.supervisor.log'))))
archive='containers/ORIGINAL-EVIDENCE.json.gz.b64';members=[];archived=[];payloads=[]
need(len(originals)==len({x['path'] for x in originals}),'Duplicate original paths')
for row in sorted(originals,key=lambda x:x['path']):
 b=row['data'];member={k:row[k] for k in ('path','kind','original_source')};member.update(bytes=len(b),sha256=SHA(b))
 if 'source_selection' in row:member['source_selection']=row['source_selection']
 if row['readable']:
  b.decode();payloads.append((row['path'],b,'byte-exact-readable-original'));member.update(storage='readable',transport_path=row['path'])
 else:
  archived.append(dict(path=row['path'],bytes=len(b),sha256=SHA(b),data_base64=base64.b64encode(b).decode()));member.update(storage='container',transport_path=archive)
 members.append(member)
container=(json.dumps(dict(schema=1,encoding='base64',members=archived),sort_keys=True,separators=(',',':'))+'\n').encode();need(len(container)<64*1024*1024,'Decoder size limit');encoded=base64.b64encode(gzip.compress(container,compresslevel=9,mtime=0))+b'\n';need(gzip.decompress(base64.b64decode(encoded))==container,'Container roundtrip')
inner=dict(schema=1,original_member_count=len(members),original_member_bytes=sum(x['bytes'] for x in members),container=dict(path=archive,encoding='base64 of deterministic gzip mtime=0 containing JSON',members=len(archived),json_bytes=len(container),json_sha256=SHA(container)),members=members)
decoder=bind(R/'validation-evidence-qualification-policy-v23-packet/decode_verify.py','a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4')
guide='''# Separate v29 frozen ARC focused qualification

PASS within this focused scope: all nine methods passed normally and optimized,
zero skips, eighteen executions. Stage times were 29.119174102 and 30.584908304
seconds; the complete window took 66.718386939 seconds. Caps remained 1,800
seconds per module and 10,800 seconds for the window. Source/SDK receipts stayed
unchanged and no owned descendants remained. This is not a full v29 matrix,
native/coverage qualification, hosted-CI result or issue-completion claim.

The repair changes exactly two files from sealed v28. Both before/after files,
the original source-only manifest, both complete seals, exact config/console,
executed supervisor and related source are included. The earlier manifest's
pending-execution wording is historical; the later focused result is separate.
The original five test methods remain byte/AST-identical. Four new methods cover
real current/historical rejection paths and explicitly labeled synthetic
dispatch behavior. Synthetic dispatch does not establish real owner admission.

The focused config also binds the v28 baseline as an additional source. The
unchanged supervisor checks that additional tree at its verification points.
The primary stability receipt is not a separately named baseline-status flag.
The complete focused window lies within one completed v28 pause/resume interval.
Only that exact completed JSONL record is retained, with extraction provenance.
Its source stream may grow; no mutable ongoing continuation file or later
result is copied. The original failed v28 matrix is neither rewritten nor
converted into a pass by this separate focused qualification.

All thirteen original focused phase files and both full raw merged logs are
preserved. Readable originals retain their exact bytes. Other originals are
base64 members in JSON, gzip-compressed with mtime=0, then base64-encoded. The
inner manifest lists each original size/hash/storage. The outer manifest seals
all payloads and excludes itself. Summary, command index and snapshot metadata
are labeled derived. The full unchanged repository and SDK image are not shipped.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The copied reviewed decoder validates hashes, sizes and paths, rejects symlinks
and existing output, and never executes decoded content. Packaging performs
no project imports, tests/native runs, candidate edits or uploads. Internal
review/design notes are excluded; only their pre-existing hashes in the source
manifest remain as provenance.
'''
payloads.extend([(archive,encoded,'lossless-original-receipts-logs-source-and-seals'),('INNER-MEMBER-MANIFEST.json',JSON(inner),'complete-original-member-inventory'),('VALIDATION-SUMMARY.json',JSON(summary),'derived-focused-scope-summary'),('COMMAND-RECEIPT-SEAL.json',JSON(commands),'derived-command-receipt-binding'),('COMPLETED-HANDOFF-SNAPSHOT-PROVENANCE.json',JSON(handoff_meta),'derived-specific-completed-record-extraction-provenance'),('decode_verify.py',decoder,'reviewed-safe-decoder-no-execution'),('reproduce/build_frozen_arc_focused_v29_packet.py',raw(Path(__file__)),'source-only-packet-builder'),('README.md',guide.encode(),'scope-and-safe-transport-guide')])
need(len(payloads)==len({n for n,_,_ in payloads})<=35,'Transport payload count')
secret_patterns=(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',rb'gh[pousr]_[A-Za-z0-9]{30,}',rb'AKIA[0-9A-Z]{16}',rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
for row in originals:
 need(not any(re.search(p,row['data']) for p in secret_patterns),'Credential pattern '+row['path'])
 observed_now=raw(Path(row['original_source']))
 if 'source_selection' in row:
  selection=row['source_selection'];observed_now=observed_now[selection['byte_offset']:selection['byte_offset']+selection['bytes']]
 need(observed_now==row['data'],'Original changed during packaging')
O.mkdir();rows=[]
for name,b,kind in sorted(payloads):
 p=O/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(b)
 need(raw(p)==b,'Written payload differs');rows.append(dict(path=name,local_source=str(p),bytes=len(b),sha256=SHA(b),kind=kind))
p=O/'PUBLISHABLE-EVIDENCE-MANIFEST.json'
with p.open('xb') as f:f.write(JSON(dict(schema=1,scope=summary['scope'],files=rows)))
print(json.dumps(dict(manifest=str(p),sha256=SHA(raw(p)),payloads=len(rows),original_members=len(members),archived_members=len(archived),original_bytes=inner['original_member_bytes'],packet_bytes_including_manifest=sum(x['bytes'] for x in rows)+len(raw(p)),result_sha256=RESULT,source_seal_sha256=SEAL)))
