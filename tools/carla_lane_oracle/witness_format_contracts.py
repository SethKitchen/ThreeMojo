# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Four exact formatter-only native witness edges, below source admission.

This pure leaf never reads a root or grants a receipt. It reconstructs the
unchanged historical witness bytes and checks lexical equivalence of the
four enumerated endpoints. Physical ownership, path/resolver refusal and
final rereads stay in full_audit_cleanup_contracts. No math edge is admitted.
"""
import ast
import hashlib
import json
import sys
import tokenize

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

_EXECUTED_MODULE_CODE = sys._getframe().f_code

SOURCE_PATHS = ('tests/test_carla_chord_endpoint_refusals.mojo',
 'tests/test_carla_junction_endpoint_refusals.mojo',
 'tests/test_carla_speed_parser_exceptions.mojo',
 'tests/test_carla_width_overflow_admission.mojo')
BEFORE_SHA256 = {'tests/test_carla_chord_endpoint_refusals.mojo': '46a5a86a35348024e05c1806016e82f15366b2bfd348e35b3732be30c050aa9f',
 'tests/test_carla_junction_endpoint_refusals.mojo': '8be215d8f87cae1a271a6f040573f4b85f475e99fc91346d7fdbe369ecf3f800',
 'tests/test_carla_speed_parser_exceptions.mojo': '563606f7f879c80ebe150055ddbd54ae6507983d5fe2d1ac41f962cbba4c9630',
 'tests/test_carla_width_overflow_admission.mojo': '0e96b3b91614bb4266c35372e17ce0da2a42d83e17fa413f6fa3a2e1f8eaec2a'}
AFTER_SHA256 = {'tests/test_carla_chord_endpoint_refusals.mojo': 'bcf738095dfa6001801dc5a40c75844fcf1ab04d8cfa673419e39984b717fbe0',
 'tests/test_carla_junction_endpoint_refusals.mojo': '73b2b5ef0ecced0d6377b929c5a076f64db78ba245ba2ad580e04e3e433f6077',
 'tests/test_carla_speed_parser_exceptions.mojo': '46ef2fd18fde1f532f06b0027b317f96a3e5f3f2260ddcb7b266f1fe9d58731b',
 'tests/test_carla_width_overflow_admission.mojo': 'f90e73f4ccb3581a112e0f38e6a4a39fc9fadac0c3688fb97087b576bddd0a42'}
BEFORE_TOKEN_SHA256 = {'tests/test_carla_chord_endpoint_refusals.mojo': 'd8db9bd1c144b4429d71ada6d94978401f15e9c80c1fe173b33865a92a95bbc6',
 'tests/test_carla_junction_endpoint_refusals.mojo': 'd94c0e922f5095064406052594be1e11c336641c55c2ea6f0ce11dd5ebc006cd',
 'tests/test_carla_speed_parser_exceptions.mojo': 'b0f6e5f0b020eeef862a73be8bc5febb3a92243a81ffff8bacf5bcc1b7a3bda9',
 'tests/test_carla_width_overflow_admission.mojo': '2d60ab6b1c157b4b3fa04e1d88886a41c0021015e3755114b1ec3823bce1560b'}
AFTER_TOKEN_SHA256 = {'tests/test_carla_chord_endpoint_refusals.mojo': '8670f1dd41e37b0eebfb5c5ddef8e984e6a8d22d4b99b0377bb2e2e2cd42e280',
 'tests/test_carla_junction_endpoint_refusals.mojo': '46c0712165500862388226da86d82f8da1c52da62f4817cdd966fe37a2b8ebd1',
 'tests/test_carla_speed_parser_exceptions.mojo': 'e5005d4bd15a6074ea9d73bca08039ecf1a94567903a06b7141512e180a71132',
 'tests/test_carla_width_overflow_admission.mojo': '498b3bfd881603a6315e0c508f2448eae08120ba8d4fe679ec182c72fa54c725'}
EDITS = {'tests/test_carla_chord_endpoint_refusals.mojo': (('1',
                                                    '"""Real-road endpoint refusals under the '
                                                    'original bounded coarse-box path."""\n'
                                                    'from extensions.carla.curve_bounds import '
                                                    '_reference_work\n'
                                                    'from extensions.carla.geometry import LINE, '
                                                    'SPIRAL, RoadGeometry\n'
                                                    'from extensions.carla.lane_refinement import '
                                                    '_ProofNodeWork, '
                                                    '_chord_certificate_capture_with_nodes\n'
                                                    'from extensions.carla.map_search import '
                                                    'MapBuildBudget, _MapBuildWork\n'
                                                    'from extensions.carla.map_validation import '
                                                    '_preflight_road_records\n'
                                                    'from extensions.carla.polynomial import '
                                                    'CubicPolynomial\n'
                                                    'from extensions.carla.road import Road\n'
                                                    'from extensions.carla.road_info import '
                                                    'LANE_DRIVING, NO_JUNCTION, LaneId, RoadId, '
                                                    'RoadInfoElevation, RoadInfoGeometry, '
                                                    'RoadInfoLaneOffset, RoadInfoLaneWidth, '
                                                    'SectionId\n'
                                                    'from extensions.carla.spiral_domain_proof '
                                                    'import _SpiralRootCapture\n'
                                                    'from math.vector3 import Vector3\n'
                                                    'from std.math import inf\n',
                                                    '"""Real-road endpoint refusals under the '
                                                    'original bounded coarse-box path."""\n'
                                                    'from extensions.carla.curve_bounds import '
                                                    '_reference_work\n'
                                                    'from extensions.carla.geometry import LINE, '
                                                    'SPIRAL, RoadGeometry\n'
                                                    'from extensions.carla.lane_refinement import '
                                                    '(\n'
                                                    '    _ProofNodeWork,\n'
                                                    '    _chord_certificate_capture_with_nodes,\n'
                                                    ')\n'
                                                    'from extensions.carla.map_search import '
                                                    'MapBuildBudget, _MapBuildWork\n'
                                                    'from extensions.carla.map_validation import '
                                                    '_preflight_road_records\n'
                                                    'from extensions.carla.polynomial import '
                                                    'CubicPolynomial\n'
                                                    'from extensions.carla.road import Road\n'
                                                    'from extensions.carla.road_info import (\n'
                                                    '    LANE_DRIVING,\n'
                                                    '    NO_JUNCTION,\n'
                                                    '    LaneId,\n'
                                                    '    RoadId,\n'
                                                    '    RoadInfoElevation,\n'
                                                    '    RoadInfoGeometry,\n'
                                                    '    RoadInfoLaneOffset,\n'
                                                    '    RoadInfoLaneWidth,\n'
                                                    '    SectionId,\n'
                                                    ')\n'
                                                    'from extensions.carla.spiral_domain_proof '
                                                    'import _SpiralRootCapture\n'
                                                    'from math.vector3 import Vector3\n'
                                                    'from std.math import inf\n'),
                                                   ('2',
                                                    '\n'
                                                    '\n'
                                                    'def _road(first_refuses: Bool, last_refuses: '
                                                    'Bool) raises -> Road:\n'
                                                    '    var road = Road(RoadId(1), "bounded '
                                                    'endpoint preflight", 4.0, NO_JUNCTION, '
                                                    'RoadId(0), RoadId(0), True)\n'
                                                    '    _ = road.add_section(SectionId(0), 0.0)\n'
                                                    '    _ = '
                                                    'road.sections[0].add_lane(LaneId(-1))\n'
                                                    '    road.sections[0].lanes[0].type = '
                                                    'LANE_DRIVING\n'
                                                    '    '
                                                    'road.sections[0].lanes[0].info.widths.append(RoadInfoLaneWidth(0.0, '
                                                    'CubicPolynomial.constant(2.0)))\n'
                                                    '    '
                                                    'road.info.elevations.append(RoadInfoElevation(0.0, '
                                                    'CubicPolynomial.constant(0.0)))\n'
                                                    '    '
                                                    'road.info.lane_offsets.append(RoadInfoLaneOffset(0.0, '
                                                    'CubicPolynomial.constant(1.0)))\n'
                                                    '    var first = RoadGeometry(SPIRAL if '
                                                    'first_refuses else LINE, 0, 0, 0, 0, 2)\n'
                                                    '    first.curvature_start = 2e9\n'
                                                    '    first.curvature_end = 2e9\n',
                                                    '\n'
                                                    '\n'
                                                    'def _road(first_refuses: Bool, last_refuses: '
                                                    'Bool) raises -> Road:\n'
                                                    '    var road = Road(\n'
                                                    '        RoadId(1),\n'
                                                    '        "bounded endpoint preflight",\n'
                                                    '        4.0,\n'
                                                    '        NO_JUNCTION,\n'
                                                    '        RoadId(0),\n'
                                                    '        RoadId(0),\n'
                                                    '        True,\n'
                                                    '    )\n'
                                                    '    _ = road.add_section(SectionId(0), 0.0)\n'
                                                    '    _ = '
                                                    'road.sections[0].add_lane(LaneId(-1))\n'
                                                    '    road.sections[0].lanes[0].type = '
                                                    'LANE_DRIVING\n'
                                                    '    '
                                                    'road.sections[0].lanes[0].info.widths.append(\n'
                                                    '        RoadInfoLaneWidth(0.0, '
                                                    'CubicPolynomial.constant(2.0))\n'
                                                    '    )\n'
                                                    '    road.info.elevations.append(\n'
                                                    '        RoadInfoElevation(0.0, '
                                                    'CubicPolynomial.constant(0.0))\n'
                                                    '    )\n'
                                                    '    road.info.lane_offsets.append(\n'
                                                    '        RoadInfoLaneOffset(0.0, '
                                                    'CubicPolynomial.constant(1.0))\n'
                                                    '    )\n'
                                                    '    var first = RoadGeometry(SPIRAL if '
                                                    'first_refuses else LINE, 0, 0, 0, 0, 2)\n'
                                                    '    first.curvature_start = 2e9\n'
                                                    '    first.curvature_end = 2e9\n'),
                                                   ('3',
                                                    '    # either child before traversal. The '
                                                    'standard 2-million-term cap stays.\n'
                                                    '    var nodes = _ProofNodeWork(1, '
                                                    'fail_on_limit=False)\n'
                                                    '    var captured = _SpiralRootCapture()\n'
                                                    '    var result = '
                                                    '_chord_certificate_capture_with_nodes(road, '
                                                    '0, 0, 1.0, 3.0, Vector3(1, 0, 0), Vector3(3, '
                                                    '0, 0), captured, nodes)\n'
                                                    '    assert_equal(result[0], '
                                                    'inf[DType.float64]())\n'
                                                    '    for value in [result[1][0], result[1][1], '
                                                    'result[1][2]]:\n'
                                                    '        assert_equal(value.low, '
                                                    '-inf[DType.float64]())\n',
                                                    '    # either child before traversal. The '
                                                    'standard 2-million-term cap stays.\n'
                                                    '    var nodes = _ProofNodeWork(1, '
                                                    'fail_on_limit=False)\n'
                                                    '    var captured = _SpiralRootCapture()\n'
                                                    '    var result = '
                                                    '_chord_certificate_capture_with_nodes(\n'
                                                    '        road,\n'
                                                    '        0,\n'
                                                    '        0,\n'
                                                    '        1.0,\n'
                                                    '        3.0,\n'
                                                    '        Vector3(1, 0, 0),\n'
                                                    '        Vector3(3, 0, 0),\n'
                                                    '        captured,\n'
                                                    '        nodes,\n'
                                                    '    )\n'
                                                    '    assert_equal(result[0], '
                                                    'inf[DType.float64]())\n'
                                                    '    for value in [result[1][0], result[1][1], '
                                                    'result[1][2]]:\n'
                                                    '        assert_equal(value.low, '
                                                    '-inf[DType.float64]())\n')),
 'tests/test_carla_junction_endpoint_refusals.mojo': (('1',
                                                       'from extensions.carla.map_validation '
                                                       'import _preflight_road_records\n'
                                                       'from extensions.carla.polynomial import '
                                                       'CubicPolynomial\n'
                                                       'from extensions.carla.road import Road\n'
                                                       'from extensions.carla.road_info import '
                                                       'LANE_DRIVING, NO_JUNCTION, LaneId, RoadId, '
                                                       'RoadInfoElevation, RoadInfoGeometry, '
                                                       'RoadInfoLaneOffset, RoadInfoLaneWidth, '
                                                       'SectionId\n'
                                                       'from math.bounds import Box3\n'
                                                       'from math.vector3 import Vector3\n'
                                                       'from std.ffi import external_call\n'
                                                       'from std.memory import bitcast\n'
                                                       'from std.testing import TestSuite, '
                                                       'assert_equal, assert_false, assert_true, '
                                                       'assert_raises\n'
                                                       '\n'
                                                       '\n'
                                                       'def _first_road() raises -> Road:\n',
                                                       'from extensions.carla.map_validation '
                                                       'import _preflight_road_records\n'
                                                       'from extensions.carla.polynomial import '
                                                       'CubicPolynomial\n'
                                                       'from extensions.carla.road import Road\n'
                                                       'from extensions.carla.road_info import (\n'
                                                       '    LANE_DRIVING,\n'
                                                       '    NO_JUNCTION,\n'
                                                       '    LaneId,\n'
                                                       '    RoadId,\n'
                                                       '    RoadInfoElevation,\n'
                                                       '    RoadInfoGeometry,\n'
                                                       '    RoadInfoLaneOffset,\n'
                                                       '    RoadInfoLaneWidth,\n'
                                                       '    SectionId,\n'
                                                       ')\n'
                                                       'from math.bounds import Box3\n'
                                                       'from math.vector3 import Vector3\n'
                                                       'from std.ffi import external_call\n'
                                                       'from std.memory import bitcast\n'
                                                       'from std.testing import (\n'
                                                       '    TestSuite,\n'
                                                       '    assert_equal,\n'
                                                       '    assert_false,\n'
                                                       '    assert_true,\n'
                                                       '    assert_raises,\n'
                                                       ')\n'
                                                       '\n'
                                                       '\n'
                                                       'def _first_road() raises -> Road:\n'),
                                                      ('2',
                                                       '    var geometry = RoadGeometry(SPIRAL, 0, '
                                                       '0, 0, 0, 2)\n'
                                                       '    geometry.curvature_start = curvature\n'
                                                       '    geometry.curvature_end = curvature\n'
                                                       '    var road = Road(RoadId(1), "direct '
                                                       'junction helper refusal", 2.0, '
                                                       'NO_JUNCTION, RoadId(0), RoadId(0), True)\n'
                                                       '    _ = road.add_section(SectionId(0), '
                                                       '0.0)\n'
                                                       '    _ = '
                                                       'road.sections[0].add_lane(LaneId(-1))\n'
                                                       '    road.sections[0].lanes[0].type = '
                                                       'LANE_DRIVING\n'
                                                       '    '
                                                       'road.sections[0].lanes[0].info.widths.append(RoadInfoLaneWidth(-1.0, '
                                                       'CubicPolynomial.constant(2.0)))\n'
                                                       '    '
                                                       'road.info.geometries.append(RoadInfoGeometry(-1.0, '
                                                       'geometry^))\n'
                                                       '    '
                                                       'road.info.elevations.append(RoadInfoElevation(-1.0, '
                                                       'CubicPolynomial(2.0, 1.0, 0.0, 0.0, '
                                                       '0.0)))\n'
                                                       '    '
                                                       'road.info.lane_offsets.append(RoadInfoLaneOffset(-1.0, '
                                                       'CubicPolynomial.constant(1.0)))\n'
                                                       '    var validation = '
                                                       '_MapBuildWork(MapBuildBudget())\n'
                                                       '    _preflight_road_records(road, '
                                                       'validation)\n'
                                                       '    assert_false(validation.exhausted)\n',
                                                       '    var geometry = RoadGeometry(SPIRAL, 0, '
                                                       '0, 0, 0, 2)\n'
                                                       '    geometry.curvature_start = curvature\n'
                                                       '    geometry.curvature_end = curvature\n'
                                                       '    var road = Road(\n'
                                                       '        RoadId(1),\n'
                                                       '        "direct junction helper refusal",\n'
                                                       '        2.0,\n'
                                                       '        NO_JUNCTION,\n'
                                                       '        RoadId(0),\n'
                                                       '        RoadId(0),\n'
                                                       '        True,\n'
                                                       '    )\n'
                                                       '    _ = road.add_section(SectionId(0), '
                                                       '0.0)\n'
                                                       '    _ = '
                                                       'road.sections[0].add_lane(LaneId(-1))\n'
                                                       '    road.sections[0].lanes[0].type = '
                                                       'LANE_DRIVING\n'
                                                       '    '
                                                       'road.sections[0].lanes[0].info.widths.append(\n'
                                                       '        RoadInfoLaneWidth(-1.0, '
                                                       'CubicPolynomial.constant(2.0))\n'
                                                       '    )\n'
                                                       '    '
                                                       'road.info.geometries.append(RoadInfoGeometry(-1.0, '
                                                       'geometry^))\n'
                                                       '    road.info.elevations.append(\n'
                                                       '        RoadInfoElevation(-1.0, '
                                                       'CubicPolynomial(2.0, 1.0, 0.0, 0.0, 0.0))\n'
                                                       '    )\n'
                                                       '    road.info.lane_offsets.append(\n'
                                                       '        RoadInfoLaneOffset(-1.0, '
                                                       'CubicPolynomial.constant(1.0))\n'
                                                       '    )\n'
                                                       '    var validation = '
                                                       '_MapBuildWork(MapBuildBudget())\n'
                                                       '    _preflight_road_records(road, '
                                                       'validation)\n'
                                                       '    assert_false(validation.exhausted)\n'),
                                                      ('3',
                                                       '\n'
                                                       'def _same(one: _Interval, two: _Interval) '
                                                       'raises:\n'
                                                       '    '
                                                       'assert_equal(bitcast[DType.uint64](one.low), '
                                                       'bitcast[DType.uint64](two.low))\n'
                                                       '    '
                                                       'assert_equal(bitcast[DType.uint64](one.high), '
                                                       'bitcast[DType.uint64](two.high))\n'
                                                       '\n'
                                                       '\n'
                                                       'def _first_endpoint_control() raises:\n',
                                                       '\n'
                                                       'def _same(one: _Interval, two: _Interval) '
                                                       'raises:\n'
                                                       '    '
                                                       'assert_equal(bitcast[DType.uint64](one.low), '
                                                       'bitcast[DType.uint64](two.low))\n'
                                                       '    assert_equal(\n'
                                                       '        bitcast[DType.uint64](one.high), '
                                                       'bitcast[DType.uint64](two.high)\n'
                                                       '    )\n'
                                                       '\n'
                                                       '\n'
                                                       'def _first_endpoint_control() raises:\n'),
                                                      ('4',
                                                       '        assert_true(z.is_finite())\n'
                                                       '        assert_true(z.low < 2.0 or z.high '
                                                       '> 2.0)\n'
                                                       '        var work = '
                                                       '_MapBuildWork(MapBuildBudget(0, 5, terms, '
                                                       '0))\n'
                                                       '        var result = '
                                                       '_monotone_junction_enclosure(road, 0, 0, '
                                                       'low, high, terms, proposal, x, y, z, '
                                                       'work)\n'
                                                       '        _same(result[0], x)\n'
                                                       '        _same(result[1], y)\n'
                                                       '        _same(result[2], z)\n',
                                                       '        assert_true(z.is_finite())\n'
                                                       '        assert_true(z.low < 2.0 or z.high '
                                                       '> 2.0)\n'
                                                       '        var work = '
                                                       '_MapBuildWork(MapBuildBudget(0, 5, terms, '
                                                       '0))\n'
                                                       '        var result = '
                                                       '_monotone_junction_enclosure(\n'
                                                       '            road, 0, 0, low, high, terms, '
                                                       'proposal, x, y, z, work\n'
                                                       '        )\n'
                                                       '        _same(result[0], x)\n'
                                                       '        _same(result[1], y)\n'
                                                       '        _same(result[2], z)\n'),
                                                      ('5',
                                                       '        assert_false(work.exhausted)\n'
                                                       '        var short = '
                                                       '_MapBuildWork(MapBuildBudget(0, 5, terms - '
                                                       '1, 0))\n'
                                                       '        with '
                                                       'assert_raises(contains="global term '
                                                       'budget"):\n'
                                                       '            _ = '
                                                       '_monotone_junction_enclosure(road, 0, 0, '
                                                       'low, high, terms, proposal, x, y, z, '
                                                       'short)\n'
                                                       '        assert_equal(short.steps, 1)\n'
                                                       '        assert_equal(short.terms, 0)\n'
                                                       '        assert_true(short.exhausted)\n'
                                                       '        print("REFUSAL_LEDGER", '
                                                       'work.steps, work.terms, short.steps, '
                                                       'short.terms)\n'
                                                       '    except error:\n'
                                                       '        '
                                                       'external_call["sum2_test_restore_mode", '
                                                       'NoneType](original)\n'
                                                       '        raise error\n',
                                                       '        assert_false(work.exhausted)\n'
                                                       '        var short = '
                                                       '_MapBuildWork(MapBuildBudget(0, 5, terms - '
                                                       '1, 0))\n'
                                                       '        with '
                                                       'assert_raises(contains="global term '
                                                       'budget"):\n'
                                                       '            _ = '
                                                       '_monotone_junction_enclosure(\n'
                                                       '                road, 0, 0, low, high, '
                                                       'terms, proposal, x, y, z, short\n'
                                                       '            )\n'
                                                       '        assert_equal(short.steps, 1)\n'
                                                       '        assert_equal(short.terms, 0)\n'
                                                       '        assert_true(short.exhausted)\n'
                                                       '        print(\n'
                                                       '            "REFUSAL_LEDGER", work.steps, '
                                                       'work.terms, short.steps, short.terms\n'
                                                       '        )\n'
                                                       '    except error:\n'
                                                       '        '
                                                       'external_call["sum2_test_restore_mode", '
                                                       'NoneType](original)\n'
                                                       '        raise error\n'),
                                                      ('6',
                                                       '    var geometry = RoadGeometry(SPIRAL, 0, '
                                                       '0, 0, 0, length)\n'
                                                       '    geometry.curvature_start = curvature\n'
                                                       '    geometry.curvature_end = '
                                                       '_next_up(curvature)\n'
                                                       '    var road = Road(RoadId(1), "direct '
                                                       'last-end junction helper refusal", 2.0, '
                                                       'NO_JUNCTION, RoadId(0), RoadId(0), True)\n'
                                                       '    _ = road.add_section(SectionId(0), '
                                                       '0.0)\n'
                                                       '    _ = '
                                                       'road.sections[0].add_lane(LaneId(-1))\n'
                                                       '    road.sections[0].lanes[0].type = '
                                                       'LANE_DRIVING\n'
                                                       '    '
                                                       'road.sections[0].lanes[0].info.widths.append(RoadInfoLaneWidth(0.0, '
                                                       'CubicPolynomial.constant(2.0)))\n'
                                                       '    '
                                                       'road.info.geometries.append(RoadInfoGeometry(0.0, '
                                                       'geometry^))\n'
                                                       '    '
                                                       'road.info.elevations.append(RoadInfoElevation(0.0, '
                                                       'CubicPolynomial(2.0, 1.0, 0.0, 0.0, '
                                                       '0.0)))\n'
                                                       '    '
                                                       'road.info.lane_offsets.append(RoadInfoLaneOffset(0.0, '
                                                       'CubicPolynomial.constant(1.0)))\n'
                                                       '    var validation = '
                                                       '_MapBuildWork(MapBuildBudget())\n'
                                                       '    _preflight_road_records(road, '
                                                       'validation)\n'
                                                       '    assert_false(validation.exhausted)\n',
                                                       '    var geometry = RoadGeometry(SPIRAL, 0, '
                                                       '0, 0, 0, length)\n'
                                                       '    geometry.curvature_start = curvature\n'
                                                       '    geometry.curvature_end = '
                                                       '_next_up(curvature)\n'
                                                       '    var road = Road(\n'
                                                       '        RoadId(1),\n'
                                                       '        "direct last-end junction helper '
                                                       'refusal",\n'
                                                       '        2.0,\n'
                                                       '        NO_JUNCTION,\n'
                                                       '        RoadId(0),\n'
                                                       '        RoadId(0),\n'
                                                       '        True,\n'
                                                       '    )\n'
                                                       '    _ = road.add_section(SectionId(0), '
                                                       '0.0)\n'
                                                       '    _ = '
                                                       'road.sections[0].add_lane(LaneId(-1))\n'
                                                       '    road.sections[0].lanes[0].type = '
                                                       'LANE_DRIVING\n'
                                                       '    '
                                                       'road.sections[0].lanes[0].info.widths.append(\n'
                                                       '        RoadInfoLaneWidth(0.0, '
                                                       'CubicPolynomial.constant(2.0))\n'
                                                       '    )\n'
                                                       '    '
                                                       'road.info.geometries.append(RoadInfoGeometry(0.0, '
                                                       'geometry^))\n'
                                                       '    road.info.elevations.append(\n'
                                                       '        RoadInfoElevation(0.0, '
                                                       'CubicPolynomial(2.0, 1.0, 0.0, 0.0, 0.0))\n'
                                                       '    )\n'
                                                       '    road.info.lane_offsets.append(\n'
                                                       '        RoadInfoLaneOffset(0.0, '
                                                       'CubicPolynomial.constant(1.0))\n'
                                                       '    )\n'
                                                       '    var validation = '
                                                       '_MapBuildWork(MapBuildBudget())\n'
                                                       '    _preflight_road_records(road, '
                                                       'validation)\n'
                                                       '    assert_false(validation.exhausted)\n'),
                                                      ('7',
                                                       '        assert_true(z.is_finite())\n'
                                                       '        assert_true(z.low < 3.0 or z.high '
                                                       '> 3.0)\n'
                                                       '        var work = '
                                                       '_MapBuildWork(MapBuildBudget(0, 5, terms, '
                                                       '0))\n'
                                                       '        var result = '
                                                       '_monotone_junction_enclosure(road, 0, 0, '
                                                       'low, high, terms, proposal, x, y, z, '
                                                       'work)\n'
                                                       '        _same(result[0], x)\n'
                                                       '        _same(result[1], y)\n'
                                                       '        _same(result[2], z)\n',
                                                       '        assert_true(z.is_finite())\n'
                                                       '        assert_true(z.low < 3.0 or z.high '
                                                       '> 3.0)\n'
                                                       '        var work = '
                                                       '_MapBuildWork(MapBuildBudget(0, 5, terms, '
                                                       '0))\n'
                                                       '        var result = '
                                                       '_monotone_junction_enclosure(\n'
                                                       '            road, 0, 0, low, high, terms, '
                                                       'proposal, x, y, z, work\n'
                                                       '        )\n'
                                                       '        _same(result[0], x)\n'
                                                       '        _same(result[1], y)\n'
                                                       '        _same(result[2], z)\n'),
                                                      ('8',
                                                       '        assert_false(work.exhausted)\n'
                                                       '        var short = '
                                                       '_MapBuildWork(MapBuildBudget(0, 5, terms - '
                                                       '1, 0))\n'
                                                       '        with '
                                                       'assert_raises(contains="global term '
                                                       'budget"):\n'
                                                       '            _ = '
                                                       '_monotone_junction_enclosure(road, 0, 0, '
                                                       'low, high, terms, proposal, x, y, z, '
                                                       'short)\n'
                                                       '        assert_equal(short.steps, 1)\n'
                                                       '        assert_equal(short.terms, 0)\n'
                                                       '        assert_true(short.exhausted)\n'
                                                       '        print("LAST_REFUSAL_LEDGER", mode, '
                                                       'work.steps, work.terms, short.steps, '
                                                       'short.terms)\n'
                                                       '    except error:\n'
                                                       '        '
                                                       'external_call["sum2_test_restore_mode", '
                                                       'NoneType](original)\n'
                                                       '        raise error\n',
                                                       '        assert_false(work.exhausted)\n'
                                                       '        var short = '
                                                       '_MapBuildWork(MapBuildBudget(0, 5, terms - '
                                                       '1, 0))\n'
                                                       '        with '
                                                       'assert_raises(contains="global term '
                                                       'budget"):\n'
                                                       '            _ = '
                                                       '_monotone_junction_enclosure(\n'
                                                       '                road, 0, 0, low, high, '
                                                       'terms, proposal, x, y, z, short\n'
                                                       '            )\n'
                                                       '        assert_equal(short.steps, 1)\n'
                                                       '        assert_equal(short.terms, 0)\n'
                                                       '        assert_true(short.exhausted)\n'
                                                       '        print(\n'
                                                       '            "LAST_REFUSAL_LEDGER",\n'
                                                       '            mode,\n'
                                                       '            work.steps,\n'
                                                       '            work.terms,\n'
                                                       '            short.steps,\n'
                                                       '            short.terms,\n'
                                                       '        )\n'
                                                       '    except error:\n'
                                                       '        '
                                                       'external_call["sum2_test_restore_mode", '
                                                       'NoneType](original)\n'
                                                       '        raise error\n'),
                                                      ('9',
                                                       '        _last_endpoint_control(Int32(5))\n'
                                                       '        _last_endpoint_control(Int32(6))\n'
                                                       '    else:\n'
                                                       '        '
                                                       'print("LAST_DAZ_CAPABILITY_UNAVAILABLE: '
                                                       'fixture exposes Arm modes0..4; first-end '
                                                       'FTZ control executed")\n'
                                                       '\n'
                                                       '\n'
                                                       'def '
                                                       'test_real_junction_admitted_endpoints_charge_both_traversals() '
                                                       'raises:\n',
                                                       '        _last_endpoint_control(Int32(5))\n'
                                                       '        _last_endpoint_control(Int32(6))\n'
                                                       '    else:\n'
                                                       '        print(\n'
                                                       '            '
                                                       '"LAST_DAZ_CAPABILITY_UNAVAILABLE: fixture '
                                                       'exposes Arm modes0..4;"\n'
                                                       '            " first-end FTZ control '
                                                       'executed"\n'
                                                       '        )\n'
                                                       '\n'
                                                       '\n'
                                                       'def '
                                                       'test_real_junction_admitted_endpoints_charge_both_traversals() '
                                                       'raises:\n'),
                                                      ('10',
                                                       '    assert_true(first_terms >= 0)\n'
                                                       '    assert_true(last_terms >= 0)\n'
                                                       '    var point = _lane_value_bound(road, 0, '
                                                       '0, low, high)\n'
                                                       '    var work = '
                                                       '_MapBuildWork(MapBuildBudget(0, 9, terms + '
                                                       'first_terms + last_terms, 0))\n'
                                                       '    var result = '
                                                       '_monotone_junction_enclosure(road, 0, 0, '
                                                       'low, high, terms, Box3(Vector3(-2, -2, 2), '
                                                       'Vector3(2, 2, 2)), '
                                                       'point[0].rounded_value(), '
                                                       '-point[1].rounded_value(), '
                                                       'point[2].rounded_value(), work)\n'
                                                       '    assert_equal(work.steps, 9)\n'
                                                       '    assert_equal(work.terms, terms + '
                                                       'first_terms + last_terms)\n'
                                                       '    assert_false(work.exhausted)\n',
                                                       '    assert_true(first_terms >= 0)\n'
                                                       '    assert_true(last_terms >= 0)\n'
                                                       '    var point = _lane_value_bound(road, 0, '
                                                       '0, low, high)\n'
                                                       '    var work = _MapBuildWork(\n'
                                                       '        MapBuildBudget(0, 9, terms + '
                                                       'first_terms + last_terms, 0)\n'
                                                       '    )\n'
                                                       '    var result = '
                                                       '_monotone_junction_enclosure(\n'
                                                       '        road,\n'
                                                       '        0,\n'
                                                       '        0,\n'
                                                       '        low,\n'
                                                       '        high,\n'
                                                       '        terms,\n'
                                                       '        Box3(Vector3(-2, -2, 2), '
                                                       'Vector3(2, 2, 2)),\n'
                                                       '        point[0].rounded_value(),\n'
                                                       '        -point[1].rounded_value(),\n'
                                                       '        point[2].rounded_value(),\n'
                                                       '        work,\n'
                                                       '    )\n'
                                                       '    assert_equal(work.steps, 9)\n'
                                                       '    assert_equal(work.terms, terms + '
                                                       'first_terms + last_terms)\n'
                                                       '    assert_false(work.exhausted)\n')),
 'tests/test_carla_speed_parser_exceptions.mojo': (('1',
                                                    'exception. No injected parser or synthetic '
                                                    'coverage trace is used.\n'
                                                    '"""\n'
                                                    '\n'
                                                    'from extensions.carla.speed_limits import '
                                                    '_speed_decimal_syntax, read_speed_number\n'
                                                    'from std.testing import TestSuite, '
                                                    'assert_equal, assert_raises, assert_true\n'
                                                    '\n'
                                                    '\n',
                                                    'exception. No injected parser or synthetic '
                                                    'coverage trace is used.\n'
                                                    '"""\n'
                                                    '\n'
                                                    'from extensions.carla.speed_limits import (\n'
                                                    '    _speed_decimal_syntax,\n'
                                                    '    read_speed_number,\n'
                                                    ')\n'
                                                    'from std.testing import TestSuite, '
                                                    'assert_equal, assert_raises, assert_true\n'
                                                    '\n'
                                                    '\n'),),
 'tests/test_carla_width_overflow_admission.mojo': (('1',
                                                     'from extensions.carla.map_validation import '
                                                     '_preflight_road_records\n'
                                                     'from math.vector3 import Vector3\n'
                                                     'from std.math import isfinite\n'
                                                     'from std.testing import TestSuite, '
                                                     'assert_equal, assert_false, assert_raises, '
                                                     'assert_true\n'
                                                     'from tests._lazy_taylor_controls import '
                                                     '_whole_certificate\n'
                                                     'from '
                                                     'tests.test_carla_cross_candidate_certificates '
                                                     'import _road\n'
                                                     '\n',
                                                     'from extensions.carla.map_validation import '
                                                     '_preflight_road_records\n'
                                                     'from math.vector3 import Vector3\n'
                                                     'from std.math import isfinite\n'
                                                     'from std.testing import (\n'
                                                     '    TestSuite,\n'
                                                     '    assert_equal,\n'
                                                     '    assert_false,\n'
                                                     '    assert_raises,\n'
                                                     '    assert_true,\n'
                                                     ')\n'
                                                     'from tests._lazy_taylor_controls import '
                                                     '_whole_certificate\n'
                                                     'from '
                                                     'tests.test_carla_cross_candidate_certificates '
                                                     'import _road\n'
                                                     '\n'),
                                                    ('2',
                                                     '    # One cell and depth zero rule out '
                                                     'recursive search or a large workload.\n'
                                                     '    with assert_raises(contains="numerical '
                                                     'accuracy limit"):\n'
                                                     '        _run_lane_search(\n'
                                                     '            road, 0, 0, low, high, location, '
                                                     'certificate, pending^,\n'
                                                     '            _ClosedIntervals(), '
                                                     'List[_ClosedInterval](),\n'
                                                     '            (Float64(0.0), Float64(1.0)), 1, '
                                                     '6, 0,\n'
                                                     '        )\n'
                                                     '    assert_equal(certificate.nodes, 1)\n'
                                                     '    # One initial incumbent, three '
                                                     'edge/center samples, one whole enclosure,\n',
                                                     '    # One cell and depth zero rule out '
                                                     'recursive search or a large workload.\n'
                                                     '    with assert_raises(contains="numerical '
                                                     'accuracy limit"):\n'
                                                     '        _run_lane_search(\n'
                                                     '            road,\n'
                                                     '            0,\n'
                                                     '            0,\n'
                                                     '            low,\n'
                                                     '            high,\n'
                                                     '            location,\n'
                                                     '            certificate,\n'
                                                     '            pending^,\n'
                                                     '            _ClosedIntervals(),\n'
                                                     '            List[_ClosedInterval](),\n'
                                                     '            (Float64(0.0), Float64(1.0)),\n'
                                                     '            1,\n'
                                                     '            6,\n'
                                                     '            0,\n'
                                                     '        )\n'
                                                     '    assert_equal(certificate.nodes, 1)\n'
                                                     '    # One initial incumbent, three '
                                                     'edge/center samples, one whole '
                                                     'enclosure,\n'))}

