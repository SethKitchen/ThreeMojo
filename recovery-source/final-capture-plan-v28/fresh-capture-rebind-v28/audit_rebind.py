"""Source/config-only audit. Never imports candidate tools or executes phases."""
import ast
import difflib
import hashlib
import json
from pathlib import Path
import re

R = Path(__file__).resolve().parent.parent
O = Path(__file__).resolve().parent
P = R/'fresh-capture-plan'
OLD, NEW = P/'prepared/carla-final-v17', P/'prepared/carla-final-v28'
sha = lambda value: hashlib.sha256(value).hexdigest()
read = lambda path: json.loads(path.read_bytes())
digest = lambda path: sha(path.read_bytes())
def dump(path, value):
    with path.open('x') as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True)+'\n')
def snapshot(root):
    result={}
    for path in sorted(root.rglob('*')):
        rel=path.relative_to(root)
        if any(part in ('__pycache__','.cache') for part in rel.parts) or rel.parts[:2]==('coverage','build'):
            continue
        assert not path.is_symlink(),path
        if path.is_file(): result[rel.as_posix()]=digest(path)
    return result
old_seal_path=R/'CANDIDATE-V17-SOURCE-SEAL.json';new_seal_path=R/'CANDIDATE-V28-SOURCE-SEAL.json'
assert digest(old_seal_path)=='3e63e8a02b46f1d2d7102b829427448a891fcb0189c445990ac33bafac9f3d21'
assert digest(new_seal_path)=='fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596'
old_source,new_source=read(old_seal_path),read(new_seal_path)
assert snapshot(R/'candidate-v17')==old_source
assert snapshot(R/'candidate-v28')==new_source
protocol_seal=read(P/'PACKET-SEAL.json')
assert all(digest(P/name)==expected for name,expected in protocol_seal.items())
old_bundle_path=P/'prepared/carla-final-v17-SEAL.json';new_bundle_path=P/'prepared/carla-final-v28-SEAL.json'
old_bundle,new_bundle=read(old_bundle_path),read(new_bundle_path)
assert snapshot(OLD)==old_bundle and snapshot(NEW)==new_bundle
assert set(old_bundle)==set(new_bundle) and len(new_bundle)==9
assert (OLD/'capture_support.py').read_bytes()==(NEW/'capture_support.py').read_bytes()==(P/'capture_support.py').read_bytes()
old_plan,new_plan,spec=read(OLD/'plan.json'),read(NEW/'plan.json'),read(P/'plan-spec.json')
assert {k for k in old_plan.keys()|new_plan.keys() if old_plan.get(k)!=new_plan.get(k)}=={'source_seal_sha256'}
assert all(new_plan[k]==v for k,v in spec.items())
assert new_plan['source_seal_sha256']==digest(new_seal_path)
assert len(spec['suites'])==19 and sum(s['source_test_definitions'] for s in spec['suites'])==86
native=spec['native_closure']['union'];assert len(native)==95
assert sum(name.endswith('.mojo') for name in native)==93
assert len(spec['frozen_hashes'])==96 and set(spec['frozen_hashes'])-set(native)=={'tools/native_test_support.py'}
for name,expected in spec['frozen_hashes'].items():
    assert old_source[name]==new_source[name]==expected
    assert digest(R/'candidate-v17'/name)==digest(R/'candidate-v28'/name)==expected
suites=[]
for suite in spec['suites']:
    path=suite['path'];definitions=len(re.findall(r'^def\s+test_\w*\s*\(', (R/'candidate-v28'/path).read_text(),re.M))
    assert definitions==suite['source_test_definitions'] and digest(R/'candidate-v28'/path)==suite['sha256']
    suites.append({'path':path,'sha256':suite['sha256'],'static_test_definitions':definitions})
targets=[]
for target in spec['targets']:
    path=R/'candidate-v28'/(target['module']+'.mojo')
    span=''.join(path.read_text().splitlines(keepends=True)[target['first_line']-1:target['last_line']]).encode()
    assert digest(path)==target['source_sha256'] and sha(span)==target['span_sha256']
    targets.append({key:target[key] for key in ('id','module','first_line','last_line','source_sha256','span_sha256')})
assert len(targets)==13 and len(spec['center_new_decision_lines'])==29 and len(spec['center_success_exit_lines'])==9
mojo=[name for name in old_source.keys()|new_source.keys() if name.endswith('.mojo')]
reports=[name for name in old_source.keys()|new_source.keys() if 'report' in name.lower()]
coverage=[name for name in old_source.keys()|new_source.keys() if name.startswith('coverage/')]
assert all(old_source.get(name)==new_source.get(name) for name in mojo+reports+coverage)
unchanged_tools=['tools/affected.py','tools/suite_key.py','tools/native_test_support.py','tools/run_suite.py',
                 'tools/coverage_io.py','tools/coverage_hit_aot.py','tools/coverage_toolchain_identity.py']
