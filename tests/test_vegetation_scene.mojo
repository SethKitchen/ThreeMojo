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
    _unit,
    birch_tree,
    bush_parameters,
    crown_level_for,
    default_crown_levels,
    dress,
    grow_crown,
    hang_leaves,
    leafy_tree,
    round_tree,
    windswept_tree,
    young_tree,
)
from extensions.vegetation.field import LodBand
from extensions.vegetation.foliage import SKYLIT, SUNLIT
from extensions.vegetation.ground import Canyon, Ground, Lot, Pond
from extensions.vegetation.limbs import CrownShape, grow_limbs
from extensions.vegetation.meadow import (
    EXPOSURE,
    EYE_HEIGHT,
    Meadow,
    MeadowParameters,
    Planting,
    blend_frames,
    default_crowns,
    default_plantings,
    grove_plantings,
    meadow_camera,
    meadow_renderer,
    scatter_plantings,
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
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    METER,
    PER_METER,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    InverseLength,
    Length,
)

# The sun straight above, the frame a tree's light is baked in.
comptime OVERHEAD = Vector3(0, 1, 0)


def _sapling() -> CrownParameters:
    """Return a small tree: a crown 3 meters across from 1.5 meters up, in
    four lobes, with a few leaves on each twig."""
    var crown = CrownParameters()
    crown.limbs.shape = CrownShape(
        Length(1.5, METER),
        Length(4.5, METER),
        Length(1.5, METER),
        0.5,
        4,
        Length(0.8, METER),
        0.3,
        0.1,
    )
    crown.limbs.points = 200
    crown.limbs.step = Length(0.15, METER)
    crown.limbs.reach = Length(0.8, METER)
    crown.limbs.kill = Length(0.25, METER)
    crown.leaf_reach = Length(0.3, METER)
    crown.leaves_per_node = 4
    return crown^


def _full() -> CrownLevel:
    """Return a level that keeps every ovate leaf."""
    return CrownLevel(Length(10.0, METER), 1.0, False)


def _meadow_parameters(crowded: Bool) raises -> MeadowParameters:
    """Return a meadow small enough to build in a test. A crowded meadow
    has two trees, a bush and a boulder near the field, and two bushes far
    away; an empty one has none."""
    var p = MeadowParameters()
    p.field.span = Length(16.0, METER)
    p.field.cluster_size = Length(4.0, METER)
    p.field.density = 10
    p.field.bands = [LodBand(Length(60.0, METER), 0.001, 1)]
    p.ground = Ground(seed=11)
    var bush = _sapling()
    bush.seed = 9
    p.crowns = [_sapling(), bush^]
    p.crown_levels = [
        CrownLevel(Length(20.0, METER), 1.0, False),
        CrownLevel(Length(1.0e5, METER), 0.5, True),
    ]
    p.ground_span = Length(60.0, METER)
    p.ground_cells = 4
    p.mountain_radius = Length(100.0, METER)
    p.sky_size = 8
    p.rocks = 0
    p.litter = 2000
    p.litter_reach = Length(10.0, METER)
    p.plantings = List[Planting]()
    if crowded:
        p.ground = Ground(
            seed=11,
            canyon=Canyon(
                Length(20.0, METER),
                Length(36.0, METER),
                Length(5.0, METER),
                Length(3.0, METER),
            ),
        )
        p.rocks = 1
        p.plantings = [
            Planting(0, 2.0, -3.0, 1.0),
            Planting(0, 4.0, -40.0, 1.2),
            Planting(1, -3.0, 2.0, 0.7),
            Planting(1, 300.0, 1.0, 0.5),
            Planting(1, 1.0, -300.0, 0.5),
        ]
    return p^


def _refused(var p: MeadowParameters, text: String) raises:
    """Assert that the meadow is refused with `text`."""
    with assert_raises(contains=text):
        p.check()


