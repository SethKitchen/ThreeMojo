"""Terminal-only v34 focused evidence packaging; no candidate/test execution.

Use only after terminal notification and independent source review. All three
expected hashes must be supplied explicitly. No waiting, polling or live packet.
"""
from pathlib import Path
import argparse, base64, gzip, hashlib, json, re, stat
R=Path(__file__).resolve().parent
PHASE='post-diagnostic-repairs-focused-v34'
E=R/'evidence'/PHASE
S=R/'candidate-v34'
O=R/'validation-evidence-post-diagnostic-repairs-focused-v34-packet'
SEALS={'34':'482899bef6550a42cbbf8e63329fa3a9a32feec144640bc74d9a0c117461b796','33':'5b34331e984e7abc56840d55e6115851d17e62337b1c6d90abb1b6701f465397','28':'fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596'}
PINS={
 PHASE+'.json':'9e98f266b990aa4b6d3ba864047f89316cd6a8978c3c3a93882cb89584f4a5a9',
 'run_checkpoint_matrix.py':'6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032',
 'combined-repairs-v34-independent-materialization/AUDIT.json':'e8ade1e4b293d241f79b5d68a2f4c854a7090bd18d88d019ac9074536dacdb7d',
 'combined-repairs-implementation-v34/PUBLISHABLE-SOURCE-MANIFEST.json':'d4ddb7eabc284ee61ae8639c1639d960f241cf8c44331a690955ec98acb439c9',
 'combined-repairs-implementation-v34/CUMULATIVE-ELEVEN-PATH-SOURCE-MANIFEST.json':'4815c5fe6a728f90bf56215566a217d830c72ab94b347a2e57a53d2b80408ee3',
 'PUBLISHED-V28-QUALIFICATION-BINDING.json':'0df492bd6c870ecb2e8a6d3cb66167c2d5042aa7ba0a70d4b42f02f71eef8bdf',
 'evidence/full-python-matrix-final-v28/RESULT.json':'a2d054ac36ac97e729d292956a2233f10b479b6f40194fec90c9f088858be844',
 'evidence/full-python-diagnostic-continuation-v28/RESULT.json':'ddcd0576ed61827896eac96a52ae44a7d98cbb9f202137d7a38ecb887838359b',
}
SDK='7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207'
DECODER='a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4'
SHA=lambda b:hashlib.sha256(b).hexdigest()
JSON=lambda x:(json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def need(value,message):
 if not value:raise ValueError(message)
def raw(path):
 need(stat.S_ISREG(path.lstat().st_mode),'Nonregular or symlink '+str(path))
 need(path.stat().st_size<64*1024*1024,'Oversize '+str(path))
 return path.read_bytes()
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 for key in ('result','console','builder'):parser.add_argument('--expected-'+key+'-sha256',required=True)
 args=parser.parse_args()
 for value in vars(args).values():need(re.fullmatch('[0-9a-f]{64}',value) is not None,'Exact hash required')
 # This gate precedes all reads of focused evidence and source files.
 need((E/'RESULT.json').is_file(),'Refuse: focused RESULT absent; run has not reached terminal receipt')
 need(not O.exists() and not O.is_symlink(),'Never overwrite evidence')
 observed={}
 def read(path,expected=None):
  data=raw(path)
  if expected is not None:need(SHA(data)==expected,'Changed binding '+str(path))
  if path in observed:need(observed[path]==data,'Changed during read '+str(path))
  observed[path]=data;return data
 builder=read(Path(__file__).resolve(),args.expected_builder_sha256)
 result_raw=read(E/'RESULT.json',args.expected_result_sha256);result=json.loads(result_raw)
 console_path=R/(PHASE+'.supervisor.log');console_raw=read(console_path,args.expected_console_sha256)
 console=[json.loads(line) for line in console_raw.decode('utf-8').splitlines()]
 need(console and console[-1]==result,'Refuse: completed console has no matching terminal result')
 bound={name:read(R/name,digest) for name,digest in PINS.items()}
 config=json.loads(bound[PHASE+'.json'])
 audit=json.loads(bound['combined-repairs-v34-independent-materialization/AUDIT.json'])
 small=json.loads(bound['combined-repairs-implementation-v34/PUBLISHABLE-SOURCE-MANIFEST.json'])
 cumulative=json.loads(bound['combined-repairs-implementation-v34/CUMULATIVE-ELEVEN-PATH-SOURCE-MANIFEST.json'])
 seals={v:json.loads(read(R/('CANDIDATE-V'+v+'-SOURCE-SEAL.json'),digest)) for v,digest in SEALS.items()}
 need(read(E/'SOURCE-SEAL.json',SEALS['34'])==observed[R/'CANDIDATE-V34-SOURCE-SEAL.json'],'Executed source seal')
 before=read(E/'SDK-BEFORE.json',SDK);after=read(E/'SDK-AFTER.json')
 window=json.loads(read(E/'WINDOW-START.json'))
 need(config['phase']==PHASE and config['source']==str(S) and config['source_seal_sha256']==SEALS['34']
      and config['seal']=='CANDIDATE-V34-SOURCE-SEAL.json' and config['scope']==result['scope'],'Exact focused config')
 need(config['additional_sources']==[dict(source=str(R/('candidate-v'+v)),seal=str(R/('CANDIDATE-V'+v+'-SOURCE-SEAL.json'))) for v in ('33','28')],'Exact additional baselines')
 need(window['supervisor_sha256']==PINS['run_checkpoint_matrix.py'] and window['source_seal_sha256']==SEALS['34']
      and window['python_optimize']==0 and window['runtime_gate_seconds']==5
      and window['whole_window_seconds']==config['window_seconds']==10800,'Supervisor/window caps')
 need(result['source_seal_unchanged'] is True and result['sdk_identity_unchanged'] is (json.loads(before)==json.loads(after))
      and isinstance(result['remaining_owned_descendants'],list),'Terminal source/SDK/cleanup receipt')
 need(type(result['sequence_completed']) is bool,'Terminal completion flag')
 plans=config['stages'];stages=result['stages'];labels=[p['label'] for p in plans]
 need(len(plans)==len(audit['stages'])==12 and sum(p['expected_tests'] for p in plans)==40
      and len(set(labels))==12 and audit['config_sha256']==PINS[PHASE+'.json']
      and audit['candidate_source_seal_sha256']==SEALS['34'],'Reviewed twelve-stage/fourty-execution scope')
 need([s['label'] for s in stages]==labels[:len(stages)] and len(console)==len(stages)+1,'Recorded prefix/console')
 need(all(p['seconds']==1800 and not p.get('accept_nonzero',False) for p in plans),'Unchanged fatal stage policy and caps')
 need(set(seals['34'])==set(seals['33'])==set(seals['28']) and len(seals['34'])==3837,'Source-seal path inventory')
 delta4={p for p in seals['34'] if seals['34'][p]!=seals['33'][p]}
 delta11={p for p in seals['34'] if seals['34'][p]!=seals['28'][p]}
 need(delta4=={r['path'] for r in small['files']} and len(delta4)==small['delta_count']==4
      and delta11=={r['path'] for r in cumulative['files']} and len(delta11)==cumulative['delta_count']==11,'Exact manifest deltas')
 need(small['source_seal_sha256']==cumulative['source_seal_sha256']==SEALS['34']
      and small['base_source_seal_sha256']==SEALS['33'] and cumulative['base_source_seal_sha256']==SEALS['28'],'Manifest seal binding')
 # Only named sealed files are read after terminal notification. No candidate scan.
 for row in cumulative['files']:
  path=row['path'];new=read(S/path,row['sha256']);read(R/'candidate-v28'/path,row['before_sha256'])
  need(row['sha256']==seals['34'][path] and row['before_sha256']==seals['28'][path]
       and len(new)==row['bytes'] and row['mode']=='100644' and not((S/path).stat().st_mode&0o111)
       and hashlib.sha1(b'blob '+str(len(new)).encode()+b'\0'+new).hexdigest()==row['git_blob'],'Changed source mode/hash/blob '+path)
 for row in small['files']:
  path=row['path'];need(row['sha256']==seals['34'][path] and row['before_sha256']==seals['33'][path],'Four-path manifest '+path)
  read(R/'candidate-v33'/path,row['before_sha256'])
 related=('tools/carla_lane_oracle/full_audit_cleanup_contracts.py','tools/carla_lane_oracle/seed_count_contracts.py',
          'tools/carla_lane_oracle/sum2_guard_contracts.py','tools/carla_lane_oracle/source_contracts.py',
          'tools/carla_lane_oracle/_full_audit_test_fixtures.py','tools/coverage_toolchain_identity.py')
 for path in related:read(S/path,seals['34'][path])
 stage_names=set();outcomes=[];unrun=[]
 for index,planned in enumerate(plans):
  label=planned['label'];reviewed=audit['stages'][index];command=planned['command']
  need(reviewed['label']==label and reviewed['expected_tests']==planned['expected_tests'] and reviewed['seconds']==1800,'Reviewed command selection')
  module=command[command.index('-s')+1]+'/'+command[command.index('-p')+1]
  need(reviewed['source_sha256']==seals['34'][module],'Selected module seal')
  argv=[part.replace('{python}',str(R.parent/'restored-toolchain/official-venv/bin/python')) for part in command]
  files={suffix:E/(label+suffix) for suffix in ('-START.json','-RESULT.json','.log')}
  present={suffix:path for suffix,path in files.items() if path.exists() or path.is_symlink()}
  stage_names.update(p.name for p in present.values())
  for path in present.values():read(path)
  if index>=len(stages):
   need('-RESULT.json' not in present and (not present or index==len(stages)),'Unindexed stage artifacts')
   if present:
    need('.log' in present,'Incomplete launch is missing its actual log')
    if '-START.json' in present:
     start=json.loads(observed[files['-START.json']])
     need(start['label']==label and start['argv']==argv and start['cwd']==str(S)
          and start['source_seal_sha256']==SEALS['34'] and start['stage_timeout_seconds']==1800,
          'Incomplete launch START binding')
    observed[files['.log']].decode('utf-8')
   unrun.append(dict(label=label,expected_methods=planned['expected_tests'],artifacts=sorted(p.name for p in present.values()),
                    status='incomplete launch without terminal stage receipt' if present else 'unlaunched'))
   continue
  need(set(present)==set(files),'Missing stage START/RESULT/log')
  stage=json.loads(observed[files['-RESULT.json']]);start=json.loads(observed[files['-START.json']]);log_raw=observed[files['.log']];log=log_raw.decode('utf-8')
  need(stage==stages[index] and all(stage.get(k)==v for k,v in start.items()),'Individual terminal receipt')
  need(stage['argv']==argv and stage['cwd']==str(S) and stage['source_seal_sha256']==SEALS['34']
       and stage['stage_timeout_seconds']==1800 and SHA(log_raw)==stage['log_sha256']
       and stage['leader_reaped'] is True,'Actual command/cap/source/log/leader')
  need(console[index]=={k:v for k,v in stage.items() if k not in ('test_count','expected_tests','skipped_test_count')},'Actual console stage')
  totals=re.findall(r'^Ran (\d+) tests? in ',log,re.M);need(len(totals)<=1,'Ambiguous method count')
  methods=int(totals[0]) if totals else None
  headers=re.findall(r'^(test_\w+) \(([\w.]+)\) \.\.\. ',log,re.M)
  ids=[full for method,full in headers]
  need(len(ids)==len(set(ids)) and set(ids)<=set(reviewed['selected']),'Unexpected/repeated selected method')
  annotated='test_count' in stage
  if annotated:
   need(stage['test_count']==stage['expected_tests']==planned['expected_tests']==methods
        and stage['skipped_test_count']==sum(' ... skipped ' in line for line in log.splitlines())
        and set(ids)==set(reviewed['selected']),'Complete focused method inventory')
  status=re.findall(r'^(?:OK(?: \([^\n]*\))?|FAILED \([^\n]*\))$',log,re.M);need(len(status)<=1,'Ambiguous unittest outcome')
  passed=stage['returncode']==0 and not stage['timed_out'] and not stage['remaining_owned_descendants'] and annotated and stage['skipped_test_count']==0 and status==['OK']
  outcomes.append(dict(label=label,expected_methods=planned['expected_tests'],reported_methods=methods,selected=reviewed['selected'],
                       observed_method_headers=ids,unittest_status=status[0] if status else None,passed_focused_stage=passed,
                       returncode=stage['returncode'],timed_out=stage['timed_out'],seconds=stage['seconds'],count_annotations_present=annotated,
                       log_sha256=SHA(log_raw),log_bytes=len(log_raw)))
 if result['sequence_completed']:
  need(len(stages)==12 and result['failure'] is None,'Completed sequence mismatch')
 else:need(bool(result['failure']),'Missing terminal failure')
 required={'RESULT.json','SOURCE-SEAL.json','SDK-BEFORE.json','SDK-AFTER.json','WINDOW-START.json'}
 optional={'FAILURE.json','LATEST.json','PROCESSES.jsonl','LANE-CHECKPOINT.json','LANE-HANDOFFS.jsonl'}
 actual={p.name for p in E.iterdir()}
 need(required<=actual and actual<=required|optional|stage_names,'Unknown/missing terminal phase file')
 for name in actual:read(E/name)
 if result['failure'] is not None:need('FAILURE.json' in actual and json.loads(observed[E/'FAILURE.json'])['error']==result['failure'],'Failure traceback binding')
 else:need('FAILURE.json' not in actual,'Unexpected failure receipt')
 originals=[]
 def add(path,name,kind,readable=False):
  data=read(path);data.decode('utf-8');originals.append(dict(path=name,data=data,original_source=str(path),kind=kind,readable=readable))
 for name in sorted(actual):add(E/name,'actual/'+PHASE+'/'+name,'original-terminal-focused-phase',name in ('RESULT.json','FAILURE.json','SDK-BEFORE.json','SDK-AFTER.json','WINDOW-START.json'))
 add(console_path,'actual/'+console_path.name,'complete-actual-terminal-console')
 for name in PINS:add(R/name,'reproduce/'+name,'exact-reviewed-protocol-manifest-audit-or-prior-failure-binding',name in (PHASE+'.json','run_checkpoint_matrix.py'))
 for v in SEALS:add(R/('CANDIDATE-V'+v+'-SOURCE-SEAL.json'),'reproduce/CANDIDATE-V'+v+'-SOURCE-SEAL.json','exact-primary-or-additional-baseline-seal')
 for row in cumulative['files']:
  path=row['path'];add(S/path,'reproduce/source-v34/'+path,'exact-cumulative-revised-source');add(R/'candidate-v28'/path,'reproduce/source-before-v28/'+path,'exact-published-baseline-source')
 for row in small['files']:
  path=row['path'];add(R/'candidate-v33'/path,'reproduce/source-before-v33/'+path,'exact-direct-predecessor-source')
 for path in related:add(S/path,'reproduce/source-v34/'+path,'exact-related-helper-fixture-or-sdk-source')
 all_passed=len(outcomes)==12 and all(row['passed_focused_stage'] for row in outcomes) and result['source_seal_unchanged'] and result['sdk_identity_unchanged'] and result['remaining_owned_descendants']==[] and result['sequence_completed']
 summary=dict(schema=1,status='TERMINAL_V34_FOCUSED_DIAGNOSTIC_EVIDENCE',diagnostic_only=True,qualification_passed=False,
  all_selected_focused_stages_passed=all_passed,planned_stages=12,planned_method_executions=40,
  actual_stages=outcomes,unrun_stages=unrun,reported_method_executions=sum(x['reported_methods'] or 0 for x in outcomes),
  result_sha256=SHA(result_raw),console_sha256=SHA(console_raw),config_sha256=PINS[PHASE+'.json'],
  supervisor_sha256=PINS['run_checkpoint_matrix.py'],source_seal_sha256=SEALS['34'],additional_baseline_seals={v:SEALS[v] for v in ('33','28')},
  sdk_before_sha256=SHA(before),sdk_after_sha256=SHA(after),source_seal_unchanged=result['source_seal_unchanged'],
  sdk_identity_unchanged=result['sdk_identity_unchanged'],remaining_owned_descendants=result['remaining_owned_descendants'],
  finished=result['finished'],elapsed_seconds=result['elapsed_seconds'],stage_cap_seconds=1800,window_cap_seconds=10800,
  actual_sequence_completed=result['sequence_completed'],actual_failure=result['failure'],
  scope=config['scope'],policy_boundary='The exact configured focus records the two-probe timeout-policy owner approval as pending. This packet records source-scoped diagnostic outcomes and does not grant or infer policy approval or full qualification.',
  count_boundary='Reported unittest methods and failure/error/subtest records are distinct. Raw logs are complete; interrupted stages may lack a method total. Unlaunched expected counts are not executed counts.',
  source_boundary='Eleven cumulative changed paths and their v28 before-bytes; four immediate v33 before-files; six related sealed helpers. Seal dictionaries and original manifests are bound. No full candidate or installed-SDK scan is performed by this builder.',
  baseline_boundary='Unchanged supervisor verifies both configured additional source trees. Its primary unchanged flag is not an invented per-baseline receipt.',
  earlier_failures='The original v28 full matrix and terminal diagnostic collection remain failed and separately preserved. Their exact RESULT receipts are provenance, never relabeled by this focus.',
  pending_scope='Full modules, fresh complete final matrix, native controls, maintained coverage, hosted CI and issue completion are outside this packet.',
  evidence_policy='Original terminal bytes plus explicitly derived summary/index only. No project imports, tests/native runs, candidate edits, uploads, live phase packaging or private notes.')
 commands=dict(schema=1,kind='derived-exact-focused-command-and-outcome-index',config_sha256=PINS[PHASE+'.json'],result_sha256=SHA(result_raw),
               source_seal_sha256=SEALS['34'],planned=config['stages'],actual=stages,unrun=unrun,qualification_passed=False)
 archive='containers/ORIGINAL-EVIDENCE.json.gz.b64';members=[];archived=[];payloads=[]
 need(len(originals)==len({x['path'] for x in originals}),'Duplicate original member')
 for row in sorted(originals,key=lambda x:x['path']):
  b=row['data'];member={key:row[key] for key in ('path','kind','original_source')};member.update(bytes=len(b),sha256=SHA(b))
  if row['readable']:payloads.append((row['path'],b,'byte-exact-readable-original'));member.update(storage='readable',transport_path=row['path'])
  else:archived.append(dict(path=row['path'],bytes=len(b),sha256=SHA(b),data_base64=base64.b64encode(b).decode()));member.update(storage='container',transport_path=archive)
  members.append(member)
 container=(json.dumps(dict(schema=1,encoding='base64',members=archived),sort_keys=True,separators=(',',':'))+'\n').encode()
 need(len(container)<64*1024*1024,'Reviewed decoder size bound; no truncation permitted')
 encoded=base64.b64encode(gzip.compress(container,compresslevel=9,mtime=0))+b'\n'
 need(gzip.decompress(base64.b64decode(encoded))==container,'Container round-trip')
 inner=dict(schema=1,original_member_count=len(members),original_member_bytes=sum(x['bytes'] for x in members),
  container=dict(path=archive,encoding='base64 of deterministic gzip mtime=0 containing JSON',members=len(archived),json_bytes=len(container),json_sha256=SHA(container)),members=members)
 decoder=read(R/'validation-evidence-qualification-policy-v23-packet/decode_verify.py',DECODER)
 guide='''# V34 post-diagnostic repair focus

This packet reports the actual terminal outcomes of twelve focused stages with
forty planned method executions. VALIDATION-SUMMARY.json distinguishes recorded
passing, failing, interrupted and unrun evidence. Even if every selected method
passes, this is source-scoped diagnostic evidence. Qualification remains false;
full modules, the full matrix, native/coverage and hosted CI are outside scope.
The configured two-probe timeout-policy approval remains a separate decision.

All actual per-stage START/RESULT/full raw UTF-8 logs, terminal phase files and
complete actual console are preserved without truncation. Exact source/SDK,
commands and original 1800/10800-second caps remain bound. Both baseline source
seals, reviewed installed/config audit, exact four-path and cumulative eleven-path
manifests, before/revised sources and related sealed helpers are included.
Earlier v28 failed receipts remain separate provenance and are not relabeled.

Method totals are distinct from failure records and subtests. Missing totals
or unrun stages are disclosed. The supervisor's source/SDK/cleanup receipts are
identified as that boundary; the packet builder neither executes code nor scans
candidate or SDK trees. No live receipt is packaged as completed evidence.

Original members carry path, size, hash and storage. Archived originals use
base64 JSON, deterministic gzip mtime=0, then UTF-8 base64. Outer manifest seals
all payloads except itself. Summary and command index are derived metadata.

Verify: python -B decode_verify.py
Decode: python -B decode_verify.py --output /path/to/new-directory
The reviewed decoder validates safe paths, sizes and hashes, rejects symlinks
and existing output, and never executes decoded bytes. No private notes or
unrelated later-run evidence is included. Publication requires separate review.
'''
 payloads.extend([(archive,encoded,'lossless-complete-original-evidence'),('INNER-MEMBER-MANIFEST.json',JSON(inner),'complete-original-member-inventory'),
  ('VALIDATION-SUMMARY.json',JSON(summary),'derived-focused-diagnostic-summary'),('COMMAND-RECEIPT-SEAL.json',JSON(commands),'derived-command-and-binding-index'),
  ('decode_verify.py',decoder,'reviewed-safe-decoder'),('reproduce/'+Path(__file__).name,builder,'source-only-packet-builder'),('README.md',guide.encode(),'scope-and-safe-transport-guide')])
 need(len(payloads)==len({name for name,_,_ in payloads})<=35,'Payload names/count')
 patterns=(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',rb'gh[pousr]_[A-Za-z0-9]{30,}',rb'AKIA[0-9A-Z]{16}',rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
 for row in originals:need(not any(re.search(p,row['data']) for p in patterns),'Credential pattern '+row['path'])
 need({p.name for p in E.iterdir()}==actual,'Terminal phase membership changed')
 for path,b in observed.items():need(raw(path)==b,'Input changed during packaging '+str(path))
 O.mkdir();rows=[]
 for name,b,kind in sorted(payloads):
  p=O/name;p.parent.mkdir(parents=True,exist_ok=True)
  with p.open('xb') as f:f.write(b)
  need(raw(p)==b,'Output copy mismatch');rows.append(dict(path=name,local_source=str(p),bytes=len(b),sha256=SHA(b),kind=kind))
 manifest=O/'PUBLISHABLE-EVIDENCE-MANIFEST.json'
 with manifest.open('xb') as f:f.write(JSON(dict(schema=1,scope=config['scope'],files=rows)))
 print(json.dumps(dict(manifest=str(manifest),sha256=SHA(raw(manifest)),payloads=len(rows),original_members=len(members),
  archived_members=len(archived),packet_bytes_including_manifest=sum(x['bytes'] for x in rows)+len(raw(manifest)),
  all_selected_focused_stages_passed=all_passed,qualification_passed=False)))
if __name__=='__main__':main()
