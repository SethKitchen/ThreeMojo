"""Package two terminal seed-count diagnostic stages, never live phase state.

No project imports, tests/native runs, candidate edits or uploads. Only named
terminal stage files and constant source/protocol bindings are read; no overall
continuation RESULT, LATEST, PROCESSES, SDK-AFTER or console is read or copied.
"""
from pathlib import Path
from datetime import datetime, timedelta
import ast, base64, gzip, hashlib, json, re
from collections import Counter
R=Path(__file__).resolve().parent;PHASE='full-python-diagnostic-continuation-v28';E=R/'evidence'/PHASE;S=R/'candidate-v28';O=R/'validation-evidence-seed-count-v28-failure-pair-packet'
SEAL='fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596';SDK='7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207';SUP='0c6cf71e8be2fe48be76414cd800449e382569de824424a9e51110e90bc50ffc';CONFIG='a7282c67969f81b7e323cb685ed635db516aaf79621ea107d3d86ff2ecf1a0b3'
PINNED={'28-normal-test_seed_count_contracts-START.json': '435c218baefaa9ecac61cbeee538ed8aaf5a18acb8053c429f85250b0f0913af', '28-normal-test_seed_count_contracts-RESULT.json': '1084458e4bd1535ab0584e8ba5d5d88b877ef0bb467a0d367182623681bc719f', '28-normal-test_seed_count_contracts.log': 'a4df1bb14bb27fc705e5933b317c11a043422f1caf9ab51dcef54a53f8c07998', '28-optimized-test_seed_count_contracts-START.json': '2150964290879752466c2d60d8fd334362299b9658429e6d5a713c69bd50a99a', '28-optimized-test_seed_count_contracts-RESULT.json': '5ec639ab401fa24bb8f11adacbfc6b58c72e88e00c2a485fe0a92474d7339e74', '28-optimized-test_seed_count_contracts.log': 'c364dc114e02da8f74c6391dfde23fc7ef0b2ad6bb11ebf7905ed8f3e7d5348e'}
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
test='tools/carla_lane_oracle/test_seed_count_contracts.py';module=next(m for m in inv['modules'] if m['path']==test);need(module['test_count']==68 and module['sha256']==seal[test],'Selected source/discovery count')
stages=[];log_names=[];positions=[];outcomes=[]
for mode in ('normal','optimized'):
 label='28-'+mode+'-test_seed_count_contracts';index=next(i for i,x in enumerate(config['stages']) if x['label']==label);positions.append(index+1);planned=config['stages'][index]
 stage=json.loads(bind(E/(label+'-RESULT.json'),PINNED[label+'-RESULT.json']));start=json.loads(bind(E/(label+'-START.json'),PINNED[label+'-START.json']));log=bind(E/(label+'.log'),PINNED[label+'.log']).decode()
 need(all(stage.get(k)==v for k,v in start.items()),'START/result agreement')
 cmd=[str(R.parent/'restored-toolchain/official-venv/bin/python')]+(['-O'] if mode=='optimized' else [])+['-B','-m','unittest','discover','-s','tools/carla_lane_oracle','-p','test_seed_count_contracts.py','-v']
 need(stage['label']==label and stage['argv']==cmd and planned['command']==['{python}']+cmd[1:] and stage['cwd']==str(S),'Actual command')
 need(planned['accept_nonzero'] is True and stage['returncode']==1 and not stage['timed_out'] and stage['stage_timeout_seconds']==planned['seconds']==1800,'Diagnostic nonzero/cap')
 need(stage['source_seal_sha256']==SEAL and stage['leader_reaped'] is True and stage['remaining_owned_descendants']==[] and stage['test_count']==stage['expected_tests']==planned['expected_tests']==68 and stage['skipped_test_count']==0,'Terminal count/cleanup')
 need(re.findall(r'^Ran (\d+) tests? in ',log,re.M)==['68'] and log.rstrip().endswith('FAILED (failures=328, errors=4)') and ' ... skipped ' not in log,'Exact raw reported totals')
 names=re.findall(r'^(test_\w+) \(test_seed_count_contracts\.([A-Za-z_]+)\.',log,re.M);need(len(names)==68 and len(set(names))==68,'Sixty-eight top-level named methods')
 expected_ids=module['modes']['1' if mode=='optimized' else '0']['test_ids'];need({'test_seed_count_contracts.'+cls+'.'+name for name,cls in names}==set(expected_ids),'Actual methods match fresh inventory')
 failure_counts=Counter();error_counts=Counter();subtest_failures=0;plain_failures=0;error_endings={};blocks=re.split(r'^={10,}\n',log,flags=re.M)[1:]
 for block in blocks:
  match=re.match(r'(FAIL|ERROR): (\w+) \(test_seed_count_contracts\.([^\)]+)\)([^\n]*)',block);need(match is not None,'Diagnostic block header')
  kind,method,suffix=match[1],match[3],match[4]
  if kind=='FAIL':
   failure_counts[method]+=1;subtest_failures+=int(bool(suffix.strip()));plain_failures+=int(not suffix.strip())
   need('does not match "full-audit cleanup successor: unchanged premise, record or fixture changed: extensions/carla/map.mojo"' in block and 'full_audit_cleanup_contracts.ContractError:' in block and 'not raised' not in block,'Earlier Map rejection, not missed rejection')
  else:
   error_counts[method]+=1
   ending=next((x for x in reversed(block.splitlines()) if re.match(r'^(ValueError|full_audit_cleanup_contracts\.ContractError):',x)),None)
   need(ending is not None and 'unchanged premise, record or fixture changed: extensions/carla/map.mojo' in ending,'Exact error preserves Map rejection');error_endings[method]=ending
 expected_failures={'FrontierReservationSuccessorTests.test_frontier_edge_rechecks_every_bound_dependency_record_and_test':82,'OptionalSeedGuardSuccessorTests.test_new_edge_rechecks_all_prior_dependencies_records_and_test_bytes':82,'SeedCountSuccessorTests.test_after_count_suite_is_required_and_mutations_reject':1,'SeedCountSuccessorTests.test_each_historical_record_and_live_dependency_is_exact':81,'SupportSeedGuardSuccessorTests.test_new_edge_checks_all_pinned_dependencies_records_and_native_tests':82}
 expected_errors={'FrontierReservationSuccessorTests.test_separate_frontier_edge_retains_all_four_predecessors':1,'OptionalSeedGuardSuccessorTests.test_separate_exact_edge_preserves_old_record_and_all_test_pins':1,'OptionalSeedGuardSuccessorTests.test_unchanged_consumer_routes_and_ordered_observables':1,'SupportSeedGuardSuccessorTests.test_distinct_edge_reconstructs_every_published_endpoint':1}
 need(dict(failure_counts)==expected_failures and dict(error_counts)==expected_errors and subtest_failures==327 and plain_failures==1 and len(blocks)==332,'Independent per-mode failure/subtest/error counts')
 affected=set(failure_counts)|set(error_counts);need(len(affected)==9 and not(set(failure_counts)&set(error_counts)),'Nine distinct affected methods')
 outcomes.append(dict(mode=mode,methods_run=68,passing_methods=59,methods_with_failure_records=5,methods_with_errors=4,failure_records=328,subtest_failure_records=327,ordinary_method_failure_records=1,error_records=4,failures_by_method=dict(failure_counts),errors_by_method=dict(error_counts),error_final_messages=error_endings,earlier_map_regex_mismatch_records=328,missing_rejection_records=0,log_bytes=len(raw(E/(label+'.log'))),log_sha256=stage['log_sha256']))
 stages.append(stage);log_names.append(names)
