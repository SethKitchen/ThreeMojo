"""Package two terminal optional-runtime diagnostic stages, never live phase state.

No project imports, tests/native runs, candidate edits or uploads. Only named
terminal stage files and constant source/protocol bindings are read; no overall
continuation RESULT, LATEST, PROCESSES, SDK-AFTER or console is read or copied.
"""
from pathlib import Path
from datetime import datetime, timedelta
import ast, base64, gzip, hashlib, json, re
R=Path(__file__).resolve().parent;PHASE='full-python-diagnostic-continuation-v28';E=R/'evidence'/PHASE;S=R/'candidate-v28';O=R/'validation-evidence-optional-runtime-v28-failure-pair-packet'
SEAL='fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596';SDK='7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207';SUP='0c6cf71e8be2fe48be76414cd800449e382569de824424a9e51110e90bc50ffc';CONFIG='a7282c67969f81b7e323cb685ed635db516aaf79621ea107d3d86ff2ecf1a0b3'
PINNED={
'17-normal-test_optional_runtime_contracts-START.json':'320962c1173f90d7540a6685917caa20fb3901850ea2a184c9826151b2179583',
'17-normal-test_optional_runtime_contracts-RESULT.json':'e23c02fac9a02824073c1098307055e5d757981a71d76ac3b2f629e7668a5a8c',
'17-normal-test_optional_runtime_contracts.log':'0ed334f0c2a5d3391b21f68a8bea034dfed7272fa445df84bba043892b2f8329',
'17-optimized-test_optional_runtime_contracts-START.json':'33d8d63968292a937c0ba67f08ef8ee4f628c7561c3ffa8f4ae0d704278e595b',
'17-optimized-test_optional_runtime_contracts-RESULT.json':'a3d0fb6027e393bf5737af63e27e0394b3cf74acda2e47fc1944da179d4ac480',
'17-optimized-test_optional_runtime_contracts.log':'376eeef74e9a7cf3b43d55d9583e00c5f738ac81d0020723b2d56217abfedd89'}
SHA=lambda b:hashlib.sha256(b).hexdigest();JSON=lambda x:(json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def need(x,m):
 if not x:raise ValueError(m)
def raw(p):
 need(p.is_file() and not p.is_symlink(),'Nonregular '+str(p));return p.read_bytes()
def bind(p,h):
 b=raw(p);need(SHA(b)==h,'Changed '+str(p));return b
need(not O.exists(),'Never overwrite evidence')
config=json.loads(bind(R/(PHASE+'.json'),CONFIG));supervisor=bind(R/'run_diagnostic_continuation_v28.py',SUP);seal=json.loads(bind(R/'CANDIDATE-V28-SOURCE-SEAL.json',SEAL))
need(bind(E/'SOURCE-SEAL.json',SEAL)==raw(R/'CANDIDATE-V28-SOURCE-SEAL.json'),'Executed source binding')
window=json.loads(bind(E/'WINDOW-START.json','d87934d76871e7ba07167d30214cfc93a7c6746be3574d26e21abc4d74c63cc4'));bind(E/'SDK-BEFORE.json',SDK)
need(config['diagnostic_only'] is True and config['qualification_passed'] is False and config['source_seal_sha256']==SEAL and config['source']==str(S) and len(config['stages'])==137,'Exact diagnostic config')
need(config['supervisor_sha256']==window['supervisor_sha256']==SUP and window['source_seal_sha256']==SEAL and window['python_optimize']==0 and window['runtime_gate_seconds']==5,'Window/supervisor source identity')
original_path=R/'evidence/full-python-matrix-final-v28/RESULT.json';original=json.loads(bind(original_path,'a2d054ac36ac97e729d292956a2233f10b479b6f40194fec90c9f088858be844'))
need(config['original_matrix_result_sha256']==SHA(raw(original_path)) and original['sequence_completed'] is False and original['failure'],'Original failed qualification stays failed')
deadline=datetime.fromisoformat(original['finished'])+timedelta(seconds=10800-original['elapsed_seconds']);need(deadline.isoformat()==config['absolute_deadline_utc']=='2026-10-11T08:35:38.016452+00:00' and window['whole_window_seconds']==9158.74437 and config['window_seconds']==10800,'Original absolute-deadline clamp')
inv_path=R/'FINAL-PYTHON-EXPECTED-INVENTORY-V28.json';inv=json.loads(bind(inv_path,'0996f6650319b26da030bcfccf85868e2eba6b755a46063bec9daabfd796a2f9'));need(config['expected_inventory_sha256']==SHA(raw(inv_path)),'Fresh expected inventory binding')
test='tools/carla_lane_oracle/test_optional_runtime_contracts.py';module=next(m for m in inv['modules'] if m['path']==test);need(module['test_count']==95 and module['sha256']==seal[test],'Selected source/discovery count')
stages=[];log_names=[];positions=[]
for mode in ('normal','optimized'):
 label='17-'+mode+'-test_optional_runtime_contracts';index=next(i for i,x in enumerate(config['stages']) if x['label']==label);positions.append(index+1);planned=config['stages'][index]
 stage=json.loads(bind(E/(label+'-RESULT.json'),PINNED[label+'-RESULT.json']));start=json.loads(bind(E/(label+'-START.json'),PINNED[label+'-START.json']));log=bind(E/(label+'.log'),PINNED[label+'.log']).decode()
 need(all(stage.get(k)==v for k,v in start.items()),'START/result agreement')
 cmd=[str(R.parent/'restored-toolchain/official-venv/bin/python')]+(['-O'] if mode=='optimized' else [])+['-B','-m','unittest','discover','-s','tools/carla_lane_oracle','-p','test_optional_runtime_contracts.py','-v']
 need(stage['label']==label and stage['argv']==cmd and planned['command']==['{python}']+cmd[1:] and stage['cwd']==str(S),'Actual command')
 need(planned['accept_nonzero'] is True and stage['returncode']==1 and not stage['timed_out'] and stage['stage_timeout_seconds']==planned['seconds']==1800,'Diagnostic nonzero/cap')
 need(stage['source_seal_sha256']==SEAL and stage['leader_reaped'] is True and stage['remaining_owned_descendants']==[] and stage['test_count']==stage['expected_tests']==planned['expected_tests']==95 and stage['skipped_test_count']==0,'Terminal count/cleanup')
 need(re.findall(r'^Ran (\d+) tests? in ',log,re.M)==['95'] and log.rstrip().endswith('FAILED (errors=1)') and ' ... skipped ' not in log and len(re.findall(r'^ERROR: ',log,re.M))==1 and not re.search(r'^FAIL: ',log,re.M),'Exact raw one-error outcome')
 names=re.findall(r'^(test_\w+) \(test_optional_runtime_contracts\.OptionalRuntimeContracts\.',log,re.M);need(len(names)==95 and len(set(names))==95,'Ninety-five named methods')
 expected_ids=module['modes']['1' if mode=='optimized' else '0']['test_ids'];need({'test_optional_runtime_contracts.OptionalRuntimeContracts.'+n for n in names}==set(expected_ids),'Raw method names match fresh inventory')
 need('ERROR: test_absence_checks_actual_solver_imports_and_inert_decoys' in log and 'line 468, in test_absence_checks_actual_solver_imports_and_inert_decoys' in log and 'self.assertEqual(guards.verify(ROOT)[\'status\'], \'PASS\')' in log and 'full_audit_cleanup_contracts._OperationCoherenceError: full-audit cleanup successor: consumed operation text changed: extensions/carla/lane_refinement.mojo' in log,'Exact split-read failure path')
 stages.append(stage);log_names.append(names)
need(positions==[18,19] and log_names[0]==log_names[1],'Selected positions/same method order')
test_raw=bind(S/test,seal[test]);tree=ast.parse(test_raw);lines=test_raw.decode().splitlines();need(lines[467].strip()=="self.assertEqual(guards.verify(ROOT)['status'], 'PASS')",'Original error line')
method=next(n for c in tree.body if isinstance(c,ast.ClassDef) for n in c.body if isinstance(n,ast.FunctionDef) and n.name=='test_absence_checks_actual_solver_imports_and_inert_decoys');method_text='\n'.join(lines[method.lineno-1:method.end_lineno]);need("prefix = '# cached_model _restrict_objective_model\\n'" in method_text and "patch.object(Path, 'read_text'" in method_text and "'read_bytes'" not in method_text,'Original inert-comment split-read hook')
source_paths=[test,'tools/carla_lane_oracle/optional_runtime_contracts.py','tools/carla_lane_oracle/source_contracts.py','tools/carla_lane_oracle/sum2_guard_contracts.py','tools/carla_lane_oracle/reviewed_cleanup_contracts.py','tools/carla_lane_oracle/coverage_invariant_contracts.py','tools/carla_lane_oracle/coverage_followup_contracts.py','tools/carla_lane_oracle/full_audit_cleanup_contracts.py','tools/coverage_toolchain_identity.py','extensions/carla/lane_refinement.mojo']
for p in source_paths:bind(S/p,seal[p])
originals=[]
def add(p,name,kind,readable=False):originals.append(dict(path=name,data=raw(p),original_source=str(p),kind=kind,readable=readable))
for name in sorted(PINNED):add(E/name,'actual/selected-terminal-stages/'+name,'original-terminal-stage-start-result-or-complete-merged-log',True)
for name in ('SOURCE-SEAL.json','SDK-BEFORE.json','WINDOW-START.json'):add(E/name,'actual/constant-continuation-bindings/'+name,'constant-original-source-sdk-or-window-binding',name!='SOURCE-SEAL.json')
for name in (PHASE+'.json','run_diagnostic_continuation_v28.py','FINAL-PYTHON-EXPECTED-INVENTORY-V28.json','CANDIDATE-V28-SOURCE-SEAL.json','PUBLISHED-V28-QUALIFICATION-BINDING.json'):
 add(R/name,'reproduce/'+name,'constant-diagnostic-protocol-inventory-or-published-source-binding',name in (PHASE+'.json','run_diagnostic_continuation_v28.py','PUBLISHED-V28-QUALIFICATION-BINDING.json'))
bind(R/'PUBLISHED-V28-QUALIFICATION-BINDING.json','0df492bd6c870ecb2e8a6d3cb66167c2d5042aa7ba0a70d4b42f02f71eef8bdf')
add(original_path,'reproduce/original-failed-matrix-RESULT.json','unchanged-original-qualification-failure-deadline-input')
for p in source_paths:add(S/p,'reproduce/source/'+p,'exact-seal-bound-test-observer-guard-or-source',p==test)
summary=dict(schema=1,status='TWO_TERMINAL_OPTIONAL_RUNTIME_DIAGNOSTIC_ERRORS_NOT_QUALIFICATION',scope='Two selected completed diagnostic stages on immutable v28: normal and optimized optional-runtime each ran95methods with94passing and1error, zero skips. Both retained1800-second stage caps and returned1 without timeout. This selected pair is not a passing module, complete continuation result or full qualification.',source_seal_sha256=SEAL,base_published_commit='031f9f726edb6e9409853fd777af966c8ebba88d',source_tree='d2c9f94523b9c03aa94b04eaad774f73f147cd74',config_sha256=CONFIG,supervisor_sha256=SUP,sdk_before_sha256=SDK,selected_stage_results=stages,per_mode=dict(methods_run=95,passed=94,errors=1,failures=0,skips=0),selected_pair_total=dict(methods_run=190,passed=188,errors=2),error_method='OptionalRuntimeContracts.test_absence_checks_actual_solver_imports_and_inert_decoys',error_type='full_audit_cleanup_contracts._OperationCoherenceError',error_message='full-audit cleanup successor: consumed operation text changed: extensions/carla/lane_refinement.mojo',source_read_boundary='Original test patches Path.read_text to prepend an inert comment to lane_refinement.mojo while leaving Path.read_bytes unpatched. The raw traceback shows rejection at the owned consumed-text comparison during guards.verify(ROOT), after optional.verify(ROOT) returned. This packet records that error; it does not change or waive the existing assertion.',selected_config_positions_one_based=positions,configured_continuation_stage_count=137,other_135_stage_outcomes='Outside this packet; no pass/fail/unrun or completion status assigned.',completed_prefix_disclosure='Only the two specified terminal stage receipts at positions18/19 of the diagnostic configuration are packaged. No assertion that this packet contains all completed prefix stages. Collection-level RESULT, LATEST, PROCESSES, SDK-AFTER, ongoing console and handoff files are neither read nor copied.',source_sdk_check_boundary='Each terminal receipt has post-run test-count annotations. In the exact included supervisor those annotations are written only after run returns through source verification and SDK comparison. This is a control-flow inference from terminal receipts, not a fabricated overall source/SDK-after receipt. The constant initial source and SDK bindings are retained; no final collection stability claim is made.',cleanup_boundary='Each selected leader was reaped and its receipt reports no remaining owned descendants. No live process status for the overall continuation is asserted.',original_window=dict(configured_seconds=10800,clamped_seconds_recorded_at_start=window['whole_window_seconds'],absolute_deadline_utc=config['absolute_deadline_utc'],original_failed_matrix_result_sha256=config['original_matrix_result_sha256']),original_failure_boundary='Original v28 full-matrix failure remains failed and unchanged. Diagnostic accept_nonzero collects ordinary errors without converting them to passes. Any later v30 focus, repair or diagnostic result is excluded.',qualification_limit='No passing optional-runtime module, complete continuation, full matrix, native/coverage, hosted CI or issue completion.',reproduction_boundary='Contains six selected terminal stage files, only constant phase bindings, exact diagnostic config and supervisor, expected inventory, source/publication seals, original failure deadline input, and ten bound relevant source files. The complete unchanged repository and installed SDK are not distributed.',evidence_policy='Exact original bytes plus clearly derived summaries/index. No mutable ongoing files, private notes, test/native execution, candidate edits, uploads or invented receipts.')
commands=dict(schema=1,kind='derived-selected-commands-and-binding-index',source_seal_sha256=SEAL,config_sha256=CONFIG,supervisor_sha256=SUP,stage_files_sha256=PINNED,selected_stages=stages,scope='Selected terminal pair only; no aggregate continuation status.')
archive='containers/ORIGINAL-EVIDENCE.json.gz.b64';members=[];archived=[];payloads=[];need(len(originals)==len({r['path'] for r in originals}),'Duplicate originals')
for row in sorted(originals,key=lambda r:r['path']):
 b=row['data'];m={k:row[k] for k in ('path','kind','original_source')};m.update(bytes=len(b),sha256=SHA(b))
 if row['readable']:
  b.decode();payloads.append((row['path'],b,'byte-exact-readable-original'));m.update(storage='readable',transport_path=row['path'])
 else:
  archived.append(dict(path=row['path'],bytes=len(b),sha256=SHA(b),data_base64=base64.b64encode(b).decode()));m.update(storage='container',transport_path=archive)
 members.append(m)
container=(json.dumps(dict(schema=1,encoding='base64',members=archived),sort_keys=True,separators=(',',':'))+'\n').encode();need(len(container)<64*1024*1024,'Decoder size limit');encoded=base64.b64encode(gzip.compress(container,compresslevel=9,mtime=0))+b'\n';need(gzip.decompress(base64.b64decode(encoded))==container,'Lossless roundtrip')
inner=dict(schema=1,original_member_count=len(members),original_member_bytes=sum(x['bytes'] for x in members),container=dict(path=archive,encoding='base64 of deterministic gzip mtime=0 containing JSON',members=len(archived),json_bytes=len(container),json_sha256=SHA(container)),members=members)
decoder=bind(R/'validation-evidence-qualification-policy-v23-packet/decode_verify.py','a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4')
guide='''# V28 optional-runtime terminal diagnostic failure pair

ERROR in both selected modes. Each ran 95 methods: 94 passed and one errored,
zero skips. Normal elapsed 741.056556715 seconds; optimized 736.246391576.
Each returned 1 without timeout under its unchanged 1,800-second module cap.
The complete original raw logs and START/RESULT receipts are readable.

Both errors are test_absence_checks_actual_solver_imports_and_inert_decoys:
the inert-comment Path.read_text hook leaves Path.read_bytes unchanged, and
the owned guard rejects consumed text differing from its captured bytes.
The exact traceback and original assertion are preserved, not repaired or
waived by this packet. The 188 passing methods do not turn either module into
a pass. Diagnostic accept_nonzero allows collection; it is not qualification.

This packet selects configuration positions 18 and 19 of a 137-stage diagnostic
continuation. It does not contain or claim the whole completed prefix, assign
outcomes to the other 135 stages, or establish a collection-level result.
No ongoing RESULT, LATEST, PROCESSES, SDK-AFTER, console or handoff file is read
or copied. Only constant WINDOW-START, SOURCE-SEAL and SDK-BEFORE bindings are
included. The original absolute deadline remains 2026-10-11T08:35:38.016452Z;
the initial clamped window was 9,158.74437 seconds. The original failed matrix
result used to derive that deadline remains unchanged and separately identified.

Terminal receipts include test-count annotations written only after the exact
supervisor returns through post-stage source/SDK checks. That control-flow
inference is disclosed; there is no invented overall after-receipt. Both selected
leaders were reaped and each terminal receipt reports no remaining descendants.
No live process state or final continuation stability is asserted.

The inner manifest records original paths, byte sizes, hashes and storage.
Readable originals are byte-exact; others are base64 JSON members, deterministic
gzip mtime=0, then base64. Full raw merged logs are preserved without reconstructing
separate streams. The outer manifest seals all payloads except itself. Summary
and command index are derived. Exact relevant source is included; the full
unchanged repository and installed SDK image are not distributed. No private
notes, later v30 result or mutable continuation file enters this packet.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The copied reviewed decoder checks safe paths, hashes and sizes, rejects symlinks
and existing output, and never executes decoded contents. Packaging performs
no project imports, tests/native runs, candidate edits or uploads.
'''
payloads.extend([(archive,encoded,'lossless-original-source-and-constant-bindings'),('INNER-MEMBER-MANIFEST.json',JSON(inner),'complete-original-member-inventory'),('VALIDATION-SUMMARY.json',JSON(summary),'derived-selected-error-pair-scope-summary'),('COMMAND-RECEIPT-SEAL.json',JSON(commands),'derived-selected-command-binding-index'),('decode_verify.py',decoder,'reviewed-safe-decoder-no-execution'),('reproduce/build_optional_runtime_failure_pair_v28_packet.py',raw(Path(__file__)),'source-only-packet-builder'),('README.md',guide.encode(),'scope-and-safe-transport-guide')])
need(len(payloads)==len({n for n,_,_ in payloads})<=35,'Payload count/names')
patterns=(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',rb'gh[pousr]_[A-Za-z0-9]{30,}',rb'AKIA[0-9A-Z]{16}',rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
for row in originals:
 need(not any(re.search(p,row['data']) for p in patterns),'Credential pattern '+row['path']);need(raw(Path(row['original_source']))==row['data'],'Original changed during packaging')
O.mkdir();rows=[]
for name,b,kind in sorted(payloads):
 p=O/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(b)
 need(raw(p)==b,'Copy mismatch');rows.append(dict(path=name,local_source=str(p),bytes=len(b),sha256=SHA(b),kind=kind))
p=O/'PUBLISHABLE-EVIDENCE-MANIFEST.json'
with p.open('xb') as f:f.write(JSON(dict(schema=1,scope=summary['scope'],files=rows)))
print(json.dumps(dict(manifest=str(p),sha256=SHA(raw(p)),payloads=len(rows),original_members=len(members),archived_members=len(archived),original_bytes=inner['original_member_bytes'],packet_bytes_including_manifest=sum(x['bytes'] for x in rows)+len(raw(p)))))
