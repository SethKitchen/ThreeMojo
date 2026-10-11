"""Verify genuine generated report/probe/current-input binding without changing source."""
from pathlib import Path
import copy,hashlib,json,math,sys
ROOT=Path.cwd();OUT=Path(sys.argv[1]);GEN=Path(sys.argv[2]);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
PLAN=Path(__file__).resolve().parent
if sha(PLAN/'CANDIDATE-V16-SOURCE-SEAL.json')!='478fbee7e6e2fa274df78090c6d83bcd16ad1e550bd9e25f77e4a7b4883c2eed':raise RuntimeError('Generation source seal differs')
r=json.loads((GEN/'RESULT.json').read_text())
if not (r['sequence_completed'] and r['failure'] is None and r['source_seal_unchanged'] and r['sdk_identity_unchanged'] and r['remaining_owned_descendants']==[]):raise RuntimeError('Generation supervisor did not qualify')
# Bind the actual terminal receipts to the reviewed command/source/SDK protocol.
config_path=PLAN/'anatomy-report-generation-v16.json'
if sha(config_path)!='61caf56bf797f0640c9f58b7941abc8c8ff7521154073f9d50a30bc770441ff4':raise RuntimeError('Reviewed generation config changed')
config=json.loads(config_path.read_text());py=str(PLAN.parent/'restored-toolchain/official-venv/bin/python');mojo=str(PLAN.parent/'restored-toolchain/official-venv/bin/mojo')
expected_argv=[x.replace('{python}',py).replace('{mojo}',mojo).replace('{evidence}',str(GEN)) for x in config['stages'][0]['command']]
if len(r['stages'])!=1:raise RuntimeError('Generation stage inventory differs')
stage=r['stages'][0]
if not (stage['label']=='generate-full-report' and stage['argv']==expected_argv and stage['cwd']==str(ROOT) and stage['stage_timeout_seconds']==1800 and stage['returncode']==0 and stage['timed_out'] is False and stage['leader_reaped'] is True and stage['remaining_owned_descendants']==[]):raise RuntimeError('Generation command or terminal state differs')
if stage!=json.loads((GEN/'generate-full-report-RESULT.json').read_text()) or sha(GEN/'generate-full-report.log')!=stage['log_sha256']:raise RuntimeError('Generation stage receipt or raw log differs')
started=json.loads((GEN/'generate-full-report-START.json').read_text())
if any(stage.get(k)!=v for k,v in started.items()):raise RuntimeError('Generation start and terminal receipts disagree')
expected_seal=sha(PLAN/'CANDIDATE-V16-SOURCE-SEAL.json')
if sha(GEN/'SOURCE-SEAL.json')!=expected_seal or stage['source_seal_sha256']!=expected_seal:raise RuntimeError('Generation source receipt differs')
window=json.loads((GEN/'WINDOW-START.json').read_text());supervisor_sha=sha(PLAN/'run_checkpoint_matrix.py')
if supervisor_sha!='6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032' or window['supervisor_sha256']!=supervisor_sha or window['source_seal_sha256']!=expected_seal or window['python_optimize']!=0 or window['runtime_gate_seconds']!=5 or window['whole_window_seconds']!=10800:raise RuntimeError('Generation supervisor protocol differs')
pinned=json.loads((PLAN.parent/'restored-toolchain/receipts/mojo-identity.json').read_text())
if json.loads((GEN/'SDK-BEFORE.json').read_text())!=pinned or json.loads((GEN/'SDK-AFTER.json').read_text())!=pinned:raise RuntimeError('Generation SDK receipt differs')
sys.path.insert(0,str(ROOT/'tools'))
import anatomy_validity as av
if Path(av.__file__).resolve()!=ROOT/'tools/anatomy_validity.py':raise RuntimeError('Producer came from another root')
report_path=GEN/'generated-anatomy-report.json';probe=GEN/'anatomy-probe';provenance_path=probe.with_suffix('.provenance.json')
report_bytes=report_path.read_bytes();data=json.loads(report_bytes);metadata=provenance_path.read_bytes();provenance=json.loads(metadata)
snapshot=av.source_snapshot(ROOT);av.verify_report_inputs(ROOT,probe,provenance,snapshot,metadata)
if data['build_provenance']!=provenance or provenance['toolchain']!=av.PINNED_TOOLCHAIN or provenance['flags']!=av.BUILD_FLAGS:raise RuntimeError('Report/probe provenance differs')
if data['report_logic_sha256']!=snapshot[1]['tools/anatomy_validity.py'] or data['inventory_sha256']!=snapshot[1][av.INVENTORY]:raise RuntimeError('Report code/inventory binding differs')
inventory=json.loads(snapshot[2]);names=sorted({p for row in inventory['parameters'] for p in row['source_files']})
if data['source_file_sha256']!={p:snapshot[1][p] for p in names} or data['provenance_inventory']!=inventory:raise RuntimeError('Report source inventory differs')
if data['schema_version']!=2 or data['spec']!={'stature_m':1.8288,'sex':'male','side':'right','athleticism':'untoned','genome':'template'}:raise RuntimeError('Report specification differs')
if data['gate']!=av.use_gate('template-estimate') or data['result_label']!='template estimate':raise RuntimeError('Report usage gate or result label differs')
pairs=data['pair_inventory'];rows=pairs['pairs'];ids=[row['pair_id'] for row in rows]
if not (pairs['run_scope']=='full' and len(pairs['components'])==134 and pairs['total_pairs']==8911 and len(rows)==8911 and len(set(ids))==8911 and all(row['status']=='checked' for row in rows) and pairs['all_catalog_pairs_checked'] is True and pairs['selected_execution_complete'] is True):raise RuntimeError('Full pair accounting differs')
catalog=copy.deepcopy(pairs['components'])
if av.validate_catalog(catalog)!=pairs['components'] or pairs['schema_version']!=1 or pairs['frame_id']!=av.PAIR_FRAME:raise RuntimeError('Canonical catalog or frame differs')
plan=av.pair_plan(catalog,'full');classes={}
for actual,expected in zip(rows,plan,strict=True):
 for key in ('pair_id','first_id','second_id','class','status'):
  if actual.get(key)!=expected[key]:raise RuntimeError('Exact canonical pair identity differs: '+key)
 counts=classes.setdefault(expected['class'],{'checked':0,'intentionally_omitted':0,'unsupported':0});counts[expected['status']]+=1
