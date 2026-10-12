# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One token-bound cache-key successor edge; no historical pin is rewritten.

This gate proves source correspondence, not native execution or coverage. The
SIMD equality premise is scoped to the reviewed pinned toolchain. Historical
checks receive a predecessor only after the complete live successor and its
production routing have passed. Unknown edits, callers and records fail closed.
"""
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import sys
import tokenize

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

MODULE = 'extensions/carla/lane_refinement.mojo'
MIGRATION = 'tools/carla_lane_oracle/cache-key-migration.json'
MIGRATION_SHA256 = '06f0aefb02a1f897563f4e7d25e0a26f3fc56f1bef5f3fcb8eb68b5cd1188d5b'
BEFORE_SHA256 = '13afed281e9df7549d3acb022680e2e20a57ea54411817eed6f45bf9042e5938'
BEFORE_TOKEN_SHA256 = 'ad94f8e2a32d175b01e55f3e226c676a9aee371b49e00fc7b502ab56b6acfb46'
AFTER_TOKEN_SHA256 = '9893380d70f28a8cd85d41f21cb05102905f4ba528e7916437ba4397058895e0'
NAMES = frozenset(('_same_cache_key', '_run_lane_search', 'lane_refinement'))
PROTECTED_INPUTS = (MIGRATION, MODULE,
    'extensions/carla/junction_bounds.mojo',
    'extensions/carla/lane_box_cover.mojo', 'extensions/carla/map.mojo')
HISTORICAL_RECORDS = ('lane-order-migration.json', 'lane-control-migration.json', 'coverage-followup-migration.json', 'coverage-invariant-migration.json', 'curve-support-dispatch-migration.json', 'optional-runtime-migration.json', 'runtime-source-pins.json', 'sum2-guard-pins.json', 'spiral-moment-pins.json', 'winner-sign-query-migration.json', 'default-query-restoration-migration.json', 'accepted-successor-migration.json')
PROTECTED_INPUTS += tuple('tools/carla_lane_oracle/' + name for name in HISTORICAL_RECORDS)


class ContractError(ValueError, RuntimeError):
    """Compatible with the existing fail-closed contract interfaces."""


def require(condition, message):
    if not condition:
        raise ContractError('cache-key successor: ' + message)


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


@lru_cache(maxsize=128)
def inventory_entry(text):
    if __package__:
        from . import sum2_guard_contracts as guard
    else:
        import sum2_guard_contracts as guard
    if not any(name in text for name in NAMES):
        return None
    names = [t.string for t in source.tokens(text) if t.type == tokenize.NAME]
    uses = [[i, name] for i, name in enumerate(names) if name in NAMES]
    return {'routing': guard.declaration_routing(text), 'uses': uses} if uses else None


def inventory(root, *, verified_lane_source=None, _inputs=None, _input_owner=None, _operation=None):
    operation_args = {} if _operation is None else {'_operation': _operation}
    # Reuse the established production boundary, including nested namespaces
    # and __init__ re-exports. Do not normalize identifier ordinals.
    if __package__:
        from . import sum2_guard_contracts as guard
    else:
        import sum2_guard_contracts as guard
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        full_audit._operation_check(_operation, root)
    if _inputs is not None or _input_owner is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        require(type(_inputs) in (full_audit._CacheInputs, full_audit._BorrowedCacheInputs)
                and _input_owner is not None,
                'invalid owned inventory inputs')
        _inputs._check(_input_owner, root)
    paths = (guard.production_mojo_paths(root) if _inputs is None else
             (Path(root) / path for path in _inputs.production_paths(_input_owner, root)))
    if _inputs is None and _operation is not None:
        paths = full_audit._operation_production_paths(root, paths, _operation=_operation)
    result = {}
    for path in sorted(paths):
        rel = (full_audit._relative_path(path, root)
               if _inputs is not None or _operation is not None else path.relative_to(root))
        if rel.parts[0] in guard.NONPRODUCTION or any(p.startswith('.') for p in rel.parts):
            continue
        if _inputs is None:
            text = path.read_text()
            if _operation is not None:
                text = full_audit._observe_text(root, rel.as_posix(), text,
                        _operation=_operation, supplied=rel.as_posix() == 'extensions/carla/map.mojo')
        elif rel.as_posix() == 'extensions/carla/map.mojo':
            # Keep the supplied text observation distinct from physical bytes.
            try:
                text = path.read_text()
            except (OSError, UnicodeError) as error:
                raise ContractError('cache-key successor: unreadable owned Map view') from error
            physical = _inputs.observe_bytes(_input_owner, root, rel.as_posix())
            if __package__:
                from . import seed_count_contracts as seed_count
            else:
                import seed_count_contracts as seed_count
            require(hashlib.sha256(physical).hexdigest() in {seed_count.SCORE_AFTER_SHA256, seed_count.station.AFTER_SHA256, seed_count.deviation.AFTER_SHA256},
                    'score-helper view needs the exact physical Map')
            require(source.token_sha256(text) == source.token_sha256(
                        _inputs.text_default(_input_owner, root, rel.as_posix()))
                    == seed_count.score_family_token_sha256(hashlib.sha256(physical).hexdigest()),
                    'unreviewed supplied score-helper source')
        else:
            text = _inputs.text_default(_input_owner, root, rel.as_posix())
        if rel.as_posix() == MODULE and verified_lane_source is not None:
            # This explicit source is supplied only after fresh root admission.
            text = verified_lane_source
        if not any(name in text for name in NAMES):
            continue
        if rel.as_posix() == 'extensions/carla/map.mojo':
            if __package__:
                from . import seed_count_contracts as seed_count
            else:
                import seed_count_contracts as seed_count
            if _inputs is None:
                physical = path.read_bytes()
                if _operation is not None:
                    physical = full_audit._observe_bytes(root, rel.as_posix(), physical, _operation=_operation)
            physical_digest = hashlib.sha256(physical).hexdigest()
            supplied_tokens = source.token_sha256(text)
            if (physical_digest in {seed_count.SCORE_AFTER_SHA256, seed_count.station.AFTER_SHA256, seed_count.deviation.AFTER_SHA256}
                    or supplied_tokens in {seed_count.SCORE_AFTER_TOKEN_SHA256, seed_count.station.AFTER_TOKEN_SHA256, seed_count.deviation.AFTER_TOKEN_SHA256}):
                require(physical_digest in {seed_count.SCORE_AFTER_SHA256, seed_count.station.AFTER_SHA256, seed_count.deviation.AFTER_SHA256},
                        'score-helper view needs the exact physical Map')
                require(supplied_tokens == seed_count.score_family_token_sha256(physical_digest),
                        'unreviewed supplied score-helper source')
                # Qualify the actual helper/caller and dependencies before
                # mapping identifier ordinals to the exact preceding graph.
                if _inputs is None:
                    seed_count.verify_score(root, **operation_args)
                    after = path.read_bytes()
                    if _operation is not None:
                        after = full_audit._observe_bytes(root, rel.as_posix(), after, _operation=_operation)
                else:
                    seed_count.verify_score(root, _inputs=_inputs, _input_owner=_input_owner)
                    after = _inputs.observe_bytes(_input_owner, root, rel.as_posix())
                require(after == physical,
                        'Map changed during score-helper inventory check')
                text = seed_count.score_family_predecessor_source(physical.decode('utf-8'))
        entry = inventory_entry(text)
        if entry is not None:
            result[rel.as_posix()] = entry
    return result


def read_record(root):
    raw = (Path(root) / MIGRATION).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == MIGRATION_SHA256, 'migration record changed')
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    require(record['module'] == MODULE and record['schema'] == 1, 'wrong edge')
    require(sha(record['before']) == record['before_sha256'] == BEFORE_SHA256,
            'predecessor bytes changed')
    require(sha(record['after']) == record['after_sha256'], 'successor bytes changed')
    require(source.token_sha256(record['before']) == BEFORE_TOKEN_SHA256 and
            source.token_sha256(record['after']) == AFTER_TOKEN_SHA256, 'module tokens changed')
    return record


def reverse_exact(text, record):
    """Undo only three exact fragments, then compare all predecessor bytes."""
    require(sha(text) == record['after_sha256'] and text == record['after'],
            'complete live successor bytes changed')
    require(len(record['edits']) == 3 and
            [edit['name'] for edit in record['edits']] ==
            ['helper', 'cached_fast', 'cached_expansion'], 'wrong exact delta set')
    for edit in record['edits']:
        require(text.count(edit['after']) == 1, 'missing or duplicate delta: ' + edit['name'])
        text = text.replace(edit['after'], edit['before'], 1)
    require(text == record['before'] and sha(text) == BEFORE_SHA256,
            'byte-exact predecessor reconstruction failed')
    return text


def verify(root, *, _operation=None):
    root = Path(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        full_audit._operation_check(_operation, root)
        if not full_audit._cache_verify_frame(sys._getframe()):
            # An unsupported alias remains a wholly fresh independent call.
            _operation = None
            operation_args = {}
    record = read_record(root)
    for name, expected in record['preserved_records'].items():
        require(hashlib.sha256((root / 'tools/carla_lane_oracle' / name).read_bytes()).hexdigest() == expected,
                'historical component changed: ' + name)
    _input_owner = object()
    _inputs = None
    try:
        current = (root / MODULE).read_text()
        if _operation is not None:
            current = full_audit._observe_text(root, MODULE, current, _operation=_operation, supplied=True)
        if source.token_sha256(current) != AFTER_TOKEN_SHA256:
            try:
                if __package__:
                    from . import full_audit_cleanup_contracts as full_audit
                else:
                    import full_audit_cleanup_contracts as full_audit
                if full_audit._cache_verify_frame(sys._getframe()):
                    current, _inputs = full_audit._cache_lane_inputs(root, current, _input_owner, **operation_args)
                else:
                    # Unsupported import aliases preserve the complete fresh
                    # public path; they cannot acquire or borrow an input view.
                    current = full_audit.reviewed_text(root, MODULE, current, **operation_args)
            except (ValueError, OSError) as error:
                raise ContractError('cache-key successor: ' + str(error)) from error
        require(source.token_sha256(current) == AFTER_TOKEN_SHA256,
                'complete live successor tokens changed')
        # Exact adopted bytes reverse independently. General live source keeps the
        # established comment/whitespace compatibility of the historical gates.
        # Full tokens retain indentation, boundaries, qualifiers and operations.
        reverse_exact(record['after'], record)
        observed = (inventory(root, verified_lane_source=current, **operation_args) if _inputs is None else
                    inventory(root, verified_lane_source=current, _inputs=_inputs, _input_owner=_input_owner, **operation_args))
        require(observed == record['inventory'],
                'production helper/caller inventory changed')
        # Complete module tokens retain imports, builtin name resolution, types,
        # external-witness/Optional guards, word order, memo lifetimes and ledgers.
        if _inputs is not None:
            _inputs.checkpoint(_input_owner, root)
        return record
    finally:
        if _inputs is not None:
            _inputs.close(_input_owner)


def predecessor_source(root, *, _operation=None):
    record = verify(root, **({} if _operation is None else {'_operation': _operation}))
    return reverse_exact(record['after'], record)


def reviewed_text(root, path, text, *, _operation=None):
    """Only this named module and this verified edge can obtain a projection."""
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    operation_args = {} if _operation is None else {'_operation': _operation}
    if _operation is not None:
        full_audit._operation_check(_operation, root)
    if str(path) != MODULE:
        return full_audit.reviewed_text(root, path, text, **operation_args) if str(path) in full_audit.SOURCE_PATHS else text
    if source.token_sha256(text) == BEFORE_TOKEN_SHA256:
        return text
    observed = (Path(root)/MODULE).read_text()
    if _operation is not None:
        observed = full_audit._observe_text(root, MODULE, observed, _operation=_operation, supplied=True)
    require(source.token_sha256(text) == source.token_sha256(observed),
            'unreviewed supplied lane source')
    # predecessor_source performs fresh complete live admission before either
    # historical edge. Do not qualify the same source twice here.
    return predecessor_source(root, **operation_args)


if __name__ == '__main__':
    import sys
    verify(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])
    print('Cache-key byte-exact successor: PASS (source correspondence only)')
