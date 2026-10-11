"""Package two terminal runtime-correspondence diagnostic stages, never live phase state.

No project imports, tests/native runs, candidate edits or uploads. Only named
terminal stage files and constant source/protocol bindings are read; no overall
continuation RESULT, LATEST, PROCESSES, SDK-AFTER or console is read or copied.
"""
from pathlib import Path
from datetime import datetime, timedelta
import ast, base64, gzip, hashlib, json, re
R=Path(__file__).resolve().parent;PHASE='full-python-diagnostic-continuation-v28';E=R/'evidence'/PHASE;S=R/'candidate-v28';O=R/'validation-evidence-runtime-correspondence-v28-failure-pair-packet'
SEAL='fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596';SDK='7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207';SUP='0c6cf71e8be2fe48be76414cd800449e382569de824424a9e51110e90bc50ffc';CONFIG='a7282c67969f81b7e323cb685ed635db516aaf79621ea107d3d86ff2ecf1a0b3'
PINNED={'26-normal-test_runtime_correspondence-START.json': '54ab7aca5797e3cca2a17ded033828de36a2f3bf6f0c0192dca614c069fa1d61', '26-normal-test_runtime_correspondence-RESULT.json': 'e37edbb5789da041466a7952431c50dc7f71cf5a8401bb07cf3b1baaedd56690', '26-normal-test_runtime_correspondence.log': '038597f77bd76e69f0fb5c74d42d9275497c91a85dd6632479bd1aae75f80235', '26-optimized-test_runtime_correspondence-START.json': '93e7d47009b67f404676f6428aa689a7b972753c75d2f00a14dbcadc4a565de2', '26-optimized-test_runtime_correspondence-RESULT.json': 'dfd6d6663886412a5031c0c3928d8284e063f251385785366ac1641dec16bf86', '26-optimized-test_runtime_correspondence.log': '1209fbff426dc2ee7d007d0a9e9376895cc45ab9d0a05e24b606788048003936'}
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
test='tools/carla_lane_oracle/test_runtime_correspondence.py';module=next(m for m in inv['modules'] if m['path']==test);need(module['test_count']==91 and module['sha256']==seal[test],'Selected source/discovery count')
stages=[];log_names=[];positions=[]
for mode in ('normal','optimized'):
 label='26-'+mode+'-test_runtime_correspondence';index=next(i for i,x in enumerate(config['stages']) if x['label']==label);positions.append(index+1);planned=config['stages'][index]
 stage=json.loads(bind(E/(label+'-RESULT.json'),PINNED[label+'-RESULT.json']));start=json.loads(bind(E/(label+'-START.json'),PINNED[label+'-START.json']));log=bind(E/(label+'.log'),PINNED[label+'.log']).decode()
 need(all(stage.get(k)==v for k,v in start.items()),'START/result agreement')
 cmd=[str(R.parent/'restored-toolchain/official-venv/bin/python')]+(['-O'] if mode=='optimized' else [])+['-B','-m','unittest','discover','-s','tools/carla_lane_oracle','-p','test_runtime_correspondence.py','-v']
 need(stage['label']==label and stage['argv']==cmd and planned['command']==['{python}']+cmd[1:] and stage['cwd']==str(S),'Actual command')
 need(planned['accept_nonzero'] is True and stage['returncode']==1 and not stage['timed_out'] and stage['stage_timeout_seconds']==planned['seconds']==1800,'Diagnostic nonzero/cap')
 need(stage['source_seal_sha256']==SEAL and stage['leader_reaped'] is True and stage['remaining_owned_descendants']==[] and stage['test_count']==stage['expected_tests']==planned['expected_tests']==91 and stage['skipped_test_count']==0,'Terminal count/cleanup')
 need(re.findall(r'^Ran (\d+) tests? in ',log,re.M)==['91'] and log.rstrip().endswith('FAILED (failures=1, errors=1)') and ' ... skipped ' not in log and len(re.findall(r'^ERROR: ',log,re.M))==1 and len(re.findall(r'^FAIL: ',log,re.M))==1,'Exact raw failure/error outcome')
 names=re.findall(r'^(test_\w+) \(test_runtime_correspondence\.([A-Za-z_]+)\.',log,re.M);need(len(names)==91 and len(set(names))==91,'Ninety-one named methods')
 expected_ids=module['modes']['1' if mode=='optimized' else '0']['test_ids'];need({'test_runtime_correspondence.'+cls+'.'+name for name,cls in names}==set(expected_ids),'Raw method names match fresh inventory')
 need('ERROR: test_benign_comments_preserve_all_gates' in log and 'line 184, in test_benign_comments_preserve_all_gates' in log and 'sampled.verify(ROOT)' in log and 'full_audit_cleanup_contracts._OperationCoherenceError: full-audit cleanup successor: consumed operation text changed: extensions/carla/curve_rounded_line.mojo' in log and 'check_sampled_values.CheckError: unreviewed complete successor: full-audit cleanup successor: consumed operation text changed: extensions/carla/curve_rounded_line.mojo' in log,'Exact all-Mojo split-read error and wrappers')
 need('FAIL: test_cli_positive_negative_and_missing_inputs_normal_and_optimized' in log and 'line 275, in test_cli_positive_negative_and_missing_inputs_normal_and_optimized' in log and 'AssertionError: 1 != 0 : FAIL: full-audit cleanup successor: unreadable or malformed record' in log,'Exact first CLI positive failure')
 stages.append(stage);log_names.append(names)
