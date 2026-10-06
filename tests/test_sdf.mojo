# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shared distance field package: vectors, frames, ids, primitives,
smooth unions, sculpt helpers and the narrow-band surface nets mesher."""

from extensions.sdf.ids import (
    BoneId,
    CONE,
    ELLIPSOID,
    FIN,
    LENS,
    PrimitiveKind,
    SurfacePart,
    TagId,
    require_kind,
    require_part,
)
from extensions.animals.parts import (
    BODY,
    JAW,
)
from extensions.sdf.sculpt import (
    cone_or_ball,
    ell_y,
    tube,
)
from extensions.sdf.distance import (
    almond_distance,
    ellipsoid_estimate,
    oriented_ellipsoid_estimate,
    rect_distance,
    round_cone_estimate,
    segment_distance,
    segment_param,
)
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    head_local,
    sculpt_eye_socket,
)
from extensions.sdf.mesher import (
    Lattice,
    SPILL_ROUNDS,
    SurfaceMesh,
    UNSAMPLED,
    _Grid,
    _blocks,
    _checked_count,
    _check_grid_sizes,
    _faces,
    _mesh_part,
    _number_vertices,
    _sample_band,
    _share_faces,
    _wake,
    check_cell,
    merge,
    mesh_part,
)
from extensions.animals.noise import cells3, fbm3, ihash, vnoise3
from extensions.animals.options import (
    ADULT,
    ANY_AGE,
    ANY_SEX,
    ANY_VARIANT,
    CROWD,
    FEMALE,
    HERO,
    HIGH,
    JUVENILE,
    LOW,
    MALE,
    MEDIUM,
    Age,
    AnimalOptions,
    Quality,
    Sex,
    Variant,
    animal_options,
    body_random,
    check_options,
    coat_random,
)
from extensions.animals.rig import (
    NO_BONE,
    Bone,
    Pose,
    Rig,
    add_sided,
    quadruped_bones,
    tail_chain,
)
from extensions.sdf.field import (
    FAR,
    SdfModel,
    outline_distance,
    smin,
)
from extensions.animals.traits import (
    Traits,
    pick_age,
    pick_sex,
    pick_variant,
)
from extensions.sdf.vector import (
    Rigid,
    V3,
    clamp,
    on_side,
    cross,
    distance,
    dot,
    frame_zy,
    identity,
    length,
    lerp,
    mirror,
    mix,
    normalize,
    rotate_about,
    rotation_about,
    smoothstep,
    v3,
)
from extensions.animals.warp import (
    GIRTH,
    LEGS,
    SCALE_ABOUT,
    SHIFT,
    Warp,
    WarpKind,
    Warps,
    apply_warp,
    check_warp,
    girth_warp,
    legs_warp,
    length_warp,
    scale_about_warp,
    scale_warp,
    shift_warp,
)
from std.math import inf, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import METER, Length


def _near(a: V3, b: V3, tolerance: Float64 = 1e-9) raises:
    assert_almost_equal(a.x, b.x, atol=tolerance)
    assert_almost_equal(a.y, b.y, atol=tolerance)
    assert_almost_equal(a.z, b.z, atol=tolerance)


def test_vector_arithmetic() raises:
    var a = v3(1, 2, 3)
    var b = V3(4, 5, 6)
    _near(a + b, V3(5, 7, 9))
    _near(b - a, V3(3, 3, 3))
    _near(a * 2.0, V3(2, 4, 6))
    _near(-a, V3(-1, -2, -3))
    assert_equal(dot(a, b), 32.0)
    _near(cross(V3(1, 0, 0), V3(0, 1, 0)), V3(0, 0, 1))
    assert_equal(length(V3(3, 4, 0)), 5.0)
    assert_equal(distance(a, a), 0.0)
    _near(normalize(V3(0, 0, 2)), V3(0, 0, 1))
    # A zero vector stays zero rather than dividing by zero.
    _near(normalize(V3(0, 0, 0)), V3(0, 0, 0))
    _near(lerp(a, b, 0.5), V3(2.5, 3.5, 4.5))
    _near(mirror(a), V3(-1, 2, 3))


def test_scalar_helpers() raises:
    assert_equal(clamp(-1.0, 0.0, 1.0), 0.0)
    assert_equal(clamp(2.0, 0.0, 1.0), 1.0)
    assert_equal(clamp(0.5, 0.0, 1.0), 0.5)
    assert_equal(smoothstep(0.0, 1.0, -1.0), 0.0)
    assert_equal(smoothstep(0.0, 1.0, 0.5), 0.5)
    assert_equal(smoothstep(0.0, 1.0, 2.0), 1.0)
    # A reversed step falls instead of rising.
    assert_equal(smoothstep(1.0, 0.0, 0.0), 1.0)
    assert_equal(mix(2.0, 4.0, 0.25), 2.5)


def test_frames_and_turns() raises:
    var f = frame_zy(V3(0, 0, 2), V3(0, 1, 0))
    _near(f.x, V3(1, 0, 0))
    _near(f.y, V3(0, 1, 0))
    _near(f.z, V3(0, 0, 1))
    # A hint along the axis falls back to world x.
    var g = frame_zy(V3(0, 1, 0), V3(0, 1, 0))
    _near(g.z, V3(0, 1, 0))
    assert_almost_equal(dot(g.x, g.z), 0.0, atol=1e-12)
    _near(rotate_about(V3(1, 0, 0), V3(0, 0, 1), pi / 2.0), V3(0, 1, 0), 1e-12)
    var turn = rotation_about(V3(1, 0, 0), V3(0, 0, 1), pi / 2.0)
    # The pivot stays put, and a point beside it swings round it.
    _near(turn.apply(V3(1, 0, 0)), V3(1, 0, 0), 1e-12)
    _near(turn.apply(V3(2, 0, 0)), V3(1, 1, 0), 1e-12)
    _near(turn.turn(V3(1, 0, 0)), V3(0, 1, 0), 1e-12)
    _near(turn.inverse().apply(V3(1, 1, 0)), V3(2, 0, 0), 1e-12)
    var both = turn.then(turn)
    _near(both.apply(V3(2, 0, 0)), V3(0, 0, 0), 1e-12)
    _near(identity().apply(V3(3, 2, 1)), V3(3, 2, 1))


def test_ids_are_checked() raises:
    assert_true(PrimitiveKind(3).is_valid())
    assert_false(PrimitiveKind(4).is_valid())
    assert_false(PrimitiveKind(-1).is_valid())
    assert_true(BoneId(0).is_valid())
    assert_false(BoneId(-1).is_valid())
    assert_true(TagId(0).is_valid())
    assert_false(TagId(-1).is_valid())
    assert_true(SurfacePart(11).is_valid())
    assert_false(SurfacePart(12).is_valid())
    assert_false(SurfacePart(-1).is_valid())
    require_part(JAW)
    require_kind(FIN)
    with assert_raises(contains="Surface part"):
        require_part(SurfacePart(12))
    with assert_raises(contains="Primitive kind"):
        require_kind(PrimitiveKind(9))


def test_smooth_minimum() raises:
    assert_equal(smin(1.0, 2.0, 0.0), 1.0)
    assert_equal(smin(2.0, 1.0, -1.0), 1.0)
    # Far apart, the blend leaves the minimum alone.
    assert_equal(smin(1.0, 3.0, 0.5), 1.0)
    # Equal distances dip by a quarter of the blend radius.
    assert_almost_equal(smin(1.0, 1.0, 0.4), 0.9)


def _ball() raises -> SdfModel:
    var m = SdfModel()
    _ = m.sphere("ball", BoneId(0), V3(0, 0, 0), 1.0, k=0.0)
    return m^


def test_ellipsoid_distance() raises:
    var m = SdfModel()
    _ = m.ell("egg", BoneId(0), V3(0, 0, 0), V3(1, 2, 3))
    # The center reads as the least radius inside.
    assert_equal(m.distance(0, V3(0, 0, 0)), -1.0)
    assert_almost_equal(m.distance(0, V3(2, 0, 0)), 1.0, atol=1e-9)
    assert_almost_equal(m.distance(0, V3(0, 0, 3)), 0.0, atol=1e-9)
    # A turned ellipsoid has its long axis along `axis`.
    var t = SdfModel()
    _ = t.ell("egg", BoneId(0), V3(0, 0, 0), V3(1, 1, 3), axis=V3(1, 0, 0))
    assert_almost_equal(t.distance(0, V3(3, 0, 0)), 0.0, atol=1e-9)


def test_cone_distance() raises:
    var m = SdfModel()
    _ = m.cone("bone", BoneId(0), V3(0, 0, 0), V3(0, 0, 1), 0.5, 0.25)
    # Beyond each end, the distance is to that end's ball.
    assert_almost_equal(m.distance(0, V3(0, 0, -1)), 0.5, atol=1e-9)
    assert_almost_equal(m.distance(0, V3(0, 0, 2)), 0.75, atol=1e-9)
    # Beside the middle, the distance is to the slanted side.
    var side = m.distance(0, V3(1, 0, 0.5))
    assert_true(side > 0.5)
    assert_true(side < 0.7)
    # A cone wider at its far end works the same way.
    var w = SdfModel()
    _ = w.cone("bone", BoneId(0), V3(0, 0, 0), V3(0, 0, 1), 0.25, 0.5)
    assert_almost_equal(w.distance(0, V3(0, 0, 2)), 0.5, atol=1e-9)
    assert_almost_equal(w.distance(0, V3(0, 0, -1)), 0.75, atol=1e-9)


def test_cone_refusals() raises:
    var m = SdfModel()
    with assert_raises(contains="ends must differ"):
        _ = m.cone("x", BoneId(0), V3(0, 0, 0), V3(0, 0, 0), 0.1, 0.1)
    with assert_raises(contains="must not be negative"):
        _ = m.cone("x", BoneId(0), V3(0, 0, 0), V3(0, 0, 1), -0.1, 0.1)
    with assert_raises(contains="hold each other"):
        _ = m.cone("x", BoneId(0), V3(0, 0, 0), V3(0, 0, 1), 2.0, 0.1)


def test_lens_distance() raises:
    var m = SdfModel()
    _ = m.lens(
        "eye",
        BoneId(0),
        V3(0, 0, 0),
        V3(1, 0, 0),
        V3(0, 1, 0),
        V3(0, 0, 1),
        1.0,
        0.5,
        -1.0,
        1.0,
    )
    # The almond is 2 sqrt(0.75) wide and one high.
    assert_almost_equal(m.distance(0, V3(0, 0.5, 0)), 0.0, atol=1e-9)
    assert_true(m.distance(0, V3(0, 0, 0)) < 0.0)
    assert_almost_equal(m.distance(0, V3(0, 0, 2)), 1.0, atol=1e-9)
    with assert_raises(contains="arcs must overlap"):
        _ = m.lens(
            "e",
            BoneId(0),
            V3(0, 0, 0),
            V3(1, 0, 0),
            V3(0, 1, 0),
            V3(0, 0, 1),
            1.0,
            1.0,
            -1.0,
            1.0,
        )
    with assert_raises(contains="arcs must overlap"):
        _ = m.lens(
            "e",
            BoneId(0),
            V3(0, 0, 0),
            V3(1, 0, 0),
            V3(0, 1, 0),
            V3(0, 0, 1),
            1.0,
            -0.1,
            -1.0,
            1.0,
        )
    with assert_raises(contains="slab must not be empty"):
        _ = m.lens(
            "e",
            BoneId(0),
            V3(0, 0, 0),
            V3(1, 0, 0),
            V3(0, 1, 0),
            V3(0, 0, 1),
            1.0,
            0.5,
            1.0,
            1.0,
        )


def _square() -> List[Float64]:
    return [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, 1.0]


def test_outline_distance() raises:
    var square = _square()
    assert_almost_equal(outline_distance(square, 0, 4, 0.0, 0.0), -1.0)
    assert_almost_equal(outline_distance(square, 0, 4, 3.0, 0.0), 2.0)
    # The other winding gives the same answer.
    var turned: List[Float64] = [-1.0, 1.0, 1.0, 1.0, 1.0, -1.0, -1.0, -1.0]
    assert_almost_equal(outline_distance(turned, 0, 4, 0.0, 0.0), -1.0)


def test_fin_distance() raises:
    var m = SdfModel()
    _ = m.fin(
        "fin", BoneId(0), V3(0, 0, 0), V3(1, 0, 0), V3(0, 1, 0), _square(), 0.2
    )
    # Through the face, the distance is half the thickness away.
    assert_almost_equal(m.distance(0, V3(0, 0, 1)), 0.9, atol=1e-9)
    assert_almost_equal(m.distance(0, V3(0, 0, 0)), -0.1, atol=1e-9)
    assert_almost_equal(m.distance(0, V3(2, 0, 0)), 1.0, atol=1e-9)
    # A tapered fin with a sharper rim thins along u.
    _ = m.fin(
        "fin",
        BoneId(0),
        V3(0, 0, 0),
        V3(1, 0, 0),
        V3(0, 1, 0),
        _square(),
        0.2,
        round=0.01,
        grad_u=-0.05,
    )
    assert_true(m.distance(1, V3(0.8, 0, 0.09)) > 0.0)
    assert_equal(m.prims[1].r.y, 0.01)
    with assert_raises(contains="three or more points"):
        _ = m.fin(
            "f",
            BoneId(0),
            V3(0, 0, 0),
            V3(1, 0, 0),
            V3(0, 1, 0),
            [0.0, 0.0, 1.0, 1.0],
            0.2,
        )
    with assert_raises(contains="three or more points"):
        _ = m.fin(
            "f",
            BoneId(0),
            V3(0, 0, 0),
            V3(1, 0, 0),
            V3(0, 1, 0),
            [0.0, 0.0, 1.0, 1.0, 2.0, 0.0, 1.0],
            0.2,
        )
    with assert_raises(contains="thickness must be positive"):
        _ = m.fin(
            "f",
            BoneId(0),
            V3(0, 0, 0),
            V3(1, 0, 0),
            V3(0, 1, 0),
            _square(),
            0.0,
        )


def test_sculpt_refusals_and_tags() raises:
    var m = SdfModel()
    with assert_raises(contains="radii must be positive"):
        _ = m.ell("x", BoneId(0), V3(0, 0, 0), V3(0, 1, 1))
    with assert_raises(contains="bone must not be negative"):
        _ = m.sphere("x", BoneId(-1), V3(0, 0, 0), 1.0)
    with assert_raises(contains="Surface part"):
        _ = m.sphere("x", BoneId(0), V3(0, 0, 0), 1.0, part=SurfacePart(40))
    with assert_raises(contains="blend radius"):
        _ = m.sphere("x", BoneId(0), V3(0, 0, 0), 1.0, k=-0.1)
    _ = m.sphere("nose", BoneId(0), V3(0, 0, 0), 1.0)
    _ = m.sphere("nose", BoneId(0), V3(0, 0, 0), 1.0)
    _ = m.sphere("claw", BoneId(0), V3(0, 0, 0), 1.0)
    assert_equal(len(m.tags), 2)
    assert_equal(m.tag_name(TagId(1)), "claw")
    with assert_raises(contains="names no tag"):
        _ = m.tag_name(TagId(-1))
    with assert_raises(contains="names no tag"):
        _ = m.tag_name(TagId(2))


def test_field_blends_and_carves() raises:
    var m = SdfModel()
    assert_equal(m.eval_list(List[Int](), V3(0, 0, 0)), FAR)
    assert_equal(m.max_blend(), 0.0)
    _ = m.sphere("a", BoneId(0), V3(-0.5, 0, 0), 0.6, k=0.2)
    _ = m.sphere("b", BoneId(1), V3(0.5, 0, 0), 0.6, k=0.2)
    _ = m.sphere("hole", BoneId(0), V3(0, 1, 0), 0.5, k=0.1, carve=True)
    _ = m.sphere("jaw", BoneId(1), V3(0, -3, 0), 0.5, part=JAW)
    var body = m.part_list(BODY)
    assert_equal(len(body), 3)
    assert_equal(m.max_blend(), 0.2)
    # The blend fills the waist between the balls.
    var waist = m.eval_list([0, 1], V3(0, 0.2, 0))
    assert_true(
        waist < min(m.distance(0, V3(0, 0.2, 0)), m.distance(1, V3(0, 0.2, 0)))
    )
    # The carver cuts the top.
    assert_true(
        m.eval_list(body, V3(0, 0.55, 0)) > m.eval_list([0, 1], V3(0, 0.55, 0))
    )
    var g = m.gradient(body, V3(1.2, 0, 0), 1e-4)
    assert_almost_equal(g.x, 1.0, atol=1e-3)
    assert_equal(m.nearest(body, V3(0.9, 0, 0)), 1)
    assert_equal(m.nearest(List[Int](), V3(0.9, 0, 0)), -1)
    assert_equal(m.nearest([2], V3(0, 0, 0)), -1)
    var pair = m.nearest_pair_span(body, 0, 3, V3(0.4, 0, 0))
    assert_equal(pair[0], 1)
    assert_equal(pair[1], 0)
    var none = m.nearest_pair_span([2], 0, 1, V3(0, 0, 0))
    assert_equal(none[0], -1)
    # A cull far from the waist keeps only the ball there.
    var near = m.cull(body, V3(2, 0, 0), 0.01, 0.2)
    assert_equal(len(near), 1)
    assert_equal(len(m.cull(List[Int](), V3(0, 0, 0), 1.0, 0.0)), 0)
    # Near the carver, the cull keeps it.
    var top = m.cull(body, V3(0, 0.6, 0), 0.05, 0.2)
    assert_true(len(top) == 3)


def test_moved_model() raises:
    var m = SdfModel()
    _ = m.cone("arm", BoneId(1), V3(0, 0, 0), V3(0, 1, 0), 0.1, 0.1, k=0.0)
    var turns = List[Rigid]()
    turns.append(identity())
    turns.append(rotation_about(V3(0, 0, 0), V3(0, 0, 1), -pi / 2.0))
    var moved = m.moved(turns)
    _near(moved.prims[0].b, V3(1, 0, 0), 1e-12)
    var short = List[Rigid]()
    short.append(identity())
    with assert_raises(contains="has no transform"):
        _ = m.moved(short)
    assert_equal(len(SdfModel().moved(short).prims), 0)


def _assert_same_mesh(actual: SurfaceMesh, expected: SurfaceMesh) raises:
    assert_equal(len(actual.positions), len(expected.positions))
    assert_equal(len(actual.normals), len(expected.normals))
    assert_equal(len(actual.indices), len(expected.indices))
    for i in range(len(expected.positions)):
        assert_equal(actual.positions[i], expected.positions[i])
    for i in range(len(expected.normals)):
        assert_equal(actual.normals[i], expected.normals[i])
    for i in range(len(expected.indices)):
        assert_equal(actual.indices[i], expected.indices[i])


def test_blended_multiblock_mesh_is_bitwise_thread_deterministic() raises:
    var m = _ball()
    _ = m.sphere("blend", BoneId(0), V3(0.8, 0.2, 0.1), 0.7, k=0.3)
    var low = V3(-1, -1, -1)
    var high = V3(1.5, 1, 1)
    var cell = Length(0.25, METER)
    var serial = mesh_part(m, [0, 1], low, high, cell, block=2, workers=1)
    assert_true(len(serial.list_start) > 1)
    assert_true(serial.vertex_count() > 50)
    for workers in [2, 0]:
        var parallel = mesh_part(
            m, [0, 1], low, high, cell, block=2, workers=workers
        )
        _assert_same_mesh(parallel, serial)


def _check_shared_point(
    blocks: List[Int], point: SIMD[DType.int64, 4], owner: Int
) raises:
    var lt = Lattice(V3(0, 0, 0), 1.0, 2, 2, 2, 2)
    var grid = _Grid(lt)
    for b in blocks:
        grid.slot_of[b] = len(grid.active)
        grid.active.append(b)
        for _ in range(27):
            # Distinct signs make inconsistent ownership visible.
            grid.samples.append(Float32(b - 4))
    var expected = Float32(owner - 4)
    var gx = Int(point[0])
    var gy = Int(point[1])
    var gz = Int(point[2])
    assert_equal(grid.sample(gx, gy, gz), expected)
    _share_faces(grid)
    for slot in range(len(grid.active)):
        var b = grid.active[slot]
        var i = b % 2
        var j = (b // 2) % 2
        var k = b // 4
        var local = (gx - i * 2) + 3 * ((gy - j * 2) + 3 * (gz - k * 2))
        assert_equal(grid.samples[slot * 27 + local], expected)
    assert_equal(grid.sample(gx, gy, gz), expected)
    # Sharing a second time cannot change the selected value.
    _share_faces(grid)
    assert_equal(grid.sample(gx, gy, gz), expected)


def test_shared_edges_and_corners_use_one_active_fallback_owner() raises:
    _check_shared_point([6, 5, 3], SIMD[DType.int64, 4](2, 2, 2, 0), 3)
    _check_shared_point([3, 5, 6], SIMD[DType.int64, 4](2, 2, 2, 0), 3)
    _check_shared_point([2, 1], SIMD[DType.int64, 4](2, 2, 1, 0), 1)
    _check_shared_point([1, 2], SIMD[DType.int64, 4](2, 2, 1, 0), 1)
    # An active floor owner takes priority over every lower block.
    _check_shared_point([3, 5, 6, 7], SIMD[DType.int64, 4](2, 2, 2, 0), 7)
    _check_shared_point([7, 6, 5, 3], SIMD[DType.int64, 4](2, 2, 2, 0), 7)


def test_mesh_a_ball() raises:
    var m = _ball()
    var mesh = mesh_part(
        m, [0], V3(-1, -1, -1), V3(1, 1, 1), Length(0.25, METER), block=4
    )
    assert_true(mesh.vertex_count() > 50)
    # A closed surface has twice as many triangles as vertices, less two.
    assert_equal(len(mesh.indices) // 3, 2 * mesh.vertex_count() - 4)
    for v in range(mesh.vertex_count()):
        assert_almost_equal(length(mesh.vertex(v)), 1.0, atol=0.01)
        # Normals point out of the ball.
        assert_true(dot(mesh.normal(v), mesh.vertex(v)) > 0.95)
    # Two threads make the same mesh.
    var two = mesh_part(
        m,
        [0],
        V3(-1, -1, -1),
        V3(1, 1, 1),
        Length(0.25, METER),
        block=4,
        workers=2,
    )
    _assert_same_mesh(two, mesh)
    var all = mesh_part(
        m,
        [0],
        V3(-1, -1, -1),
        V3(1, 1, 1),
        Length(0.25, METER),
        block=4,
        workers=0,
    )
    _assert_same_mesh(all, mesh)


def _same_mesh(a: SurfaceMesh, b: SurfaceMesh) raises:
    assert_equal(len(a.positions), len(b.positions))
    assert_equal(len(a.normals), len(b.normals))
    assert_equal(len(a.indices), len(b.indices))
    for i in range(len(a.positions)):
        assert_equal(a.positions[i], b.positions[i])
        assert_equal(a.normals[i], b.normals[i])
    for i in range(len(a.indices)):
        assert_equal(a.indices[i], b.indices[i])


def test_any_worker_count_makes_the_same_mesh() raises:
    # Blended balls and a carver over many blocks: one, two and all
    # workers must agree to the bit.
    var m = SdfModel()
    _ = m.sphere("a", BoneId(0), V3(-0.3, 0, 0), 0.5, k=0.2)
    _ = m.sphere("b", BoneId(0), V3(0.35, 0.1, 0), 0.4, k=0.2)
    _ = m.sphere("c", BoneId(0), V3(0, 0.45, 0), 0.25, k=0.05, carve=True)
    var parts: List[Int] = [0, 1, 2]
    var lo = V3(-1, -1, -1)
    var hi = V3(1, 1, 1)
    var step = Length(0.05, METER)
    var one = mesh_part(m, parts, lo, hi, step, block=4, workers=1)
    assert_true(one.vertex_count() > 500)
    for workers in [2, 0]:
        _same_mesh(
            mesh_part(m, parts, lo, hi, step, block=4, workers=workers), one
        )


def test_shared_edge_points_agree_when_their_owner_is_asleep() raises:
    # Blocks of two cells, two by two. The edge at gx = gy = 2 belongs to
    # all four; its floor-division owner, block (1, 1), is not active.
    var grid = _Grid(Lattice(V3(0, 0, 0), 1.0, 2, 2, 2, 1))
    var per = 27
    for b in [1, 2]:  # blocks (1, 0) and (0, 1)
        grid.slot_of[b] = len(grid.active)
        grid.active.append(b)
        for _ in range(per):
            grid.samples.append(Float32(b))
    _share_faces(grid)
    for gz in range(3):
        var shared = grid.sample(2, 2, gz)
        var at10 = grid.samples[0 * per + 0 + 3 * (2 + 3 * gz)]
        var at01 = grid.samples[1 * per + 2 + 3 * (0 + 3 * gz)]
        assert_equal(at10, at01)
        assert_equal(at10, shared)
    # A point only one block holds keeps its own value.
    assert_equal(grid.sample(3, 0, 0), Float32(1))
    assert_equal(grid.sample(0, 3, 0), Float32(2))


def test_spill_wakes_the_blocks_a_thin_first_pass_misses() raises:
    # With no margin, the first pass wakes only the blocks whose corners
    # straddle the surface. The lattice's block faces lie at multiples of
    # 0.5 m, so this ball's cap bulges 5 cm past the face at x = 1 into a
    # block whose corners all lie 1.061 m from its center, outside it. The
    # cap crosses that face at a sample of the awake block beside it, so
    # the spill wakes the block and the cap is meshed. A cap that crosses
    # no awake face cannot be seen this way: that is what the usual
    # margin is for.
    var m = SdfModel()
    _ = m.sphere("ball", BoneId(0), V3(0, 0.25, 0.25), 1.05, k=0.0)
    var low = V3(-1, -1, -1)
    var high = V3(1.5, 1.5, 1.5)
    var cell = Length(0.25, METER)
    var usual = mesh_part(m, [0], low, high, cell, block=2)
    var thin = _mesh_part(m, [0], low, high, cell, 2, 1, 0.0)
    var cap = 0
    for v in range(thin.vertex_count()):
        cap += Int(thin.vertex(v).x > 1.0)
    assert_true(cap > 0)
    assert_true(thin.vertex_count() <= usual.vertex_count())


def test_mesh_winding_faces_out() raises:
    var m = _ball()
    var mesh = mesh_part(
        m, [0], V3(-1, -1, -1), V3(1, 1, 1), Length(0.3, METER), block=3
    )
    for t in range(0, len(mesh.indices), 3):
        var a = mesh.vertex(mesh.indices[t])
        var b = mesh.vertex(mesh.indices[t + 1])
        var c = mesh.vertex(mesh.indices[t + 2])
        var n = cross(b - a, c - a)
        assert_true(dot(n, a + b + c) > 0.0)


def test_mesh_empty_box_and_merge() raises:
    var m = _ball()
    # A box that holds no surface makes no vertices.
    var none = mesh_part(
        m, [0], V3(5, 5, 5), V3(6, 6, 6), Length(0.25, METER), block=4
    )
    assert_equal(none.vertex_count(), 0)
    var a = mesh_part(
        m, [0], V3(-1, -1, -1), V3(1, 1, 1), Length(0.4, METER), block=4
    )
    var count = a.vertex_count()
    var b = mesh_part(
        m, [0], V3(-1, -1, -1), V3(1, 1, 1), Length(0.4, METER), block=4
    )
    merge(a, b)
    assert_equal(a.vertex_count(), 2 * count)
    assert_equal(a.indices[len(b.indices)], b.indices[0] + count)
    assert_equal(len(a.list_start), 2 * len(b.list_start))


def test_mesh_refusals() raises:
    var m = _ball()
    check_cell(Length(0.1, METER), 6)
    with assert_raises(contains="positive and finite"):
        check_cell(Length(0.0, METER), 6)
    with assert_raises(contains="positive and finite"):
        check_cell(Length(1e6, METER), 6)
    with assert_raises(contains="from 2 to 16"):
        check_cell(Length(0.1, METER), 1)
    with assert_raises(contains="from 2 to 16"):
        check_cell(Length(0.1, METER), 17)
    with assert_raises(contains="must not be empty"):
        _ = mesh_part(m, [0], V3(0, 0, 0), V3(0, 1, 1), Length(0.1, METER))
    with assert_raises(contains="must not be empty"):
        _ = mesh_part(m, [0], V3(0, 0, 0), V3(1, 0, 1), Length(0.1, METER))
    with assert_raises(contains="must not be empty"):
        _ = mesh_part(m, [0], V3(0, 0, 0), V3(1, 1, 0), Length(0.1, METER))
    with assert_raises(contains="at least one primitive"):
        _ = mesh_part(
            m, List[Int](), V3(0, 0, 0), V3(1, 1, 1), Length(0.1, METER)
        )


def test_mesh_checks_part_indexes() raises:
    var model = _ball()
    var invalid: List[Int] = [-1, len(model.prims), Int.MAX]
    for index in invalid:
        with assert_raises(contains="index names no primitive"):
            _ = mesh_part(
                model,
                [0, index],
                V3(-1, -1, -1),
                V3(1, 1, 1),
                Length(0.4, METER),
            )
    # A repeated valid index keeps its existing meaning; it is not refused.
    var repeated = mesh_part(
        model, [0, 0], V3(-1, -1, -1), V3(1, 1, 1), Length(0.4, METER)
    )
    assert_true(repeated.vertex_count() > 0)


def test_mesh_refuses_nonfinite_bounds() raises:
    var model = _ball()
    var invalid: List[Float64] = [
        inf[DType.float64](),
        -inf[DType.float64](),
        nan[DType.float64](),
    ]
    for bad in invalid:
        var points: List[V3] = [V3(bad, 0, 0), V3(0, bad, 0), V3(0, 0, bad)]
        for point in points:
            with assert_raises(contains="finite coordinates"):
                _ = mesh_part(model, [0], point, V3(1, 1, 1), Length(1, METER))
            with assert_raises(contains="finite coordinates"):
                _ = mesh_part(
                    model, [0], V3(-1, -1, -1), point, Length(1, METER)
                )


def test_mesh_refuses_unrepresentable_cell_counts() raises:
    var model = _ball()
    with assert_raises(contains="cell count cannot fit"):
        _ = mesh_part(
            model,
            [0],
            V3(-1e308, 0, 0),
            V3(1e308, 1, 1),
            Length(1, METER),
        )
    with assert_raises(contains="cell count cannot fit"):
        _ = mesh_part(model, [0], V3(0, 0, 0), V3(1e20, 1, 1), Length(1, METER))
    with assert_raises(contains="cell count cannot fit"):
        _ = mesh_part(
            model, [0], V3(0, 0, 0), V3(1, 1, 1), Length(1e-30, METER)
        )
    with assert_raises(contains="cell count cannot fit"):
        _ = _blocks(Float64(Int.MAX), 1.0, 2)
    with assert_raises(contains="cell count cannot fit"):
        _ = _blocks(-1.0, 1.0, 2)
    assert_equal(_blocks(1.0, 1.0, 2), 3)


def test_mesh_checks_grid_products_before_allocation() raises:
    var model = _ball()
    with assert_raises(contains="addressable storage"):
        _ = mesh_part(
            model,
            [0],
            V3(0, 0, 0),
            V3(1e8, 1e8, 1e8),
            Length(1, METER),
            block=2,
        )
    # The corner count fits Int, but its Float64 allocation does not.
    with assert_raises(contains="addressable storage"):
        _check_grid_sizes(
            Lattice(V3(0, 0, 0), 1.0, 2, 1_000_000_000, 1_000_000_000, 1)
        )
    # Sparse storage does not remove the limit on linear fine-cell indexes.
    with assert_raises(contains="addressable storage"):
        _check_grid_sizes(Lattice(V3(0, 0, 0), 1.0, 16, 1 << 52, 1, 1))
    assert_equal(_checked_count(0, 8), 0)
    assert_equal(_checked_count(Int.MAX, 1), Int.MAX)
    assert_equal(_checked_count(Int.MAX // 8, 8), Int.MAX - 7)
    with assert_raises(contains="addressable storage"):
        _ = _checked_count(Int.MAX // 8 + 1, 8)
    with assert_raises(contains="nonnegative count"):
        _ = _checked_count(-1, 1)
    with assert_raises(contains="positive factor"):
        _ = _checked_count(0, 0)


def test_tube_of_single_spans() raises:
    var m = SdfModel()
    var points: List[V3] = [V3(0, 0, 0), V3(0, 0, 1), V3(0, 1, 1)]
    var radii: List[Float64] = [0.1, 0.08, 0.06]
    # With no cones per later span, only the first span is built.
    tube(m, "lip", BoneId(0), points, radii, V3(0, 2, 1), 0, 0.01)
    assert_equal(len(m.prims), 1)


def test_merge_an_empty_surface() raises:
    var m = _ball()
    var a = mesh_part(
        m, [0], V3(-1, -1, -1), V3(1, 1, 1), Length(0.4, METER), block=4
    )
    var count = a.vertex_count()
    merge(a, SurfaceMesh())
    assert_equal(a.vertex_count(), count)


def test_mesh_cut_by_its_box() raises:
    # A box smaller than the ball cuts the surface at the lattice's edge:
    # the cut leaves an open mesh, not a crash.
    var big = SdfModel()
    _ = big.sphere("ball", BoneId(0), V3(0, 0, 0), 1.0, k=0.0)
    var open = mesh_part(
        big,
        [0],
        V3(-0.9, -0.9, -0.9),
        V3(0.9, 0.9, 0.9),
        Length(0.25, METER),
        block=2,
    )
    assert_true(open.vertex_count() > 0)


def _spill_cylinder() raises -> SdfModel:
    # A narrow cylinder crosses each x face at its center sample only.
    # One active block wakes exactly one more block in each spill round.
    var model = SdfModel()
    _ = model.cone(
        "cylinder",
        BoneId(0),
        V3(0, 1, 1),
        V3(Float64(2 * (SPILL_ROUNDS + 1)), 1, 1),
        0.75,
        0.75,
        k=0.0,
    )
    return model^


def _spill_grid(model: SdfModel, blocks: Int) -> _Grid:
    var grid = _Grid(Lattice(V3(0, 0, 0), 1.0, 2, blocks, 1, 1))
    _wake(model, [0], grid, 0.0, 0, 0, 0)
    return grid^


def test_spill_budget_refuses_an_unsampled_frontier() raises:
    var model = _spill_cylinder()
    var grid = _spill_grid(model, SPILL_ROUNDS + 1)
    with assert_raises(contains="spill budget exhausted"):
        _sample_band(model, [0], grid, 0.0, 1)
    # The last wake added a block, but not its 27 samples. The old loop
    # continued into vertex numbering and read beyond this sample list.
    assert_equal(len(grid.active), SPILL_ROUNDS + 1)
    assert_equal(len(grid.samples), SPILL_ROUNDS * 27)
    assert_equal(len(grid.vertex_of), 0)


def test_spill_can_converge_on_the_last_round() raises:
    var model = _spill_cylinder()
    var one = _spill_grid(model, SPILL_ROUNDS)
    _sample_band(model, [0], one, 0.0, 1)
    assert_equal(len(one.active), SPILL_ROUNDS)
    assert_equal(len(one.samples), SPILL_ROUNDS * 27)
    # Every cell touches the center line and a positive corner. Numbering
    # all eight cells per block must preserve each vertex's block slot.
    var cells = List[Int]()
    var blocks = List[Int]()
    _number_vertices(one, cells, blocks)
    assert_equal(len(cells), SPILL_ROUNDS * 8)
    for v in range(len(blocks)):
        assert_equal(blocks[v], v // 8)
    var two = _spill_grid(model, SPILL_ROUNDS)
    _sample_band(model, [0], two, 0.0, 2)
    assert_equal(len(two.samples), len(one.samples))
    for i in range(len(one.samples)):
        assert_equal(two.samples[i], one.samples[i])


def _plane_grid() -> _Grid:
    # Two blocks of two cells a side along x; only the first is active. The
    # field is x - 1.5 cells, so the surface crosses the first block.
    var lattice = Lattice(V3(0, 0, 0), 1.0, 2, 2, 1, 1)
    var grid = _Grid(lattice)
    grid.slot_of[0] = 0
    grid.active.append(0)
    for n in range(27):
        grid.samples.append(Float32(n % 3) - 1.5)
    grid.vertex_of = List[Int](length=8, fill=-1)
    return grid^


def test_grid_lookups() raises:
    var grid = _plane_grid()
    # A point on the face between the blocks is read from the active one.
    assert_equal(grid.sample(2, 0, 0), Float32(0.5))
    assert_equal(grid.sample(1, 1, 1), Float32(-0.5))
    # Past the active block there is no sample, and no vertex.
    assert_equal(grid.sample(3, 0, 0), UNSAMPLED)
    assert_equal(grid.vertex(2, 0, 0), -1)
    assert_equal(grid.vertex(1, 0, 0), -1)


def test_faces_need_four_vertices() raises:
    var grid = _plane_grid()
    # Cells with x = 1 hold the surface. Give them vertices, but one.
    var mesh = SurfaceMesh()
    var cells = List[Int]()
    for gz in range(2):
        for gy in range(2):
            var v = len(cells)
            cells.append(1 + 4 * (gy + 2 * gz))
            mesh.positions.append(1.5)
            mesh.positions.append(Float32(gy) + 0.5)
            mesh.positions.append(Float32(gz) + 0.5)
            mesh.normals.append(1.0)
            mesh.normals.append(0.0)
            mesh.normals.append(0.0)
            grid.vertex_of[1 + 2 * (gy + 2 * gz)] = v
    _faces(grid, cells, mesh)
    assert_equal(len(mesh.indices), 6)
    grid.vertex_of[1 + 2 * (1 + 2 * 1)] = -1
    var fewer = SurfaceMesh()
    fewer.positions = mesh.positions.copy()
    fewer.normals = mesh.normals.copy()
    _faces(grid, cells, fewer)
    assert_equal(len(fewer.indices), 0)


def test_closed_form_distances() raises:
    # The almond of two unit circles offset by a half: its tips are at
    # the origin's sides, its rims a half above and below.
    assert_almost_equal(almond_distance(0.0, 0.0, 1.0, 0.5), -0.5)
    assert_almost_equal(almond_distance(0.0, 1.0, 1.0, 0.5), 0.5)
    assert_almost_equal(rect_distance(-0.2, -0.1), -0.1)
    assert_almost_equal(rect_distance(3.0, 4.0), 5.0)
    var a = V3(0, 0, 0)
    var b = V3(0, 0, 2)
    assert_almost_equal(segment_param(V3(1, 0, 1), a, b), 0.5)
    assert_almost_equal(segment_param(V3(1, 0, -3), a, b), 0.0)
    assert_almost_equal(segment_distance(V3(0, 3, 6), a, b), 5.0)
    assert_almost_equal(round_cone_estimate(V3(1, 0, 1), a, b, 0.2, 0.4), 0.7)
    var r = V3(1, 2, 3)
    assert_almost_equal(ellipsoid_estimate(V3(0, 4, 0), a, r), 1.0)
    assert_almost_equal(
        oriented_ellipsoid_estimate(
            V3(4, 0, 0), a, V3(0, 0, 1), V3(0, 1, 0), r
        ),
        3.0,
    )
    _near(on_side(V3(1, 2, 3), -1.0), V3(-1, 2, 3))


def test_cone_or_ball_takes_nested_ends() raises:
    var m = SdfModel()
    var bone = BoneId(0)
    _ = cone_or_ball(m, "a", bone, V3(0, 0, 0), V3(0, 0, 1), 0.2, 0.1, 0.0)
    assert_equal(m.prims[0].kind, CONE)
    # The small ball sits inside the big one: only the big ball is added.
    _ = cone_or_ball(m, "b", bone, V3(0, 0, 0), V3(0, 0, 0.1), 0.1, 0.5, 0.0)
    assert_equal(m.prims[1].kind, ELLIPSOID)
    _near(m.prims[1].c, V3(0, 0, 0.1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
