# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reviewed winner-seed and construction sign-query source correspondence.

Complete pins and these explicit source obligations complement the separate
arithmetic, work-accounting and native reviews. They are not a native proof.
"""
import hashlib
import json
import tokenize

if __package__:
    from . import source_contracts as source
    from . import sum2_guard_contracts as guard
    from . import reviewed_cleanup_contracts as cleanup
    from . import frozen_arc_producer_contracts as frozen
else:
    import source_contracts as source
    import sum2_guard_contracts as guard
    import reviewed_cleanup_contracts as cleanup
    import frozen_arc_producer_contracts as frozen

if __package__:
    from . import accepted_successor_contracts as accepted
else:
    import accepted_successor_contracts as accepted

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


@source.lexical_memo_scope()
def verify(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == guard.WINNER_SIGN_MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(record['schema'] == 1, 'unsupported migration schema')
    previous = root/'tools/carla_lane_oracle/default-query-restoration-migration.json'
    require(hashlib.sha256(previous.read_bytes()).hexdigest() ==
            record['prior_default_restoration_sha256'], 'historical restoration changed')
    text = (root/'extensions/carla/map.mojo').read_bytes().decode('utf-8')
    live_map = text
    live_map_sha256 = hashlib.sha256(text.encode()).hexdigest()
    historical_map_sha256 = record['raw_successors']['extensions/carla/map.mojo'][-1]['after']
    map_count_edge = None
    if live_map_sha256 != historical_map_sha256:
        if __package__:
            from . import seed_count_contracts as seed_count
        else:
            import seed_count_contracts as seed_count
        require(live_map_sha256 in {seed_count.AFTER_SHA256, seed_count.OPTIONAL_AFTER_SHA256,
                                      seed_count.SUPPORT_AFTER_SHA256,
                                      seed_count.FRONTIER_AFTER_SHA256, seed_count.SCORE_AFTER_SHA256},
                'unreviewed complete Map source')
        map_count_edge = seed_count.verify(root)
        require(map_count_edge is not None
                and map_count_edge['before_sha256'] == historical_map_sha256
                and map_count_edge['after_sha256'] == live_map_sha256,
                'Map count edge does not extend the historical winner source')
        text = seed_count.historical_source(root)
    require(hashlib.sha256(text.encode()).hexdigest() == historical_map_sha256,
            'unreviewed historical Map reconstruction')
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
    if __package__:
        from . import coverage_followup_contracts as followup
    else:
        import coverage_followup_contracts as followup
    for path, transition in followup.verify(root)['sources'].items():
        if path in successors:
            require(successors[path]['after_sha256'] == transition['before_sha256'],
                    'successive source edge does not start at previous endpoint')
            successor = dict(transition)
            successor['before_sha256'] = successors[path]['before_sha256']
            successor['before_token_sha256'] = successors[path]['before_token_sha256']
            successors[path] = successor
        else:
            successors[path] = transition

    for path, transition in accepted.verify(root)['sources'].items():
        if path in successors:
            require(successors[path]['after_sha256'] == transition['before_sha256'],
                    'accepted source edge does not start at previous endpoint')
            successor = dict(transition)
            successor['before_sha256'] = successors[path]['before_sha256']
            successor['before_token_sha256'] = successors[path]['before_token_sha256']
            successors[path] = successor
        else:
            successors[path] = transition

    if __package__:
        from . import speed_parser_contracts as parser
    else:
        import speed_parser_contracts as parser
    parser_edge = parser.verify(root)
    require(parser_edge['path'] not in successors, 'duplicate speed parser edge')
    successors[parser_edge['path']] = parser_edge

    if __package__:
        from . import cache_key_contracts as cache_key
    else:
        import cache_key_contracts as cache_key
    key_edge = cache_key.verify(root)
    path = cache_key.MODULE
    require(path in successors and successors[path]['after_sha256'] == key_edge['before_sha256'],
            'cache-key edge does not start at previous endpoint')
    key_successor = dict(successors[path])
    key_successor['after_sha256'] = key_edge['after_sha256']
    key_successor['after_token_sha256'] = cache_key.AFTER_TOKEN_SHA256
    successors[path] = key_successor

    if __package__:
        from . import border_parser_contracts as border
    else:
        import border_parser_contracts as border
    border_edge = border.verify(root)
    if border_edge is not None:
        require(border.MODULE not in successors, 'duplicate border parser edge')
        successors[border.MODULE] = border_edge

    if __package__:
        from . import runtime_boundary_contracts as boundary
    else:
        import runtime_boundary_contracts as boundary
    for path, edge in boundary.verify(root).items():
        require(path not in successors, 'duplicate runtime boundary edge')
        successors[path] = edge

    if __package__:
        from . import render_actor_reuse_contracts as reuse
    else:
        import render_actor_reuse_contracts as reuse
    for path, edge in reuse.verify(root).items():
        require(path not in successors, 'duplicate render actor reuse edge')
        successors[path] = edge

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
            fresh_guard(guard.declaration(live_map, name, ()))
    seed = guard.declaration(live_map, '_try_winner_seed', ())
    room = guard.declaration(live_map, '_winner_seed_room', ())
    contains(seed, 'work._step(60)', 'fixed admission must be prepaid')
    contains(seed, 'work._step(12)', 'local-band retry must be separately prepaid')
    contains(seed, 'for level in range(8):', 'dyadic proposal depth changed')
    if map_count_edge is not None and live_map_sha256 == seed_count.SCORE_AFTER_SHA256:
        seed_count.verify_score_live(live_map)
    else:
        contains(seed, 'if _wide_point_order(point, certificate.point, query) < 0:',
                 'only strict exact point improvement can replace the incumbent')
    contains(seed, 'work.charge(0, point_work, node_cost)',
             'scalar proposal work must be charged')
    winner_followup = 'var winner_followup = len(winner.cells) + 12'
    if map_count_edge is not None and live_map_sha256 in {
            seed_count.FRONTIER_AFTER_SHA256, seed_count.SCORE_AFTER_SHA256}:
        winner_followup = 'var winner_followup = min(len(winner.cells), 16373) + 12'
    contains(room, winner_followup, 'winner continuation reserve changed')
    contains(room, 'var target_followup = target_cells + 12',
             'competitor continuation reserve changed')
    contains(room, 'var winner_units = proof_nodes + 255 + 50',
             'complete regular/tiny term reserve changed')
    contains(room, 'return target_reference <= terms_left // 50',
             'competitor term reserve changed')
    selector = guard.declaration(live_map, '_closest_lane_certificate_with_work', ('Map',))
    require('Exact lane witnesses have inconsistent dominance' not in selector,
            'reviewed redundant exact guard reappeared')
    # source_bound_helpers counts the four immutable historical seed helpers.
    # Report the separately bound numerical extraction without rewriting that count.
    return {'status': 'PASS', 'source_bound_helpers': 4,
            'numerical_score_helpers': int(map_count_edge is not None and
                                          live_map_sha256 == seed_count.SCORE_AFTER_SHA256),
            'fresh_environment_entries': 2, 'changed_map_dependency_groups': 3,
            'canonical_dependencies_unchanged': len(record['canonical_source_unchanged']) - len(successors),
            'reviewed_cleanup_successors': len(successors),
            'map_count_successor': map_count_edge, 'map_source_sha256': live_map_sha256,
            'native_qualification_claimed': False}
