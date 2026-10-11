# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""The exact default-query station edge (#302), below the Map proof graph.

This leaf uses only the existing lexer and the standard library. Its fixed
inverse reconstructs the complete fifth seed endpoint. It grants no root
admission: callers own physical observations, tests, final rereads and receipts.
The certified search, seed score, floating-point guards and debits are unchanged.
Native qualification of the bound tests is a separate requirement.
"""
import hashlib
import sys
import textwrap
import tokenize

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

_EXECUTED_MODULE_CODE = sys._getframe().f_code

MODULE = 'extensions/carla/map.mojo'
BEFORE_SHA256 = '70ec94630e2530e9389fdb6388ff4c139bb268f5549f1a9f06602b6dfebecb94'
AFTER_SHA256 = '96611c1a85a89720cf739404924005aad4408e6868e1058f724675a6ad58630e'
BEFORE_TOKEN_SHA256 = '56e9801cd0b87c07b67ff96286cac37ef621cee7c2967fb16bd979c1f6981b06'
AFTER_TOKEN_SHA256 = '2d93f5be33becf4f2e6476a88b8e222119a408a3fea13684b5161347395e5cfd'
EDITS = (('station_span_1',
  "the sign check at load use it with CARLA's algorithm: the nearest segment,\n"
  "then a step along the lane to the point's foot. These queries do not use\n"
  'the certified search budget. Input validation, lane stepping and canonical\n'
  "pose evaluation can still raise errors. They keep CARLA's approximations:\n"
  'the step treats distance along the segment chord as road s.\n'
  '\n'
  '**The certified index.** `certified_closest_waypoint_on_road` and\n'
  "`certified_waypoint` use a second index. It starts with CARLA's partition\n",
  "the sign check at load use it with CARLA's algorithm: the nearest segment,\n"
  "then a step along the lane to the point's foot. These queries do not use\n"
  'the certified search budget. Input validation, lane stepping and canonical\n'
  "pose evaluation can still raise errors. They keep CARLA's partition, but\n"
  'they correct one CARLA approximation. CARLA steps by the plan distance along\n'
  'the segment chord, as if it were road s. A lane offset, a lane width or a\n'
  'curve can make the chord longer or shorter than its road-s span. A sloped\n'
  "lane then misses points on its center. This port steps by the foot's plan\n"
  "fraction of the chord times the chord's road-s span (#302).\n"
  '\n'
  '**The certified index.** `certified_closest_waypoint_on_road` and\n'
  "`certified_waypoint` use a second index. It starts with CARLA's partition\n"),
 ('station_span_2',
  'The public `segment_count` and `segment` methods expose this accuracy-driven\n'
  'index. Its partition and count can change when the geometry requires more\n'
  'subdivision. Lane order and index tie rules remain deterministic. The\n'
  'certified queries correct curved lane offsets and the treatment of lane\n'
  "distance as road s. They cost more and can raise where CARLA's query\n"
  'answers, so they are not the default.\n'
  '\n'
  'The R-tree, full-center bounds, and optional sampled-curve box covers belong\n'
  'to the same construction snapshot. Queries do not update these proofs.\n',
  'The public `segment_count` and `segment` methods expose this accuracy-driven\n'
  'index. Its partition and count can change when the geometry requires more\n'
  'subdivision. Lane order and index tie rules remain deterministic. The\n'
  'certified queries also correct the chord error of curved lane offsets.\n'
  "They cost more and can raise where CARLA's query answers, so they are not\n"
  'the default.\n'
  '\n'
  'The R-tree, full-center bounds, and optional sampled-curve box covers belong\n'
  'to the same construction snapshot. Queries do not update these proofs.\n'),
 ('station_span_3',
  ')\n'
  'from extensions.carla.speed_limits import opendrive_speed, NUMERIC_SPEED_LIMIT\n'
  'from extensions.carla.math import (\n'
  '    distance_segment_to_point,\n'
  '    make_unit_vector,\n'
  '    vector_angle,\n'
  ')\n',
  ')\n'
  'from extensions.carla.speed_limits import opendrive_speed, NUMERIC_SPEED_LIMIT\n'
  'from extensions.carla.math import (\n'
  '    make_unit_vector,\n'
  '    vector_angle,\n'
  ')\n'),
 ('station_span_4',
  '    )\n\n\n# --- the map ------------------------------------------------------------------\n\n\n',
  '    )\n'
  '\n'
  '\n'
  'def _chord_station_delta(\n'
  '    location: Vector3, start: Vector3, end: Vector3, span: Float64\n'
  ') -> Float64:\n'
  "    # The default query's step along the lane, in road s. CARLA steps by the\n"
  '    # plan distance along the chord (`Math::DistanceSegmentToPoint`). That\n'
  '    # distance is not road s when a lane offset, a lane width or a curve\n'
  "    # changes the lane's plan speed (#302). This uses the foot's plan\n"
  "    # fraction of the chord times the chord's road-s span instead. Float64\n"
  '    # holds the square of any finite Float32 chord. A nonfinite chord gives\n'
  '    # NaN, which the callers refuse or return as before.\n'
  '    var dx = Float64(end.x) - Float64(start.x)\n'
  '    var dy = Float64(end.y) - Float64(start.y)\n'
  '    var l2 = dx * dx + dy * dy\n'
  '    if l2 == 0.0:\n'
  '        return 0.0\n'
  '    var px = Float64(location.x) - Float64(start.x)\n'
  '    var py = Float64(location.y) - Float64(start.y)\n'
  '    var t = (px * dx + py * dy) / l2\n'
  '    # Clamp without min and max, so that a NaN fraction stays NaN.\n'
  '    if t < 0.0:\n'
  '        t = 0.0\n'
  '    elif t > 1.0:\n'
  '        t = 1.0\n'
  '    return t * span\n'
  '\n'
  '\n'
  '# --- the map ------------------------------------------------------------------\n'
  '\n'
  '\n'),
 ('station_span_5',
  '        """Return the waypoint nearest a point, `GetClosestWaypointOnRoad`.\n'
  '\n'
  '        CARLA finds the nearest segment of a lane of the given types, then\n'
  "        steps from the segment's start by the distance along it to the\n"
  "        point's foot. The segments are CARLA's heading and length partition.\n"
  '        For the certified nearest center, use\n'
  '        `certified_closest_waypoint_on_road`.\n'
  '\n',
  '        """Return the waypoint nearest a point, `GetClosestWaypointOnRoad`.\n'
  '\n'
  '        CARLA finds the nearest segment of a lane of the given types, then\n'
  "        steps from the segment's start toward the point's foot. The step is\n"
  "        the foot's plan fraction of the segment times the segment's road-s\n"
  '        span. CARLA steps by the plan distance itself; that is not road s\n'
  '        on a lane with a sloped or curved offset (#302). The segments are\n'
  "        CARLA's heading and length partition.\n"
  '        For the certified nearest center, use\n'
  '        `certified_closest_waypoint_on_road`.\n'
  '\n'),
 ('station_span_6',
  '        if len(found) == 0:\n'
  '            return None\n'
  '        ref segment = self._carla_segments[found[0].start_value]\n'
  '        var along = distance_segment_to_point(\n'
  '            location, segment.start, segment.end\n'
  '        )\n'
  '        var start = segment.first\n'
  '        var end = segment.second\n'
  '        var delta = Float64(along[0].value)\n'
  '        var forward = self.is_positive_direction(start)\n'
  '        var final_s = start.s + delta if forward else start.s - delta\n'
  '        var past = final_s >= end.s if forward else final_s <= end.s\n',
  '        if len(found) == 0:\n'
  '            return None\n'
  '        ref segment = self._carla_segments[found[0].start_value]\n'
  '        var start = segment.first\n'
  '        var end = segment.second\n'
  '        var delta = _chord_station_delta(\n'
  '            location, segment.start, segment.end, abs(end.s - start.s)\n'
  '        )\n'
  '        var forward = self.is_positive_direction(start)\n'
  '        var final_s = start.s + delta if forward else start.s - delta\n'
  '        var past = final_s >= end.s if forward else final_s <= end.s\n'),
 ('station_span_7',
  '            raise Error(\n'
  '                "CARLA query segment must stay in one finite lane section"\n'
  '            )\n'
  '        var along = distance_segment_to_point(\n'
  '            location, segment.start, segment.end\n'
  '        )\n'
  '        var delta = Float64(along[0].value)\n'
  '        # The default query resolves this metadata twice (direction and\n'
  '        # next). Reuse the same checked location and preserve its arithmetic.\n'
  '        var at = self._locate_with_work(start, work)\n',
  '            raise Error(\n'
  '                "CARLA query segment must stay in one finite lane section"\n'
  '            )\n'
  '        var delta = _chord_station_delta(\n'
  '            location, segment.start, segment.end, abs(end.s - start.s)\n'
  '        )\n'
  '        # The default query resolves this metadata twice (direction and\n'
  '        # next). Reuse the same checked location and preserve its arithmetic.\n'
  '        var at = self._locate_with_work(start, work)\n'))
