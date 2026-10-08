# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reviewed winner-seed and construction sign-query source correspondence.

Complete pins and these explicit source obligations complement the separate
arithmetic, work-accounting and native reviews. They are not a native proof.
"""
import hashlib
import json
import tokenize

try:
    import source_contracts as source
    import sum2_guard_contracts as guard
    import reviewed_cleanup_contracts as cleanup
    import frozen_arc_producer_contracts as frozen
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts as source
    from tools.carla_lane_oracle import sum2_guard_contracts as guard
    from tools.carla_lane_oracle import reviewed_cleanup_contracts as cleanup
    from tools.carla_lane_oracle import frozen_arc_producer_contracts as frozen

MIGRATION = 'tools/carla_lane_oracle/winner-sign-query-migration.json'


def require(condition, message):
    if not condition:
        raise ValueError('winner/sign source contract: ' + message)


def words(text):
    return [t.string for t in source.tokens(text) if t.type not in
            (tokenize.COMMENT, tokenize.NL, tokenize.NEWLINE, tokenize.INDENT,
             tokenize.DEDENT, tokenize.ENDMARKER)]


def contains(text, fragment, label):
    actual, expected = words(text), words(fragment)
    count = sum(actual[i:i+len(expected)] == expected
                for i in range(len(actual)-len(expected)+1))
    require(count == 1, label)


def fresh_guard(text):
    tokens = source.tokens(text)
    start = next(i for i, token in enumerate(tokens)
                 if token.type == tokenize.INDENT)
    body = [t.string for t in tokens[start+1:]
            if t.type not in (tokenize.COMMENT, tokenize.NL)]
    require(body[:4] == ['_require_sum2_environment', '(', ')', '\n'],
            'fresh environment guard must be the first operation')


def verify(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == guard.WINNER_SIGN_MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(record['schema'] == 1, 'unsupported migration schema')
    previous = root/'tools/carla_lane_oracle/default-query-restoration-migration.json'
    require(hashlib.sha256(previous.read_bytes()).hexdigest() ==
            record['prior_default_restoration_sha256'], 'historical restoration changed')
    text = (root/'extensions/carla/map.mojo').read_text()
    require(hashlib.sha256(text.encode()).hexdigest() ==
            record['raw_successors']['extensions/carla/map.mojo'][-1]['after'],
            'unreviewed complete Map source')
    for group in ('canonical_accumulation', 'support', 'optional_runtime'):
        source.verify_group(root, group)
    guard.verify(root)
    successors = dict(cleanup.read_record(root)['sources'])
    fourth = frozen.read_record(root)['source_successor']
    require(fourth['path'] not in successors, 'duplicate cleanup successor')
    successors[fourth['path']] = fourth
    additional = cleanup.invariant.verify(root)['sources']
    require(not (set(successors) & set(additional)), 'duplicate invariant successor')
    successors.update(additional)
    for path, expected in record['canonical_source_unchanged'].items():
        if path in successors:
            require(expected == successors[path]['before_sha256'],
                    'cleanup predecessor differs from historical canonical record: '+path)
            expected = successors[path]['after_sha256']
        require(hashlib.sha256((root/path).read_bytes()).hexdigest() == expected,
                'unreviewed canonical dependency: '+path)
    for name, expected in record['unchanged_public_methods'].items():
        require(source.token_sha256(guard.declaration(text, name, ('Map',))) == expected,
                'unchanged public/selected method changed: '+name)
    for name, expected in record['new_helper_source'].items():
        actual = guard.declaration(text, name, ())
        require(guard.significant(actual) == guard.significant(expected),
                'complete seed helper changed: '+name)
        if name in record['fresh_guard_helpers']:
            fresh_guard(actual)
    seed = guard.declaration(text, '_try_winner_seed', ())
    room = guard.declaration(text, '_winner_seed_room', ())
    contains(seed, 'work._step(60)', 'fixed admission must be prepaid')
    contains(seed, 'work._step(12)', 'local-band retry must be separately prepaid')
    contains(seed, 'for level in range(8):', 'dyadic proposal depth changed')
    contains(seed, 'if _wide_point_order(point, certificate.point, query) < 0:',
             'only strict exact point improvement can replace the incumbent')
    contains(seed, 'work.charge(0, point_work, node_cost)',
             'scalar proposal work must be charged')
    contains(room, 'var winner_followup = len(winner.cells) + 12',
             'winner continuation reserve changed')
    contains(room, 'var target_followup = target_cells + 12',
             'competitor continuation reserve changed')
    contains(room, 'var winner_units = proof_nodes + 255 + 50',
             'complete regular/tiny term reserve changed')
    contains(room, 'return target_reference <= terms_left // 50',
             'competitor term reserve changed')
    selector = guard.declaration(text, '_closest_lane_certificate_with_work', ('Map',))
    require('Exact lane witnesses have inconsistent dominance' not in selector,
            'reviewed redundant exact guard reappeared')
    return {'status': 'PASS', 'source_bound_helpers': 4,
            'fresh_environment_entries': 2, 'changed_map_dependency_groups': 3,
            'canonical_dependencies_unchanged': len(record['canonical_source_unchanged']) - len(successors),
            'reviewed_cleanup_successors': len(successors),
            'native_qualification_claimed': False}
