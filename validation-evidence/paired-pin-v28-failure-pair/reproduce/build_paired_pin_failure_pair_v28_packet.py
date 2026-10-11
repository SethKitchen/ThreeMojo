"""Package two terminal paired-pin diagnostic stages, never live phase state.

No project imports, tests/native runs, candidate edits or uploads. Only named
terminal stage files and constant source/protocol bindings are read; no overall
continuation RESULT, LATEST, PROCESSES, SDK-AFTER or console is read or copied.
"""
from pathlib import Path
from datetime import datetime, timedelta
import ast, base64, gzip, hashlib, json, re
R=Path(__file__).resolve().parent;PHASE='full-python-diagnostic-continuation-v28';E=R/'evidence'/PHASE;S=R/'candidate-v28';O=R/'validation-evidence-paired-pin-v28-failure-pair-packet'
SEAL='fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596';SDK='7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207';SUP='0c6cf71e8be2fe48be76414cd800449e382569de824424a9e51110e90bc50ffc';CONFIG='a7282c67969f81b7e323cb685ed635db516aaf79621ea107d3d86ff2ecf1a0b3'
PINNED={'18-normal-test_paired_pin_contracts-START.json': '5a8931ace5cc1437abc174767eb299c46a7c4e3680edf41c0a2a1e4bdac86619', '18-normal-test_paired_pin_contracts-RESULT.json': 'aa2f6e033172d77d253adcd2fc3c3c6bb9f2b0f8417ff98c60aa64971e7715aa', '18-normal-test_paired_pin_contracts.log': '417fd79076c5cbc27082d7717f2ffeeb21f9e8483180c724ede0f97fa05c78e3', '18-optimized-test_paired_pin_contracts-START.json': 'e26f87503c1f831f95594fd02464e006ef2c735804ea3cf9a53d5b8a1a28de85', '18-optimized-test_paired_pin_contracts-RESULT.json': '8a0ee08d24b505abf2a2aefe4125476456402612760a1ac06ff134166f8d8969', '18-optimized-test_paired_pin_contracts.log': '31134047816c2f1893557807a1a7570ed13c897bc3c75b3dd8c79ea2fbca46b3'}
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
test='tools/carla_lane_oracle/test_paired_pin_contracts.py';module=next(m for m in inv['modules'] if m['path']==test);need(module['test_count']==33 and module['sha256']==seal[test],'Selected source/discovery count')
stages=[];log_names=[];positions=[]
for mode in ('normal','optimized'):
 label='18-'+mode+'-test_paired_pin_contracts';index=next(i for i,x in enumerate(config['stages']) if x['label']==label);positions.append(index+1);planned=config['stages'][index]
 stage=json.loads(bind(E/(label+'-RESULT.json'),PINNED[label+'-RESULT.json']));start=json.loads(bind(E/(label+'-START.json'),PINNED[label+'-START.json']));log=bind(E/(label+'.log'),PINNED[label+'.log']).decode()
 need(all(stage.get(k)==v for k,v in start.items()),'START/result agreement')
 cmd=[str(R.parent/'restored-toolchain/official-venv/bin/python')]+(['-O'] if mode=='optimized' else [])+['-B','-m','unittest','discover','-s','tools/carla_lane_oracle','-p','test_paired_pin_contracts.py','-v']
 need(stage['label']==label and stage['argv']==cmd and planned['command']==['{python}']+cmd[1:] and stage['cwd']==str(S),'Actual command')
 need(planned['accept_nonzero'] is True and stage['returncode']==1 and not stage['timed_out'] and stage['stage_timeout_seconds']==planned['seconds']==1800,'Diagnostic nonzero/cap')
 need(stage['source_seal_sha256']==SEAL and stage['leader_reaped'] is True and stage['remaining_owned_descendants']==[] and stage['test_count']==stage['expected_tests']==planned['expected_tests']==33 and stage['skipped_test_count']==0,'Terminal count/cleanup')
 need(re.findall(r'^Ran (\d+) tests? in ',log,re.M)==['33'] and log.rstrip().endswith('FAILED (failures=1, errors=1)') and ' ... skipped ' not in log and len(re.findall(r'^ERROR: ',log,re.M))==1 and len(re.findall(r'^FAIL: ',log,re.M))==1,'Exact raw failure/error outcome')
 names=re.findall(r'^(test_\w+) \(test_paired_pin_contracts\.([A-Za-z_]+)\.',log,re.M);need(len(names)==33 and len(set(names))==33,'Thirty-three named methods')
 expected_ids=module['modes']['1' if mode=='optimized' else '0']['test_ids'];need({'test_paired_pin_contracts.'+cls+'.'+name for name,cls in names}==set(expected_ids),'Raw method names match fresh inventory')
 need('ERROR: test_each_owner_initial_phase_uses_one_fresh_pair' in log and "(owner='coverage_invariant_contracts')" in log and 'FileNotFoundError: [Errno 2]' in log and 'coverage-followup-migration.json' in log and 'followup._predecessor_pin_pair(root, _operation=_operation)' in log,'Exact missed private fake dispatch error')
 need('FAIL: test_fixed_shape_order_signatures_and_single_freshness' in log and "AssertionError: Tuples differ: ('root', 'prior_digest', '_operation') != ('root', 'prior_digest')" in log,'Exact private signature assertion')
 stages.append(stage);log_names.append(names)
