"""Bind the finite ordered queue successor without rewriting historical pins."""
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import tokenize

if __package__:
    from . import source_contracts as source
    from . import sum2_guard_contracts as guard
else:
    import source_contracts as source
    import sum2_guard_contracts as guard
if __package__:
    from . import cache_key_contracts as cache_key
else:
    import cache_key_contracts as cache_key


RECORD_SHA256 = 'e0aece69b861bc11a197cae17803e3273cdbd0cfed7ed0ca577ca6c3b4d217b1'
PREDECESSOR_SHA256 = 'b607c75982a15122dd8f3de743e48ec66e71f027cb5dd034b459dc46602c5c3e'


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


@lru_cache(maxsize=128)
def inventory_entry(text):
    names = {'_run_lane_search', 'lane_refinement'}
    if not any(name in text for name in names):
        return None
    identifiers = [t.string for t in source.tokens(text) if t.type == tokenize.NAME]
    uses = [[i, name] for i, name in enumerate(identifiers) if name in names]
    return {'routing': guard.declaration_routing(text), 'uses': uses} if uses else None


def inventory(root, *, verified_lane_predecessor=None, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    result = {}
    operation_args = {} if _operation is None else {'_operation': _operation}
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
    paths = sorted(guard.production_mojo_paths(root))
    if _operation is not None:
        paths = full_audit._operation_production_paths(root, paths, _operation=_operation)
    for path in paths:
        rel = path.relative_to(root)
        if rel.parts[0] in guard.NONPRODUCTION or any(p.startswith('.') for p in rel.parts):
            continue
        text = _observe_text(
            root, rel.as_posix(), path.read_text(), _operation=_operation,
            supplied=rel.as_posix() == 'extensions/carla/map.mojo')
        if rel.as_posix() == cache_key.MODULE and verified_lane_predecessor is not None:
            text = verified_lane_predecessor
        if '_run_lane_search' not in text and 'lane_refinement' not in text:
            continue
        if rel.as_posix() == 'extensions/carla/map.mojo':
            if __package__:
                from . import seed_count_contracts as seed_count
            else:
                import seed_count_contracts as seed_count
            physical = path.read_bytes()
            if _operation is not None:
                full_audit._observe_bytes(root, rel.as_posix(), physical, _operation=_operation)
            physical_digest = hashlib.sha256(physical).hexdigest()
            supplied_tokens = source.token_sha256(text)
            if (physical_digest == seed_count.SCORE_AFTER_SHA256
                    or supplied_tokens == seed_count.SCORE_AFTER_TOKEN_SHA256):
                require(physical_digest == seed_count.SCORE_AFTER_SHA256,
                        'score-helper view needs the exact physical Map')
                require(supplied_tokens == seed_count.SCORE_AFTER_TOKEN_SHA256,
                        'unreviewed supplied score-helper source')
                seed_count.verify_score(root, **operation_args)
                final_raw = path.read_bytes()
                if _operation is not None:
                    full_audit._observe_bytes(root, rel.as_posix(), final_raw, _operation=_operation)
                require(final_raw == physical,
                        'Map changed during score-helper routing check')
                text = seed_count.score_predecessor_source(physical.decode('utf-8'))
        entry = inventory_entry(text)
        if entry is not None:
            result[rel.as_posix()] = entry
    return result


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    root = Path(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    raw = (root / 'tools/carla_lane_oracle/lane-order-migration.json').read_bytes()
    require(hashlib.sha256(raw).hexdigest() == RECORD_SHA256, 'lane-order record changed')
    record = json.loads(raw)
    require(hashlib.sha256(record['before'].encode()).hexdigest() == record['before_sha256'] == PREDECESSOR_SHA256, 'lane-order predecessor changed')
    require(hashlib.sha256(record['after'].encode()).hexdigest() == record['after_sha256'], 'lane-order successor record changed')
    for rel, expected in record['immutable_predecessor_records'].items():
        require(hashlib.sha256((root / rel).read_bytes()).hexdigest() == expected, 'lane-order predecessor record changed: ' + rel)
    live = _observe_text(root, record['module'], (root / record['module']).read_text(), _operation=_operation)
    current = cache_key.reviewed_text(root, record['module'], live, **operation_args)
    require(source.token_sha256(current) == source.token_sha256(record['after']), 'lane-order successor module changed')
    for rel, expected in record['premise_modules'].items():
        require(source.token_sha256(_observe_text(root, rel, (root / rel).read_text(), _operation=_operation)) == source.token_sha256(expected), 'lane-order producer premise changed: ' + rel)
    require(inventory(root, verified_lane_predecessor=current, **operation_args) == record['inventory'], 'lane-order production routing changed')
    run = guard.declaration(current, '_run_lane_search', ())
    insertions = [{'line_in_function': i + 1, 'operation': line.strip()} for i, line in enumerate(run.splitlines()) if any(word in line for word in ['pending.append(', 'closed.add(', 'terminal.append(', 'closed.recheck('])]
    # Line positions are documentary. Token-bound complete function controls semantics.
    require([x['operation'] for x in insertions] == [x['operation'] for x in record['insertions']], 'lane-order insertion scan changed')
    test = _observe_text(root, 'tests/test_carla_lane_order_successor.mojo',
                         (root / 'tests/test_carla_lane_order_successor.mojo').read_text(),
                         _operation=_operation)
    for name, expected in record['references'].items():
        require(source.token_sha256(guard.declaration(test, name, ())) == source.token_sha256(expected), 'lane-order frozen reference changed: ' + name)
    return record


def predecessor_source(root, *, _operation=None):
    """Return the exact earlier module only after qualifying its reviewed successor."""
    if _operation is not None:
        _check_operation(root, _operation)
    return verify(root, **({} if _operation is None else {'_operation': _operation}))['before']


if __name__ == '__main__':
    import sys
    verify(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])
    print('Lane finite-order migration: PASS')
