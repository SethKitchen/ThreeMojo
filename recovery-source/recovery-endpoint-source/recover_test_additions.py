"""Recover retained original endpoint controls and exact assembly transformation.

Optional argument: recovered f01a81f4 domains suite. Never fabricate its missing
middle section. Without that input only known fragments are materialized.
No Mojo process, formatting, compile, or qualification is executed here.
"""
from pathlib import Path
import difflib,hashlib,json,sys
R=Path(__file__).resolve().parent
sha=lambda s:hashlib.sha256(s.encode()).hexdigest()
junction=(R/'probes/probe_junction_endpoint_controls.mojo').read_text()
allfalse='''def test_real_junction_admitted_endpoints_charge_both_traversals() raises:
    var road = _first_road()
    road.info.geometries[0].geometry.curvature_start = 0.0
    road.info.geometries[0].geometry.curvature_end = 0.0
    var low = Float64(0)
    var high = Float64(0.125)
    var terms = _reference_work(road, low, high)
    var first_terms = _reference_work(road, low, low)
    var last_terms = _reference_work(road, high, high)
    assert_true(terms >= 0)
    assert_true(first_terms >= 0)
    assert_true(last_terms >= 0)
    var point = _lane_value_bound(road, 0, 0, low, high)
    var work = _MapBuildWork(MapBuildBudget(0, 9, terms + first_terms + last_terms, 0))
    var result = _monotone_junction_enclosure(road, 0, 0, low, high, terms, Box3(Vector3(-2, -2, 2), Vector3(2, 2, 2)), point[0].rounded_value(), -point[1].rounded_value(), point[2].rounded_value(), work)
    assert_equal(work.steps, 9)
    assert_equal(work.terms, terms + first_terms + last_terms)
    assert_false(work.exhausted)
    for station in [low, high]:
        var actual = road._lane_center(0, 0, station)
        assert_true(result[0].contains(actual[0]))
        assert_true(result[1].contains(actual[1]))
        assert_true(result[2].contains(actual[2]))
    print("ADMITTED_LEDGER", work.steps, work.terms)


'''
junction=junction.replace('def main() raises:',allfalse+'def main() raises:')
(R/'maintained/tests/test_carla_junction_endpoint_refusals.mojo').write_text(junction)
last=junction[junction.index('def _last_road()'):junction.index('def test_genuine_endpoint_refusals_keep_bounds_ledgers_and_state()')]
last=last.replace('_last_road','_last_endpoint_refusal_road').replace('_same(', '_same_interval_words(')
last+='''def test_real_last_endpoint_refusal_preserves_helper_bounds_and_reservations() raises:
    var modes = external_call["sum2_test_mode_count", Int32]()
    assert_true(modes == 5 or modes == 7)
    if modes == 7:
        _last_endpoint_control(Int32(5))
        _last_endpoint_control(Int32(6))
    else:
        print("LAST_DAZ_CAPABILITY_UNAVAILABLE: fixture exposes Arm modes0..4; first-end FTZ control is a separate maintained test")


'''
last+=allfalse.replace('_first_road()', '_endpoint_refusal_road()')
chord=(R/'maintained/tests/test_carla_chord_endpoint_refusals.mojo').read_text();chord=chord[chord.index('def _road('):chord.index('def main()')].replace('_road(', '_chord_endpoint_refusal_road(').replace('_control(', '_chord_endpoint_refusal_control(')
(R/'DOMAIN-APPEND-FRAGMENT.mojo').write_text(last+chord)
result={'classification':'recovered from full retained creation text; per-file original hash not retained','original_combined_before_sha256':'f01a81f48ec2e696fe7f4402d0b15c8ddccb6f036b948b8341065f572ba553d4','original_combined_after_sha256':'caf08b631961185d026982b754d2c0b5c33af75a12d066f9699cbaa633038cb2','combined_before_source':'missing; only append transformation recovered','fragment_sha256':sha(last+chord),'native_qualification':'Not run in recovered executor; lost receipts must be regenerated.'}
if len(sys.argv)>1:
 before=Path(sys.argv[1]).read_text();assert sha(before)==result['original_combined_before_sha256']
 after=before.replace('from extensions.carla.lane_refinement import (','from extensions.carla.lane_refinement import (\n    _ProofNodeWork,\n    _chord_certificate_capture_with_nodes,',1)
 after=after.replace('from math.bounds import Box3','from extensions.carla.spiral_domain_proof import _SpiralRootCapture\nfrom math.bounds import Box3',1)
 assert after.count('def main() raises:')==1
 after=after.replace('def main() raises:',last+chord+'def main() raises:')
 assert sha(after)==result['original_combined_after_sha256'],sha(after)
 (R/'test_carla_full_audit_domains.mojo').write_text(after)
 (R/'test-domain-additions.patch').write_text(''.join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='a/tests/test_carla_full_audit_domains.mojo',tofile='b/tests/test_carla_full_audit_domains.mojo')))
 result['classification']='Exact combined recovery verified against recorded before and after hashes'
 result['combined_before_source']=str(sys.argv[1])
(R/'TEST-RECOVERY.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
