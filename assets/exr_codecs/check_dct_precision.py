# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compare official DCT helpers, not Mojo, on deterministic half coefficients.

Usage: python3 check_dct_precision.py HELPER_SO OPENEXR_SOURCE OUTPUT_JSON
Requires an x86-64 CPU with AVX, and the pinned OpenEXR 3.1.5 helper build.
This experiment does not set or adjust the Mojo fixture tolerance.
"""
from pathlib import Path
import sys
import ctypes, struct, re, random, json, math
helper, source, output = sys.argv[1:]
lib=ctypes.CDLL(str(Path(helper).resolve()))
f=lib.compare_dct;f.argtypes=[ctypes.POINTER(ctypes.c_float)]*4
C=ctypes.c_float*64
a=C();b=C();c=C();d=C()
hbits=lambda v:struct.unpack('<H',struct.pack('<e',v))[0]
hval=lambda v:struct.unpack('<e',struct.pack('<H',v))[0]
s=(Path(source)/'src/lib/OpenEXR/dwaLookups.h').read_text().split('dwaCompressorToLinear[] =')[1].split('}')[0]
lut=[int(x,16) for x in re.findall(r'0x([0-9a-f]+)',s)]
rng=random.Random(615)
results={n:{'max_float_scaled':0.,'max_final_scaled':0.,'changed_input_halves':0,'max_input_half_steps':0,'max_final_half_steps':0,'over_0003':0} for n in ['sse2','avx']}
first={}
def ordered(h):return 0x8000-(h&0x7fff) if h&0x8000 else 0x8000+h
for trial in range(20000):
    bits=[hbits(rng.uniform(-2,2)) for _ in range(64)]
    for i,h in enumerate(bits):a[i]=hval(h)
    f(a,b,c,d)
    for name,other in [('sse2',c),('avx',d)]:
        out=results[name]
        for i in range(64):
            x,y=b[i],other[i]
            out['max_float_scaled']=max(out['max_float_scaled'],abs(x-y)/max(1,abs(y)))
            hx,hy=hbits(x),hbits(y)
            if hx==hy:continue
            out['changed_input_halves']+=1
            out['max_input_half_steps']=max(out['max_input_half_steps'],abs(ordered(hx)-ordered(hy)))
            tx,ty=lut[hx],lut[hy];vx,vy=hval(tx),hval(ty)
            if not(math.isfinite(vx) and math.isfinite(vy)):continue
            err=abs(vx-vy)/max(1,abs(vy))
            out['max_final_scaled']=max(out['max_final_scaled'],err)
            out['max_final_half_steps']=max(out['max_final_half_steps'],abs(ordered(tx)-ordered(ty)))
            if err>0.003:
                out['over_0003']+=1
                if name not in first:
                    first[name]={'trial':trial,'position':i,'input_half_bits':bits,'scalar_prehalf':x,'simd_prehalf':y,'scalar_half':hx,'simd_half':hy,'scalar_final':vx,'simd_final':vy,'scaled_error':err}
report={'blocks':20000,'seed':615,'distribution':'64 independent uniform[-2,2] coefficients, each rounded to half','results':results,'first_counterexamples':first}
Path(output).write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'blocks':20000,'results':results,'first_counterexamples':{k:{kk:vv for kk,vv in v.items() if kk!='input_half_bits'} for k,v in first.items()}},indent=2))
