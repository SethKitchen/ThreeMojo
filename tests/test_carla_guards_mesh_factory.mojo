# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The finite work limits of CARLA's `MeshFactory`.

Each test sets a step so small that a loop reaches its limit of
4194304 passes, and checks that the factory stops with an error. The
roads are built by hand: straight lines east, one driving lane each.
"""

from extensions.carla.map import Map
from extensions.carla.map_builder import MapBuilder
from extensions.carla.mesh_factory import (
    MeshFactory,
    OpendriveGenerationParameters,
    generate_chunked_mesh,
    trees_transform,
)
from extensions.carla.road_info import (
    JuncId,
    LANE_DRIVING,
    LaneId,
    LaneType,
    RoadId,
    SectionId,
)
from math.vector3 import Vector3
from std.testing import TestSuite, assert_raises
from units.si import Length, METER


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _road(
    mut b: MapBuilder,
    id: Int,
    x: Float64,
    y: Float64,
    length: Float64,
    curve: Float64,
    width: Float64,
) raises -> Int:
    # One section east from (x, y) with driving lane -1. A nonzero `curve`
    # bends the elevation, so the lane is not straight.
    var r = b.add_road_si(
        RoadId(id), "r", length, JuncId(-1), RoadId(0), RoadId(0), True
    )
    _ = b.add_road_section_si(r, SectionId(0), 0.0)
    _ = b.add_road_section_lane(
        r, 0, LaneId(-1), LANE_DRIVING, False, LaneId(0), LaneId(0)
    )
    b.create_lane_width_si(
        b.lane_si(RoadId(id), LaneId(-1), 0.0), 0.0, width, 0, 0, 0
    )
    b.create_section_offset_si(r, 0.0, 0, 0, 0, 0)
    b.add_road_elevation_profile_si(r, 0.0, 0, 0, curve, 0)
    b.add_road_geometry_line_si(r, 0.0, x, y, 0.0, length)
    return r


def _one(length: Float64, curve: Float64, width: Float64) raises -> Map:
    var b = MapBuilder()
    _ = _road(b, 1, 0, 0, length, curve, width)
    return b.build()


def test_curved_lane_rows_stop_at_the_limit() raises:
    # A curved lane takes a row every resolution: 5 m at 1 um is more
    # than the limit.
    var map = _one(10, 0.01, 3.5)
    var factory = MeshFactory()
    factory.road_param.resolution = _m(1e-6)
    with assert_raises(contains="row work limit"):
        _ = factory.generate_lane_si(map.road(RoadId(1)), 0, 0, 0.0, 5.0)


def test_tessellated_rows_stop_at_the_limit() raises:
    var map = _one(10, 0, 3.5)
    var factory = MeshFactory()
    factory.road_param.resolution = _m(1e-6)
    with assert_raises(contains="row work limit"):
        _ = factory.generate_tesselated_si(map.road(RoadId(1)), 0, 0, 0.0, 5.0)


def test_tessellated_vertices_stop_at_the_limit() raises:
    # 5000 rows of 2000 vertices are more than the vertex limit.
    var map = _one(10, 0, 3.5)
    var factory = MeshFactory()
    factory.road_param.resolution = _m(0.001)
    factory.road_param.vertex_width_resolution = 2000
    with assert_raises(contains="vertex work limit"):
        _ = factory.generate_tesselated_si(map.road(RoadId(1)), 0, 0, 0.0, 5.0)


def test_chunks_stop_at_the_limit() raises:
    # A 10 m section in chunks of 1 um is more than the limit.
    var map = _one(10, 0, 3.5)
    var factory = MeshFactory()
    factory.road_param.max_road_len = _m(1e-6)
    with assert_raises(contains="chunking exhausted"):
        _ = factory.generate_section_with_max_len(map.road(RoadId(1)), 0)


def test_lane_mark_steps_stop_at_the_limit() raises:
    # A mark of type "none" adds no paint, so each step only moves on.
    var b = MapBuilder()
    _ = _road(b, 1, 0, 0, 10, 0, 3.5)
    b.create_road_mark_si(
        b.lane_si(RoadId(1), LaneId(-1), 0.0),
        0,
        0.0,
        "none",
        "",
        "white",
        "",
        0.1,
        "",
        0,
        "",
        0,
        True,
    )
    var map = b.build()
    var factory = MeshFactory()
    factory.road_param.resolution = _m(1e-6)
    with assert_raises(contains="Lane mark sampling exhausted"):
        _ = factory.generate_lane_marks_for_not_center_line(
            map.road(RoadId(1)), 0, 0
        )


def test_chunk_grid_stops_at_the_limit() raises:
    # Two short roads 5000 km apart, on 1 m squares, make a grid with more
    # columns, or more rows, than the limit.
    var params = OpendriveGenerationParameters()
    params.max_road_length = _m(1)
    var east = MapBuilder()
    _ = _road(east, 1, 0, 0, 0.5, 0, 3.5)
    _ = _road(east, 2, 5.0e6, 0, 0.5, 0, 3.5)
    with assert_raises(contains="chunk grid exceeds its finite work limit"):
        _ = generate_chunked_mesh(east.build(), params)
    var north = MapBuilder()
    _ = _road(north, 1, 0, 0, 0.5, 0, 3.5)
    _ = _road(north, 2, 0, 5.0e6, 0.5, 0, 3.5)
    with assert_raises(contains="chunk grid exceeds its finite work limit"):
        _ = generate_chunked_mesh(north.build(), params)
    # 3001 columns and 3001 rows are each in the limit, but their cells
    # are not.
    var square = MapBuilder()
    _ = _road(square, 1, 0, 0, 0.5, 0, 3.5)
    _ = _road(square, 2, 3000, 3000, 0.5, 0, 3.5)
    with assert_raises(contains="chunk grid exceeds its cell work limit"):
        _ = generate_chunked_mesh(square.build(), params)


def test_tree_steps_stop_at_the_limit() raises:
    # A lane of no width gets no tree, so each step only moves on.
    var map = _one(10, 0, 0.0)
    with assert_raises(contains="Tree sampling exhausted"):
        _ = trees_transform(
            map,
            Vector3(-100, 100, 0),
            Vector3(100, -100, 0),
            _m(1e-6),
            _m(1),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
