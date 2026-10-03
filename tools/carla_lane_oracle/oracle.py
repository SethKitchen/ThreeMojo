#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Independent stored-coefficient town oracle. No Mojo execution; reports go to the requested output directory.

All polynomial coefficient algebra and Gauss moments use Fraction. Constant
intermediates use the native-exported bits, including rounded 1+GL_node. mpmath is
used only for high precision displays and isolated root refinement. Bounds
with rational endpoints are checked with exact arithmetic. This certifies a
smooth stored-expression model plus separately stated Float64 error bounds,
not an exact argmin of the Float64 staircase.
"""
from fractions import Fraction as F
from pathlib import Path
import math, re, json, hashlib, os
import mpmath as mp
mp.mp.dps = 90
PACKAGE=Path(__file__).resolve().parent
SOURCE=PACKAGE.parents[1]
HERE=Path(os.environ.get('CARLA_LANE_ORACLE_OUTPUT', str(SOURCE/'out/carla-lane-oracle')))
HERE.mkdir(parents=True, exist_ok=True)
# These proofs are for a reviewed operation graph, not arbitrary later source.
SUPPORTED=json.loads((PACKAGE/'supported-source.json').read_text())
for name, expected in SUPPORTED['source_sha256'].items():
    data=(SOURCE/name).read_bytes()
    if name.endswith('/road.mojo'):
        data=data[data.index(b'from extensions.carla.geometry import ('):]
    assert hashlib.sha256(data).hexdigest()==expected, ('Review oracle graph after source change', name)

def b64(x): return F(float(x))
def mf(x):
    if isinstance(x,F): return mp.mpf(x.numerator)/x.denominator
    return mp.mpf(x)
def out(x): return mp.nstr(mf(x),45)
def array(file,name):
    text=file.read_text()
    values=re.search(r'comptime '+name+r':[^=]*=\s*\[(.*?)\]',text,re.S).group(1)
    return [b64(x.strip()) for x in values.split(',') if x.strip()]
trig=SOURCE/'extensions/carla/curve_trig.mojo'
geom=SOURCE/'extensions/carla/geometry.mojo'
S=array(trig,'_SIN_COEFFICIENTS'); C=array(trig,'_COS_COEFFICIENTS')
N=array(geom,'_GL_NODES'); W=array(geom,'_GL_WEIGHTS')
BIT_FILE=PACKAGE/'constants.json'
RECORDED=json.loads(BIT_FILE.read_text())
BITS={name:F(value['exact_rational']) for name,value in RECORDED.items()}
assert all(float(BITS[name]).hex()==value['hex'] for name,value in RECORDED.items())
assert N==[BITS[f'node_{i}'] for i in range(5)]
assert W==[BITS[f'weight_{i}'] for i in range(5)]
J=[BITS[f'one_plus_node_{i}'] for i in range(5)]
assert J==[b64(1+float(v)) for v in N]
r=BITS['spiral_rate']; a=r/2
h=BITS['lane_width_-1']+BITS['lane_width_-2']/2-BITS['lane_offset']
grade=BITS['elevation_b']

def add(*ps):
    o=[F(0)]*max(map(len,ps))
    for p in ps:
        for i,c in enumerate(p):o[i]+=c
    return o

def mul(p,q):
    o=[F(0)]*(len(p)+len(q)-1)
    for i,c in enumerate(p):
        for j,d in enumerate(q):o[i+j]+=c*d
    return o

def derivative(p,n=1):
    for _ in range(n):p=[i*p[i] for i in range(1,len(p))]
    return p

def evaluate(p,x):
    v=mp.mpf(0)
    for c in reversed(p):v=v*x+mf(c)
    return v

def rational_evaluate(p,x):
    v=F(0)
    for c in reversed(p):v=v*x+c
    return v

def absbound(p,x,order=0):
    return sum(abs(c)*x**i for i,c in enumerate(derivative(p,order)))

def moment(n,k):
    return sum(w*((F(j)+node/2)/n)**k for j in range(n) for node,w in zip(J,W))/(2*n)

def shoulder(n):
    x=[F(0)]*44;y=[F(0)]*44
    y[0]=100
    for j in range(11):
        x[4*j+1]+=C[j]*a**(2*j)*moment(n,4*j)
        y[4*j+3]+=S[j]*a**(2*j+1)*moment(n,4*j+2)
        x[4*j+2]+=h*S[j]*a**(2*j+1)
        y[4*j]-=h*C[j]*a**(2*j)
    return x,y,[F(1),grade]

def exact_taylor_shoulder():
    x=[F(0)]*44;y=[F(0)]*44;y[0]=100
    for j in range(11):
        c=F((-1)**j,math.factorial(2*j));ss=F((-1)**j,math.factorial(2*j+1))
        x[4*j+1]+=c*a**(2*j)/(4*j+1)
        y[4*j+3]+=ss*a**(2*j+1)/(4*j+3)
        x[4*j+2]+=h*ss*a**(2*j+1)
        y[4*j]-=h*c*a**(2*j)
    return x,y,[F(1),grade]

def distance(p,query):
    return add(*(mul(add(v,[-q]),add(v,[-q])) for v,q in zip(p,query)))

def tail_shoulder(s,order):
    # Absolute infinite Taylor tail bound. For j>=11 and s<=20 the ratio
    # of consecutive terms, including derivatives <=2, is below 1/100.
    # Multiply the first omitted term by 100/99 (conservative geometric sum).
    result=[]
    for axis in range(2):
        terms=[]
        j=11
        if axis==0:
            terms=[(4*j+1,a**(2*j)/F(math.factorial(2*j)*(4*j+1))),
                   (4*j+2,h*a**(2*j+1)/math.factorial(2*j+1))]
        else:
            terms=[(4*j+3,a**(2*j+1)/F(math.factorial(2*j+1)*(4*j+3))),
                   (4*j,h*a**(2*j)/math.factorial(2*j))]
        z=F(0)
        for exponent,coef in terms:
            z+=coef*math.prod(range(exponent-order+1,exponent+1))*s**(exponent-order)
        result.append(z*F(100,99))
    return result

def boundary(m):return 2*mp.mpf(m)/(1+mp.sqrt(1+4*mf(r)*m))

def exactcurve(s):
    t=mf(a)*s*s
    return (mp.quad(lambda u:mp.cos(mf(a)*u*u),[0,s])+mf(h)*mp.sin(t),
            100+mp.quad(lambda u:mp.sin(mf(a)*u*u),[0,s])-mf(h)*mp.cos(t),
            1+mf(grade)*s)

def main():
    baseline=exact_taylor_shoulder()
    rows=[]; error=[[F(0),F(0)] for _ in range(3)]
    minimum=None
    for n in range(1,24):
        p=shoulder(n); D=distance(p,[10,-105,0]); g=derivative(D)
        lower=mp.mpf(0) if n<=2 else boundary(n-2)
        upper=min(mp.mpf(20),boundary(n-1)) if n>1 else mp.mpf(0)
        if n==23: lower=min(lower,mp.mpf(20))
        # Exact rational upper endpoint (loose) sufficient for all error bounds.
        endpoint=F(min(20,n-1))
        eb=[]
        for order in range(3):
            tails=tail_shoulder(endpoint,order)
            e=[absbound(add(p[axis],[-c for c in baseline[axis]]),endpoint,order)+tails[axis] for axis in range(2)]
            for axis in range(2): error[order][axis]=max(error[order][axis],e[axis])
            eb.append([out(v) for v in e])
        gl=evaluate(g,lower); gu=evaluate(g,upper)
        row={'count':n,'s_low':out(lower),'s_high':out(upper),'Dprime_low':out(gl),'Dprime_high':out(gu),'D2_low':out(evaluate(D,lower)),'D2_high':out(evaluate(D,upper)),'position_derivative_error_bounds':eb}
        if gl<0<gu:
            root=mp.findroot(lambda s:evaluate(g,s),(lower,upper))
            row['stationary_s']=out(root); row['D2_stationary']=out(evaluate(D,root));row['D2second_stationary']=out(evaluate(derivative(g),root))
            minimum=(n,root,D,p)
        rows.append(row)
    assert minimum is not None and minimum[0]==6
    n,root,D,p=minimum
    assert all(row['count'] in [1,6] or mf(row['Dprime_low'])*mf(row['Dprime_high'])>0 for row in rows)
    # For the true clothoid on 0..20: P'=v*T, v=1+h*r*s,
    # D''/2=h*r*A+v*v+v*r*s*B+grade^2; A>=-10, B>0.
    # Thus D'' >= 2*(1-10*h*r+grade^2)>1.813.
    true_convex=2*(1-10*h*r+grade*grade)
    # Each ODR residual coordinate magnitude <220, each true first derivative
    # magnitude <2, each true second derivative magnitude <1 (loose bounds).
    # D''=2 sum(P'^2+(P-Q)P''); apply these coordinate-wise.
    second_error=2*sum(4*error[1][i]+error[1][i]**2+220*error[2][i]+error[0][i]*(1+error[2][i]) for i in range(2))
    assert true_convex-second_error>F(1813,1000)
    min_boundary=min(mf(row[k]) for row in rows for k in ['D2_low','D2_high'])
    # A simple all-operations Float64 forward bound is documented separately.
    pos_round=F(1,10**11) # 1e-11 coordinate bound; large safety margin.
    D_round=4*220*pos_round+2*pos_round**2+F(1,10**10)
    radius=mp.sqrt(4*mf(D_round)/mf(true_convex-second_error))
    report={'source_sha256':{str(f.relative_to(SOURCE)):hashlib.sha256(f.read_bytes()).hexdigest() for f in [trig,geom,SOURCE/'assets/carla/town.xodr']},'recorded_constants_sha256':hashlib.sha256(BIT_FILE.read_bytes()).hexdigest(),'model':'Exact real operations over actual binary64 stored coefficients, with derived constant rate=Float64(stored(0.05)/20) and ARC radius=Float64(1/stored(-0.05)) frozen at their executed binary64 values. Every arithmetic operation in the executed Float64 model is covered separately. Polynomial moments use exact Fraction and frozen exported Float64(1+node), nodes, and weights. Count join candidates include both adjacent models.','shoulder':{'stationary_s':out(root),'retained_native_s':'4.5865310585259165','retained_native_minus_model':out(mp.mpf('4.5865310585259165')-root),'D2':out(evaluate(D,root)),'center_ODR':[out(evaluate(v,root)) for v in p],'D2second':out(evaluate(derivative(D,2),root)),'global_position_error_bounds_vs_clothoid':[[out(v) for v in row] for row in error],'true_clothoid_D2second_lower':out(true_convex),'D2second_perturbation_bound':out(second_error),'stored_piece_D2second_lower':out(true_convex-second_error),'nearest_count_boundary_D2_gap':out(min_boundary-evaluate(D,root)),'other_record_D2_lower':'42539.0625','other_record_gap':out(mf(F(680625,16))-evaluate(D,root)),'all_float64_coordinate_rounding_bound':out(pos_round),'all_float64_D2_rounding_bound':out(D_round),'conservative_global_rounded_argmin_radius':out(radius),'counts':rows}}
    # Arc ideal half-angle polynomial. No quadrant change occurs in the
    # stationary basin. Tiny endpoint branch alternatives use uniform trig
    # approximation bounds, not an assumed exact polynomial identity.
    k=-b64('.05'); h_arc=F(7,4); beta=k/2; stored_radius=b64(1/float(k)); factor=(stored_radius+h_arc)*k
    sinc=[F(0)]*21; cos=[F(0)]*21;sin=[F(0)]*22
    for j in range(11):
        sinc[2*j]=S[j]*beta**(2*j)
        cos[2*j]=C[j]*beta**(2*j)
        sin[2*j+1]=S[j]*beta**(2*j+1)
    chord=[F(0)]+[factor*c for c in sinc]
    xp=add([60],mul(chord,cos));yp=add([h_arc],[-v for v in mul(chord,sin)])
    arcD=distance([xp,yp,[F(0)]],[70,10,0]);arcg=derivative(arcD)
    aroot=mp.findroot(lambda s:evaluate(arcg,s),(15,16));circle=mp.pi/(4*mf(-k))
    R=-stored_radius-h_arc
    arc_exact_D=(mf(R)-mp.sqrt(200))**2
    arc_base_x=[F(0)]*43;arc_base_y=[F(0)]*43
    arc_base_x[0]=60;arc_base_y[0]=h_arc
    for j in range(21): arc_base_x[2*j+1]=R*F((-1)**j,math.factorial(2*j+1))*(-k)**(2*j+1)
    for j in range(1,22): arc_base_y[2*j]=R*F((-1)**(j+1),math.factorial(2*j))*(-k)**(2*j)
    arc_errors=[]
    for order in range(3):
        e=[]
        for axis,(model,base,exponent) in enumerate([(xp,arc_base_x,43),(yp,arc_base_y,44)]):
            tail=R*(-k)**exponent/F(math.factorial(exponent))*math.prod(range(exponent-order+1,exponent+1))*F(32)**(exponent-order)*F(100,99)
            e.append(absbound(add(model,[-c for c in base]),F(32),order)+tail)
        arc_errors.append(e)
    arc_second_error=2*sum(2*arc_errors[1][i]+arc_errors[1][i]**2+40*arc_errors[2][i]+arc_errors[0][i]*(1+arc_errors[2][i]) for i in range(2))
    assert 20*R*k*k-arc_second_error>F(912,1000)
    report['arc']={'global_derivative_error_bounds_vs_circle':[[out(v) for v in row] for row in arc_errors],'D2second_perturbation_bound':out(arc_second_error),'stored_polynomial_D2second_lower':out(20*R*k*k-arc_second_error),'stored_halfangle_stationary_s':out(aroot),'exact_circle_s':out(circle),'model_minus_circle':out(aroot-circle),'retained_native_s':'15.707963306006883','retained_native_minus_model':out(mp.mpf('15.707963306006883')-aroot),'D2':out(evaluate(arcD,aroot)),'circle_D2':out(arc_exact_D),'D2second':out(evaluate(derivative(arcD,2),aroot)),'true_circle_D2second_lower':out(20*R*k*k),'other_driving_lanes_D2_lower':'68.0625','old_s':'15.603252062536761','old_minus_minimum_D2':out(evaluate(arcD,mp.mpf('15.603252062536761'))-evaluate(arcD,aroot))}
    report['yaw_road1_s50']={'center_slope':'.025','correct_degrees':out(mp.atan(mf(b64('.025')))*180/mp.pi),'old_degrees':'1.4323944878270582','old_is_slope_times_180_over_pi':out(mf(b64('.025'))*180/mp.pi),'explanation':'The old value treats dy/ds as a radian angle. The center tangent angle is atan(dy/dx).'}
    rational_checks={}
    for label,poly,stationary in [('shoulder',derivative(D),root),('arc',arcg,aroot)]:
        denom=10**40
        lo=F(int(mp.floor(stationary*denom)),denom);hi=lo+F(1,denom)
        f_lo=rational_evaluate(poly,lo);f_hi=rational_evaluate(poly,hi)
        assert f_lo<0<f_hi
        rational_checks[label]={'root_bracket':[str(lo.numerator)+'/'+str(lo.denominator),str(hi.numerator)+'/'+str(hi.denominator)],'derivative_signs':['negative','positive'],'root_bracket_decimal':[out(lo),out(hi)]}
    report['exact_rational_root_brackets']=rational_checks
    # Exact rational enclosures establish endpoint signs, rather than
    # trusting rounded high precision displays at irrational count boundaries.
    def b_interval(m):
        if m==0:return (F(0),F(0))
        scale=10**40;v=boundary(m);lo=F(int(mp.floor(v*scale)),scale);hi=lo+F(1,scale)
        assert lo+r*lo*lo<=m<=hi+r*hi*hi
        return (lo,hi)
    def interval_eval(poly,domain):
        lo=hi=F(0);xlo,xhi=domain
        for coef in reversed(poly):
            products=[lo*xlo,lo*xhi,hi*xlo,hi*xhi]
            lo=min(products)+coef;hi=max(products)+coef
        return lo,hi
    proved=[];boundary_lower=None
    for count in range(1,24):
        poly=distance(shoulder(count),[10,-105,0]);grad=derivative(poly)
        low=b_interval(max(0,count-2))
        upper=b_interval(count-1) if count-1<20+r*400 else (F(20),F(20))
        for which,domain in [('low',low),('high',upper)]:
            sign=interval_eval(grad,domain)
            expected=-1 if (count<6 or (count==6 and which=='low')) else 1
            assert sign[1]<0 if expected<0 else sign[0]>0
            cost=interval_eval(poly,domain)
            boundary_lower=cost[0] if boundary_lower is None else min(boundary_lower,cost[0])
            proved.append({'count':count,'endpoint':which,'derivative_sign':expected,'D2_interval':[out(v) for v in cost]})
    root_interval=tuple(F(v) for v in rational_checks['shoulder']['root_bracket'])
    min_cost_interval=interval_eval(D,root_interval)
    gap=boundary_lower-min_cost_interval[1]
    assert gap>F(443,1000)
    report['exact_rational_endpoint_checks']={'all_46_signs_verified':True,'boundary_cost_gap_lower':out(gap),'details':proved}
    (HERE/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='source_sha256' and k!='model' and k!='shoulder'},indent=2))
    print(json.dumps({k:v for k,v in report['shoulder'].items() if k!='counts'},indent=2))

if __name__=='__main__':main()