need(positions==[20,21] and log_names[0]==log_names[1],'Selected positions/same method order')
test_raw=bind(S/test,seal[test]);tree=ast.parse(test_raw);lines=test_raw.decode().splitlines()
need(lines[167].strip()=="self.assertEqual(tuple(inspect.signature(frozen._verified_pin_pair).parameters), ('root', 'prior_digest'))" and lines[341].strip()=='owner.verify(self.root)','Original traceback line/source binding')
source_paths=[test,'tools/carla_lane_oracle/frozen_arc_producer_contracts.py','tools/carla_lane_oracle/coverage_invariant_contracts.py','tools/carla_lane_oracle/coverage_followup_contracts.py','tools/carla_lane_oracle/accepted_successor_contracts.py','tools/carla_lane_oracle/rounded_line_selector_contracts.py','tools/carla_lane_oracle/reviewed_cleanup_contracts.py','tools/carla_lane_oracle/full_audit_cleanup_contracts.py','tools/carla_lane_oracle/_full_audit_test_fixtures.py','tools/coverage_toolchain_identity.py']
for p in source_paths:bind(S/p,seal[p])
frozen_ast=ast.parse(raw(S/'tools/carla_lane_oracle/frozen_arc_producer_contracts.py'));fn=next(n for n in frozen_ast.body if isinstance(n,ast.FunctionDef) and n.name=='_verified_pin_pair')
need([n.arg for n in fn.args.args]==['root','prior_digest'] and [n.arg for n in fn.args.kwonlyargs]==['_operation'] and isinstance(fn.args.kw_defaults[0],ast.Constant) and fn.args.kw_defaults[0].value is None,'Actual private helper signature')
owner_test=next(n for c in tree.body if isinstance(c,ast.ClassDef) for n in c.body if isinstance(n,ast.FunctionDef) and n.name=='test_each_owner_initial_phase_uses_one_fresh_pair');owner_text='\n'.join(lines[owner_test.lineno-1:owner_test.end_lineno])
need("(invariant, invariant, 'predecessor_pin_pair', self.outputs['invariant'])" in owner_text and "patch.object(provider, method, return_value=output)" in owner_text and "patch.object(Path, 'read_text', side_effect=StopAfterPins)" in owner_text,'Original public fake interception')
originals=[]
def add(p,name,kind,readable=False):originals.append(dict(path=name,data=raw(p),original_source=str(p),kind=kind,readable=readable))
for name in sorted(PINNED):add(E/name,'actual/selected-terminal-stages/'+name,'original-terminal-stage-start-result-or-complete-merged-log',True)
for name in ('SOURCE-SEAL.json','SDK-BEFORE.json','WINDOW-START.json'):add(E/name,'actual/constant-continuation-bindings/'+name,'constant-original-source-sdk-or-window-binding',name!='SOURCE-SEAL.json')
for name in (PHASE+'.json','run_diagnostic_continuation_v28.py','FINAL-PYTHON-EXPECTED-INVENTORY-V28.json','CANDIDATE-V28-SOURCE-SEAL.json','PUBLISHED-V28-QUALIFICATION-BINDING.json'):
 add(R/name,'reproduce/'+name,'constant-diagnostic-protocol-inventory-or-published-source-binding',name in (PHASE+'.json','run_diagnostic_continuation_v28.py','PUBLISHED-V28-QUALIFICATION-BINDING.json'))
