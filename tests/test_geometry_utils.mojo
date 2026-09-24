# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.utils`, and for the geometry methods beside it:
`to_non_indexed`, `center`, `compute_tangents`, groups and `clone`."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    GeometryGroup,
    MaterialIndex,
    NORMAL,
    POSITION,
    TANGENT,
    UV,
)
from geometries.box import cube
from geometries.plane import plane
from geometries.sphere import sphere
from geometries.utils import (
    DEFAULT_CREASE,
    DEFAULT_TOLERANCE,
    EPSILON,
    KEY_LIMIT,
    merge_geometries,
    merge_vertices,
    to_creased_normals,
    truncated,
)
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime NEAR = 1e-5


def points(var numbers: List[Float32]) raises -> BufferGeometry:
    """Return a geometry holding `numbers` as positions and nothing else.

    Args:
        numbers: Three per point.

    Returns:
        The geometry.

    Raises:
        Error: If the numbers do not divide into points.
    """
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    return geometry^


def quad() raises -> BufferGeometry:
    """Return a unit square facing +z as two indexed triangles, with
    normals and texture coordinates running as three.js's plane's do.

    Returns:
        Four vertices and six index entries.

    Raises:
        Error: Never, for these numbers.
    """
    var geometry = points([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0])
    geometry.set_attribute(
        String(NORMAL),
        BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], 3),
    )
    geometry.set_attribute(
        String(UV), BufferAttribute([0, 0, 1, 0, 1, 1, 0, 1], 2)
    )
    geometry.set_index([0, 1, 2, 0, 2, 3])
    return geometry^


# --- groups, clone and the stream ------------------------------------------


def test_a_material_index_is_valid_from_zero() raises:
    """A material index is a position in a list."""
    assert_true(MaterialIndex(0).is_valid())
    assert_true(MaterialIndex(3).is_valid())
    assert_false(MaterialIndex(-1).is_valid())


def test_groups_are_added_and_cleared() raises:
    """A group keeps its run and its material; clearing removes them all."""
    var geometry = quad()
    geometry.add_group(0, 3)
    geometry.add_group(3, 3, MaterialIndex(1))
    assert_equal(len(geometry.groups), 2)
    assert_equal(geometry.groups[1].start, 3)
    assert_equal(geometry.groups[1].count, 3)
    assert_true(geometry.groups[1].material_index == MaterialIndex(1))
    assert_true(geometry.groups[0].material_index == MaterialIndex(0))
    geometry.clear_groups()
    assert_equal(len(geometry.groups), 0)


def test_a_group_that_cannot_be_read_is_refused() raises:
    """A negative start, count or material index is refused."""
    var geometry = quad()
    with assert_raises(contains="negative distance"):
        geometry.add_group(-1, 3)
    with assert_raises(contains="negative distance"):
        geometry.add_group(0, -3)
    with assert_raises(contains="material index"):
        geometry.add_group(0, 3, MaterialIndex(-1))
    assert_equal(len(geometry.groups), 0)


def test_a_clone_shares_nothing() raises:
    """A clone holds everything, and changing it leaves the source alone."""
    var geometry = quad()
    geometry.add_morph_target(
        BufferAttribute(List[Float32](length=12, fill=1.0), 3)
    )
    geometry.morph_relative = True
    geometry.add_group(0, 6, MaterialIndex(2))
    var copied = geometry.clone()
    assert_equal(copied.attribute_count(), 3)
    assert_equal(len(copied.index), 6)
    assert_equal(copied.morph_count(), 1)
    assert_true(copied.morph_relative)
    assert_equal(len(copied.groups), 1)
    copied.center()
    copied.index[0] = 3
    assert_equal(geometry.index[0], 0)
    assert_equal(geometry.attribute_view(String(POSITION)).data[0], 0)