DECLARATIONS = (('_chord_station_delta', (), '5088d8bc20c4e64354c0f8d8f38b76faf46667020262e6a97fa56f6b271ee6b3'),
 ('closest_waypoint_on_road', ('Map',), '10b7e8e8bad30eeb8fa417db013c9029392e9297c27b4df022b8fc611843edb4'),
 ('_closest_lane_with_build_work',
  ('Map',),
  '14fc1616d247a2710aaf5b5dcf1a8b1015daa8ac852cec1960d06d525ae87c02'))
TESTS = {'tests/test_carla_map.mojo': '001c8d5b8ee66eadc936c79ebe373824fe27240e19f0171f3415b2628a06430c',
 'tests/test_carla_offset_lane_station.mojo': '1fcb4f63566db96ca7c17f7c2b83b1963ca11f51c9c6013846f0d910b6545984',
 'tests/test_carla_sign_query_accounting.mojo': '1aa54a95ed460aec6c04eb4e88b838b4264acf5479ca1b6665375895a3338c2f',
 'tests/test_carla_waypoint_stations.mojo': '7e2f1d9029833c42c7a078e1943f52502b1d2629500fbf6ed2744f42560db5ce'}
ROUTING_SHA256 = '29bdf4685cae38a45cf84bc06b60535927cbf992ae36dd563b3d3f00cce68d09'


