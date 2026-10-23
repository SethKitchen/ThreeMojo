# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The meadow's trees, its sky, and the scene that holds them."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import CUBE_BACKGROUND
from core.buffer_geometry import COLOR, NORMAL, POSITION
from core.fog import EXP2_FOG
from core.scene import Scene
from extensions.vegetation.crown import (
    CrownLevel,
    CrownParameters,
    bush_parameters,
    crown_level_for,
    default_crown_levels,
    leafy_tree,
)
from extensions.vegetation.field import LodBand
from extensions.vegetation.ground import Ground
from extensions.vegetation.meadow import (
    EXPOSURE,
    EYE_HEIGHT,
    Meadow,
    MeadowParameters,
    meadow_camera,
    meadow_renderer,
    sun_direction,
    two_sided_program,
)
from extensions.vegetation.sky import SkyDome, SkyLook, cloud_density, paint_sky
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.nodes import NORMAL_NODE, POSITION_NODE
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.cube_texture import FACE_COUNT, face_direction
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, RADIAN, SECOND, Angle, Duration, Length


def _sapling() -> CrownParameters:
    """Return a small tree: a trunk and one level of branches."""
    var crown = CrownParameters()
    crown.tree.levels = 2
    crown.tree.children = [5]
    crown.tree.trunk_length = Length(3.0, METER)
    crown.tree.trunk_radius = Length(0.1, METER)
    crown.tree.section_length = Length(0.5, METER)
    crown.twig_radius = Length(0.05, METER)
    crown.leaves_per_ring = 6
    return crown^


def _meadow_parameters(crowded: Bool) raises -> MeadowParameters:
    """Return a meadow small enough to build in a test. A crowded meadow
    has trees, a bush, a lone tree and a boulder; an empty one has none."""
    var p = MeadowParameters()
    p.field.span = Length(16.0, METER)
    p.field.cluster_size = Length(4.0, METER)
    p.field.density = 10
    p.field.bands = [LodBand(Length(60.0, METER), 0.001, 1)]
    p.ground = Ground(seed=11)
    p.crown = _sapling()
    p.bush = _sapling()
    p.tree_kinds = 1
    p.crown_levels = [
        CrownLevel(Length(20.0, METER), 1.0),
        CrownLevel(Length(1.0e5, METER), 0.5),
    ]
    p.ground_span = Length(60.0, METER)
    p.ground_cells = 4
    p.mountain_radius = Length(100.0, METER)
    p.sky_size = 8
    p.trees = 0
    p.bushes = 0
    p.rocks = 0
    p.solitary = List[Vector2]()
    if crowded:
        p.trees = 2
        p.bushes = 1
        p.rocks = 1
        p.solitary = [Vector2(2.0, -3.0)]
        p.treeline_near = Length(10.0, METER)
        p.treeline_far = Length(40.0, METER)
        p.treeline_width = Length(30.0, METER)
    return p^


def _refused(var p: MeadowParameters, text: String) raises:
    """Assert that the meadow is refused with `text`."""
    with assert_raises(contains=text):
        p.check()


def test_crown_parameters_are_checked() raises:
    """The default tree and bush pass; each leaf field out of range is
    refused, and so is a tree the generator refuses."""
    CrownParameters().check()
    bush_parameters().check()
    var c = CrownParameters()
    c.tree.levels = 0
    with assert_raises():
        c.check()
    c = CrownParameters()
    c.twig_radius = Length(0.0, METER)
    with assert_raises(contains="twig"):
        c.check()
    c = CrownParameters()
    c.leaves_per_ring = 0
    with assert_raises(contains="ring"):
        c.check()
    c = CrownParameters()
    c.spread = Length(11.0, METER)
    with assert_raises(contains="spread"):
        c.check()
    c = CrownParameters()
    c.leaf_length = Length(3.0, METER)
    with assert_raises(contains="long"):
        c.check()
    c = CrownParameters()
    c.leaf_width = Length(0.0, METER)
    with assert_raises(contains="wide"):
        c.check()


def test_crown_levels_pick_by_distance() raises:
    """The first level whose reach holds a distance is picked, and the
    last past every reach. No level is refused."""
    var levels = default_crown_levels()
    for index in range(len(levels)):
        levels[index].check()
    assert_equal(crown_level_for(levels, 10), 0)
    assert_equal(crown_level_for(levels, 45), 1)
    assert_equal(crown_level_for(levels, 2.0e5), 2)
    with assert_raises(contains="no level"):
        _ = crown_level_for(List[CrownLevel](), 1)
    with assert_raises(contains="reach"):
        CrownLevel(Length(-1.0, METER), 1.0).check()
    with assert_raises(contains="detail"):
        CrownLevel(Length(1.0, METER), 0.0).check()