def test_the_stream_is_the_index_or_the_vertices() raises:
    """A slot reads through the index when there is one."""
    var geometry = quad()
    assert_equal(geometry.stream_length(), 6)
    assert_equal(geometry.vertex_at(5), 3)
    var loose = points([0, 0, 0, 1, 0, 0, 0, 1, 0])
    assert_equal(loose.stream_length(), 3)
    assert_equal(loose.vertex_at(2), 2)
    with assert_raises(contains="no slot"):
        _ = loose.vertex_at(3)
    with assert_raises(contains="no slot"):
        _ = loose.vertex_at(-1)
    var broken = points([0, 0, 0, 1, 0, 0, 0, 1, 0])
    broken.set_index([0, 1, 7])
    with assert_raises(contains="past the last vertex"):
        _ = broken.vertex_at(2)
    with assert_raises():
        _ = BufferGeometry().stream_length()


def test_an_attribute_gathers_the_items_an_index_names() raises:
    """Gathering copies an item once per entry, in the entry's order."""
    var pairs = BufferAttribute([1, 2, 3, 4, 5, 6], 2)
    var gathered = pairs.gather([2, 0, 2])
    assert_equal(gathered.item_size, 2)
    assert_equal(gathered.count(), 3)
    assert_equal(gathered.data[0], 5)
    assert_equal(gathered.data[3], 2)
    assert_equal(pairs.gather(List[Int]()).count(), 0)
    with assert_raises():
        _ = pairs.gather([3])


# --- to_non_indexed ----------------------------------------------------------


def test_a_non_indexed_geometry_gives_every_triangle_its_corners() raises:
    """Six index entries become six vertices, each read through the index."""
    var geometry = quad()
    geometry.add_group(0, 6, MaterialIndex(1))
    var loose = geometry.to_non_indexed()
    assert_false(loose.is_indexed())
    assert_equal(loose.vertex_count(), 6)
    assert_equal(loose.attribute_count(), 3)
    # The fourth corner is the first triangle's first vertex again.
    var fourth = loose.attribute_view(String(POSITION)).vector3(3)
    assert_equal(fourth.x, 0)
    assert_equal(fourth.y, 0)
    ref uvs = loose.attribute_view(String(UV))
    assert_equal(uvs.component(5, 0), 0)
    assert_equal(uvs.component(5, 1), 1)
    assert_equal(len(loose.groups), 1)
    assert_equal(loose.corner(1, 2).y, 1)


def test_morph_targets_are_read_through_the_index_too() raises:
    """Every target and its normals become non-indexed with the base."""
    var geometry = quad()
    var moved = List[Float32]()
    for vertex in range(4):
        moved.append(Float32(vertex))
        moved.append(0)
        moved.append(0)
    geometry.add_morph_target(
        BufferAttribute(moved^, 3),
        BufferAttribute(List[Float32](length=12, fill=0.5), 3),
    )
    geometry.morph_relative = True
    var loose = geometry.to_non_indexed()
    assert_equal(loose.morph_count(), 1)
    assert_true(loose.has_morph_normals())
    assert_true(loose.morph_relative)
    assert_equal(loose.morph_position(0, 5).x, 3)
    assert_equal(loose.morph_normal(0, 5).z, 0.5)


def test_a_geometry_without_an_index_is_copied() raises:
    """A copy comes back, where three.js returns the geometry itself."""
    var geometry = points([0, 0, 0, 1, 0, 0, 0, 1, 0])
    var loose = geometry.to_non_indexed()
    assert_equal(loose.vertex_count(), 3)
    assert_false(loose.is_indexed())


def test_an_index_with_no_attributes_to_read_gives_none() raises:
    """An index over no attributes gives a geometry with no attributes."""
    var geometry = BufferGeometry()
    geometry.set_index([0, 1, 2])
    assert_equal(geometry.to_non_indexed().attribute_count(), 0)


def test_an_index_past_an_attribute_is_refused_when_unshared() raises:
    """An entry past the last item cannot be read."""
    var geometry = points([0, 0, 0, 1, 0, 0, 0, 1, 0])
    geometry.set_index([0, 1, 5])
    with assert_raises():
        _ = geometry.to_non_indexed()


# --- center ------------------------------------------------------------------


