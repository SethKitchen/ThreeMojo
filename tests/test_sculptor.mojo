# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the sculptor: `geometries.sculptor`, `sculptor_mesh`,
`sculptor_tools` and `sculptor_utils`.

The expected numbers come from three.js r186's own `Sculptor`, run headless
in Node on the same meshes and strokes. Two meshes serve:

- The bumpy plane: three.js's `PlaneGeometry(2, 2, 8, 8)` with each
  vertex's z set to `x y / 4 + x^2 / 8 - y^2 / 16`. Every coordinate is a
  sum of halves, so both sides store the same `Float32`s.
- The box: `BoxGeometry(1, 1, 1, 4, 4, 4)`, welded to 98 vertices.

A ray's origin and direction are exact in `Float32` too, and each radius is
a sum of halves, so a ray stroke matches three.js to the rounding of the
last operation. A pointer's ray is unprojected in `Float32` here and in
doubles in three.js, so the pointer tests allow more.

Each case compares a summary of the whole mesh: the counts, a checksum of
every triangle's corners, the sums of the coordinates, of their squares
and of the drawn normals, the hit, and one vertex.
"""

from cameras.perspective_camera import PerspectiveCamera
from controls.input import PointerButton, SECONDARY
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from core.geometry_store import GeometryId
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from geometries.sculptor import (
    _compact_dirty_vertices,
    SCULPT_BRUSH,
    SCULPT_CHANGE,
    SCULPT_CLAY,
    SCULPT_CREASE,
    SCULPT_DRAG,
    SCULPT_END,
    SCULPT_FLATTEN,
    SCULPT_INFLATE,
    SCULPT_PINCH,
    SCULPT_SCALE,
    SCULPT_SMOOTH,
    SCULPT_START,
    SculptTool,
    Sculptor,
    SculptorEventKind,
)
from geometries.sculptor_mesh import NO_CELL, OCTREE_MAX_DEPTH, SculptorMesh
from geometries.sculptor_tools import (
    _DecData,
    _SubData,
    _dec_decimate_triangles,
    _dec_find_opposite_triangle,
    _fill_split,
    _half_edge_split,
    _sub_fill_triangles,
    _unit_or_x,
    area_normal,
    has_at_least_three_common_elements,
    laplacian_smooth,
    smooth_tangent_verts,
    tool_crease,
    tool_flatten,
    tool_inflate,
)
from geometries.sculptor_utils import (
    MAX_FLAG,
    Point3,
    distance_sq_to_segment,
    distance_sq_to_triangle,
    falloff,
    intersection_ray_triangle,
    js_max,
    js_min,
    remove_element,
    replace_element,
    tidy,
)
from materials.material import Material
from math.ray import Ray
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import inf, isnan, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

# A ray stroke rounds as three.js's does; the sums of 81 or more
# coordinates add rounding of their own.
comptime EXACT = Float64(1e-6)
comptime SUMS = Float64(1e-5)
# A pointer's ray is unprojected in `Float32`.
comptime POINTER = Float64(2e-4)


@fieldwise_init
struct Expected(ImplicitlyCopyable):
    """A summary of a sculpted mesh, as the Node script prints it."""

    var nv: Int
    var nf: Int
    var check: Int
    var sx: Float64
    var sy: Float64
    var sz: Float64
    var sq: Float64
    var nsum: Float64
    var hx: Float64
    var hy: Float64
    var hz: Float64
    var nx: Float64
    var ny: Float64
    var nz: Float64
    var radius: Float64
    var k: Int
    var vx: Float64
    var vy: Float64
    var vz: Float64


def _expect(sculptor: Sculptor, e: Expected, tolerance: Float64) raises:
    """Assert a sculptor's mesh matches a summary.

    Args:
        sculptor: The sculptor.
        e: The summary three.js printed.
        tolerance: How far a coordinate may be off; sums get ten times it.

    Raises:
        Error: If anything differs.
    """
    ref mesh = sculptor.sculpt_mesh()
    assert_equal(mesh.nb_vertices, e.nv)
    assert_equal(mesh.nb_faces, e.nf)
    var check = 0
    for i in range(mesh.nb_faces):
        check += (
            mesh.triangles[i * 3]
            + 7 * mesh.triangles[i * 3 + 1]
            + 13 * mesh.triangles[i * 3 + 2]
        ) * (i % 97 + 1)
    assert_equal(check, e.check)
    var sx = 0.0
    var sy = 0.0
    var sz = 0.0
    var sq = 0.0
    var nsum = 0.0
    for i in range(mesh.nb_vertices):
        var x = Float64(mesh.vertices[i * 3])
        var y = Float64(mesh.vertices[i * 3 + 1])
        var z = Float64(mesh.vertices[i * 3 + 2])
        sx += x
        sy += y
        sz += z
        sq += x * x + y * y + z * z
        nsum += (
            Float64(mesh.render_normals[i * 3])
            + 2 * Float64(mesh.render_normals[i * 3 + 1])
            + 3 * Float64(mesh.render_normals[i * 3 + 2])
        )
    var sums = tolerance * 10
    assert_almost_equal(sx, e.sx, atol=sums)
    assert_almost_equal(sy, e.sy, atol=sums)
    assert_almost_equal(sz, e.sz, atol=sums)
    assert_almost_equal(sq, e.sq, atol=sums)
    assert_almost_equal(nsum, e.nsum, atol=sums)
    var hit = sculptor.get_hit_point()
    assert_almost_equal(Float64(hit.x), e.hx, atol=tolerance)
    assert_almost_equal(Float64(hit.y), e.hy, atol=tolerance)
    assert_almost_equal(Float64(hit.z), e.hz, atol=tolerance)
    var normal = sculptor.get_hit_normal()
    assert_almost_equal(Float64(normal.x), e.nx, atol=tolerance)
    assert_almost_equal(Float64(normal.y), e.ny, atol=tolerance)
    assert_almost_equal(Float64(normal.z), e.nz, atol=tolerance)
    assert_almost_equal(
        Float64(sculptor.get_world_radius().value), e.radius, atol=tolerance
    )
    assert_almost_equal(Float64(mesh.vertices[e.k * 3]), e.vx, atol=tolerance)
    assert_almost_equal(
        Float64(mesh.vertices[e.k * 3 + 1]), e.vy, atol=tolerance
    )
    assert_almost_equal(
        Float64(mesh.vertices[e.k * 3 + 2]), e.vz, atol=tolerance
    )


def _bumpy() raises -> BufferGeometry:
    """Return the bumpy plane of the module docstring.

    Returns:
        The geometry.

    Raises:
        Error: If the plane is refused.
    """
    var geometry = plane(Length(2.0, METER), Length(2.0, METER), 8, 8)
    var position = geometry.clone_attribute(String(POSITION))
    for i in range(position.count()):
        var x = position.component(i, 0)
        var y = position.component(i, 1)
        position.set_component(
            i, 2, 0.25 * x * y + 0.125 * x * x - 0.0625 * y * y
        )
    geometry.set_attribute(String(POSITION), position^)
    return geometry^


def _box() raises -> BufferGeometry:
    """Return the box of the module docstring.

    Returns:
        The geometry.

    Raises:
        Error: If the box is refused.
    """
    return box(
        Length(1.0, METER), Length(1.0, METER), Length(1.0, METER), 4, 4, 4
    )


def _scene(
    var geometry: BufferGeometry, mut assets: Assets, var node: Object3D
) raises -> Scene:
    """Return a scene of one mesh.

    Args:
        geometry: The mesh's geometry.
        assets: Where the geometry and a material go.
        node: The mesh's node.

    Returns:
        The scene, its mesh at place zero.

    Raises:
        Error: If the scene is refused.
    """
    var scene = Scene()
    var id = assets.geometries.add(geometry^)
    var material = assets.materials.add(Material(Color(255, 255, 255)))
    var at = scene.add(node^)
    scene.update()
    scene.add_mesh(Mesh(id, material, at))
    return scene^


def _ray(ox: Float32, oy: Float32, oz: Float32, dx: Float32, dy: Float32, dz: Float32) raises -> Ray:
    """Return a ray.

    Args:
        ox: The origin's x.
        oy: Its y.
        oz: Its z.
        dx: The direction's x.
        dy: Its y.
        dz: Its z.

    Returns:
        The ray.

    Raises:
        Error: If the direction has no length.
    """
    return Ray(Vector3(ox, oy, oz), Vector3(dx, dy, dz))


def _down() raises -> Ray:
    """Return the ray the tool tests stroke with.

    Returns:
        A ray straight down -z through (0.1875, 0.0625).

    Raises:
        Error: Never.
    """
    return _ray(0.1875, 0.0625, 3, 0, 0, -1)


def _camera() raises -> PerspectiveCamera:
    """Return the pointer tests' camera: 50 degrees, three meters up +z.

    Returns:
        The camera.

    Raises:
        Error: If the camera is refused.
    """
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
    return camera^


def _tool_case(
    tool: SculptTool, negative: Bool, e: Expected
) raises:
    """Stroke the bumpy plane once with a tool at detail zero, and compare.

    Args:
        tool: The tool.
        negative: Whether it works the other way.
        e: What three.js made.

    Raises:
        Error: If the mesh differs.
    """
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(tool)
    sculptor.set_detail(0)
    sculptor.set_negative(negative)
    assert_true(
        sculptor.stroke_from_ray(scene, assets, _down(), Length(0.625, METER))
    )
    _expect(sculptor, e, EXACT)


# --- the helpers ---------------------------------------------------------------


def test_falloff_is_one_at_the_center_and_zero_at_the_rim() raises:
    assert_equal(falloff(0), 1)
    assert_equal(falloff(1), 0)
    assert_equal(falloff(0.5), 0.6875)


def test_a_ray_meets_a_triangle_inside_it_only() raises:
    var a = Point3(0, 0, 0)
    var b = Point3(1, 0, 0)
    var c = Point3(0, 1, 0)
    var down = Point3(0, 0, -1)
    assert_equal(intersection_ray_triangle(Point3(0.25, 0.25, 1), down, a, b, c), 1)
    # Parallel.
    assert_equal(
        intersection_ray_triangle(Point3(0.25, 0.25, 1), Point3(1, 0, 0), a, b, c),
        -1,
    )
    # Outside each edge.
    assert_equal(intersection_ray_triangle(Point3(-0.5, 0.25, 1), down, a, b, c), -1)
    assert_equal(intersection_ray_triangle(Point3(1.5, 0.25, 1), down, a, b, c), -1)
    assert_equal(intersection_ray_triangle(Point3(0.25, -0.5, 1), down, a, b, c), -1)
    assert_equal(intersection_ray_triangle(Point3(0.75, 0.75, 1), down, a, b, c), -1)
    # Behind the origin.
    assert_equal(
        intersection_ray_triangle(Point3(0.25, 0.25, -1), down, a, b, c), -1
    )


def test_the_distance_to_a_triangle_in_each_region() raises:
    var a = Point3(0, 0, 0)
    var b = Point3(1, 0, 0)
    var c = Point3(0, 1, 0)
    assert_equal(distance_sq_to_triangle(Point3(-1, -1, 0), a, b, c), 2)
    assert_equal(distance_sq_to_triangle(Point3(2, -1, 0), a, b, c), 2)
    assert_equal(distance_sq_to_triangle(Point3(0.5, -1, 0), a, b, c), 1)
    assert_equal(distance_sq_to_triangle(Point3(-1, 2, 0), a, b, c), 2)
    assert_equal(distance_sq_to_triangle(Point3(-1, 0.5, 0), a, b, c), 1)
    assert_equal(distance_sq_to_triangle(Point3(1, 1, 0), a, b, c), 0.5)
    assert_equal(distance_sq_to_triangle(Point3(0.25, 0.25, 1), a, b, c), 1)
    # A flat triangle is measured to its edges.
    assert_equal(
        distance_sq_to_triangle(
            Point3(0.5, 1, 0), a, b, Point3(2, 0, 0)
        ),
        1,
    )
    assert_equal(distance_sq_to_triangle(Point3(0, 1, 0), a, a, b), 1)


def test_the_distance_to_a_segment() raises:
    var a = Point3(0, 0, 0)
    var b = Point3(1, 0, 0)
    assert_equal(distance_sq_to_segment(Point3(3, 0, 0), a, b), 4)
    assert_equal(distance_sq_to_segment(Point3(-2, 0, 0), a, b), 4)
    assert_equal(distance_sq_to_segment(Point3(0.5, 2, 0), a, b), 4)
    assert_equal(distance_sq_to_segment(Point3(0, 2, 0), a, a), 4)


def test_list_helpers_act_as_three_js_does() raises:
    var values: List[Int] = [3, 1, 3, 2, 1]
    tidy(values)
    assert_equal(len(values), 3)
    assert_equal(values[0], 1)
    assert_equal(values[2], 3)
    var one: List[Int] = [5]
    tidy(one)
    assert_equal(len(one), 1)
    var ring: List[Int] = [4, 5, 6]
    replace_element(ring, 5, 9)
    replace_element(ring, 7, 1)
    assert_equal(ring[1], 9)
    remove_element(ring, 4)
    remove_element(ring, 8)
    assert_equal(len(ring), 2)
    assert_equal(ring[0], 6)
    assert_true(has_at_least_three_common_elements([1, 2, 3, 5], [0, 2, 3, 4, 5]))
    assert_false(has_at_least_three_common_elements([1, 2, 6], [2, 3, 6]))


def test_min_and_max_carry_a_nan_as_javascript_does() raises:
    assert_true(isnan(js_min(nan[DType.float64](), 1)))
    assert_true(isnan(js_min(1, nan[DType.float64]())))
    assert_true(isnan(js_max(nan[DType.float64](), 1)))
    assert_true(isnan(js_max(1, nan[DType.float64]())))
    assert_equal(js_min(1, 2), 1)
    assert_equal(js_max(1, 2), 2)


# --- the mesh ------------------------------------------------------------------


def test_the_bumpy_plane_welds_as_three_js_does() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    _expect(
        sculptor,
        Expected(81, 128, 4637754, 0.0, 0.0, 2.109375, 68.64532470703125, 234.51774644851685,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            40, 0.0, 0.0, 0.0),
        EXACT,
    )
    # 128 faces are more than a cell holds, so the root splits.
    ref mesh = sculptor.sculpt_mesh()
    assert_equal(len(mesh.cells[mesh.octree].children), 8)
    # The mesh draws the sculpted geometry now; the source is unchanged.
    assert_equal(scene.meshes[0].geometry.value, 1)
    assert_equal(assets.geometries.get(scene.meshes[0].geometry).vertex_count(), 81)
    assert_equal(assets.geometries.get(scene.meshes[0].geometry).triangle_count(), 128)
    assert_equal(assets.geometries.get(sculptor.geometry).vertex_count(), 81)
    assert_equal(len(sculptor.events), 0)


def test_the_box_welds_its_seams() raises:
    var assets = Assets()
    var scene = _scene(_box(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    _expect(
        sculptor,
        Expected(98, 192, 10387823, 0.0, 0.0, 0.0, 43.5, 0.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            40, -0.5, -0.25, -0.5),
        EXACT,
    )
    # A closed box has no open edge.
    ref mesh = sculptor.sculpt_mesh()
    for i in range(mesh.nb_vertices):
        assert_equal(mesh.vert_on_edge[i], 0)


def _triangles(var positions: List[Float32], var index: List[Int]) raises -> BufferGeometry:
    """Return a geometry of positions and an index.

    Args:
        positions: Three numbers per position.
        index: Three positions per triangle, or empty for none.

    Returns:
        The geometry.

    Raises:
        Error: If the attribute is refused.
    """
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    if len(index) > 0:
        geometry.set_index(index^)
    return geometry^


def test_a_geometry_the_mesh_cannot_weld_is_refused() raises:
    var mesh = SculptorMesh()
    with assert_raises(contains="position attribute"):
        mesh.init_from_geometry(BufferGeometry())
    var flat = BufferGeometry()
    flat.set_attribute(String(POSITION), BufferAttribute([0.0, 0.0, 1.0, 0.0], 2))
    with assert_raises(contains="position attribute"):
        mesh.init_from_geometry(flat)
    with assert_raises(contains="complete"):
        mesh.init_from_geometry(_triangles([0, 0, 0, 1, 0, 0], []))
    with assert_raises(contains="valid positions"):
        mesh.init_from_geometry(_triangles([0, 0, 0, 1, 0, 0, 0, 1, 0], [0, 1, 3]))
    var negative = _triangles([0, 0, 0, 1, 0, 0, 0, 1, 0], [0, 1, 2])
    negative.index[2] = -1
    with assert_raises(contains="valid positions"):
        mesh.init_from_geometry(negative)
    with assert_raises(contains="finite"):
        mesh.init_from_geometry(
            _triangles([0, 0, 0, 1, 0, 0, 0, inf[DType.float32](), 0], [])
        )
    with assert_raises(contains="degenerate"):
        mesh.init_from_geometry(_triangles([0, 0, 0, 1, 0, 0, 1, 0, 0], []))
    with assert_raises(contains="zero-area"):
        mesh.init_from_geometry(_triangles([0, 0, 0, 1, 0, 0, 2, 0, 0], []))
    with assert_raises(contains="fit in Float32"):
        mesh.init_from_geometry(
            _triangles([0, 0, 0, 1e30, 0, 0, 0, 1e30, 0], [])
        )


def test_positions_no_triangle_names_are_not_read() raises:
    # The fourth position is not a number, and no triangle names it.
    var mesh = SculptorMesh()
    mesh.init_from_geometry(
        _triangles(
            [0, 0, 0, 1, 0, 0, 0, 1, 0, nan[DType.float32](), 0, 0], [0, 1, 2]
        )
    )
    assert_equal(mesh.nb_vertices, 3)
    assert_equal(mesh.nb_faces, 1)
    # Every vertex of a lone triangle is on an open edge.
    assert_equal(mesh.vert_on_edge[0], 1)


def test_positions_nearer_than_the_tolerance_weld() raises:
    # Three triangles side by side. Two corners round to the same
    # `Float32`s, and one lies less than a ten-millionth of the width
    # from another, in the next weld cell.
    var mesh = SculptorMesh()
    mesh.init_from_geometry(
        _triangles(
            [
                0, 0, 0, 1, 0, 0, 0, 1, 0,
                1, 0, 0, 1.00000005, 1, 0, 0, 1.00000002, 0,
                0.99999995, 0.00000003, 0, 2, 0, 0, 1, 1, 0,
            ],
            [],
        )
    )
    assert_equal(mesh.nb_vertices, 5)
    assert_equal(mesh.faces[3], 1)
    assert_equal(mesh.faces[5], 2)
    assert_equal(mesh.faces[6], 1)


def test_the_tags_start_again_past_the_largest_flag() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_triangles([0, 0, 0, 1, 0, 0, 0, 1, 0], []))
    mesh.tag_flag = MAX_FLAG
    mesh.vert_tag_flags[0] = -1
    mesh.vert_tag_flags[1] = 7
    mesh.faces_tag_flags[0] = 9
    assert_equal(mesh.next_tag_flag(), 1)
    assert_equal(mesh.vert_tag_flags[0], -1)
    assert_equal(mesh.vert_tag_flags[1], 0)
    assert_equal(mesh.faces_tag_flags[0], 0)
    mesh.sculpt_flag = MAX_FLAG
    mesh.vert_sculpt_flags[2] = 5
    assert_equal(mesh.next_sculpt_flag(), 1)
    assert_equal(mesh.vert_sculpt_flags[2], 0)
    assert_equal(mesh.next_sculpt_flag(), 2)


def test_the_lists_grow_and_shrink_with_room_to_spare() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_triangles([0, 0, 0, 1, 0, 0, 0, 1, 0], []))
    mesh.re_allocate_arrays(0)
    assert_equal(mesh.buffer_version, 0)
    mesh.re_allocate_arrays(5)
    assert_equal(len(mesh.faces_tag_flags), 12)
    assert_equal(len(mesh.vert_on_edge), 16)
    assert_equal(len(mesh.vertices), 48)
    assert_equal(mesh.buffer_version, 2)
    mesh.re_allocate_arrays(0)
    assert_equal(len(mesh.faces_tag_flags), 2)
    assert_equal(len(mesh.vert_on_edge), 6)
    assert_equal(Float64(mesh.vertices[3]), 1)
    assert_equal(mesh.buffer_version, 4)


def _cluster() raises -> BufferGeometry:
    """Return one large triangle and 101 copies of one small one, whose
    boxes all share a center.

    Returns:
        The geometry.

    Raises:
        Error: If the geometry is refused.
    """
    var positions: List[Float32] = [
        0, 0, 0, 1, 0, 0, 0, 1, 1,
        0.25, 0.25, 0.25, 0.25390625, 0.25, 0.25, 0.25, 0.25390625, 0.25,
    ]
    var index: List[Int] = [0, 1, 2]
    for _ in range(101):
        index.append(3)
        index.append(4)
        index.append(5)
    return _triangles(positions^, index^)


def test_a_cell_stops_splitting_at_the_deepest_level() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_cluster())
    var leaf = mesh.face_leaf[1]
    assert_equal(mesh.cells[leaf].depth, OCTREE_MAX_DEPTH)
    assert_equal(len(mesh.cells[leaf].faces), 101)
    # Queued, it is still too deep to split.
    _ = mesh.intersect_sphere(Point3(0.25, 0.25, 0.25), 0.01, True)
    assert_true(mesh.cells[leaf].queued_for_update)
    mesh.balance_octree()
    assert_equal(len(mesh.cells[leaf].children), 0)
    assert_false(mesh.cells[leaf].queued_for_update)


def test_empty_leaves_prune_up_the_tree() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_bumpy())
    var root = mesh.octree
    var first = mesh.cells[root].children[0]
    var busy = -1
    for child in mesh.cells[root].children:
        if len(mesh.cells[child].faces) > 0:
            busy = child
    assert_true(busy >= 0)
    # A sibling holds faces, so nothing is pruned.
    mesh._prune_if_possible(first if first != busy else mesh.cells[root].children[1])
    assert_equal(len(mesh.cells[root].children), 8)
    # With every leaf empty, the root's children go.
    for child in mesh.cells[root].children:
        mesh.cells[child].faces = List[Int]()
    mesh._prune_if_possible(first)
    assert_equal(len(mesh.cells[root].children), 0)
    # A leaf whose parent was pruned already stops at once.
    mesh._prune_if_possible(first)
    assert_equal(len(mesh.cells[root].children), 0)


def test_balance_prunes_an_empty_queued_leaf() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_bumpy())
    var root = mesh.octree
    for child in mesh.cells[root].children:
        mesh.cells[child].faces = List[Int]()
    mesh._queue_leaf(mesh.cells[root].children[3])
    mesh._queue_leaf(mesh.cells[root].children[3])
    assert_equal(len(mesh.leaves_to_update), 1)
    mesh.balance_octree()
    assert_equal(len(mesh.cells[root].children), 0)
    assert_equal(len(mesh.leaves_to_update), 0)


def test_a_face_moved_out_of_its_cell_changes_cells() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_bumpy())
    var old_leaf = mesh.face_leaf[0]
    # Face 0 is at the top-left corner. Moving its corners across the
    # plane puts its center in another cell.
    for corner in range(3):
        var vertex = mesh.faces[corner]
        mesh.vertices[vertex * 3] += 1.5
        mesh.vertices[vertex * 3 + 1] -= 1.5
    var faces = mesh.get_faces_from_vertices(
        [mesh.faces[0], mesh.faces[1], mesh.faces[2]]
    )
    var vertices = mesh.get_vertices_from_faces(faces)
    mesh.update_geometry(faces, vertices)
    assert_true(mesh.face_leaf[0] != old_leaf)
    assert_true(0 in mesh.cells[mesh.face_leaf[0]].faces)
    assert_false(0 in mesh.cells[old_leaf].faces)
    assert_true(mesh.cells[old_leaf].queued_for_update)
    # A face moved outside the root rebuilds the whole octree.
    var vertex = mesh.faces[0]
    mesh.vertices[vertex * 3 + 2] = 40
    faces = mesh.get_faces_from_vertices([vertex])
    vertices = mesh.get_vertices_from_faces(faces)
    mesh.update_geometry(faces, vertices)
    assert_true(mesh.cells[mesh.octree].aabb_split[5] > 40)
    assert_equal(len(mesh.leaves_to_update), 0)


def test_a_flat_mesh_gets_a_thick_octree() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_triangles([0, 0, 0, 1, 0, 0, 0, 1, 0], []))
    ref loose = mesh.cells[mesh.octree].aabb_loose
    assert_true(loose[2] < 0)
    assert_true(loose[5] > 0)


def test_the_ring_helpers_walk_out_by_rings() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_bumpy())
    # The center vertex has six faces and six neighbors.
    assert_equal(len(mesh.expands_faces(mesh.vert_ring_face[40].copy(), 0)), 6)
    assert_equal(len(mesh.expands_faces(mesh.vert_ring_face[40].copy(), 1)), 24)
    assert_equal(len(mesh.expands_vertices([40], 1)), 7)
    assert_equal(len(mesh.expands_vertices([40], 2)), 19)
    assert_equal(len(mesh.get_vertices_from_faces([])), 0)
    assert_equal(len(mesh.get_faces_from_vertices([])), 0)


def test_tools_leave_a_vertex_with_no_normal_in_place() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_bumpy())
    for axis in range(3):
        mesh.normals[40 * 3 + axis] = 0
    var before = mesh.vertices[40 * 3 + 2]
    smooth_tangent_verts(mesh, [40], 1.0)
    assert_equal(mesh.vertices[40 * 3 + 2], before)
    # Inflate moves it by the bare weight, along no direction.
    tool_inflate(mesh, [40], Point3(0, 0, 0), 1, 1, False)
    assert_equal(mesh.vertices[40 * 3 + 2], before)
    assert_false(Bool(area_normal(mesh, [40])))
    assert_false(Bool(area_normal(mesh, [])))


def test_a_vertex_of_two_neighbors_does_not_smooth() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_triangles([0, 0, 0, 1, 0, 0, 0, 1, 0], []))
    var smooth = laplacian_smooth(mesh, [1])
    assert_equal(smooth[0], 1)
    assert_equal(smooth[1], 0)


# --- the tools, against three.js -------------------------------------------------


def test_clay() raises:
    _tool_case(SCULPT_CLAY, False, Expected(81, 128, 4637754, -0.016182709268832696, -0.010114216711372137, 2.368298187619075, 68.64774097821294, 234.52042172929214,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, -0.0017621340230107307, -0.0011013337643817067, 0.028194144368171692))
    _tool_case(SCULPT_CLAY, True, Expected(81, 128, 4637754, 0.014231848859708407, 0.008894969912944362, 1.8816646803170443, 68.64995578392566, 234.39349019423685,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, 0.0017566508613526821, 0.0010979067301377654, -0.028106413781642914))


def test_brush() raises:
    _tool_case(SCULPT_BRUSH, False, Expected(81, 128, 4637754, -0.015204753612124478, -0.009824724129430251, 2.352679194882512, 68.64846682105848, 234.52752230864098,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, -0.001759099424816668, -0.0011366637190803885, 0.028148826211690903))
    _tool_case(SCULPT_BRUSH, True, Expected(81, 128, 4637754, 0.01520472380980209, 0.009824724129430251, 1.8660708055831492, 68.65236626559832, 234.385615828156,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, 0.001759099424816668, 0.0011366637190803885, -0.028148826211690903))


def test_inflate() raises:
    _tool_case(SCULPT_INFLATE, False, Expected(81, 128, 4637754, -0.008935195142839802, -0.0054019989765947685, 2.2546324887662195, 68.64427876534961, 234.53873470906592,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, 0.0, 0.0, 0.016935979947447777))
    _tool_case(SCULPT_INFLATE, True, Expected(81, 128, 4637754, 0.008935075933550252, 0.005402028778917156, 1.9641175109427422, 68.65003663740157, 234.4521857541372,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, 0.0, 0.0, -0.016935979947447777))


def test_smooth() raises:
    var smoothed = Expected(81, 128, 4637754, 0.0, 0.0, 2.2265625, 68.64935302734375, 234.5687120826915,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, 0.0, 0.0, 0.005859375)
    _tool_case(SCULPT_SMOOTH, False, smoothed)
    _tool_case(SCULPT_SMOOTH, True, smoothed)


def test_flatten() raises:
    _tool_case(SCULPT_FLATTEN, False, Expected(81, 128, 4637754, -0.002802337191951665, -0.001751527938495201, 2.1542132588729146, 68.6440083839744, 234.52675963123147,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, -0.000004112421720492421, -0.0000025702634047775064, 0.00006579874752787873))
    _tool_case(SCULPT_FLATTEN, True, Expected(81, 128, 4637754, 0.001339310978210051, 0.0008370667146664346, 2.087946394458413, 68.64441984192479, 234.50815130281262,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, 0.0, 0.0, 0.0))


def test_pinch() raises:
    _tool_case(SCULPT_PINCH, False, Expected(81, 128, 4637754, 0.0014987094982643612, -0.000855712394695729, 2.109010985965142, 68.585277864175, 234.5245138778111,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, 0.00635099271312356, 0.002116997493430972, 0.00029770276159979403))
    _tool_case(SCULPT_PINCH, True, Expected(81, 128, 4637754, -0.0014986498936195858, 0.0008556676912121475, 2.109739012637874, 68.70645961417279, 234.51065442637017,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, -0.00635099271312356, -0.002116997493430972, -0.00029770276159979403))


def test_crease() raises:
    _tool_case(SCULPT_CREASE, False, Expected(81, 128, 4637754, -0.003725498099811375, -0.004960993392160162, 2.2020557206124067, 68.56237016385305, 234.52091058821023,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, 0.007661925163120031, 0.0021693629678338766, 0.02009047381579876))
    _tool_case(SCULPT_CREASE, True, Expected(81, 128, 4637754, 0.007921996410004795, 0.0025651442410890013, 2.015675058530178, 68.56455530110416, 234.47082854769613,
        0.1875, 0.0625, 0.0087890625, -0.062320554675837726, -0.04026919265852434, 0.9972434710678866, 0.625,
        40, 0.010120853781700134, 0.0037582300137728453, -0.01925690658390522))


def test_smooth_keeps_an_open_edge_on_its_edge() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(SCULPT_SMOOTH)
    _ = sculptor.stroke_from_ray(
        scene, assets, _ray(0.9375, 0.0625, 3, 0, 0, -1), Length(0.375, METER)
    )
    _expect(sculptor, Expected(81, 128, 4637754, 0.0, 0.0, 2.1123046875, 68.64541912078857, 234.6201238259673,
        0.9375, 0.0625, 0.1259765625, -0.20100109330309437, -0.20710611652226932, 0.9574474486832293, 0.375,
        40, 0.0, 0.0, 0.0), EXACT)


def test_smooth_at_the_box_corner() raises:
    var assets = Assets()
    var scene = _scene(_box(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(SCULPT_SMOOTH)
    sculptor.set_detail(1)
    _ = sculptor.stroke_from_ray(
        scene, assets, _ray(2, 0.4375, 0.3125, -1, 0, 0), Length(0.5, METER)
    )
    _expect(sculptor, Expected(98, 192, 10387823, -0.34375, -0.28125, -0.109375, 42.738525390625, 4.815569147467613,
        0.5, 0.4375, 0.3125, 0.7314715230996512, 0.5748670165001809, 0.36671150000300895, 0.5,
        40, -0.5, -0.25, -0.5), EXACT)


# --- the adaptive topology, against three.js ------------------------------------


def test_brush_strokes_split_and_collapse_edges() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(SCULPT_BRUSH)
    for i in range(4):
        assert_true(
            sculptor.stroke_from_ray(
                scene,
                assets,
                _ray(-0.3125 + 0.1875 * Float32(i), 0.0625, 3, 0, 0, -1),
                Length(0.5, METER),
            )
        )
    sculptor.end_stroke()
    _expect(sculptor, Expected(503, 931, 201411848, -33.433307147439336, 19.579314920738398, 14.72036621398729, 321.3138109061283, 1477.6568668978489,
        0.25, 0.0625, 0.038546113930117976, 0.05117212661186143, -0.05115172662015244, 0.9973790223991061, 0.5,
        40, 0.005871576257050037, 0.0007951995357871056, 0.07590516656637192), EXACT)
    var kinds: List[SculptorEventKind] = [
        SCULPT_START, SCULPT_CHANGE, SCULPT_CHANGE, SCULPT_CHANGE, SCULPT_CHANGE, SCULPT_END
    ]
    assert_equal(len(sculptor.events), len(kinds))
    for i in range(len(kinds)):
        assert_true(sculptor.events[i] == kinds[i])
    # The geometry the mesh draws holds every vertex and triangle.
    ref drawn = assets.geometries.get(sculptor.geometry)
    assert_equal(drawn.vertex_count(), 503)
    assert_equal(drawn.triangle_count(), 931)
    var copy = sculptor.get_geometry(assets)
    assert_equal(copy.vertex_count(), 503)
    assert_equal(copy.triangle_count(), 931)
    assert_true(copy.has_attribute(String(NORMAL)))


def test_inflating_the_box_at_full_detail() raises:
    var assets = Assets()
    var scene = _scene(_box(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(SCULPT_INFLATE)
    sculptor.set_detail(1)
    for i in range(2):
        _ = sculptor.stroke_from_ray(
            scene,
            assets,
            _ray(2, 0.0625 * Float32(i) + 0.03125, 0.0625, -1, 0, 0),
            Length(0.3125, METER),
        )
    sculptor.end_stroke()
    _expect(sculptor, Expected(1734, 3464, 2711572684, 795.4236235348508, 41.86111636943497, 85.23213460964871, 704.608927861403, 1606.660135335489,
        0.5091141424629717, 0.09375, 0.0625, 0.9999320789124638, 0.011654936292470412, 0.00000467081524412731, 0.3125,
        40, -0.5, -0.25, -0.5), EXACT)


def test_clay_on_the_box_with_little_detail() raises:
    var assets = Assets()
    var scene = _scene(_box(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_detail(0.3)
    for i in range(3):
        _ = sculptor.stroke_from_ray(
            scene,
            assets,
            _ray(0.0625 + 0.1875 * Float32(i), 2, 0.1875, 0, -1, 0),
            Length(0.4375, METER),
        )
    sculptor.end_stroke()
    _expect(sculptor, Expected(363, 722, 116152158, -5.543298659846187, 61.49311605472758, 30.662749165770947, 156.42714341740768, 286.87491334792384,
        0.4375, 0.5157929886890615, 0.1875, 0.3533752895321125, 0.9353982452734145, 0.012491096329481198, 0.4375,
        40, -0.4821428656578064, -0.25, -0.5178571343421936), EXACT)


def test_a_moved_and_scaled_mesh_sculpts_in_its_own_space() raises:
    var assets = Assets()
    var node = Object3D()
    node.set_position(1, 2, 3)
    node.set_scale(2, 2, 2)
    var scene = _scene(_bumpy(), assets, node^)
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(SCULPT_INFLATE)
    sculptor.set_detail(0)
    assert_true(
        sculptor.stroke_from_ray(
            scene, assets, _ray(1.5, 2.5, 10, 0, 0, -1), Length(1.0, METER)
        )
    )
    _expect(sculptor, Expected(81, 128, 4637754, -0.009297145006712526, -0.002322021231520921, 2.18433107342571, 68.64288502130927, 234.5231217900291,
        0.25, 0.25, 0.01953125, -0.12397514547474874, -0.030993786368687184, 0.9918011637979899, 1.0,
        40, 0.0, 0.0, 0.005008385516703129), EXACT)


def _pick(ray: Ray) raises -> Sculptor:
    """Return a sculptor of the bumpy plane that has picked with a ray.

    Args:
        ray: The ray.

    Returns:
        The sculptor.

    Raises:
        Error: If the scene is refused.
    """
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    _ = sculptor.pick_from_ray(scene, ray, Length(0.5, METER))
    return sculptor^


def test_rays_along_the_octree_bounds_pick_as_three_js_does() raises:
    # A ray on a cell's bound, parallel to it, meets it at no number: as in
    # three.js, the cell counts as met.
    var s = _pick(_ray(-1, 0.4375, 3, 0, 0, -1))
    assert_equal(s._hit_face, 32)
    assert_almost_equal(Float64(s.get_hit_point().z), 0.0029296875, atol=EXACT)
    assert_almost_equal(Float64(s.get_hit_normal().x), 0.08097851792950184, atol=EXACT)
    s = _pick(_ray(0.4375, 1, 3, 0, 0, -1))
    assert_equal(s._hit_face, 10)
    assert_almost_equal(Float64(s.get_hit_normal().x), -0.3025962351102489, atol=EXACT)
    # From below, and from the side.
    s = _pick(_ray(0.4375, 0.4375, -3, 0, 0, 1))
    assert_equal(s._hit_face, 42)
    assert_almost_equal(Float64(s.get_hit_point().z), 0.0634765625, atol=EXACT)
    s = _pick(_ray(3, 0.4375, 0, -1, 0, 0))
    assert_equal(s._hit_face, 40)
    assert_almost_equal(Float64(s.get_hit_point().x), 0.08124999999999982, atol=EXACT)
    # Away from the plane.
    s = _pick(_ray(0.4375, 0.4375, 3, 0, 0, 1))
    assert_false(s.has_hit())
    assert_equal(Float64(s.get_world_radius().value), 0)


# --- the pointer, against three.js -----------------------------------------------


def _pointer_sculptor(
    mut scene: Scene, mut assets: Assets, tool: SculptTool, size: Float64
) raises -> Sculptor:
    """Return a sculptor of the bumpy plane at detail zero, connected to a
    view of 200 by 200 pixels.

    Args:
        scene: The scene of the bumpy plane.
        assets: Its assets.
        tool: The tool.
        size: The brush size, in pixels.

    Returns:
        The sculptor.

    Raises:
        Error: If the sculptor is refused.
    """
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(tool)
    sculptor.set_detail(0)
    sculptor.set_size(size)
    sculptor.connect(0, 0, 200, 200)
    return sculptor^


def test_a_pointer_picks_the_center_of_the_view() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.connect(0, 0, 200, 200)
    assert_true(sculptor.pick_from_pointer(_camera(), scene, 100, 100))
    _expect(sculptor, Expected(81, 128, 4637754, 0.0, 0.0, 2.109375, 68.64532470703125, 234.51774644851685,
        0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.6994614872324967,
        40, 0.0, 0.0, 0.0), POINTER)
    # Off the plane.
    assert_false(sculptor.pick_from_pointer(_camera(), scene, 2, 2))
    assert_false(sculptor.has_hit())
    # At no place.
    assert_false(sculptor.pick_from_pointer(_camera(), scene, nan[DType.float64](), 2))
    assert_false(sculptor.pick_from_pointer(_camera(), scene, 2, inf[DType.float64]()))


def test_clay_follows_the_pointer() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = _pointer_sculptor(scene, assets, SCULPT_CLAY, 30)
    var camera = _camera()
    sculptor.pointer_down(camera, scene, 100, 100)
    assert_true(sculptor.is_sculpting())
    sculptor.pointer_move(camera, scene, assets, 130, 110)
    # Nearer than a stamp's spacing: no stamp, but the hit follows.
    sculptor.pointer_move(camera, scene, assets, 131, 110)
    sculptor.pointer_move(camera, scene, assets, 160, 120)
    sculptor.pointer_up()
    assert_false(sculptor.is_sculpting())
    _expect(sculptor, Expected(81, 128, 4637754, -0.015784392453497276, -0.0995356906496454, 2.853569668950513, 68.73913449677241, 234.17367110820487,
        0.8157213112502919, -0.27190710375009786, 0.08446667136111063, 0.021948641829257664, -0.30591136785892914, 0.9518069615928063, 0.4078606556251354,
        40, -0.0009539069142192602, -0.0014701014151796699, 0.05386316776275635), POINTER)
    var kinds: List[SculptorEventKind] = [SCULPT_START, SCULPT_CHANGE, SCULPT_CHANGE, SCULPT_END]
    assert_equal(len(sculptor.events), len(kinds))
    for i in range(len(kinds)):
        assert_true(sculptor.events[i] == kinds[i])


def test_drag_pulls_the_surface_with_the_pointer() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = _pointer_sculptor(scene, assets, SCULPT_DRAG, 40)
    var camera = _camera()
    sculptor.pointer_down(camera, scene, 100, 100)
    sculptor.pointer_move(camera, scene, assets, 120, 100)
    sculptor.pointer_move(camera, scene, assets, 120, 130)
    # A move to the same place drags nothing.
    sculptor.pointer_move(camera, scene, assets, 120, 130)
    sculptor.pointer_up()
    _expect(sculptor, Expected(81, 128, 4637754, 1.76158264852711, -2.63350279442966, 2.442490484449081, 71.25915341207983, 231.0678600310348,
        0.27498735066832375, -0.4124810260024851, 0.0514386171960437, -0.04498250057535058, 0.02015689047077963, 0.998784398360596, 0.5499747013366294,
        40, 0.2703089118003845, -0.4071822166442871, 0.050693221390247345), POINTER)


def test_scale_grows_the_surface_as_the_pointer_moves_right() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = _pointer_sculptor(scene, assets, SCULPT_SCALE, 50)
    var camera = _camera()
    sculptor.pointer_down(camera, scene, 110, 95)
    sculptor.pointer_move(camera, scene, assets, 130, 95)
    sculptor.pointer_move(camera, scene, assets, 125, 95)
    # Straight down scales nothing.
    sculptor.pointer_move(camera, scene, assets, 125, 99)
    sculptor.pointer_up()
    _expect(sculptor, Expected(81, 128, 4637754, -0.002380272907771541, 0.0003742168191820383, 2.110544049879536, 69.04491947312535, 234.4618478808261,
        0.1395364627214163, 0.06976823136070814, 0.007630900305077404, -0.05678799103661917, -0.03326049043154923, 0.9978320819908917, 0.6976823136070583,
        40, -0.019051481038331985, -0.009525740519165993, -0.001041877781972289), POINTER)


def test_pointer_events_that_do_not_sculpt() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = _pointer_sculptor(scene, assets, SCULPT_BRUSH, 30)
    var camera = _camera()
    # A press off the mesh starts nothing.
    sculptor.pointer_down(camera, scene, 2, 2)
    assert_false(sculptor.is_sculpting())
    # Nor does a secondary button, a secondary pointer, or a disabled
    # sculptor.
    sculptor.pointer_down(camera, scene, 100, 100, button=SECONDARY)
    sculptor.pointer_down(camera, scene, 100, 100, is_primary=False)
    sculptor.enabled = False
    sculptor.pointer_down(camera, scene, 100, 100)
    assert_false(sculptor.is_sculpting())
    sculptor.pointer_move(camera, scene, assets, 150, 100)
    sculptor.enabled = True
    # A move with no stroke on does nothing, nor during a ray stroke.
    sculptor.pointer_move(camera, scene, assets, 150, 100)
    assert_true(
        sculptor.stroke_from_ray(scene, assets, _down(), Length(0.5, METER))
    )
    sculptor.pointer_move(camera, scene, assets, 150, 100)
    sculptor.pointer_up()
    assert_true(sculptor.is_sculpting())
    sculptor.end_stroke()
    with assert_raises(contains="Invalid pointer button"):
        sculptor.pointer_down(camera, scene, 100, 100, button=PointerButton(7))
    sculptor.pointer_down(camera, scene, 100, 100, pointer_id=4)
    assert_true(sculptor.is_sculpting())
    # A second press, another pointer's move and lift, and a ray stroke
    # are all ignored while the stroke is on.
    sculptor.pointer_down(camera, scene, 120, 100, pointer_id=4)
    sculptor.pointer_move(camera, scene, assets, 150, 100, pointer_id=5)
    sculptor.pointer_up(pointer_id=5)
    assert_true(sculptor.is_sculpting())
    assert_false(
        sculptor.stroke_from_ray(scene, assets, _down(), Length(0.5, METER))
    )
    # A move off the mesh stamps until it leaves it.
    sculptor.pointer_move(camera, scene, assets, 199, 100, pointer_id=4)
    # A move to no place stamps nothing and loses the hit.
    sculptor.pointer_move(camera, scene, assets, nan[DType.float64](), 100, pointer_id=4)
    assert_false(sculptor.has_hit())
    sculptor.pointer_up(pointer_id=4)
    assert_false(sculptor.is_sculpting())
    assert_true(sculptor.events[len(sculptor.events) - 1] == SCULPT_END)


def test_drag_off_the_view_and_to_no_place() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = _pointer_sculptor(scene, assets, SCULPT_DRAG, 40)
    var camera = _camera()
    sculptor.pointer_down(camera, scene, 100, 100)
    var before = sculptor.sculpt_mesh().vertices[40 * 3]
    sculptor.pointer_move(camera, scene, assets, nan[DType.float64](), 100)
    assert_equal(sculptor.sculpt_mesh().vertices[40 * 3], before)
    sculptor.pointer_up()
    # A view with no width gives a pointer no ray.
    sculptor.connect(0, 0, 0, 200)
    assert_false(sculptor.pick_from_pointer(camera, scene, 100, 100))
    sculptor.connect(0, 0, 200, inf[DType.float64]())
    assert_false(sculptor.pick_from_pointer(camera, scene, 100, 100))
    sculptor.connect(0, 0, inf[DType.float64](), 200)
    assert_false(sculptor.pick_from_pointer(camera, scene, 100, 100))
    sculptor.connect(0, 0, 200, 0)
    assert_false(sculptor.pick_from_pointer(camera, scene, 100, 100))


def test_a_pointer_needs_a_view() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    with assert_raises(contains="connect()"):
        _ = sculptor.pick_from_pointer(_camera(), scene, 100, 100)
    sculptor.connect(0, 0, 200, 200)
    assert_true(sculptor.is_connected())
    sculptor.pointer_down(_camera(), scene, 100, 100)
    # Connecting again ends the stroke first.
    sculptor.connect(0, 0, 100, 100)
    assert_false(sculptor.is_sculpting())
    sculptor.dispose()
    assert_false(sculptor.is_connected())
    assert_false(sculptor.has_hit())
    # Disconnecting twice is harmless.
    sculptor.disconnect()
    assert_false(sculptor.is_connected())


# --- settings and refusals ---------------------------------------------------------


def test_each_tool_keeps_its_own_settings() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    assert_true(sculptor.get_tool() == SCULPT_CLAY)
    assert_equal(sculptor.get_size(), 50)
    assert_equal(sculptor.get_strength(), 0.5)
    assert_false(sculptor.get_negative())
    assert_equal(sculptor.get_detail(), 0.75)
    sculptor.set_tool(SCULPT_CREASE)
    assert_equal(sculptor.get_size(), 25)
    assert_equal(sculptor.get_strength(), 0.75)
    assert_true(sculptor.get_negative())
    sculptor.set_size(80)
    sculptor.set_strength(0.25)
    sculptor.set_negative(False)
    sculptor.set_tool(SCULPT_CREASE)
    sculptor.set_tool(SCULPT_DRAG)
    assert_equal(sculptor.get_size(), 150)
    sculptor.set_tool(SCULPT_CREASE)
    assert_equal(sculptor.get_size(), 80)
    assert_equal(sculptor.get_strength(), 0.25)
    assert_false(sculptor.get_negative())
    with assert_raises(contains="Unknown tool"):
        sculptor.set_tool(SculptTool(9))
    with assert_raises(contains="Unknown tool"):
        sculptor.set_tool(SculptTool(-1))
    with assert_raises(contains="size"):
        sculptor.set_size(4)
    with assert_raises(contains="size"):
        sculptor.set_size(501)
    with assert_raises(contains="size"):
        sculptor.set_size(nan[DType.float64]())
    with assert_raises(contains="strength"):
        sculptor.set_strength(-0.5)
    with assert_raises(contains="strength"):
        sculptor.set_strength(1.5)
    with assert_raises(contains="detail"):
        sculptor.set_detail(inf[DType.float64]())
    assert_true(SCULPT_SCALE.is_valid())
    assert_true(SCULPT_START.is_valid())
    assert_true(SCULPT_END.is_valid())
    assert_false(SculptorEventKind(3).is_valid())
    assert_false(SculptorEventKind(-1).is_valid())


def test_zero_strength_moves_nothing_at_zero_detail() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(SCULPT_BRUSH)
    sculptor.set_strength(0)
    sculptor.set_detail(0)
    assert_true(
        sculptor.stroke_from_ray(scene, assets, _down(), Length(0.5, METER))
    )
    # The stroke began, but no geometry changed.
    assert_equal(len(sculptor.events), 1)
    # At a detail above zero, the topology still changes.
    sculptor.set_detail(0.75)
    _ = sculptor.stroke_from_ray(scene, assets, _down(), Length(0.5, METER))
    assert_true(sculptor.sculpt_mesh().nb_faces > 128)
    assert_true(sculptor.events[1] == SCULPT_CHANGE)


def test_a_brush_that_reaches_no_vertex_moves_nothing() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(SCULPT_PINCH)
    sculptor.set_detail(0)
    # A tiny brush in the middle of a face holds no vertex.
    assert_true(
        sculptor.stroke_from_ray(scene, assets, _down(), Length(0.01, METER))
    )
    assert_equal(len(sculptor.events), 1)
    # With detail, the hit face's vertices are the start of the remesh.
    sculptor.set_detail(1)
    assert_true(
        sculptor.stroke_from_ray(scene, assets, _down(), Length(0.01, METER))
    )


def test_clay_facing_away_moves_nothing() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_detail(0)
    # From below, every normal faces along the ray, so no vertex is in
    # front and the plane has no normal.
    assert_true(
        sculptor.stroke_from_ray(
            scene, assets, _ray(0.1875, 0.0625, -3, 0, 0, 1), Length(0.5, METER)
        )
    )
    assert_equal(len(sculptor.events), 1)


def test_ray_strokes_refuse_what_three_js_refuses() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    with assert_raises(contains="worldRadius"):
        _ = sculptor.pick_from_ray(scene, _down(), Length(0.0, METER))
    with assert_raises(contains="worldRadius"):
        _ = sculptor.pick_from_ray(scene, _down(), Length(nan[DType.float32](), METER))
    var bad = _down()
    bad.origin.x = nan[DType.float32]()
    with assert_raises(contains="finite"):
        _ = sculptor.pick_from_ray(scene, bad, Length(0.5, METER))
    bad = _down()
    bad.origin.y = inf[DType.float32]()
    with assert_raises(contains="finite"):
        _ = sculptor.pick_from_ray(scene, bad, Length(0.5, METER))
    bad = _down()
    bad.origin.z = inf[DType.float32]()
    with assert_raises(contains="finite"):
        _ = sculptor.pick_from_ray(scene, bad, Length(0.5, METER))
    bad = _down()
    bad.direction.z = inf[DType.float32]()
    with assert_raises(contains="finite"):
        _ = sculptor.pick_from_ray(scene, bad, Length(0.5, METER))
    bad = _down()
    bad.direction.z = 0
    with assert_raises(contains="non-zero"):
        _ = sculptor.pick_from_ray(scene, bad, Length(0.5, METER))
    sculptor.set_tool(SCULPT_DRAG)
    with assert_raises(contains="pointer"):
        _ = sculptor.stroke_from_ray(scene, assets, _down(), Length(0.5, METER))
    sculptor.set_tool(SCULPT_SCALE)
    with assert_raises(contains="pointer"):
        _ = sculptor.stroke_from_ray(scene, assets, _down(), Length(0.5, METER))
    # A miss is no stroke.
    sculptor.set_tool(SCULPT_BRUSH)
    assert_false(
        sculptor.stroke_from_ray(
            scene, assets, _ray(5, 5, 3, 0, 0, -1), Length(0.5, METER)
        )
    )
    assert_false(sculptor.is_sculpting())
    # Nothing to end.
    sculptor.end_stroke()
    assert_equal(len(sculptor.events), 0)
    # The sculpted geometry must be in the assets the stroke writes.
    var other = Assets()
    with assert_raises(contains="not in the assets"):
        _ = sculptor.stroke_from_ray(scene, other, _down(), Length(0.5, METER))


def test_a_radius_too_large_for_the_scale_is_refused() raises:
    var assets = Assets()
    var node = Object3D()
    node.set_scale(1e-6, 1e-6, 1e-6)
    var scene = _scene(_bumpy(), assets, node^)
    var sculptor = Sculptor(scene, assets, 0)
    with assert_raises(contains="too large"):
        _ = sculptor.pick_from_ray(scene, _down(), Length(3e38, METER))


def _matrix_node(x: Vector3, y: Vector3, z: Vector3) -> Object3D:
    """Return a node whose matrix has these three axes.

    Args:
        x: The first column.
        y: The second.
        z: The third.

    Returns:
        The node.
    """
    var node = Object3D()
    node.matrix_auto_update = False
    var axes = [x, y, z]
    for column in range(3):
        node.matrix.elements[column * 4] = axes[column].x
        node.matrix.elements[column * 4 + 1] = axes[column].y
        node.matrix.elements[column * 4 + 2] = axes[column].z
    return node^


def _refuses_the_matrix(var node: Object3D) raises:
    """Assert a sculptor refuses to stroke a mesh on this node.

    Args:
        node: The mesh's node.

    Raises:
        Error: If the stroke is not refused.
    """
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, node^)
    var sculptor = Sculptor(scene, assets, 0)
    with assert_raises(contains="uniform world scale"):
        _ = sculptor.stroke_from_ray(scene, assets, _down(), Length(0.5, METER))


def test_a_mesh_must_scale_uniformly_without_shear() raises:
    var flat = Object3D()
    flat.set_scale(0, 0, 0)
    _refuses_the_matrix(flat^)
    var stretched = Object3D()
    stretched.set_scale(1, 2, 1)
    _refuses_the_matrix(stretched^)
    # Axes of one length that lean on each other: x on y, then x on z,
    # then y on z.
    _refuses_the_matrix(
        _matrix_node(Vector3(1, 1, 0), Vector3(1, 0, 1), Vector3(0, 1, 1))
    )
    _refuses_the_matrix(
        _matrix_node(Vector3(1, 1, 0), Vector3(1, -1, 0), Vector3(1, 0, 1))
    )
    _refuses_the_matrix(
        _matrix_node(Vector3(1, 1, 0), Vector3(1, -1, 0), Vector3(1, -1, 0))
    )


def test_a_sculptor_needs_one_mesh_of_one_material() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    with assert_raises(contains="must be a Mesh"):
        _ = Sculptor(scene, assets, 1)
    with assert_raises(contains="must be a Mesh"):
        _ = Sculptor(scene, assets, -1)
    var material = scene.meshes[0].material
    scene.meshes[0].materials = [material, material]
    with assert_raises(contains="Multi-material"):
        _ = Sculptor(scene, assets, 0)


# --- the topology helpers, one case at a time ----------------------------------


def test_a_face_is_filled_across_the_split_edge_with_fewest_neighbors() raises:
    # Only the first edge split.
    assert_equal(_fill_split(9, -1, -1, 6, 6, 6), 1)
    # All three: the far corner with the fewest neighbors decides.
    assert_equal(_fill_split(9, 9, 9, 4, 5, 6), 2)
    assert_equal(_fill_split(9, 9, 9, 5, 4, 6), 3)
    assert_equal(_fill_split(9, 9, 9, 6, 6, 4), 1)
    assert_equal(_fill_split(9, 9, 9, 5, 6, 4), 1)
    # The first two.
    assert_equal(_fill_split(9, 9, -1, 4, 6, 5), 2)
    assert_equal(_fill_split(9, 9, -1, 6, 4, 5), 1)
    # The first and the third.
    assert_equal(_fill_split(9, -1, 9, 6, 4, 5), 3)
    assert_equal(_fill_split(9, -1, 9, 6, 5, 4), 1)
    # The second, alone or with the third.
    assert_equal(_fill_split(-1, 9, -1, 6, 6, 6), 2)
    assert_equal(_fill_split(-1, 9, 9, 6, 5, 6), 3)
    assert_equal(_fill_split(-1, 9, 9, 5, 6, 6), 2)
    # The third alone, and none.
    assert_equal(_fill_split(-1, -1, 9, 6, 6, 6), 3)
    assert_equal(_fill_split(-1, -1, -1, 6, 6, 6), 0)


def test_a_zero_normal_becomes_x() raises:
    var n = _unit_or_x(Point3(0, 0, 0))
    assert_equal(n.x, 1)
    assert_equal(n.y, 0)
    n = _unit_or_x(Point3(0, 3, 4))
    assert_equal(n.y, 0.6)


def test_a_split_edge_splits_the_face_across_it() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_bumpy())
    var sub = _SubData(Point3(0, 0, 0), 100, 0)
    sub.edge_key_stride = 200
    mesh.re_allocate_arrays(4)
    # Face 1 is (9, 10, 1). Split its edge 10-1 at a new vertex 81.
    _half_edge_split(mesh, sub, 1, 10, 1, 9)
    assert_equal(mesh.nb_vertices, 82)
    assert_equal(mesh.nb_faces, 129)
    assert_equal(mesh.faces[3], 10)
    assert_equal(mesh.faces[4], 81)
    assert_equal(mesh.faces[5], 9)
    assert_equal(mesh.faces[128 * 3], 81)
    assert_equal(mesh.faces[128 * 3 + 1], 1)
    assert_equal(mesh.faces[128 * 3 + 2], 9)
    # Face 2, (1, 10, 2), has that edge first; it is split across it.
    var next = _sub_fill_triangles(mesh, sub, [2])
    assert_equal(len(next), 2)
    assert_equal(next[0], 2)
    assert_equal(next[1], 129)
    assert_equal(mesh.faces[6], 1)
    assert_equal(mesh.faces[7], 81)
    assert_equal(mesh.faces[8], 2)
    assert_equal(mesh.faces[129 * 3], 81)
    assert_equal(mesh.faces[129 * 3 + 1], 10)
    assert_equal(mesh.faces[129 * 3 + 2], 2)
    assert_equal(len(mesh.vert_ring_vert[81]), 4)
    assert_equal(len(mesh.vert_ring_face[81]), 4)


def test_an_edge_split_twice_shares_its_middle() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_bumpy())
    var sub = _SubData(Point3(0, 0, 0), 100, 0)
    sub.edge_key_stride = 200
    mesh.re_allocate_arrays(4)
    _half_edge_split(mesh, sub, 1, 10, 1, 9)
    # Face 2 splits the same edge from its side: no new vertex.
    _half_edge_split(mesh, sub, 2, 1, 10, 2)
    assert_equal(mesh.nb_vertices, 82)
    assert_equal(mesh.nb_faces, 130)
    assert_equal(mesh.faces[7], 81)
    assert_equal(len(mesh.vert_ring_face[81]), 4)


def _quad(var index: List[Int]) raises -> SculptorMesh:
    """Return a mesh of two triangles over the four corners of a square.

    Args:
        index: The two triangles' corners.

    Returns:
        The mesh.

    Raises:
        Error: If the mesh is refused.
    """
    var mesh = SculptorMesh()
    mesh.init_from_geometry(
        _triangles([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0.5], index^)
    )
    return mesh^


def test_each_way_two_faces_can_share_an_edge() raises:
    # Every pairing of the shared corners. Each collapse stops at the open
    # edge, so the faces stay as they are.
    var pairs: List[List[Int]] = [
        [0, 1, 2, 0, 3, 1],
        [0, 1, 2, 0, 2, 3],
        [0, 1, 2, 1, 0, 3],
        [0, 1, 2, 2, 0, 3],
        [0, 1, 2, 3, 1, 0],
        [0, 1, 2, 2, 3, 0],
        [0, 1, 2, 1, 2, 3],
        [0, 1, 2, 3, 1, 2],
        [0, 1, 2, 2, 3, 1],
    ]
    for pair in pairs:
        var mesh = _quad(pair.copy())
        var dec = _DecData()
        var tris = List[Int]()
        _dec_decimate_triangles(mesh, dec, 0, 1, tris)
        assert_equal(len(dec.verts_decimated), 0)
        assert_equal(mesh.topology_version, 0)
    # An edge of one face has no second face to collapse with.
    var mesh = _quad([0, 1, 2, 0, 2, 3])
    var dec = _DecData()
    var tris = List[Int]()
    assert_equal(_dec_find_opposite_triangle(mesh, 0, 0, 1), -1)
    _dec_decimate_triangles(mesh, dec, 0, -1, tris)
    assert_equal(len(tris), 0)


def test_no_collapse_touches_an_open_edge() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_bumpy())
    var tris = List[Int]()
    var dec = _DecData()
    # Faces 30 and 15 share 16-17: 16 is inside, 17 on the right edge.
    _dec_decimate_triangles(mesh, dec, 30, 15, tris)
    # Faces 3 and 18 share 10-11, both inside; the far corner of face 3
    # is on the top edge.
    _dec_decimate_triangles(mesh, dec, 3, 18, tris)
    _dec_decimate_triangles(mesh, dec, 18, 3, tris)
    assert_equal(len(dec.verts_decimated), 0)
    assert_equal(mesh.topology_version, 0)


def _bipyramid() raises -> SculptorMesh:
    """Return two triangular pyramids base to base: 0, 1 and 3 on the
    base, 2 above and 4 below.

    Returns:
        The mesh.

    Raises:
        Error: If the mesh is refused.
    """
    var mesh = SculptorMesh()
    mesh.init_from_geometry(
        _triangles(
            [0, 0, 0, 1, 0, 0, 0.5, 0.5, 1, 0.5, 1, 0, 0.5, 0.5, -1],
            [0, 1, 2, 2, 3, 0, 0, 3, 4, 0, 4, 1, 1, 3, 2, 1, 4, 3],
        )
    )
    return mesh^


def test_an_edge_whose_ends_share_three_neighbors_flips() raises:
    var mesh = _bipyramid()
    var dec = _DecData()
    var tris = List[Int]()
    # Faces 0 and 3 share the base edge 0-1, whose ends share 2, 3 and 4.
    _dec_decimate_triangles(mesh, dec, 0, 3, tris)
    assert_equal(mesh.topology_version, 1)
    assert_equal(mesh.faces[0], 0)
    assert_equal(mesh.faces[1], 4)
    assert_equal(mesh.faces[2], 2)
    assert_equal(mesh.faces[9], 2)
    assert_equal(mesh.faces[10], 4)
    assert_equal(mesh.faces[11], 1)
    assert_equal(len(dec.verts_to_delete), 0)


def test_an_edge_from_the_apex_collapses() raises:
    var mesh = _bipyramid()
    var dec = _DecData()
    var tris = List[Int]()
    # Faces 1 and 0 share 2-0: the apex, of three neighbors, and a base
    # corner of four. The base corner joins the apex.
    _dec_decimate_triangles(mesh, dec, 1, 0, tris)
    assert_equal(len(dec.verts_to_delete), 1)
    assert_equal(dec.verts_to_delete[0], 0)
    assert_equal(len(dec.tris_to_delete), 2)
    assert_true(len(tris) > 0)


def test_a_tetrahedron_does_not_collapse() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(
        _triangles(
            [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1],
            [0, 2, 1, 0, 1, 3, 1, 2, 3, 0, 3, 2],
        )
    )
    var dec = _DecData()
    var tris = List[Int]()
    _dec_decimate_triangles(mesh, dec, 0, 1, tris)
    assert_equal(len(dec.verts_decimated), 0)


def test_a_flip_onto_an_existing_edge_is_skipped() raises:
    # The seven-vertex torus: every two vertices are neighbors, so a flip
    # would make an edge that is there already.
    var positions = List[Float32]()
    var index = List[Int]()
    for i in range(7):
        positions.append(Float32(i))
        positions.append(Float32(i * i % 5))
        positions.append(Float32(i * i * i % 7))
    for i in range(7):
        index.append(i)
        index.append((i + 1) % 7)
        index.append((i + 3) % 7)
        index.append(i)
        index.append((i + 3) % 7)
        index.append((i + 2) % 7)
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_triangles(positions^, index^))
    var dec = _DecData()
    var tris = List[Int]()
    # Faces 0, (0, 1, 3), and 1, (0, 3, 2), share 0-3.
    _dec_decimate_triangles(mesh, dec, 0, 1, tris)
    assert_equal(len(dec.verts_decimated), 0)
    assert_equal(mesh.topology_version, 0)


def test_a_hit_on_a_vertex_takes_its_normal() raises:
    # The hit vertex is the face's first, second and third corner.
    var s = _pick(_ray(-1, 0.25, 3, 0, 0, -1))
    assert_equal(s._hit_face, 48)
    assert_almost_equal(
        Float64(s.get_hit_normal().x), 0.12977148365512958, atol=EXACT
    )
    assert_almost_equal(
        Float64(s.get_hit_normal().z), 0.9583124595333423, atol=EXACT
    )
    s = _pick(_ray(-1, -1, 3, 0, 0, -1))
    assert_equal(s._hit_face, 112)
    assert_almost_equal(
        Float64(s.get_hit_normal().x), 0.3988215548120161, atol=EXACT
    )
    s = _pick(_ray(-0.75, 0.25, 3, 0, 0, -1))
    assert_equal(s._hit_face, 48)
    assert_almost_equal(
        Float64(s.get_hit_normal().y), 0.21212121212121213, atol=EXACT
    )


def test_a_view_too_narrow_gives_no_ray() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.connect(0, 0, 1e-300, 200)
    assert_false(sculptor.pick_from_pointer(_camera(), scene, 100, 100))
    # A drag whose view narrows mid-stroke stops.
    sculptor.connect(0, 0, 200, 200)
    sculptor.set_tool(SCULPT_DRAG)
    sculptor.pointer_down(_camera(), scene, 100, 100)
    sculptor._rect[2] = 1e-300
    var before = sculptor.sculpt_mesh().vertices[40 * 3]
    sculptor.pointer_move(_camera(), scene, assets, 120, 100)
    assert_equal(sculptor.sculpt_mesh().vertices[40 * 3], before)


def test_positions_in_one_place_do_not_weld_to_a_triangle() raises:
    var mesh = SculptorMesh()
    with assert_raises(contains="degenerate"):
        mesh.init_from_geometry(_triangles([1, 1, 1, 1, 1, 1, 1, 1, 1], []))
    with assert_raises(contains="degenerate"):
        mesh.init_from_geometry(_triangles([1, 1, 1, 2, 1, 1, 2, 1, 1], []))
    with assert_raises(contains="degenerate"):
        mesh.init_from_geometry(_triangles([1, 1, 1, 2, 1, 1, 1, 1, 1], []))
    with assert_raises(contains="position attribute"):
        mesh.init_from_geometry(_triangles(List[Float32](), []))
    with assert_raises(contains="finite"):
        mesh.init_from_geometry(
            _triangles([0, 0, 0, 1, 0, 0, nan[DType.float32](), 1, 0], [])
        )
    with assert_raises(contains="finite"):
        mesh.init_from_geometry(
            _triangles([0, 0, 0, 1, 0, 0, 0, 1, inf[DType.float32]()], [])
        )
    with assert_raises(contains="fit in Float32"):
        mesh.init_from_geometry(
            _triangles([0, 0, 0, 0, 1e30, 0, 0, 0, 1e30], [])
        )
    with assert_raises(contains="fit in Float32"):
        mesh.init_from_geometry(
            _triangles([0, 0, 0, 0, 0, 1e30, 1e30, 0, 0], [])
        )


def test_a_position_welds_to_the_nearest_within_the_tolerance() raises:
    # The widest extent is 4, so positions weld within 4e-7. Along x from
    # 1, the second position is 4 steps of a `Float32` on, too far to weld;
    # the third is 2 steps on, as near the first as the second, and welds
    # to the second, found first.
    var mesh = SculptorMesh()
    mesh.init_from_geometry(
        _triangles(
            [
                0, 0, 0, 1, 0, 0, 0, 1, 0,
                1.000000476837158203125, 0, 0, 4, 0, 0, 3, 1, 0,
                1.0000002384185791015625, 0, 0, 2, 2, 0, 1, 3, 0,
            ],
            [],
        )
    )
    assert_equal(mesh.nb_vertices, 8)
    assert_equal(mesh.faces[3], 3)
    assert_equal(mesh.faces[6], 3)


def test_the_dirty_vertices_are_sorted_once_and_in_range() raises:
    var vertices: List[Int] = [5, 1, 1, 9, 3]
    assert_true(_compact_dirty_vertices(vertices, 6))
    assert_equal(len(vertices), 3)
    assert_equal(vertices[0], 1)
    assert_equal(vertices[2], 5)
    var none = List[Int]()
    assert_false(_compact_dirty_vertices(none, 6))


def test_empty_lists_change_nothing() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_bumpy())
    assert_equal(len(mesh.expands_faces([], 1)), 0)
    assert_equal(len(mesh.expands_vertices([], 1)), 0)
    mesh.update_topology([], [])
    mesh.update_geometry([], [])
    assert_equal(len(laplacian_smooth(mesh, [])), 0)
    smooth_tangent_verts(mesh, [], 1.0)
    var empty = List[Int]()
    replace_element(empty, 1, 2)
    remove_element(empty, 1)
    assert_equal(len(empty), 0)
    assert_equal(mesh.topology_version, 0)
    # A sphere query that queues nothing.
    _ = mesh.intersect_sphere(Point3(0, 0, 0), 0.25, False)
    assert_equal(len(mesh.leaves_to_update), 0)
    # With every leaf pruned, the root is an empty leaf.
    for child in mesh.cells[mesh.octree].children:
        mesh.cells[child].faces = List[Int]()
    mesh._prune_if_possible(mesh.cells[mesh.octree].children[0])
    assert_equal(
        len(mesh.intersect_ray(Point3(0, 0, 3), Point3(0, 0, -1))), 0
    )


def test_a_vertex_with_one_edge_neighbor_smooths_to_all() raises:
    # Two tetrahedra, and a triangle between them given twice. Vertex 0
    # is on an open edge, but of its neighbors only vertex 1 is, so it
    # smooths toward all four.
    var mesh = SculptorMesh()
    mesh.init_from_geometry(
        _triangles(
            [
                0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1,
                2, 2, 2, 3, 2, 2, 2, 3, 2, 2, 2, 3,
            ],
            [
                0, 2, 1, 0, 1, 3, 1, 2, 3, 0, 3, 2,
                4, 6, 5, 4, 5, 7, 5, 6, 7, 4, 7, 6,
                0, 1, 4, 0, 1, 4,
            ],
        )
    )
    assert_equal(mesh.vert_on_edge[0], 1)
    assert_equal(mesh.vert_on_edge[1], 1)
    assert_equal(mesh.vert_on_edge[4], 0)
    var smooth = laplacian_smooth(mesh, [0])
    assert_equal(smooth[0], 0.75)
    assert_equal(smooth[1], 0.75)
    assert_equal(smooth[2], 0.75)


def test_tools_leave_a_vertex_outside_the_brush() raises:
    var mesh = SculptorMesh()
    mesh.init_from_geometry(_bumpy())
    var before = mesh.vertices[0]
    var far = Point3(1, -1, 0)
    var up = Point3(0, 0, 1)
    tool_flatten(mesh, [0], up, Point3(0, 0, 1), far, 0.25, 1, False)
    tool_crease(mesh, [0], up, far, 0.25, 1, False)
    assert_equal(mesh.vertices[0], before)


def test_a_brush_whose_edges_fit_changes_no_topology() raises:
    var assets = Assets()
    var scene = _scene(_bumpy(), assets, Object3D())
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(SCULPT_BRUSH)
    sculptor.set_detail(0.01)
    assert_true(
        sculptor.stroke_from_ray(scene, assets, _down(), Length(1.0, METER))
    )
    assert_equal(sculptor.sculpt_mesh().nb_faces, 128)
    assert_equal(sculptor.sculpt_mesh().topology_version, 0)
    # A geometry id no store hands out is refused.
    sculptor.geometry = GeometryId(-1)
    with assert_raises(contains="not in the assets"):
        _ = sculptor.stroke_from_ray(scene, assets, _down(), Length(1.0, METER))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
