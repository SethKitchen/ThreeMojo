#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Regenerate directed CARLA index-key controls from exact rational squares.

Output needs no compiler or formatter. Use --check for an exact, read-only
replay of the saved fixture. Do not combine --check and --json.
"""
from pathlib import Path
from fractions import Fraction
from decimal import Decimal,localcontext
import math,struct,random,json,argparse
root=Path(__file__).resolve().parents[1];s=root;rng=random.Random(589302)
parser=argparse.ArgumentParser(description=__doc__, allow_abbrev=False);parser.add_argument('--json',type=Path)
parser.add_argument('--check', action='store_true', help='verify without writing')
args=parser.parse_args()
if args.check and args.json is not None:
 parser.error('--check is read-only; do not combine it with --json')
def bits(v):return struct.unpack('>Q',struct.pack('>d',v))[0]
def floor_bound(k,d):
 q=Fraction.from_float(k)/(1+Fraction(1,2**40));df=Fraction.from_float(d)
 if df*df>=q:return 0.0
 with localcontext() as c:
  c.prec=130;x=float((Decimal(q.numerator)/Decimal(q.denominator)).sqrt()-Decimal(d))
 while (Fraction.from_float(x)+df)**2>q:x=math.nextafter(x,0)
 while (Fraction.from_float(math.nextafter(x,math.inf))+df)**2<=q:x=math.nextafter(x,math.inf)
 return x
cases=[]
for i in range(96):
 k=math.ldexp(1+rng.random(),rng.randrange(-298,260));radius=math.sqrt(k)
 d=radius*rng.choice([0,.125,.5,.99,1,2]);f=floor_bound(k,d)
 cases.append([bits(k),bits(d),bits(f)])
t='''# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Directed admission controls for the frozen #589 segment key contract."""

from extensions.carla.lane_refinement import _indexed_curve_lower
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_index_key_allowance_against_exact_rational_squared_bound() raises:
    var cases: List[Array[UInt64, 3]] = [
'''
for a in cases:
 t+='        [\n'
 t+=''.join(f'            UInt64(0x{x:016X}),\n' for x in a)
 t+='        ],\n'
t+='''    ]
    for i in range(len(cases)):
        var key = bitcast[DType.float64](cases[i][0])
        var deviation = bitcast[DType.float64](cases[i][1])
        # Largest Float64 L with (L+deviation)^2 <= K/(1+2^-40),
        # generated using exact rational squares rather than native sqrt.
        var reference = bitcast[DType.float64](cases[i][2])
        var lower = _indexed_curve_lower(key, deviation)
        assert_true(lower >= 0.0)
        assert_true(lower <= reference)
        if reference > 0.0:
            assert_true(lower > 0.0)


def test_unknown_index_bounds_disable_pruning() raises:
    assert_equal(_indexed_curve_lower(0.0, 0.0), 0.0)
    assert_equal(_indexed_curve_lower(-1.0, 0.0), 0.0)
    assert_equal(_indexed_curve_lower(1.0, -1.0), 0.0)
    assert_equal(_indexed_curve_lower(inf[DType.float64](), 0.0), 0.0)
    assert_equal(_indexed_curve_lower(1.0, inf[DType.float64]()), 0.0)
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    assert_equal(_indexed_curve_lower(nan, 0.0), 0.0)
    assert_equal(_indexed_curve_lower(1.0, nan), 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
'''
target=s/'tests/test_carla_index_admission.mojo'
expected=t.encode('utf-8')
if args.check:
 try:matches=target.read_bytes()==expected
 except OSError as error:raise SystemExit(f'Cannot check {target}: {error}')
 if not matches:raise SystemExit(f'{target} is stale; regenerate without --check')
else:target.write_bytes(expected)
if args.json:args.json.write_text(json.dumps(cases,indent=2)+'\n')
print('Verified' if args.check else 'Generated',len(cases),'cases independently bounded by exact rational inequalities')