def test_center_moves_the_box_onto_the_origin() raises:
    """The box's middle lands on the origin; its size does not change."""
    var geometry = points([1, 2, 3, 3, 6, 5, 2, 4, 4])
    geometry.add_morph_target(BufferAttribute([1, 2, 3, 1, 2, 3, 1, 2, 3], 3))
    geometry.center()
    var box = geometry.bounding_box()
    assert_equal(box.min.x, -1)
    assert_equal(box.max.y, 2)
    assert_equal(box.min.z, -1)
    # A target of finished positions moves with the base.
    assert_equal(geometry.morph_position(0, 0).x, -1)
    assert_equal(geometry.morph_position(0, 0).y, -2)


def test_center_leaves_offsets_where_they_are() raises:
    """A relative target holds offsets, and an offset does not move."""
    var geometry = points([1, 1, 1, 3, 3, 3, 2, 2, 2])
    geometry.add_morph_target(BufferAttribute([1, 0, 0, 1, 0, 0, 1, 0, 0], 3))
    geometry.morph_relative = True
    geometry.center()
    assert_equal(geometry.morph_position(0, 0).x, 1)
    assert_equal(geometry.attribute_view(String(POSITION)).data[0], -1)


def test_center_leaves_an_empty_geometry_alone() raises:
    """No vertices means no box and nothing to move."""
    var geometry = points(List[Float32]())
    geometry.center()
    assert_equal(geometry.vertex_count(), 0)
    var nothing = BufferGeometry()
    with assert_raises():
        nothing.center()


# --- compute_tangents --------------------------------------------------------


def test_a_plane_has_tangents_along_x() raises:
    """U grows along x on three.js's plane, and v along y: right-handed."""
    var sheet = plane(Length(2, METER), Length(1, METER), 2, 2)
    sheet.compute_tangents()
    ref tangents = sheet.attribute_view(String(TANGENT))
    assert_equal(tangents.item_size, 4)
    assert_equal(tangents.count(), sheet.vertex_count())
    for vertex in range(tangents.count()):
        assert_almost_equal(tangents.component(vertex, 0), 1, atol=NEAR)
        assert_almost_equal(tangents.component(vertex, 1), 0, atol=NEAR)
        assert_almost_equal(tangents.component(vertex, 2), 0, atol=NEAR)
        assert_equal(tangents.component(vertex, 3), 1)


def test_a_mirrored_texture_gives_a_left_handed_tangent() raises:
    """U running against x turns the tangent and the handedness over."""
    var geometry = quad()
    geometry.set_attribute(
        String(UV), BufferAttribute([1, 0, 0, 0, 0, 1, 1, 1], 2)
    )
    geometry.compute_tangents()
    ref tangents = geometry.attribute_view(String(TANGENT))
    assert_almost_equal(tangents.component(0, 0), -1, atol=NEAR)
    assert_equal(tangents.component(0, 3), -1)


def test_a_tangent_is_square_to_the_normal() raises:
    """The u direction is flattened onto the surface before it is kept."""
    var geometry = quad()
    # Normals tilted toward x: the tangent loses its part along them.
    var tilt = Float32(1 / sqrt(2.0))
    geometry.set_attribute(
        String(NORMAL),
        BufferAttribute(
            [tilt, 0, tilt, tilt, 0, tilt, tilt, 0, tilt, tilt, 0, tilt], 3
        ),
    )
    geometry.compute_tangents()
    ref tangents = geometry.attribute_view(String(TANGENT))
    assert_almost_equal(tangents.component(0, 0), tilt, atol=NEAR)
    assert_almost_equal(tangents.component(0, 2), -tilt, atol=NEAR)


def test_a_triangle_with_no_texture_area_gives_no_direction() raises:
    """Every corner at one texture coordinate is skipped, as three.js does."""
    var geometry = quad()
    geometry.set_attribute(
        String(UV), BufferAttribute(List[Float32](length=8, fill=0.5), 2)
    )
    geometry.compute_tangents()
    ref tangents = geometry.attribute_view(String(TANGENT))
    assert_equal(tangents.component(0, 0), 0)
    assert_equal(tangents.component(0, 3), 1)


