# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Package verified native files as reviewable UTF-8 hex and audit metadata."""
import hashlib
import json
from pathlib import Path
import struct
import sys
root=Path(sys.argv[1])
destination=Path(__file__).resolve().parent
records=[]
for path in sorted(root.glob('*.exr')):
    data=path.read_bytes();at=8;channels=[]
    while data[at]:
        end=data.index(0,at);name=data[at:end];at=end+1
        end=data.index(0,at);at=end+1
        size,=struct.unpack_from('<I',data,at);at+=4
        value=data[at:at+size];at+=size
        if name==b'channels':
            pos=0
            while value[pos]:
                end=value.index(0,pos);t=struct.unpack_from('<I',value,end+1)[0]
                channels.append({'name':value[pos:end].decode(),'type':t,'pLinear':bool(value[end+5])});pos=end+17
        if name==b'dataWindow':x0,y0,x1,y1=struct.unpack('<4i',value)
        if name==b'compression':codec=value[0]
    at+=1;w=x1-x0+1;h=y1-y0+1
    per=[1,1,1,16,32,16,32,32,32,256][codec]
    chunks=[]
    for i in range((h+per-1)//per):
        offset,=struct.unpack_from('<Q',data,at+8*i)
        y,size=struct.unpack_from('<iI',data,offset)
        raw=w*min(per,h-y+y0)*sum(2 if c['type']==1 else 4 for c in channels)
        chunks.append({'line':y,'size':size,'raw_size':raw,'compressed':size<raw})
    record={'name':path.name,'codec':codec,'width':w,'height':h,'channels':channels,'chunks':chunks}
    for suffix in ['', '.rgba']:
        file=Path(str(path)+suffix);b=file.read_bytes();text=b.hex()
        (destination/(file.name+'.hex')).write_text('\n'.join(text[i:i+128] for i in range(0,len(text),128))+'\n')
        record['sha256'+suffix]=hashlib.sha256(b).hexdigest()
    source=Path(str(path)+'.input')
    if source.exists():
        a=struct.unpack('<'+'f'*(source.stat().st_size//4),source.read_bytes())
        target=Path(str(path)+'.rgba').read_bytes();b=struct.unpack('<'+'f'*(len(target)//4),target)
        record['max_source_absolute_error']=max(abs(x-y) for x,y in zip(a,b))
        record['max_source_scaled_error']=max(abs(x-y)/max(1,abs(x)) for x,y in zip(a,b))
        record['max_alpha_error']=max(abs(a[i]-b[i]) for i in range(3,len(a),4))
    records.append(record)
meta={'reference':'OpenEXR 3.1.5; Imath 3.1.5','archive_sha256':{'OpenEXR':'93925805c1fc4f8162b35f0ae109c4a75344e6decae5a240afdfce25f8a433ec','Imath':'1e9c7c94797cf7b7e61908aed1f80a331088cc7d8873318f70376e4aed5f25fb'},'fixtures':records}
(destination/'manifest.json').write_text(json.dumps(meta,indent=2)+'\n')
for codec in range(5,10):
    cases=[r for r in records if r['codec']==codec]
    print(codec,len(cases),'compressed chunks',sum(c['compressed'] for r in cases for c in r['chunks']),'max source scaled error',max(r.get('max_source_scaled_error',0) for r in cases))