def test_a_leafy_tree_has_cards_that_face_out() raises:
    """Each leaf is four vertices and two triangles. Its normal is of unit
    length and points away from the crown's center more than toward it."""
    var tree = leafy_tree(_sapling(), 1.0)
    assert_true(tree.leaf_count > 10)
    assert_equal(tree.leaves.vertex_count(), 4 * tree.leaf_count)
    assert_equal(len(tree.leaves.index), 6 * tree.leaf_count)
    assert_true(tree.wood.has_attribute(String(COLOR)))
    ref p = tree.leaves.attribute_view(String(POSITION))
    ref n = tree.leaves.attribute_view(String(NORMAL))
    var outward = 0
    for leaf in range(tree.leaf_count):
        var normal = n.vector3(4 * leaf)
        assert_almost_equal(normal.length(), 1, atol=1e-4)
        var middle = (p.vector3(4 * leaf) + p.vector3(4 * leaf + 2)) * 0.5
        if (middle - tree.crown_center).dot(normal) > 0:
            outward += 1
    assert_true(outward * 10 > tree.leaf_count * 9)
    assert_true(tree.crown_radius > 0)


def test_a_thin_crown_keeps_fewer_larger_leaves_on_lean_wood() raises:
    """A quarter of the detail keeps about a quarter of the leaves, each
    twice as long. Lean wood has fewer vertices."""
    var full = leafy_tree(_sapling(), 1.0)
    var thin = leafy_tree(_sapling(), 0.25, lean_wood=True)
    assert_true(thin.leaf_count < full.leaf_count // 2)
    assert_true(thin.leaf_count > 0)
    assert_true(thin.wood.vertex_count() < full.wood.vertex_count())
    ref a = full.leaves.attribute_view(String(POSITION))
    ref b = thin.leaves.attribute_view(String(POSITION))
    var long_full = (a.vector3(2) - a.vector3(0)).length()
    var long_thin = (b.vector3(2) - b.vector3(0)).length()
    assert_almost_equal(long_thin, long_full * 2, atol=1e-4)


def test_a_crown_with_no_leaf_is_refused() raises:
    """A detail out of range, a tree with no twig thin enough, and a
    detail that keeps no leaf are refused."""
    with assert_raises(contains="detail"):
        _ = leafy_tree(_sapling(), 0.0)
    var bare = _sapling()
    bare.twig_radius = Length(0.001, METER)
    with assert_raises(contains="no twig"):
        _ = leafy_tree(bare, 1.0)
    var sparse = _sapling()
    sparse.tree.levels = 1
    sparse.twig_radius = Length(1.0, METER)
    sparse.leaves_per_ring = 1
    with assert_raises(contains="keeps no leaf"):
        _ = leafy_tree(sparse, 0.01)


def test_a_sky_look_is_checked() raises:
    """The default sky passes; each field out of range is refused."""
    SkyLook().check()
    var look = SkyLook()
    look.turbidity = 0
    with assert_raises(contains="turbidity"):
        look.check()
    look = SkyLook()
    look.rayleigh = 5
    with assert_raises(contains="rayleigh"):
        look.check()
    look = SkyLook()
    look.gain = -1
    with assert_raises(contains="gain"):
        look.check()
    look = SkyLook()
    look.saturation = 5
    with assert_raises(contains="saturation"):
        look.check()
    look = SkyLook()
    look.tint = Vector3(5, 1, 1)
    with assert_raises(contains="tint"):
        look.check()
    look = SkyLook()
    look.tint = Vector3(1, -1, 1)
    with assert_raises(contains="tint"):
        look.check()
    look = SkyLook()
    look.tint = Vector3(1, 1, 9)
    with assert_raises(contains="tint"):
        look.check()
    look = SkyLook()
    look.cloud_cover = 2
    with assert_raises(contains="cover"):
        look.check()
    look = SkyLook()
    look.cloud_scale = 0
    with assert_raises(contains="scale"):
        look.check()


def test_clouds_stay_above_the_horizon() raises:
    """No cloud lies at or below the horizon. No cover is a clear sky,
    and full cover is cloud overhead."""
    var look = SkyLook()
    assert_equal(cloud_density(Vector3(1, 0, 0), look), 0)
    assert_equal(cloud_density(Vector3(0.6, -0.8, 0), look), 0)
    look.cloud_cover = 0
    assert_equal(cloud_density(Vector3(0, 1, 0), look), 0)
    look.cloud_cover = 1
    assert_almost_equal(cloud_density(Vector3(0, 1, 0), look), 1, atol=1e-4)


def test_paint_sky_fills_a_cube_and_holds_the_haze_below() raises:
    """The painted cube is in the store. Every texel below the horizon is
    the haze, and the haze is a bright, bluish color."""
    var renderer = Renderer(8, 8)
    var assets = Assets()
    var sun = sun_direction(Angle(40.0, DEGREE), Angle(20.0, DEGREE))
    var dome = paint_sky(renderer, assets, sun, SkyLook(), 8)
    ref cube = assets.cube_textures.get(dome.cube)
    assert_equal(cube.size, 8)
    assert_true(dome.horizon.z > dome.horizon.x)
    for face in range(FACE_COUNT):
        ref data = cube.faces[face].data
        for y in range(8):
            for x in range(8):
                if face_direction(face, x, y, 8).y <= 0:
                    assert_almost_equal(
                        data[(y * 8 + x) * 4 + 2], dome.horizon.z
                    )
    var haze = dome.haze()
    assert_true(haze.b > haze.r)
    var bright = SkyDome(dome.cube, Vector3(3, -1, 0.5))
    assert_equal(Int(bright.haze().r), 255)
    assert_equal(Int(bright.haze().g), 0)
    with assert_raises(contains="texels"):
        _ = paint_sky(renderer, assets, sun, SkyLook(), 4)
    with assert_raises(contains="horizon"):
        _ = paint_sky(renderer, assets, Vector3(1, 0, 0), SkyLook(), 8)
    var dull = SkyLook()
    dull.gain = -1
    with assert_raises(contains="gain"):
        _ = paint_sky(renderer, assets, sun, dull, 8)


def test_the_light_helpers() raises:
    """The two-sided program sets the normal and nothing else. The sun's
    direction is of unit length at its elevation. The renderer and the
    camera are set up for the meadow."""
    var program = two_sided_program()
    assert_true(program.has(NORMAL_NODE))
    assert_false(program.has(POSITION_NODE))
    var sun = sun_direction(Angle(30.0, DEGREE), Angle(90.0, DEGREE))
    assert_almost_equal(sun.length(), 1, atol=1e-6)
    assert_almost_equal(sun.y, 0.5, atol=1e-6)
    assert_almost_equal(sun.z, 0.8660254, atol=1e-6)
    var renderer = meadow_renderer(16, 9)
    assert_true(renderer.tone_mapping == ACES_FILMIC_TONE_MAPPING)
    assert_equal(renderer.tone_mapping_exposure, EXPOSURE)
    assert_true(renderer.shadow_map_type == PCF_SOFT_SHADOW_MAP)
    assert_true(renderer.antialias)
    var p = MeadowParameters()
    var camera = meadow_camera(p, 16, 9, Length(2.0, METER))
    assert_almost_equal(camera.position.z, 20, atol=1e-5)
    assert_almost_equal(
        camera.position.y, p.ground.height_at(2, 20) + EYE_HEIGHT, atol=1e-5
    )


def test_each_meadow_parameter_is_refused_out_of_range() raises:
    """Each meadow parameter outside its range is refused, and a part
    that its own check refuses is refused too."""
    MeadowParameters().check()
    var p = MeadowParameters()
    p.field.density = 0
    _refused(p^, "blades a square meter")
    p = MeadowParameters()
    p.ground.climb = 4
    _refused(p^, "climb")
    p = MeadowParameters()
    p.wind.calm = 4
    _refused(p^, "calm")
    p = MeadowParameters()
    p.crown.leaves_per_ring = 0
    _refused(p^, "ring")
    p = MeadowParameters()
    p.bush.spread = Length(20.0, METER)
    _refused(p^, "spread")
    p = MeadowParameters()
    p.sky.gain = -2
    _refused(p^, "gain")
    p = MeadowParameters()
    p.tree_kinds = 0
    _refused(p^, "tree kinds")
    p = MeadowParameters()
    p.trees = -1
    _refused(p^, "trees")
    p = MeadowParameters()
    p.bushes = 20000
    _refused(p^, "bushes")
    p = MeadowParameters()
    for _ in range(1001):
        p.solitary.append(Vector2(0, 0))
    _refused(p^, "lone trees")
    p = MeadowParameters()
    p.solitary = [Vector2(2.0e4, 0)]
    _refused(p^, "within 10 kilometers")
    p = MeadowParameters()
    p.solitary = [Vector2(0, -2.0e4)]
    _refused(p^, "within 10 kilometers")
    p = MeadowParameters()
    p.rocks = 1001
    _refused(p^, "boulders")
    p = MeadowParameters()
    p.treeline_near = Length(-1.0, METER)
    _refused(p^, "start")
    p = MeadowParameters()
    p.treeline_far = p.treeline_near
    _refused(p^, "end past")
    p = MeadowParameters()
    p.treeline_width = Length(-1.0, METER)
    _refused(p^, "wide")
    p = MeadowParameters()
    p.crown_levels = List[CrownLevel]()
    _refused(p^, "levels")
    p = MeadowParameters()
    p.crown_levels[0].detail = 2
    _refused(p^, "detail")
    p = MeadowParameters()
    p.sun_elevation = Angle(0.0, DEGREE)
    _refused(p^, "degrees high")
    p = MeadowParameters()
    p.sun_azimuth = Angle(2.0e6, RADIAN)
    _refused(p^, "way round")
    p = MeadowParameters()
    p.ground_span = Length(5.0, METER)
    _refused(p^, "ground must be")
    p = MeadowParameters()
    p.mountain_radius = Length(5.0, METER)
    _refused(p^, "mountains")


def test_an_empty_meadow_draws_its_grass_and_sky() raises:
    """A meadow with no tree, bush or boulder still has its ground,
    mountains, sky, sun, fog and grass. Its frame draws clusters near the
    camera and leaves the far ones to the ground."""
    var renderer = Renderer(16, 9)
    var assets = Assets()
    var scene = Scene()
    var p = _meadow_parameters(False)
    var meadow = Meadow(scene, assets, renderer, p)
    assert_equal(len(meadow.trees), 0)
    assert_true(scene.background.kind == CUBE_BACKGROUND)
    assert_true(scene.fog.kind == EXP2_FOG)
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE),
        16.0 / 9.0,
        Length(0.1, METER),
        Length(300.0, METER),
    )
    camera.place(Vector3(0, 30, 0.1), Vector3(0, 0, 0))
    var stats = meadow.update(scene, assets, camera, Duration(1.0, SECOND))
    assert_equal(stats.clusters, 16)
    assert_equal(stats.drawn, 16)
    assert_true(stats.empty > 0)
    assert_true(stats.empty < 16)
    assert_true(stats.triangles > 0)
    camera.place(Vector3(0, 2, 200), Vector3(0, 0, 400))
    stats = meadow.update(scene, assets, camera, Duration(2.0, SECOND))
    assert_equal(stats.drawn, 0)
    assert_equal(stats.beyond + stats.culled, 16)


