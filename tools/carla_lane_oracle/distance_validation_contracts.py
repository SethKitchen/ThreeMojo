"""Exact bounded representation checks; not capture/proof authentication."""
from pathlib import Path
try:
    import source_contracts
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts
MODULE='extensions/carla/spiral_domain_proof.mojo'
EXPECTED='7263f3e46da6496d3b3a6054870b4238d9f4767c07e90161065c5c87e6d18813'
INTERVAL='e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11'

def verify_text(module,interval):
    if source_contracts.token_sha256(module)!=EXPECTED:raise ValueError('Distance validation, derivative/association checks or debit/routing changed')
    if source_contracts.token_sha256(interval)!=INTERVAL:raise ValueError('Ordered nonnegative-error widening operation changed')
    return {'status':'PASS','scope':'Finite ordered raw value and finite nonnegative error; original derivative and association checks retained','provenance_authenticated':False,'original_debit_retained':True}

def verify(root):
    root=Path(root)
    return verify_text((root/MODULE).read_text(),(root/'extensions/carla/curve_interval.mojo').read_text())
