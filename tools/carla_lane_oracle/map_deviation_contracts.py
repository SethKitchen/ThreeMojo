# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""The exact per-segment curve deviation edge (#685, item 1), below the Map proof graph.

This leaf uses only the existing lexer, the station leaf and the standard
library. Its fixed inverse reconstructs the complete station endpoint
(#302). It grants no root admission: callers own physical observations,
tests, final rereads and receipts.

The edge stores each segment's certified full-curve deviation, the value
whose maximum the map already keeps as `_curve_deviation`. The certified
query keeps the global early stop. After that stop, it skips a candidate
whose own lower bound is strictly greater than the incumbent's upper radius.
The skip comes before candidate admission, refinement and any append, as the
existing box and cover skips do. A skipped candidate's exact distance is
greater than the distance of an actual stored witness, so it can never win or
tie. Work counters, budgets, seed scores, floating-point guards and the
retained competitor set of every admitted candidate are unchanged. Native
qualification of the bound test is a separate requirement.
"""
import hashlib
import sys

if __package__:
    from . import source_contracts as source
    from . import map_station_contracts as station
else:
    import source_contracts as source
    import map_station_contracts as station

_EXECUTED_MODULE_CODE = sys._getframe().f_code

MODULE = 'extensions/carla/map.mojo'
BEFORE_SHA256 = '96611c1a85a89720cf739404924005aad4408e6868e1058f724675a6ad58630e'
AFTER_SHA256 = '0e2d282fcd6c70217e7413b7febe40619af070f7adbeaefa3fd56d95562c404b'
BEFORE_TOKEN_SHA256 = '2d93f5be33becf4f2e6476a88b8e222119a408a3fea13684b5161347395e5cfd'
AFTER_TOKEN_SHA256 = '8e900de7c4c82cba9ced3e09fa2360e39d1474f0a715d2bebf1ebc1603bd9977'
EDITS = (('deviation_span_1',
  'struct _Segment(ImplicitlyCopyable):\n'
  '    var start: Vector3\n'
  '    var end: Vector3\n'
  '    var first: Waypoint\n'
  '    var second: Waypoint\n'
  '    var bounds: Tuple[_Interval, _Interval, _Interval]\n'
  '    # -1 means the optional construction proof is absent.\n'
  '    var cover_index: Int\n'
  '\n'
  '\n'
  '@fieldwise_init\n'
  'struct _CarlaSegment',
  'struct _Segment(ImplicitlyCopyable):\n'
  '    var start: Vector3\n'
  '    var end: Vector3\n'
  '    var first: Waypoint\n'
  '    var second: Waypoint\n'
  '    var bounds: Tuple[_Interval, _Interval, _Interval]\n'
  '    # -1 means the optional construction proof is absent.\n'
  '    var cover_index: Int\n'
  "    # This segment's certified full-curve distance to its stored chord. The\n"
  "    # map's `_curve_deviation` is the maximum over every segment (#685).\n"
  '    var deviation: Float64\n'
  '\n'
  '\n'
  '@fieldwise_init\n'
  'struct _CarlaSegment'),
 ('deviation_span_2',
  '            ref segment = self._segments[index]\n'
  '            if best >= 0:\n'
  '                var lower = _indexed_curve_lower(\n'
  '                    _segment_distance2(segment.start, segment.end, location),\n'
  '                    self._curve_deviation,\n'
  '                )\n'
  '                if lower > best_radius:\n'
  '                    break\n',
  '            ref segment = self._segments[index]\n'
  '            if best >= 0:\n'
  '                var key = _segment_distance2(\n'
  '                    segment.start, segment.end, location\n'
  '                )\n'
  '                var lower = _indexed_curve_lower(key, self._curve_deviation)\n'
  '                if lower > best_radius:\n'
  '                    break\n'
  '                # The index orders keys only, so the walk keeps the global\n'
  "                # stop. This candidate's own deviation can still exclude it.\n"
  '                if _indexed_curve_lower(key, segment.deviation) > best_radius:\n'
  '                    continue\n'),
 ('deviation_span_3',
  '                certificate[1],\n'
  '                cover_index,\n'
  '            )\n'
  '        )\n'
  '        self._curve_deviation = max(self._curve_deviation, certificate[0])\n',
  '                certificate[1],\n'
  '                cover_index,\n'
  '                certificate[0],\n'
  '            )\n'
  '        )\n'
  '        self._curve_deviation = max(self._curve_deviation, certificate[0])\n'))
DECLARATIONS = (('_closest_lane_certificate_with_work',
  ('Map',),
  '1614e264cd2291fc2e81b01eedaa9828d2d36719725f63718b9cfeed07f5db90'),
 ('_subdivide_segment',
  ('Map',),
  '49d94bf475d0065237818a40aac3172fb999186c78cbfb53c2eee0ec14da259f'))
TESTS = {'tests/test_carla_segment_deviation.mojo': '26e275b0d31bed176f0b3df08c1b4d5a92812f0fba363af24a7e39a65fd05614'}
ROUTING_SHA256 = 'f4accdcff29b092eccc8bc2416596f9b70f2bb6b71344decd88d66ab1734536d'


def require(value, message):
    if not value:
        raise ValueError('reviewed Map deviation successor: ' + message)


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def verify_live(text):
    """Bind the actual query and segment builder before any inverse."""
    for name, owner, expected in DECLARATIONS:
        require(source.token_sha256(station.declaration(text, name, owner)) == expected,
                'live query/builder changed: ' + name)


def predecessor_source(text):
    """Reverse only this complete endpoint through three unique exact spans."""
    require(sha(text) == AFTER_SHA256 and source.token_sha256(text) == AFTER_TOKEN_SHA256,
            'unknown complete deviation endpoint')
    verify_live(text)
    require(tuple(item[0] for item in EDITS) == tuple('deviation_span_' + str(i) for i in range(1, 4)),
            'deviation inverse inventory changed')
    for name, before, after in reversed(EDITS):
        require(bool(before) and bool(after) and text.count(after) == 1,
                'missing or ambiguous deviation inverse: ' + name)
        text = text.replace(after, before, 1)
    require(sha(text) == BEFORE_SHA256 and source.token_sha256(text) == BEFORE_TOKEN_SHA256,
            'deviation inverse does not reconstruct the station endpoint')
    return text


def station_source(text):
    """Return the station endpoint for either reviewed physical Map endpoint."""
    return predecessor_source(text) if sha(text) == AFTER_SHA256 else text


def edge():
    """Describe the fixed edge; this descriptor is never an admission token."""
    return {'path': MODULE, 'before_sha256': BEFORE_SHA256, 'after_sha256': AFTER_SHA256,
            'before_token_sha256': BEFORE_TOKEN_SHA256, 'after_token_sha256': AFTER_TOKEN_SHA256}
