"""Independent exact projection/clipped-interval oracle from retained F32 bits.

Uses stdlib Fraction, not the production polynomial expansion. It verifies the
retained native fixture words and expected values, then checks a Float64 model
of the adaptive guards. It does not replace native compilation or tests.
"""
from fractions import Fraction as F
from pathlib import Path
import argparse,json,random,re,struct
ROOT=Path(__file__).resolve().parents[1]

def bits(x): return struct.unpack('<I',struct.pack('<f',x))[0]
def val(x): return struct.unpack('<f',struct.pack('<I',x))[0]
def vec(x): return tuple(F.from_float(val(v)) for v in x)
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def distance(raw):
    a,b,p=(vec(raw[i:i+3]) for i in (0,3,6))
    d,u=sub(b,a),sub(p,a)
    dd=dot(d,d)
    if not dd: return dot(u,u)
    t=max(F(0),min(F(1),dot(u,d)/dd))
    residual=tuple(x-t*y for x,y in zip(u,d))
    return dot(residual,residual)
def slab(raw):
    a,b,lo,hi=(vec(raw[i:i+3]) for i in (0,3,6,9))
    near,far=F(0),F(1)
    for x,y,l,h in zip(a,b,lo,hi):
        if l>h: return False
        if x==y:
            if x<l or x>h: return False
        else:
            t1,t2=sorted(((l-x)/(y-x),(h-x)/(y-x)))
            near,far=max(near,t1),min(far,t2)
            if near>far:return False
    return True

def norm(v): return v[0]*v[0]+v[1]*v[1]+v[2]*v[2]
paths={}
def model(raw):
    a,b,p=(tuple(val(v) for v in raw[i:i+3]) for i in (0,3,6))
    if b<a:a,b=b,a
    ab,ap,bp=sub(b,a),sub(p,a),sub(p,b)
    da=sum(x*y for x,y in zip(ap,ab)); db=sum(x*y for x,y in zip(bp,ab))
    ga=2**-49*sum(abs(x*y) for x,y in zip(ap,ab));gb=2**-49*sum(abs(x*y) for x,y in zip(bp,ab))
    if norm(ab)==0:r,path=norm(ap),'point'
    elif da < -ga:r,path=norm(ap),'start'
    elif db > gb:r,path=norm(bp),'end'
    else:
        cross=[];scale=[]
        for i in range(3):
            j,k=(i+1)%3,(i+2)%3
            l,r=ap[j]*ab[k],ap[k]*ab[j]
            cross.append(l-r);scale.append(abs(l)+abs(r))
        if da>ga and db < -gb and norm(cross)>=2**-12*norm(scale):r,path=norm(cross)/norm(ab),'interior'
        else:
            # Model the candidate's exact-sign polynomials, not the oracle's
            # clamped-projection distance formula.
            af,bf,pf=tuple(map(F.from_float,a)),tuple(map(F.from_float,b)),tuple(map(F.from_float,p))
            df,uf,vf=sub(bf,af),sub(pf,af),sub(pf,bf)
            if dot(uf,df)<=0:r=norm(ap)
            elif dot(vf,df)>=0:r=norm(bp)
            else:
                c=[float(uf[(i+1)%3]*df[(i+2)%3]-uf[(i+2)%3]*df[(i+1)%3]) for i in range(3)]
                r=norm(c)/float(dot(df,df))
            path='exact'
    gap=tuple(max(min(x,y)-z,z-max(x,y),0) for x,y,z in zip(a,b,p))
    r=max(r,norm(gap))
    paths[path]=paths.get(path,0)+1
    return r