need(positions==[36,37] and log_names[0]==log_names[1],'Selected positions/same method order')
test_raw=bind(S/test,seal[test]);tree=ast.parse(test_raw);lines=test_raw.decode().splitlines()
need(lines[183].strip()=='sampled.verify(ROOT)' and lines[274].strip()=='self.assertEqual(positive.returncode, 0, positive.stdout+positive.stderr)','Exact original traceback lines')
source_paths=[test,'tools/carla_lane_oracle/check_sampled_values.py','tools/carla_lane_oracle/check_runtime_support.py','tools/carla_lane_oracle/sum2_contracts.py','tools/carla_lane_oracle/sum2_guard_contracts.py','tools/carla_lane_oracle/reviewed_cleanup_contracts.py','tools/carla_lane_oracle/coverage_invariant_contracts.py','tools/carla_lane_oracle/coverage_followup_contracts.py','tools/carla_lane_oracle/accepted_successor_contracts.py','tools/carla_lane_oracle/rounded_line_selector_contracts.py','tools/carla_lane_oracle/full_audit_cleanup_contracts.py','tools/carla_lane_oracle/_full_audit_test_fixtures.py','tools/carla_lane_oracle/source_contracts.py','tools/carla_lane_oracle/seed_count_contracts.py','tools/coverage_toolchain_identity.py','extensions/carla/curve_rounded_line.mojo']
for p in source_paths:bind(S/p,seal[p])
methods={n.name:n for c in tree.body if isinstance(c,ast.ClassDef) for n in c.body if isinstance(n,ast.FunctionDef)}
comment=methods['test_benign_comments_preserve_all_gates'];comment_text='\n'.join(lines[comment.lineno-1:comment.end_lineno])
need("path.suffix == '.mojo'" in comment_text and "patch.object(Path, 'read_text', annotated)" in comment_text and "'read_bytes'" not in comment_text,'All-Mojo split-read hook')
cli=methods['test_cli_positive_negative_and_missing_inputs_normal_and_optimized'];cli_text='\n'.join(lines[cli.lineno-1:cli.end_lineno])
need("for mode in ([], ['-O']):" in cli_text and "for script in ('check_sampled_values.py', 'check_runtime_support.py'):" in cli_text and 'cleanup_fixtures.write_predecessors(root, cleanup_fixtures.verified_predecessors(ROOT))' in cli_text and 'cleanup_fixtures.copy_current_root' not in cli_text,'Actual partial historical fixture and first child order')
originals=[]
def add(p,name,kind,readable=False):originals.append(dict(path=name,data=raw(p),original_source=str(p),kind=kind,readable=readable))
for name in sorted(PINNED):add(E/name,'actual/selected-terminal-stages/'+name,'original-terminal-stage-start-result-or-complete-merged-log',True)
for name in ('SOURCE-SEAL.json','SDK-BEFORE.json','WINDOW-START.json'):add(E/name,'actual/constant-continuation-bindings/'+name,'constant-original-source-sdk-or-window-binding',name!='SOURCE-SEAL.json')
for name in (PHASE+'.json','run_diagnostic_continuation_v28.py','FINAL-PYTHON-EXPECTED-INVENTORY-V28.json','CANDIDATE-V28-SOURCE-SEAL.json','PUBLISHED-V28-QUALIFICATION-BINDING.json'):
 add(R/name,'reproduce/'+name,'constant-diagnostic-protocol-inventory-or-published-source-binding',name in (PHASE+'.json','run_diagnostic_continuation_v28.py','PUBLISHED-V28-QUALIFICATION-BINDING.json'))
