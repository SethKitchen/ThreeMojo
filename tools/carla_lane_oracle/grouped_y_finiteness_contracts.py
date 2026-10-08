"""Exact graph for the reviewed private Y-finiteness lemma. No arbitrary projection."""
from pathlib import Path
try:
    import source_contracts
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts
EXPECTED = {'extensions/carla/spiral_grouped_roundoff_proof.mojo': 'cd92ac2f02c75fc420920fe3a73b4ddd28a4e5cf0d97785b4ae4eb0f54f2cbd7', 'extensions/carla/curve_interval.mojo': 'e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11', 'extensions/carla/curve_trig.mojo': '523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f', 'extensions/carla/geometry.mojo': 'a1979bd37d0ea725f452e0a0a269c7aaef3cda485b291e8fe79b49b35850adcb', 'extensions/carla/curve_sum2.mojo': '3fbcbb7f6ba0b9120500698665f0419acf6618d8bd34b7e18b9d10896282383d'}

def verify_text(modules):
    if set(modules) != set(EXPECTED):
        raise ValueError('Wrong Y-finiteness dependency set')
    for name, digest in EXPECTED.items():
        if source_contracts.token_sha256(modules[name]) != digest:
            try:
                import reviewed_cleanup_contracts as words
            except ModuleNotFoundError:
                from tools.carla_lane_oracle import reviewed_cleanup_contracts as words
            try:
                words.verify_dependency(name, modules[name], digest)
            except ValueError as error:
                raise ValueError('Y-finiteness premise, graph, writes or ordering changed: ' + name) from error
    return {'status': 'PASS', 'maximum_accumulator_exponent': 947, 'origin_error_refusal_unchanged': True, 'y_call_and_writes_retained': True}

def verify(root):
    root = Path(root)
    return verify_text({p: (root/p).read_text() for p in EXPECTED})

MODULE = 'extensions/carla/spiral_grouped_roundoff_proof.mojo'
RECORD = 'tools/carla_lane_oracle/grouped-y-successor-record.json'
RECORD_SHA256 = '4b72cd07de22d61d70c7aa489e566cd25468189b6a60b5e105fa26ea726e6853'
PREDECESSOR_TOKEN_SHA256 = 'a8f3beca23c8d6a84d01f5eebecb0a01cd2102aad4e226ed6a782722733a86b7'


def predecessor_text(root, path):
    """Verify all actual Y premises before restoring its exact prior module."""
    import hashlib
    import json
    root = Path(root)
    if str(path) != MODULE:
        raise ValueError('Y projection permits only its exact grouped module')
    # Never call selection or another historical projection from here. The
    # actual five-file graph must pass before any record can provide text.
    verify(root)
    payload = (root / RECORD).read_bytes()
    if hashlib.sha256(payload).hexdigest() != RECORD_SHA256:
        raise ValueError('Unreviewed grouped Y successor record')
    record = json.loads(payload, object_pairs_hook=source_contracts.unique_keys)
    required = {'module', 'predecessor_file_sha256', 'successor_file_sha256',
                'predecessor_token_sha256', 'successor_token_sha256',
                'before_complete_module', 'after_complete_module',
                'only_change', 'dependencies'}
    if set(record) != required or record['module'] != MODULE:
        raise ValueError('Wrong grouped Y record schema or module')
    if record['dependencies'] != EXPECTED:
        raise ValueError('Grouped Y record dependency set changed')
    before = record['before_complete_module']
    after = record['after_complete_module']
    if not isinstance(before, str) or not isinstance(after, str):
        raise ValueError('Grouped Y record must contain complete source text')
    if (hashlib.sha256(before.encode()).hexdigest() != record['predecessor_file_sha256']
            or hashlib.sha256(after.encode()).hexdigest() != record['successor_file_sha256']):
        raise ValueError('Grouped Y complete-module byte identity changed')
    if (record['predecessor_token_sha256'] != PREDECESSOR_TOKEN_SHA256
            or source_contracts.token_sha256(before) != PREDECESSOR_TOKEN_SHA256
            or record['successor_token_sha256'] != EXPECTED[MODULE]
            or source_contracts.token_sha256(after) != EXPECTED[MODULE]):
        raise ValueError('Grouped Y predecessor/successor token identity changed')
    return before