def test_tangents_visit_only_the_triangles_in_groups() raises:
    """A vertex outside every group keeps four zeros."""
    var geometry = points(
        [0, 0, 0, 1, 0, 0, 0, 1, 0, 5, 0, 0, 6, 0, 0, 5, 1, 0]
    )
    geometry.set_attribute(
        String(NORMAL), BufferAttribute(List[Float32](length=18, fill=0), 3)
    )
    geometry.set_attribute(
        String(UV), BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], 2)
    )
    # The first triangle, and an empty group that visits nothing.
    geometry.add_group(0, 3)
    geometry.add_group(3, 0)
    geometry.compute_tangents()
    ref tangents = geometry.attribute_view(String(TANGENT))
    assert_almost_equal(tangents.component(1, 0), 1, atol=NEAR)
    assert_equal(tangents.component(4, 0), 0)
    assert_equal(tangents.component(4, 3), 0)


def test_tangents_need_positions_normals_and_texture_coordinates() raises:
    """Each of the three is required."""
    var geometry = points([0, 0, 0, 1, 0, 0, 0, 1, 0])
    with assert_raises(contains="normal"):
        geometry.compute_tangents()
    geometry.set_attribute(
        String(NORMAL), BufferAttribute(List[Float32](length=9, fill=0), 3)
    )
    with assert_raises(contains="uv"):
        geometry.compute_tangents()
    var nothing = BufferGeometry()
    with assert_raises(contains="position"):
        nothing.compute_tangents()
    var broken = quad()
    broken.set_index([0, 1, 9])
    with assert_raises(contains="past the last vertex"):
        broken.compute_tangents()


# --- merge_geometries --------------------------------------------------------


def test_merged_parts_follow_one_another() raises:
    """Attributes are joined end to end and the index is moved along."""
    var parts = List[BufferGeometry]()
    parts.append(quad())
    parts.append(quad())
    var merged = merge_geometries(parts, use_groups=True)
    assert_equal(merged.vertex_count(), 8)
    assert_equal(len(merged.index), 12)
    assert_equal(merged.index[6], 4)
    assert_equal(merged.index[11], 7)
    assert_equal(merged.attribute_count(), 3)
    assert_equal(merged.attribute_view(String(UV)).count(), 8)
    assert_equal(len(merged.groups), 2)
    assert_equal(merged.groups[1].start, 6)
    assert_equal(merged.groups[1].count, 6)
    assert_true(merged.groups[1].material_index == MaterialIndex(1))


def test_merged_parts_without_an_index_have_none() raises:
    """Parts without an index merge into a geometry without one."""
    var parts = List[BufferGeometry]()
    parts.append(points([0, 0, 0, 1, 0, 0, 0, 1, 0]))
    parts.append(points([0, 0, 1, 1, 0, 1, 0, 1, 1]))
    var merged = merge_geometries(parts)
    assert_false(merged.is_indexed())
    assert_equal(merged.vertex_count(), 6)
    assert_equal(len(merged.groups), 0)
    parts.append(points([0, 0, 2, 1, 0, 2, 0, 1, 2]))
    var grouped = merge_geometries(parts, True)
    assert_equal(grouped.groups[2].start, 6)
    assert_equal(grouped.groups[2].count, 3)


def test_one_part_merges_into_itself() raises:
    """A single part is copied."""
    var parts = List[BufferGeometry]()
    parts.append(quad())
    var merged = merge_geometries(parts)
    assert_equal(merged.vertex_count(), 4)
    assert_equal(len(merged.index), 6)


def test_morph_targets_are_merged_target_by_target() raises:
    """Each target's arrays are joined across the parts."""
    var parts = List[BufferGeometry]()
    for part in range(2):
        var geometry = quad()
        geometry.add_morph_target(
            BufferAttribute(List[Float32](length=12, fill=Float32(part)), 3),
            BufferAttribute(List[Float32](length=12, fill=1), 3),
        )
        geometry.morph_relative = True
        parts.append(geometry^)
    var merged = merge_geometries(parts)
    assert_equal(merged.morph_count(), 1)
    assert_true(merged.has_morph_normals())
    assert_true(merged.morph_relative)
    assert_equal(merged.morph_position(0, 0).x, 0)
    assert_equal(merged.morph_position(0, 7).x, 1)