bind(R/'PUBLISHED-V28-QUALIFICATION-BINDING.json','0df492bd6c870ecb2e8a6d3cb66167c2d5042aa7ba0a70d4b42f02f71eef8bdf')
add(original_path,'reproduce/original-failed-matrix-RESULT.json','unchanged-original-qualification-failure-deadline-input')
for p in source_paths:add(S/p,'reproduce/source/'+p,'exact-seal-bound-test-observer-guard-or-source',p==test)
summary=dict(schema=1,status='TWO_TERMINAL_PAIRED_PIN_DIAGNOSTIC_FAILURES_NOT_QUALIFICATION',scope='Two selected completed diagnostic stages on immutable v28: normal and optimized paired-pin each ran33methods with31passing,1failure and1error, zero skips. Both retained1800-second stage caps and returned1 without timeout. This pair is not a passing module, complete continuation result or full qualification.',source_seal_sha256=SEAL,base_published_commit='031f9f726edb6e9409853fd777af966c8ebba88d',source_tree='d2c9f94523b9c03aa94b04eaad774f73f147cd74',config_sha256=CONFIG,supervisor_sha256=SUP,sdk_before_sha256=SDK,selected_stage_results=stages,per_mode=dict(methods_run=33,passed=31,errors=1,failures=1,skips=0),selected_pair_total=dict(methods_run=66,passed=62,errors=2,failures=2),failure_method='PairedPinFakeControls.test_fixed_shape_order_signatures_and_single_freshness',failure_detail="The unchanged test expects private frozen._verified_pin_pair parameter names ('root','prior_digest'); actual sealed helper adds keyword-only _operation=None. The original tuple assertion failure is preserved.",error_method='PairedPinFakeControls.test_each_owner_initial_phase_uses_one_fresh_pair',error_subtest="owner='coverage_invariant_contracts'",error_detail='FileNotFoundError for coverage-followup-migration.json in the temporary fake root. The traceback reaches invariant._predecessor_pin_pair then followup._predecessor_pin_pair; the sealed fake test patches only invariant.predecessor_pin_pair for that owner and intercepts Path.read_text, while the actual reached record read is Path.read_bytes.',interpretation_boundary='These fixture/signature observations are static-source and raw-trace findings, not repaired outcomes or evidence of full behavior equivalence. Both original module runs remain failed.',selected_config_positions_one_based=positions,configured_continuation_stage_count=137,other_135_stage_outcomes='Outside this packet; no pass/fail/unrun or completion status assigned.',completed_prefix_disclosure='Only terminal configuration positions20/21 are packaged. This is not the complete completed-prefix inventory. Collection-level RESULT, LATEST, PROCESSES, SDK-AFTER, ongoing console and handoff files are neither read nor copied.',source_sdk_check_boundary='The terminal receipts include post-run count annotations. In the exact included supervisor these are written only after source and SDK post-stage checks return. This is a disclosed control-flow inference, not an invented overall after-receipt.',cleanup_boundary='Each selected leader was reaped and reports no remaining owned descendants. No live collection process status is asserted.',original_window=dict(configured_seconds=10800,clamped_seconds_recorded_at_start=window['whole_window_seconds'],absolute_deadline_utc=config['absolute_deadline_utc'],original_failed_matrix_result_sha256=config['original_matrix_result_sha256']),original_failure_boundary='Original v28 full-matrix failure stays failed. Diagnostic accept_nonzero collects these failures without crediting a pass. Later repairs/focused outcomes are excluded.',qualification_limit='No passing paired-pin module, complete continuation, full matrix, native/coverage, hosted CI or issue completion.',reproduction_boundary='Six terminal stage files; constant source/SDK/window bindings; exact diagnostic config, supervisor, expected inventory and publication binding; original failed-matrix deadline input; ten relevant sealed test/helper sources. Entire unchanged repository and installed SDK are not distributed.',evidence_policy='Original bytes and separately labeled summaries/index only. No mutable ongoing files, private notes, test/native execution, candidate edits, uploads or invented receipts.')
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
guide='''# V28 paired-pin terminal diagnostic failure pair

FAILED in both modes. Each selected run executed 33 methods: 31 passed,
one failed and one errored, zero skips. Normal elapsed 267.954062371 seconds;
optimized 282.708564959. Both returned1 without timeout under the unchanged
1,800-second module caps. The full raw logs and START/RESULT receipts are readable.

The private-helper signature assertion expects root/prior_digest, but the exact
sealed helper also declares keyword-only _operation=None. The invariant-owner
fake test patches the public pair helper; actual dispatch reaches the private
pair and attempts to read coverage-followup-migration.json from the fake root,
raising FileNotFoundError. The original signatures, fixture code and complete
tracebacks are retained. These source/trace observations neither repair nor
waive the failures, nor establish full behavioral equivalence.

Only terminal configuration positions20/21 of the137-stage diagnostic continuation
are included. Other135 stage outcomes are outside this packet, without being
labeled passed, failed or unrun. This is not an inventory of the full completed
prefix or an overall continuation result. No mutable RESULT, LATEST, PROCESSES,
SDK-AFTER, ongoing console or handoff file is read/copied. Constant initial
source/SDK/window records remain intact. The absolute deadline stays
2026-10-11T08:35:38.016452Z, with the original initial clamp9,158.74437seconds.

Post-run test-count annotations occur only after the exact supervisor's source
and SDK post-stage checks return. This control-flow inference is explicit;
there is no invented final after-receipt. Each selected leader was reaped with
no remaining owned descendants reported. No live collection process state is
claimed. The original full-matrix failure and all later repairs stay separate.
Diagnostic accept_nonzero is collection policy, never qualification success.

The inner manifest identifies each original path, size, hash and storage.
Readable files retain exact bytes; archived originals are per-member base64 JSON,
deterministic gzip mtime=0, then base64. Raw merged logs remain complete. The
outer seals all payloads except itself; summary and command index are derived.
The full unchanged repository and SDK executable image are not distributed.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The copied reviewed decoder verifies safe paths/hashes/sizes, rejects symlinks
and existing output, and never executes decoded contents. Packaging performs
no project imports, tests/native runs, candidate changes or uploads. Private
notes, mutable collection state and later repair evidence are excluded.
''' 
payloads.extend([(archive,encoded,'lossless-original-source-and-constant-bindings'),('INNER-MEMBER-MANIFEST.json',JSON(inner),'complete-original-member-inventory'),('VALIDATION-SUMMARY.json',JSON(summary),'derived-selected-error-pair-scope-summary'),('COMMAND-RECEIPT-SEAL.json',JSON(commands),'derived-selected-command-binding-index'),('decode_verify.py',decoder,'reviewed-safe-decoder-no-execution'),('reproduce/build_paired_pin_failure_pair_v28_packet.py',raw(Path(__file__)),'source-only-packet-builder'),('README.md',guide.encode(),'scope-and-safe-transport-guide')])
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