if pairs['classes']!=classes:raise RuntimeError('Per-class full pair accounting differs')
import humanoid_fidelity as hf
if Path(hf.__file__).resolve()!=ROOT/'tools/humanoid_fidelity.py':raise RuntimeError('Report envelope consumer came from another root')
for name in av.SEGMENTS:
 for index in range(3):hf.report_properties(data,name,index)
if set(data['segments'])!=set(av.SEGMENTS):raise RuntimeError('Segment inventory differs')
for segment in data['segments'].values():
 if len(segment['grids'])!=3 or not all(math.isclose(row['step_m'],step,rel_tol=1e-6) for row,step in zip(segment['grids'],(.02,.01,.005),strict=True)):raise RuntimeError('Grid settings differ')
av.finite_tree(data)
av.verify_report_inputs(ROOT,probe,provenance,snapshot,metadata)
if report_path.read_bytes()!=report_bytes:raise RuntimeError('Generated report changed while checked')
receipt={'schema':1,'status':'PASS','scope':'Genuine generated report/probe/current-input binding and unchanged full-scope accounting. Does not replace final regression/native/coverage qualification.','generation_result_sha256':sha(GEN/'RESULT.json'),'generated_report_sha256':sha(report_path),'generated_report_bytes':len(report_bytes),'binary_sha256':sha(probe),'provenance_sha256':sha(provenance_path),'source_binding_sha256':snapshot[0],'bound_input_sha256':snapshot[1],'source_seal_sha256':sha(PLAN/'CANDIDATE-V16-SOURCE-SEAL.json'),'verifier_sha256':sha(Path(__file__)),'generation_stage_receipt_sha256':sha(GEN/'generate-full-report-RESULT.json'),'generation_window_sha256':sha(GEN/'WINDOW-START.json'),'generation_sdk_before_sha256':sha(GEN/'SDK-BEFORE.json'),'generation_sdk_after_sha256':sha(GEN/'SDK-AFTER.json'),'report_envelope_consumer_sha256':sha(ROOT/'tools/humanoid_fidelity.py'),'pair_components':134,'checked_pairs':8911,'exact_pair_identities_and_class_accounting':True,'report_grid_envelopes_checked':9,'specification':data['spec']}
(OUT/'REPORT-BINDING-RESULT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
print('PASS: genuine full134-component/8911-pair report bound to current source, producer, inventory, probe and SDK provenance')