def test_parts_that_do_not_match_are_refused() raises:
    """Every way two parts can disagree is refused."""
    with assert_raises(contains="at least one"):
        _ = merge_geometries(List[BufferGeometry]())
    var indexed = List[BufferGeometry]()
    indexed.append(quad())
    indexed.append(points([0, 0, 0, 1, 0, 0, 0, 1, 0]))
    with assert_raises(contains="indexed"):
        _ = merge_geometries(indexed)

    var fewer = List[BufferGeometry]()
    fewer.append(points([0, 0, 0, 1, 0, 0, 0, 1, 0]))
    fewer.append(points([0, 0, 0, 1, 0, 0, 0, 1, 0]))
    fewer[1].set_attribute(String(UV), BufferAttribute([0, 0, 1, 0, 0, 1], 2))
    with assert_raises(contains="same attributes"):
        _ = merge_geometries(fewer)

    var named = List[BufferGeometry]()
    named.append(points([0, 0, 0, 1, 0, 0, 0, 1, 0]))
    named.append(BufferGeometry())
    named[1].set_attribute(
        String(NORMAL), BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    with assert_raises(contains="same attributes"):
        _ = merge_geometries(named)

    var sized = List[BufferGeometry]()
    sized.append(points([0, 0, 0, 1, 0, 0, 0, 1, 0]))
    sized.append(BufferGeometry())
    sized[1].set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0], 2)
    )
    with assert_raises(contains="item size"):
        _ = merge_geometries(sized)


def test_parts_whose_morph_targets_disagree_are_refused() raises:
    """The targets must agree in number, in normals and in kind."""
    var counted = List[BufferGeometry]()
    counted.append(quad())
    counted.append(quad())
    counted[1].add_morph_target(
        BufferAttribute(List[Float32](length=12, fill=0), 3)
    )
    with assert_raises(contains="same morph targets"):
        _ = merge_geometries(counted)

    var normals = List[BufferGeometry]()
    normals.append(quad())
    normals.append(quad())
    normals[0].add_morph_target(
        BufferAttribute(List[Float32](length=12, fill=0), 3)
    )
    normals[1].add_morph_target(
        BufferAttribute(List[Float32](length=12, fill=0), 3),
        BufferAttribute(List[Float32](length=12, fill=0), 3),
    )
    with assert_raises(contains="carry normals"):
        _ = merge_geometries(normals)

    var relative = List[BufferGeometry]()
    relative.append(quad())
    relative.append(quad())
    relative[1].morph_relative = True
    with assert_raises(contains="relative"):
        _ = merge_geometries(relative)


def colored_quad(channels: Int, fill: Float32) raises -> BufferGeometry:
    """Return a quad with one named morph target that carries a color of
    `channels` numbers."""
    var geometry = quad()
    geometry.add_morph_target(
        BufferAttribute(List[Float32](length=12, fill=0), 3), name="glow"
    )
    var tints = List[BufferAttribute]()
    tints.append(
        BufferAttribute(List[Float32](length=4 * channels, fill=fill), channels)
    )
    geometry.set_morph_colors(tints^)
    return geometry^


def test_color_targets_are_merged_target_by_target() raises:
    """Each color target is joined across the parts, and the names kept."""
    var parts = List[BufferGeometry]()
    parts.append(colored_quad(3, 0.25))
    parts.append(colored_quad(3, 0.75))
    var merged = merge_geometries(parts)
    assert_true(merged.has_morph_colors())
    assert_equal(merged.morph_colors[0].item_size, 3)
    assert_equal(merged.morph_color(0, 0)[0], 0.25)
    assert_equal(merged.morph_color(0, 7)[0], 0.75)
    assert_equal(merged.morph_target_name(0), "glow")


def test_parts_whose_color_targets_disagree_are_refused() raises:
    """Colors on one part and not the other, or of another size."""
    var plain = List[BufferGeometry]()
    plain.append(colored_quad(3, 0))
    plain.append(quad())
    plain[1].add_morph_target(
        BufferAttribute(List[Float32](length=12, fill=0), 3)
    )
    with assert_raises(contains="carry colors"):
        _ = merge_geometries(plain)
    var sized = List[BufferGeometry]()
    sized.append(colored_quad(3, 0))
    sized.append(colored_quad(4, 0))
    with assert_raises(contains="color target must keep"):
        _ = merge_geometries(sized)


