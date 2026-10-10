# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One reviewed OpenDRIVE border successor with an exact inverse.

This is source correspondence, not a numerical, native, or coverage proof.
The historical parser remains accepted without activating an edge. Only the
reviewed border parser activates the new edge. Consumer checks read the live
root; reconstructed source is never substituted for their actual inputs.
"""
import hashlib
import json
from pathlib import Path

if __package__:
    from . import source_contracts as source
    from . import sum2_guard_contracts as guard
    from . import speed_parser_contracts as speed
    from . import runtime_boundary_contracts as boundary
    from . import render_actor_reuse_contracts as reuse
else:
    import source_contracts as source
    import sum2_guard_contracts as guard
    import speed_parser_contracts as speed
    import runtime_boundary_contracts as boundary
    import render_actor_reuse_contracts as reuse

MODULE = 'extensions/carla/opendrive.mojo'
MIGRATION = 'tools/carla_lane_oracle/border-parser-successor.json'
MIGRATION_SHA256 = '0119f046c502021dc422f82ad602074e24cf3fa192f27fd372e80a927d94860b'
BEFORE_SHA256 = '4c7ac574196b83d025b84cf6c88261d5e3f3b9ce69923262fcf3cb935e9bf1e5'
AFTER_SHA256 = '9ff9b750af2c1c1a92fe3f3dfe1e49566e9d6f8c39a3576e0d4cf542bc8cdc28'
BEFORE_TOKEN_SHA256 = '3dfc5672424f8550e358758c5f32c3dd21253bb848dd0e4648ae1ceed1269f5c'
AFTER_TOKEN_SHA256 = '1d29eeea907706d3b63c0898f00490ffea8470cd061c7e3383ed907b26f809ce'
EDIT_NAMES = ('contract', 'imports', 'border_helpers_and_lane_prepass',
              'derived_width_routing', 'section_bounds_and_offsets')
TESTS = ('tests/test_carla_lane_borders.mojo',)
UNCHANGED_TESTS = ('tests/test_carla_opendrive.mojo',
                   'tests/test_carla_width_scan_equivalence.mojo',
                   'tests/test_carla_speed_lexical.mojo',
                   'tests/test_carla_speed_xml_lexical.mojo')
UNCHANGED_DECLARATIONS = ('_roads', '_geometries', '_profiles',
                          'load_opendrive', 'load_opendrive_file')
AFTER_DECLARATIONS = ('_active', '_border_ratio', '_lowest', '_border_widths',
                      '_lane_records', '_lanes')


def require(value, message):
    """Keep all source gates active under optimized Python."""
    if not value:
        raise ValueError('reviewed border parser successor: ' + message)


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def read_record(root):
    payload = (Path(root)/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'immutable successor record changed')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1
            and record['path'] == MODULE, 'wrong successor scope')
    require((record['before_sha256'], record['after_sha256'],
             record['before_token_sha256'], record['after_token_sha256']) ==
            (BEFORE_SHA256, AFTER_SHA256, BEFORE_TOKEN_SHA256, AFTER_TOKEN_SHA256),
            'reviewed endpoints changed')
    require(set(record['after_correctness_tests']) == set(TESTS)
            and set(record['unchanged_correctness_tests']) == set(UNCHANGED_TESTS),
            'correctness-test scope changed')
    require(set(record['unchanged_declarations']) == set(UNCHANGED_DECLARATIONS)
            and set(record['after_declarations']) == set(AFTER_DECLARATIONS),
            'declaration scope changed')
    return record


def checked_edits(record):
    edits = record['edits']
    require(tuple(edit['name'] for edit in edits) == EDIT_NAMES,
            'missing, duplicate, reordered or extra inverse edit')
    for edit in edits:
        require(set(edit) == {'name', 'before', 'after', 'before_sha256', 'after_sha256'},
                'inverse edit fields changed')
        for side in ('before', 'after'):
            require(bool(edit[side]) and sha(edit[side]) == edit[side+'_sha256'],
                    'inverse span hash changed: ' + edit['name'])
    return edits


def predecessor_source(text, record):
    """Reverse only reviewed unique spans, then require exact old bytes."""
    require(sha(text) == AFTER_SHA256 and source.token_sha256(text) == AFTER_TOKEN_SHA256,
            'unreviewed complete after parser')
    for edit in reversed(checked_edits(record)):
        require(text.count(edit['after']) == 1, 'missing or ambiguous inverse anchor')
        text = text.replace(edit['after'], edit['before'], 1)
    require(sha(text) == BEFORE_SHA256 and source.token_sha256(text) == BEFORE_TOKEN_SHA256,
            'inverse does not reconstruct historical parser')
    return text


def successor_source(root):
    """Reconstruct the reviewed after fixture; this does not qualify a root."""
    record = read_record(root)
    text = (Path(root)/MODULE).read_bytes().decode('utf-8')
    if sha(text) == BEFORE_SHA256:
        require(source.token_sha256(text) == BEFORE_TOKEN_SHA256, 'before tokens changed')
        for edit in checked_edits(record):
            require(text.count(edit['before']) == 1, 'missing or ambiguous forward anchor')
            text = text.replace(edit['before'], edit['after'], 1)
    predecessor_source(text, record)
    return text


def verify_declarations(text, record, after):
    """Bind actual public load order, old passes, and every new operation."""
    for name, digest in record['unchanged_declarations'].items():
        require(source.token_sha256(guard.declaration(text, name, ())) == digest,
                'old load ordering or parser pass changed: ' + name)
    start, end = text.find('struct _Doc('), text.find('def _roads(')
    require(0 <= start < end and sha(text[start:end]) == record['doc_adapter_sha256'],
            'XML numeric adapter changed')
    if after:
        for name, digest in record['after_declarations'].items():
            require(source.token_sha256(guard.declaration(text, name, ())) == digest,
                    'finite guard, width precedence or builder routing changed: ' + name)


def verify_source(text, record):
    """Return an edge only for the exact independently reviewed after bytes."""
    require((record['before_sha256'], record['after_sha256'],
             record['before_token_sha256'], record['after_token_sha256']) ==
            (BEFORE_SHA256, AFTER_SHA256, BEFORE_TOKEN_SHA256, AFTER_TOKEN_SHA256),
            'reviewed endpoint metadata changed')
    digest = sha(text)
    require(digest in {BEFORE_SHA256, AFTER_SHA256}, 'unknown complete parser variant')
    after = digest == AFTER_SHA256
    require(source.token_sha256(text) == (AFTER_TOKEN_SHA256 if after else BEFORE_TOKEN_SHA256),
            'actual parser tokens changed')
    verify_declarations(text, record, after)
    if not after:
        return None
    predecessor_source(text, record)
    return {'path': MODULE, 'before_sha256': BEFORE_SHA256,
            'after_sha256': AFTER_SHA256, 'before_token_sha256': BEFORE_TOKEN_SHA256,
            'after_token_sha256': AFTER_TOKEN_SHA256}


@source.lexical_memo_scope()
def verify(root):
    """Check the real source, retained lineage, live consumers and tests."""
    root = Path(root)
    record = read_record(root)
    edge = verify_source((root/MODULE).read_bytes().decode('utf-8'), record)
    consumers = boundary.verify(root)
    for path, reviewed in reuse.verify(root).items():
        require(path not in consumers, 'duplicate reviewed consumer edge: ' + path)
        consumers[path] = reviewed
    for group in ('historical_records', 'unchanged_inputs', 'unchanged_correctness_tests'):
        for path, expected in record[group].items():
            actual = hashlib.sha256((root/path).read_bytes()).hexdigest()
            if group == 'unchanged_inputs' and path == 'extensions/carla/map.mojo' and actual != expected:
                if __package__:
                    from . import seed_count_contracts as seed_count
                else:
                    import seed_count_contracts as seed_count
                require(expected == seed_count.BEFORE_SHA256
                        and actual in {seed_count.AFTER_SHA256, seed_count.OPTIONAL_AFTER_SHA256,
                                      seed_count.SUPPORT_AFTER_SHA256,
                                      seed_count.FRONTIER_AFTER_SHA256, seed_count.SCORE_AFTER_SHA256},
                        'unreviewed Map consumer variant')
                map_edge = seed_count.verify(root)
                require(map_edge is not None and map_edge['before_sha256'] == expected
                        and map_edge['after_sha256'] == actual,
                        'Map consumer edge does not extend the immutable parser record')
            elif group == 'unchanged_inputs' and path in consumers:
                require(expected == consumers[path]['before_sha256']
                        and actual == consumers[path]['after_sha256'],
                        'runtime boundary consumer does not extend the record: ' + path)
            else:
                require(actual == expected,
                        'historical record or live consumer changed: ' + path)
    # These are ACTUAL live-root checks. Never project reconstructed parser or
    # old consumer text into an existing arithmetic or speed-grammar checker.
    for group in ('canonical_accumulation', 'support', 'optional_runtime'):
        source.verify_group(root, group)
    speed.verify(root)
    if edge is not None:
        for path, expected in record['after_correctness_tests'].items():
            require((root/path).is_file()
                    and hashlib.sha256((root/path).read_bytes()).hexdigest() == expected,
                    'reviewed border regression suite missing or changed: ' + path)
    return edge
