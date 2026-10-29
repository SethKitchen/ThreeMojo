# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for garments made elsewhere, bound to one body and fitted to
another."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from extensions.attire.binding import (
    SKIN_CELL,
    Binding,
    SkinIndex,
    bind_garment,
    fit_garment,
    wear_fitted,
)
from extensions.attire.fabric import fabric_material
from extensions.attire.kinds import WOOL
from extensions.humanoid.genome import SHOULDER_BREADTH, Expression, Genome
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.rig.joints import HIPS
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from render.framebuffer import Color
from renderers.renderer import available_workers
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import empty_mesh, line_rig, strip
from tests._attire_people import coarse_person
from units.si import INCH, Length


def _lifted(var mesh: BufferGeometry, z: Float32) raises -> BufferGeometry:
    """Return `mesh` moved `z` meters along +z."""
    var places = mesh.clone_attribute(String(POSITION))
    for v in range(places.count()):
        places.set_component(v, 2, places.component(v, 2) + z)
    mesh.set_attribute(String(POSITION), places^)
    return mesh^


def test_the_nearest_point_of_a_skin_is_found() raises:
    var skin = strip(0, 4, HIPS)
    var index = SkinIndex(skin)
    var above = index.nearest(Vector3(0.1, -0.3, 0.05))
    assert_almost_equal(above.point.x, 0.1, atol=1e-5)
    assert_almost_equal(above.point.y, -0.3, atol=1e-5)
    assert_almost_equal(above.point.z, 0, atol=1e-5)
    var total = above.weights.x + above.weights.y + above.weights.z
    assert_almost_equal(total, 1, atol=1e-5)
    # From far off the grid, the search widens until it finds the skin.
    var far = index.nearest(Vector3(3, 0.5, 0))
    assert_almost_equal(far.point.x, 0.5, atol=1e-5)
    assert_almost_equal(far.point.y, 0, atol=1e-5)
    # Off the grid on the low side as well.
    var low = index.nearest(Vector3(-2, -3, -1))
    assert_almost_equal(low.point.y, -1, atol=1e-5)
    assert_true(SKIN_CELL > 0)


def test_degenerate_triangles_are_left_out() raises:
    var skin = BufferGeometry()
    skin.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(0), 0, 0, 1, 0, 0, 2, 0, 0, 0, 1, 0], 3),
    )
    skin.set_index([0, 1, 2, 0, 1, 3])
    var index = SkinIndex(skin)
    assert_equal(len(index.triangles), 1)
    var flat = BufferGeometry()
    flat.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(0), 0, 0, 1, 0, 0, 2, 0, 0], 3),
    )
    with assert_raises(contains="needs a triangle"):
        _ = SkinIndex(flat)


def test_a_garment_is_bound_and_fitted_through_the_rig() raises:
    var rig = line_rig()
    var skin = strip(0, 4, HIPS)
    var coat = _lifted(strip(0, 4, HIPS), 0.02)
    var binding = bind_garment(coat, skin, rig)
    assert_equal(binding.count(), 10)
    assert_equal(binding.joints[3], HIPS)
    assert_almost_equal(binding.offsets[3], 0.02, atol=1e-6)
    # A rig half as tall: the place from the hips halves, the offset holds.
    var small = line_rig()
    small.stature = rig.stature / 2
    var fitted = fit_garment(binding, coat, skin, small)
    ref placed = fitted.attribute_view(String(POSITION))
    assert_almost_equal(placed.vector3(9).y, -0.5, atol=1e-5)
    assert_almost_equal(placed.vector3(9).z, 0.02, atol=1e-5)
    assert_equal(
        Int(fitted.attribute_view(String(SKIN_INDEX)).component(0, 0)),
        HIPS.value,
    )
    assert_almost_equal(
        fitted.attribute_view(String(SKIN_WEIGHT)).component(0, 0), 1
    )
    with assert_raises(contains="one entry per vertex"):
        _ = fit_garment(Binding(), coat, skin, small)


