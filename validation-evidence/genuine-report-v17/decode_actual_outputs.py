"""Decode only the two named evidence payloads; never execute the probe."""
from pathlib import Path
import base64,gzip,hashlib,json,sys
r=Path(__file__).resolve().parent
s=json.loads((r/'VALIDATION-SUMMARY.json').read_text())
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=False)
for row in s['encoded_outputs']:
 p=Path(row['encoded_path']);name=row['decoded_name']
 if p.is_absolute() or '..' in p.parts or Path(name).name!=name:raise ValueError('Unsafe path')
 data=gzip.decompress(base64.b64decode((r/p).read_bytes()))
 if len(data)!=row['decoded_bytes'] or hashlib.sha256(data).hexdigest()!=row['decoded_sha256']:raise ValueError('Changed payload')
 (out/name).write_bytes(data)
 print(name,len(data),row['decoded_sha256'])
