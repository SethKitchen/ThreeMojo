"""Bind the grouped proof to its reviewed immutable-table producer contract."""
from pathlib import Path
import hashlib
import math
import struct

if __package__:
    from .source_contracts import token_sha256
else:
    from source_contracts import token_sha256

TOKEN_SHA256='3fcfc637a40c4e322b5747f27f8d77163c3f47a49d1092b37c20744cafecba40'
MODULE='extensions/carla/spiral_grouped_roundoff_proof.mojo'
EXPECTED='0e42c79e3bbda283c32886e50ad8b1acd614f651f1d258f4ea4b5e4e0e139299'

def verify_text(module, geometry):
    # Exact complete module binding includes imports, both materializations,
    # every use/write of local arrays, environment guard and error/work graph.
    if token_sha256(module)!=TOKEN_SHA256:
        raise ValueError('Reviewed grouped consumer graph changed')
    if __package__:
        from .spiral_moments import parse_array
    else:
        from spiral_moments import parse_array
    arrays={}
    for name in ('_GL_NODES','_GL_WEIGHTS'):
        words = parse_array(geometry, name, 5)
        values = [struct.unpack('>d', struct.pack('>Q', word))[0] for word in words]
        arrays[name]=values
    w=arrays['_GL_WEIGHTS'];n=arrays['_GL_NODES']
    if not(w[0]==w[4] and w[1]==w[3]):raise ValueError('Weight symmetry changed')
    if not all(math.isfinite(x) and 0<x<=1 for x in w):raise ValueError('Invalid stored weight')
    if not all(math.isfinite(x) and -1<x<1 for x in n):raise ValueError('Invalid stored node')
    return {'status':'PASS','consumer_sha256':EXPECTED,'runtime_arithmetic':'unchanged after impossible table refusals','coverage_waiver':False}

def verify(root):
    root=Path(root)
    text=(root/MODULE).read_text()
    if token_sha256(text)!=TOKEN_SHA256:
        if __package__:
            from . import selection_finiteness_contracts as selection
        else:
            import selection_finiteness_contracts as selection
        text=selection.predecessor_text(root,MODULE)
    return verify_text(text,(root/'extensions/carla/geometry.mojo').read_text())