def require(value, message):
    if not value:
        raise ValueError('reviewed witness-format successor: ' + message)


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def _statement(tokens):
    """Compare the fixed formatting grammar; never normalize arbitrary source.

    Import parentheses, call-only trailing commas and adjacent plain string
    literals are the only token changes in these exact formatter endpoints.
    Tuple/grouping parentheses and commas, qualifiers and all operators stay.
    """
    stream = list(tokens)
    if stream and stream[0] == (tokenize.NAME, 'from'):
        imports = [i for i, token in enumerate(stream) if token == (tokenize.NAME, 'import')]
        require(len(imports) == 1, 'ambiguous import statement')
        at = imports[0] + 1
        if stream[at:at + 1] == [(tokenize.OP, '(')]:
            require(stream[-1] == (tokenize.OP, ')'), 'unclosed import group')
            imported = stream[at + 1:-1]
            if imported[-1:] == [(tokenize.OP, ',')]:
                imported.pop()
            require(all(kind == tokenize.NAME or (kind, word) in
                        ((tokenize.OP, ','), (tokenize.OP, '.'))
                        for kind, word in imported), 'non-name import group')
            stream = stream[:at] + imported
    result, stack = [], []
    for token in stream:
        kind, word = token
        if kind == tokenize.OP and word in ('(', '[', '{'):
            previous = result[-1] if result else None
            call = (word == '(' and previous is not None and
                    (previous[0] == tokenize.NAME and previous[1] not in
                     ('if', 'elif', 'while', 'for', 'return', 'yield', 'in', 'not',
                      'and', 'or', 'else', 'assert', 'with', 'raise', 'raises')
                     or previous in ((tokenize.OP, ')'), (tokenize.OP, ']'))))
            stack.append((word, call))
        elif kind == tokenize.OP and word in (')', ']', '}'):
            require(bool(stack), 'unmatched closing group')
            opening, call = stack.pop()
            require((opening, word) in (('(', ')'), ('[', ']'), ('{', '}')),
                    'crossed lexical group')
            if call and result[-1:] == [(tokenize.OP, ',')]:
                result.pop()
        if kind == tokenize.STRING:
            literal = ast.literal_eval(word)
            require(type(literal) is str, 'non-plain string literal')
            if result and result[-1][0] == tokenize.STRING:
                literal = ast.literal_eval(result.pop()[1]) + literal
            token = (kind, repr(literal))
        result.append(token)
    require(not stack, 'unclosed lexical group')
    return result


