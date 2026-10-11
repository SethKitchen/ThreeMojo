"""Freshly bind the preserved genuine report to composed v38 producer inputs."""
from pathlib import Path
import hashlib,json,sys
R=Path(__file__).resolve().parent; ROOT=Path.cwd(); OUT=Path(sys.argv[1]); GEN=R/'evidence/anatomy-report-generation-v16'
sha=lambda b:hashlib.sha256(b).hexdigest()
def need(ok,msg):
 if not ok:raise RuntimeError(msg)
need(ROOT==R/'candidate-v38','Wrong candidate root')
seal_path=R/'CANDIDATE-V38-SOURCE-SEAL.json'; need(sha(seal_path.read_bytes())=='47eb6c57d3d88f116326dfab6bb999d31e909f532a396318b05fd2254dac8537','Source seal identity')
original_path=R/'evidence/anatomy-report-binding-v16/REPORT-BINDING-RESULT.json';original_raw=original_path.read_bytes()
need(sha(original_raw)=='3807443877d95bce90db3af9c03dd9da8c165a18de2757ac55365d2deea2343d','Original binding receipt identity')
original=json.loads(original_raw); need(original['status']=='PASS','Original binding was unsuccessful')
sys.path.insert(0,str(ROOT/'tools'));import anatomy_validity as av
need(Path(av.__file__).resolve()==ROOT/'tools/anatomy_validity.py','Producer module origin')
snapshot=av.source_snapshot(ROOT)
need(snapshot[0]==original['source_binding_sha256'] and snapshot[1]==original['bound_input_sha256'] and len(snapshot[1])==205,'Fresh producer input closure differs from genuine generation')
probe=GEN/'anatomy-probe';metadata=probe.with_suffix('.provenance.json').read_bytes();provenance=json.loads(metadata)
need(sha(probe.read_bytes())==original['binary_sha256'] and sha(metadata)==original['provenance_sha256'],'Original probe/provenance bytes differ')
av.verify_report_inputs(ROOT,probe,provenance,snapshot,metadata)
report_path=ROOT/'docs/validation/anatomy-template-report.json';raw=report_path.read_bytes();data=json.loads(raw)
need(raw==(GEN/'generated-anatomy-report.json').read_bytes() and sha(raw)==original['generated_report_sha256'] and len(raw)==original['generated_report_bytes'],'Preserved genuine report differs')
need(data['build_provenance']==provenance and provenance['toolchain']==av.PINNED_TOOLCHAIN and provenance['flags']==av.BUILD_FLAGS,'Report contract differs')
need(data['report_logic_sha256']==snapshot[1]['tools/anatomy_validity.py'] and data['inventory_sha256']==snapshot[1][av.INVENTORY],'Report producer/inventory identity')
inventory=json.loads(snapshot[2]);names=sorted({p for row in inventory['parameters'] for p in row['source_files']})
need(data['source_file_sha256']=={p:snapshot[1][p] for p in names} and data['provenance_inventory']==inventory,'Embedded inventory binding differs')
need(sha((ROOT/'tools/humanoid_fidelity.py').read_bytes())==original['report_envelope_consumer_sha256'],'Report envelope consumer changed')
av.verify_report_inputs(ROOT,probe,provenance,snapshot,metadata)
need(report_path.read_bytes()==raw,'Report changed during binding')
receipt={'schema':1,'status':'PASS','scope':'Fresh current resolver/producer-input binding of original genuine full report. No report regeneration, native execution, or transfer of whole-tree qualification. The unrelated physics source universe changed; the actual 205-input closure was recomputed twice by the current producer and remained exact.','candidate':str(ROOT),'base_commit':'6db270f00be742545d6f8961d70762a101783f6e','source_seal_sha256':sha(seal_path.read_bytes()),'original_binding_receipt_sha256':sha(original_raw),'generated_report_sha256':sha(raw),'generated_report_bytes':len(raw),'binary_sha256':sha(probe.read_bytes()),'provenance_sha256':sha(metadata),'source_binding_sha256':snapshot[0],'bound_input_sha256':snapshot[1],'verifier_sha256':sha(Path(__file__).read_bytes())}
(OUT/'REPORT-BINDING-RESULT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
print('PASS: current v38 resolver recomputed205 unchanged genuine report inputs; original report/probe bytes retained')
