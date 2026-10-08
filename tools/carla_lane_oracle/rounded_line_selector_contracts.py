# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Explicit pure-selector successor; no reachability or coverage waiver."""
import hashlib
import json
try:
    import source_contracts as source
    import sum2_guard_contracts as guard
    import rounded_line_singleton_contracts as prior
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts as source
    from tools.carla_lane_oracle import sum2_guard_contracts as guard
    from tools.carla_lane_oracle import rounded_line_singleton_contracts as prior

MIGRATION = 'tools/carla_lane_oracle/rounded-line-selector-migration.json'
MIGRATION_SHA256 = 'ccb63b640653126b098185b188e33a036b140919a3c48b1ecb1b1541571ef4c4'


def require(value, message):
    if not value:
        raise ValueError('rounded LINE selector contract: ' + message)


def read_record(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256, 'unreviewed selector migration')
    return json.loads(payload, object_pairs_hook=source.unique_keys)


def verify_premises(root):
    record = read_record(root)
    old = prior.read_record(root)
    require(hashlib.sha256((root/prior.MIGRATION).read_bytes()).hexdigest() == record['prior_migration_sha256'], 'prior migration changed')
    path = record['path']
    require(guard.significant(record['before_source']) == guard.significant(old['modules'][path]['source']), 'wrong immediate predecessor')
    require(guard.significant((root/path).read_text()) == guard.significant(record['after_source']), 'selector or context graph/name changed')
    for name, item in old['modules'].items():
        if name != path:
            actual = (root/name).read_text()
            if guard.significant(actual) != guard.significant(item['source']):
                try:
                    import reviewed_cleanup_contracts as words
                except ModuleNotFoundError:
                    from tools.carla_lane_oracle import reviewed_cleanup_contracts as words
                words.verify_dependency(name, actual, item['token_sha256'])
    for name, expected in old['import_scopes'].items():
        actual=(root/name).read_text().split('\ndef ',1)[0].split('\n@',1)[0].split('\nstruct ',1)[0]
        require(guard.significant(actual) == guard.significant(expected), 'consumer import scope changed')
    for item in old['declarations']:
        actual=guard.declaration((root/item['path']).read_text(),item['name'],tuple(item['owner']))
        require(guard.significant(actual) == guard.significant(item['source']), 'prior consumer/reference changed: ' + item['name'])
    item=record['reference']
    actual=guard.declaration((root/item['path']).read_text(),item['name'],())
    require(guard.significant(actual) == guard.significant(item['source']), 'immediate predecessor native reference changed')
    return record


def verify(root):
    record=verify_premises(root)
    require(source.token_sha256((root/record['path']).read_text()) == record['after_token_sha256'], 'complete selector successor changed')
    return record