def require(value, message):
    if not value:
        raise ValueError('reviewed Map station successor: ' + message)


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def declaration(text, name, owner):
    """Select one complete definition at its exact lexical owner, uncached."""
    tokens = source.tokens(text)
    scopes, statement, found = [], [], []
    pending = None
    for index, token in enumerate(tokens):
        if token.type == tokenize.INDENT:
            scopes.append(pending or ('block', ''))
            pending = None
        elif token.type == tokenize.DEDENT:
            require(bool(scopes), 'unmatched lexical owner')
            scopes.pop()
        elif token.type == tokenize.NEWLINE:
            words = [item.string for item in statement]
            if len(words) >= 2 and words[:2] == ['def', name]:
                found.append((tuple(scopes), statement[0].start[0]-1, index+1))
            if words and words[-1] == ':':
                pending = ((words[0], words[1]) if len(words) >= 2 and
                           words[0] in ('def', 'struct', 'trait', 'class')
                           else ('block', ''))
            else:
                pending = None
            statement = []
        elif token.type not in (tokenize.COMMENT, tokenize.NL, tokenize.ENDMARKER):
            statement.append(token)
    require(not scopes and not statement, 'incomplete lexical owner')
    require(len(found) == 1 and found[0][0] == tuple(('struct', part) for part in owner),
            'missing or ambiguous scoped declaration: ' + name)
    _, first, index = found[0]
    while index < len(tokens) and tokens[index].type in (tokenize.COMMENT, tokenize.NL):
        index += 1
    require(index < len(tokens) and tokens[index].type == tokenize.INDENT,
            'missing declaration body: ' + name)
    depth = 1
    index += 1
    while index < len(tokens) and depth:
        depth += int(tokens[index].type == tokenize.INDENT)
        depth -= int(tokens[index].type == tokenize.DEDENT)
        index += 1
    require(depth == 0, 'incomplete declaration: ' + name)
    last = tokens[index-1].start[0]-1
    return textwrap.dedent(''.join(text.splitlines(keepends=True)[first:last]))


def verify_live(text):
    """Bind the actual helper and both entire callers before any inverse."""
    for name, owner, expected in DECLARATIONS:
        require(source.token_sha256(declaration(text, name, owner)) == expected,
                'live helper/caller changed: ' + name)


def predecessor_source(text):
    """Reverse only this complete endpoint through seven unique exact spans."""
    require(sha(text) == AFTER_SHA256 and source.token_sha256(text) == AFTER_TOKEN_SHA256,
            'unknown complete station endpoint')
    verify_live(text)
    require(tuple(item[0] for item in EDITS) == tuple('station_span_' + str(i) for i in range(1, 8)),
            'station inverse inventory changed')
    for name, before, after in reversed(EDITS):
        require(bool(before) and bool(after) and text.count(after) == 1,
                'missing or ambiguous station inverse: ' + name)
        text = text.replace(after, before, 1)
    require(sha(text) == BEFORE_SHA256 and source.token_sha256(text) == BEFORE_TOKEN_SHA256,
            'station inverse does not reconstruct fifth seed endpoint')
    return text


def edge():
    """Describe the fixed edge; this descriptor is never an admission token."""
    return {'path': MODULE, 'before_sha256': BEFORE_SHA256, 'after_sha256': AFTER_SHA256,
            'before_token_sha256': BEFORE_TOKEN_SHA256, 'after_token_sha256': AFTER_TOKEN_SHA256}
