# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a garment's shell, made from the skin it covers."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from extensions.attire.shell import (
    COVER,
    HIDE_LEVEL,
    SkinFrame,
    garment_piece,
    hidden_mask,
    hide_under,
    outer_faces,
    shell_positions,
    smooth_values,
    standoff,
    under_share,
)
from extensions.humanoid.rig.joints import HIPS
from extensions.humanoid.skeleton.head.skin.tint import THINNESS
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import empty_mesh, strip


def _tent() raises -> BufferGeometry:
    """Return a strip of four rungs whose middle rung stands out 0.2 m."""
    var mesh = strip(0, 4, HIPS)
    var places = mesh.clone_attribute(String(POSITION))
    places.set_component(4, 2, 0.2)
    places.set_component(5, 2, 0.2)
    mesh.set_attribute(String(POSITION), places^)
    return mesh^


def test_a_frame_reads_points_normals_and_neighbors() raises:
    var mesh = strip(0, 2, HIPS)
    var frame = SkinFrame(mesh)
    assert_equal(frame.count(), 6)
    assert_almost_equal(frame.normals[3].z, 1)
    assert_equal(len(frame.neighbors[0]), 2)
    # Without normals, the frame computes them.
    var bare = strip(0, 2, HIPS, normals=False)
    var made = SkinFrame(bare)
    assert_almost_equal(abs(made.normals[2].z), 1, atol=1e-5)
    # Copies of a vertex share the mean of their normals; opposite ones
    # cancel, and the vertex then moves straight up.
    var twin = BufferGeometry()
    twin.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(0), 0, 0, 0, 0, 0, 1, 0, 0], 3),
    )
    twin.set_attribute(
        String(NORMAL),
        BufferAttribute([Float32(0), 0, 1, 0, 0, -1, 0, 0, 1], 3),
    )
    twin.set_index([0, 1, 2])
    var cancelled = SkinFrame(twin)
    assert_equal(cancelled.normals[0].y, 1)
    assert_equal(cancelled.normals[1].y, 1)
    assert_equal(cancelled.normals[2].z, 1)


def test_values_smooth_over_welded_edges() raises:
    var mesh = strip(0, 2, HIPS)
    var frame = SkinFrame(mesh)
    var step: List[Float32] = [1, 1, 1, 1, 0, 0]
    var kept = smooth_values(frame, step, 0)
    assert_equal(kept, step)
    var smooth = smooth_values(frame, step, 2)
    assert_true(smooth[0] < 1)
    assert_true(smooth[5] > 0)
    with assert_raises(contains="one value per vertex"):
        _ = smooth_values(frame, [Float32(1)], 1)
    # A copy takes its group's value; a vertex with no neighbor keeps its.
    var twin = BufferGeometry()
    twin.set_attribute(
        String(POSITION),
        BufferAttribute(
            [Float32(0), 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 5, 5, 5], 3
        ),
    )
    twin.set_index([0, 1, 2])
    var shared = smooth_values(SkinFrame(twin), [0, 1, 1, 0, 3], 1)
    assert_equal(shared[0], shared[3])
    assert_equal(shared[4], 3)


def test_a_layer_under_lifts_the_one_over_it() raises:
    assert_equal(under_share(0), 0)
    assert_equal(under_share(0.25), 0)
    assert_equal(under_share(0.5), 1)
    assert_almost_equal(under_share(0.375), 0.5)
    var values: List[List[Float32]] = [[1, 0.5, 0], [0, 1, 1]]
    var faces: List[List[Float32]] = [[0.01, 0.02, 0.03], [0.005, 0.004, 0.003]]
    assert_almost_equal(standoff(0.002, values, faces, 0), 0.012)
    assert_almost_equal(standoff(0.002, values, faces, 1), 0.022)
    assert_almost_equal(standoff(0.002, values, faces, 2), 0.005)
    assert_almost_equal(
        standoff(0.002, List[List[Float32]](), List[List[Float32]](), 0), 0.002
    )


