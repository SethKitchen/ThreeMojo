# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact source/name binding for the rounded LINE singleton successor.

This standalone verifier grants no coverage exclusion. Central migration and
independent approval must compose this proposal into aggregate tooling.
"""
import hashlib
import json
if __package__:
    from . import source_contracts as source
    from . import sum2_guard_contracts as guard
else:
    import source_contracts as source
    import sum2_guard_contracts as guard

MIGRATION = 'tools/carla_lane_oracle/rounded-line-singleton-migration.json'
MIGRATION_SHA256 = 'e4a0eb6c9e527dd66b2b803ee69754334feecc9bea33ce001cdf584d3a693506'


def require(value, message):
    if not value:
        raise ValueError('rounded LINE singleton contract: ' + message)


def read_record(root):
    payload = (root / MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(record['schema'] == 1, 'wrong schema')
    return record



def _reviewed_text(root, path, record):
    text = (root/path).read_text()
    if path != 'extensions/carla/curve_rounded_line.mojo' or guard.significant(text) == guard.significant(record['modules'][path]['source']):
        return text
    if __package__:
        from . import rounded_line_selector_contracts as successor
    else:
        import rounded_line_selector_contracts as successor
    # Validate the actual complete selector/context/name graph before restoring
    # its exact immediate predecessor. The successor calls read_record only.
    current = successor.verify_premises(root)
    require(current['path'] == path, 'wrong selector predecessor path')
    return current['before_source']


def _verify_dependency(path, text, expected):
    if __package__:
        from . import reviewed_cleanup_contracts as words
    else:
        import reviewed_cleanup_contracts as words
    words.verify_dependency(path, text, expected)


def verify_premises(root):
    record = read_record(root)
    # Whole module tokens bind imports, declaration owners and local names.
    for path, item in record['modules'].items():
        actual = _reviewed_text(root, path, record)
        if guard.significant(actual) != guard.significant(item['source']):
            _verify_dependency(path, actual, item['token_sha256'])
    for path, expected in record['import_scopes'].items():
        actual = (root/path).read_text().split('\ndef ',1)[0].split('\n@',1)[0].split('\nstruct ',1)[0]
        require(guard.significant(actual) == guard.significant(expected), 'consumer import scope changed: ' + path)
    for item in record['declarations']:
        actual = guard.declaration((root/item['path']).read_text(), item['name'], tuple(item['owner']))
        require(guard.significant(actual) == guard.significant(item['source']),
                'consumer/reference declaration changed: ' + item['name'])
    return record


def verify(root):
    record = read_record(root)
    for path, item in record['modules'].items():
        _verify_dependency(path, _reviewed_text(root, path, record), item['token_sha256'])
    verify_premises(root)
    return record