assert all(old_source[name]==new_source[name] for name in unchanged_tools)
interfaces=[]
for name in ['begin_generation','seal','verify','verify_captures','masked_manifest','capture_receipt_path']:
    args=[]
    for root in ['candidate-v17','candidate-v28']:
        tree=ast.parse((R/root/'tools/coverage_loop_proofs.py').read_bytes())
        fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name==name)
        args.append(ast.dump(fn.args,include_attributes=False))
    assert args[0]==args[1]
    interfaces.append({'function':name,'arguments_AST_sha256':sha(args[0].encode()),'unchanged':True})
settings_old,settings=read(OLD/'settings.json'),read(NEW/'settings.json')
assert digest(R/'run_stage.py')==settings_old['supervisor_sha256']==settings['supervisor_sha256']
replacements=[('carla-final-v17','carla-final-v28'),('/candidate-v17','/candidate-v28'),
              ('CANDIDATE-V17-SOURCE-SEAL.json','CANDIDATE-V28-SOURCE-SEAL.json'),
              (digest(old_seal_path),digest(new_seal_path)),(digest(OLD/'plan.json'),digest(NEW/'plan.json'))]
normalized=[]
for name in sorted(new_bundle):
    before=(OLD/name).read_text();after=(NEW/name).read_text()
    normalized_before=before
    for old,new in replacements:normalized_before=normalized_before.replace(old,new)
    assert normalized_before==after,name
    normalized.append({'path':name,'old_sha256':old_bundle[name],'new_sha256':new_bundle[name],
                       'only_explicit_path_seal_or_derived_plan_hash_rebind':True})
assert settings['suites']==[s['path'] for s in spec['suites']]
assert settings['flags']=='-I .' and settings['profile']=='aot-hits' and settings['coverage_group_seconds']==9000
assert settings['platform_scope']=={'system':'Linux','machine':'x86_64','arm_qualified':False}
phase_rows=[]
for phase,window in [('prepare',1200),('native-o3',4005),('native-o0',4005),('capture',10000),('finish',300)]:
    cfg=read(NEW/(phase+'.json'));assert cfg['window_seconds']==window
    assert cfg['source']==str(R/'candidate-v28') and cfg['seal']==str(new_seal_path)
    assert cfg['additional_sources'][0]=={'source':str(NEW),'seal':str(new_bundle_path)}
    assert not (R/'evidence'/('carla-final-v28-'+phase)).exists()
    if phase.startswith('native-'):
        assert len(cfg['stages'])==39
        for i,suite in enumerate(settings['suites']):
            build,run=cfg['stages'][2*i:2*i+2]
            assert build['seconds']==180 and run['seconds']==15
            assert '--num-threads' in build['command'] and '1' in build['command']
            assert '--target-triple=x86_64-unknown-linux-gnu' in build['command']
            assert '--target-cpu=x86-64-v3' in build['command'] and '--Werror' in build['command']
            assert '-O'+phase[-1] in build['command']
            assert run['command'][run['command'].index('--seconds')+1]=='5'
    if phase=='prepare':
        assert [x['label'] for x in cfg['stages']]==['copy-source','native-inventory','begin-generation','instrument','copy-passthrough','seal-generation','freeze-targets']
    if phase=='capture':
        assert [(s['label'],s['seconds']) for s in cfg['stages']]==[('reporter-build',180),('maintained-captures',9030),('targeted-report',180),('whole-measured-modules-report',180)]
        assert cfg['stages'][2]['accept_nonzero'] is True
    phase_rows.append({'phase':phase,'window_seconds':window,'stage_count':len(cfg['stages']),
                       'stages':[{'label':s['label'],'seconds':s['seconds'],'accept_nonzero':s.get('accept_nonzero',False)} for s in cfg['stages']]})
assert not Path(settings['clone']).exists() and not Path(settings['build']).exists()
changes=[{'path':name,'v17_sha256':old_source.get(name),'v28_sha256':new_source.get(name)}
         for name in sorted(old_source.keys()|new_source.keys()) if old_source.get(name)!=new_source.get(name)]