def test_parts_that_cannot_be_read_are_refused() raises:
    """A part with no positions or a bad index is refused."""
    var empty = List[BufferGeometry]()
    empty.append(BufferGeometry())
    empty.append(BufferGeometry())
    with assert_raises(contains="position"):
        _ = merge_geometries(empty)
    var broken = List[BufferGeometry]()
    broken.append(quad())
    broken.append(quad())
    broken[1].set_index([0, 1, 4])
    with assert_raises(contains="past the last vertex"):
        _ = merge_geometries(broken)


# --- merge_vertices ----------------------------------------------------------


def test_two_triangles_of_a_quad_weld_into_four_vertices() raises:
    """The two shared corners become one vertex each."""
    var loose = quad().to_non_indexed()
    assert_equal(loose.vertex_count(), 6)
    var welded = merge_vertices(loose)
    assert_equal(welded.vertex_count(), 4)
    assert_equal(len(welded.index), 6)
    assert_equal(welded.index[3], 0)
    assert_equal(welded.index[4], 2)
    assert_equal(welded.attribute_count(), 3)


def test_every_attribute_decides_what_welds() raises:
    """A cube's corners share places but not normals, and stay apart."""
    var box = cube(Length(1, METER))
    assert_equal(merge_vertices(box).vertex_count(), 24)
    var bare = points(box.clone_attribute(String(POSITION)).data.copy())
    bare.set_index(box.index.copy())
    assert_equal(merge_vertices(bare).vertex_count(), 8)


def test_the_tolerance_decides_how_near_is_one_vertex() raises:
    """Numbers inside one step weld; numbers apart by more do not."""
    var geometry = points([0, 0, 0, 0.00001, 0, 0, 0.5, 0, 0])
    geometry.add_group(0, 3, MaterialIndex(4))
    var welded = merge_vertices(geometry)
    assert_equal(welded.vertex_count(), 2)
    assert_equal(len(welded.groups), 1)
    assert_equal(merge_vertices(geometry, 2.0).vertex_count(), 1)
    # Zero is raised to the smallest step, and keeps every point.
    assert_equal(merge_vertices(geometry, 0.0).vertex_count(), 3)
    assert_equal(DEFAULT_TOLERANCE, 1e-4)
    assert_true(EPSILON > 0)


def test_a_tolerance_that_is_not_a_step_is_refused() raises:
    """A negative, infinite or undefined tolerance is refused."""
    var geometry = points([0, 0, 0, 1, 0, 0, 0, 1, 0])
    with assert_raises(contains="tolerance"):
        _ = merge_vertices(geometry, -1.0)
    with assert_raises(contains="tolerance"):
        _ = merge_vertices(geometry, inf[DType.float64]())
    with assert_raises(contains="tolerance"):
        _ = merge_vertices(geometry, nan[DType.float64]())
    with assert_raises(contains="position"):
        _ = merge_vertices(BufferGeometry())


def test_welding_carries_the_morph_targets_along() raises:
    """A kept vertex keeps its targets; the targets do not decide."""
    var geometry = quad().to_non_indexed()
    var moved = List[Float32]()
    for vertex in range(6):
        moved.append(Float32(vertex))
        moved.append(0)
        moved.append(0)
    geometry.add_morph_target(
        BufferAttribute(moved^, 3),
        BufferAttribute(List[Float32](length=18, fill=1), 3),
    )
    var tints = List[BufferAttribute]()
    tints.append(BufferAttribute(List[Float32](length=18, fill=0.5), 3))
    geometry.set_morph_colors(tints^)
    var welded = merge_vertices(geometry)
    assert_equal(welded.morph_count(), 1)
    assert_true(welded.has_morph_normals())
    assert_true(welded.has_morph_colors())
    assert_equal(welded.morph_colors[0].count(), 4)
    assert_equal(welded.vertex_count(), 4)
    # The fourth kept vertex is the sixth vertex of the source.
    assert_equal(welded.morph_position(0, 3).x, 5)


def test_welding_nothing_gives_nothing() raises:
    """An empty geometry welds into an empty indexed one."""
    var welded = merge_vertices(points(List[Float32]()))
    assert_equal(welded.vertex_count(), 0)
    assert_false(welded.is_indexed())