def test_a_shell_stands_off_and_drapes() raises:
    var mesh = _tent()
    var frame = SkinFrame(mesh)
    var standoffs = List[Float32](length=10, fill=0.01)
    var covered = List[Float32](length=10, fill=1)
    var stiff = shell_positions(frame, standoffs, covered, 0)
    assert_almost_equal(stiff[4].z, 0.21, atol=1e-6)
    assert_almost_equal(stiff[0].z, 0.01, atol=1e-6)
    # Draped, the peak keeps its standoff and the hollows beside it rise:
    # the shell spans them.
    var draped = shell_positions(frame, standoffs, covered, 6)
    var out = outer_faces(frame, draped, 0.002)
    for v in range(10):
        assert_true(out[v] >= 0.01 + 0.002 - 1e-5)
    assert_true(draped[2].z > stiff[2].z)
    assert_true(draped[6].z > stiff[6].z)
    # Bare vertices hold still.
    var bare = List[Float32](length=10, fill=0)
    var still = shell_positions(frame, standoffs, bare, 6)
    assert_almost_equal(still[2].z, stiff[2].z)
    with assert_raises(contains="one standoff and one value"):
        _ = shell_positions(frame, [Float32(0)], covered, 1)
    with assert_raises(contains="one standoff and one value"):
        _ = shell_positions(frame, standoffs, [Float32(0)], 1)
    with assert_raises(contains="zero or more"):
        _ = shell_positions(frame, standoffs, covered, -1)
    with assert_raises(contains="one position per vertex"):
        _ = outer_faces(frame, List[Vector3](), 0.002)


def test_a_drape_skips_vertices_with_no_neighbors() raises:
    var lone = BufferGeometry()
    lone.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(0), 0, 0, 1, 0, 0, 0, 1, 0, 9, 9, 9], 3),
    )
    lone.set_index([0, 1, 2])
    var frame = SkinFrame(lone)
    var places = shell_positions(
        frame,
        List[Float32](length=4, fill=0.1),
        List[Float32](length=4, fill=1),
        2,
    )
    assert_almost_equal(places[3].x, 9)


def test_covered_triangles_hide() raises:
    var mesh = strip(0, 2, HIPS)
    var over: List[Float32] = [1, 1, 1, 1, HIDE_LEVEL - 0.1, 1]
    var keep = hidden_mask(mesh, over)
    assert_false(keep[0])
    assert_true(keep[2])
    with assert_raises(contains="one value per vertex"):
        _ = hidden_mask(mesh, [Float32(1)])
    hide_under(mesh, over)
    assert_equal(mesh.triangle_count(), 2)


def test_a_piece_is_cut_at_its_hems() raises:
    var skin = strip(0, 2, HIPS)
    skin.set_attribute(
        String(COLOR), BufferAttribute(List[Float32](length=18, fill=1), 3)
    )
    skin.set_attribute(
        String(THINNESS), BufferAttribute(List[Float32](length=6, fill=0), 1)
    )
    var frame = SkinFrame(skin)
    var places = shell_positions(
        frame,
        List[Float32](length=6, fill=0.01),
        List[Float32](length=6, fill=1),
        0,
    )
    var values: List[Float32] = [1, 1, 1, 1, 0, 0]
    var nothing = List[Float32](length=6, fill=0)
    var piece = garment_piece(skin, places, values, nothing)
    assert_true(piece.triangle_count() > 0)
    assert_false(piece.has_attribute(String(COLOR)))
    assert_false(piece.has_attribute(String(THINNESS)))
    assert_true(piece.has_attribute(String(COVER)))
    assert_almost_equal(
        piece.attribute_view(String(POSITION)).vector3(0).z, 0.01, atol=1e-6
    )
    # Hidden wholly by a layer over it: nothing.
    var hidden = garment_piece(
        skin, places, values, List[Float32](length=6, fill=1)
    )
    assert_equal(hidden.triangle_count(), 0)
    # Covering none of this skin: nothing.
    var none = garment_piece(skin, places, nothing, nothing)
    assert_equal(none.triangle_count(), 0)
    with assert_raises(contains="one place and one value"):
        _ = garment_piece(skin, List[Vector3](), values, nothing)
    with assert_raises(contains="one place and one value"):
        _ = garment_piece(skin, places, [Float32(1)], nothing)


def test_an_empty_skin_makes_an_empty_piece() raises:
    var with_normals = SkinFrame(empty_mesh())
    assert_equal(with_normals.count(), 0)
    var frame = SkinFrame(empty_mesh(normals=False))
    assert_equal(frame.count(), 0)
    var none = List[Float32]()
    assert_equal(len(smooth_values(frame, none, 3)), 0)
    var places = shell_positions(frame, none, none, 4)
    assert_equal(len(places), 0)
    assert_equal(len(outer_faces(frame, places, 0.001)), 0)
    assert_equal(len(hidden_mask(empty_mesh(), none)), 0)
    var piece = garment_piece(empty_mesh(), places, none, none)
    assert_equal(piece.triangle_count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
