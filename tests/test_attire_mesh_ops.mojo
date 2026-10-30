# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the mesh operations garments are cut and joined with."""

from std.memory import bitcast

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.attire.mesh_ops import (
    COVER,
    MeshWriter,
    add_rim,
    cut,
    cut_attribute,
    keep_triangles,
    merge,
    normalize_normals,
    top_four,
    vertex_neighbors,
    weld_groups,
)
from extensions.humanoid.rig.joints import CHEST, HIPS
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import empty_mesh, strip


def _mesh(points: List[Float32], index: List[Int]) raises -> BufferGeometry:
    """Return a mesh of flat positions, indexed if `index` is not empty."""
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(points.copy(), 3))
    if len(index) > 0:
        mesh.set_index(index.copy())
    return mesh^


def test_copies_of_a_vertex_weld_and_collisions_do_not() raises:
    # Vertex 2 copies vertex 0. Vertices 3 and 4 stand apart: (1, 0, 0)
    # and (0, tiny, 0), whose y bits shifted by 16 equal the bits of one,
    # so a hash that mixes the three by shifts would join them.
    var tiny = bitcast[DType.float32](UInt32(0x00003F80))
    var mesh = _mesh(
        [0, 0, 0, 5, 0, 0, 0, 0, 0, 1, 0, 0, 0, tiny, 0],
        List[Int](),
    )
    var groups = weld_groups(mesh)
    assert_equal(groups, [0, 1, 0, 3, 4])


def test_neighbors_are_welded_and_unique() raises:
    # Two triangles share an edge through a copied vertex, and one is
    # degenerate after welding.
    var mesh = _mesh(
        [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0],
        [0, 1, 2, 3, 4, 5, 0, 1, 1],
    )
    var groups = weld_groups(mesh)
    var around = vertex_neighbors(mesh, groups)
    assert_equal(len(around[0]), 2)
    assert_equal(len(around[1]), 3)
    assert_equal(len(around[3]), 0)
    with assert_raises(contains="one entry per vertex"):
        _ = vertex_neighbors(mesh, [0, 1])


def test_a_cut_clips_triangles_along_the_level() raises:
    var mesh = strip(0, 2, HIPS)
    var values = List[Float32]()
    ref placed = mesh.attribute_view(String(POSITION))
    for v in range(placed.count()):
        values.append(placed.vector3(v).y + 0.75)
    var kept = cut(mesh, values, 0)
    # The first quad whole; the second clipped into three triangles.
    assert_equal(kept.triangle_count(), 5)
    # Four corners kept, and one new vertex on each of three edges: the
    # edge two triangles share gives one vertex, not two.
    assert_equal(kept.vertex_count(), 7)
    ref out = kept.attribute_view(String(POSITION))
    var lowest = Float32(1)
    for v in range(out.count()):
        lowest = min(lowest, out.vector3(v).y)
    assert_almost_equal(lowest, -0.75, atol=1e-6)
    # Every attribute is carried; normals stay +z.
    assert_almost_equal(
        kept.attribute_view(String(NORMAL)).vector3(6).z, 1, atol=1e-6
    )
    assert_equal(kept.attribute_view(String(SKIN_WEIGHT)).component(6, 0), 1)
    # All above, or all below.
    assert_equal(cut(mesh, values, -5).triangle_count(), 4)
    assert_equal(cut(mesh, values, 5).triangle_count(), 0)
    with assert_raises(contains="one value per vertex"):
        _ = cut(mesh, [Float32(1)], 0)


def test_a_cut_merges_skin_weights() raises:
    # Two rows bound to different joints: the new vertices take both, and
    # the empty places are zero.
    var mesh = strip(0, 1, HIPS)
    var bones = mesh.clone_attribute(String(SKIN_INDEX))
    bones.set_component(2, 0, Float32(CHEST.value))
    bones.set_component(3, 0, Float32(CHEST.value))
    mesh.set_attribute(String(SKIN_INDEX), bones^)
    var kept = cut(mesh, [1, 1, -1, -1], 0)
    ref joints = kept.attribute_view(String(SKIN_INDEX))
    ref weights = kept.attribute_view(String(SKIN_WEIGHT))
    var last = kept.vertex_count() - 1
    assert_almost_equal(weights.component(last, 0), 0.5, atol=1e-6)
    assert_almost_equal(weights.component(last, 1), 0.5, atol=1e-6)
    assert_equal(weights.component(last, 3), 0)
    var named = List[Int]()
    named.append(Int(joints.component(last, 0)))
    named.append(Int(joints.component(last, 1)))
    assert_true(HIPS.value in named and CHEST.value in named)