def test_a_key_truncates_as_javascript_does() raises:
    """Toward zero, zero for NaN, and clamped far out."""
    assert_equal(truncated(2.7), 2)
    assert_equal(truncated(-2.7), -2)
    assert_equal(truncated(nan[DType.float64]()), 0)
    assert_equal(truncated(1e30), Int(KEY_LIMIT))
    assert_equal(truncated(-1e30), -Int(KEY_LIMIT))


def test_undefined_numbers_weld_as_zero() raises:
    """A NaN makes the key a zero does, as `~~` gives in three.js."""
    var geometry = points([nan[DType.float32](), 0, 0, 0, 0, 0, 1, 0, 0])
    assert_equal(merge_vertices(geometry).vertex_count(), 2)


# --- to_creased_normals ------------------------------------------------------


def test_a_cube_keeps_its_flat_faces() raises:
    """Faces a right angle apart are across a crease of sixty degrees."""
    var creased = to_creased_normals(cube(Length(1, METER)))
    assert_false(creased.is_indexed())
    assert_equal(creased.vertex_count(), 36)
    ref normals = creased.attribute_view(String(NORMAL))
    for vertex in range(36):
        var normal = normals.vector3(vertex)
        var largest = max(abs(normal.x), abs(normal.y), abs(normal.z))
        assert_almost_equal(largest, 1, atol=NEAR)


def test_a_wide_crease_rounds_a_cube_corner() raises:
    """Past a right angle, a corner leans into all three of its faces.

    The faces are summed by triangle, as three.js sums them, and a face
    holds one or two triangles at a given corner. So the corner leans
    toward some faces more than others, and is not the exact diagonal.
    """
    var creased = to_creased_normals(
        cube(Length(1, METER)), Angle(100.0, DEGREE)
    )
    ref positions = creased.attribute_view(String(POSITION))
    ref normals = creased.attribute_view(String(NORMAL))
    for vertex in range(creased.vertex_count()):
        var normal = normals.vector3(vertex)
        var place = positions.vector3(vertex)
        assert_almost_equal(normal.length(), 1, atol=NEAR)
        assert_true(normal.x * place.x > 0.1)
        assert_true(normal.y * place.y > 0.1)
        assert_true(normal.z * place.z > 0.1)


def test_a_sphere_shades_smoothly() raises:
    """A sphere's facets turn by less than the crease: normals point out."""
    var ball = sphere(Length(1, METER), 24, 16)
    var creased = to_creased_normals(ball, DEFAULT_CREASE)
    ref positions = creased.attribute_view(String(POSITION))
    ref normals = creased.attribute_view(String(NORMAL))
    for vertex in range(0, creased.vertex_count(), 97):
        var place = positions.vector3(vertex)
        # The poles are fans of faces with no area; skip them.
        if abs(place.y) > 0.99:
            continue
        assert_true(place.dot(normals.vector3(vertex)) > 0.99)


def test_a_loose_geometry_is_left_alone() raises:
    """A geometry without an index is copied, not changed."""
    var geometry = points([0, 0, 0, 1, 0, 0, 0, 1, 0, 5, 5, 5])
    var creased = to_creased_normals(geometry)
    assert_false(geometry.has_attribute(String(NORMAL)))
    ref normals = creased.attribute_view(String(NORMAL))
    assert_almost_equal(normals.component(0, 2), 1, atol=NEAR)
    # The fourth vertex belongs to no whole triangle.
    assert_equal(normals.component(3, 2), 0)
    var empty = to_creased_normals(points(List[Float32]()))
    assert_equal(empty.vertex_count(), 0)


def test_a_crease_that_is_not_an_angle_is_refused() raises:
    """A negative or undefined crease angle is refused."""
    var geometry = points([0, 0, 0, 1, 0, 0, 0, 1, 0])
    with assert_raises(contains="crease"):
        _ = to_creased_normals(geometry, Angle(-1.0, DEGREE))
    with assert_raises(contains="crease"):
        _ = to_creased_normals(
            geometry, Angle(Float32(nan[DType.float32]()), DEGREE)
        )
    with assert_raises(contains="position"):
        _ = to_creased_normals(BufferGeometry())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
