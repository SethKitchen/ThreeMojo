"""Preserve the original failed v28 full matrix and its fresh discovery provenance.

Byte/JSON/AST inspection, hashing and reversible serialization only. No project
imports, tests/native runs, source edits, Git writes, upload or later-run merge.
"""
from pathlib import Path
import ast, base64, gzip, hashlib, json, re
R=Path(__file__).resolve().parent; S=R/'candidate-v28'; PHASE='full-python-matrix-final-v28'; DISC='python-discovery-final-v28'; E=R/'evidence'/PHASE; DE=R/'evidence'/DISC
O=R/'validation-evidence-full-matrix-v28-failure-packet'
SEAL='fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596'
RESULT='a2d054ac36ac97e729d292956a2233f10b479b6f40194fec90c9f088858be844'
CONFIG='b078e691b04f3e2acfee6c1ddcd4f0ca934b500062593bb72d24592e882e7f5a'
INVENTORY='0996f6650319b26da030bcfccf85868e2eba6b755a46063bec9daabfd796a2f9'
PUBLISHED='0df492bd6c870ecb2e8a6d3cb66167c2d5042aa7ba0a70d4b42f02f71eef8bdf'
SDK='7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207'
SUPERVISOR='6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032'
SHA=lambda b:hashlib.sha256(b).hexdigest()
JSON=lambda x:(json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def need(x,m):
 if not x:raise ValueError(m)
def raw(p):
 need(p.is_file() and not p.is_symlink(),'Nonregular input '+str(p));return p.read_bytes()
def parse(b):return json.loads(b)
def read(p):return parse(raw(p))
def checked(p,h):
 b=raw(p);need(SHA(b)==h,'Identity differs '+str(p));return b
need(not O.exists(),'Never overwrite an evidence packet')
result=parse(checked(E/'RESULT.json',RESULT)); config=parse(checked(R/(PHASE+'.json'),CONFIG)); inv=parse(checked(R/'FINAL-PYTHON-EXPECTED-INVENTORY-V28.json',INVENTORY)); publication=parse(checked(R/'PUBLISHED-V28-QUALIFICATION-BINDING.json',PUBLISHED))
seal=parse(checked(R/'CANDIDATE-V28-SOURCE-SEAL.json',SEAL))
need(checked(E/'SOURCE-SEAL.json',SEAL)==raw(R/'CANDIDATE-V28-SOURCE-SEAL.json'),'Source seal bytes')
need(publication['published_commit']=='031f9f726edb6e9409853fd777af966c8ebba88d' and publication['published_tree']=='d2c9f94523b9c03aa94b04eaad774f73f147cd74' and publication['published_parent']=='3583300bf47cc52dba7c6b97b77bccc09e0cc56a','Publication identity')
need(publication['source_seal_sha256']==SEAL and publication['matrix_config_sha256']==CONFIG and publication['inventory_sha256']==INVENTORY,'Publication bindings')
need(not result['sequence_completed'] and result['failure'] and len(result['stages'])==17 and len(config['stages'])==154,'Original failure/stage inventory')
need(result['finished']=='2026-10-11T05:52:19.473115+00:00' and result['elapsed_seconds']==1001.4566625619991,'Original finish/time')
need(result['source_seal_unchanged'] is True and result['sdk_identity_unchanged'] is True and result['remaining_owned_descendants']==[],'Final stability/cleanup')
need(config['source']==str(S) and config['source_seal_sha256']==SEAL and config['scope']==result['scope'],'Config source/scope')
window=read(E/'WINDOW-START.json');need(window['supervisor_sha256']==SHA(raw(R/'run_checkpoint_matrix.py'))==SUPERVISOR and window['source_seal_sha256']==SEAL,'Supervisor identity')
need(window['whole_window_seconds']==config['window_seconds']==10800 and window['python_optimize']==0 and window['runtime_gate_seconds']==5,'Window policy')
need(checked(E/'SDK-BEFORE.json',SDK)==raw(E/'SDK-AFTER.json'),'SDK before/after')
original_names={'RESULT.json','FAILURE.json','SOURCE-SEAL.json','SDK-BEFORE.json','SDK-AFTER.json','WINDOW-START.json','LATEST.json','PROCESSES.jsonl'}
console=[parse(b) for b in raw(R/(PHASE+'.supervisor.log')).splitlines()]
need(len(console)==18 and console[-1]==result,'Original supervisor aggregate console')
stage_summaries=[]
for i,stage in enumerate(result['stages']):
 planned=config['stages'][i];label=stage['label'];need(label==planned['label'],'Stage order')
 need(stage==read(E/(label+'-RESULT.json')),'Stage receipt equality')
 start=read(E/(label+'-START.json'));need(all(stage.get(k)==v for k,v in start.items()),'Stage START binding')
 expected_argv=[v.replace('{python}',str(R.parent/'restored-toolchain/official-venv/bin/python')) for v in planned['command']]
 need(stage['argv']==expected_argv and stage['cwd']==str(S) and stage['source_seal_sha256']==SEAL,'Actual command/source')
 need(stage['stage_timeout_seconds']==planned['seconds']==1800 and not stage['timed_out'] and stage['leader_reaped'] and stage['remaining_owned_descendants']==[],'Stage caps/cleanup')
 need(console[i]=={k:v for k,v in stage.items() if k not in ('test_count','expected_tests','skipped_test_count')},'Original console pre-annotation receipt')
 log=checked(E/(label+'.log'),stage['log_sha256']).decode();counts=re.findall(r'^Ran (\d+) tests? in ',log,re.M)
 need(counts==[str(planned['expected_tests'])] and ' ... skipped ' not in log,'Actual unittest count/skips')
 if i<16:
  need(stage['returncode']==0 and stage['test_count']==stage['expected_tests']==planned['expected_tests'] and stage['skipped_test_count']==0 and log.rstrip().endswith('OK'),'Passing-stage evidence')
 else:
  need(stage['returncode']==1 and label=='08-normal-test_frozen_arc_producer_contracts' and planned['expected_tests']==5 and log.rstrip().endswith('FAILED (failures=1)'),'Exact failed stage')
  need(not any(k in stage for k in ('test_count','expected_tests','skipped_test_count')),'No post-success annotations on failure')
 original_names.update((label+'-RESULT.json',label+'-START.json',label+'.log'))
 stage_summaries.append(dict(label=label,returncode=stage['returncode'],seconds=stage['seconds'],timed_out=stage['timed_out'],reported_tests=int(counts[0]),configured_expected_tests=planned['expected_tests'],status='PASS_COMPLETE_STAGE' if i<16 else 'FAIL_ONE_DIAGNOSTIC_ASSERTION'))
need({p.name for p in E.iterdir()}==original_names and len(original_names)==59,'Every original matrix phase file')
need(sum(s['test_count'] for s in result['stages'][:16])==110,'Passing complete-stage count')
need(sum(s['expected_tests'] for s in config['stages'])==2674 and len(config['stages'][17:])==137 and sum(s['expected_tests'] for s in config['stages'][17:])==2559,'Full/unrun expected counts')
last=result['stages'][-1];failed_log=raw(E/(last['label']+'.log'));text=failed_log.decode()
need(SHA(failed_log)=='59dfe69d7f2279fe843752fc7eba51b728312a5f5ac49c90472b8e0cb055bdf1' and len(failed_log)==5094,'Exact full failure log')
need(len(re.findall(r'^FAIL: ',text,re.M))==1 and not re.search(r'^ERROR: ',text,re.M),'One failure, no errors')
need('AssertionError: "unreviewed runtime pin" does not match "unreviewed complete successor: full-audit cleanup successor: unchanged premise, record or fixture changed: tools/carla_lane_oracle/runtime-source-pins.json"' in text,'Exact diagnostic mismatch')
need(len(re.findall(r'^test_.*? \.\.\. (?:ok)?',text,re.M))==5 and text.count(' ... ok\n')==3 and '\nok\ntest_frozen_native' in text,'Four passing methods around failing method')
need('subprocess.TimeoutExpired' not in text and 'full_audit_cleanup_contracts.ContractError:' in text and 'ValueError: unreviewed complete successor:' in text,'Rejection trace, no timeout')
need(read(E/'FAILURE.json')['error']==result['failure'],'Failure traceback binding')
processes=[parse(b) for b in raw(E/'PROCESSES.jsonl').splitlines()];need(processes and read(E/'LATEST.json')==processes[-1],'Process history terminal snapshot')
# Preserve and verify all fresh discovery provenance; discovery never runs test bodies.
disc_config=parse(checked(R/(DISC+'.json'),inv['discovery_config_sha256']));disc_result=parse(checked(DE/'RESULT.json',inv['discovery_result_sha256']));disc_window=read(DE/'WINDOW-START.json')
need(disc_result['sequence_completed'] and disc_result['failure'] is None and disc_result['source_seal_unchanged'] and disc_result['sdk_identity_unchanged'] and disc_result['remaining_owned_descendants']==[] and len(disc_result['stages'])==154,'Discovery success boundary')
need(disc_config['source_seal_sha256']==SEAL and disc_window['source_seal_sha256']==SEAL and disc_window['supervisor_sha256']==SUPERVISOR and disc_window['whole_window_seconds']==disc_config['window_seconds']==1800,'Discovery source/supervisor/cap')
for name,h in inv['discovery_evidence_sha256'].items():checked(DE/name,h)
need(inv['module_count']==77 and inv['consumer_module_count']==76 and inv['test_count_per_mode']==1337 and inv['expected_executions_both_modes']==2674 and inv['authority_test_count_per_mode']==95,'Fresh inventory counts')
need(inv['discovery_program_sha256']==SHA(raw(R/'discover_python_module_v2.py'))=='702838da94b1f8b6e868e85dba87932288d1fd5af501e515882eafdc53c96bfe','Actual discovery program')
need(inv['module_plan_sha256']==SHA(raw(R/'FINAL-PYTHON-MODULE-PLAN-V28.json'))=='6c8dd504c67255b27fad6e5b0f339915a8a73cc59bd424c95c9a03ac7634ffa7','Module plan')
for i,stage in enumerate(disc_result['stages']):
 planned=disc_config['stages'][i];label=stage['label'];need(label==planned['label'] and stage==read(DE/(label+'-RESULT.json')),'Discovery stage receipt/order')
 need(stage['returncode']==0 and not stage['timed_out'] and stage['leader_reaped'] and stage['remaining_owned_descendants']==[] and stage['source_seal_sha256']==SEAL and stage['stage_timeout_seconds']==planned['seconds']==180,'Discovery exact outcome/cap')
 need(all(stage.get(k)==v for k,v in read(DE/(label+'-START.json')).items()),'Discovery START')
 checked(DE/(label+'.log'),stage['log_sha256'])
seen={0:set(),1:set()}
for module in inv['modules']:
 need(SHA(raw(S/module['path']))==module['sha256']==seal[module['path']],'Discovered test source')
 for mode in (0,1):
  row=module['modes'][str(mode)];record=parse(checked(Path(row['discovery_record']),row['discovery_record_sha256']))
  need(all(row[k]==v for k,v in record.items()) and record['test_bodies_executed'] is False and record['optimize']==mode and record['test_count']==len(record['test_ids'])==module['test_count'] and len(set(record['test_ids']))==len(record['test_ids']),'Discovery actual IDs/count/mode')
  need(not (seen[mode]&set(record['test_ids'])),'Duplicate global discovery IDs');seen[mode].update(record['test_ids'])
  checked(Path(row['discovery_log']),row['discovery_log_sha256']);checked(Path(row['discovery_stage_receipt']),row['discovery_stage_receipt_sha256'])
  checked(DE/(Path(row['discovery_stage_receipt']).name.replace('-RESULT.json','-START.json')),row['discovery_stage_start_sha256'])
 need(module['modes']['0']['test_ids']==module['modes']['1']['test_ids'],'Normal/optimized test IDs')
need(len(seen[0])==len(seen[1])==1337,'Fresh global discovery count')
need([s['command'][-2] for s in config['stages'][-2:]]==['test_full_audit_cleanup_contracts.py']*2 and all(s['expected_tests']==95 for s in config['stages'][-2:]),'Authority-last stages')
disc_console=[parse(b) for b in raw(R/(DISC+'.supervisor.log')).splitlines()];need(disc_console==disc_result['stages']+[disc_result],'Original complete discovery console')
need(checked(DE/'SDK-BEFORE.json',SDK)==raw(DE/'SDK-AFTER.json')==raw(E/'SDK-BEFORE.json'),'Discovery/matrix SDK receipt equality')
# Originals are selected only from these two exact completed phases and named source/protocol inputs.
originals=[]
def add(p,name,kind,readable=False):originals.append(dict(path=name,data=raw(p),original_source=str(p),kind=kind,readable=readable))
for phase,directory in ((PHASE,E),(DISC,DE)):
 for p in sorted(directory.iterdir()):
  need(p.is_file() and not p.is_symlink(),'Unexpected phase directory entry')
  readable=phase==PHASE and (p.name in ('RESULT.json','FAILURE.json','WINDOW-START.json','SDK-BEFORE.json','SDK-AFTER.json') or p.name==last['label']+'.log')
  add(p,'actual/'+phase+'/'+p.name,'original-matrix-failure-evidence' if phase==PHASE else 'original-fresh-discovery-no-test-body-evidence',readable)
for name in (PHASE+'.json',PHASE+'.supervisor.log',DISC+'.json',DISC+'.supervisor.log','run_checkpoint_matrix.py','discover_python_module_v2.py','prepare_final_python_discovery_77.py','prepare_final_python_matrix.py','FINAL-PYTHON-MODULE-PLAN-V28.json','FINAL-PYTHON-EXPECTED-INVENTORY-V28.json','CANDIDATE-V28-SOURCE-SEAL.json','PUBLISHED-V28-QUALIFICATION-BINDING.json','PUBLISHABLE-V28-31-PATH-MANIFEST.json'):
 add(R/name,'reproduce/'+name,'exact-protocol-config-console-inventory-or-source-publication-binding',name in (PHASE+'.json','PUBLISHED-V28-QUALIFICATION-BINDING.json','run_checkpoint_matrix.py','discover_python_module_v2.py'))
sm=R/'test-append-implementation-v28/PUBLISHABLE-SOURCE-MANIFEST.json'; source_manifest=parse(checked(sm,'d3b1e05667a9d64a9b3f23bcb553ecda4ae65911c4cfac4576e90cd7dc2d5e31'))
add(sm,'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json','exact-frozen-source-manifest')
source_paths={r['path'] for r in source_manifest['files']}|{m['path'] for m in inv['modules']}|{'tools/coverage_toolchain_identity.py','tools/carla_lane_oracle/runtime-source-pins.json'}
for path in sorted(source_paths):
 checked(S/path,seal[path]);add(S/path,'reproduce/source/'+path,'exact-seal-bound-source',path=='tools/carla_lane_oracle/test_frozen_arc_producer_contracts.py')
# Exact caps and static diagnostic assertion are readable in their unchanged source.
frozen_source=raw(S/'tools/carla_lane_oracle/test_frozen_arc_producer_contracts.py');ast.parse(frozen_source)
need(frozen_source.decode().splitlines()[119].strip()=='with self.assertRaisesRegex(ValueError, diagnostic):','Traceback line/source binding')
summary=dict(schema=1,status='FAILED_ORIGINAL_FULL_MATRIX_V28_NOT_A_QUALIFICATION_PASS',source_commit=publication['published_commit'],source_tree=publication['published_tree'],source_seal_sha256=SEAL,result_sha256=RESULT,config_sha256=CONFIG,inventory_sha256=INVENTORY,published_binding_sha256=PUBLISHED,scope='The original final v28 matrix stopped at stage 17 of 154. Sixteen complete stages passed 110 test executions. The failed normal frozen-arc module ran five methods: four passed and one failed a diagnostic-string assertion after rejecting the runtime-pin mutation. All 137 later stages, with 2559 expected executions, were unrun in this attempt.',finished=result['finished'],total_window_seconds=result['elapsed_seconds'],sequence_completed=False,completed_passing_stages=16,passing_executions_in_complete_stages=110,failed_stage=last['label'],failed_stage_seconds=last['seconds'],failed_stage_returncode=1,failed_stage_timed_out=False,failed_module_reported_methods=5,failed_module_passing_methods=4,failed_module_failures=1,failed_module_errors=0,failed_module_skips_observed=0,failed_method='FrozenArcProducerContracts.test_manifest_and_runtime_pin_refresh_cannot_authorize_change',failed_subtest_path='tools/carla_lane_oracle/runtime-source-pins.json',failure_kind='assertRaisesRegex expected unreviewed runtime pin, but rejection raised unreviewed complete successor wrapping the full-audit unchanged-record rejection',failure_interpretation='The complete original traceback proves this runtime-pin mutation was rejected and the asserted diagnostic did not match. This does not waive the assertion, establish full behavior equivalence, or qualify any unrun test.',unrun_stage_count=137,unrun_expected_executions=2559,configured_module_count=77,configured_stage_count=154,configured_test_executions_per_mode=1337,configured_test_executions_both_modes=2674,source_sdk_unchanged=True,remaining_owned_descendants=[],sdk_receipt_sha256=SDK,original_caps=dict(per_module_seconds=1800,whole_window_seconds=10800,authority_child_seconds=120,two_named_import_verification_watchdogs_seconds=30,other_watchdogs='Preserved exact source policy; no limit changed by this packet.',native_runtime_gate_metadata_seconds=5),fresh_discovery=dict(phase=DISC,result_sha256=inv['discovery_result_sha256'],stages_completed=154,test_bodies_executed=False,test_count_per_mode=1337,meaning='Fresh discovery establishes expected IDs/counts, not test-body passes.'),stage_timings=stage_summaries,original_phase_file_counts={PHASE:len(original_names),DISC:len(list(DE.iterdir()))},frozen_source_payload_count=len(source_paths),later_diagnostic_continuation='Excluded. Any later diagnostic continuation has separate receipts and cannot change this original failed result or make its unrun stages passed.',reproduction_boundary='Preserves every original matrix/discovery phase file and raw merged log, both actual supervisor consoles, executed supervisor/discovery program, prepared configs/plans/inventory, exact publication/source seals, all31 delta source files and all77 selected test modules plus SDK support/runtime record. Requires the exact published repository and pinned SDK to reproduce; their entire unchanged images are not distributed.',qualification_limit='No full Python matrix, paired native, maintained coverage, hosted CI or issue-completion pass is established.',evidence_policy='Original bytes and separately labeled derived summary only. No private review notes, source edits, tests/native execution, uploads or rewritten failure receipts.')
commands=dict(schema=1,kind='derived-command-and-receipt-index',source_seal_sha256=SEAL,result_sha256=RESULT,config_sha256=CONFIG,inventory_sha256=INVENTORY,published_binding_sha256=PUBLISHED,actual_stage_labels=[s['label'] for s in result['stages']],unrun_stages=[dict(label=s['label'],command=s['command'],expected_tests=s['expected_tests'],seconds=s['seconds']) for s in config['stages'][17:]],actual_supervisor_console_sha256=SHA(raw(R/(PHASE+'.supervisor.log'))),fresh_discovery_result_sha256=inv['discovery_result_sha256'])
archive_name='containers/ORIGINAL-EVIDENCE.json.gz.b64';members=[];archived=[];payloads=[]
need(len(originals)==len({r['path'] for r in originals}),'Duplicate original')
for row in sorted(originals,key=lambda r:r['path']):
 b=row['data']; member={k:row[k] for k in ('path','kind','original_source')};member.update(bytes=len(b),sha256=SHA(b))
 if row['readable']:
  b.decode();payloads.append((row['path'],b,'byte-exact-readable-original'));member.update(storage='readable',transport_path=row['path'])
 else:
  archived.append(dict(path=row['path'],bytes=len(b),sha256=SHA(b),data_base64=base64.b64encode(b).decode()));member.update(storage='container',transport_path=archive_name)
 members.append(member)
container=(json.dumps(dict(schema=1,encoding='base64',members=archived),sort_keys=True,separators=(',',':'))+'\n').encode();need(len(container)<64*1024*1024,'Decoder size limit')
encoded=base64.b64encode(gzip.compress(container,compresslevel=9,mtime=0))+b'\n';need(gzip.decompress(base64.b64decode(encoded))==container,'Reversible container')
inner=dict(schema=1,original_member_count=len(members),original_member_bytes=sum(r['bytes'] for r in members),container=dict(path=archive_name,encoding='base64 of deterministic gzip mtime=0 containing JSON',members=len(archived),json_bytes=len(container),json_sha256=SHA(container)),members=members)
decoder=checked(R/'validation-evidence-qualification-policy-v23-packet/decode_verify.py','a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4')
readme='''# Original full-matrix v28 failure evidence

FAILED. The original 154-stage matrix stopped at stage 17. Sixteen complete
stages passed 110 executions. The normal frozen-arc module ran five methods:
four passed and one failed its diagnostic-string assertion. The mutation was
rejected, but the resulting ValueError did not match "unreviewed runtime pin".
The complete original traceback is readable in actual/full-python-matrix-final-v28/.
All 137 later stages (2,559 expected executions) were unrun in this attempt.
The failed stage returned 1 without timeout. The 1,800-second module and
10,800-second whole-window limits were unchanged; the actual window lasted
1,001.456662562 seconds. Source/SDK receipts stayed unchanged; no descendants
remained. This is a failed qualification attempt, not an overall pass.

The exact published source commit is 031f9f726edb6e9409853fd777af966c8ebba88d,
with tree d2c9f94523b9c03aa94b04eaad774f73f147cd74. The pre-execution publication
binding is retained as originally written. All original matrix files, logs and
actual console output are retained. All fresh discovery files and console
output are also retained: 77 modules in both modes, 1,337 IDs per mode.
Discovery did not run test bodies and contributes no passing executions.
Later diagnostic-continuation receipts are deliberately outside this packet.
They cannot retroactively complete or rewrite the original failed attempt.

The inner manifest lists each original's path, size, SHA-256 and storage.
Readable originals are byte-exact. Other originals are per-member base64 in
JSON, compressed with deterministic gzip mtime=0 and base64 encoded. Raw merged
logs are complete; stdout/stderr separation is not reconstructed. Derived
summary and command-index files are labeled separately. The outer manifest
seals every payload and excludes itself. Exact source payloads cover all 31
changed paths, all 77 selected test modules and SDK support/runtime record;
the entire unchanged repository and installed SDK image are not distributed.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The copied reviewed decoder verifies hashes/sizes and safe paths before writing,
refuses symlinks and existing output, and never executes decoded contents.
The packet builder only reads, checks and serializes bytes. No project import,
rerun, native operation, candidate edit or upload is performed by packaging.
No private design/review notes or diagnostic-continuation evidence is included.
'''
payloads.extend([(archive_name,encoded,'lossless-all-original-phase-files-raw-logs-source-and-provenance'),('INNER-MEMBER-MANIFEST.json',JSON(inner),'complete-original-member-inventory'),('VALIDATION-SUMMARY.json',JSON(summary),'derived-failure-count-and-scope-summary'),('COMMAND-RECEIPT-SEAL.json',JSON(commands),'derived-command-and-unrun-stage-index'),('decode_verify.py',decoder,'reviewed-safe-decoder-no-content-execution'),('reproduce/build_full_matrix_v28_failure_packet.py',raw(Path(__file__)),'source-only-packet-builder'),('README.md',readme.encode(),'scope-and-transport-guide')])
need(len(payloads)==len({n for n,_,_ in payloads})<=35,'Payload names/count')
# Bounded credential/private-note screening; ordinary original workspace paths are evidence.
secret_patterns=(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',rb'gh[pousr]_[A-Za-z0-9]{30,}',rb'AKIA[0-9A-Z]{16}',rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
for row in originals:
 need(not any(re.search(p,row['data']) for p in secret_patterns),'Credential pattern '+row['path'])
 need(not any(x in row['path'].lower() for x in ('dream_notes','scratch_notes','independent-review','independent-audit')),'Private note path')
# Check every original still has the exact bytes consumed above before writing.
for row in originals:need(raw(Path(row['original_source']))==row['data'],'Original changed during packaging')
O.mkdir();rows=[]
for name,b,kind in sorted(payloads):
 p=O/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(b)
 need(raw(p)==b,'Written payload mismatch');rows.append(dict(path=name,local_source=str(p),bytes=len(b),sha256=SHA(b),kind=kind))
p=O/'PUBLISHABLE-EVIDENCE-MANIFEST.json'
with p.open('xb') as f:f.write(JSON(dict(schema=1,scope=summary['scope'],files=rows)))
print(json.dumps(dict(manifest=str(p),sha256=SHA(raw(p)),payloads=len(rows),original_members=len(members),archived_members=len(archived),original_bytes=inner['original_member_bytes'],packet_bytes_including_manifest=sum(r['bytes'] for r in rows)+len(raw(p)),source_seal_sha256=SEAL,result_sha256=RESULT)))