def test_a_crowded_meadow_grows_again_and_picks_crowns() raises:
    """A second frame replaces each drawn cluster's geometry. A near tree
    wears its full crown and a far one its thin crown. A small frame of
    it draws."""
    var renderer = Renderer(16, 9)
    var assets = Assets()
    var scene = Scene()
    var p = _meadow_parameters(True)
    var meadow = Meadow(scene, assets, renderer, p)
    assert_equal(len(meadow.trees), 4)
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE),
        16.0 / 9.0,
        Length(0.1, METER),
        Length(300.0, METER),
    )
    camera.place(Vector3(2, 30, 0), Vector3(0, 0, 0))
    var first = meadow.update(scene, assets, camera, Duration(0.0, SECOND))
    var meshes = len(scene.meshes)
    var second = meadow.update(scene, assets, camera, Duration(0.5, SECOND))
    assert_equal(len(scene.meshes), meshes)
    assert_equal(first.drawn, second.drawn)
    camera.place(Vector3(2, 2, -2), Vector3(0, 0, -20))
    _ = meadow.update(scene, assets, camera, Duration(1.0, SECOND))
    var near = 0
    var far = 0
    for t in range(len(meadow.trees)):
        ref tree = meadow.trees[t]
        var wears = scene.meshes[tree.wood + 1].geometry
        if wears == meadow.leaves[tree.kind * 2]:
            near += 1
        if wears == meadow.leaves[tree.kind * 2 + 1]:
            far += 1
    assert_true(near > 0)
    assert_true(far > 0)
    var image = renderer.render(scene, assets, camera)
    assert_equal(image.width, 16)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
