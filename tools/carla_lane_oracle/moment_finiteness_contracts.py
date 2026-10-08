"""Source-bound finite-intermediate proof for the dynamic moment producer."""
from pathlib import Path

try:
    import source_contracts
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts

MODULE='extensions/carla/spiral_moment_proof.mojo'
INTERVAL='extensions/carla/curve_interval.mojo'
EXPECTED='9001f34d01c28de8dcf85af0bec9d9b9409ef8d56e083bfc25d6342c375f80d1'
EXPECTED_INTERVAL='e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11'

def verify_text(module, interval, geometry, trig):
    if source_contracts.token_sha256(module)!=EXPECTED:
        raise ValueError('Moment producer count/work/arithmetic graph changed')
    if source_contracts.token_sha256(interval)!=EXPECTED_INTERVAL:
        raise ValueError('Directed interval arithmetic dependency changed')
    # Lazy import avoids a cycle through the maintained migration checkers.
    try:
        import spiral_moments
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import spiral_moments
    for name,size,text,low,high,strict in [('_GL_NODES',5,geometry,-1,1,True),('_GL_WEIGHTS',5,geometry,0,1,False),('_COS_COEFFICIENTS',11,trig,-1,1,False),('_SIN_COEFFICIENTS',11,trig,-1,1,False)]:
        # Parse the complete actual top-level declaration, never a matching
        # prefix in a string/conditional/concatenation. Decode exact stored
        # binary64 words; nonfinite words are refused before rational bounds.
        words=spiral_moments.parse_array(text,name,size)
        values=[spiral_moments.fraction_of_word(word) for word in words]
        for value in values:
            valid=low<=value<=high
            if name=='_GL_WEIGHTS':valid=valid and value>0
            if strict:valid=valid and low<value<high
            if not valid:raise ValueError('Constant outside finite proof bound: '+name)
    return {'status':'PASS','finite_bound_exponent':410,'count_domain':[1,64],'source_token_sha256':EXPECTED}

def verify(root):
    root=Path(root)
    return verify_text((root/MODULE).read_text(),(root/INTERVAL).read_text(),(root/'extensions/carla/geometry.mojo').read_text(),(root/'extensions/carla/curve_trig.mojo').read_text())
