#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Independent lane-center differentiation for changed ordinary poses.

Use exact analytic derivatives of the center interpolation expression.
Reconstruct only the two small parabola chord tables; do not run Mojo.
"""
import json,math
import mpmath as mp
from oracle import HERE, S,C,array,trig,b64,mf,out,shoulder,add,evaluate,derivative,r,a
mp.mp.dps=80
AT=array(trig,'_ATAN_COEFFICIENTS')
PI=mf(b64('3.141592653589793'));HP=mf(b64('1.5707963267948966'));QP=mf(b64('0.7853981633974483'));INV=mf(b64('0.6366197723675814'))
HI=mf(b64('1.57079632673412561417'));LO=mf(b64('6.07710050650619224932e-11'))

def horner(c,x):
    v=mp.mpf(0)
    for t in reversed(c):v=v*x+mf(t)
    return v

def sc(x):
    q=int(mp.floor(x*INV+mp.mpf('.5')));z=x-q*HI-q*LO
    s=z*horner(S,z*z);c=horner(C,z*z)
    return [(s,c),(c,-s),(-s,-c),(-c,s)][q%4]

def at(x):
    sign=-1 if x<0 else 1;x=abs(x);inv=x>1
    if inv:x=1/x
    shifted=x>mf(b64('.41421356237309503'))
    if shifted:x=(x-1)/(x+1)
    v=x*horner(AT,x*x)
    if shifted:v=QP+v
    if inv:v=HP-v
    return sign*v

def angles(dx,dy,dz,reverse=False):
    horizontal=mp.sqrt(dx*dx+dy*dy)
    yaw=-mp.atan2(dy,dx)*180/mp.pi
    pitch=-mp.atan2(dz,horizontal)*180/mp.pi
    if reverse:yaw+=180;pitch=360-pitch
    return {'dx_ODR':out(dx),'dy_ODR':out(dy),'dz':out(dz),'horizontal_speed':out(horizontal),'yaw_degrees':out(yaw),'pitch_degrees':out(pitch)}

results={}
# Straight varying lane width gives the exact tangent (1,-.025,0).
results['road1_section1_lane-1_s50']=angles(mp.mpf(1),-mf(b64('.025')),mp.mpf(0))
# Spiral lane -1 at s=10. Replace shoulder offset3.75 with1.25.
p=shoulder(12);s=mp.mpf(10)
def spiral_center(q):
    sn,cs=sc(mf(a)*q*q)
    return evaluate(p[0],q)-mp.mpf('2.5')*sn,evaluate(p[1],q)+mp.mpf('2.5')*cs
results['road5_lane-1_s10']=angles(mp.diff(lambda q:spiral_center(q)[0],s),mp.diff(lambda q:spiral_center(q)[1],s),mf(b64('.02')))
# Every sample stores a point on v=.02u². s is accumulated chord length.
# u step is .5 in both geometries, with actual binary64 p construction.
def table(length,normalized):
    count=max(int(length/.5),5);dp=1.0/count
    if not normalized:dp*=length
    p=0.;last=(0.,0.,0.,10. if normalized else 1.,0.);samples=[last]
    for _ in range(count):
        p+=dp
        u=p*(10. if normalized else 1.)
        v=p*(p*(2. if normalized else .02))
        tu=10. if normalized else 1.;tv=p*(2*(2. if normalized else .02))
        ds=math.sqrt((u-last[0])**2+(v-last[1])**2)
        last=(u,v,last[2]+ds,tu,tv);samples.append(last)
        if last[2]>length:break
    return [[mf(b64(x)) for x in row] for row in samples]

for s,base,heading,origin,normalized,reverse in [(40,35,'.6',(35,112),False,True),(50,47,'.7',(46,118),True,False)]:
    t=table(10 if normalized else 12,normalized);distance=mp.mpf(s-base)
    j=next(j for j in range(len(t)-1) if t[j+1][2]>=distance)
    v0,v1=t[j],t[j+1]
    def center(q):
        d=q-base;mix=(v1[2]-d)/(v1[2]-v0[2])
        u=mix*v0[0]+(1-mix)*v1[0];v=mix*v0[1]+(1-mix)*v1[1]
        tu=mix*v0[3]+(1-mix)*v1[3];tv=mix*v0[4]+(1-mix)*v1[4]
        theta=mf(b64(heading))+at(tv/tu)
        sn,cs=sc(mf(b64(heading)));st,ct=sc(theta)
        if normalized:offset=mp.mpf('3.75')-mf(b64('.01'))*(q-20)
        else:offset=-(mp.mpf('3.25')+mf(b64('.01'))*q)/2-(mp.mpf('.5')+mf(b64('.01'))*(q-20))
        return origin[0]+u*cs-v*sn+offset*st,origin[1]+u*sn+v*cs-offset*ct
    dx=mp.diff(lambda q:center(q)[0],mp.mpf(s));dy=mp.diff(lambda q:center(q)[1],mp.mpf(s))
    result=angles(dx,dy,mf(b64('.002'))*(s-30),reverse)
    result['active_sample_index']=j;result['active_sample_s']=[out(v0[2]),out(v1[2])];result['center_CARLA']=[out(center(mp.mpf(s))[0]),out(-center(mp.mpf(s))[1])]
    results[f'road5_lane{1 if reverse else -2}_s{s}']=result
results['road5_lane0_s0']=angles(mp.mpf(1),mp.mpf(0),mf(b64('.02')))
(HERE/'pose-results.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
