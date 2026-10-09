"""Bind the exact no-counter-alias span between envelope budget admissions."""
from pathlib import Path
if __package__:
    from . import source_contracts
    from . import sum2_guard_contracts
else:
    import source_contracts
    import sum2_guard_contracts
MODULE='extensions/carla/curve_bounds.mojo'
EXPECTED='9bc62290a6bdeca43c4d695a0f0ce6592d69f49386d83ce7342b667c73680fce'

def verify_text(text):
    if source_contracts.token_sha256(text)!=EXPECTED:
        raise ValueError('Reviewed budget admission, routing or arithmetic changed')
    body=sum2_guard_contracts.declaration(text,'_try_lane_envelope_capture',())
    start=body.index('    var at = info_index(')
    end=body.index('    if optional_work > max_terms - terms:')
    import tokenize
    names={token.string for token in source_contracts.tokens(body[start:end]) if token.type==tokenize.NAME}
    if names & {'terms','max_terms'}:
        raise ValueError('Intervening span can access budget parameters')
    return {'status':'PASS','source_token_sha256':EXPECTED,'intervening_counter_uses':0,'retained_capacity_and_debit':True}

def verify(root):return verify_text((Path(root)/MODULE).read_text())


def historical_function(text):
    """Return the bound predecessor only after verifying the exact successor."""
    import hashlib
    import json
    verify_text(text)
    payload = Path(__file__).with_name('envelope-budget-contract.json').read_bytes()
    if hashlib.sha256(payload).hexdigest() != 'c43aa2bfdfb2a33575745eefb44b2f8ff0714a71a31ad750e8c4c0572fa7f2be':
        raise ValueError('Unreviewed envelope budget predecessor record')
    record = json.loads(payload, object_pairs_hook=source_contracts.unique_keys)
    actual = sum2_guard_contracts.declaration(text,'_try_lane_envelope_capture',())
    if sum2_guard_contracts.significant(actual) != sum2_guard_contracts.significant(record['after_complete_function']):
        raise ValueError('Envelope budget successor function changed')
    return record['before_complete_function']
