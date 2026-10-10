# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Explicit pure-selector successor; no reachability or coverage waiver."""
import hashlib
import io
import json
if __package__:
    from . import source_contracts as source
    from . import full_audit_cleanup_contracts as full_audit
    from . import sum2_guard_contracts as guard
    from . import rounded_line_singleton_contracts as prior
else:
    import source_contracts as source
    import full_audit_cleanup_contracts as full_audit
    import sum2_guard_contracts as guard
    import rounded_line_singleton_contracts as prior

MIGRATION = 'tools/carla_lane_oracle/rounded-line-selector-migration.json'
MIGRATION_SHA256 = 'ccb63b640653126b098185b188e33a036b140919a3c48b1ecb1b1541571ef4c4'


def require(value, message):
    if not value:
        raise ValueError('rounded LINE selector contract: ' + message)


def read_record(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256, 'unreviewed selector migration')
    return json.loads(payload, object_pairs_hook=source.unique_keys)


def _lane_observation(root):
    """Compare actual text/byte views without imposing a historical file pin."""
    path = root/'extensions/carla/lane_refinement.mojo'
    text = path.read_text()
    raw = path.read_bytes()
    with io.TextIOWrapper(io.BytesIO(raw), encoding='utf-8', newline=None) as reader:
        require(source.token_sha256(text) == source.token_sha256(reader.read()),
                'consumer lane source text/bytes disagree')
    return text, raw


def _lane_text(root):
    return _lane_observation(root)[0]


def verify_premises(root, *, _return_current_admission=False):
    require(type(_return_current_admission) is bool,
            'invalid current-admission output request')
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
                if __package__:
                    from . import reviewed_cleanup_contracts as words
                else:
                    import reviewed_cleanup_contracts as words
                words.verify_dependency(name, actual, item['token_sha256'])
    lane_predecessor = lane_raw = road_raw = None
    for name, expected in old['import_scopes'].items():
        if name == 'extensions/carla/lane_refinement.mojo':
            text, observed_raw = _lane_observation(root)
        else:
            text = (root/name).read_text()
        actual = text.split('\ndef ',1)[0].split('\n@',1)[0].split('\nstruct ',1)[0]
        if (name == 'extensions/carla/lane_refinement.mojo'
                and guard.significant(actual) != guard.significant(expected)):
            # Only a changed consumed scope requests complete current admission.
            text, observed_road = full_audit._reviewed_lane_observation(root, text, observed_raw)
            if observed_road is not None:
                lane_predecessor, lane_raw, road_raw = text, observed_raw, observed_road
            actual = text.split('\ndef ',1)[0].split('\n@',1)[0].split('\nstruct ',1)[0]
        require(guard.significant(actual) == guard.significant(expected), 'consumer import scope changed')
    for item in old['declarations']:
        selected = (item['path'], item['name'], tuple(item['owner'])) == (
            'extensions/carla/lane_refinement.mojo', '_rounded_axis_lane_minimum', ())
        if selected and lane_predecessor is not None:
            text = lane_predecessor
        elif lane_predecessor is not None and item['path'] in (
                'extensions/carla/lane_refinement.mojo', 'extensions/carla/road.mojo'):
            name = item['path']
            expected_raw = lane_raw if name == 'extensions/carla/lane_refinement.mojo' else road_raw
            try:
                physical = full_audit._regular(root, name)
                raw = physical.read_bytes()
            except (OSError, UnicodeError) as error:
                raise ValueError('rounded LINE selector contract: unreadable observation: ' + name) from error
            require(type(raw) is bytes and raw == expected_raw, 'consumer observation changed: ' + name)
            try:
                text = full_audit._physical_text(raw)
                supplied = physical.read_text()
            except (OSError, UnicodeError) as error:
                raise ValueError('rounded LINE selector contract: unreadable observation: ' + name) from error
            require(source.token_sha256(supplied) == source.token_sha256(text),
                    'consumer source text/bytes disagree: ' + name)
        elif selected:
            text, observed_raw = _lane_observation(root)
        else:
            text = (root/item['path']).read_text()
        actual = guard.declaration(text, item['name'], tuple(item['owner']))
        if selected and lane_predecessor is None and guard.significant(actual) != guard.significant(item['source']):
            text, observed_road = full_audit._reviewed_lane_observation(root, text, observed_raw)
            if observed_road is not None:
                lane_predecessor, lane_raw, road_raw = text, observed_raw, observed_road
                scope = text.split('\ndef ',1)[0].split('\n@',1)[0].split('\nstruct ',1)[0]
                require(guard.significant(scope) == guard.significant(old['import_scopes'][item['path']]),
                        'consumer import scope changed')
            actual = guard.declaration(text, item['name'], tuple(item['owner']))
        require(guard.significant(actual) == guard.significant(item['source']), 'prior consumer/reference changed: ' + item['name'])
    item=record['reference']
    actual=guard.declaration((root/item['path']).read_text(),item['name'],())
    require(guard.significant(actual) == guard.significant(item['source']), 'immediate predecessor native reference changed')
    if lane_predecessor is not None:
        for name, expected_raw in (('extensions/carla/lane_refinement.mojo', lane_raw),
                                   ('extensions/carla/road.mojo', road_raw)):
            try:
                raw = full_audit._regular(root, name).read_bytes()
            except (OSError, UnicodeError) as error:
                raise ValueError('rounded LINE selector contract: unreadable observation: ' + name) from error
            require(type(raw) is bytes and raw == expected_raw, 'consumer observation changed: ' + name)
    if _return_current_admission:
        return record, lane_predecessor is not None
    return record


def verify(root):
    record=verify_premises(root)
    require(source.token_sha256((root/record['path']).read_text()) == record['after_token_sha256'], 'complete selector successor changed')
    return record


def _verify_for_pin_pair(root):
    """Report only this completed selector execution's admission branch."""
    record, observed_current_admission = verify_premises(
        root, _return_current_admission=True)
    require(source.token_sha256((root/record['path']).read_text()) == record['after_token_sha256'], 'complete selector successor changed')
    return record, observed_current_admission