def observations(text):
    """Retain statement depth, comments and ordered executable observations."""
    require(type(text) is str, 'source is not text')
    rows, statement, depth = [], [], 0
    for item in source.tokens(text):
        if item.type == tokenize.INDENT:
            depth += 1
        elif item.type == tokenize.DEDENT:
            depth -= 1
            require(depth >= 0, 'unmatched indentation')
        elif item.type == tokenize.NEWLINE:
            rows.append((depth, _statement(statement)))
            statement = []
        elif item.type == tokenize.COMMENT:
            # Comments are bound in order and at their actual statement depth.
            rows.append((depth, [(item.type, item.string)]))
        elif item.type not in (tokenize.NL, tokenize.ENDMARKER):
            statement.append((item.type, item.string))
    require(not statement and depth == 0, 'unterminated source')
    return rows


EDITS_SHA256 = 'e02654f4db2391ae4880ec6b79ed6c7e497e0994b9776bcbaa1dbf24dc37db7a'


def predecessor_source(path, text):
    """Invert only one exact reviewed after endpoint, then check equivalence."""
    require(path in SOURCE_PATHS and type(text) is str, 'unknown witness')
    require(sha(text) == AFTER_SHA256[path] and
            source.token_sha256(text) == AFTER_TOKEN_SHA256[path],
            'unknown exact formatted witness: ' + path)
    require(hashlib.sha256(json.dumps(EDITS, sort_keys=True).encode()).hexdigest() == EDITS_SHA256,
            'inverse inventory changed')
    current = text
    edits = EDITS[path]
    require(tuple(item[0] for item in edits) == tuple(str(i + 1) for i in range(len(edits))),
            'inverse order changed: ' + path)
    for name, before, after in reversed(edits):
        require(bool(before) and bool(after) and text.count(after) == 1,
                'missing or ambiguous inverse: ' + path + ':' + name)
        text = text.replace(after, before, 1)
    require(sha(text) == BEFORE_SHA256[path] and
            source.token_sha256(text) == BEFORE_TOKEN_SHA256[path],
            'historical witness endpoint changed: ' + path)
    require(observations(text) == observations(current),
            'formatter changed witness observations: ' + path)
    return text


def edge(path):
    """A descriptor alone grants no physical admission."""
    require(path in SOURCE_PATHS, 'unknown witness edge')
    return {'path': path, 'before_sha256': BEFORE_SHA256[path],
            'after_sha256': AFTER_SHA256[path],
            'before_token_sha256': BEFORE_TOKEN_SHA256[path],
            'after_token_sha256': AFTER_TOKEN_SHA256[path]}


# Filled from the exact reviewed new test and policy-note bytes. Historical
# JSON and theorem documents remain unchanged.
BOUND_INPUTS = {'tools/carla_lane_oracle/test_witness_format_contracts.py': '2e57bf5524f03303042c30c04588b776802b5d672e0ad69e15a04611e4bc9e7b',
 'docs/validation/carla-witness-format-successor.md': 'e2df2607c2aba63bf440dcc1efb2acad4da7a1e6f9eaef82cd1f8e2827fbb8db'}
