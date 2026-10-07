# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Review-grid station and public-pose controls from an independent oracle.

Expected values come from tools/carla_lane_oracle/town-station-controls.json.
The grid and original town are unchanged. This includes the three on-lane
points whose default queries exhausted the reviewed head's global budget.
"""

from extensions.carla.map import Map
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import LaneId, RoadId, SectionId
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def _check(
    map: Map,
    i: Int,
    j: Int,
    x_word: UInt32,
    y_word: UInt32,
    road: Int,
    lane: Int,
    station: Float64,
    x: Float64,
    y: Float64,
    z: Float64,
    yaw: Float64,
    pitch: Float64,
) raises:
    # These are the exact recorded review-grid input words. Do not let
    # compiler constant folding reconstruct a slightly different grid.
    var query = Vector3(
        bitcast[DType.float32](x_word), bitcast[DType.float32](y_word), 0
    )
    var found = map.certified_waypoint(query)
    assert_true(Bool(found))
    var waypoint = found.value()
    assert_equal(waypoint.road_id, RoadId(road))
    assert_equal(waypoint.section_id, SectionId(0))
    assert_equal(waypoint.lane_id, LaneId(lane))
    assert_almost_equal(waypoint.s, station, atol=1e-4)
    var pose = map.compute_transform(waypoint)
    assert_almost_equal(Float64(pose.location.x), x, atol=1e-4)
    assert_almost_equal(Float64(pose.location.y), y, atol=1e-4)
    assert_almost_equal(Float64(pose.location.z), z, atol=1e-4)
    assert_almost_equal(Float64(pose.rotation.yaw), yaw, atol=1e-4)
    assert_almost_equal(Float64(pose.rotation.pitch), pitch, atol=1e-4)
    if i == 10 and j == 21:
        # Road 5 jumps at s=35. A station-only tolerance misses the wrong pose.
        assert_true(waypoint.s < 35.0)


def test_review_grid_spiral_stations_and_public_poses() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    _check(
        map,
        0,
        23,
        UInt32(0x27200000),
        UInt32(0xC2C68666),
        5,
        -1,
        0.0,
        0.0,
        -98.75,
        1.0,
        0.0,
        -1.1457628381751035,
    )
    _check(
        map,
        1,
        23,
        UInt32(0x404CCCCD),
        UInt32(0xC2C68666),
        5,
        -1,
        3.1695607319147916,
        3.1852073925732736,
        -98.76336581342449,
        1.0633912146382958,
        -0.719500004212448,
        -1.134528453968141,
    )
    _check(
        map,
        2,
        23,
        UInt32(0x40CCCCCD),
        UInt32(0xC2C68666),
        5,
        -1,
        6.33709262686339,
        6.398217626680483,
        -98.85759287554328,
        1.1267418525372679,
        -2.8761581028019707,
        -1.1235191954787402,
    )
    _check(
        map,
        3,
        23,
        UInt32(0x4119999A),
        UInt32(0xC2C68666),
        5,
        -1,
        9.465953757681152,
        9.593799562436745,
        -99.11092848413992,
        1.1893190751536231,
        -6.417433876743465,
        -1.112852092480304,
    )
    _check(
        map,
        4,
        23,
        UInt32(0x414CCCCD),
        UInt32(0xC2C68666),
        5,
        -1,
        12.51551892701184,
        12.710809959554913,
        -99.5884868666338,
        1.2503103785402367,
        -11.21838571672124,
        -1.1026484387183149,
    )
    _check(
        map,
        5,
        23,
        UInt32(0x41800000),
        UInt32(0xC2C68666),
        5,
        -1,
        15.418842004671017,
        15.649254718335214,
        -100.32255235442561,
        1.3083768400934204,
        -17.02692260596024,
        -1.0931064449365864,
    )


def test_review_grid_sampled_stations_and_public_poses() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    _check(
        map,
        6,
        22,
        UInt32(0x4199999A),
        UInt32(0xC2D7D99A),
        5,
        1,
        20.723892033335673,
        19.533094500774745,
        -107.29854223827104,
        1.4144778406667133,
        149.61334792435366,
        361.1966874988127,
    )
    _check(
        map,
        7,
        22,
        UInt32(0x41B33333),
        UInt32(0xC2D7D99A),
        5,
        1,
        23.549089640998105,
        21.83981661376204,
        -108.72921458056588,
        1.4709817928199622,
        146.92447774652427,
        361.18832479478505,
    )
    _check(
        map,
        8,
        22,
        UInt32(0x41CCCCCD),
        UInt32(0xC2D7D99A),
        5,
        -1,
        26.258256435971077,
        25.989481479998013,
        -107.31506769116733,
        1.5251651287194217,
        -34.94122171248667,
        -1.1290618564574109,
    )
    _check(
        map,
        9,
        22,
        UInt32(0x41E66666),
        UInt32(0xC2D7D99A),
        5,
        -1,
        28.814479588946313,
        28.088056115951712,
        -108.83059523592465,
        1.5762895917789264,
        -36.6214595133324,
        -1.1336532182011847,
    )
    _check(
        map,
        10,
        21,
        UInt32(0x42000000),
        UInt32(0xC2E92CCC),
        5,
        1,
        34.99999999999999,
        30.821320650253377,
        -115.4425189566643,
        1.625,
        141.1366880399541,
        360.5758286660056,
    )
    _check(
        map,
        11,
        21,
        UInt32(0x420CCCCD),
        UInt32(0xC2E92CCC),
        5,
        1,
        38.195211556775476,
        35.85482804116508,
        -115.83456062101938,
        1.6671614924603064,
        137.24800784351856,
        361.0402493616438,
    )
    _check(
        map,
        12,
        21,
        UInt32(0x4219999A),
        UInt32(0xC2E92CCC),
        5,
        1,
        40.64932301503916,
        37.41508133110284,
        -117.41072394511019,
        1.7134080806786427,
        131.6879321088508,
        361.34648705218524,
    )
    _check(
        map,
        13,
        21,
        UInt32(0x42266666),
        UInt32(0xC2E92CCC),
        5,
        -1,
        42.76765248306451,
        41.45102001796163,
        -116.64822953787899,
        1.7630129499283034,
        -52.14682576078103,
        -1.4122136079472327,
    )
    _check(
        map,
        15,
        20,
        UInt32(0x42400000),
        UInt32(0xC2FA8000),
        5,
        1,
        54.10566426679256,
        48.46823095635184,
        -124.81079596688609,
        2.18108304974332,
        122.7150067411829,
        363.05675690111156,
    )
    _check(
        map,
        15,
        21,
        UInt32(0x42400000),
        UInt32(0xC2E92CCC),
        5,
        -1,
        47.50002499937502,
        47.022097941308495,
        -117.59292094260385,
        1.9062508749787508,
        -41.2529463284343,
        -1.929477694867365,
    )
    _check(
        map,
        16,
        20,
        UInt32(0x424CCCCD),
        UInt32(0xC2FA8000),
        5,
        -1,
        55.94805344072029,
        52.48327152950449,
        -124.37542572135716,
        2.2733014773624762,
        -59.95462997928516,
        -2.884447240707337,
    )
    _check(
        map,
        17,
        20,
        UInt32(0x4259999A),
        UInt32(0xC2FA8000),
        5,
        -1,
        57.0,
        53.00818839203509,
        -125.32228263993244,
        2.329,
        -61.97032069748265,
        -3.0054624670465055,
    )


def test_review_grid_ordinary_stations_and_public_poses() raises:
    var map = load_opendrive_file("assets/carla/town.xodr")
    _check(
        map,
        0,
        0,
        UInt32(0x27200000),
        UInt32(0xC3954000),
        7,
        -1,
        2.2204528255138903e-15,
        2.2204528255138903e-15,
        -298.5,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        0,
        11,
        UInt32(0x27200000),
        UInt32(0xC34B3666),
        6,
        1,
        0.0,
        0.0,
        -201.75,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        1,
        0,
        UInt32(0x404CCCCD),
        UInt32(0xC3954000),
        7,
        -1,
        3.200000047683716,
        3.200000047683716,
        -298.5,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        1,
        11,
        UInt32(0x404CCCCD),
        UInt32(0xC34B3666),
        6,
        1,
        3.200000047683716,
        3.200000047683716,
        -201.75,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        2,
        0,
        UInt32(0x40CCCCCD),
        UInt32(0xC3954000),
        7,
        -1,
        6.400000095367432,
        6.400000095367432,
        -298.5,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        2,
        11,
        UInt32(0x40CCCCCD),
        UInt32(0xC34B3666),
        6,
        1,
        6.400000095367432,
        6.400000095367432,
        -201.75,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        3,
        0,
        UInt32(0x4119999A),
        UInt32(0xC3954000),
        7,
        -1,
        9.600000381469727,
        9.600000381469727,
        -298.5,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        3,
        11,
        UInt32(0x4119999A),
        UInt32(0xC34B3666),
        6,
        1,
        9.600000381469727,
        9.600000381469727,
        -201.75,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        4,
        11,
        UInt32(0x414CCCCD),
        UInt32(0xC34B3666),
        6,
        1,
        12.800000190734863,
        12.800000190734863,
        -201.75,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        5,
        11,
        UInt32(0x41800000),
        UInt32(0xC34B3666),
        6,
        1,
        15.999999999999996,
        15.999999999999996,
        -201.75,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        6,
        11,
        UInt32(0x4199999A),
        UInt32(0xC34B3666),
        6,
        1,
        19.200000762939453,
        19.200000762939453,
        -201.75,
        0.0,
        0.0,
        -0.0,
    )
    _check(
        map,
        21,
        35,
        UInt32(0x42866666),
        UInt32(0x40960000),
        11,
        -1,
        8.790557353054357,
        67.76559865525647,
        3.484613915337043,
        0.0,
        25.18309179488535,
        -0.0,
    )
    _check(
        map,
        22,
        35,
        UInt32(0x428CCCCD),
        UInt32(0x40960000),
        11,
        -1,
        11.932366084417904,
        70.25372994500295,
        4.902863774379257,
        0.0,
        34.18371081210949,
        -0.0,
    )
    _check(
        map,
        24,
        36,
        UInt32(0x4299999A),
        UInt32(0x415599A0),
        11,
        -1,
        23.87774865450764,
        76.96897321581284,
        13.283122153781086,
        0.0,
        68.4047111088734,
        -0.0,
    )
    _check(
        map,
        24,
        37,
        UInt32(0x4299999A),
        UInt32(0x41B019A0),
        3,
        -1,
        2.0125122070312482,
        78.25,
        22.01251220703125,
        0.0,
        90.0,
        -0.0,
    )
    _check(
        map,
        24,
        38,
        UInt32(0x4299999A),
        UInt32(0x41F56660),
        3,
        -1,
        10.674987792968746,
        78.25,
        30.674987792968746,
        0.0,
        90.0,
        -0.0,
    )
    _check(
        map,
        24,
        39,
        UInt32(0x4299999A),
        UInt32(0x421D5998),
        3,
        -1,
        19.337493896484368,
        78.25,
        39.33749389648437,
        0.0,
        90.0,
        -0.0,
    )
    _check(
        map,
        24,
        40,
        UInt32(0x4299999A),
        UInt32(0x42400000),
        3,
        -1,
        27.999999999999993,
        78.25,
        47.99999999999999,
        0.0,
        90.0,
        -0.0,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
