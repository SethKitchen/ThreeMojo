"""Qualify the reviewed lane-control successor without changing historical pins."""
import hashlib
import json
from pathlib import Path

if __package__:
    from .sum2_guard_contracts import declaration
    from .source_contracts import token_sha256
else:
    from sum2_guard_contracts import declaration
    from source_contracts import token_sha256

RECORD_SHA256 = '73d95d594e740205bad4cd900288a68d9f82897474fdc33e4d6043a156790170'
PREDECESSOR_SHA256 = '33d33ba0e481e3eca3b17ae0d02457ab53bae906430b0dca58abcfa876756315'


def _check_operation(root, operation):
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    full_audit._operation_check(operation, root)


def _observe_text(root, path, text, *, _operation=None, supplied=False):
    if _operation is None:
        return text
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    return full_audit._observe_text(
        root, path, text, _operation=_operation, supplied=supplied)


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    root = Path(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    path = root / 'tools/carla_lane_oracle/lane-control-migration.json'
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == RECORD_SHA256,
            'lane-control migration record changed')
    record = json.loads(raw)
    require(hashlib.sha256(record['before_source'].encode()).hexdigest()
            == record['before_sha256'] == PREDECESSOR_SHA256,
            'lane-control predecessor changed')
    require(hashlib.sha256(record['after_source'].encode()).hexdigest()
            == record['after_sha256'], 'lane-control successor record changed')
    current = _observe_text(root, record['module'], (root / record['module']).read_text(), _operation=_operation)
    if token_sha256(current) != token_sha256(record['after_source']):
        if __package__:
            from . import lane_order_contracts as order
        else:
            import lane_order_contracts as order
        current = order.predecessor_source(root, **operation_args)

    require(token_sha256(current) == token_sha256(record['after_source']),
            'lane-control successor module changed')
    for item in record['declarations']:
        name = item['name']
        require(token_sha256(declaration(record['before_source'], name, ()))
                == token_sha256(item['before']), 'lane-control before declaration drift')
        require(token_sha256(declaration(current, name, ()))
                == token_sha256(item['after']), 'lane-control after declaration drift')
        test = _observe_text(root, 'tests/test_carla_lane_control_successor.mojo',
                             (root / 'tests/test_carla_lane_control_successor.mojo').read_text(),
                             _operation=_operation)
        frozen = declaration(test, '_reference' + name, ())
        expected = item['before'].replace('def ' + name + '(', 'def _reference' + name + '(', 1)
        require(token_sha256(frozen) == token_sha256(expected),
                'lane-control frozen predecessor changed')
    for item in record['premises']:
        actual = declaration(_observe_text(root, item['path'], (root / item['path']).read_text(), _operation=_operation), item['name'], ())
        require(token_sha256(actual) == token_sha256(item['source']),
                'lane-control guarded premise changed: ' + item['name'])
    for rel, expected in record['producer_modules'].items():
        require(token_sha256(_observe_text(root, rel, (root / rel).read_text(), _operation=_operation)) == token_sha256(expected),
                'lane-control IEEE producer module changed: ' + rel)
    return record


def accepts_predecessor(root, path, name, owner, expected_source, *, _operation=None):
    """Delegate only an exact historical declaration to this reviewed successor."""
    if _operation is not None:
        _check_operation(root, _operation)
    record = verify(root, **({} if _operation is None else {'_operation': _operation}))
    if owner:
        return False
    for item in record['declarations']:
        if path == item['path'] and name == item['name']:
            return token_sha256(expected_source) == token_sha256(item['before'])
    return False


if __name__ == '__main__':
    import sys
    verify(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])
    print('Lane control-flow migration: PASS')