assert len(changes)==31 and all(row['path'].endswith('.py') or row['path']=='docs/validation/full-audit-721-qualification-policy.md' for row in changes)
comparison={'status':'source_only_no_native_execution','old_source_files':len(old_source),'new_source_files':len(new_source),
            'complete_physical_snapshots_match_both_seals':True,'unchanged_mojo_count':len(mojo),
            'unchanged_report_paths':{name:new_source[name] for name in sorted(reports)},
            'unchanged_coverage_directory_paths':{name:new_source[name] for name in sorted(coverage)},
            'unchanged_native_closure':native,'native_input_count':95,'frozen_pin_count':96,
            'unchanged_closure_and_runtime_tools':{name:new_source[name] for name in unchanged_tools},
            'suites':suites,'targets':targets,'center_new_decision_lines':spec['center_new_decision_lines'],
            'center_success_exit_lines':spec['center_success_exit_lines'],'changed_source_paths':changes,
            'unchanged_called_proof_interfaces':interfaces,'normalized_file_comparisons':normalized,
            'phase_limits':phase_rows,'original_protocol_files_verified':protocol_seal}
dump(O/'SOURCE-AND-PROTOCOL-COMPARISON.json',comparison)
diffs=[]
for name in sorted(new_bundle):
    diffs.extend(difflib.unified_diff((OLD/name).read_text().splitlines(True),(NEW/name).read_text().splitlines(True),
                                    fromfile='carla-final-v17/'+name,tofile='carla-final-v28/'+name))
diffs.extend(difflib.unified_diff(old_bundle_path.read_text().splitlines(True),new_bundle_path.read_text().splitlines(True),
                                fromfile='carla-final-v17-SEAL.json',tofile='carla-final-v28-SEAL.json'))
with (O/'REBIND.diff').open('x') as stream:stream.write(''.join(diffs))
manifest={'schema':1,'status':'PREPARED_SOURCE_ONLY_UNEXECUTED','required_semantic_protocol_changes':[],
          'source_root':str(R/'candidate-v28'),'source_seal_path':str(new_seal_path),'source_seal_sha256':digest(new_seal_path),
          'parent_expected_publication_tree':'d2c9f94523b9c03aa94b04eaad774f73f147cd74','publication_verified_by_this_audit':False,
          'prepared_bundle':str(NEW),'prepared_bundle_seal':str(new_bundle_path),'prepared_bundle_seal_sha256':digest(new_bundle_path),
          'old_bundle_preserved':True,'old_bundle_seal_sha256':digest(old_bundle_path),
          'generator_sha256':digest(P/'prepare_run.py'),'spec_sha256':digest(P/'plan-spec.json'),
          'helper_sha256':digest(NEW/'capture_support.py'),'supervisor_sha256':digest(R/'run_stage.py'),
          'suite_count':19,'native_input_count':95,'native_mojo_inputs':93,'static_definitions':86,
          'target_spans':13,'all_mojo_unchanged':2469,'source_delta_paths':31,
          'execution_gate':'Parent-only serialized native lane after full Python matrix passes, independent rebind review, and exact source publication verification.',
          'fresh_execution_required':'New source clone, maintained closure check, instrumenter, proof generation, target freeze, native O3/O0, reporter build and all19 maintained captures/reports. No v17 capture, proof envelope, denominator or native receipt reuse.',
          'denominator_boundary':'Derive from a new original manifest and current v28 proof tooling. Historical293 is not an acceptance pin.',
          'stdout_and_failure_policy':'Original helper/supervisor bytes are unchanged: actual complete TestSuite outputs, DAZ ledgers, strict report classification, source/SDK/target/capture bindings, prior-phase cleanup checks and failure retention remain mandatory.',
          'platform_scope':settings['platform_scope'],'original_phase_caps_unchanged':True,
          'legacy_provenance_context':'The unchanged generator retains its historical ce7e6e038622792b091ce84d545fb2b8597310bf plus reviewed overlays context string. The explicit complete v28 source seal is the actual new source authority; the context string was not silently repinned.',
          'source_clone_materialized':False,'native_compiler_or_test_execution':False,'candidate_edits':False,
          'preparation_stdout_sha256':digest(O/'PREPARE-STDOUT.json'),
          'comparison_sha256':digest(O/'SOURCE-AND-PROTOCOL-COMPARISON.json'),'actual_diff_sha256':digest(O/'REBIND.diff'),
          'bundle_files':new_bundle}
dump(O/'REBIND-MANIFEST.json',manifest)
print(json.dumps({'manifest':str(O/'REBIND-MANIFEST.json'),'manifest_sha256':digest(O/'REBIND-MANIFEST.json'),
                  'diff_sha256':digest(O/'REBIND.diff'),'comparison_sha256':digest(O/'SOURCE-AND-PROTOCOL-COMPARISON.json'),
                  'prepared_bundle_seal_sha256':digest(new_bundle_path),'diff_bytes':(O/'REBIND.diff').stat().st_size},indent=2))
