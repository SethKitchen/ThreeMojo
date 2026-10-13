#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Source-only binary64 proof for the retained translated-s Map fixture.

No Mojo execution, compilation, production writes, Git writes, or external I/O.
Integer/Fraction rounding to the proven local binary64 lattice is independent
of the host float expression; each modeled source result is cross-checked.
"""
from fractions import Fraction
import hashlib
import json
import math
import os
import re
from pathlib import Path
import struct

PACKAGE = Path(__file__).resolve().parent
SOURCE = PACKAGE.parents[1]
HERE = Path(os.environ.get('CARLA_LANE_ORACLE_OUTPUT', str(SOURCE/'out/carla-lane-oracle')))
HERE.mkdir(parents=True, exist_ok=True)
# A fresh complete current graph is required before consulting the immutable
# historical pins below. Their method/source identities are provenance only;
# the #333 local-polynomial theorem supplies the current numerical semantics.
import full_audit_cleanup_contracts as full_audit
import typed_boundary_contracts as typed_boundary
_CURRENT_BINDINGS = full_audit.proof_bindings(SOURCE)
_OBSERVED = {}


def _current_bytes(name):
    raw = (SOURCE/name).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if name in _CURRENT_BINDINGS and digest != _CURRENT_BINDINGS[name]:
        raise ValueError(('Current fixture input changed', name))
    if _OBSERVED.setdefault(name, raw) != raw:
        raise ValueError(('Fixture input changed after consumption', name))
    return raw


def _historical_text(name):
    text = _current_bytes(name).decode('utf-8')
    return (typed_boundary.historical_source(name, text)
            if typed_boundary.is_current(name, text) else text)


def _finish_current_graph():
    for name, expected in _CURRENT_BINDINGS.items():
        if hashlib.sha256(_current_bytes(name)).hexdigest() != expected:
            raise ValueError(('Current fixture receipt changed', name))
    for name, raw in tuple(_OBSERVED.items()):
        if _current_bytes(name) != raw:
            raise ValueError(('Fixture final observation changed', name))
    # Recheck resolution, the complete caller census, and all owned proof
    # providers after arithmetic. There is no reused verification result.
    if full_audit.proof_bindings(SOURCE) != _CURRENT_BINDINGS:
        raise ValueError('Current fixture graph changed during proof')

B = 100_000_000_000_000_000_000
U = 16384
base = float(B)
end = base + 81920.0
threshold = 0.000001


def bits(value):
    return struct.unpack('>Q', struct.pack('>d', value))[0]


def f32(value):
    return struct.unpack('>f', struct.pack('>f', value))[0]


def exact_grid_round(value):
    """Exact round-to-nearest/even on the local 2^14 lattice."""
    q, r = divmod(value, U)
    q = int(q)
    if 2 * r > U or (2 * r == U and q % 2):
        q += 1
    rounded = q * U
    # Every value used remains strictly inside the same binary64 binade.
    assert 2**66 <= rounded < 2**67
    return rounded


def segment(k, n):
    """Follow map.mojo's source operations for endpoints B+k*U,B+(k+n)*U."""
    first = base + k * U
    second = base + (k+n) * U
    assert int(first) == B+k*U and int(second) == B+(k+n)*U
    one, two = first-base, second-base
    samples = []
    for q in (1, 2, 3):
        fraction = q * 0.25
        exact_s = Fraction(B+k*U) + Fraction(q, 4) * n * U
        rounded_s = exact_grid_round(exact_s)
        source_s = first + fraction * (second-first)
        assert int(source_s) == rounded_s
        point_x = source_s-base
        chord_x = one + fraction * (two-one)
        exact_chord_x = Fraction(k*U) + Fraction(q, 4) * n * U
        assert Fraction(chord_x) == exact_chord_x
        dx = point_x-chord_x
        exact_dx = rounded_s - B - exact_chord_x
        assert Fraction(dx) == exact_dx
        samples.append({
            'fraction': f'{q}/4',
            'exact_requested_s': str(exact_s),
            'rounded_s_bits': f'0x{bits(source_s):016x}',
            'rounded_s_k': (rounded_s-B)//U,
            'point_x': int(point_x),
            'chord_x': str(exact_chord_x),
            'dx': str(exact_dx),
        })
    error = max(float(Fraction(s['dx'])**2) for s in samples)
    middle = first + (second-first)*0.5
    exact_mid = exact_grid_round(Fraction(B+k*U) + Fraction(n*U, 2))
    assert int(middle) == exact_mid
    return {
        'first_k': k, 'second_k': k+n, 'signed_ulps': n,
        'samples': samples, 'max_squared_error': error,
        'accepts_current_chord_target': error <= threshold,
        'midpoint_k': (exact_mid-B)//U,
        'midpoint_is_strictly_interior': min(first,second) < middle < max(first,second),
    }