def test_a_normal_that_cancels_falls_back_to_a_corner() raises:
    var skin = strip(0, 1, HIPS)
    var normals = skin.clone_attribute(String(NORMAL))
    normals.set_component(1, 2, -1)
    skin.set_attribute(String(NORMAL), normals^)
    # The midpoint of the first edge mixes +z and -z equally.
    var coat = BufferGeometry()
    coat.set_attribute(
        String(POSITION), BufferAttribute([Float32(0), 0, 0.01], 3)
    )
    var binding = bind_garment(coat, skin, line_rig())
    assert_almost_equal(abs(binding.offsets[0]), 0.01, atol=1e-6)


def test_a_bone_the_rig_does_not_have_is_refused() raises:
    var skin = strip(0, 1, HIPS)
    var bones = skin.clone_attribute(String(SKIN_INDEX))
    bones.set_component(0, 0, 99)
    bones.set_component(1, 0, -1)
    bones.set_component(2, 0, 99)
    bones.set_component(3, 0, -1)
    skin.set_attribute(String(SKIN_INDEX), bones^)
    with assert_raises(contains="bone the rig does not have"):
        _ = bind_garment(_lifted(strip(0, 1, HIPS), 0.01), skin, line_rig())
    # A bone below zero is refused too.
    var below = strip(0, 1, HIPS)
    var negative = below.clone_attribute(String(SKIN_INDEX))
    for v in range(4):
        negative.set_component(v, 0, -1)
    below.set_attribute(String(SKIN_INDEX), negative^)
    with assert_raises(contains="bone the rig does not have"):
        _ = bind_garment(_lifted(strip(0, 1, HIPS), 0.01), below, line_rig())


def test_an_empty_garment_binds_and_fits_as_nothing() raises:
    var skin = strip(0, 2, HIPS)
    var rig = line_rig()
    var binding = bind_garment(empty_mesh(), skin, rig)
    assert_equal(binding.count(), 0)
    var fitted = fit_garment(binding, empty_mesh(), skin, rig)
    assert_equal(fitted.vertex_count(), 0)
    with assert_raises(contains="needs a triangle"):
        _ = SkinIndex(empty_mesh())


def test_a_garment_from_one_body_fits_another() raises:
    var scene = Scene()
    var assets = Assets()
    var maker = coarse_person(scene, assets)
    var root = scene.add(Object3D())
    var genome = Genome().with_gene(SHOULDER_BREADTH, Expression(0.8))
    var wearer = add_game_humanoid(
        scene,
        assets,
        root,
        HumanoidSpec(Length(64, INCH), FEMALE, genome=genome),
        3000,
        12,
        8,
        8,
        workers=available_workers(),
    )
    ref first = assets.geometries.get(
        scene.skinned_meshes[maker.skins[0]].geometry
    )
    ref second = assets.geometries.get(
        scene.skinned_meshes[wearer.skins[0]].geometry
    )
    # The garment: the maker's skin, one centimeter out.
    var coat = first.clone()
    var places = coat.clone_attribute(String(POSITION))
    ref normals = first.attribute_view(String(NORMAL))
    for v in range(places.count()):
        var p = places.vector3(v) + normals.vector3(v) * 0.01
        places.set_component(v, 0, p.x)
        places.set_component(v, 1, p.y)
        places.set_component(v, 2, p.z)
    coat.set_attribute(String(POSITION), places^)
    var binding = bind_garment(coat, first, maker.rig)
    var fitted = fit_garment(binding, coat, second, wearer.rig)
    # Every vertex stands about a centimeter off the wearer's skin.
    var index = SkinIndex(second)
    ref moved = fitted.attribute_view(String(POSITION))
    var total = Float32(0)
    for v in range(moved.count()):
        var p = moved.vector3(v)
        total += (index.nearest(p).point - p).length()
    var mean = total / Float32(moved.count())
    assert_true(mean > 0.006 and mean < 0.012)
    # And the fitted coat is shorter than the one it was made as.
    var top = Float32(-1e9)
    var top_made = Float32(-1e9)
    ref made = coat.attribute_view(String(POSITION))
    for v in range(moved.count()):
        top = max(top, moved.vector3(v).y)
        top_made = max(top_made, made.vector3(v).y)
    assert_true(top < top_made)
    var look = assets.materials.add(fabric_material(WOOL, Color(80, 60, 40)))
    var at = wear_fitted(scene, assets, wearer, fitted^, look)
    assert_equal(at, len(scene.skinned_meshes) - 1)
    assert_equal(scene.skinned_meshes[at].node, wearer.root)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
