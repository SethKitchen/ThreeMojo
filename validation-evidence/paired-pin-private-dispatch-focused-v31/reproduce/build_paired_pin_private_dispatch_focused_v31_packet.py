"""Byte-only packaging of completed v31 focus; no candidate execution or edits."""
from pathlib import Path
from datetime import datetime, timezone
import ast,base64,copy,gzip,hashlib,json,re
R=Path(__file__).resolve().parent;PHASE='paired-pin-private-dispatch-focused-v31';E=R/'evidence'/PHASE;S=R/'candidate-v31';B=R/'candidate-v30';O=R/'validation-evidence-paired-pin-private-dispatch-focused-v31-packet'
SEAL='a6cb4394fecbeefdcb4615b43621c481db32f9dbf72c83e04e64283ac7f83456';V30='e595593ff7afaef3a4e04d6cbb24ec5343a0178ba11ea421e6a6c5ee455c4c38';V28='fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596';RESULT='22c057bd1a34286f417e1361637edefc04084ff053bd6a3bc881b21b35cff99f';CONFIG='2b9d63b82b200380e6fb8eb00d7727f3120fc279067a879214409014eb54bc93';SM='848ef0105a364eb1b4331fa4dad0b389666fe4e36fca300cce371ea1c3537a40';SUP='6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032';SDK='7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207'
TEST='tools/carla_lane_oracle/test_paired_pin_contracts.py';CHANGED='test_fixed_shape_order_signatures_and_single_freshness';SECOND='test_each_owner_initial_phase_uses_one_fresh_pair'
SHA=lambda b:hashlib.sha256(b).hexdigest();JSON=lambda x:(json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def need(x,m):
 if not x:raise ValueError(m)
def raw(p):
 need(p.is_file() and not p.is_symlink(),'Nonregular '+str(p));return p.read_bytes()
def bind(p,h):
 b=raw(p);need(SHA(b)==h,'Hash '+str(p));return b
need(not O.exists(),'Never overwrite evidence')
r=json.loads(bind(E/'RESULT.json',RESULT));config=json.loads(bind(R/(PHASE+'.json'),CONFIG));window=json.loads(bind(E/'WINDOW-START.json','920ccff9ebb9668d03ab700e350650bbeea9fe45e5b09f0345c6bf72428b9b86'))
seal=json.loads(bind(R/'CANDIDATE-V31-SOURCE-SEAL.json',SEAL));b29=json.loads(bind(R/'CANDIDATE-V30-SOURCE-SEAL.json',V30));b28=json.loads(bind(R/'CANDIDATE-V28-SOURCE-SEAL.json',V28));sm_path=R/'paired-pin-private-dispatch-implementation-v31/PUBLISHABLE-SOURCE-MANIFEST.json';sm=json.loads(bind(sm_path,SM))
need(bind(E/'SOURCE-SEAL.json',SEAL)==raw(R/'CANDIDATE-V31-SOURCE-SEAL.json'),'Exact executed seal')
need(r['sequence_completed'] is True and r['failure'] is None and r['source_seal_unchanged'] is True and r['sdk_identity_unchanged'] is True and r['remaining_owned_descendants']==[] and len(r['stages'])==2,'Completed focused result')
need(r['finished']=='2026-10-11T07:08:32.030943+00:00' and r['elapsed_seconds']==11.909391335000691,'Exact terminal time')
need(config['source']==str(S) and config['source_seal_sha256']==SEAL and config['scope']==r['scope'] and config['additional_sources']==[dict(source=str(R/('candidate-v'+v)),seal=str(R/('CANDIDATE-V'+v+'-SOURCE-SEAL.json'))) for v in ('30','28')],'Actual primary/additional source bindings')
need(window['supervisor_sha256']==SHA(raw(R/'run_checkpoint_matrix.py'))==SUP and window['source_seal_sha256']==SEAL and window['python_optimize']==0 and window['runtime_gate_seconds']==5 and window['whole_window_seconds']==config['window_seconds']==10800,'Supervisor/caps')
need(bind(E/'SDK-BEFORE.json',SDK)==raw(E/'SDK-AFTER.json'),'SDK before/after')
need(set(seal)==set(b29)==set(b28) and len(seal)==3837 and {p for p in seal if seal[p]!=b29[p]}=={TEST},'Only one test changed atop v30')
need(sm['source_seal_sha256']==SEAL and sm['base_source_seal_sha256']==V30 and sm['delta_count']==1 and len(sm['files'])==1 and sm['files'][0]['path']==TEST,'Source-only repair manifest')
row=sm['files'][0];new=bind(S/TEST,row['sha256']);old=bind(B/TEST,row['before_sha256']);need(SHA(new)==seal[TEST] and SHA(old)==b29[TEST]==b28[TEST] and old==raw(R/'candidate-v28'/TEST) and len(new)==row['bytes']==56096,'Exact revised/before test')
need(hashlib.sha1(b'blob '+str(len(new)).encode()+b'\0'+new).hexdigest()==row['git_blob'] and row['mode']=='100644' and (S/TEST).stat().st_mode&0o111==0,'Revised test mode/blob')
# Both revised methods are synthetic controls; all other source AST remains exact.
old_ast=ast.parse(old);new_ast=ast.parse(new);projected=copy.deepcopy(new_ast)
def cls(t):return next(n for n in t.body if isinstance(n,ast.ClassDef) and n.name=='PairedPinFakeControls')
old_cls=cls(old_ast);new_cls=cls(new_ast);project_cls=cls(projected)
old_methods={n.name:n for n in old_cls.body if isinstance(n,ast.FunctionDef)}
need(CHANGED in old_methods and SECOND in old_methods,'Both revised methods pre-exist')
project_cls.body=[copy.deepcopy(old_methods[n.name]) if isinstance(n,ast.FunctionDef) and n.name in (CHANGED,SECOND) else n for n in project_cls.body]
need(ast.dump(projected,include_attributes=False)==ast.dump(old_ast,include_attributes=False),'Other source AST exact')
old_lines=old.splitlines(keepends=True);new_lines=new.splitlines(keepends=True)
for n in old_cls.body:
 if isinstance(n,ast.FunctionDef) and n.name not in (CHANGED,SECOND):
  m=next(x for x in new_cls.body if isinstance(x,ast.FunctionDef) and x.name==n.name);need(b''.join(old_lines[n.lineno-1:n.end_lineno])==b''.join(new_lines[m.lineno-1:m.end_lineno]),'Unchanged method bytes '+n.name)
method_count=lambda t:sum(isinstance(n,ast.FunctionDef) and n.name.startswith('test_') for c in t.body if isinstance(c,ast.ClassDef) for n in c.body)
need(method_count(old_ast)==method_count(new_ast)==33,'Full module still has33 methods; only2 selected')
need(all(seal[p]==b29[p] for p in seal if p!=TEST),'Production/fixtures unchanged from v30')
console=[json.loads(b) for b in raw(R/(PHASE+'.supervisor.log')).splitlines()];need(len(console)==3 and console[-1]==r,'Original console aggregate')
expected={'RESULT.json','SOURCE-SEAL.json','SDK-BEFORE.json','SDK-AFTER.json','WINDOW-START.json','LATEST.json','PROCESSES.jsonl'}
for i,(mode,stage,planned) in enumerate(zip(('normal','optimized'),r['stages'],config['stages'])):
 label=mode+'-paired-pin-private-dispatch';need(stage['label']==planned['label']==label and stage==json.loads(raw(E/(label+'-RESULT.json'))),'Stage order/result')
 need(all(stage.get(k)==v for k,v in json.loads(raw(E/(label+'-START.json'))).items()),'START/result')
 command=[str(R.parent/'restored-toolchain/official-venv/bin/python')]+(['-O'] if i else [])+['-B','-m','unittest','discover','-s','tools/carla_lane_oracle','-p','test_paired_pin_contracts.py','-k',CHANGED,'-k',SECOND,'-v']
 need(stage['argv']==command and planned['command']==['{python}']+command[1:] and stage['cwd']==str(S),'Exact two-method command')
 need(stage['returncode']==0 and not stage['timed_out'] and stage['source_seal_sha256']==SEAL and stage['stage_timeout_seconds']==planned['seconds']==1800 and stage['test_count']==stage['expected_tests']==planned['expected_tests']==2 and stage['skipped_test_count']==0 and stage['leader_reaped'] and stage['remaining_owned_descendants']==[],'Outcome/count/cap/cleanup')
 need(console[i]=={k:v for k,v in stage.items() if k not in ('test_count','expected_tests','skipped_test_count')},'Pre-annotation console bytes')
 log=bind(E/(label+'.log'),stage['log_sha256']).decode();need(re.findall(r'^Ran (\d+) tests? in ',log,re.M)==['2'] and log.rstrip().endswith('OK') and ' ... skipped ' not in log and not re.search(r'^(FAIL|ERROR): ',log,re.M),'Full raw focused log')
 need(re.findall(r'^(test_\w+) \(test_paired_pin_contracts\.PairedPinFakeControls\.',log,re.M)==sorted([CHANGED,SECOND]),'Only exact two named methods');expected.update((label+'-START.json',label+'-RESULT.json',label+'.log'))
need({p.name for p in E.iterdir()}==expected and len(expected)==13,'Complete focused file inventory')
processes=[json.loads(b) for b in raw(E/'PROCESSES.jsonl').splitlines()];need(processes and json.loads(raw(E/'LATEST.json'))==processes[-1],'Focused process terminal snapshot')
# One complete handoff excerpt; all mutable continuation files remain excluded.
hp=R/'evidence/full-python-diagnostic-continuation-v28/LANE-HANDOFFS.jsonl';observed=raw(hp);hl=observed.splitlines(keepends=True);selected=[(i,b,json.loads(b)) for i,b in enumerate(hl) if json.loads(b).get('started')=='2026-10-11T07:07:40.195348+00:00'];need(len(selected)==1,'Unique completed handoff');hi,hb,h=selected[0]
need(h['paused'] is False and h['resumed']=='2026-10-11T07:08:41.297263+00:00' and h['next_stage']=='22-optimized-test_reviewed_cleanup_contracts' and h['source_seal_sha256']==V28 and h['remaining_owned_descendants']==[],'Exact completed handoff')
need(datetime.fromisoformat(h['started'])<datetime.fromisoformat(window['started'])<datetime.fromisoformat(r['finished'])<datetime.fromisoformat(h['resumed']),'Entire focus within completed handoff')
selection=dict(line_number=hi+1,byte_offset=sum(map(len,hl[:hi])),bytes=len(hb));handoff_meta=dict(schema=1,kind='one-completed-record-byte-exact-extraction',original_stream=str(hp),selection=selection,record_sha256=SHA(hb),observed_stream_bytes=len(observed),observed_stream_sha256=SHA(observed),snapshot_observed_utc=datetime.now(timezone.utc).isoformat(),boundary='Only the specified completed record is copied. Its source stream is mutable; the observed stream hash is timestamped provenance, not a final continuation binding. No other continuation files/results are read or included.')
originals=[]
def add(p,name,kind,readable=False):originals.append(dict(path=name,data=raw(p),original_source=str(p),kind=kind,readable=readable))
for name in sorted(expected):add(E/name,'actual/'+PHASE+'/'+name,'original-completed-focused-phase',name in ('RESULT.json','SDK-BEFORE.json','SDK-AFTER.json','WINDOW-START.json') or name.endswith('.log'))
for name in (PHASE+'.json',PHASE+'.supervisor.log','run_checkpoint_matrix.py','CANDIDATE-V31-SOURCE-SEAL.json','CANDIDATE-V30-SOURCE-SEAL.json','CANDIDATE-V28-SOURCE-SEAL.json','PUBLISHED-V28-QUALIFICATION-BINDING.json'):
 add(R/name,'reproduce/'+name,'exact-supervisor-command-console-or-source-baseline-binding',name in (PHASE+'.json','run_checkpoint_matrix.py','PUBLISHED-V28-QUALIFICATION-BINDING.json'))
bind(R/'PUBLISHED-V28-QUALIFICATION-BINDING.json','0df492bd6c870ecb2e8a6d3cb66167c2d5042aa7ba0a70d4b42f02f71eef8bdf');add(sm_path,'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json','original-source-only-repair-manifest',True)
add(S/TEST,'reproduce/source-v31/'+TEST,'exact-revised-test-source',True);add(B/TEST,'reproduce/source-before-v30-and-v28/'+TEST,'exact-shared-before-test-source')
for p in ('tools/coverage_toolchain_identity.py','tools/carla_lane_oracle/full_audit_cleanup_contracts.py','tools/carla_lane_oracle/frozen_arc_producer_contracts.py','tools/carla_lane_oracle/coverage_invariant_contracts.py','tools/carla_lane_oracle/coverage_followup_contracts.py','tools/carla_lane_oracle/_full_audit_test_fixtures.py'):
 bind(S/p,seal[p]);add(S/p,'reproduce/unchanged-source/'+p,'exact-unchanged-helper-fixture-or-sdk-source')
originals.append(dict(path='actual/completed-v28-handoff/COMPLETED-HANDOFF.jsonl',data=hb,original_source=str(hp),source_selection=selection,kind='byte-exact-selected-completed-handoff-record',readable=True))
summary=dict(schema=1,status='PASS_SEPARATE_V31_TWO_SYNTHETIC_METHOD_FOCUS_ONLY',scope='The two revised paired-pin synthetic methods passed normally and optimized, four executions, zero skips. This test-only correction atop v30 does not qualify the complete33-method module, real source admission, full matrix, native suite or coverage.',source_seal_sha256=SEAL,additional_baseline_seal_sha256={'v30':V30,'v28':V28},result_sha256=RESULT,config_sha256=CONFIG,source_manifest_sha256=SM,supervisor_sha256=SUP,sdk_receipt_sha256=SDK,finished=r['finished'],whole_window_seconds=r['elapsed_seconds'],stage_cap_seconds=1800,window_cap_seconds=10800,selected_methods=[CHANGED,SECOND],actual_stage_results=r['stages'],source_sdk_unchanged=True,remaining_owned_descendants=[],test_only_delta=dict(path=TEST,before_sha256=SHA(old),after_sha256=SHA(new),new_method_count=0,changed_method_count=2,total_module_method_count=33,other_source_ast_preserved=True,all_other_3836_seal_entries_unchanged=True),additional_baseline_boundary='Exact config binds candidate-v30 and candidate-v28 as additional source trees; unchanged supervisor verifies them at its verification points. The primary source-stability flag is not a separately named per-baseline flag.',control_semantics='Synthetic fixed-shape control now checks private keyword-only _operation=None while retaining public root-only checks. Initial-owner fake control intercepts the actual private invariant pair, checks the real pending owner handle and record/pair/source ordering, and blocks public-pair bypass and full source admission. Fake pin results and early StopAfterPins do not establish real source admission or complete verification.',completed_handoff_record_sha256=SHA(hb),completed_handoff_resumed=h['resumed'],handoff_boundary='Only the specified completed handoff record is included. Its interval contains the focused window. No mutable continuation file or result is packaged.',historical_status_boundary='Original source-only manifest keeps its earlier pending-execution wording; later focused PASS is separate. Original v28 matrix and paired-pin failures stay unchanged; later continuation results are not credited.',pending_scope='Complete33-method paired-pin module, full normal/optimized matrix, paired native controls, maintained coverage, hosted CI and issue completion remain outside this focused evidence.',reproduction_boundary='All13 completed phase files, exact config/console/supervisor, three source seals, v28 published baseline binding, revised/before test, six unchanged related sources and one completed handoff excerpt. Full unchanged repository and installed SDK image are not distributed.',evidence_policy='Original bytes and labeled derived metadata only. No private notes, candidate changes, project imports, tests/native runs or uploads.')
commands=dict(schema=1,kind='derived-actual-command-and-baseline-binding',config_sha256=CONFIG,result_sha256=RESULT,source_seal_sha256=SEAL,baseline_seals={'v30':V30,'v28':V28},actual_stages=r['stages'],actual_console_sha256=SHA(raw(R/(PHASE+'.supervisor.log'))))
archive='containers/ORIGINAL-EVIDENCE.json.gz.b64';members=[];archived=[];payloads=[];need(len(originals)==len({x['path'] for x in originals}),'Duplicate originals')
for row in sorted(originals,key=lambda x:x['path']):
 b=row['data'];m={k:row[k] for k in ('path','kind','original_source')};m.update(bytes=len(b),sha256=SHA(b))
 if 'source_selection' in row:m['source_selection']=row['source_selection']
 if row['readable']:
  b.decode();payloads.append((row['path'],b,'byte-exact-readable-original'));m.update(storage='readable',transport_path=row['path'])
 else:
  archived.append(dict(path=row['path'],bytes=len(b),sha256=SHA(b),data_base64=base64.b64encode(b).decode()));m.update(storage='container',transport_path=archive)
 members.append(m)
container=(json.dumps(dict(schema=1,encoding='base64',members=archived),sort_keys=True,separators=(',',':'))+'\n').encode();need(len(container)<64*1024*1024,'Decoder limit');encoded=base64.b64encode(gzip.compress(container,compresslevel=9,mtime=0))+b'\n';need(gzip.decompress(base64.b64decode(encoded))==container,'Reversible container')
inner=dict(schema=1,original_member_count=len(members),original_member_bytes=sum(x['bytes'] for x in members),container=dict(path=archive,encoding='base64 of deterministic gzip mtime=0 containing JSON',members=len(archived),json_bytes=len(container),json_sha256=SHA(container)),members=members)
decoder=bind(R/'validation-evidence-qualification-policy-v23-packet/decode_verify.py','a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4')
guide='''# Separate v31 paired-pin private-dispatch focused qualification

PASS within this narrow synthetic focus: two revised methods per mode, four
executions, zero skips. Normal elapsed0.502909742seconds and optimized
1.003429976seconds; whole window11.909391335seconds. Caps remain1,800seconds
per stage and10,800seconds per window. Source/SDK receipts were unchanged;
both leaders were reaped with no remaining owned descendants.

Only the paired-pin test file changes atop sealed v30, with exactly two existing
method bodies revised. No test is added; the complete module still has33methods.
All other source AST and nonrevised method bytes are preserved. Before-test
bytes also match v28. One control checks the private keyword-only operation
parameter while retaining public signatures. The other intercepts the actual
private invariant dispatch, verifies pending-owner and call-order behavior,
and blocks public-pair bypass and full admission. This synthetic focus does
not establish real source admission or a complete33-method module pass.

The exact config additionally binds v30 and v28 source trees. The unchanged
supervisor checks them at its verification points; the single primary stability
flag is not an invented per-baseline receipt. The original source-only manifest
keeps its earlier pending wording, and this later focused result is separate.
Old v28 failed qualification and paired-pin diagnostics are not rewritten.

All thirteen actual phase files, full logs/console, commands/caps, source/SDK
seals, before/revised test and unchanged related source are retained. The full
focused window lies in one completed v28 handoff ending07:08:41.297263UTC.
Only that exact completed record is extracted with byte-range provenance.
No mutable continuation files or later outcomes are included or credited.
This packet contains only this completed execution and does not reconstruct
or fabricate any earlier setup-attempt receipt.

Readable originals retain exact bytes. Other originals use per-member base64
JSON, deterministic gzip mtime=0, then base64. Inner manifest records original
paths/sizes/hashes/storage; outer seals all payloads except itself. Summary,
command index and snapshot provenance are derived. The unchanged repository
and SDK executable image are not distributed. Full matrix, native/coverage,
hosted CI and issue completion remain outside this focused PASS.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The copied reviewed decoder validates safe paths/hashes/sizes, rejects symlinks
and existing output, and never executes decoded contents. Packaging performs
no project imports, tests/native runs, candidate changes or uploads. Private
notes are excluded; existing manifest review hashes remain provenance only.
''' 
payloads.extend([(archive,encoded,'lossless-original-receipts-source-and-bindings'),('INNER-MEMBER-MANIFEST.json',JSON(inner),'complete-original-member-inventory'),('VALIDATION-SUMMARY.json',JSON(summary),'derived-focused-scope-summary'),('COMMAND-RECEIPT-SEAL.json',JSON(commands),'derived-command-and-baseline-binding'),('COMPLETED-HANDOFF-SNAPSHOT-PROVENANCE.json',JSON(handoff_meta),'derived-specific-completed-record-extraction'),('decode_verify.py',decoder,'reviewed-safe-decoder-no-execution'),('reproduce/build_paired_pin_private_dispatch_focused_v31_packet.py',raw(Path(__file__)),'source-only-packet-builder'),('README.md',guide.encode(),'scope-and-safe-transport-guide')])
need(len(payloads)==len({n for n,_,_ in payloads})<=35,'Payload count/names')
patterns=(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',rb'gh[pousr]_[A-Za-z0-9]{30,}',rb'AKIA[0-9A-Z]{16}',rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
for row in originals:
 need(not any(re.search(p,row['data']) for p in patterns),'Credential pattern '+row['path']);b=raw(Path(row['original_source']))
 if 'source_selection' in row:
  x=row['source_selection'];b=b[x['byte_offset']:x['byte_offset']+x['bytes']]
 need(b==row['data'],'Original changed during packaging')
O.mkdir();rows=[]
for name,b,kind in sorted(payloads):
 p=O/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(b)
 need(raw(p)==b,'Written payload mismatch');rows.append(dict(path=name,local_source=str(p),bytes=len(b),sha256=SHA(b),kind=kind))
p=O/'PUBLISHABLE-EVIDENCE-MANIFEST.json'
with p.open('xb') as f:f.write(JSON(dict(schema=1,scope=summary['scope'],files=rows)))
print(json.dumps(dict(manifest=str(p),sha256=SHA(raw(p)),payloads=len(rows),original_members=len(members),archived_members=len(archived),original_bytes=inner['original_member_bytes'],packet_bytes_including_manifest=sum(x['bytes'] for x in rows)+len(raw(p)),result_sha256=RESULT)))
