#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact-rational interval/absolute-error Float64 forward analysis.

Each operation receives an interval for the exact stored-expression value
and an absolute error for executed Float64 arithmetic. Every interval endpoint
and error is rounded outward to a 2^-160 rational grid to bound denominator
growth. This introduces outward slack only, with exact Fraction operations. Round-to-nearest
unit roundoff is 2^-53. A 2^-1075 additive allowance covers gradual
underflow for elementary round-to-nearest operations. FTZ/DAZ is unsupported.
The term graph conservatively allows contraction within a term. Every completed
term must be materialized before the non-reassociated streaming Sum2 recurrence.
Sum2 uses the independently derived E + (u + gamma_(n-1)^2) M theorem bound;
its residual arithmetic must not be contracted, reassociated or flushed.
"""
from fractions import Fraction as F
import json
from oracle import HERE,BITS,J,W,S,C,r,h,grade,mf,out,b64
U=F(1,2**53); TINY=F(1,2**1075)
GRID=2**160
def down(x):return F(x.numerator*GRID//x.denominator,GRID)
def up(x):return -down(-x)

def require(condition, message):
    if not condition:
        raise ValueError(message)


from sum2_analysis import sum2_error


def sum2_terms(terms):
    """Enclose the unchanged ideal sum with the new scalar operation error."""
    require(bool(terms), 'empty Sum2 term sequence')
    low = sum((term.lo for term in terms), F(0))
    high = sum((term.hi for term in terms), F(0))
    inherited = sum((term.e for term in terms), F(0))
    magnitude = sum((term.mag + term.e for term in terms), F(0))
    return B(low, high, sum2_error(magnitude, inherited, len(terms)))

class B:
    def __init__(self,lo,hi=None,error=F(0)):
        self.lo=down(F(lo));self.hi=self.lo if hi is None else up(F(hi));self.e=up(F(error))
    @property
    def mag(self):return max(abs(self.lo),abs(self.hi))
    @staticmethod
    def rounded(lo,hi,propagated):
        value=B(lo,hi)
        value.e=up(propagated+U*(value.mag+propagated)+TINY)
        return value
    def __add__(a,b):
        if not isinstance(b,B):b=B(b)
        return B.rounded(a.lo+b.lo,a.hi+b.hi,a.e+b.e)
    __radd__=__add__
    def __neg__(a):return B(-a.hi,-a.lo,a.e)
    def __sub__(a,b):return a+-b if isinstance(b,B) else a+B(-b)
    def __mul__(a,b):
        if not isinstance(b,B):b=B(b)
        values=[a.lo*b.lo,a.lo*b.hi,a.hi*b.lo,a.hi*b.hi]
        propagated=a.mag*b.e+b.mag*a.e+a.e*b.e
        return B.rounded(min(values),max(values),propagated)
    __rmul__=__mul__
    def divide(a,b):
        require(b.lo*b.hi>0, "division domain contains zero")
        m=min(abs(b.lo),abs(b.hi));require(b.e<m, "division error reaches zero")
        values=[a.lo/b.lo,a.lo/b.hi,a.hi/b.lo,a.hi/b.hi]
        propagated=a.e/(m-b.e)+a.mag*b.e/(m*(m-b.e))
        return B.rounded(min(values),max(values),propagated)
    def divide_constant(a,n):
        require(n>0, "nonpositive divisor")
        return B.rounded(a.lo/n,a.hi/n,a.e/n)

def poly(c,x):
    v=B(c[-1])
    for cc in reversed(c[:-1]):v=v*x+B(cc)
    return v

def sc(theta,quadrant=0):
    # All spiral phases lie in [0,.5+roundoff], so quadrant=0.
    # Include both subtractions from the split reduction, even though
    # their native zero operands usually make them exact.
    reduced=(theta-B(quadrant*b64("1.57079632673412561417")))-B(quadrant*b64("6.07710050650619224932e-11"))
    sq=reduced*reduced
    ss=reduced*poly(S,sq);cc=poly(C,sq)
    return [(ss,cc),(cc,-ss),(-ss,-cc),(-cc,ss)][quadrant%4]

def check(n):
    # Expand every upper endpoint by 1e-12, which covers rounded count
    # selection neighborhoods. Restrict actual road domain to s<=20.
    upper=min(F(20),F(max(0,n-1))+F(1,10**12))
    d=B(0,upper);step=d.divide_constant(n)
    x_terms=[];y_terms=[]
    max_phase=F(0); max_trig_error=F(0)
    for j in range(n):
        start=step*j
        for node,weight in zip(J,W):
            t=start+(step*F(1,2))*node
            theta=B(0)+t*(B(0)+(B(F(1,2))*B(r))*t)
            sn,cs=sc(theta)
            factor=(step*F(1,2))*weight
            x_terms.append(factor*cs);y_terms.append(factor*sn)
            max_phase=max(max_phase,theta.e)
            max_trig_error=max(max_trig_error,sn.e,cs.e)
    require(len(x_terms) == 5*n and len(y_terms) == 5*n, 'wrong Sum2 node count')
    x=sum2_terms(x_terms);y=sum2_terms(y_terms)
    x=B(BITS['spiral_x'])+x;y=B(BITS['spiral_y'])+y
    theta=B(0)+d*(B(0)+(B(F(1,2))*B(r))*d)
    sn,cs=sc(theta)
    # Actual lane offset arithmetic is exactly representable for these
    # three binary fractions: 3.5 + 1.5*.5 - .5 = 3.75.
    px=x+B(h)*sn;py=y-B(h)*cs
    # Include the cubic Horner operations with zero c,d coefficients.
    z=B(1)+d*(B(grade)+d*(B(0)+d*B(0)))
    # CARLA y reflection is exact. Query coordinates are exact integers.
    dx=px-B(10);dy=-py-B(105);dz=z-B(0)
    D=dx*dx+dy*dy+dz*dz
    return {'count':n,'s_upper':out(upper),'max_phase_error':out(max_phase),'max_trig_error':out(max_trig_error),'coordinate_errors':[out(t.e) for t in [px,py,z]],'D2_arithmetic_error':out(D.e)},[px.e,py.e,z.e],D.e

def arc_check():
    d=B(0,31);k=B(BITS['arc_k']);offset=B(F(7,4));radius=B(BITS['arc_radius'])
    turn=d*k;half=turn*F(1,2);phase=B(0)+half
    factor=((radius+offset)*k)*d
    sinc=poly(S,half*half);chord=factor*sinc
    hs,hc=sc(B(0));ps,pc=sc(phase)
    x=B(60)+offset*hs+chord*pc
    y=B(0)-offset*hc+chord*ps
    dx=x-B(70);dy=-y-B(10)
    D=dx*dx+dy*dy
    require(max(x.e,y.e)<F(1,10**12), "arc coordinate error exceeds bound")
    require(D.e<F(4,10**12), "arc distance error exceeds bound")
    return {'s_domain':'[0,31]','coordinate_errors':[out(x.e),out(y.e)],'D2_arithmetic_error':out(D.e),'certified_coordinate_bound':'1e-12','certified_D2_bound':'4e-12'}

def arc_endpoint():
    rows=[]
    for quadrant in [0,-1]:
        for use_division in [False,True]:
            d=B(31,b64('31.41592653589793'));k=B(BITS['arc_k']);offset=B(F(7,4));radius=B(BITS['arc_radius'])
            half=(d*k)*F(1,2);phase=B(0)+half
            sn,cs=sc(half,quadrant)
            sinc=sn.divide(half) if use_division else poly(S,half*half)
            chord=(((radius+offset)*k)*d)*sinc
            ps,pc=sc(phase,quadrant);hs,hc=sc(B(0))
            x=B(60)+offset*hs+chord*pc;y=-(B(0)-offset*hc+chord*ps)
            lower=F(0)
            for coordinate,query in [(x,70),(y,10)]:
                lo=coordinate.lo-query-coordinate.e;hi=coordinate.hi-query+coordinate.e
                lower+=min(lo*lo,hi*hi) if lo*hi>0 else 0
            require(lower>100, "arc endpoint exclusion failed")
            rows.append({'quadrant':quadrant,'sinc_division':use_division,'executed_D2_lower_bound':out(lower),'coordinate_error_bounds':[out(x.e),out(y.e)]})
    return rows

def main():
    rows=[];errors=[F(0)]*3;dist=F(0)
    for n in range(1,24):
        row,err,de=check(n);rows.append(row)
        errors=[max(a,b) for a,b in zip(errors,err)];dist=max(dist,de)
    require(max(errors)<F(1,10**12), "coordinate error exceeds bound")
    # Round a safe human-readable coordinate bound upward. This bound
    # applies to all counts; D² distance error below is independently
    # propagated through subtraction, squares, and additions above.
    require(dist<F(5,10**11), "distance error exceeds bound")
    report={'arc_endpoint_exclusion':arc_endpoint(),'arc_interior':arc_check(),'outward_rounding_grid':'2^-160','unit_roundoff':str(U),'additive_underflow_allowance_per_operation':str(TINY),'underflow_mode':'gradual only; FTZ/DAZ unsupported','spiral_accumulation':'materialized Sum2; E + (u + gamma_(n-1)^2) M','max_coordinate_errors':[out(x) for x in errors],'max_D2_arithmetic_error':out(dist),'certified_coordinate_bound':'1e-12','certified_D2_bound':'5e-11','loose_original_coordinate_bound':'1e-11','loose_original_D2_bound':'8.9000000000002e-9','notes':['Count neighborhoods are widened by 1e-12 in s. A reach/count argument bounds any count-boundary displacement by less than this width.','The maximum coordinate bound applies to each executed point, not only sampled points. All value intervals and error computations are rational.','The exact real distance of the rounded point has no larger error than the included separately rounded D² computation.'], 'counts':rows}
    import mpmath as mp
    report['rounded_minimizer_radius']={'shoulder':out(mp.sqrt(mp.mpf('4')*mp.mpf('5e-11')/mp.mpf('1.81329999999999'))),'arc':out(mp.sqrt(mp.mpf('4')*mp.mpf('4e-12')/mp.mpf('.912499999999998'))),'meaning':'Every exact global minimizer of the executed rounded-point distance lies in this radius around the smooth stored-expression minimum. This is an enclosure, not a claim of a unique rounded minimizer. The representable-s comparison slack is below 1e-25 and is absorbed by the strict outward margins.'}
    (HERE/'rounding-results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='counts'},indent=2))
if __name__=='__main__':main()