need(positions==[40,41] and log_names[0]==log_names[1],'Selected positions/same method order')
test_raw=bind(S/test,seal[test]);tree=ast.parse(test_raw);lines=test_raw.decode().splitlines()
methods={c.name+'.'+n.name:n for c in tree.body if isinstance(c,ast.ClassDef) for n in c.body if isinstance(n,ast.FunctionDef)}
need((set(expected_failures)|set(expected_errors))<=set(methods),'All diagnosed method bodies are in sealed source')
need('values = {MAP: self.after.encode(), **(changes or {})}' in test_raw.decode() and "patch.object(Path, 'read_bytes'" in test_raw.decode(),'Bound source contains old-Map read overlays')
source_paths=[test,'tools/carla_lane_oracle/seed_count_contracts.py','tools/carla_lane_oracle/source_contracts.py','tools/carla_lane_oracle/sum2_guard_contracts.py','tools/carla_lane_oracle/full_audit_cleanup_contracts.py','tools/carla_lane_oracle/cache_key_contracts.py','tools/carla_lane_oracle/_full_audit_test_fixtures.py','tools/cache_key.py','tools/affected.py','tools/coverage_toolchain_identity.py','extensions/carla/map.mojo','tools/carla_lane_oracle/seed-count-successor.json','tools/carla_lane_oracle/full-audit-cleanup-successor.json']
for p in source_paths:bind(S/p,seal[p])
seed_text=raw(S/'tools/carla_lane_oracle/seed_count_contracts.py').decode()
need('cleanup_edges = (full_audit.verified_edges(root,' in seed_text and "'historical record, live dependency or regression fixture changed: '+path" in seed_text,'Preserved nested gate and subsequent dependency check source')
originals=[]
def add(p,name,kind,readable=False):originals.append(dict(path=name,data=raw(p),original_source=str(p),kind=kind,readable=readable))
for name in sorted(PINNED):add(E/name,'actual/selected-terminal-stages/'+name,'original-terminal-stage-start-result-or-complete-merged-log',not name.endswith('.log'))
for name in ('SOURCE-SEAL.json','SDK-BEFORE.json','WINDOW-START.json'):add(E/name,'actual/constant-continuation-bindings/'+name,'constant-original-source-sdk-or-window-binding',name!='SOURCE-SEAL.json')
for name in (PHASE+'.json','run_diagnostic_continuation_v28.py','FINAL-PYTHON-EXPECTED-INVENTORY-V28.json','CANDIDATE-V28-SOURCE-SEAL.json','PUBLISHED-V28-QUALIFICATION-BINDING.json'):
 add(R/name,'reproduce/'+name,'constant-diagnostic-protocol-inventory-or-published-source-binding',name in (PHASE+'.json','run_diagnostic_continuation_v28.py','PUBLISHED-V28-QUALIFICATION-BINDING.json'))
