"""Recover test before pinned formatting from retained full generation text."""
from pathlib import Path
import hashlib,json
P=Path(__file__).parent
probe=(P/'probe_center_phase_inputs.mojo').read_text()
probe=probe.replace('"""Bounded real-input qualification for a proposed optional-bound phase.\n\nExisting production only. No proposed helper exists or is invoked here.','"""Direct optional-center bound controls with real numerical inputs.\n\nThe refusal fixture executes the extracted numerical phase.')
probe=probe.replace('from extensions.carla.curve_interval import _next_down, _next_up','from extensions.carla.curve_interval import _Interval, _next_down, _next_up')
probe=probe.replace('    _checked_center,','    _LaneBoundClose,\n    _LaneBoundContract,\n    _LaneBoundDiscard,\n    _LaneBoundPolicy,\n    _LaneExpansionContext,\n    _try_lane_center_bound,\n    _checked_center,',1)
probe=probe.replace('from std.testing import TestSuite, assert_equal, assert_false, assert_true','from std.testing import (\n    TestSuite, assert_equal, assert_false, assert_raises, assert_true,\n)\nfrom tests.test_carla_cross_candidate_certificates import _road')
probe=probe.replace('test_real_unknown_domain_and_cheap_line_incumbent','test_real_center_count_refusal_preserves_ledger_and_empty_caches')
marker='    assert_equal(terms, 5000000006)\n    assert_true(_sum2_supported_environment())'
replacement='''    assert_equal(terms, 5000000006)
    var context = _LaneExpansionContext(
        0, 0, _Interval(low, best), location, None, None, None, None, None
    )
    var nodes = 0
    var proposal = _try_lane_center_bound(
        road,
        context,
        _Interval(low, high),
        best,
        domain,
        natural,
        whole_work,
        _LaneBoundPolicy(best_bounds.high, scale, tolerance, None),
        nodes,
        terms,
        16,
        max_terms,
    )
    assert_false(Bool(proposal))
    assert_equal(nodes, 0)
    assert_equal(terms, 5000000006)
    assert_false(Bool(context.cached_fast))
    assert_false(Bool(context.cached_expansion))
    assert_true(_sum2_supported_environment())'''
assert marker in probe;probe=probe.replace(marker,replacement)
probe=probe[:probe.index('\ndef main() raises:')]
s=probe+(P/'line-tests.append.txt').read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='db5e250d29b68b9328ac200308524e9ca04a35c4bb98c21407d2177bb5cb9bec',hashlib.sha256(s.encode()).hexdigest()
(P/'test.native-v1.mojo').write_text(s)
s=s.replace('    _LaneBoundPolicy,','    _LaneBoundPolicy,\n    _LaneBoundProposal,')
s=s.replace('from tests.test_carla_cross_candidate_certificates import _road','from tests.test_carla_cross_candidate_certificates import _road\nfrom tests._lazy_taylor_controls import _diagonal_road, _whole_certificate\nfrom tests._spiral_acceptance_controls import _capture_acceptance_proof')
helper='''def _proposal_values(
    proposal: _LaneBoundProposal,
) -> Tuple[Float64, Float64, Float64]:
    if proposal.isa[_LaneBoundDiscard]():
        var value = proposal[_LaneBoundDiscard]
        return (value.lower, value.support.low, value.support.high)
    if proposal.isa[_LaneBoundClose]():
        var value = proposal[_LaneBoundClose]
        return (value.lower, value.support.low, value.support.high)
    var value = proposal[_LaneBoundContract]
    return (value.lower, value.support.low, value.support.high)


'''
s=s.replace('def _check_line_phase(',helper+'def _check_line_phase(')
s=s.replace('        # An admission error preserves the populated cache and spent ledger.','''            var first_values = _proposal_values(result.value())
            var next_values = _proposal_values(repeated.value())
            for i in range(3):
                assert_equal(
                    bitcast[DType.uint64](first_values[i]),
                    bitcast[DType.uint64](next_values[i]),
                )
        # An admission error preserves the populated cache and spent ledger.''')
s=s.replace('\ndef main() raises:',(P/'POST-DEBIT-TEST.txt').read_text()+'\n\ndef main() raises:')
assert hashlib.sha256(s.encode()).hexdigest()=='6206d8d950c7622a5c9919d8d8fa641c4c6af26fd690500a9abdf48c1b71d694',hashlib.sha256(s.encode()).hexdigest()
(P/'test.native-v2-compile-failure.mojo').write_text(s)
s=s.replace('''            for i in range(3):
                assert_equal(
                    bitcast[DType.uint64](first_values[i]),
                    bitcast[DType.uint64](next_values[i]),
                )''','''            for values in [
                (first_values[0], next_values[0]),
                (first_values[1], next_values[1]),
                (first_values[2], next_values[2]),
            ]:
                assert_equal(
                    bitcast[DType.uint64](values[0]),
                    bitcast[DType.uint64](values[1]),
                )''')
actual=hashlib.sha256(s.encode()).hexdigest()
assert actual=='ff15d56ec87c1569250ad7b1e8eda8aadeee9180b5797133abf9eee1cb19374c',actual
(P/'test_carla_lane_center_bound_phase.before-format.mojo').write_text(s)
(P/'TEST-PREFORMAT-RECOVERY.json').write_text(json.dumps({'exact_preformat_sha256':actual,'expected_final_sha256':'7848eb3592d4caa4f3bd8fd4d5bcc1f7f2d45cff1ad1d904db13b1df1ac9696c','status':'Pre-format exact bytes recovered; formatting still required. No native qualification.'},indent=2)+'\n')
print(actual)