def test_a_cut_mixes_meshes_with_and_without_skins() raises:
    # No skin: every attribute mixes linearly. Skin indices without
    # weights: the indices mix as plain numbers.
    var bare = _mesh([0, 0, 0, 1, 0, 0, 0, 1, 0], List[Int]())
    var half = cut(bare, [1, -1, 1], 0)
    assert_equal(half.triangle_count(), 2)
    var partial = strip(0, 1, CHEST, normals=False)
    partial.delete_attribute(String(SKIN_WEIGHT))
    var mixed = cut(partial, [1, 1, -1, -1], 0)
    assert_almost_equal(
        mixed.attribute_view(String(SKIN_INDEX)).component(4, 0),
        Float32(CHEST.value),
        atol=1e-6,
    )


def test_meshes_merge_when_their_attributes_match() raises:
    var a = strip(0, 1, HIPS)
    var b = strip(3, 2, HIPS)
    var both = merge(a, b)
    assert_equal(both.vertex_count(), 4 + 6)
    assert_equal(both.triangle_count(), 2 + 4)
    assert_equal(both.corner_index(2, 0), 4)
    with assert_raises(contains="same attributes"):
        _ = merge(a, strip(0, 1, HIPS, normals=False))
    var renamed = strip(0, 1, HIPS, normals=False)
    renamed.set_attribute(
        "other", BufferAttribute(List[Float32](length=4, fill=0), 1)
    )
    with assert_raises(contains="same attributes"):
        _ = merge(a, renamed)
    var wide = strip(0, 1, HIPS)
    wide.set_attribute(
        String(NORMAL), BufferAttribute(List[Float32](length=8, fill=0), 2)
    )
    with assert_raises(contains="same attributes"):
        _ = merge(a, wide)


def test_triangles_are_kept_by_a_mask() raises:
    var mesh = strip(0, 2, HIPS)
    keep_triangles(mesh, [True, False, False, True])
    assert_equal(mesh.triangle_count(), 2)
    # Dropping every triangle leaves one degenerate one, not an empty
    # index that would draw every vertex.
    keep_triangles(mesh, [False, False])
    assert_equal(mesh.triangle_count(), 1)
    assert_equal(mesh.corner_index(0, 2), 0)
    with assert_raises(contains="one flag per triangle"):
        keep_triangles(mesh, [True, True])


def test_a_cut_can_read_the_mesh_s_own_attribute() raises:
    var mesh = strip(0, 2, HIPS)
    mesh.set_attribute(
        "height", BufferAttribute([Float32(0), 0, 1, 1, 2, 2], 1)
    )
    var top = cut_attribute(mesh, "height", 1.5, True)
    var bottom = cut_attribute(mesh, "height", 1.5, False)
    # The crossing quad's two triangles clip into one and two above the
    # level, and two and one below it.
    assert_equal(top.triangle_count(), 3)
    assert_equal(bottom.triangle_count(), 5)
    # The attribute rides along: a second cut reads it at the new
    # vertices.
    var band = cut_attribute(
        cut_attribute(mesh, "height", 0.5, True), "height", 1.5, False
    )
    ref height = band.attribute_view("height")
    for v in range(height.count()):
        assert_true(height.component(v, 0) >= 0.5 - 1e-6)
        assert_true(height.component(v, 0) <= 1.5 + 1e-6)
    with assert_raises(contains="no attribute named"):
        _ = cut_attribute(mesh, "missing", 0, True)


def test_normals_scale_back_to_unit_length() raises:
    var mesh = strip(0, 1, HIPS)
    mesh.set_attribute(
        String(NORMAL),
        BufferAttribute([Float32(0), 0, 2, 0, 0, 0, 3, 0, 0, 0, 0.5, 0], 3),
    )
    normalize_normals(mesh)
    ref normals = mesh.attribute_view(String(NORMAL))
    assert_almost_equal(normals.vector3(0).z, 1)
    assert_equal(normals.vector3(1).length(), 0)
    assert_almost_equal(normals.vector3(2).x, 1)
    assert_almost_equal(normals.vector3(3).y, 1)


def test_an_empty_mesh_passes_through_every_operation() raises:
    var mesh = empty_mesh()
    var groups = weld_groups(mesh)
    assert_equal(len(groups), 0)
    assert_equal(len(vertex_neighbors(mesh, groups)), 0)
    var kept = cut(mesh, List[Float32](), 0)
    assert_equal(kept.vertex_count(), 0)
    assert_equal(kept.triangle_count(), 0)
    var above = cut_attribute(mesh, String(SKIN_WEIGHT), 0.5, True)
    assert_equal(above.vertex_count(), 0)
    assert_equal(merge(mesh, kept).triangle_count(), 0)
    keep_triangles(mesh, List[Bool]())
    assert_equal(mesh.triangle_count(), 0)
    normalize_normals(mesh)
    assert_equal(mesh.attribute_view(String(NORMAL)).count(), 0)


