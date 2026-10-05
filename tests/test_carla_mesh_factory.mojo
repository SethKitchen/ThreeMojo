# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's `MeshFactory` and the map's meshes.

Positions on the straight roads are worked by hand: road 1 runs east
from the origin, its lanes are 3.5 m wide, and CARLA's y is OpenDRIVE's
negated. The arc's corners and the junction smoothing come from
`carla_ref.py`, a Python copy of CARLA's C++ in the scratchpad.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV, UV1
from extensions.carla.map import Map
from extensions.carla.map_builder import MapBuilder
from extensions.carla.mesh_factory import (
    CROSSWALK_SURFACE,
    CURB_SURFACE,
    LaneMarkMesh,
    MeshFactory,
    OpendriveGenerationParameters,
    OrderedMeshes,
    ROAD_SURFACE,
    RoadParameters,
    SIDEWALK_SURFACE,
    SurfaceKind,
    WALL_SURFACE,
    WHITE_MARK_SURFACE,
    YELLOW_MARK_SURFACE,
    all_crosswalk_mesh,
    append_geometry,
    concat_geometry,
    filter_junctions_by_position,
    filter_roads_by_position,
    generate_chunked_mesh,
    generate_line_markings,
    generate_mesh,
    generate_ordered_chunked_mesh_in_locations,
    generate_single_junction,
    junctions_bounding_boxes,
    surface_name,
    to_three_frame,
    trees_transform,
)
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.road_info import (
    CrosswalkPoint,
    ConId,
    JuncId,
    LANE_DRIVING,
    LANE_NONE,
    LANE_SHOULDER,
    LANE_SIDEWALK,
    LaneId,
    LaneType,
    RoadId,
    SectionId,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime TOWN = "assets/carla/town.xodr"


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _near(
    a: Vector3, x: Float64, y: Float64, z: Float64, tol: Float64 = 1e-4
) raises:
    assert_almost_equal(Float64(a.x), x, atol=tol)
    assert_almost_equal(Float64(a.y), y, atol=tol)
    assert_almost_equal(Float64(a.z), z, atol=tol)


def _at(g: BufferGeometry, i: Int) raises -> Vector3:
    return g.attribute_view(POSITION).vector3(i)


def _normal(g: BufferGeometry, i: Int) raises -> Vector3:
    return g.attribute_view(NORMAL).vector3(i)


def _uv(
    g: BufferGeometry, name: String, i: Int
) raises -> Tuple[Float32, Float32]:
    ref a = g.attribute_view(name)
    return (a.component(i, 0), a.component(i, 1))


def _mark(var found: Optional[LaneMarkMesh]) raises -> LaneMarkMesh:
    return found.take()


def _hollow() raises -> BufferGeometry:
    # A geometry with positions, UVs and CARLA's grid, and no vertices.
    var g = BufferGeometry()
    g.set_attribute(POSITION, BufferAttribute(List[Float32](), 3))
    g.set_attribute(UV, BufferAttribute(List[Float32](), 2))
    g.set_attribute(UV1, BufferAttribute(List[Float32](), 2))
    return g^


def _kind_triangles(g: BufferGeometry, kind: SurfaceKind) -> Int:
    for group in g.groups:
        if group.material_index.value == kind.value:
            return group.count // 3
    return 0


def _road(
    mut b: MapBuilder,
    id: Int,
    y: Float64,
    length: Float64,
    junction: Int,
    rht: Bool,
    elevation: Float64,
    curve: Float64,
    lanes: List[Tuple[Int, LaneType, Float64]],
) raises -> Int:
    # One straight section east from (0, y); `curve` bends the elevation so
    # the lanes are not straight.
    var r = b.add_road(
        RoadId(id), "r", length, JuncId(junction), RoadId(0), RoadId(0), rht
    )
    _ = b.add_road_section(r, SectionId(0), 0.0)
    for lane in lanes:
        _ = b.add_road_section_lane(
            r, 0, LaneId(lane[0]), lane[1], False, LaneId(0), LaneId(0)
        )
        b.create_lane_width(
            b.lane(RoadId(id), LaneId(lane[0]), 0.0), 0.0, lane[2], 0, 0, 0
        )
    b.create_section_offset(r, 0.0, 0, 0, 0, 0)
    b.add_road_elevation_profile(r, 0.0, elevation, 0, curve, 0)
    b.add_road_geometry_line(r, 0.0, 0.0, y, 0.0, length)
    return r


# --- kinds and parameters -------------------------------------------------


def test_kinds_and_parameters() raises:
    assert_true(YELLOW_MARK_SURFACE.is_valid())
    assert_false(SurfaceKind(-1).is_valid())
    assert_false(SurfaceKind(7).is_valid())
    assert_equal(WALL_SURFACE.material().value, 3)
    assert_equal(surface_name(ROAD_SURFACE), "road")
    assert_equal(surface_name(CROSSWALK_SURFACE), "crosswalk")
    assert_equal(surface_name(CURB_SURFACE), "curb")
    with assert_raises():
        _ = surface_name(SurfaceKind(9))
    var params = OpendriveGenerationParameters()
    assert_equal(params.vertex_distance.value, 2.0)
    assert_equal(params.max_road_length.value, 50.0)
    assert_equal(params.wall_height.value, 1.0)
    assert_almost_equal(params.additional_width.value, 0.6)
    assert_equal(params.vertex_width_resolution, 4.0)
    assert_equal(params.simplification_percentage, 20.0)
    assert_true(params.smooth_junctions)
    assert_true(params.enable_mesh_visibility)
    assert_true(params.enable_pedestrian_navigation)
    var road = RoadParameters()
    assert_equal(road.extra_lane_width.value, 1.0)
    assert_almost_equal(road.wall_height.value, 0.6)
    assert_equal(road.max_weight_distance.value, 5.0)
    assert_equal(road.same_lane_weight_multiplier, 2.0)
    assert_equal(road.lane_ends_multiplier, 2.0)
    params.vertex_distance = _m(3)
    params.vertex_width_resolution = 1.0
    var factory = MeshFactory(params)
    assert_equal(factory.road_param.resolution.value, 3.0)
    assert_almost_equal(factory.road_param.extra_lane_width.value, 0.6)
    assert_equal(factory.road_param.wall_height.value, 1.0)
    assert_equal(factory.road_param.vertex_width_resolution, 1.0)


# --- lanes ----------------------------------------------------------------


def test_straight_lane() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    ref road = map.road(RoadId(1))
    # A straight lane has only its two end rows.
    var g = factory.generate_whole_lane(road, 0, 1)
    assert_equal(g.vertex_count(), 4)
    assert_equal(g.triangle_count(), 2)
    _near(_at(g, 0), 0.0, 3.5, 0.0)
    _near(_at(g, 1), 0.0, 0.0, 0.0)
    _near(_at(g, 2), 30.0, 3.5, 0.0)
    _near(_at(g, 3), 30.0, 0.0, 0.0)
    # Faces point up; u is the offset from lane 0, v is s.
    _near(_normal(g, 0), 0.0, 0.0, 1.0)
    var uv = _uv(g, UV, 0)
    assert_almost_equal(uv[0], 3.5, atol=1e-6)
    uv = _uv(g, UV, 3)
    assert_almost_equal(uv[0], 0.0, atol=1e-6)
    assert_almost_equal(uv[1], 30.0, atol=1e-4)
    assert_equal(len(g.groups), 1)
    assert_equal(g.groups[0].material_index.value, ROAD_SURFACE.value)
    assert_false(g.has_attribute(UV1))
    # Lane 0 has no surface.
    assert_equal(factory.generate_whole_lane(road, 0, 2).vertex_count(), 0)
    factory.road_param.resolution = _m(0)
    with assert_raises():
        _ = factory.generate_whole_lane(road, 0, 1)


def test_curved_lane() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    ref road = map.road(RoadId(11))
    # Rows every 2 m to 30 m, then one at the end: 17 rows. A junction's
    # driving lane widens by a meter each side.
    var g = factory.generate_whole_lane(road, 0, 1)
    assert_equal(g.vertex_count(), 34)
    assert_equal(g.triangle_count(), 32)
    _near(_at(g, 0), 60.0, 4.5, 0.0)
    _near(_at(g, 1), 60.0, -1.0, 0.0)
    _near(_at(g, 10), 67.43109584836515, 6.397470290699226, 0.0, 1e-3)
    _near(_at(g, 11), 70.06793631068827, 1.5707662003021756, 0.0, 1e-3)
    for i in range(34):
        assert_true(_normal(g, i).z > 0.99)
    # The sidewalk is not widened.
    var walk = factory.generate_whole_lane(road, 0, 0)
    _near(_at(walk, 10), 66.95167030976094, 7.2750528525895986, 0.1524, 1e-3)
    assert_equal(walk.groups[0].material_index.value, SIDEWALK_SURFACE.value)


def test_tesselated_lane() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    ref road = map.road(RoadId(1))
    # Rows every 2 m from 0 to 28 m, then one at 30 m: 16 rows of 4.
    var g = factory.generate_whole_tesselated(road, 0, 1)
    assert_equal(g.vertex_count(), 64)
    assert_equal(g.triangle_count(), 90)
    _near(_at(g, 5), 2.0, 3.5 - 3.5 / 3.0, 0.0)
    var grid = _uv(g, UV1, 5)
    assert_equal(grid[0], 1.0)
    assert_equal(grid[1], 1.0)
    var uv = _uv(g, UV, 5)
    assert_almost_equal(uv[0], 3.5 - 3.5 / 3.0, atol=1e-5)
    assert_almost_equal(uv[1], 2.0, atol=1e-5)
    _near(_normal(g, 5), 0.0, 0.0, 1.0)
    assert_equal(
        factory.generate_whole_tesselated(road, 0, 2).vertex_count(), 0
    )
    # Fewer than two vertices across still makes two.
    factory.road_param.vertex_width_resolution = 1.0
    assert_equal(
        factory.generate_whole_tesselated(road, 0, 1).vertex_count(), 32
    )


def test_sidewalk_block() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    ref road = map.road(RoadId(1))
    var g = factory.generate_whole_sidewalk(road, 0, 0)
    assert_equal(g.vertex_count(), 96)
    assert_equal(g.triangle_count(), 90)
    # The row: under the outer edge, the outer edge twice, the inner edge
    # twice, and under it.
    _near(_at(g, 6), 2.0, 5.5, 0.1524 - 1.0)
    _near(_at(g, 7), 2.0, 5.5, 0.1524)
    _near(_at(g, 9), 2.0, 3.5, 0.1524)
    _near(_at(g, 11), 2.0, 3.5, 0.1524 - 1.0)
    # The top faces up, the outer curb outward, the inner curb inward.
    _near(_normal(g, 8), 0.0, 0.0, 1.0)
    _near(_normal(g, 6), 0.0, 1.0, 0.0)
    _near(_normal(g, 11), 0.0, -1.0, 0.0)
    assert_equal(len(g.groups), 2)
    assert_equal(g.groups[0].material_index.value, SIDEWALK_SURFACE.value)
    assert_equal(g.groups[0].count, 90)
    assert_equal(g.groups[1].material_index.value, CURB_SURFACE.value)
    assert_equal(g.groups[1].count, 180)
    assert_equal(_uv(g, UV1, 9)[0], 2.0)
    # A driving lane made a block wears the road kind on top.
    var driving = factory.generate_whole_sidewalk(road, 0, 1)
    assert_equal(driving.groups[0].material_index.value, ROAD_SURFACE.value)
    assert_equal(factory.generate_whole_sidewalk(road, 0, 2).vertex_count(), 0)
    # Every lane of the section: four blocks and lane 0's nothing.
    assert_equal(
        factory.generate_section_sidewalks(road, 0).vertex_count(), 384
    )


def test_walls() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    ref road = map.road(RoadId(1))
    var g = factory.generate_walls(road, 0)
    assert_equal(g.vertex_count(), 8)
    assert_equal(g.triangle_count(), 4)
    # Lanes come in order of id: first the right wall, on lane -2's first
    # edge, 0.6 m high, then the left wall on lane 2's second edge.
    _near(_at(g, 0), 0.0, 5.5, 0.7524)
    _near(_at(g, 1), 0.0, 5.5, 0.1524)
    _near(_at(g, 4), 0.0, -5.5, 0.1524)
    _near(_at(g, 5), 0.0, -5.5, 0.7524)
    # Both face the road.
    _near(_normal(g, 0), 0.0, -1.0, 0.0)
    _near(_normal(g, 4), 0.0, 1.0, 0.0)
    assert_equal(g.groups[0].material_index.value, WALL_SURFACE.value)
    var right = factory.generate_right_wall(road, 0, 1, 1.0, 5.0)
    assert_equal(right.vertex_count(), 4)
    var left = factory.generate_left_wall(road, 0, 2, 1.0, 5.0)
    assert_equal(left.vertex_count(), 0)
    # A curved wall has a row every resolution: 17 rows on lane -1's
    # second edge and 17 on lane -2's first.
    ref turn = map.road(RoadId(11))
    assert_equal(factory.generate_walls(turn, 0).vertex_count(), 68)
    # A section with lanes on one side only walls that side twice.
    var b = MapBuilder()
    _ = _road(b, 1, 0, 10, -1, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    _ = _road(
        b,
        2,
        20,
        10,
        -1,
        True,
        0,
        0,
        [(0, LANE_NONE, 0.0), (1, LANE_DRIVING, 3.5)],
    )
    _ = _road(b, 3, 40, 10, -1, True, 0, 0, [(0, LANE_NONE, 0.0)])
    var small = b.build()
    assert_equal(
        factory.generate_walls(small.road(RoadId(1)), 0).vertex_count(), 8
    )
    assert_equal(
        factory.generate_walls(small.road(RoadId(2)), 0).vertex_count(), 8
    )
    assert_equal(
        factory.generate_walls(small.road(RoadId(3)), 0).vertex_count(), 0
    )
    var empty = MapBuilder()
    var r = empty.add_road(
        RoadId(1), "", 10, JuncId(-1), RoadId(0), RoadId(0), True
    )
    _ = empty.add_road_section(r, SectionId(0), 0.0)
    with assert_raises():
        _ = factory.generate_walls(empty.roads[0], 0)


def test_sections_roads_and_chunks() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    ref road = map.road(RoadId(1))
    # Four lanes of four vertices, and lane 0's none.
    assert_equal(factory.generate_section(road, 0).vertex_count(), 16)
    assert_equal(factory.generate_road(road).vertex_count(), 32)
    assert_equal(len(factory.generate_with_max_len(road)), 2)
    assert_equal(len(factory.generate_walls_with_max_len(road)), 2)
    var all = factory.generate_all_with_max_len(road)
    assert_equal(len(all), 2)
    # Each chunk holds its section's lanes and walls.
    assert_equal(all[0].vertex_count(), 24)
    # A junction road has no walls.
    var junction = factory.generate_all_with_max_len(map.road(RoadId(10)))
    assert_equal(junction[0].vertex_count(), 8)
    # A 120 m section is cut at 50 and 100 m.
    var b = MapBuilder()
    _ = _road(b, 1, 0, 120, -1, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    var long = b.build()
    ref far = long.road(RoadId(1))
    var chunks = factory.generate_with_max_len(far)
    assert_equal(len(chunks), 3)
    _near(_at(chunks[1], 0), 50.0, 3.5, 0.0)
    _near(_at(chunks[2], 2), 120.0, 3.5, 0.0)
    assert_equal(len(factory.generate_walls_with_max_len(far)), 3)
    # A 100 m section is cut once, at 50 m.
    b = MapBuilder()
    _ = _road(b, 1, 0, 100, -1, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    var even = b.build()
    assert_equal(len(factory.generate_with_max_len(even.road(RoadId(1)))), 2)


def test_ordered_meshes() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    ref road = map.road(RoadId(1))
    var out = OrderedMeshes()
    factory.generate_lane_section_ordered(road, 0, out)
    assert_equal(len(out.types), 3)
    assert_equal(out.types[0], LANE_NONE)
    assert_equal(out.types[1], LANE_DRIVING)
    assert_equal(out.types[2], LANE_SIDEWALK)
    assert_equal(len(out.meshes[1]), 2)
    assert_equal(out.meshes[1][0].vertex_count(), 64)
    assert_equal(out.meshes[2][0].vertex_count(), 96)
    assert_equal(out.find(LANE_SHOULDER), -1)
    # A second section stitches its first lanes onto the meshes already
    # there, as CARLA does, and adds the rest.
    factory.generate_lane_section_ordered(road, 1, out)
    assert_equal(len(out.meshes[2]), 3)
    assert_equal(out.meshes[2][0].vertex_count(), 192)
    # Stitching joins the rows with 5 quads across.
    assert_equal(out.meshes[2][0].triangle_count(), 190)
    assert_equal(len(out.meshes[1]), 3)
    assert_equal(out.meshes[1][1].vertex_count(), 128)
    assert_equal(len(out.meshes[0]), 2)
    # The road keeps each type's meshes from the first section only.
    var whole = factory.generate_ordered_with_max_len(road)
    assert_equal(len(whole.meshes[1]), 2)
    var into = OrderedMeshes()
    factory.generate_all_ordered_with_max_len(road, into)
    factory.generate_all_ordered_with_max_len(road, into)
    assert_equal(len(into.meshes[1]), 4)
    # A long section: two stitched chunks and a tail added plain.
    var b = MapBuilder()
    _ = _road(
        b,
        1,
        0,
        120,
        -1,
        True,
        0,
        0,
        [(-1, LANE_DRIVING, 3.5), (0, LANE_NONE, 0.0), (1, LANE_SHOULDER, 3.5)],
    )
    var long = b.build()
    var chunked = factory.generate_section_ordered_with_max_len(
        long.road(RoadId(1)), 0
    )
    assert_equal(len(chunked.types), 3)
    var driving = chunked.find(LANE_DRIVING)
    assert_equal(len(chunked.meshes[driving]), 1)
    # Three chunks of 26 rows, 26 rows and 11 rows, four across.
    assert_equal(chunked.meshes[driving][0].vertex_count(), 252)
    var shoulder = chunked.find(LANE_SHOULDER)
    assert_equal(len(chunked.meshes[shoulder]), 3)
    # Lane 0 sits at place 1: its second chunk is new, its tail joins it.
    var none = chunked.find(LANE_NONE)
    assert_equal(len(chunked.meshes[none]), 2)
    # A shoulder at place 0 is a block stitched two vertices wide: two
    # chunks of 26 rows of six, one curb quad between them, and a tail of
    # 11 rows added plain.
    b = MapBuilder()
    _ = _road(
        b,
        1,
        0,
        120,
        -1,
        True,
        0,
        0,
        [
            (-2, LANE_SHOULDER, 3.5),
            (-1, LANE_DRIVING, 3.5),
            (0, LANE_NONE, 0.0),
        ],
    )
    var edge = b.build()
    var parts = factory.generate_section_ordered_with_max_len(
        edge.road(RoadId(1)), 0
    )
    ref block = parts.meshes[parts.find(LANE_SHOULDER)][0]
    assert_equal(block.vertex_count(), 378)
    assert_equal(block.triangle_count(), 362)
    assert_equal(_kind_triangles(block, CURB_SURFACE), 242)
    assert_equal(_kind_triangles(block, ROAD_SURFACE), 120)


def test_stitching() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    ref road = map.road(RoadId(1))
    var a = factory.generate_whole_lane(road, 0, 1)
    var b = factory.generate_whole_lane(road, 1, 1)
    var joined = factory.generate_whole_lane(road, 0, 1)
    concat_geometry(joined, b, 2, [ROAD_SURFACE])
    assert_equal(joined.vertex_count(), 8)
    assert_equal(joined.triangle_count(), 6)
    var plain = factory.generate_whole_lane(road, 0, 1)
    append_geometry(plain, b)
    assert_equal(plain.triangle_count(), 4)
    var empty = factory.generate_whole_lane(road, 0, 2)
    concat_geometry(joined, empty, 2, [ROAD_SURFACE])
    assert_equal(joined.vertex_count(), 8)
    var five: List[SurfaceKind] = [
        CURB_SURFACE,
        CURB_SURFACE,
        ROAD_SURFACE,
        CURB_SURFACE,
        CURB_SURFACE,
    ]
    with assert_raises():
        concat_geometry(empty, a, 6, five)
    # Each quad of the stitch needs a kind.
    with assert_raises():
        concat_geometry(joined, b, 3, [ROAD_SURFACE])
    # A stitch one vertex wide adds no quads.
    var single = factory.generate_whole_lane(road, 0, 1)
    concat_geometry(single, b, 1, List[SurfaceKind]())
    assert_equal(single.vertex_count(), 8)
    assert_equal(single.triangle_count(), 4)
    # Geometries with CARLA's grid and no vertices join to nothing.
    var hollow = _hollow()
    append_geometry(hollow, _hollow())
    assert_equal(hollow.vertex_count(), 0)
    assert_true(hollow.has_attribute(UV1))
    # A part without CARLA's grid joins one with it, and the other way.
    var grid = factory.generate_whole_tesselated(road, 0, 1)
    append_geometry(grid, a)
    assert_equal(grid.vertex_count(), 68)
    assert_true(grid.has_attribute(UV1))
    var plain2 = factory.generate_whole_lane(road, 0, 1)
    append_geometry(plain2, factory.generate_whole_tesselated(road, 0, 1))
    assert_true(plain2.has_attribute(UV1))
    assert_equal(_uv(plain2, UV1, 0)[0], 0.0)
    var bare = BufferGeometry()
    append_geometry(bare, a)
    assert_equal(bare.vertex_count(), 4)


def test_three_frame() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    var g = factory.generate_whole_lane(map.road(RoadId(1)), 0, 1)
    var three = to_three_frame(g)
    _near(_at(three, 0), 0.0, 0.0, 3.5)
    # Up in CARLA is up in three.js, and the faces still face it.
    _near(_normal(three, 0), 0.0, 1.0, 0.0)
    assert_equal(three.index[1], g.index[2])
    assert_equal(three.index[2], g.index[1])
    var again = three.clone()
    again.compute_vertex_normals()
    _near(_normal(again, 0), 0.0, 1.0, 0.0)


def test_smoothing() raises:
    # Two overlapping bent lanes, one at 0 m and one at 1 m. Heights from
    # the Python copy of `MergeAndSmooth`.
    var b = MapBuilder()
    _ = _road(b, 1, 0, 10, -1, True, 0.0, 1e-12, [(-1, LANE_DRIVING, 3.5)])
    _ = _road(b, 2, -2, 10, -1, True, 1.0, 1e-12, [(-1, LANE_DRIVING, 3.5)])
    var map = b.build()
    var factory = MeshFactory()
    var lanes = List[BufferGeometry]()
    lanes.append(factory.generate_whole_lane(map.road(RoadId(1)), 0, 0))
    lanes.append(factory.generate_whole_lane(map.road(RoadId(2)), 0, 0))
    var g = factory.merge_and_smooth(lanes)
    assert_equal(g.vertex_count(), 24)
    var a: List[Float64] = [
        0.0,
        0.0,
        0.0,
        0.2322391,
        0.4030235,
        0.3218586,
        0.4202321,
        0.3472787,
        0.3551175,
        0.2649834,
        0.0,
        0.0,
    ]
    var c: List[Float64] = [
        1.0,
        1.0,
        1.0,
        0.6199124,
        0.6451265,
        0.5373051,
        0.6325635,
        0.5290906,
        0.7188254,
        0.6253787,
        1.0,
        1.0,
    ]
    for i in range(12):
        assert_almost_equal(Float64(_at(g, i).z), a[i], atol=1e-5)
        assert_almost_equal(Float64(_at(g, 12 + i).z), c[i], atol=1e-5)
    # A lone short lane has nothing to move.
    var short = List[BufferGeometry]()
    short.append(factory.generate_whole_lane(map.road(RoadId(1)), 0, 0))
    factory.road_param.max_weight_distance = _m(0.1)
    var still = factory.merge_and_smooth(short)
    _near(_at(still, 5), 4.0, 0.0, 0.0)


def test_edges_for_lanemark() raises:
    var factory = MeshFactory()
    var b = MapBuilder()
    _ = _road(
        b,
        1,
        0,
        10,
        -1,
        True,
        0,
        0,
        [(-2, LANE_DRIVING, 0.0), (-1, LANE_DRIVING, 3.5), (0, LANE_NONE, 0.0)],
    )
    _ = _road(
        b,
        2,
        20,
        10,
        -1,
        True,
        0,
        0,
        [(-1, LANE_DRIVING, 0.0), (0, LANE_NONE, 0.0)],
    )
    var map = b.build()
    ref road = map.road(RoadId(1))
    var e = factory.compute_edges_for_lanemark(road, 0, 1, 5.0, 0.2, 0.0)
    _near(e[0], 5.0, 3.5, 0.0)
    _near(e[1], 5.0, 3.3, 0.0)
    # A lane of no width borrows lane -1's direction.
    e = factory.compute_edges_for_lanemark(road, 0, 0, 5.0, 0.2, 0.0)
    _near(e[0], 5.0, 3.5, 0.0)
    _near(e[1], 5.0, 3.3, 0.0)
    # With no lane of any width the mark has no width either.
    e = factory.compute_edges_for_lanemark(
        map.road(RoadId(2)), 0, 0, 5.0, 0.2, 0.0
    )
    _near(e[1], 5.0, -20.0, 0.0)


def test_lane_marks() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    # Broken: dashes at 0-6, 12-18 and 24-30 m, then the closing row.
    var broken = _mark(
        factory.generate_lane_marks_for_not_center_line(
            map.road(RoadId(1)), 0, 1
        )
    )
    assert_equal(broken.color, "white")
    assert_equal(broken.geometry.vertex_count(), 14)
    assert_equal(broken.geometry.triangle_count(), 6)
    _near(_at(broken.geometry, 0), 0.0, 3.5, 0.0)
    _near(_at(broken.geometry, 1), 0.0, 3.35, 0.0)
    _near(_at(broken.geometry, 2), 6.0, 3.5, 0.0)
    _near(_at(broken.geometry, 4), 12.0, 3.5, 0.0)
    _near(_at(broken.geometry, 11), 30.0, 3.35, 0.0)
    assert_equal(
        broken.geometry.groups[0].material_index.value, WHITE_MARK_SURFACE.value
    )
    _near(_normal(broken.geometry, 0), 0.0, 0.0, 1.0)
    var uv = _uv(broken.geometry, UV, 1)
    assert_almost_equal(uv[0], 0.15, atol=1e-5)
    # Solid: a row every 2 m, each joined to the next, then the closing
    # row at the section's end.
    var solid = _mark(
        factory.generate_lane_marks_for_not_center_line(
            map.road(RoadId(1)), 1, 1
        )
    )
    assert_equal(solid.geometry.vertex_count(), 32)
    assert_equal(solid.geometry.triangle_count(), 30)
    _near(_at(solid.geometry, 31), 60.0, 4.35, 0.0)
    # The center line: solid yellow, 0.3 m, centered.
    var center = _mark(
        factory.generate_lane_marks_for_center_line(map.road(RoadId(1)), 0, 2)
    )
    assert_equal(center.color, "yellow")
    assert_equal(center.geometry.vertex_count(), 32)
    _near(_at(center.geometry, 0), 0.0, 0.15, 0.0)
    _near(_at(center.geometry, 1), 0.0, -0.15, 0.0)
    assert_equal(
        center.geometry.groups[0].material_index.value,
        YELLOW_MARK_SURFACE.value,
    )
    # Broken yellow in the second section runs toward lane -2's inside.
    var dashes = _mark(
        factory.generate_lane_marks_for_center_line(map.road(RoadId(1)), 1, 2)
    )
    assert_equal(dashes.geometry.vertex_count(), 14)
    _near(_at(dashes.geometry, 0), 30.0, 0.0, 0.0)
    _near(_at(dashes.geometry, 1), 30.0, -0.15, 0.0)
    _near(_at(dashes.geometry, 12), 60.0, 0.075, 0.0)
    # No mark at the section's start: CARLA loops; this gives nothing.
    assert_false(
        factory.generate_lane_marks_for_not_center_line(
            map.road(RoadId(10)), 0, 0
        )
    )
    # A type CARLA does not draw gives nothing.
    assert_false(
        factory.generate_lane_marks_for_not_center_line(
            map.road(RoadId(6)), 0, 2
        )
    )
    var marks = List[LaneMarkMesh]()
    var info = List[String]()
    factory.generate_lane_mark_for_road(map.road(RoadId(1)), marks, info)
    assert_equal(len(marks), 6)
    assert_equal(len(info), 6)
    assert_true(
        info == ["white", "yellow", "white", "white", "yellow", "white"]
    )
    var left_hand = List[LaneMarkMesh]()
    var words = List[String]()
    factory.generate_lane_mark_for_road(map.road(RoadId(6)), left_hand, words)
    assert_equal(len(left_hand), 2)
    assert_true(words == ["white", "yellow", "white"])
    # A lane 0 that is not of type none has no center mark.
    var b = MapBuilder()
    _ = _road(
        b,
        1,
        0,
        10,
        -1,
        True,
        0,
        0,
        [(0, LANE_DRIVING, 0.0), (-1, LANE_DRIVING, 3.5)],
    )
    var odd = b.build()
    var none = List[LaneMarkMesh]()
    var none_info = List[String]()
    factory.generate_lane_mark_for_road(odd.road(RoadId(1)), none, none_info)
    assert_equal(len(none_info), 1)


# --- the map's meshes -----------------------------------------------------


def test_map_mesh() raises:
    var map = load_opendrive_file(TOWN)
    var g = generate_mesh(map, _m(2))
    assert_true(g.vertex_count() > 0)
    var flat = generate_mesh(map, _m(2), _m(0.6), False)
    assert_equal(flat.vertex_count(), g.vertex_count())
    with assert_raises():
        _ = generate_mesh(map, _m(0))


def test_chunked_mesh() raises:
    var b = MapBuilder()
    _ = _road(
        b,
        1,
        0,
        30,
        -1,
        True,
        0,
        0,
        [(-1, LANE_DRIVING, 3.5), (0, LANE_NONE, 0.0)],
    )
    _ = _road(b, 2, 70, 30, -1, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    _ = _road(
        b,
        3,
        0,
        10,
        5,
        True,
        0,
        0,
        [(-1, LANE_DRIVING, 3.5), (-2, LANE_SIDEWALK, 2.0)],
    )
    _ = _road(b, 4, 0, 10, 5, True, 0, 0, [(0, LANE_NONE, 0.0)])
    b.add_junction(JuncId(5), "j")
    b.add_connection(JuncId(5), ConId(0), RoadId(1), RoadId(3))
    b.add_connection(JuncId(5), ConId(1), RoadId(1), RoadId(4))
    var map = b.build()
    var params = OpendriveGenerationParameters()
    # Road 1 starts at y = 3.5 and road 2 at y = -66.5 (CARLA's frame):
    # a grid 1 by 2 of 50 m cells. The junction starts with road 1.
    var chunks = generate_chunked_mesh(map, params)
    assert_equal(len(chunks), 2)
    # Road 2 alone: its lane and, on the section's only side lane, both
    # walls. Then road 1 the same, and the junction's lane and sidewalk.
    assert_equal(chunks[0].vertex_count(), 12)
    assert_equal(chunks[1].vertex_count(), 12 + 8)
    params.smooth_junctions = False
    var plain = generate_chunked_mesh(map, params)
    assert_equal(plain[1].vertex_count(), 20)
    var empty = MapBuilder()
    _ = _road(empty, 1, 0, 10, -1, True, 0, 0, [(0, LANE_NONE, 0.0)])
    with assert_raises():
        _ = generate_chunked_mesh(empty.build(), params)


def test_filters() raises:
    var map = load_opendrive_file(TOWN)
    var kept = filter_junctions_by_position(
        map, Vector3(0, 100, 0), Vector3(100, 0, 0)
    )
    assert_equal(len(kept), 1)
    assert_equal(
        len(
            filter_junctions_by_position(
                map, Vector3(80, 100, 0), Vector3(100, 0, 0)
            )
        ),
        0,
    )
    assert_equal(
        len(
            filter_junctions_by_position(
                map, Vector3(0, 100, 0), Vector3(70, 0, 0)
            )
        ),
        0,
    )
    assert_equal(
        len(
            filter_junctions_by_position(
                map, Vector3(0, 5, 0), Vector3(100, 0, 0)
            )
        ),
        0,
    )
    assert_equal(
        len(
            filter_junctions_by_position(
                map, Vector3(0, 100, 0), Vector3(100, 10, 0)
            )
        ),
        0,
    )
    # Every road of the town is in this box: CARLA's y test runs from the
    # larger y down.
    var roads = filter_roads_by_position(
        map, Vector3(-100, 500, 0), Vector3(200, -500, 0)
    )
    assert_equal(len(roads), 8)
    var few = filter_roads_by_position(
        map, Vector3(-100, 50, 0), Vector3(200, -50, 0)
    )
    assert_equal(len(few), 5)
    # A road with neither lane -1 nor lane 1 uses its innermost driving
    # lane; one with no driving lane is left out.
    var b = MapBuilder()
    _ = _road(
        b,
        1,
        0,
        10,
        -1,
        True,
        0,
        0,
        [
            (-2, LANE_DRIVING, 3.5),
            (-3, LANE_DRIVING, 3.5),
            (0, LANE_NONE, 0.0),
            (2, LANE_SIDEWALK, 2.0),
        ],
    )
    _ = _road(b, 2, 20, 10, -1, True, 0, 0, [(-1, LANE_SIDEWALK, 3.5)])
    _ = _road(b, 3, 40, 10, -1, False, 0, 0, [(1, LANE_DRIVING, 3.5)])
    var small = b.build()
    var some = filter_roads_by_position(
        small, Vector3(-100, 500, 0), Vector3(200, -500, 0)
    )
    assert_equal(len(some), 3)
    var bare = MapBuilder()
    _ = bare.add_road(RoadId(1), "", 10, JuncId(-1), RoadId(0), RoadId(0), True)
    with assert_raises():
        _ = filter_roads_by_position(
            bare.build(), Vector3(-1, 1, 0), Vector3(1, -1, 0)
        )


def test_junction_meshes() raises:
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    var out = OrderedMeshes()
    # Three connections: the sidewalk off the driving lanes is kept.
    generate_single_junction(map, factory, JuncId(100), out)
    var driving = out.find(LANE_DRIVING)
    var walks = out.find(LANE_SIDEWALK)
    assert_equal(len(out.meshes[driving]), 1)
    assert_equal(out.meshes[walks][0].vertex_count(), 17 * 6)
    with assert_raises():
        generate_single_junction(map, factory, JuncId(1), out)
    # Two connections keep every sidewalk; a sidewalk on a driving lane in
    # a busier junction is dropped.
    var b = MapBuilder()
    _ = _road(
        b,
        1,
        0,
        10,
        5,
        True,
        0,
        0,
        [(-1, LANE_DRIVING, 3.5), (-2, LANE_SIDEWALK, 2.0)],
    )
    _ = _road(b, 2, 0, 10, 5, True, 0, 0, [(-1, LANE_SIDEWALK, 3.5)])
    _ = _road(b, 3, 0, 10, 6, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    b.add_junction(JuncId(5), "two")
    b.add_connection(JuncId(5), ConId(0), RoadId(9), RoadId(1))
    b.add_connection(JuncId(5), ConId(1), RoadId(9), RoadId(2))
    b.add_junction(JuncId(6), "three")
    b.add_connection(JuncId(6), ConId(0), RoadId(9), RoadId(1))
    b.add_connection(JuncId(6), ConId(1), RoadId(9), RoadId(2))
    b.add_connection(JuncId(6), ConId(2), RoadId(9), RoadId(3))
    var small = b.build()
    var two = OrderedMeshes()
    generate_single_junction(small, factory, JuncId(5), two)
    # A sidewalk block has a row every 2 m: six rows of six on 10 m.
    assert_equal(two.meshes[two.find(LANE_SIDEWALK)][0].vertex_count(), 72)
    var three = OrderedMeshes()
    generate_single_junction(small, factory, JuncId(6), three)
    assert_equal(three.meshes[three.find(LANE_SIDEWALK)][0].vertex_count(), 36)
    var region = generate_ordered_chunked_mesh_in_locations(
        map,
        OpendriveGenerationParameters(),
        Vector3(-100, 500, 0),
        Vector3(200, -500, 0),
    )
    # None, driving, shoulder, biking, sidewalk, border and parking.
    assert_equal(len(region.types), 7)
    var boxes = junctions_bounding_boxes(map)
    assert_equal(len(boxes), 1)
    _near(boxes[0].min, 52.5, -7.1875, 0.0)
    _near(boxes[0].max, 97.5, 25.4375, 0.0)


def test_trees() raises:
    var map = load_opendrive_file(TOWN)
    var trees = trees_transform(
        map, Vector3(-1, 50, 0), Vector3(61, -50, 0), _m(10), _m(2)
    )
    # Road 1 only: both sections, beside lane -1, 2 m out. Positions retain
    # `GetTreesTransform` parity. The geometric yaw is atan(0.025), as
    # tools/generate_carla_lane_orientation_controls.py derives.
    assert_equal(len(trees), 6)
    _near(trees[0].transform.location, 0.0, 5.5, 0.0)
    _near(trees[5].transform.location, 50.0, 6.0, 0.0)
    assert_almost_equal(
        trees[5].transform.rotation.yaw, 1.4320961841646465, atol=1e-4
    )
    assert_equal(trees[0].type, "Town")
    with assert_raises():
        _ = trees_transform(
            map, Vector3(-1, 50, 0), Vector3(61, -50, 0), _m(0), _m(2)
        )
    # A one-way road with only left lanes uses the outermost; a road with
    # no driving lane has none; a lane of no width has none; a lane barely
    # wider than nothing is skipped.
    var b = MapBuilder()
    _ = _road(
        b,
        1,
        0,
        10,
        -1,
        True,
        0,
        0,
        [(1, LANE_DRIVING, 3.5), (2, LANE_DRIVING, 3.5), (0, LANE_NONE, 0.0)],
    )
    _ = _road(b, 2, 20, 10, -1, True, 0, 0, [(-1, LANE_SIDEWALK, 3.5)])
    _ = _road(
        b,
        3,
        40,
        10,
        -1,
        True,
        0,
        0,
        [(-1, LANE_DRIVING, 0.0), (1, LANE_DRIVING, 3.5)],
    )
    _ = _road(
        b,
        4,
        60,
        10,
        -1,
        True,
        0,
        0,
        [(-1, LANE_DRIVING, 0.00001), (-2, LANE_DRIVING, 0.00001)],
    )
    _ = _road(b, 5, 80, 10, 5, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    var small = b.build()
    var some = trees_transform(
        small, Vector3(-100, 500, 0), Vector3(200, -500, 0), _m(5), _m(1), _m(1)
    )
    assert_equal(len(some), 2)
    _near(some[0].transform.location, 1.0, -8.0, 0.0)


def test_crosswalk_mesh() raises:
    var map = load_opendrive_file(TOWN)
    var g = all_crosswalk_mesh(map)
    assert_equal(g.vertex_count(), 8)
    assert_equal(g.triangle_count(), 4)
    _near(_at(g, 0), 8.5, 6.0, 0.0)
    _near(_normal(g, 0), 0.0, 0.0, 1.0)
    assert_equal(g.groups[0].material_index.value, CROSSWALK_SURFACE.value)
    var uv = _uv(g, UV, 0)
    assert_equal(uv[0], 8.5)
    # A clockwise outline is turned to face up; one that never closes is
    # dropped; a map with none gives nothing.
    var b = MapBuilder()
    var r = _road(
        b,
        1,
        0,
        30,
        -1,
        True,
        0,
        0,
        [(-1, LANE_DRIVING, 3.5), (0, LANE_NONE, 0.0)],
    )
    var cw: List[CrosswalkPoint] = [
        CrosswalkPoint(-1, -1, 0),
        CrosswalkPoint(-1, 1, 0),
        CrosswalkPoint(1, 1, 0),
        CrosswalkPoint(1, -1, 0),
        CrosswalkPoint(-1, -1, 0),
    ]
    b.add_road_object_crosswalk(r, "cw", 5, 0, 0, 0, 0, 0, "", 2, 2, cw)
    var open: List[CrosswalkPoint] = [
        CrosswalkPoint(-1, -1, 0),
        CrosswalkPoint(1, -1, 0),
        CrosswalkPoint(1, 1, 0),
    ]
    b.add_road_object_crosswalk(r, "open", 20, 0, 0, 0, 0, 0, "", 2, 2, open)
    var small = b.build()
    var turned = all_crosswalk_mesh(small)
    assert_equal(turned.vertex_count(), 4)
    _near(_normal(turned, 0), 0.0, 0.0, 1.0)
    var none = MapBuilder()
    _ = _road(none, 1, 0, 10, -1, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    assert_equal(all_crosswalk_mesh(none.build()).vertex_count(), 0)


def test_line_markings() raises:
    var map = load_opendrive_file(TOWN)
    var info = List[String]()
    var marks = generate_line_markings(
        map,
        OpendriveGenerationParameters(),
        Vector3(-100, 500, 0),
        Vector3(200, -500, 0),
        info,
    )
    # Road 1 gives 6, road 6 gives 2; road 2, 3, 5 and 7 have no marks.
    assert_equal(len(marks), 8)
    assert_true(len(info) > len(marks))


def _bare(
    mut b: MapBuilder, id: Int, junction: Int, sections: List[Float64]
) raises -> Int:
    # A flat, straight 10 m road with its records and sections that have
    # no lanes.
    var r = b.add_road(
        RoadId(id), "bare", 10.0, JuncId(junction), RoadId(0), RoadId(0), True
    )
    for i in range(len(sections)):
        _ = b.add_road_section(r, SectionId(i), sections[i])
    b.create_section_offset(r, 0.0, 0, 0, 0, 0)
    b.add_road_elevation_profile(r, 0.0, 0, 0, 0, 0)
    b.add_road_geometry_line(r, 0.0, 0.0, 20.0 * Float64(id), 0.0, 10.0)
    return r


def test_single_rows() raises:
    # A span that ends before it starts gives one row and no triangles.
    var map = load_opendrive_file(TOWN)
    var factory = MeshFactory()
    var straight = map.road(RoadId(1)).copy()
    var lane = factory.generate_lane(straight, 0, 1, 10.0, 5.0)
    assert_equal(lane.vertex_count(), 2)
    assert_equal(len(lane.index), 0)
    var curved = factory.generate_lane(map.road(RoadId(11)), 0, 1, 10.0, 5.0)
    assert_equal(curved.vertex_count(), 2)
    var grid = factory.generate_tesselated(straight, 0, 1, 10.0, 5.0)
    assert_equal(grid.vertex_count(), 4)
    assert_equal(len(grid.index), 0)
    var block = factory.generate_sidewalk(straight, 0, 1, 10.0, 5.0)
    assert_equal(block.vertex_count(), 6)
    assert_equal(len(block.index), 0)
    # Lane 0 has no vertices, in either frame.
    var none = factory.generate_lane(straight, 0, 2, 0.5, 5.0)
    assert_equal(to_three_frame(none).vertex_count(), 0)
    # Two copies of a lane: each vertex has a twin that weighs nothing,
    # and the flat lane stays flat.
    var copy = factory.generate_whole_lane(map.road(RoadId(11)), 0, 1)
    var twice = factory.merge_and_smooth([copy.clone(), copy.clone()])
    assert_equal(twice.vertex_count(), 2 * copy.vertex_count())
    _near(_at(twice, 7), Float64(_at(copy, 7).x), Float64(_at(copy, 7).y), 0.0)
    # The regions below keep no road of the town: one lies east of it,
    # one south of it in CARLA's reversed y test.
    assert_equal(
        len(
            filter_roads_by_position(
                map, Vector3(1000, 1000, 0), Vector3(2000, -1000, 0)
            )
        ),
        0,
    )
    assert_equal(
        len(
            filter_roads_by_position(
                map, Vector3(-1000, -1000, 0), Vector3(1000, -2000, 0)
            )
        ),
        0,
    )


def test_empty_map_meshes() raises:
    var b = MapBuilder()
    var empty = b.build()
    var params = OpendriveGenerationParameters()
    assert_equal(generate_mesh(empty, _m(2.0)).vertex_count(), 0)
    with assert_raises():
        _ = generate_chunked_mesh(empty, params)
    var everywhere = (Vector3(-1000, 1000, 0), Vector3(1000, -1000, 0))
    assert_equal(
        len(filter_junctions_by_position(empty, everywhere[0], everywhere[1])),
        0,
    )
    assert_equal(
        len(filter_roads_by_position(empty, everywhere[0], everywhere[1])), 0
    )
    var ordered = generate_ordered_chunked_mesh_in_locations(
        empty, params, everywhere[0], everywhere[1]
    )
    assert_equal(len(ordered.types), 0)
    assert_equal(
        len(
            trees_transform(empty, everywhere[0], everywhere[1], _m(10), _m(1))
        ),
        0,
    )
    var colors = List[String]()
    assert_equal(
        len(
            generate_line_markings(
                empty, params, everywhere[0], everywhere[1], colors
            )
        ),
        0,
    )
    assert_equal(len(junctions_bounding_boxes(empty)), 0)
    assert_equal(all_crosswalk_mesh(empty).vertex_count(), 0)


def test_roads_with_no_lanes() raises:
    var b = MapBuilder()
    # Road 1 has no sections, road 2 one with no lanes and a crosswalk of
    # one corner, road 9 a first section 4e-15 m long. Junction 7 holds
    # road 3, with no sections, and road 4, with a section that has no
    # lanes; junction 8 connects nothing.
    _ = _bare(b, 1, -1, List[Float64]())
    var r2 = _bare(b, 2, -1, [0.0])
    b.add_road_object_crosswalk(
        r2,
        "dot",
        5.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        "+",
        1.0,
        1.0,
        [CrosswalkPoint(1.0, 1.0, 0.0), CrosswalkPoint(1.0, 1.0, 0.0)],
    )
    _ = _bare(b, 9, -1, [0.0, 4.0e-15])
    _ = _bare(b, 3, 7, List[Float64]())
    _ = _bare(b, 4, 7, [0.0])
    b.add_junction(JuncId(7), "j")
    b.add_connection(JuncId(7), ConId(0), RoadId(0), RoadId(3))
    b.add_connection(JuncId(7), ConId(1), RoadId(0), RoadId(4))
    b.add_junction(JuncId(8), "k")
    var map = b.build()
    var factory = MeshFactory()
    var none = map.road(RoadId(1)).copy()
    var bare = map.road(RoadId(2)).copy()
    var marks = List[LaneMarkMesh]()
    var colors = List[String]()
    factory.generate_lane_mark_for_road(none, marks, colors)
    factory.generate_lane_mark_for_road(bare, marks, colors)
    assert_equal(len(marks), 0)
    assert_equal(len(colors), 0)
    assert_equal(factory.generate_road(none).vertex_count(), 0)
    assert_equal(factory.generate_road(bare).vertex_count(), 0)
    assert_equal(factory.generate_section(bare, 0).vertex_count(), 0)
    assert_equal(factory.generate_section_sidewalks(bare, 0).vertex_count(), 0)
    with assert_raises():
        _ = factory.generate_walls(bare, 0)
    assert_equal(len(factory.generate_with_max_len(none)), 0)
    assert_equal(len(factory.generate_walls_with_max_len(none)), 0)
    assert_equal(len(factory.generate_all_with_max_len(none)), 0)
    assert_equal(len(factory.generate_ordered_with_max_len(none).types), 0)
    var into = OrderedMeshes()
    factory.generate_all_ordered_with_max_len(none, into)
    assert_equal(len(into.types), 0)
    factory.generate_lane_section_ordered(bare, 0, into)
    assert_equal(len(into.types), 0)
    assert_equal(len(factory.generate_ordered_with_max_len(bare).types), 0)
    # Cut in 5 m chunks, the bare section gives empty chunks, and no
    # walls.
    var short = MeshFactory()
    short.road_param.max_road_len = _m(5.0)
    var chunks = short.generate_section_with_max_len(bare, 0)
    assert_equal(len(chunks), 2)
    assert_equal(chunks[0].vertex_count(), 0)
    assert_equal(
        len(short.generate_section_ordered_with_max_len(bare, 0).types), 0
    )
    with assert_raises():
        _ = short.generate_section_walls_with_max_len(bare, 0)
    # A section shorter than two epsilons has no chunk at all.
    var tiny = map.road(RoadId(9)).copy()
    var fine = MeshFactory()
    fine.road_param.max_road_len = _m(3.0e-15)
    assert_equal(len(fine.generate_section_with_max_len(tiny, 0)), 0)
    assert_equal(len(fine.generate_section_walls_with_max_len(tiny, 0)), 0)
    assert_equal(
        len(fine.generate_section_ordered_with_max_len(tiny, 0).types), 0
    )
    # A chunk must have a length.
    var zero = MeshFactory()
    zero.road_param.max_road_len = _m(0.0)
    with assert_raises():
        _ = zero.generate_section_with_max_len(bare, 0)
    # The junctions add no vertices. The bare road cannot have walls, so
    # the map cannot be chunked.
    assert_equal(generate_mesh(map, _m(2.0)).vertex_count(), 0)
    with assert_raises():
        _ = generate_chunked_mesh(map, OpendriveGenerationParameters())
    var out = OrderedMeshes()
    generate_single_junction(map, factory, JuncId(7), out)
    generate_single_junction(map, factory, JuncId(8), out)
    assert_equal(out.meshes[out.find(LANE_DRIVING)][1].vertex_count(), 0)
    # A road with no sections cannot be placed.
    with assert_raises():
        _ = filter_roads_by_position(
            map, Vector3(-1000, 1000, 0), Vector3(1000, -1000, 0)
        )
    # A one-corner outline closes at once and makes one vertex.
    var dot = all_crosswalk_mesh(map)
    assert_equal(dot.vertex_count(), 1)
    assert_equal(len(dot.index), 0)


def test_placing_roads_with_no_lanes() raises:
    var b = MapBuilder()
    # Road 2's section has no lanes, so it has no place. Road 5's second
    # section has no lanes, so it has no trees.
    _ = _bare(b, 2, -1, [0.0])
    var r5 = _road(
        b,
        5,
        0,
        20,
        -1,
        True,
        0,
        0,
        [(-1, LANE_DRIVING, 3.5), (0, LANE_NONE, 0.0)],
    )
    _ = b.add_road_section(r5, SectionId(1), 10.0)
    var map = b.build()
    var low = Vector3(-1000, 1000, 0)
    var high = Vector3(1000, -1000, 0)
    var kept = filter_roads_by_position(map, low, high)
    assert_equal(len(kept), 1)
    assert_equal(kept[0], RoadId(5))
    # Trees every 4 m on the first section only: at 0, 4 and 8 m.
    assert_equal(len(trees_transform(map, low, high, _m(4), _m(1))), 3)


def test_junction_edges() raises:
    # A junction with no sidewalks is one chunk of its lane alone: a
    # straight lane is two rows of two.
    var b = MapBuilder()
    _ = _road(b, 6, 0, 20, 3, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    b.add_junction(JuncId(3), "plain")
    b.add_connection(JuncId(3), ConId(0), RoadId(0), RoadId(6))
    var plain = b.build()
    var chunks = generate_chunked_mesh(plain, OpendriveGenerationParameters())
    assert_equal(len(chunks), 1)
    assert_equal(chunks[0].vertex_count(), 4)
    # Road 60's sidewalk lies only in a section 1e-8 m long. Its middle,
    # rounded to a float, falls in the section before, which lacks the
    # lane, so a junction of three connections cannot test it.
    b = MapBuilder()
    var r = _road(b, 60, 0, 20, 50, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    var starts: List[Float64] = [10.00000001, 10.00000002]
    for i in range(2):
        var sec = b.add_road_section(r, SectionId(i + 1), starts[i])
        var ids: List[Int] = [-2, -1] if i == 0 else [-1]
        for id in ids:
            _ = b.add_road_section_lane(
                r,
                sec,
                LaneId(id),
                LANE_SIDEWALK if id == -2 else LANE_DRIVING,
                False,
                LaneId(0),
                LaneId(0),
            )
            b.create_lane_width(
                b.lane(RoadId(60), LaneId(id), starts[i]),
                starts[i],
                3.5,
                0,
                0,
                0,
            )
    _ = _road(b, 61, 10, 20, 50, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    _ = _road(b, 62, 20, 20, 50, True, 0, 0, [(-1, LANE_DRIVING, 3.5)])
    b.add_junction(JuncId(50), "three")
    for i in range(3):
        b.add_connection(JuncId(50), ConId(i), RoadId(0), RoadId(60 + i))
    var three = b.build()
    var out = OrderedMeshes()
    with assert_raises():
        generate_single_junction(three, MeshFactory(), JuncId(50), out)


def test_tree_outer_lane_uses_sorted_builder_order() raises:
    var builder = MapBuilder()
    var right = _road(
        builder,
        1,
        0,
        10,
        -1,
        True,
        0,
        0,
        [
            (-1, LANE_DRIVING, 3.5),
            (-3, LANE_SIDEWALK, 2.0),
            (1, LANE_DRIVING, 3.5),
            (-2, LANE_DRIVING, 3.5),
            (0, LANE_NONE, 0.0),
        ],
    )
    # Re-inserting an existing lane changes no ordering or count.
    _ = builder.add_road_section_lane(
        right, 0, LaneId(-2), LANE_DRIVING, False, LaneId(0), LaneId(0)
    )
    assert_equal(len(builder.roads[right].sections[0].lanes), 5)
    var expected: List[Int] = [-3, -2, -1, 0, 1]
    for index in range(5):
        assert_equal(
            builder.roads[right].sections[0].lanes[index].id.value,
            expected[index],
        )
    _ = _road(
        builder,
        2,
        20,
        10,
        -1,
        True,
        0,
        0,
        [
            (2, LANE_DRIVING, 3.5),
            (3, LANE_SIDEWALK, 2.0),
            (0, LANE_NONE, 0.0),
            (1, LANE_DRIVING, 3.5),
        ],
    )
    var map = builder.build()
    var trees = trees_transform(
        map, Vector3(-100, 100, 0), Vector3(100, -100, 0), _m(20), _m(1)
    )
    assert_equal(len(trees), 2)
    _near(trees[0].transform.location, 0, 8, 0)
    # OpenDRIVE y=20 becomes CARLA y=-20; the left border is 8m farther.
    _near(trees[1].transform.location, 0, -28, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
