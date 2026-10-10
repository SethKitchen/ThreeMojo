"""Reconstruct original cleanup edits from retained complete diff output.

This restores the original six edits only, not later endpoint/center changes.
No native execution or qualification is performed.
"""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1] / 'ThreeMojo-restored'
REF = 'a45ec12b'
BEFORE = {
    'extensions/carla/curve_bounds.mojo': 'a57a5fa078fc6f36389a0abdce1eaa483a1cb7b7325688689a5602e8680ca3fb',
    'extensions/carla/lane_value_bounds.mojo': '08978a7aa665aca4b82d41e1ff8b99451c647c0f8e7d6ee010fc6a6143f7959c',
    'extensions/carla/junction_bounds.mojo': 'c933e03b6bde0bede8fb0745e9c1ef075d9699fde72b74795368943381d1aa74',
    'extensions/carla/lane_refinement.mojo': 'd6bb8cb266fa350491f71e92295e70bcbfc2566b34db02400b3a6cb5bb5a93ad',
}
AFTER = {
    'extensions/carla/curve_bounds.mojo': 'a5f662df6bc146010b065341143c75223151289dc0cc633590d96b0a199ab8f5',
    # Independently confirmed from the integrator's retained v17 source seal.
    'extensions/carla/lane_value_bounds.mojo': '9028d65fdcb680ec5363f7fc974d8d46532b0f50397d7a348fc16e33821f4121',
    'extensions/carla/junction_bounds.mojo': 'd8b7a6de8e495ab16f0cbe9688459eb544ac9ef6c8ec0c44c952ed5b4743a615',
}
BLEND = (
    '    if isfinite(coupled_error) and coupled_error >= 0.0:\n',
    '    # The concrete producer returns a nonnegative allowance or infinity.\n'
    '    # Keep the finite fallback; a finite negative result is not produced.\n'
    '    if isfinite(coupled_error):\n',
)
EDITS = {
    'extensions/carla/curve_bounds.mojo': [BLEND],
    'extensions/carla/lane_value_bounds.mojo': [BLEND],
    'extensions/carla/junction_bounds.mojo': [(
        '''        if end > start:
            end = bitcast[DType.float64](bitcast[DType.uint64](end) - 1)
            start = _next_up(start)
            if start <= end:
                _certify_junction_span(
                    road, section, lane, start, end, out, work
                )
''',
        '''        # Finite, distinct sorted cuts and the retained final endpoint b
        # make end strictly greater than start. Adjacent stations still
        # need the inner check after both endpoints move into the interior.
        end = bitcast[DType.float64](bitcast[DType.uint64](end) - 1)
        start = _next_up(start)
        if start <= end:
            _certify_junction_span(road, section, lane, start, end, out, work)
''')],
    'extensions/carla/lane_refinement.mojo': [(
        '''    if isfinite(seed):
        seed = min(max(seed, lo), hi)
        var point = _checked_center(road, section, lane, seed, terms, max_terms)
        if point[axis] == query[axis]:
            return (seed, _legacy_square(point, query), point^, nodes, terms)
        if direction * point[axis] < target:
            lo = seed
            left = point^
        else:
            hi = seed
            right = point^
''',
        '''    # The accepted rounded context bounds coordinates and nonzero slope
    # to 2^-400..2^400. This inverse cannot overflow Float64.
    seed = min(max(seed, lo), hi)
    var seed_point = _checked_center(
        road, section, lane, seed, terms, max_terms
    )
    if seed_point[axis] == query[axis]:
        return (
            seed,
            _legacy_square(seed_point, query),
            seed_point^,
            nodes,
            terms,
        )
    if direction * seed_point[axis] < target:
        lo = seed
        left = seed_point^
    else:
        hi = seed
        right = seed_point^
'''), (
        '''            if (
                domain.second.low > 0.0
                and domain.first.contains(0.0)
                and isfinite(hi - lo)
            ):
''',
        '''            # Admit finite interpolation width before the derivative tests.
            # All three predicates are retained. The earlier midpoint already
            # evaluated this same subtraction, including an overflowing span.
            if (
                isfinite(hi - lo)
                and domain.second.low > 0.0
                and domain.first.contains(0.0)
            ):
'''), (
        '''                if natural > best_upper:
                    continue
                if _goal_excludes(natural, scale, goal):
''',
        '''                # An unchanged seed repeats the admitted bound exactly.
                # An improved seed is an actual in-cell witness, so its
                # upper distance cannot fall below this natural enclosure.
                if _goal_excludes(natural, scale, goal):
''')],
}

def sha(data):
    return hashlib.sha256(data).hexdigest()

records = []
for path, expected in BEFORE.items():
    before = subprocess.check_output(['git', '-C', str(REPO), 'show', REF + ':' + path])
    assert sha(before) == expected, (path, 'original before hash differs', sha(before))
    text = before.decode()
    for old, new in EDITS[path]:
        assert text.count(old) == 1, (path, 'nonunique retained inverse span', text.count(old))
        text = text.replace(old, new, 1)
    data = text.encode()
    out = ROOT / 'original-cleanup' / path
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    expected_after = AFTER.get(path)
    if expected_after:
        assert sha(data) == expected_after, (path, 'after mismatch', sha(data))
    records.append({'path': str(out.relative_to(ROOT)), 'before_sha256': expected,
                    'after_sha256': sha(data), 'recorded_after_sha256': expected_after,
                    'classification': 'byte-exact verified against recorded after hash' if expected_after else
                    'reconstructed from complete retained exact diff; needs recorded after-hash comparison'})
(ROOT / 'RECOVERY.json').write_text(json.dumps({'scope': 'Original six-edit cleanup only; not later endpoint/center changes', 'files': records}, indent=2) + '\n')
print(json.dumps(records, indent=2))
