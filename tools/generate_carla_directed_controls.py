#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Regenerate bounded CARLA endpoint arithmetic controls from exact Fractions."""
from pathlib import Path
from fractions import Fraction
import math,random,struct,json,argparse
r=Path(__file__).resolve().parents[1];s=r;rng=random.Random(594400)
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--json',type=Path);args=parser.parse_args()
def bits(x):return struct.unpack('>Q',struct.pack('>d',x))[0]
def bracket(f):
 try:x=float(f)
 except OverflowError:x=math.copysign(math.inf,1 if f>0 else -1)
 if math.isinf(x):return (math.nextafter(x,0),x) if x>0 else (x,math.nextafter(x,0))
 exact=Fraction(x);return (math.nextafter(x,-math.inf) if exact>f else x,math.nextafter(x,math.inf) if exact<f else x)
def valid(x):return x==0 or 2**-400<=abs(x)<=2**400
pairs=[(0.,1.),(-0.,-1.),(1.,0.5),(math.nextafter(1,0),-1.),(2**400,2**-400),(-2**-400,2**400),(math.nextafter(2**-400,0),2.),(2**-500,2**500),(2**500,-2**500)]
for i in range(119):
 def sample():return (-1 if rng.randrange(2) else 1)*math.ldexp(1+rng.random(),rng.choice([-400,-399,-1,0,1,398,399]))
 pairs.append((sample(),sample()))
cases=[]
for a,b in pairs:
 af,bf=Fraction(a),Fraction(b);values=[a,b,*bracket(af+bf),*bracket(af*bf),*bracket(af/bf)];cases.append({'bits':list(map(bits,values)),'tight':valid(a) and valid(b)})
t='''# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact Fraction controls for bounded directed endpoint arithmetic."""

from extensions.carla.curve_interval import _directed_endpoint_sum, _directed_endpoint_product, _directed_endpoint_quotient, _tight_quotient_bound, _Interval
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_directed_endpoint_fraction_corpus() raises:
    var cases: List[Tuple[Array[UInt64, 8], Bool]] = [
'''
for c in cases:t+='        (['+', '.join(f'UInt64(0x{x:016X})' for x in c['bits'])+f'], {c["tight"]}),\n'
t+='''    ]
    for i in range(len(cases)):
        ref row = cases[i]
        var a = bitcast[DType.float64](row[0][0])
        var b = bitcast[DType.float64](row[0][1])
        var values: Array[_Interval, 3] = [_directed_endpoint_sum(a,b), _directed_endpoint_product(a,b), _directed_endpoint_quotient(a,b)]
        for j in range(3):
            var low = bitcast[DType.float64](row[0][2+2*j])
            var high = bitcast[DType.float64](row[0][3+2*j])
            assert_true(values[j].low <= low)
            assert_true(values[j].high >= high)
            if row[1]:
                assert_equal(values[j].low,low)
                assert_equal(values[j].high,high)


def test_directed_zero_denominator_retains_unknown_enclosure() raises:
    assert_true(_directed_endpoint_quotient(1.0,0.0).contains(-1.0))
    assert_true(_directed_endpoint_quotient(1.0,0.0).contains(1.0))
    assert_true(_tight_quotient_bound(_Interval.point(1.0),_Interval(-1.0,1.0)).contains(0.0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
'''
(s/'tests/test_carla_directed_fraction.mojo').write_text(t)
if args.json:args.json.write_text(json.dumps(cases,indent=2)+'\n')
print(len(cases),'exact Fraction controls')
