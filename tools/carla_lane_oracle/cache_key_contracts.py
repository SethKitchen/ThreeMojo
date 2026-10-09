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


def inventory(root):
    # Reuse the established production boundary, including nested namespaces
    # and __init__ re-exports. Do not normalize identifier ordinals.
    if __package__:
        from . import sum2_guard_contracts as guard
    else:
        import sum2_guard_contracts as guard
    result = {}
    for path in sorted(guard.production_mojo_paths(root)):
        rel = path.relative_to(root)
        if rel.parts[0] in guard.NONPRODUCTION or any(p.startswith('.') for p in rel.parts):
            continue
        text = path.read_text()
        if not any(name in text for name in NAMES):
            continue
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


def verify(root):
    root = Path(root)
    record = read_record(root)
    for name, expected in record['preserved_records'].items():
        require(hashlib.sha256((root / 'tools/carla_lane_oracle' / name).read_bytes()).hexdigest() == expected,
                'historical component changed: ' + name)
    current = (root / MODULE).read_text()
    require(source.token_sha256(current) == AFTER_TOKEN_SHA256,
            'complete live successor tokens changed')
    # Exact adopted bytes reverse independently. General live source keeps the
    # established comment/whitespace compatibility of the historical gates.
    # Full tokens retain indentation, boundaries, qualifiers and operations.
    reverse_exact(record['after'], record)
    require(inventory(root) == record['inventory'], 'production helper/caller inventory changed')
    # Complete module tokens retain imports, builtin name resolution, types,
    # external-witness/Optional guards, word order, memo lifetimes and ledgers.
    return record


def predecessor_source(root):
    record = verify(root)
    return reverse_exact(record['after'], record)


def reviewed_text(root, path, text):
    """Only this named module and this verified edge can obtain a projection."""
    if str(path) != MODULE or source.token_sha256(text) == BEFORE_TOKEN_SHA256:
        return text
    require(source.token_sha256(text) == AFTER_TOKEN_SHA256, 'unreviewed supplied lane source')
    return predecessor_source(root)


if __name__ == '__main__':
    import sys
    verify(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])
    print('Cache-key byte-exact successor: PASS (source correspondence only)')