assert 2**66 <= B < 2**67
assert int(base) == B
assert math.ulp(base) == U == 2**(66-52)
assert math.nextafter(base, math.inf)-base == U
assert math.nextafter(base, -math.inf) == base-U
assert bits(end)-bits(base) == 5
assert B % U == 0 and (B//U) % 2 == 0
assert Fraction(81920.0) == 5*U

# Map._start_of_lane, Road.section_length, straight _create_segments, _step.
epsilon = 10.0 * 2.220446049250313e-16
section_length = end-base
inset = min(10.0*epsilon, section_length/4.0)
start = base + inset
remaining = (end-start)-0.000001
map_end = start + (remaining-epsilon)
assert start == base and map_end == end
assert remaining < section_length
assert Fraction(inset) < U/2

# With a constant axis center, test every subsegment of the exact six-point
# fixture, and a broader signed/origin-shift control matrix in the same binade.
fixture_intervals = [segment(k,n) for k in range(6) for n in range(1,6-k)]
assert len(fixture_intervals) == 15
accepted = [s for s in fixture_intervals if s['accepts_current_chord_target']]
assert [(s['first_k'],s['second_k']) for s in accepted] == [(0,4),(1,5)]
control_count = 0
for k in range(8):
    for n in range(-32,33):
        result = segment(k,n)
        assert result['accepts_current_chord_target'] == (n % 4 == 0)
        control_count += 1

# Exhaust every monotone partition of all six stored parameters. Accepting
# zero-width leaves cannot change this result because they cover no span.
partitions = []
for mask in range(16):
    cuts = [0] + [k for k in range(1,5) if mask & (1 << (k-1))] + [5]
    valid = all(segment(a,b-a)['accepts_current_chord_target'] for a,b in zip(cuts,cuts[1:]))
    assert not valid
    partitions.append({'cuts_k':cuts,'all_leaves_accepted':valid})

# Follow the current midpoint rule along the first failing child.
trace = []
k, n = 0, 5
for depth in range(25):
    state = segment(k,n)
    state['depth'] = depth
    trace.append(state)
    assert not state['accepts_current_chord_target']
    if depth == 24:
        break
    mid = state['midpoint_k']
    left = segment(k,mid-k)
    if not left['accepts_current_chord_target']:
        n = mid-k
    else:
        k, n = mid, k+n-mid
assert [s['signed_ulps'] for s in trace[:3]] == [5,2,1]
assert not trace[2]['midpoint_is_strictly_interior']
assert all(s['first_k']==0 and s['second_k']==1 for s in trace[2:])

# Query references concern representable stored centers, not construction.
# Both y values are exact dyadic rationals; the common y residual cancels
# from each point ordering. Float32 x inputs are exact integers here.
query_y = Fraction(f32(0.0001))
center_y = Fraction(0.0002)*Fraction(1,2)
query_checks=[]
for x,want in [(10000,1),(8192,0),(5000,0),(-1,0),(100000,5)]:
    qx=Fraction(f32(x))
    distances=[(Fraction(k*U)-qx)**2+(center_y-query_y)**2 for k in range(6)]
    result=min(range(6), key=lambda k:(distances[k],k))
    assert result==want
    query_checks.append({'query_x':x,'nearest_k':result,'exact_squared_x_residuals':[str((Fraction(k*U)-qx)**2) for k in range(6)]})
assert query_checks[1]['exact_squared_x_residuals'][0] == query_checks[1]['exact_squared_x_residuals'][1]

# The non-affine path asks for 1 m while at least 81919.999999 m remain.
# Its request is positive and nonterminal. Both direction results stall.
sampling=[]
for reverse in (False, True):
    before=end if reverse else base
    left=(before-base if reverse else end-before)-0.000001
    delta=min(1.0,left)
    after=before+(-delta+epsilon if reverse else delta-epsilon)
    assert delta == 1.0 and left > delta and after == before
    sampling.append({'reverse':reverse,'before_bits':f'0x{bits(before):016x}',
                     'remaining':left,'delta':delta,'after_bits':f'0x{bits(after):016x}'})

# The current retained fixture assigns a constant polynomial after moving
# the geometry/section origins, then changes only c in its non-affine case.
# Inspect its exact admitted declaration rather than infer an origin from the
# enclosing road record. The conditioned theorem distinguishes those origins.
from seed_count_contracts import declaration as _declaration
_fixture_name = 'tests/test_carla_axis_translated_map_blocker.mojo'
_fixture_text = _current_bytes(_fixture_name).decode('utf-8')
_fixture = _declaration(_fixture_text, '_flat_map')
if typed_boundary.is_current(_fixture_name, _fixture_text):
    if ('].polynomial = CubicPolynomial._constant_si(0.0002)' not in _fixture
            or '.polynomial.c = 1e-40' not in _fixture
            or '.polynomial.s =' in _fixture):
        raise ValueError('Current translated fixture local-origin premise changed')

# Pin the relevant source methods. Do not silently update this after a
# scalar graph change: review the proof and each fixture first.
def method_bytes(path, name):
    text=_historical_text(path)
    if path == 'extensions/carla/map.mojo' and name == '_subdivide_segment':
        # The complete current gate above binds the exact deviation leaf.
        # Its added segment certificate field does not change the sampled
        # station or midpoint arithmetic modeled here. Recover only this
        # method's older station-era provenance, without changing its pin.
        from map_deviation_contracts import station_source
        text = station_source(text)
    matches=list(re.finditer(r'(?m)^(?:    )?def '+re.escape(name)+r'[\[(]',text))
    if len(matches) != 1:
        raise ValueError(('Translated method is missing or ambiguous', path, name))
    match=matches[0]
    rest=text[match.start():]
    following=re.search(r'(?m)^(?:    def |def |struct |comptime )',rest[1:])
    return (rest[:following.start()+1] if following else rest).encode()

pin=json.loads(_current_bytes('tools/carla_lane_oracle/translated-parameter-source.json'))
for path, expected in pin['dependency_sha256'].items():
    if hashlib.sha256(_historical_text(path).encode('utf-8')).hexdigest() != expected:
        raise ValueError(('Review translated build dependency after source change', path))
for method in pin['methods']:
    actual=hashlib.sha256(method_bytes(method['path'],method['name'])).hexdigest()
    if actual != method['sha256']:
        raise ValueError(('Review translated-parameter proof after source change', method['path'], method['name']))

report={
    'status':'Source-only exact arithmetic proof; no Mojo build or run',
    'source_pin_sha256':hashlib.sha256(_current_bytes('tools/carla_lane_oracle/translated-parameter-source.json')).hexdigest(),
    'fixture':{'base_decimal':str(B),'base_bits':f'0x{bits(base):016x}',
               'end_decimal':str(int(end)),'end_bits':f'0x{bits(end):016x}',
               'length':81920,'length_bits':f'0x{bits(81920.0):016x}',
               'ulp':U,'stored_parameter_count':6,
               'effective_start_bits':f'0x{bits(start):016x}',
               'effective_end_bits':f'0x{bits(map_end):016x}'},
    'stored_parameters':[{'k':k,'bits':f'0x{bits(base+k*U):016x}',
                          's':str(int(base+k*U)),'center_x':k*U} for k in range(6)],
    'unchanged_squared_target':threshold,'unchanged_turn_limit':0.5,'unchanged_depth_limit':24,
    'fixture_subintervals':fixture_intervals,'all_monotone_partitions':partitions,
    'unguarded_first_failing_branch_trace':trace,
    'explicit_resolution_guard_first_depth':2,
    'independent_signed_origin_shift_controls':control_count,
    'query_controls':query_checks,
    'new_non_affine_regression':{'quadratic_width':1e-40,
                                 'quadratic_width_bits':f'0x{bits(1e-40):016x}',
                                 'positive_nonterminal_steps':sampling},
}
report['current_semantic_scope'] = (
    'Reviewed #333 translated fixture only: geometry and section stations '
    'move to 1e20 while each tested width polynomial origin stays zero, '
    'including the c=1e-40 nonprogress mutation. Historical method identity '
    'is provenance, not expanded/local polynomial equivalence.')
report['current_graph_sha256'] = dict(_CURRENT_BINDINGS)
_finish_current_graph()
result=HERE/'translated-parameter-resolution.json'
result.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'result':'PASS','subintervals':15,'impossible_partitions':16,
                  'lattice_controls':control_count,'query_controls':5,
                  'nonterminal_step_directions':2,'report':str(result)},indent=2))