def test_crown_parameters_are_checked() raises:
    """The five kinds pass; each field out of range is refused, and so is
    a shape the limbs refuse."""
    CrownParameters().check()
    birch_tree().check()
    assert_true(birch_tree().bark.x > CrownParameters().bark.x)
    windswept_tree().check()
    young_tree().check()
    round_tree().check()
    bush_parameters().check()
    var c = CrownParameters()
    c.limbs.points = 0
    with assert_raises(contains="points"):
        c.check()
    c = CrownParameters()
    c.wood_radius = Length(0.0, METER)
    with assert_raises(contains="thinnest wood"):
        c.check()
    c = CrownParameters()
    c.sides = 2
    with assert_raises(contains="sides"):
        c.check()
    c = CrownParameters()
    c.leaf_reach = Length(-1.0, METER)
    with assert_raises(contains="back from a tip"):
        c.check()
    c = CrownParameters()
    c.leaves_per_node = 0
    with assert_raises(contains="hold"):
        c.check()
    c = CrownParameters()
    c.leaf_length = Length(3.0, METER)
    with assert_raises(contains="long"):
        c.check()
    c = CrownParameters()
    c.leaf_width = Length(0.0, METER)
    with assert_raises(contains="wide"):
        c.check()
    c = CrownParameters()
    c.shade = -1
    with assert_raises(contains="shade"):
        c.check()
    c = CrownParameters()
    c.bark_marks = InverseLength(0.0, PER_METER)
    with assert_raises(contains="marks"):
        c.check()
    c = CrownParameters()
    c.leaf = Vector3(2, 0, 0)
    with assert_raises(contains="color"):
        c.check()
    c = CrownParameters()
    c.bark = Vector3(0, -1, 0)
    with assert_raises(contains="color"):
        c.check()
    c = CrownParameters()
    c.bark_dark = Vector3(0, 0, 3)
    with assert_raises(contains="color"):
        c.check()


def test_crown_levels_pick_by_distance() raises:
    """The first level whose reach holds a distance is picked, and the
    last past every reach. No level is refused, and nor is a level out of
    range."""
    var levels = default_crown_levels()
    for index in range(len(levels)):
        levels[index].check()
    assert_equal(len(levels), 4)
    assert_true(levels[2].cards)
    assert_false(levels[0].cards)
    assert_equal(crown_level_for(levels, 10), 0)
    assert_equal(crown_level_for(levels, 80), 1)
    assert_equal(crown_level_for(levels, 200), 2)
    assert_equal(crown_level_for(levels, 2.0e5), 3)
    with assert_raises(contains="no level"):
        _ = crown_level_for(List[CrownLevel](), 1)
    with assert_raises(contains="reach"):
        CrownLevel(Length(-1.0, METER), 1.0, False).check()
    with assert_raises(contains="detail"):
        CrownLevel(Length(1.0, METER), 0.0, False).check()