bind(R/'PUBLISHED-V28-QUALIFICATION-BINDING.json','0df492bd6c870ecb2e8a6d3cb66167c2d5042aa7ba0a70d4b42f02f71eef8bdf')
add(original_path,'reproduce/original-failed-matrix-RESULT.json','unchanged-original-qualification-failure-deadline-input')
for p in source_paths:add(S/p,'reproduce/source/'+p,'exact-seal-bound-test-observer-guard-or-source',p==test)
summary=dict(schema=1,status='TWO_TERMINAL_RUNTIME_CORRESPONDENCE_DIAGNOSTIC_FAILURES_NOT_QUALIFICATION',scope='Two selected completed diagnostic stages on immutable v28: normal and optimized runtime-correspondence each ran91methods with89passing,1failure and1error, zero skips. Both retained1800-second stage caps and returned1 without timeout. This pair is not a passing module, complete continuation result or full qualification.',source_seal_sha256=SEAL,base_published_commit='031f9f726edb6e9409853fd777af966c8ebba88d',source_tree='d2c9f94523b9c03aa94b04eaad774f73f147cd74',config_sha256=CONFIG,supervisor_sha256=SUP,sdk_before_sha256=SDK,selected_stage_results=stages,per_mode=dict(methods_run=91,passed=89,errors=1,failures=1,skips=0),selected_pair_total=dict(methods_run=182,passed=178,errors=2,failures=2),error_method='FixedRuntimeCandidateTests.test_benign_comments_preserve_all_gates',error_detail='The original test appends an inert comment to every Mojo Path.read_text result while leaving read_bytes unpatched. The sampled.verify(ROOT) call errors through ContractError, _OperationCoherenceError, accepted ValueError and final check_sampled_values.CheckError after capture matches consumed curve_rounded_line text against raw bytes. The later runtime.verify(ROOT) line is not reached in this method.',failure_method='FixedRuntimeCandidateTests.test_cli_positive_negative_and_missing_inputs_normal_and_optimized',failure_detail='First positive CLI child returns1 with FAIL: full-audit cleanup successor: unreadable or malformed record. The source constructs a partial historical fixture and writes predecessors, rather than copying a complete root. The recorded child output does not include a child traceback or identify an exact missing record path; this packet does not invent either.',unreached_within_failed_cli_method='The failure is at the first positive assertion: inner normal child / check_sampled_values.py. Later negative and missing-pin children, check_runtime_support.py and inner optimized children are not reached by that method in either outer module run.',interpretation_boundary='Raw tracebacks and fixture-source observations are preserved without repairing assertions or claiming complete behavioral equivalence. Both original modules remain failed.',selected_config_positions_one_based=positions,configured_continuation_stage_count=137,other_135_stage_outcomes='Outside this packet; no pass/fail/unrun or completion status assigned.',completed_prefix_disclosure='Only terminal configuration positions36/37 are packaged. This is not the complete completed-prefix inventory. Collection-level RESULT, LATEST, PROCESSES, SDK-AFTER, ongoing console and handoff files are neither read nor copied.',source_sdk_check_boundary='Terminal post-run count annotations are written by the exact included supervisor only after source and SDK post-stage checks return. This is a disclosed control-flow inference, not an invented overall after-receipt.',cleanup_boundary='Each selected leader was reaped and its receipt reports no remaining owned descendants. No live collection process status is asserted.',original_window=dict(configured_seconds=10800,clamped_seconds_recorded_at_start=window['whole_window_seconds'],absolute_deadline_utc=config['absolute_deadline_utc'],original_failed_matrix_result_sha256=config['original_matrix_result_sha256']),original_failure_boundary='Original full-matrix failure remains failed and separate. Diagnostic accept_nonzero collects errors without crediting a pass; later repairs and focused outcomes are excluded.',qualification_limit='No passing runtime-correspondence module, complete continuation, full matrix, native/coverage, hosted CI or issue completion.',reproduction_boundary='Six terminal stage files, constant source/SDK/window bindings, exact diagnostic config/supervisor/inventory/publication binding, original failure deadline input and sixteen relevant sealed test/helper/consumed-source files. Full unchanged repository and installed SDK image are not distributed.',evidence_policy='Original bytes and labeled summary/index only. No mutable ongoing files, private notes, test/native execution, candidate edits, uploads or invented receipts.')
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
guide='''# V28 runtime-correspondence terminal diagnostic failure pair

FAILED in both selected modes. Each ran91methods:89passed, one failed and one
errored, zero skips. Normal elapsed198.207305336seconds; optimized192.414934059.
Both returned1 without timeout under unchanged1,800-second stage caps. Original
START/RESULT receipts and complete raw logs are readable.

The benign-comment method patches all Mojo read_text observations while leaving
read_bytes unchanged. Its first sampled.verify(ROOT) call ends in CheckError
through the complete preserved cause chain after owned capture rejects changed
curve_rounded_line text. Its later runtime.verify(ROOT) line is not reached.

The CLI method constructs a partial historical fixture, writes predecessors,
and fails its first positive child assertion: return1, unreadable or malformed
record. Its later negative/missing-pin children and other script/mode combinations
are not reached. The raw child output has no child traceback or exact missing
record name; none is reconstructed. The fixture source is included separately
from these actual observed diagnostics. Neither failure is waived or repaired.

Only selected terminal configuration positions36/37 of the137-stage diagnostic
continuation are packaged. No outcomes are assigned to the other135stages and
no complete-prefix or aggregate continuation status is claimed. No mutable
RESULT/LATEST/PROCESSES/SDK-AFTER/console/handoff file is read or copied. Initial
source/SDK/window bindings are constant. Absolute deadline remains
2026-10-11T08:35:38.016452Z; the original initial clamp was9,158.74437seconds.

Terminal count annotations occur only after the exact supervisor returns through
its source/SDK post-stage checks. That control-flow inference is explicit; no
final after-receipt is invented. Selected leaders were reaped with no owned
descendants remaining in their receipts. No live collection process state is
claimed. Original failed qualification and later repairs remain separate.

The inner manifest records each original path, size, hash and storage. Readable
originals retain exact bytes. Others use per-member base64 JSON, deterministic
gzip mtime=0, then base64. Logs remain complete merged output; absent streams or
tracebacks are not reconstructed. Outer manifest seals every payload except
itself; summary and command index are derived. Full unchanged repository/SDK
images are not distributed.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The reviewed decoder verifies paths/hashes/sizes, rejects symlinks and existing
output, and never executes decoded contents. Packaging performs no project
imports, tests/native runs, candidate edits or uploads. Private notes, mutable
continuation files and later repair evidence are excluded.
''' 
payloads.extend([(archive,encoded,'lossless-original-source-and-constant-bindings'),('INNER-MEMBER-MANIFEST.json',JSON(inner),'complete-original-member-inventory'),('VALIDATION-SUMMARY.json',JSON(summary),'derived-selected-error-pair-scope-summary'),('COMMAND-RECEIPT-SEAL.json',JSON(commands),'derived-selected-command-binding-index'),('decode_verify.py',decoder,'reviewed-safe-decoder-no-execution'),('reproduce/build_runtime_correspondence_failure_pair_v28_packet.py',raw(Path(__file__)),'source-only-packet-builder'),('README.md',guide.encode(),'scope-and-safe-transport-guide')])
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