def raw(*vs):return tuple(bits(x) for v in vs for x in v)
D=[];S=[]
def add_d(name,*vs):D.append((name,raw(*vs)))
def add_s(name,*vs):S.append((name,raw(*vs)))
M=val(0x7f7fffff);tiny=val(1);L=val(bits(1e38))
add_d('exterior_gap',(-L,0,0),(-1,0,0),(0,0,0))
add_d('interior_near_end',(-L,0,0),(-1,0,0),(-2,1,0))
add_d('interior_slanted_near_end',(-L,-L,0),(-1,-2,0),(-2,-2,0))
add_d('interior_slanted_gap',(-L,-L,0),(-1,-2,0),(-3,-2,0))
add_d('extreme_midpoint',(-M,0,0),(M,1,0),(0,0,0))
add_d('minimum_segment',(0,0,0),(tiny,0,0),(tiny,tiny,0))
add_d('minimum_gap',(-M,0,0),(-tiny,0,0),(0,0,0))
add_d('mixed_3d',(-M,-M,-M),(-tiny,1,2),(tiny,0,0))
for name,a,b,p in [
 ('start_boundary',(0,0,0),(1,0,0),(0,1,0)),
 ('end_boundary',(0,0,0),(1,0,0),(1,1,0)),
 ('point',(1,2,3),(1,2,3),(4,6,3)),
 ('zero_point',(0,0,0),(0,0,0),(0,0,0)),
 ('collinear',(0,0,0),(2,2,2),(1,1,1)),
 ('y_order',(0,1,0),(0,-1,0),(1,0,0)),
 ('z_order',(0,0,1),(0,0,-1),(1,0,0)),
 ('end_exterior',(0,0,0),(1,0,0),(2,1,0)),
 ('start_exterior',(0,0,0),(1,0,0),(-2,1,0)),
 ('interior_axis',(0,0,0),(2,0,0),(1,1,0)),
]:add_d(name,a,b,p)
rng=random.Random(589)
# Input words span every finite exponent. Cancellation controls share anchors.
for i in range(150):
    r=tuple((rng.randrange(2)<<31)|(rng.randrange(255)<<23)|rng.randrange(1<<23) for _ in range(9))
    D.append((f'mixed_{i}',r))
for exp in [-140,-100,-30,0,30,70,120]:
    scale=2.**exp
    for i in range(6):
        vs=[tuple(rng.randrange(-8,9)*scale for _ in range(3)) for __ in range(3)]
        add_d(f'scaled_{exp}_{i}',*vs)
for exp in [30,60,100,127]:
    m=2.**exp
    for gap in [tiny,2**-70,1,2**20]:
        add_d(f'endpoint_{exp}_{bits(gap)}',(-m,-m,0),(-gap,-2*gap,0),(-2*gap,-2*gap,gap))
for y0,y1,name in [(0,.25,'overflow_miss'),(.5,.75,'overflow_hit')]:
    add_s(name,(-M,0,0),(M,1,0),(-1,y0,-1),(1,y1,1))
add_s('lost_separate_slabs',(-2**60,-2**60,0),(2**60,2**60,0),(0,2,-1),(1,3,1))
add_s('lost_touching_slabs',(-2**60,-2**60,0),(2**60,2**60,0),(0,1,-1),(1,3,1))
add_s('minimum_touch',(0,0,0),(tiny,tiny,0),(tiny,tiny,0),(tiny,tiny,0))
add_s('minimum_miss',(0,0,0),(tiny,tiny,0),(0,tiny,0),(0,tiny,0))
add_s('tiny_endpoint_gap',(-M,0,0),(-tiny,0,0),(0,-1,-1),(1,1,1))
for i in range(150):
    words=[(rng.randrange(2)<<31)|(rng.randrange(255)<<23)|rng.randrange(1<<23) for _ in range(12)]
    lo=[min(val(words[6+j]),val(words[9+j])) for j in range(3)]
    hi=[max(val(words[6+j]),val(words[9+j])) for j in range(3)]
    S.append((f'mixed_slab_{i}',tuple(words[:6])+tuple(map(bits,lo+hi))))
maxerr=0
for name,r in D:
    ex=float(distance(r));got=model(r);rev=model(r[3:6]+r[:3]+r[6:])
    err=abs(got-ex)/ex if ex else abs(got)
    assert err<=1e-12,(name,got,ex,err)
    assert got==rev,(name,got,rev)
    maxerr=max(maxerr,err)