bind(R/'PUBLISHED-V28-QUALIFICATION-BINDING.json','0df492bd6c870ecb2e8a6d3cb66167c2d5042aa7ba0a70d4b42f02f71eef8bdf')
add(original_path,'reproduce/original-failed-matrix-RESULT.json','unchanged-original-qualification-failure-deadline-input')
for p in source_paths:add(S/p,'reproduce/source/'+p,'exact-seal-bound-test-observer-guard-or-source',p==test)
summary=dict(schema=1,status='TWO_TERMINAL_SEED_COUNT_DIAGNOSTIC_FAILURES_NOT_QUALIFICATION',scope='Each selected normal/optimized seed-count run executed68methods:59methods passed,5methods produced328failure records and4other methods errored, zero skips. Of328failures,327are subtest failures and1is an ordinary method failure. Both stages returned1 without timeout under1800-second caps. No module or collection pass.',source_seal_sha256=SEAL,base_published_commit='031f9f726edb6e9409853fd777af966c8ebba88d',source_tree='d2c9f94523b9c03aa94b04eaad774f73f147cd74',config_sha256=CONFIG,supervisor_sha256=SUP,sdk_before_sha256=SDK,selected_stage_results=stages,per_mode_actual_diagnostics=outcomes,selected_pair_total=dict(methods_run=136,passing_methods=118,method_executions_with_failure_records=10,method_executions_with_errors=8,failure_records=656,subtest_failure_records=654,ordinary_method_failure_records=2,error_records=8),count_boundary='Unittest Ran68 counts methods, while failures328 counts failure records including subtests. Do not subtract328 from68 or label328 separate failed methods/subtests. Both modes were parsed independently from their own raw logs.',failure_interpretation='All328 failure records in each mode show a raised full-audit ContractError for changed extensions/carla/map.mojo that does not match the expected target path. This is an earlier/wrong-target rejection, not a mutation accepted without an exception. It does not establish that the intended dependency control was reached or validated. The four errors also preserve the Map rejection, three directly and one wrapped by canonical_accumulation source validation.',source_context='Sealed test fixtures overlay historical Map endpoint bytes through Path.read_bytes. Sealed seed._verify_bound_inputs can enter full_audit.verified_edges before its per-record/dependency checks. These source and traceback facts explain the observed earlier boundary without rerunning fixtures or repairing tests.',selected_config_positions_one_based=positions,configured_continuation_stage_count=137,other_135_stage_outcomes='Outside this packet; no pass/fail/unrun or completion status assigned.',completed_prefix_disclosure='Only terminal configuration positions40/41 are packaged. This is not the full completed-prefix inventory. Collection-level RESULT, LATEST, PROCESSES, SDK-AFTER, ongoing console and handoff files are neither read nor copied.',source_sdk_check_boundary='Terminal post-run count annotations are written only after the exact supervisor returns through source/SDK post-stage checks. This is a disclosed control-flow inference, not an invented final after-receipt.',cleanup_boundary='Selected leaders were reaped and their receipts report no remaining owned descendants. No live overall process state is asserted.',original_window=dict(configured_seconds=10800,clamped_seconds_recorded_at_start=window['whole_window_seconds'],absolute_deadline_utc=config['absolute_deadline_utc'],original_failed_matrix_result_sha256=config['original_matrix_result_sha256']),original_failure_boundary='Original full-matrix failure stays failed. Diagnostic accept_nonzero collects these failures without converting them to passes. Later repair/focused results are excluded.',qualification_limit='No passing seed-count module, completed continuation, full matrix, native/coverage, hosted CI or issue completion.',reproduction_boundary='Six complete terminal stage files, including two498953-byte merged logs, constant source/SDK/window bindings, exact diagnostic protocol/inventory/publication binding, original failure deadline input and thirteen relevant sealed source/record files. Entire unchanged repository and installed SDK are not distributed.',evidence_policy='Actual original bytes and separately labeled summaries/index only. No live ongoing files, private notes, tests/native execution, candidate edits, uploads or invented receipts.')
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
guide='''# V28 seed-count terminal diagnostic failure pair

FAILED in both selected modes. Independently parsed normal and optimized logs
each report68methods:59passing methods, five methods with328failure records,
and four distinct errored methods, zero skips. There are327subtest failures
plus one ordinary method failure, not328subtests or328failed methods. Normal
elapsed694.025092691seconds; optimized684.602375748. Both returned1 without
timeout under unchanged1,800-second stage caps.

Every failure record shows an actual earlier Map rejection that mismatches the
expected target-path regex. No failure record says the exception was not raised.
This does not prove the intended dependency-specific rejection was reached;
the tests still fail. Four other methods error on the same Map rejection,
three directly and one through canonical-accumulation validation. The exact
per-method breakdown and error endings are derived from each log separately.
The sealed source contains historical Map read_bytes overlays and the nested
full-audit edge check preceding individual dependency validation. No fixture
was rerun and no failing assertion was weakened or converted to success.

Both complete498,953-byte raw merged logs, all warnings, all328failure blocks
and all4error tracebacks per mode are preserved in the reversible container.
START/RESULT receipts remain readable. No log is truncated or replaced with
the summary. Method counts and subtest counts remain separate throughout.

Only terminal configuration positions40/41 of the137-stage diagnostic collection
are selected. No outcomes are assigned to the other135stages or the collection.
No mutable RESULT/LATEST/PROCESSES/SDK-AFTER/console/handoff file is read/copied.
Constant initial source/SDK/window bindings remain exact. The absolute deadline
is2026-10-11T08:35:38.016452Z; its original initial clamp is9,158.74437seconds.

Terminal test-count annotations occur after the exact supervisor's source/SDK
post-stage checks return. This control-flow inference is explicit and is not
a fabricated final receipt. Both selected leaders were reaped without remaining
owned descendants in their receipts; no live overall process status is claimed.
Old qualification failures and later repair evidence remain separate.

The inner manifest records original path/size/hash/storage. Archived originals
are per-member base64 JSON, deterministic gzip mtime=0, then base64. Readable
originals are byte-exact. Outer manifest seals all payloads except itself;
summary and command index are derived. Full unchanged repository/SDK images
are not distributed.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The copied reviewed decoder checks safe paths/hashes/sizes, rejects symlinks and
existing output, and never executes decoded content. Packaging performs no
project imports, tests/native runs, candidate edits or uploads. Private notes,
mutable collection files and later repair evidence are excluded.
''' 
payloads.extend([(archive,encoded,'lossless-original-source-and-constant-bindings'),('INNER-MEMBER-MANIFEST.json',JSON(inner),'complete-original-member-inventory'),('VALIDATION-SUMMARY.json',JSON(summary),'derived-selected-error-pair-scope-summary'),('COMMAND-RECEIPT-SEAL.json',JSON(commands),'derived-selected-command-binding-index'),('decode_verify.py',decoder,'reviewed-safe-decoder-no-execution'),('reproduce/build_seed_count_failure_pair_v28_packet.py',raw(Path(__file__)),'source-only-packet-builder'),('README.md',guide.encode(),'scope-and-safe-transport-guide')])
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
