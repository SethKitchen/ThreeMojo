# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Rational derivation of the seven unchanged sample-blend fixture rows.

The old-error model follows the frozen full-Jet primitive contract. The
coupled allowance uses its reviewed error identity with independently
computed rational endpoint brackets and binary64 neighbor padding. A second
oracle evaluates the three scalar graphs exactly and is independent of both
bound recipes. This reference is specific to singleton, zero-inherited-error
fixture rows; it does not replace the uniform production proof. This module never reads or executes production Mojo code.
"""
from dataclasses import dataclass
from fractions import Fraction as F
import json
import math
from pathlib import Path
import struct

ROWS = [(.25,100.,101.),(.1,1e16,1e16+2),
        (.9999999999999999,-5.1,-5.2),(-2.,1.,3.),(3.,-1.,2.),
        (.5,1e308,-1e308),(.3,1e-308,-1e-308)]
MIN = F(2) ** -400
MAX = F(2) ** 400
ETA = math.ulp(0.)
INF = math.inf

def bits(x):
    return struct.unpack('<Q', struct.pack('<d',x))[0]

def word(x):
    return f'0x{bits(x):016x}'

def rn(x):
    try:
        return float(x)
    except OverflowError:
        return INF if x > 0 else -INF

def up(x):
    return math.nextafter(x, INF)

def down(x):
    return math.nextafter(x, -INF)

def ceil64(x):
    f=rn(x)
    if f == INF:return f
    if f == -INF:return -float.fromhex('0x1.fffffffffffffp1023')
    return up(f) if F(f)<x else f

def floor64(x):
    return -ceil64(-x)

def rounding(m):
    # Independent half-binade-spacing rule. Eta is used when eta/2 is not
    # representable. The reviewed primitive adds one outward neighbor.
    if not math.isfinite(m) or m<0:return INF
    half=F(math.ulp(m))/2
    return up(rn(max(half,F(ETA))))

def plus(a,b):
    return rn(F(a)+F(b)) if math.isfinite(a) and math.isfinite(b) else a+b

def times(a,b):
    return rn(F(a)*F(b)) if math.isfinite(a) and math.isfinite(b) else a*b

def supported(x):
    return math.isfinite(x) and (x==0 or MIN<=abs(F(x))<=MAX)

@dataclass(frozen=True)
class I:
    lo: float
    hi: float
    @classmethod
    def point(cls,x):return cls(x,x)
    @classmethod
    def exact(cls,lo,hi=None):
        if hi is None:hi=lo
        return cls(floor64(lo),ceil64(hi))
    @classmethod
    def padded(cls,lo,hi):return cls(down(lo),up(hi))
    def point_is(self,x):return self.lo==x and self.hi==x
    @property
    def mag(self):return max(abs(self.lo),abs(self.hi))
    @property
    def finite(self):return math.isfinite(self.lo) and math.isfinite(self.hi)
    def __neg__(self):return I(-self.hi,-self.lo)
    def __add__(self,o):
        if self.point_is(0):return o
        if o.point_is(0):return self
        return I.padded(plus(self.lo,o.lo),plus(self.hi,o.hi))
    def __mul__(self,o):
        if self.point_is(1):return o
        if o.point_is(1):return self
        if (self.point_is(0) and o.finite) or (o.point_is(0) and self.finite):return I.point(0.)
        vals=[times(a,b) for a in (self.lo,self.hi) for b in (o.lo,o.hi)]
        if any(math.isnan(x) for x in vals):return I(-INF,INF)
        return I.padded(min(vals),max(vals))

def tight_sum(a,b):
    def endpoint(x,y):
        if supported(x) and supported(y):return I.exact(F(x)+F(y))
        return I.point(x)+I.point(y)
    return I(endpoint(a.lo,b.lo).lo,endpoint(a.hi,b.hi).hi)

def power_of_two(x):
    if not math.isfinite(x) or x==0:return False
    numerator,denominator=abs(x).as_integer_ratio()
    return numerator & (numerator-1)==0

def tight_product(a,b):
    def endpoint(x,y):
        if supported(x) and supported(y):return I.exact(F(x)*F(y))
        z=times(x,y)
        if (power_of_two(x) or power_of_two(y)) and (
            x==0 or y==0 or math.isfinite(z) and abs(z)>float.fromhex('0x1p-1022')):
            return I.point(z)
        return I.point(x)*I.point(y)
    vals=[endpoint(x,y) for x in (a.lo,a.hi) for y in (b.lo,b.hi)]
    return I(min(p.lo for p in vals),max(p.hi for p in vals))

@dataclass(frozen=True)
class FrozenValueError:
    value:I
    error:float=0.
    @classmethod
    def constant(cls,x):return cls(I.point(x))
    def __neg__(self):return FrozenValueError(-self.value,self.error)
    def __add__(self,o):
        if self.value.point_is(0) and self.error==0:return o
        if o.value.point_is(0) and o.error==0:return self
        value=tight_sum(self.value,o.value)
        inherited=up(plus(self.error,o.error))
        return FrozenValueError(value,up(plus(inherited,rounding(up(plus(value.mag,inherited))))))
    def __sub__(self,o):return self+-o
    def __mul__(self,o):
        value=tight_product(self.value,o.value)
        inherited=(I.point(self.value.mag)*I.point(o.error)
                  +I.point(o.value.mag)*I.point(self.error)
                  +I.point(self.error)*I.point(o.error)).hi
        error=up(plus(inherited,rounding(up(plus(value.mag,inherited)))))
        if self.value.point_is(0) and self.error==0 and o.value.finite:error=0.
        elif o.value.point_is(0) and o.error==0 and self.value.finite:error=0.
        elif self.value.point_is(1) and self.error==0:error=o.error
        elif o.value.point_is(1) and o.error==0:error=self.error
        return FrozenValueError(value,error)

def original_error(r,a,b):
    j=FrozenValueError.constant
    return (j(r)*j(a)+(j(1.)-j(r))*j(b)).error

def coupled_error(r,a,b):
    if not all(supported(x) for x in (r,a,b)):return INF, None
    # A singleton exact stored rate has no inherited rate perturbation. The
    # reviewed identity therefore reduces to b*ec + ep + eq + ez. These
    # rational brackets and padded positive sums expose each contribution.
    comp=I.exact(1-F(r))
    ec=0. if F(1,2)<=F(r)<=2 else rounding(comp.mag)
    actual_comp=comp+I(-ec,ec)
    p=I.exact(F(r)*F(a))
    products=[F(x)*F(b) for x in (actual_comp.lo,actual_comp.hi)]
    q=I.exact(min(products),max(products))
    ep,eq=rounding(p.mag),rounding(q.mag)
    final_mag=(I.point(p.mag)+I.point(q.mag)+I.point(ep)+I.point(eq)).hi
    ez=rounding(final_mag)
    weighted_complement=I.point(abs(b))*I.point(ec)
    value=(weighted_complement+I.point(ep)+I.point(eq)+I.point(ez)).hi
    return value, {'complement_error':ec,'first_product_error':ep,
                   'second_product_error':eq,'final_error':ez,
                   'weighted_complement':weighted_complement.hi,
                   'sum_magnitude':final_mag}

def scalar_graphs(r,a,b):
    # Every product, complement and complete sum is rounded exactly once
    # using Fraction. No production helper or bound formula is called.
    c=rn(1-F(r)); p=rn(F(r)*F(a)); q=rn(F(c)*F(b))
    return [rn(F(p)+F(q)),rn(F(r)*F(a)+F(q)),rn(F(c)*F(b)+F(p))]

def derive():
    rows=[]
    for index,(r,a,b) in enumerate(ROWS):
        exact=F(r)*F(a)+(1-F(r))*F(b)
        derivative=F(a)-F(b)
        graphs=scalar_graphs(r,a,b)
        maximum=max(abs(F(x)-exact) for x in graphs)
        old=original_error(r,a,b);coupled,parts=coupled_error(r,a,b)
        chosen=min(old,coupled)
        rows.append({'row':index,'input_words':list(map(word,(r,a,b))),
          'supported':math.isfinite(coupled),'original_error':old,
          'original_error_word':word(old),'coupled_error_word':word(coupled),
          'expected_error':chosen,'expected_error_word':word(chosen),
          'changed_error':bits(chosen)!=bits(old),
          'error_word_decrease':bits(old)-bits(chosen),
          'exact_value':str(exact),'exact_first':str(derivative),'exact_second':'0',
          'value_bracket':list(map(word,(floor64(exact),ceil64(exact)))),
          'first_bracket':list(map(word,(floor64(derivative),ceil64(derivative)))),
          'graph_words':list(map(word,graphs)),
          'required_error_fraction':str(maximum),'required_error_up':ceil64(maximum),
          'required_error_word':word(ceil64(maximum)),
          'coupled_parts':parts})
    return rows

if __name__=='__main__':
    rows=derive(); target=Path(__file__).parent/'blend-row-ledger.json'
    target.write_text(json.dumps(rows,indent=2,allow_nan=False)+'\n')
    for r in rows:
        print(r['row'],r['supported'],r['original_error_word'],r['coupled_error_word'],
              r['expected_error_word'],r['error_word_decrease'],r['graph_words'])
