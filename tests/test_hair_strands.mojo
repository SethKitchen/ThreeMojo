# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the groom, its strand-space shading, and its strands in a
scene."""

from core.assets import Assets
from core.buffer_geometry import COLOR, POSITION
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import UNTONED
from extensions.humanoid.genome import Expression, Genome, HAIR_LENGTH
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.groom import (
    GroomField,
    GroomSpec,
    HairGroom,
    _Comb,
    _fringe_continues,
    _grow_guide,
    _stride_ok,
    groom_hair,
    groom_lines,
)
from extensions.humanoid.skeleton.head.hair.shading import (
    HairLight,
    HairLook,
    kajiya_kay,
    marschner,
    scattered,
    segment_colors,
    shade_groom,
)
from extensions.humanoid.skeleton.head.hair.strands import (
    _linear,
    add_groom,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length


def _person(length: Float32 = 0) raises -> HumanoidSpec:
    """Return a six-foot male with the hair `length` asks for."""
    return HumanoidSpec(
        Length(6.0, FOOT),
        MALE,
        UNTONED,
        Genome().with_gene(HAIR_LENGTH, Expression(length)),
    )


def test_a_groom_spec_refuses_bad_counts() raises:
    var dims = head_muscle_dimensions(_person())
    with assert_raises(contains="guides"):
        _ = GroomSpec(dims, 0)
    with assert_raises(contains="guides"):
        _ = GroomSpec(dims, 20001)
    with assert_raises(contains="followers"):
        _ = GroomSpec(dims, 10, -1)
    with assert_raises(contains="followers"):
        _ = GroomSpec(dims, 10, 65)
    # Longer hair grows longer strands.
    var long = GroomSpec(head_muscle_dimensions(_person(0.9)))
    assert_true(long.longest > GroomSpec(dims).longest)


def test_a_groom_grows_guides_and_followers() raises:
    var dims = head_muscle_dimensions(_person(0.6))
    var groom = groom_hair(dims, GroomSpec(dims, 120, 2))
    # Each guide found a root is followed by its two followers.
    assert_true(len(groom) > 60)
    assert_equal(len(groom) % 3, 0)
    assert_equal(len(groom.points), len(groom.normals))
    assert_equal(len(groom.points), len(groom.depths))
    assert_equal(len(groom.shades), len(groom))
    var field = GroomField(dims)
    var crown = dims.head.at(0, 76.0, -1.0)
    for strand in range(len(groom)):  # pragma: no branch
        var first = groom.starts[strand]
        var last = groom.starts[strand + 1] - 1
        # Every strand has at least a root, a middle and a tip.
        assert_true(last - first >= 2)
        # It grows from on the head and never through its middle.
        assert_true(abs(field.distance(groom.points[first])) < 0.01)
        assert_true((groom.points[first] - crown).length() > 0.03)
        assert_true(groom.depths[first] >= 0)
        # Its tangent runs along it.
        assert_true(abs(groom.tangent(first).length() - 1) < 1e-3)
    # A guide rooted deep in the head: its first step leaps out onto the
    # hair, far past a stride, and the guide stops there.
    var points = List[Vector3]()
    var normals = List[Vector3]()
    var levels = List[Float32]()
    _grow_guide(
        field,
        GroomSpec(dims, 4, 0),
        _Comb(crown, 0.25, 0, 1),
        crown,
        0,
        1,
        crown.z + 1,
        dims.head.cm(0.08),
        points,
        normals,
        levels,
    )
    assert_equal(len(points), 1)


def test_a_groom_with_no_roots_is_refused() raises:
    var dims = head_muscle_dimensions(_person())
    var spec = GroomSpec(dims, 4, 0)
    spec.root_tries = 0
    with assert_raises(contains="root"):
        _ = groom_hair(dims, spec)
    # Guides too short to be strands are left out too.
    var stubby = GroomSpec(dims, 4, 0)
    stubby.shortest = stubby.step * 0.1
    stubby.longest = stubby.step * 0.1
    with assert_raises(contains="root"):
        _ = groom_hair(dims, stubby)


def test_the_groom_rules() raises:
    assert_true(_stride_ok(1.0, 1.0))
    assert_false(_stride_ok(0.1, 1.0))
    assert_false(_stride_ok(2.5, 1.0))
    assert_true(_fringe_continues(True, 0.5, 1.0, 2.0, 1.0))
    assert_false(_fringe_continues(False, 0.5, 1.0, 2.0, 1.0))
    assert_false(_fringe_continues(True, 1.5, 1.0, 2.0, 1.0))
    assert_false(_fringe_continues(True, 0.5, 1.0, 0.5, 1.0))
    # Straight off the hair the comb gives no direction.
    var comb = _Comb(Vector3(0, 0, 0), 0, 0, 1)
    var stuck = comb.direction(Vector3(0, 1, 0), Vector3(0, 1, 0), 0, 0)
    assert_equal(stuck.length(), 0)
    var along = comb.direction(Vector3(0, 1, 0), Vector3(0, 0, 1), 0, 0)
    assert_true(abs(along.length() - 1) < 1e-4)


def test_a_groom_holds_its_strands() raises:
    var groom = HairGroom()
    assert_equal(len(groom), 0)
    with assert_raises(contains="no strands"):
        _ = groom_lines(groom)
    var points: List[Vector3] = [Vector3(0, 0, 0)]
    var ups: List[Vector3] = [Vector3(0, 1, 0)]
    var deep: List[Float32] = [0.0]
    groom.add(points, ups, deep, 1.0)
    # A strand of one point has no direction: it points down.
    assert_equal(groom.tangent(0).y, -1)
    var more: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(0, -0.01, 0),
        Vector3(0, -0.02, 0),
    ]
    var up3: List[Vector3] = [
        Vector3(0, 0, 1),
        Vector3(0, 0, 1),
        Vector3(0, 0, 1),
    ]
    var deep3: List[Float32] = [0.0, 0.001, 0.002]
    groom.add(more, up3, deep3, 1.0)
    assert_equal(len(groom), 2)
    assert_true(groom.tangent(2).y < -0.99)
    # Two segments, two ends each.
    var lines = groom_lines(groom)
    assert_equal(lines.attribute_view(String(POSITION)).count(), 4)


def test_marschner_has_its_highlights() raises:
    var look = HairLook(Vector3(0.3, 0.1, 0.05))
    var tangent = Vector3(0, 1, 0)
    var eye = Vector3(0, 0, 1)
    # The R highlight: the light mirrored about the strand's normal
    # plane, near the camera, reflects white.
    var mirror = marschner(look, Vector3(0, 0, 1), eye, tangent)
    var aside = marschner(look, Vector3(0, 0.9, 0.44), eye, tangent)
    assert_true(mirror.x > aside.x)
    # TT lights the hair from behind, in its own color.
    look.weight_tt = 1.0
    var through = marschner(look, Vector3(0, 0, -1), eye, tangent)
    assert_true(through.x > through.z)
    # Kajiya-Kay: brightest square to the strand, dim along it.
    var square = kajiya_kay(look.color, Vector3(0, 0, 1), tangent)
    var along = kajiya_kay(look.color, tangent, tangent)
    assert_true(square.x > along.x)
    # The fake multiple scattering is lit from the camera's side.
    var lit = scattered(look.color, Vector3(0, 0, 1), eye, tangent)
    var dark = scattered(look.color, Vector3(0, 0, -1), eye, tangent)
    assert_true(lit.x > dark.x)
    # Looking straight along the strand it still returns a color.
    var end_on = scattered(look.color, Vector3(0, 0, 1), tangent, tangent)
    assert_true(end_on.x > 0)


def test_shading_a_groom() raises:
    var groom = HairGroom()
    var points: List[Vector3] = [Vector3(0, 0, 0), Vector3(0, -0.01, 0)]
    var ups: List[Vector3] = [Vector3(0, 0, 1), Vector3(0, 0, 1)]
    var shallow: List[Float32] = [0.0, 0.0]
    var deep: List[Float32] = [0.01, 0.01]
    groom.add(points, ups, shallow, 1.0)
    groom.add(points, ups, deep, 1.0)
    var lights: List[HairLight] = [
        HairLight(Vector3(0, 0, 1), Vector3(2, 2, 2))
    ]
    var look = HairLook(Vector3(0.3, 0.1, 0.05))
    var colors = shade_groom(
        groom, look, lights, Vector3(0, 0, 1), Vector3(0.1, 0.1, 0.1)
    )
    assert_equal(len(colors), 12)
    # The strand under a centimeter of hair is darker.
    assert_true(colors[6] < colors[0])
    # Reds stay redder than blues.
    assert_true(colors[0] > colors[2])
    # A light behind the head leaves only the shadow's floor and the
    # ambient.
    var behind: List[HairLight] = [
        HairLight(Vector3(0, 0, -1), Vector3(2, 2, 2))
    ]
    var back = shade_groom(
        groom, look, behind, Vector3(0, 0, 1), Vector3(0, 0, 0)
    )
    assert_true(back[0] < colors[0])
    # Laid out as the lines lay their points out: one segment, two ends,
    # for each of the two strands.
    assert_equal(len(segment_colors(groom, colors)), 12)


def test_strands_in_a_scene() raises:
    assert_true(abs(_linear(10) - 10.0 / 255 / 12.92) < 1e-6)
    assert_true(abs(_linear(255) - 1) < 1e-4)
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var hair = add_groom(scene, assets, root, _person(), 40, 1)
    assert_equal(len(scene.wide_lines), 1)
    ref lines = assets.geometries.get(hair.geometry)
    var count = lines.attribute_view(String(POSITION)).count()
    assert_equal(lines.attribute_view(String(COLOR)).count(), count)
    var lights: List[HairLight] = [
        HairLight(Vector3(0, 1, 0), Vector3(1, 1, 1))
    ]
    hair.shade(assets, lights, Vector3(0, 2, 0), Vector3(0, 0, 0))
    ref again = assets.geometries.get(hair.geometry)
    assert_equal(again.attribute_view(String(COLOR)).count(), count)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