def test_leaves_hang_near_the_twig_tips() raises:
    """Each node near a tip carries its leaves, on the twig below it. A
    reach of zero hangs leaves on the tips alone. The leaves face up more
    than down, and splay out from their twigs."""
    var sapling = _sapling()
    var skeleton = grow_limbs(sapling.limbs)
    var leaves = hang_leaves(skeleton, sapling)
    var near = 0
    for n in range(1, skeleton.count()):
        if skeleton.tip_distance[n] <= 0.3:
            near += 1
    assert_equal(len(leaves), 4 * near)
    var up = 0
    for index in range(len(leaves)):
        ref leaf = leaves[index]
        assert_almost_equal(leaf.normal.length(), 1, atol=1e-4)
        assert_almost_equal(leaf.along.dot(leaf.normal), 0, atol=1e-4)
        assert_true(leaf.scale >= 0.7 and leaf.scale <= 1.3)
        assert_equal(leaf.sun, 0)
        if leaf.normal.y > 0:
            up += 1
    assert_true(up > len(leaves) * 3 // 4)
    var tips_only = _sapling()
    tips_only.leaf_reach = Length(0.0, METER)
    assert_equal(
        len(hang_leaves(skeleton, tips_only)), 4 * (skeleton.tips() - 0)
    )


def test_a_unit_vector_falls_back_to_up() raises:
    """A vector near zero has no direction, so it is taken as +y."""
    assert_almost_equal(_unit(Vector3(0, 0, 0)).y, 1)
    assert_almost_equal(_unit(Vector3(3, 0, 4)).x, 0.6, atol=1e-6)


def test_a_leafy_tree_bakes_its_light() raises:
    """A full tree has ovate leaves of eight vertices, with the light of
    each baked. A leaf on top sees more sky than one below the crown. Its
    bark is colored."""
    var tree = leafy_tree(_sapling(), _full(), OVERHEAD)
    assert_true(tree.leaf_count > 50)
    assert_equal(tree.leaves.vertex_count(), 8 * tree.leaf_count)
    assert_equal(len(tree.leaves.index), 18 * tree.leaf_count)
    assert_true(tree.wood.has_attribute(String(COLOR)))
    ref p = tree.leaves.attribute_view(String(POSITION))
    ref sky = tree.leaves.attribute_view(String(SKYLIT))
    ref sun = tree.leaves.attribute_view(String(SUNLIT))
    var highest = 0
    var lowest = 0
    for leaf in range(tree.leaf_count):
        if p.vector3(8 * leaf).y > p.vector3(8 * highest).y:
            highest = leaf
        if p.vector3(8 * leaf).y < p.vector3(8 * lowest).y:
            lowest = leaf
        assert_true(sky.component(8 * leaf, 0) <= 1)
        assert_true(sun.component(8 * leaf, 0) <= 1)
    assert_true(sky.component(8 * highest, 0) > sky.component(8 * lowest, 0))


def test_a_thin_level_keeps_fewer_larger_cards_on_lean_wood() raises:
    """A quarter of the detail as cards keeps fewer leaves, each twice as
    long, of four vertices, on wood with fewer vertices."""
    var full = leafy_tree(_sapling(), _full(), OVERHEAD)
    var thin = leafy_tree(
        _sapling(), CrownLevel(Length(1.0, METER), 0.25, True), OVERHEAD
    )
    assert_true(thin.leaf_count < full.leaf_count // 2)
    assert_true(thin.leaf_count > 0)
    assert_equal(thin.leaves.vertex_count(), 4 * thin.leaf_count)
    assert_true(thin.wood.vertex_count() < full.wood.vertex_count())
    ref a = full.leaves.attribute_view(String(POSITION))
    ref b = thin.leaves.attribute_view(String(POSITION))
    var long_full = (a.vector3(7) - a.vector3(0)).length()
    var long_thin = (b.vector3(2) - b.vector3(0)).length()
    assert_true(long_thin > long_full * 1.5)


def test_a_dense_crown_leaves_out_the_leaves_nobody_sees() raises:
    """In a crown dense enough to stop nearly all light, most leaves see
    neither sun nor sky and are left out. Each leaf kept sees one or the
    other."""
    var dense = _sapling()
    dense.shade = 20
    dense.leaves_per_node = 12
    var open = grow_crown(_sapling(), Vector3(0, -1, 0))
    var thick = grow_crown(dense, Vector3(0, -1, 0))
    assert_true(len(thick.leaves) < len(open.leaves) // 2)
    assert_true(len(thick.leaves) > 0)
    for index in range(len(thick.leaves)):
        ref leaf = thick.leaves[index]
        assert_true(leaf.sun >= 0.004 or leaf.sky >= 0.004)
        assert_true(leaf.sun <= 1 and leaf.sky <= 1)


def test_a_crown_with_no_leaf_is_refused() raises:
    """A detail out of range, a sun that is not a unit direction, a tree
    whose root reaches every point and so grows no twig, and a detail that
    keeps no leaf are refused."""
    with assert_raises(contains="detail"):
        _ = leafy_tree(
            _sapling(), CrownLevel(Length(1.0, METER), 0.0, False), OVERHEAD
        )
    with assert_raises(contains="unit length"):
        _ = leafy_tree(_sapling(), _full(), Vector3(0, 2, 0))
    var stump = _sapling()
    stump.limbs.shape = CrownShape(
        Length(0.0, METER),
        Length(0.2, METER),
        Length(0.1, METER),
        0.5,
        0,
        Length(0.1, METER),
        0,
        0,
    )
    stump.limbs.step = Length(0.02, METER)
    stump.limbs.reach = Length(0.5, METER)
    stump.limbs.kill = Length(0.5, METER)
    stump.limbs.fork = 0
    with assert_raises(contains="no twig"):
        _ = grow_crown(stump, OVERHEAD)
    var sparse = _sapling()
    sparse.leaves_per_node = 1
    sparse.leaf_reach = Length(0.0, METER)
    sparse.limbs.points = 20
    with assert_raises(contains="keeps no leaf"):
        _ = leafy_tree(
            sparse, CrownLevel(Length(1.0, METER), 0.01, False), OVERHEAD
        )


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
    assert_true(p.ground.canyon.depth.value > 0)
    var camera = meadow_camera(p, 16, 9, Length(2.0, METER))
    assert_almost_equal(camera.position.z, 28, atol=1e-5)
    assert_almost_equal(
        camera.position.y, p.ground.height_at(0, 28) + EYE_HEIGHT, atol=1e-5
    )


def test_frames_blend_into_their_mean() raises:
    """Each channel of a blend is the rounded mean of the frames. One
    frame blends into itself. No frame, and frames of two sizes, are
    refused."""
    var dark = Framebuffer(2, 1, Color(10, 20, 30, 255))
    var light = Framebuffer(2, 1, Color(20, 41, 30, 255))
    var frames = List[Framebuffer]()
    frames.append(dark^)
    frames.append(light^)
    var blended = blend_frames(frames)
    assert_equal(blended.width, 2)
    assert_equal(Int(blended.pixels[0]), 15)
    assert_equal(Int(blended.pixels[1]), 31)
    assert_equal(Int(blended.pixels[2]), 30)
    assert_equal(Int(blended.pixels[7]), 255)
    var one = List[Framebuffer]()
    one.append(Framebuffer(1, 1, Color(7, 8, 9, 255)))
    assert_equal(Int(blend_frames(one).pixels[2]), 9)
    with assert_raises(contains="at least one"):
        _ = blend_frames(List[Framebuffer]())
    frames.append(Framebuffer(3, 1, Color(0, 0, 0, 255)))
    with assert_raises(contains="one size"):
        _ = blend_frames(frames)
    var taller = List[Framebuffer]()
    taller.append(Framebuffer(2, 1, Color(0, 0, 0, 255)))
    taller.append(Framebuffer(2, 2, Color(0, 0, 0, 255)))
    with assert_raises(contains="one size"):
        _ = blend_frames(taller)


def test_plantings_scatter_across_the_view() raises:
    """Scattered plantings stand in their band toward -z, within the view's
    width there, and cycle through their crowns. A grove stands within its
    spread. None is scattered or planted for a count of zero. The default
    layout names only its own crowns."""
    var scattered = scatter_plantings(
        40, 2, 3, Length(10.0, METER), Length(50.0, METER), 0.5, 1.5, 4
    )
    assert_equal(len(scattered), 40)
    for index in range(len(scattered)):
        ref planting = scattered[index]
        assert_true(planting.z <= -10 + 1e-4 and planting.z >= -50 - 1e-4)
        assert_true(abs(planting.x) <= 1.1 * 50 + 10)
        assert_equal(planting.crown, 2 + index % 3)
        assert_true(planting.size >= 0.5 and planting.size <= 1.5)
    assert_equal(
        len(
            scatter_plantings(
                0, 0, 1, Length(1.0, METER), Length(2.0, METER), 1, 1, 0
            )
        ),
        0,
    )
    var grove = grove_plantings(
        12, 1, 3, 10, -40, Length(8.0, METER), 0.8, 1.2, 5
    )
    assert_equal(len(grove), 12)
    for index in range(len(grove)):
        ref planting = grove[index]
        var dx = planting.x - 10
        var dz = planting.z + 40
        assert_true(dx * dx + dz * dz <= 64 + 1e-3)
        assert_equal(planting.crown, 1 + index % 3)
        assert_true(planting.size >= 0.8 and planting.size <= 1.2)
    assert_equal(
        len(grove_plantings(0, 0, 1, 0, 0, Length(1.0, METER), 1, 1, 0)), 0
    )
    var crowns = default_crowns()
    assert_equal(len(crowns), 12)
    assert_true(crowns[7].leaf_length.value < crowns[0].leaf_length.value)
    var plantings = default_plantings()
    assert_equal(len(plantings), 4 + 9 + 6 + 6 + 14 + 30 + 90 + 30)
    for index in range(len(plantings)):
        assert_true(plantings[index].crown < len(crowns))


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
    p.sky.gain = -2
    _refused(p^, "gain")
    p = MeadowParameters()
    p.crowns = List[CrownParameters]()
    _refused(p^, "crowns")
    p = MeadowParameters()
    p.crowns[1].leaves_per_node = 0
    _refused(p^, "hold")
    p = MeadowParameters()
    for _ in range(100001 - len(p.plantings)):
        p.plantings.append(Planting(0, 0, 0, 1))
    _refused(p^, "plantings")
    p = MeadowParameters()
    p.plantings = [Planting(12, 0, 0, 1)]
    _refused(p^, "wear")
    p = MeadowParameters()
    for _ in range(1001):
        p.lots.append(Lot(0, 0, 1, 1, 0))
    _refused(p^, "lots")
    p = MeadowParameters()
    p.litter = -1
    _refused(p^, "litter must try")
    p = MeadowParameters()
    p.litter_reach = Length(0.0, METER)
    _refused(p^, "litter must reach")
    p = MeadowParameters()
    p.plantings = [Planting(-1, 0, 0, 1)]
    _refused(p^, "wear")
    p = MeadowParameters()
    p.plantings = [Planting(0, 2.0e4, 0, 1)]
    _refused(p^, "within 10 kilometers")
    p = MeadowParameters()
    p.plantings = [Planting(0, 0, -2.0e4, 1)]
    _refused(p^, "within 10 kilometers")
    p = MeadowParameters()
    p.plantings = [Planting(0, 0, 0, 30)]
    _refused(p^, "size")
    p = MeadowParameters()
    p.rocks = 1001
    _refused(p^, "boulders")
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


def _camera() raises -> PerspectiveCamera:
    """Return a test camera that sees 300 meters."""
    return PerspectiveCamera(
        Angle(60.0, DEGREE),
        16.0 / 9.0,
        Length(0.1, METER),
        Length(300.0, METER),
    )


def test_no_tree_grows_on_a_lot_or_in_a_pond() raises:
    """A planting on a lot, and one in a pond's basin, are left out; the
    others grow. Nothing grows on the lot."""
    var renderer = Renderer(16, 9)
    var assets = Assets()
    var scene = Scene()
    var p = _meadow_parameters(True)
    p.lots = [Lot(2, -3, 1.5, 1.5, 0)]
    p.ground.pond = Pond(
        Length(-3.0, METER),
        Length(2.0, METER),
        Length(3.0, METER),
        Length(1.0, METER),
    )
    var meadow = Meadow(scene, assets, renderer, p)
    assert_equal(len(meadow.trees), 3)
    assert_equal(len(meadow.field.lots), 1)
    assert_almost_equal(meadow.field.cover_at(2, -3), 0)


def test_an_empty_meadow_draws_its_grass_and_sky() raises:
    """A meadow with no tree, bush or boulder still has its ground,
    mountains, sky, sun, fog and grass, and no litter. Its frame draws
    clusters near the camera and leaves the far ones to the ground."""
    var renderer = Renderer(16, 9)
    var assets = Assets()
    var scene = Scene()
    var p = _meadow_parameters(False)
    var meadow = Meadow(scene, assets, renderer, p)
    var built = len(scene.meshes)
    assert_equal(len(meadow.trees), 0)
    assert_true(scene.background.kind == CUBE_BACKGROUND)
    assert_true(scene.fog.kind == EXP2_FOG)
    var camera = _camera()
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
    # Grassy ground with no tree has no litter, and nor does a meadow
    # that tries none.
    var bare = _meadow_parameters(False)
    bare.litter = 0
    var plain = Scene()
    _ = Meadow(plain, assets, renderer, bare)
    assert_equal(len(plain.meshes), built)


def test_a_crowded_meadow_grows_again_and_picks_crowns() raises:
    """The trees in the field thin the grass round them and gather
    litter. A second frame replaces each drawn cluster's geometry. A near
    tree wears its full, swaying crown and a far one its thin, still
    crown. Each tree leans a little from its foot, and is never turned
    about +y. A small frame of it draws."""
    var renderer = Renderer(16, 9)
    var assets = Assets()
    var scene = Scene()
    var p = _meadow_parameters(True)
    var meadow = Meadow(scene, assets, renderer, p)
    assert_equal(len(meadow.trees), 5)
    assert_equal(len(meadow.leaves), 4)
    assert_equal(len(meadow.field.clearings), 2)
    assert_almost_equal(meadow.field.cover_at(2, -3), 0)
    var bare = _meadow_parameters(True)
    bare.litter = 0
    var plain = Scene()
    _ = Meadow(plain, assets, renderer, bare)
    assert_equal(len(scene.meshes), len(plain.meshes) + 1)
    var camera = _camera()
    camera.place(Vector3(2, 30, 0), Vector3(0, 0, 0))
    var first = meadow.update(scene, assets, camera, Duration(0.0, SECOND))
    var meshes = len(scene.meshes)
    var second = meadow.update(scene, assets, camera, Duration(0.5, SECOND))
    assert_equal(len(scene.meshes), meshes)
    assert_equal(first.drawn, second.drawn)
    camera.place(Vector3(2, 2, 4), Vector3(0, 0, -20))
    _ = meadow.update(scene, assets, camera, Duration(1.0, SECOND))
    var near = 0
    var far = 0
    for t in range(len(meadow.trees)):
        ref tree = meadow.trees[t]
        var wears = scene.meshes[tree.wood + 1].geometry
        var dressed = scene.meshes[tree.wood + 1].material
        if wears == meadow.leaves[tree.crown * 2]:
            near += 1
            assert_true(dressed == meadow.leaf_sway)
            assert_true(scene.meshes[tree.wood].material == meadow.wood_sway)
        if wears == meadow.leaves[tree.crown * 2 + 1]:
            far += 1
            assert_true(dressed == meadow.leaf_still)
            assert_true(scene.meshes[tree.wood].material == meadow.wood_still)
    assert_equal(near, 2)
    assert_equal(far, 3)
    for t in range(len(meadow.trees)):
        var turn = scene.get(scene.meshes[meadow.trees[t].wood].node).quaternion
        assert_true(abs(turn.w) < 1)
        assert_true(abs(turn.w) > 0.999)
        assert_almost_equal(turn.y, 0, atol=1e-6)
    var image = renderer.render(scene, assets, camera)
    assert_equal(image.width, 16)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