def test_the_four_heaviest_bones_are_kept() raises:
    var all: List[Float32] = [0.1, 0.4, 0, 0.2, 0.2, 0.1]
    var four = top_four(all)
    assert_equal(four[0], [1, 3, 4, 0])
    assert_almost_equal(four[1][0], 0.4 / 0.9)
    var none = top_four(List[Float32](length=5, fill=0))
    assert_equal(none[1][0], 0)


def test_a_writer_writes_another_mesh_s_attributes() raises:
    var like = strip(0, 1, HIPS)
    like.set_attribute(
        String(COVER), BufferAttribute(List[Float32](length=4, fill=1), 1)
    )
    var writer = MeshWriter(like)
    var a = writer.add(Vector3(0, 0, 0), 0.5, [2, 0, 0, 0], [1, 0, 0, 0])
    var b = writer.add(
        Vector3(1, 0, 0), 1, [HIPS.value, CHEST.value, 0, 0], [0.5, 0.5, 0, 0]
    )
    var c = writer.add(Vector3(0, 1, 0), 1, [2, 0, 0, 0], [1, 0, 0, 0])
    var d = writer.add(Vector3(1, 1, 0), 1, [2, 0, 0, 0], [1, 0, 0, 0])
    assert_equal(d, 3)
    writer.quad(c, a, d, b)
    writer.triangle(a, b, c)
    var mesh = writer.build()
    assert_equal(mesh.vertex_count(), 4)
    assert_equal(mesh.triangle_count(), 3)
    assert_almost_equal(mesh.attribute_view(String(COVER)).component(0, 0), 0.5)
    assert_equal(
        mesh.attribute_view(String(SKIN_INDEX)).component(1, 1),
        Float32(CHEST.value),
    )
    # The normals are made from the faces, which face +z.
    assert_almost_equal(mesh.attribute_view(String(NORMAL)).vector3(0).z, 1)
    # A mesh with no attributes writes none.
    var bare = MeshWriter(BufferGeometry())
    assert_equal(bare.add(Vector3(0, 0, 0), 1, [0, 0, 0, 0], [1, 0, 0, 0]), 0)


def test_an_open_edge_takes_a_rim() raises:
    # One quad, facing -z as it winds: four open edges, each with a rim of
    # two triangles, running back 2 mm and facing out of the edge.
    var quad = strip(0, 1, HIPS, normals=False)
    quad.compute_vertex_normals()
    var rimmed = add_rim(quad, 0.002)
    assert_equal(rimmed.triangle_count(), 2 + 4 * 2)
    assert_equal(rimmed.vertex_count(), 4 + 4 * 4)
    ref placed = rimmed.attribute_view(String(POSITION))
    ref normals = rimmed.attribute_view(String(NORMAL))
    var back = 0
    var down = 0
    for v in range(4, rimmed.vertex_count()):
        if placed.vector3(v).z > 0.0019:
            back += 1
        var n = normals.vector3(v)
        assert_almost_equal(n.z, 0)
        # The bottom edge's rim faces down, out of the quad.
        if placed.vector3(v).y < -0.99 and n.y < -0.99:
            down += 1
    assert_equal(back, 8)
    assert_equal(down, 4)
    # Its vertices keep the edge's skin weights.
    assert_equal(
        Int(rimmed.attribute_view(String(SKIN_INDEX)).component(4, 0)),
        HIPS.value,
    )
    # A seam where the mesh was parted into copies is not an edge: two
    # quads that share an edge by position alone have six open edges.
    var two = merge(strip(0, 1, HIPS), strip(1, 1, HIPS))
    assert_equal(add_rim(two, 0.002).triangle_count(), 4 + 6 * 2)
    # Normals turned against the faces are turned back: the rim still runs
    # in from the face.
    var turned = add_rim(strip(0, 1, HIPS), 0.002)
    assert_true(turned.attribute_view(String(POSITION)).vector3(5).z > 0.0019)
    # A sliver whose edge has no length takes no rim.
    var sliver = strip(0, 1, HIPS)
    var flat = sliver.clone_attribute(String(POSITION))
    flat.set_component(1, 0, flat.component(0, 0))
    flat.set_component(3, 0, flat.component(2, 0))
    sliver.set_attribute(String(POSITION), flat^)
    assert_true(add_rim(sliver, 0.002).triangle_count() < 2 + 4 * 2)
    # No normals: refused.
    with assert_raises():
        _ = add_rim(strip(0, 1, HIPS, normals=False), 0.002)


def test_meshes_without_positions_cannot_be_merged() raises:
    with assert_raises():
        _ = merge(BufferGeometry(), BufferGeometry())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