slab_paths = {"fast": 0, "exact": 0}
def parameter_before(a,b):
    left=(a[0]-a[1])*(b[2]-b[1])
    right=(b[0]-b[1])*(a[2]-a[1])
    difference=left-right
    if abs(difference)>2**-49*(abs(left)+abs(right)):
        slab_paths["fast"]+=1
        return difference<0
    slab_paths["exact"]+=1
    a,b=tuple(map(F.from_float,a)),tuple(map(F.from_float,b))
    return (a[0]-a[1])*(b[2]-b[1])<(b[0]-b[1])*(a[2]-a[1])
def slab_model(raw):
    a,b,lo,hi=(tuple(val(v) for v in raw[i:i+3]) for i in (0,3,6,9))
    near,far=(0.,0.,1.),(1.,0.,1.)
    for x,y,l,h in zip(a,b,lo,hi):
        first,last=min(x,y),max(x,y)
        if last<l or first>h:return False
        if first>=l and last<=h:continue
        low,high=(0.,0.,1.),(1.,0.,1.)
        if x<y:
            if l>x:low=(l,x,y)
            if h<y:high=(h,x,y)
        else:
            if h<x:low=(-h,-x,-y)
            if l>y:high=(-l,-x,-y)
        if parameter_before(near,low):near=low
        if parameter_before(high,far):far=high
        if parameter_before(far,near):return False
    return True
for name,r in S:
    expected=slab(r)
    assert slab_model(r)==expected,name
    assert slab_model(r[3:6]+r[:3]+r[6:])==expected,name
text=(ROOT/"tests/test_carla_rtree_numerics.mojo").read_text()
distance_rows=re.findall(r"_distance_case\(\s*\[([0-9,\s]+)\],\s*Float64\(([^)]+)\),?\s*\)",text)
slab_rows=re.findall(r"_slab_case\(\s*\[([0-9,\s]+)\],\s*(True|False),?\s*\)",text)
assert len(distance_rows)==len(D),(len(distance_rows),len(D))
assert len(slab_rows)==len(S),(len(slab_rows),len(S))
for (name,expected_bits),(words,expectation) in zip(D,distance_rows):
    retained=tuple(int(w) for w in words.split(',') if w.strip())
    assert retained==expected_bits,name
    assert float(expectation)==float(distance(retained)),name
for (name,expected_bits),(words,expectation) in zip(S,slab_rows):
    retained=tuple(int(w) for w in words.split(',') if w.strip())
    assert retained==expected_bits,name
    assert (expectation=="True")==slab(retained),name
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--stress",type=int,default=0,help="Additional seeded mixed-exponent cases for each kernel")
args=parser.parse_args()
assert args.stress>=0
stress_max_error=0.
for i in range(args.stress):
    r=tuple((rng.randrange(2)<<31)|(rng.randrange(255)<<23)|rng.randrange(1<<23) for _ in range(9))
    expected=float(distance(r));got=model(r)
    reverse=model(r[3:6]+r[:3]+r[6:])
    error=abs(got-expected)/expected if expected else abs(got)
    assert error<=1e-12,(i,r,got,expected,error)
    assert got==reverse,(i,r,got,reverse)
    stress_max_error=max(stress_max_error,error)
    words=tuple((rng.randrange(2)<<31)|(rng.randrange(255)<<23)|rng.randrange(1<<23) for _ in range(12))
    lo=tuple(bits(min(val(words[6+j]),val(words[9+j]))) for j in range(3))
    hi=tuple(bits(max(val(words[6+j]),val(words[9+j]))) for j in range(3))
    r=words[:6]+lo+hi
    assert slab_model(r)==slab(r),(i,r)
    assert slab_model(r[3:6]+r[:3]+r[6:])==slab(r),(i,r)
print(json.dumps({
    "oracle":"stdlib Fraction exact projection and interval clipping",
    "distance_cases":len(D),"slab_cases":len(S),
    "native_fixture_words_and_expectations_verified":True,
    "float64_model_max_relative_error":maxerr,
    "distance_model_paths":paths,"slab_model_paths":slab_paths,
    "stress_cases_per_kernel":args.stress,"stress_max_relative_error":stress_max_error,
    "scope":"Model and fixture checks; native gates remain separate",
},indent=2))
