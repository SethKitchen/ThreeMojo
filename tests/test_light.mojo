# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `lights.light` and `lights.lighting`.

The numbers here are worked out from the definitions rather than read off the
implementation. Two in particular are worth stating, because both are places
where doing the arithmetic on bytes gives a plausible-looking wrong answer:
a quarter of the light of byte 200 displays as 106 and not as 50, and two
half-strength white lights come to a full one and not to byte 128.
"""

from core.layers import Layers
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from lights.light import (
    AMBIENT,
    DEFAULT_SPOT_ANGLE,
    DIRECTIONAL,
    HEMISPHERE,
    POINT,
    SPOT,
    Light,
    LightKind,
    ambient_light,
    directional_light,
    hemisphere_light,
    point_light,
    spot_light,
)
from math.smoothstep import smoothstep
from std.math import inf, nan
from lights.lighting import (
    TOON_EDGE,
    TOON_SHADE,
    Lighting,
    blinn_phong,
    toon_coord,
    toon_index,
    toon_step,
    toon_tone,
)
from math.vector3 import Vector3
from units.si import Angle, DEGREE, RADIAN
from render.framebuffer import Color, FloatColor
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-6)
comptime WHITE = Color(255, 255, 255)
comptime ORIGIN = Vector3(0, 0, 0)


def scene_with_lamp_at(x: Float32, y: Float32, z: Float32) raises -> Scene:
    """Return a scene whose only node sits at a point, ready to light from."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(x, y, z)
    _ = scene.add(lamp^)
    scene.update()
    return scene^


def shaded(lighting: Lighting, base: Color, normal: Vector3) -> FloatColor:
    """Shade a surface at the origin, which is where every directional test
    puts it; only a point light would care."""
    return lighting.shade(base, normal, ORIGIN)


def lit_from(x: Float32, y: Float32, z: Float32) raises -> Scene:
    """Return a scene with one white directional light at full strength."""
    var scene = scene_with_lamp_at(x, y, z)
    scene.add_light(directional_light(WHITE, NodeId(0)))
    return scene^


# --- A light on its own -----------------------------------------------------


def test_a_light_carries_its_kind_and_color() raises:
    var fill = ambient_light(Color(10, 20, 30), 0.5)
    assert_equal(fill.kind, AMBIENT)
    assert_equal(fill.color.g, UInt8(20))
    assert_equal(fill.node, NO_PARENT)
    var sun = directional_light(Color(1, 2, 3), NodeId(4), 2.0)
    assert_equal(sun.kind, DIRECTIONAL)
    assert_equal(sun.node, NodeId(4))
    assert_almost_equal(sun.intensity, Float32(2), atol=TOLERANCE)


def test_a_lights_radiance_is_decoded_and_scaled() raises:
    # White at half strength is half the *light*, so 0.5 linear -- not byte
    # 128, which is about a fifth of the light.
    var half = ambient_light(WHITE, 0.5).radiance()
    assert_almost_equal(half.r, Float32(0.5), atol=TOLERANCE)
    # And a mid-gray light is decoded before being scaled: byte 128 is about
    # 0.2158 of the light.
    var gray = ambient_light(Color(128, 128, 128)).radiance()
    assert_almost_equal(gray.r, Float32(0.215861), atol=Float64(1e-5))


def test_a_negative_intensity_is_rejected() raises:
    # Not a dimmer light: a light that removes light.
    with assert_raises():
        _ = ambient_light(WHITE, -0.1)
    with assert_raises():
        _ = directional_light(WHITE, NodeId(0), -0.1)


def test_an_intensity_above_one_is_allowed() raises:
    # Two lamps really can overexpose a surface, and `resolve` is the single
    # place that decides what a display can show.
    var bright = ambient_light(WHITE, 3.0).radiance()
    assert_almost_equal(bright.r, Float32(3), atol=TOLERANCE)


# --- Resolving a scene's lights ---------------------------------------------


def test_a_scene_starts_with_no_lights() raises:
    var scene = Scene()
    assert_equal(len(scene.lights), 0)
    var lighting = Lighting(scene)
    assert_equal(lighting.count(), 0)
    assert_almost_equal(lighting.ambient.r, Float32(0), atol=TOLERANCE)


def test_an_unlit_scene_renders_black() raises:
    # What "no lights" means, and the clearest consequence of ambient being a
    # light rather than a fraction the surface keeps.
    var lighting = Lighting(Scene())
    var shaded = shaded(lighting, Color(200, 100, 50), Vector3(0, 1, 0))
    assert_almost_equal(shaded.r, Float32(0), atol=TOLERANCE)
    assert_almost_equal(shaded.g, Float32(0), atol=TOLERANCE)


def test_adding_a_light_does_not_make_a_scene_stale() raises:
    # A light holds no transform, so it cannot invalidate a world matrix.
    var scene = scene_with_lamp_at(0, 1, 0)
    assert_true(not scene.is_stale())
    scene.add_light(ambient_light(WHITE))
    assert_true(not scene.is_stale())


def test_a_directional_light_points_from_its_node_to_the_origin() raises:
    var lighting = Lighting(lit_from(0, 5, 0))
    assert_equal(lighting.count(), 1)
    # Given as length five, resolved as a unit vector.
    assert_almost_equal(
        lighting.directions[0].length(), Float32(1), atol=TOLERANCE
    )
    assert_almost_equal(lighting.directions[0].y, Float32(1), atol=TOLERANCE)


def test_a_directional_light_at_the_origin_is_rejected() raises:
    # No direction to shine from. A mistake rather than a dark light.
    var scene = scene_with_lamp_at(0, 0, 0)
    scene.add_light(directional_light(WHITE, NodeId(0)))
    with assert_raises():
        _ = Lighting(scene)


def test_a_light_naming_a_node_that_is_not_there_is_rejected() raises:
    var scene = scene_with_lamp_at(0, 1, 0)
    scene.add_light(directional_light(WHITE, NodeId(7)))
    with assert_raises():
        _ = Lighting(scene)


def test_a_light_is_carried_by_the_node_it_hangs_from() raises:
    # The reason a light names a node rather than a bare direction: turn the
    # parent and the lamp turns with it. A light on the renderer could not do
    # this at all.
    var scene = Scene()
    var arm = Object3D()
    arm.set_euler(Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE))
    var pivot = scene.add(arm^)
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    lamp.parent = pivot
    var hung = scene.add(lamp^)
    scene.update()
    scene.add_light(directional_light(WHITE, hung))

    # A quarter turn about y takes +z to +x.
    var lighting = Lighting(scene)
    assert_almost_equal(
        lighting.directions[0].x, Float32(1), atol=Float64(1e-5)
    )
    assert_almost_equal(
        lighting.directions[0].z, Float32(0), atol=Float64(1e-5)
    )


# --- Shading ----------------------------------------------------------------


def test_a_face_turned_towards_the_light_keeps_its_color() raises:
    var lighting = Lighting(lit_from(0, 1, 0))
    var lit = shaded(lighting, Color(200, 100, 50), Vector3(0, 1, 0)).encode()
    assert_equal(lit.r, UInt8(200))


def test_a_face_turned_away_gets_only_the_ambient() raises:
    # A quarter of the *light* of byte 200 displays as 106 -- not a quarter
    # of the byte, which would be 50. Dimming the encoded value is the
    # classic color-space error: it makes shadows far too dark.
    var scene = lit_from(0, 1, 0)
    scene.add_light(ambient_light(WHITE, 0.25))
    var lighting = Lighting(scene)
    var dim = shaded(lighting, Color(200, 100, 50), Vector3(0, -1, 0)).encode()
    assert_equal(dim.r, UInt8(106))


def test_lambert_falls_off_with_the_angle() raises:
    # Ninety degrees away catches nothing; the surface is edge-on.
    var lighting = Lighting(lit_from(0, 1, 0))
    var edge = shaded(lighting, Color(200, 0, 0), Vector3(1, 0, 0)).encode()
    assert_equal(edge.r, UInt8(0))


def test_two_lights_add_their_light_and_not_their_bytes() raises:
    # The whole reason lighting happens in linear light. Two white lamps at
    # half strength, both facing the surface, make one at full strength --
    # byte 255. Adding encoded halves would give 128, a fifth of the light
    # wearing the label of a half.
    var scene = scene_with_lamp_at(0, 1, 0)
    scene.add_light(directional_light(WHITE, NodeId(0), 0.5))
    scene.add_light(directional_light(WHITE, NodeId(0), 0.5))
    var lighting = Lighting(scene)
    assert_equal(lighting.count(), 2)
    var lit = shaded(lighting, WHITE, Vector3(0, 1, 0)).encode()
    assert_equal(lit.r, UInt8(255))


def test_ambient_lights_sum_as_well() raises:
    var scene = Scene()
    scene.add_light(ambient_light(WHITE, 0.25))
    scene.add_light(ambient_light(WHITE, 0.25))
    var lighting = Lighting(scene)
    assert_almost_equal(lighting.ambient.r, Float32(0.5), atol=TOLERANCE)


def test_a_colored_light_tints_the_surface() raises:
    # What the old scalar dimming could not do at all: a red lamp on a white
    # surface leaves red and nothing else.
    var scene = scene_with_lamp_at(0, 1, 0)
    scene.add_light(directional_light(Color(255, 0, 0), NodeId(0)))
    var lighting = Lighting(scene)
    var lit = shaded(lighting, WHITE, Vector3(0, 1, 0)).encode()
    assert_equal(lit.r, UInt8(255))
    assert_equal(lit.g, UInt8(0))
    assert_equal(lit.b, UInt8(0))


def test_a_blue_ambient_tints_the_shadows() raises:
    var scene = Scene()
    scene.add_light(ambient_light(Color(0, 0, 255), 0.5))
    var lighting = Lighting(scene)
    var shadow = shaded(lighting, WHITE, Vector3(0, -1, 0)).encode()
    assert_equal(shadow.r, UInt8(0))
    assert_true(shadow.b > 180)


def test_a_fully_lit_white_face_clamps_rather_than_wrapping() raises:
    # Rounding pushes 255 to 255.5, which must clamp rather than overflow.
    var lighting = Lighting(lit_from(0, 1, 0))
    var lit = shaded(lighting, WHITE, Vector3(0, 1, 0)).encode()
    assert_equal(lit.r, UInt8(255))
    assert_equal(lit.g, UInt8(255))


def test_an_overexposed_surface_clamps_once_at_the_end() raises:
    # Two full-strength lamps on a white surface is twice as much light as it
    # can show. Nothing clamps until `encode`, so the headroom survives every
    # step in between.
    var scene = scene_with_lamp_at(0, 1, 0)
    scene.add_light(directional_light(WHITE, NodeId(0)))
    scene.add_light(directional_light(WHITE, NodeId(0)))
    var lighting = Lighting(scene)
    var over = shaded(lighting, WHITE, Vector3(0, 1, 0))
    assert_almost_equal(over.r, Float32(2), atol=TOLERANCE)
    assert_equal(over.encode().r, UInt8(255))


def test_shading_preserves_alpha() raises:
    var lighting = Lighting(lit_from(0, 1, 0))
    var shaded = shaded(
        lighting, Color(200, 100, 50, 128), Vector3(0, 1, 0)
    ).encode()
    assert_equal(shaded.a, UInt8(128))


def test_uniform_lighting_leaves_a_color_alone() raises:
    # The identity for the multiply a fragment does, and the default both
    # rasterizers take. The same idea as the blank texture sampling opaque
    # white: it makes "no lighting" a value rather than a branch, so a
    # hand-built triangle asking about coverage or depth gets the colors it
    # passed in rather than black.
    var plain = Lighting.uniform()
    assert_equal(plain.count(), 0)
    var arriving = plain.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(arriving.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(arriving.b, Float32(1), atol=TOLERANCE)
    # Whichever way the surface faces: there is no direction in it.
    var behind = plain.intensity_at(Vector3(0, -1, 0), ORIGIN)
    assert_almost_equal(behind.g, Float32(1), atol=TOLERANCE)
    # And a surface keeps its own color exactly.
    var kept = shaded(plain, Color(200, 100, 50), Vector3(0, 0, -1)).encode()
    assert_equal(kept.r, UInt8(200))
    assert_equal(kept.g, UInt8(100))
    assert_equal(kept.b, UInt8(50))


def test_lighting_can_be_built_from_an_ambient_term_alone() raises:
    var dim = Lighting(ambient=FloatColor(0.25, 0.5, 0.75, 1.0))
    assert_equal(dim.count(), 0)
    assert_almost_equal(
        dim.intensity_at(Vector3(1, 0, 0), ORIGIN).g,
        Float32(0.5),
        atol=TOLERANCE,
    )


# --- point lights ------------------------------------------------------------


def bulb_at(
    x: Float32,
    y: Float32,
    z: Float32,
    intensity: Float32 = 1.0,
    decay: Float32 = 2.0,
    distance: Float32 = 0.0,
) raises -> Lighting:
    """Return lighting with one white point light at a position and nothing
    else."""
    var scene = scene_with_lamp_at(x, y, z)
    scene.add_light(point_light(WHITE, NodeId(0), intensity, decay, distance))
    return Lighting(scene)


def test_a_point_light_falls_off_with_the_square_of_distance() raises:
    var lighting = bulb_at(0, 2, 0)
    assert_equal(lighting.point_count(), 1)
    assert_equal(lighting.count(), 0)
    # Two meters below the bulb, facing up: a quarter of it.
    var below = lighting.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(below.r, Float32(0.25), atol=TOLERANCE)
    # One meter away: all of it.
    var near = lighting.intensity_at(Vector3(0, 1, 0), Vector3(0, 1, 0))
    assert_almost_equal(near.g, Float32(1), atol=TOLERANCE)


def test_a_point_light_shines_from_where_its_node_is() raises:
    var lighting = bulb_at(1, 0, 0)
    # Facing the bulb catches it; facing away catches nothing.
    var towards = lighting.intensity_at(Vector3(1, 0, 0), ORIGIN)
    assert_almost_equal(towards.r, Float32(1), atol=TOLERANCE)
    var away = lighting.intensity_at(Vector3(-1, 0, 0), ORIGIN)
    assert_almost_equal(away.r, Float32(0), atol=TOLERANCE)
    # Edge-on, Lambert says nothing arrives.
    var edge = lighting.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(edge.r, Float32(0), atol=TOLERANCE)


def test_lambert_applies_to_the_direction_from_the_surface() raises:
    # The bulb is off to one side and up: the surface faces up, so it catches
    # the cosine of the angle between up and the way to the bulb, and the
    # falloff is over the real distance rather than the height.
    var lighting = bulb_at(3, 4, 0)
    var arriving = lighting.intensity_at(Vector3(0, 1, 0), ORIGIN)
    # Distance five; cosine four fifths; one over twenty-five.
    assert_almost_equal(arriving.r, Float32(0.8 / 25), atol=TOLERANCE)


def test_a_point_lights_decay_is_adjustable() raises:
    var gentle = bulb_at(0, 2, 0, 1.0, 1.0)
    var arriving = gentle.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(arriving.r, Float32(0.5), atol=TOLERANCE)
    var flat = bulb_at(0, 2, 0, 1.0, 0.0)
    var undimmed = flat.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(undimmed.r, Float32(1), atol=TOLERANCE)


def test_a_point_light_with_a_distance_fades_to_nothing_at_it() raises:
    # Cut off at four meters, measured at two: the inverse square quarter is
    # scaled by the square of one minus a half to the fourth.
    var lighting = bulb_at(0, 2, 0, 1.0, 2.0, 4.0)
    var halfway = lighting.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(
        halfway.r, Float32(0.25 * 0.9375 * 0.9375), atol=TOLERANCE
    )
    # At the cutoff itself, and beyond it, nothing.
    var at_edge = lighting.intensity_at(Vector3(0, 1, 0), Vector3(0, -2, 0))
    assert_almost_equal(at_edge.r, Float32(0), atol=TOLERANCE)
    var beyond = lighting.intensity_at(Vector3(0, 1, 0), Vector3(0, -3, 0))
    assert_almost_equal(beyond.r, Float32(0), atol=TOLERANCE)


def test_a_surface_touching_the_bulb_is_bright_but_finite() raises:
    # Five centimeters away the inverse square would be four hundred; the
    # floor holds it to a hundred. Still overexposed, still a number.
    var lighting = bulb_at(0, 0.05, 0)
    var arriving = lighting.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(arriving.r, Float32(100), atol=Float64(1e-3))


def test_a_surface_exactly_on_the_bulb_gets_only_the_ambient() raises:
    # No direction to be lit from, so the bulb is skipped rather than
    # dividing by zero.
    var scene = scene_with_lamp_at(1, 1, 1)
    scene.add_light(point_light(WHITE, NodeId(0)))
    scene.add_light(ambient_light(WHITE, 0.25))
    var lighting = Lighting(scene)
    var arriving = lighting.intensity_at(Vector3(0, 1, 0), Vector3(1, 1, 1))
    assert_almost_equal(arriving.r, Float32(0.25), atol=TOLERANCE)


def test_a_point_light_is_carried_by_its_node() raises:
    var scene = Scene()
    var pivot = Object3D()
    pivot.set_position(0, 5, 0)
    var parent = scene.add(pivot^)
    var bulb = Object3D()
    bulb.set_position(0, 1, 0)
    var child = scene.attach(bulb^, parent)
    scene.add_light(point_light(WHITE, child))
    scene.update()
    var lighting = Lighting(scene)
    assert_almost_equal(lighting.positions[0].y, Float32(6), atol=TOLERANCE)
    var arriving = lighting.intensity_at(Vector3(0, 1, 0), Vector3(0, 4, 0))
    assert_almost_equal(arriving.r, Float32(0.25), atol=TOLERANCE)


def test_a_point_light_carries_its_kind_and_its_falloff() raises:
    var light = point_light(Color(255, 200, 120), NodeId(3), 0.5, 1.5, 9.0)
    assert_equal(light.kind, POINT)
    assert_equal(light.node, NodeId(3))
    assert_equal(light.intensity, Float32(0.5))
    assert_equal(light.decay, Float32(1.5))
    assert_equal(light.distance, Float32(9))
    # The defaults are three.js's: inverse square, no cutoff.
    var plain = point_light(WHITE, NodeId(0))
    assert_equal(plain.decay, Float32(2))
    assert_equal(plain.distance, Float32(0))


def test_a_point_light_rejects_negative_numbers() raises:
    with assert_raises():
        _ = point_light(WHITE, NodeId(0), -1.0)
    with assert_raises():
        _ = point_light(WHITE, NodeId(0), 1.0, -1.0)
    with assert_raises():
        _ = point_light(WHITE, NodeId(0), 1.0, 2.0, -1.0)


def test_a_point_light_naming_a_missing_node_is_rejected() raises:
    var scene = Scene()
    scene.add_light(point_light(WHITE, NodeId(4)))
    with assert_raises():
        _ = Lighting(scene)


def test_point_light_shades_a_color_at_a_position() raises:
    var lighting = bulb_at(0, 2, 0)
    var lit = lighting.shade(WHITE, Vector3(0, 1, 0), Vector3(0, 1, 0)).encode()
    assert_equal(lit.r, UInt8(255))
    var dim = lighting.shade(WHITE, Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(dim.r, Float32(0.25), atol=TOLERANCE)


def test_a_light_of_an_unknown_kind_is_refused() raises:
    # `LightKind(7)` constructs; resolving the scene is where it is caught.
    assert_true(AMBIENT.is_valid())
    assert_true(DIRECTIONAL.is_valid())
    assert_true(POINT.is_valid())
    assert_true(not LightKind(7).is_valid())
    var scene = Scene()
    scene.add_light(
        Light(
            LightKind(7),
            WHITE,
            1.0,
            NO_PARENT,
            0.0,
            0.0,
            Layers(),
            WHITE,
            Angle(0.0, DEGREE),
            0.0,
            NO_PARENT,
        )
    )
    with assert_raises():
        _ = Lighting(scene)
    assert_true(HEMISPHERE.is_valid())
    assert_true(SPOT.is_valid())


# --- layers -----------------------------------------------------------------


def test_a_light_starts_on_layer_zero_alone() raises:
    assert_equal(ambient_light(WHITE).layers, Layers())
    assert_equal(directional_light(WHITE, NodeId(0)).layers, Layers())
    assert_equal(point_light(WHITE, NodeId(0)).layers, Layers())
    assert_true(Layers.all().test(Layers()))
    assert_true(Layers.all().is_enabled(31))


def scene_lit_on_three_layers() raises -> Scene:
    """Return a scene with an ambient light on layer one, a directional on
    layer two and a point light on layer three, all white and full."""
    var scene = scene_with_lamp_at(0, 0, 4)
    var fill = ambient_light(WHITE)
    fill.layers.set(1)
    scene.add_light(fill)
    var sun = directional_light(WHITE, NodeId(0))
    sun.layers.set(2)
    scene.add_light(sun)
    var bulb = point_light(WHITE, NodeId(0))
    bulb.layers.set(3)
    scene.add_light(bulb)
    return scene^


def test_lighting_for_a_camera_leaves_out_the_lights_on_other_layers() raises:
    # Each kind in turn is the one light a camera on its layer sees, and
    # the two others are gone: an ambient light has no node, and its layers
    # are its own like every other light's.
    var scene = scene_lit_on_three_layers()
    var watching = Layers()
    watching.set(1)
    var fill_only = Lighting(scene, visible=watching)
    assert_equal(fill_only.ambient.r, Float32(1))
    assert_equal(fill_only.count(), 0)
    assert_equal(fill_only.point_count(), 0)
    watching.set(2)
    var sun_only = Lighting(scene, visible=watching)
    assert_equal(sun_only.ambient.r, Float32(0))
    assert_equal(sun_only.count(), 1)
    assert_equal(sun_only.point_count(), 0)
    watching.set(3)
    var bulb_only = Lighting(scene, visible=watching)
    assert_equal(bulb_only.ambient.r, Float32(0))
    assert_equal(bulb_only.count(), 0)
    assert_equal(bulb_only.point_count(), 1)
    # A camera on layer zero alone, the default, sees none of them.
    var dark = Lighting(scene, visible=Layers())
    assert_equal(dark.ambient.r, Float32(0))
    assert_equal(dark.count(), 0)
    assert_equal(dark.point_count(), 0)


def test_lighting_with_no_camera_asking_takes_every_light() raises:
    var scene = scene_lit_on_three_layers()
    var every = Lighting(scene)
    assert_equal(every.ambient.r, Float32(1))
    assert_equal(every.count(), 1)
    assert_equal(every.point_count(), 1)
    # A camera watching two of the layers gets those two.
    var some = Layers()
    some.set(1)
    some.enable(3)
    var two = Lighting(scene, visible=some)
    assert_equal(two.ambient.r, Float32(1))
    assert_equal(two.count(), 0)
    assert_equal(two.point_count(), 1)


# --- hemisphere lights -------------------------------------------------------


def sky_from(
    x: Float32, y: Float32, z: Float32, sky: Color, ground: Color
) raises -> Lighting:
    """Return lighting with one hemisphere light whose sky lies toward a
    point, and nothing else."""
    var scene = scene_with_lamp_at(x, y, z)
    scene.add_light(hemisphere_light(sky, ground, NodeId(0)))
    return Lighting(scene)


def test_a_hemisphere_light_carries_a_sky_and_a_ground() raises:
    var light = hemisphere_light(
        Color(200, 220, 255), Color(80, 60, 40), NodeId(2), 0.5
    )
    assert_equal(light.kind, HEMISPHERE)
    assert_equal(light.node, NodeId(2))
    assert_equal(light.color.b, UInt8(255))
    assert_equal(light.ground.r, UInt8(80))
    assert_equal(light.intensity, Float32(0.5))
    # Both colors are decoded and scaled by the one intensity.
    var white = hemisphere_light(WHITE, WHITE, NodeId(0), 0.5)
    assert_almost_equal(white.radiance().g, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(white.ground_radiance().g, Float32(0.5), atol=TOLERANCE)
    # Every other kind carries a black ground it never reads.
    var sun = directional_light(WHITE, NodeId(0))
    assert_almost_equal(sun.ground_radiance().r, Float32(0), atol=TOLERANCE)
    with assert_raises():
        _ = hemisphere_light(WHITE, WHITE, NodeId(0), -0.5)


def test_a_hemisphere_light_lights_each_side_with_its_own_color() raises:
    # Sky white and ground red, the sky straight up. Facing up sees the sky,
    # facing down sees the ground -- not nothing: there is no Lambert cutoff
    # -- and edge-on sees half of each.
    var lighting = sky_from(0, 1, 0, WHITE, Color(255, 0, 0))
    assert_equal(lighting.hemisphere_count(), 1)
    assert_equal(lighting.count(), 0)
    var up = lighting.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(up.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(up.g, Float32(1), atol=TOLERANCE)
    var down = lighting.intensity_at(Vector3(0, -1, 0), ORIGIN)
    assert_almost_equal(down.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(down.g, Float32(0), atol=TOLERANCE)
    var side = lighting.intensity_at(Vector3(1, 0, 0), ORIGIN)
    assert_almost_equal(side.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(side.g, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(side.b, Float32(0.5), atol=TOLERANCE)


def test_a_hemisphere_light_adds_to_the_other_lights() raises:
    # A quarter of ambient under a white sky: a surface facing the sky gets
    # one and a quarter, and the light does not clamp.
    var scene = scene_with_lamp_at(0, 1, 0)
    scene.add_light(hemisphere_light(WHITE, Color(0, 0, 0), NodeId(0)))
    scene.add_light(ambient_light(WHITE, 0.25))
    var lighting = Lighting(scene)
    var up = lighting.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(up.r, Float32(1.25), atol=TOLERANCE)


def test_a_hemisphere_lights_sky_is_where_its_node_is() raises:
    # The node off to +x puts the sky there: a surface facing +x sees it.
    var lighting = sky_from(3, 0, 0, WHITE, Color(0, 0, 0))
    assert_almost_equal(
        lighting.sky_directions[0].x, Float32(1), atol=TOLERANCE
    )
    var facing = lighting.intensity_at(Vector3(1, 0, 0), ORIGIN)
    assert_almost_equal(facing.r, Float32(1), atol=TOLERANCE)
    var away = lighting.intensity_at(Vector3(-1, 0, 0), ORIGIN)
    assert_almost_equal(away.r, Float32(0), atol=TOLERANCE)


def test_a_hemisphere_light_at_the_origin_is_rejected() raises:
    # No direction for the sky. A mistake rather than a dark light.
    var scene = scene_with_lamp_at(0, 0, 0)
    scene.add_light(hemisphere_light(WHITE, WHITE, NodeId(0)))
    with assert_raises():
        _ = Lighting(scene)
    var missing = Scene()
    missing.add_light(hemisphere_light(WHITE, WHITE, NodeId(4)))
    with assert_raises():
        _ = Lighting(missing)


# --- spot lights ---------------------------------------------------------------


def spot_at(
    x: Float32,
    y: Float32,
    z: Float32,
    angle: Angle = DEFAULT_SPOT_ANGLE,
    penumbra: Float32 = 0.0,
    decay: Float32 = 2.0,
    distance: Float32 = 0.0,
) raises -> Lighting:
    """Return lighting with one white spot light at a position, aimed at
    the origin, and nothing else."""
    var scene = scene_with_lamp_at(x, y, z)
    scene.add_light(
        spot_light(WHITE, NodeId(0), 1.0, distance, angle, penumbra, decay)
    )
    return Lighting(scene)


def test_a_spot_light_carries_its_cone_and_its_target() raises:
    var light = spot_light(
        Color(255, 200, 120),
        NodeId(3),
        0.5,
        9.0,
        Angle(20.0, DEGREE),
        0.25,
        1.5,
        NodeId(7),
    )
    assert_equal(light.kind, SPOT)
    assert_equal(light.node, NodeId(3))
    assert_equal(light.intensity, Float32(0.5))
    assert_equal(light.distance, Float32(9))
    assert_almost_equal(light.angle.to(DEGREE), Float32(20), atol=Float64(1e-4))
    assert_equal(light.penumbra, Float32(0.25))
    assert_equal(light.decay, Float32(1.5))
    assert_equal(light.target, NodeId(7))
    # The defaults are three.js's: no cutoff, sixty degrees, a hard rim,
    # the inverse square, aimed at the origin.
    var plain = spot_light(WHITE, NodeId(0))
    assert_equal(plain.distance, Float32(0))
    assert_almost_equal(plain.angle.to(DEGREE), Float32(60), atol=Float64(1e-4))
    assert_equal(plain.penumbra, Float32(0))
    assert_equal(plain.decay, Float32(2))
    assert_equal(plain.target, NO_PARENT)


def test_a_spot_light_rejects_bad_numbers() raises:
    with assert_raises():
        _ = spot_light(WHITE, NodeId(0), -1.0)
    with assert_raises():
        _ = spot_light(WHITE, NodeId(0), 1.0, -1.0)
    # A cone of nothing lights nothing; one past a half space is not a cone.
    with assert_raises():
        _ = spot_light(WHITE, NodeId(0), 1.0, 0.0, Angle(0.0, DEGREE))
    with assert_raises():
        _ = spot_light(WHITE, NodeId(0), 1.0, 0.0, Angle(91.0, DEGREE))
    _ = spot_light(WHITE, NodeId(0), 1.0, 0.0, Angle(90.0, DEGREE))
    with assert_raises():
        _ = spot_light(WHITE, NodeId(0), 1.0, 0.0, DEFAULT_SPOT_ANGLE, -0.1)
    with assert_raises():
        _ = spot_light(WHITE, NodeId(0), 1.0, 0.0, DEFAULT_SPOT_ANGLE, 1.1)
    with assert_raises():
        _ = spot_light(
            WHITE, NodeId(0), 1.0, 0.0, DEFAULT_SPOT_ANGLE, 0.5, -1.0
        )


def test_a_spot_light_lights_only_inside_its_cone() raises:
    # Two meters up, pointing down at the origin, thirty degrees to the rim.
    # Straight below is on the axis and gets the inverse-square quarter. Half
    # a meter aside is sixteen degrees off the axis, inside: the cosine of
    # that angle, over the squared distance. Two meters aside is forty-five
    # degrees off, outside, and gets nothing at all.
    var lighting = spot_at(0, 2, 0, Angle(30.0, DEGREE))
    assert_equal(lighting.spot_count(), 1)
    assert_equal(lighting.point_count(), 0)
    var below = lighting.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(below.r, Float32(0.25), atol=TOLERANCE)
    var inside = lighting.intensity_at(Vector3(0, 1, 0), Vector3(0.5, 0, 0))
    assert_almost_equal(inside.r, Float32(0.2282688), atol=Float64(1e-5))
    var outside = lighting.intensity_at(Vector3(0, 1, 0), Vector3(2, 0, 0))
    assert_almost_equal(outside.r, Float32(0), atol=TOLERANCE)


def test_a_spot_lights_penumbra_softens_the_rim() raises:
    # Forty-five degrees to the rim, and the inner half of the cone is full:
    # the rim starts to soften at twenty-two and a half degrees. Half a
    # meter aside is well inside and full; one meter aside is twenty-six
    # and a half degrees off, on the soft rim, and gets ninety-five percent
    # of what the bulb alone would give.
    var lighting = spot_at(0, 2, 0, Angle(45.0, DEGREE), 0.5)
    assert_almost_equal(
        lighting.cone_cosines[0], Float32(0.70710678), atol=Float64(1e-6)
    )
    assert_almost_equal(
        lighting.penumbra_cosines[0], Float32(0.92387953), atol=Float64(1e-6)
    )
    var full = lighting.intensity_at(Vector3(0, 1, 0), Vector3(0.5, 0, 0))
    assert_almost_equal(full.r, Float32(0.2282688), atol=Float64(1e-5))
    var soft = lighting.intensity_at(Vector3(0, 1, 0), Vector3(1, 0, 0))
    assert_almost_equal(soft.r, Float32(0.1698761), atol=Float64(1e-5))
    # Without a penumbra the same point is inside a hard rim and full.
    var hard = spot_at(0, 2, 0, Angle(45.0, DEGREE))
    var crisp = hard.intensity_at(Vector3(0, 1, 0), Vector3(1, 0, 0))
    assert_almost_equal(crisp.r, Float32(0.8944272 / 5), atol=Float64(1e-5))
    var beyond = hard.intensity_at(Vector3(0, 1, 0), Vector3(3, 0, 0))
    assert_almost_equal(beyond.r, Float32(0), atol=TOLERANCE)


def test_smoothstep_rises_between_its_edges_and_steps_when_they_meet() raises:
    assert_equal(smoothstep(0.2, 0.8, 0.1), Float32(0))
    assert_equal(smoothstep(0.2, 0.8, 0.2), Float32(0))
    assert_almost_equal(smoothstep(0.2, 0.8, 0.5), Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(
        smoothstep(0.0, 1.0, 0.25), Float32(0.15625), atol=TOLERANCE
    )
    assert_equal(smoothstep(0.2, 0.8, 0.8), Float32(1))
    assert_equal(smoothstep(0.2, 0.8, 0.9), Float32(1))
    # Two equal edges are a hard step rather than a division by zero: a
    # spot light with no penumbra.
    assert_equal(smoothstep(0.5, 0.5, 0.4), Float32(0))
    assert_equal(smoothstep(0.5, 0.5, 0.5), Float32(0))
    assert_equal(smoothstep(0.5, 0.5, 0.6), Float32(1))


def test_a_spot_light_falls_off_and_cuts_off_like_a_bulb() raises:
    # The same falloff as a point light, on the axis: decay one halves at
    # two meters, and a cutoff at four meters scales by the square of one
    # minus a half to the fourth.
    var gentle = spot_at(0, 2, 0, DEFAULT_SPOT_ANGLE, 0.0, 1.0)
    assert_almost_equal(
        gentle.intensity_at(Vector3(0, 1, 0), ORIGIN).r,
        Float32(0.5),
        atol=TOLERANCE,
    )
    var cut = spot_at(0, 2, 0, DEFAULT_SPOT_ANGLE, 0.0, 2.0, 4.0)
    assert_almost_equal(
        cut.intensity_at(Vector3(0, 1, 0), ORIGIN).r,
        Float32(0.25 * 0.9375 * 0.9375),
        atol=TOLERANCE,
    )


def test_a_spot_light_adds_nothing_behind_a_surface_or_on_it() raises:
    var lighting = spot_at(0, 2, 0)
    # Facing away from the bulb, inside the cone: Lambert says nothing.
    var away = lighting.intensity_at(Vector3(0, -1, 0), ORIGIN)
    assert_almost_equal(away.r, Float32(0), atol=TOLERANCE)
    # Exactly on the bulb: no direction to be lit from.
    var on = lighting.intensity_at(Vector3(0, 1, 0), Vector3(0, 2, 0))
    assert_almost_equal(on.r, Float32(0), atol=TOLERANCE)


def test_a_spot_light_points_at_its_target_node() raises:
    # The bulb at (0, 2, 0) aimed at a node at (2, 2, 0) shines along +x. A
    # surface a meter along that way, facing back, is on the axis and gets
    # everything; one a meter the other way is behind the bulb and gets
    # nothing, cone or no cone.
    var scene = scene_with_lamp_at(0, 2, 0)
    var aim = Object3D()
    aim.set_position(2, 2, 0)
    var target = scene.add(aim^)
    scene.update()
    scene.add_light(spot_light(WHITE, NodeId(0), target=target))
    var lighting = Lighting(scene)
    assert_almost_equal(
        lighting.spot_directions[0].x, Float32(-1), atol=TOLERANCE
    )
    var ahead = lighting.intensity_at(Vector3(-1, 0, 0), Vector3(1, 2, 0))
    assert_almost_equal(ahead.r, Float32(1), atol=TOLERANCE)
    var behind = lighting.intensity_at(Vector3(1, 0, 0), Vector3(-1, 2, 0))
    assert_almost_equal(behind.r, Float32(0), atol=TOLERANCE)


def test_a_spot_light_needs_a_direction() raises:
    # On its target there is no way to point: at the origin aimed at the
    # origin, or on the node it is aimed at.
    var scene = scene_with_lamp_at(0, 0, 0)
    scene.add_light(spot_light(WHITE, NodeId(0)))
    with assert_raises():
        _ = Lighting(scene)
    var stacked = scene_with_lamp_at(1, 2, 3)
    var same = Object3D()
    same.set_position(1, 2, 3)
    var target = stacked.add(same^)
    stacked.update()
    stacked.add_light(spot_light(WHITE, NodeId(0), target=target))
    with assert_raises():
        _ = Lighting(stacked)


def test_a_spot_light_naming_a_missing_node_or_target_is_rejected() raises:
    var scene = Scene()
    scene.add_light(spot_light(WHITE, NodeId(4)))
    with assert_raises():
        _ = Lighting(scene)
    var aimed = scene_with_lamp_at(0, 2, 0)
    aimed.add_light(spot_light(WHITE, NodeId(0), target=NodeId(9)))
    with assert_raises():
        _ = Lighting(aimed)


def test_a_spot_light_is_carried_by_its_node() raises:
    # Hung a meter below a pivot five meters up, aimed at the origin: the
    # bulb is four meters up, and a surface below it gets a sixteenth.
    var scene = Scene()
    var pivot = Object3D()
    pivot.set_position(0, 5, 0)
    var parent = scene.add(pivot^)
    var bulb = Object3D()
    bulb.set_position(0, -1, 0)
    var child = scene.attach(bulb^, parent)
    scene.add_light(spot_light(WHITE, child))
    scene.update()
    var lighting = Lighting(scene)
    assert_almost_equal(
        lighting.spot_positions[0].y, Float32(4), atol=TOLERANCE
    )
    var below = lighting.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(below.r, Float32(1.0 / 16), atol=TOLERANCE)


# --- a directional light's target ---------------------------------------------


def test_a_directional_light_points_at_its_target_node() raises:
    # From (0, 5, 0) toward a target at (0, 5, 5): the light travels along
    # +z, so seen from the target the lamp lies along -z, and that is the
    # direction the Lambert term is taken against.
    var scene = scene_with_lamp_at(0, 5, 0)
    var aim = Object3D()
    aim.set_position(0, 5, 5)
    var target = scene.add(aim^)
    scene.update()
    scene.add_light(directional_light(WHITE, NodeId(0), target=target))
    var lighting = Lighting(scene)
    assert_almost_equal(lighting.directions[0].z, Float32(-1), atol=TOLERANCE)
    assert_almost_equal(lighting.directions[0].y, Float32(0), atol=TOLERANCE)
    var facing = lighting.intensity_at(Vector3(0, 0, -1), ORIGIN)
    assert_almost_equal(facing.r, Float32(1), atol=TOLERANCE)
    # Aimed at the origin, the default, the same lamp shines straight down.
    assert_equal(directional_light(WHITE, NodeId(0)).target, NO_PARENT)


def test_a_directional_light_on_its_target_is_rejected() raises:
    var scene = scene_with_lamp_at(0, 5, 0)
    var same = Object3D()
    same.set_position(0, 5, 0)
    var target = scene.add(same^)
    scene.update()
    scene.add_light(directional_light(WHITE, NodeId(0), target=target))
    with assert_raises():
        _ = Lighting(scene)
    var missing = scene_with_lamp_at(0, 5, 0)
    missing.add_light(directional_light(WHITE, NodeId(0), target=NodeId(9)))
    with assert_raises():
        _ = Lighting(missing)


# --- the new kinds and layers ------------------------------------------------


def test_the_new_kinds_start_on_layer_zero_and_follow_the_camera() raises:
    assert_equal(hemisphere_light(WHITE, WHITE, NodeId(0)).layers, Layers())
    assert_equal(spot_light(WHITE, NodeId(0)).layers, Layers())
    var scene = scene_with_lamp_at(0, 2, 0)
    var sky = hemisphere_light(WHITE, WHITE, NodeId(0))
    sky.layers.set(4)
    scene.add_light(sky)
    var beam = spot_light(WHITE, NodeId(0))
    beam.layers.set(5)
    scene.add_light(beam)
    var watching = Layers()
    watching.set(4)
    var sky_only = Lighting(scene, visible=watching)
    assert_equal(sky_only.hemisphere_count(), 1)
    assert_equal(sky_only.spot_count(), 0)
    watching.set(5)
    var beam_only = Lighting(scene, visible=watching)
    assert_equal(beam_only.hemisphere_count(), 0)
    assert_equal(beam_only.spot_count(), 1)
    var every = Lighting(scene)
    assert_equal(every.hemisphere_count(), 1)
    assert_equal(every.spot_count(), 1)
    var none = Lighting.uniform()
    assert_equal(none.hemisphere_count(), 0)
    assert_equal(none.spot_count(), 0)


# --- validation ----------------------------------------------------------------


def not_a_number() -> Float32:
    """Return a NaN, the value no check by comparison alone catches."""
    return nan[DType.float32]()


def test_a_builder_refuses_a_number_that_is_not_finite() raises:
    var endless = inf[DType.float32]()
    with assert_raises():
        _ = ambient_light(WHITE, not_a_number())
    with assert_raises():
        _ = directional_light(WHITE, NodeId(0), endless)
    with assert_raises():
        _ = hemisphere_light(WHITE, WHITE, NodeId(0), not_a_number())
    with assert_raises():
        _ = point_light(WHITE, NodeId(0), 1.0, not_a_number())
    with assert_raises():
        _ = point_light(WHITE, NodeId(0), 1.0, 2.0, endless)
    with assert_raises():
        _ = spot_light(WHITE, NodeId(0), 1.0, not_a_number())
    with assert_raises():
        _ = spot_light(
            WHITE, NodeId(0), 1.0, 0.0, Angle(not_a_number(), DEGREE)
        )
    with assert_raises():
        _ = spot_light(
            WHITE, NodeId(0), 1.0, 0.0, DEFAULT_SPOT_ANGLE, not_a_number()
        )
    with assert_raises():
        _ = spot_light(
            WHITE, NodeId(0), 1.0, 0.0, DEFAULT_SPOT_ANGLE, 0.5, endless
        )


def test_a_light_edited_after_it_was_built_is_refused_when_resolved() raises:
    # The builders' checks are `Light.validate`, and `Lighting` asks it
    # again of every light, on the camera's layers or not: a wrong light is
    # a wrong asset, not a wrong frame.
    var scene = scene_with_lamp_at(0, 2, 0)
    var beam = spot_light(WHITE, NodeId(0))
    beam.penumbra = 2.0
    scene.add_light(beam)
    with assert_raises():
        _ = Lighting(scene)
    var hidden = scene_with_lamp_at(0, 2, 0)
    var bulb = point_light(WHITE, NodeId(0))
    bulb.decay = not_a_number()
    bulb.layers.set(3)
    hidden.add_light(bulb)
    with assert_raises():
        _ = Lighting(hidden, visible=Layers())
    var dim = ambient_light(WHITE)
    dim.intensity = -1.0
    with assert_raises():
        dim.validate()
    # A placeholder the kind never reads is not checked: a directional
    # light's angle is nothing to it.
    var sun = directional_light(WHITE, NodeId(0))
    sun.angle = Angle(not_a_number(), DEGREE)
    sun.validate()


def test_a_cone_too_narrow_to_resolve_is_refused() raises:
    # The fragment compares cosines, and the cosine of a hundredth of a
    # degree rounds to one in Float32: on the axis the surface could not be
    # told from the rim, and a valid light lit nothing on its own axis. A
    # degree resolves, and lights the axis fully.
    with assert_raises():
        _ = spot_light(WHITE, NodeId(0), 1.0, 0.0, Angle(0.01, DEGREE))
    var narrow = spot_at(0, 1, 0, Angle(1.0, DEGREE))
    var on_axis = narrow.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(on_axis.r, Float32(1), atol=TOLERANCE)
    # And the same narrowing after the fact is caught when resolved.
    var scene = scene_with_lamp_at(0, 1, 0)
    var beam = spot_light(WHITE, NodeId(0))
    beam.angle = Angle(0.005, DEGREE)
    scene.add_light(beam)
    with assert_raises():
        _ = Lighting(scene)


# --- the Blinn-Phong highlight ----------------------------------------------


comptime UP_Z = Vector3(0, 0, 1)
comptime WHITE_SHEEN = Vector3(1, 1, 1)


def test_a_highlight_head_on_is_the_lobe_times_the_geometric_term() raises:
    # Light, eye and normal all along z, so the half vector is the normal
    # and both of three.js's dots saturate to one. The lobe is then
    # `shininess * 0.5 + 1` and the geometric term a quarter, and a
    # specular of one leaves the Fresnel weight exactly one. Sixteen
    # quarters is four.
    var sent = blinn_phong(UP_Z, UP_Z, UP_Z, WHITE_SHEEN, 30.0)
    assert_almost_equal(sent.x, Float32(4.0), atol=TOLERANCE)
    assert_almost_equal(sent.y, Float32(4.0), atol=TOLERANCE)
    assert_almost_equal(sent.z, Float32(4.0), atol=TOLERANCE)
    # Twice as shiny is twice as tight a lobe and twice as bright a center.
    var tighter = blinn_phong(UP_Z, UP_Z, UP_Z, WHITE_SHEEN, 62.0)
    assert_almost_equal(tighter.x, Float32(8.0), atol=TOLERANCE)
    # A shininess of zero is the widest lobe three.js allows, and is one.
    var widest = blinn_phong(UP_Z, UP_Z, UP_Z, WHITE_SHEEN, 0.0)
    assert_almost_equal(widest.x, Float32(0.25), atol=TOLERANCE)
    # three.js saturates the dot, so a normal longer than one reflects no
    # more than a unit one does.
    var stretched = blinn_phong(UP_Z, UP_Z, Vector3(0, 0, 2), WHITE_SHEEN, 30.0)
    assert_almost_equal(stretched.x, Float32(4.0), atol=TOLERANCE)


def test_a_highlight_is_tinted_by_the_specular_it_is_given() raises:
    # Each channel on its own, so a green specular gives a green highlight.
    var sent = blinn_phong(UP_Z, UP_Z, UP_Z, Vector3(0, 1, 0), 30.0)
    assert_true(sent.y > 3.9, "the green channel lost its highlight")
    # The other two keep only the Fresnel term, which head on is tiny.
    assert_true(sent.x < 0.01, "a black channel reflected too much")
    assert_true(sent.x > 0, "a black channel reflected nothing at all")


def test_a_black_specular_still_catches_the_grazing_rim() raises:
    # three.js's F_Schlick rises to one at a grazing angle whatever the
    # surface reflects head on. Eye and light a third of a turn apart put
    # the half vector sixty degrees from each, so the Fresnel weight is
    # what is left.
    var aside = Vector3(0.8660254, 0, -0.5)
    var sent = blinn_phong(
        UP_Z, aside, Vector3(0.5, 0, 0.8660254), Vector3(0, 0, 0), 30.0
    )
    assert_true(sent.x > 0, "the rim reflected nothing")
    # Head on the same black surface reflects almost nothing.
    var straight = blinn_phong(UP_Z, UP_Z, UP_Z, Vector3(0, 0, 0), 30.0)
    assert_true(sent.x > straight.x, "the rim was no brighter than head on")


def test_a_surface_turned_away_from_the_half_vector_reflects_nothing() raises:
    # three.js saturates the dot to zero and the lobe follows.
    var behind = blinn_phong(UP_Z, UP_Z, Vector3(0, 0, -1), WHITE_SHEEN, 30.0)
    assert_equal(behind.x, Float32(0))
    assert_equal(behind.y, Float32(0))
    assert_equal(behind.z, Float32(0))
    # Edge on is the boundary and reflects nothing either.
    var edge = blinn_phong(UP_Z, UP_Z, Vector3(1, 0, 0), WHITE_SHEEN, 30.0)
    assert_equal(edge.x, Float32(0))


def test_a_light_opposite_the_eye_leaves_no_half_direction() raises:
    var opposite = blinn_phong(UP_Z, Vector3(0, 0, -1), UP_Z, WHITE_SHEEN, 30.0)
    assert_equal(opposite.x, Float32(0))
    assert_equal(opposite.y, Float32(0))
    assert_equal(opposite.z, Float32(0))


def test_lighting_remembers_where_the_camera_is() raises:
    # A highlight is measured from there, so `Lighting` carries it. The
    # origin by default, which a scene with no phong surface never reads.
    var scene = lit_from(0, 0, 1)
    assert_equal(Lighting(scene).eye.z, Float32(0))
    var placed = Lighting(scene, Layers.all(), Vector3(1, 2, 3))
    assert_equal(placed.eye.x, Float32(1))
    assert_equal(placed.eye.y, Float32(2))
    assert_equal(placed.eye.z, Float32(3))
    assert_equal(Lighting.uniform().eye.z, Float32(0))


def test_a_directional_light_makes_a_highlight_from_where_you_stand() raises:
    # The same surface under the same light, seen from two places: the
    # highlight is four head on and almost nothing from the side, which is
    # the whole difference between a phong surface and a lambert one.
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(WHITE, node, 1.0))
    scene.update()
    var head_on = Lighting(scene, Layers.all(), Vector3(0, 0, 4))
    var sent = head_on.specular_at(UP_Z, ORIGIN, WHITE_SHEEN, 30.0)
    assert_almost_equal(sent.r, Float32(4.0), atol=TOLERANCE)
    assert_equal(sent.a, Float32(1))
    var aside = Lighting(scene, Layers.all(), Vector3(4, 0, 4))
    var dim = aside.specular_at(UP_Z, ORIGIN, WHITE_SHEEN, 30.0)
    assert_true(dim.r < 1.0, "the highlight did not follow the camera")
    assert_true(dim.r > 0, "the highlight vanished entirely")
    # And the diffuse term did not move, because a lambert term cannot.
    assert_equal(
        head_on.intensity_at(UP_Z, ORIGIN).r,
        aside.intensity_at(UP_Z, ORIGIN).r,
    )


def test_a_surface_turned_from_the_light_takes_no_highlight() raises:
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(WHITE, node, 1.0))
    scene.update()
    var lighting = Lighting(scene, Layers.all(), Vector3(0, 0, 4))
    var away = lighting.specular_at(
        Vector3(0, 0, -1), ORIGIN, WHITE_SHEEN, 30.0
    )
    assert_equal(away.r, Float32(0))
    # Edge on to the light is the boundary, and takes none either.
    var edge = lighting.specular_at(Vector3(1, 0, 0), ORIGIN, WHITE_SHEEN, 30.0)
    assert_equal(edge.r, Float32(0))


def test_a_point_light_highlight_falls_off_with_distance() raises:
    var scene = Scene()
    var bulb = Object3D()
    bulb.set_position(0, 0, 2)
    var node = scene.add(bulb^)
    scene.add_light(point_light(WHITE, node, 1.0))
    scene.update()
    var lighting = Lighting(scene, Layers.all(), Vector3(0, 0, 2))
    # Two meters away under the inverse square, so a quarter of the light,
    # and the eye is on the bulb so the half vector is still the normal.
    var sent = lighting.specular_at(UP_Z, ORIGIN, WHITE_SHEEN, 30.0)
    assert_almost_equal(sent.r, Float32(1.0), atol=TOLERANCE)
    # A surface exactly on the bulb has no direction to be lit from. The
    # camera stands further back, so it is the bulb's distance that is zero
    # and not the camera's.
    var behind = Lighting(scene, Layers.all(), Vector3(0, 0, 5))
    var on_it = behind.specular_at(UP_Z, Vector3(0, 0, 2), WHITE_SHEEN, 30.0)
    assert_equal(on_it.r, Float32(0))
    # And a surface turned away from the bulb takes no highlight from it.
    var away = behind.specular_at(Vector3(0, 0, -1), ORIGIN, WHITE_SHEEN, 30.0)
    assert_equal(away.r, Float32(0))


def test_a_spot_light_highlight_stops_at_its_cone() raises:
    var scene = Scene()
    var beam = Object3D()
    beam.set_position(0, 0, 2)
    var node = scene.add(beam^)
    scene.add_light(spot_light(WHITE, node, 1.0, angle=Angle(20.0, DEGREE)))
    scene.update()
    var lighting = Lighting(scene, Layers.all(), Vector3(0, 0, 2))
    var inside = lighting.specular_at(UP_Z, ORIGIN, WHITE_SHEEN, 30.0)
    assert_true(inside.r > 0, "the axis of the cone took no highlight")
    # A meter to the side of a two-meter throw is well past twenty degrees.
    var outside = lighting.specular_at(
        UP_Z, Vector3(2, 0, 0), WHITE_SHEEN, 30.0
    )
    assert_equal(outside.r, Float32(0))
    # A surface on the bulb has no direction, as under a point light, and
    # one turned away takes none either. The camera stands further back so
    # that it is the bulb's distance that is zero.
    var behind = Lighting(scene, Layers.all(), Vector3(0, 0, 5))
    var on_it = behind.specular_at(UP_Z, Vector3(0, 0, 2), WHITE_SHEEN, 30.0)
    assert_equal(on_it.r, Float32(0))
    var away = behind.specular_at(Vector3(0, 0, -1), ORIGIN, WHITE_SHEEN, 30.0)
    assert_equal(away.r, Float32(0))


def test_a_light_with_no_direction_makes_no_highlight() raises:
    # An ambient light has none, and a hemisphere light is an ambient term
    # with a gradient: three.js reflects both diffusely and nothing else.
    var scene = Scene()
    var sky = Object3D()
    sky.set_position(0, 1, 0)
    var node = scene.add(sky^)
    scene.add_light(ambient_light(WHITE, 1.0))
    scene.add_light(hemisphere_light(WHITE, WHITE, node, 1.0))
    scene.update()
    var lighting = Lighting(scene, Layers.all(), Vector3(0, 0, 4))
    var sent = lighting.specular_at(UP_Z, ORIGIN, WHITE_SHEEN, 30.0)
    assert_equal(sent.r, Float32(0))
    assert_equal(sent.g, Float32(0))
    assert_equal(sent.b, Float32(0))
    # They do light it diffusely, or this would prove nothing.
    assert_true(lighting.intensity_at(UP_Z, ORIGIN).r > 1)


def test_a_surface_at_the_camera_takes_no_highlight() raises:
    # There is no direction to be seen along from there.
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(WHITE, node, 1.0))
    scene.update()
    var lighting = Lighting(scene, Layers.all(), ORIGIN)
    var sent = lighting.specular_at(UP_Z, ORIGIN, WHITE_SHEEN, 30.0)
    assert_equal(sent.r, Float32(0))
    assert_equal(sent.a, Float32(1))


# --- a toon ramp ------------------------------------------------------------


def no_ramp() -> List[Float32]:
    """Return the empty ramp, which means three.js's fallback."""
    return List[Float32]()


def unit(x: Float32, y: Float32, z: Float32) -> Vector3:
    """Return a unit vector pointing that way."""
    var facing = Vector3(x, y, z)
    facing.normalize()
    return facing^


def three_tones() -> List[Float32]:
    """Return a ramp of three flat tones: dark, middle and full."""
    var tones = List[Float32]()
    tones.append(0.2)
    tones.append(0.6)
    tones.append(1.0)
    return tones^


def test_a_cosine_maps_onto_the_whole_ramp() raises:
    # three.js reads at `dot * 0.5 + 0.5`, so the ramp covers every angle
    # and not just the lit half. That is why a toon surface never goes
    # black: facing straight away reads the ramp's left end.
    assert_equal(toon_coord(-1.0), Float32(0))
    assert_equal(toon_coord(0.0), Float32(0.5))
    assert_equal(toon_coord(1.0), Float32(1))
    assert_almost_equal(toon_coord(0.5), Float32(0.75), atol=TOLERANCE)


def test_the_fallback_ramp_has_two_tones_and_one_edge() raises:
    # three.js's `mix(vec3(0.7), vec3(1.0), smoothstep(0.7 - fw, 0.7 + fw,
    # coord))`, with the edge hard because a software rasterizer has no
    # neighboring fragment to take `fwidth` against.
    assert_equal(toon_step(0.0), TOON_SHADE)
    assert_equal(toon_step(TOON_EDGE - 0.001), TOON_SHADE)
    assert_equal(toon_step(TOON_EDGE), Float32(1))
    assert_equal(toon_step(1.0), Float32(1))


def test_a_ramp_is_read_as_a_lookup_table_with_its_ends_clamped() raises:
    # Nearest and never wrapped: a ramp is a table, not a picture. Three
    # tones split the range in thirds.
    assert_equal(toon_index(0.0, 3), 0)
    assert_equal(toon_index(0.33, 3), 0)
    assert_equal(toon_index(0.34, 3), 1)
    assert_equal(toon_index(0.67, 3), 2)
    assert_equal(toon_index(1.0, 3), 2)
    # A coordinate outside the range clamps rather than wrapping. Only a
    # hand-built call reaches these, since `toon_coord` cannot leave zero
    # to one, but the kernel indexes memory with the answer.
    assert_equal(toon_index(-0.5, 3), 0)
    assert_equal(toon_index(2.0, 3), 2)
    # One tone is a legal ramp, and every angle reads it.
    assert_equal(toon_index(0.0, 1), 0)
    assert_equal(toon_index(1.0, 1), 0)


def test_a_tone_comes_off_the_ramp_or_off_the_fallback() raises:
    assert_equal(toon_tone(1.0, no_ramp()), Float32(1))
    assert_equal(toon_tone(-1.0, no_ramp()), TOON_SHADE)
    assert_equal(toon_tone(1.0, three_tones()), Float32(1))
    assert_equal(toon_tone(-1.0, three_tones()), Float32(0.2))
    assert_equal(toon_tone(0.0, three_tones()), Float32(0.6))


def test_a_toon_surface_steps_where_a_lambert_one_fades() raises:
    # The whole point of the kind. Two normals a few degrees apart on the
    # same side of the edge read the same tone; a lambert surface reads
    # two different ones.
    var lighting = Lighting(lit_from(0, 0, 1))
    var square = lighting.toon_at(Vector3(0, 0, 1), ORIGIN, no_ramp())
    var tilted = lighting.toon_at(unit(0.2, 0, 1), ORIGIN, no_ramp())
    assert_equal(square.r, Float32(1))
    assert_equal(tilted.r, Float32(1))
    var smooth = lighting.intensity_at(unit(0.2, 0, 1), ORIGIN)
    assert_true(smooth.r < 1, "a lambert surface did not fade at all")
    # And across the edge it steps, rather than passing through the values
    # in between. The edge sits at a cosine of 0.4: these two are a cosine
    # of 0.5 and of 0.3, one either side of it.
    var above = lighting.toon_at(unit(0, 0.8660254, 0.5), ORIGIN, no_ramp())
    var below = lighting.toon_at(unit(0, 0.9539392, 0.3), ORIGIN, no_ramp())
    assert_equal(above.r, Float32(1))
    assert_equal(below.r, TOON_SHADE)


def test_a_toon_surface_turned_away_is_still_lit() raises:
    # three.js's ramp has no zero to clamp at, so a lamp behind the surface
    # reads the ramp's left end. That is what keeps the shaded side flat
    # instead of black, and it is the one place toon and lambert disagree
    # about whether a light counts at all.
    var lighting = Lighting(lit_from(0, 0, 1))
    var away = Vector3(0, 0, -1)
    assert_equal(lighting.intensity_at(away, ORIGIN).r, Float32(0))
    assert_equal(lighting.toon_at(away, ORIGIN, no_ramp()).r, TOON_SHADE)
    assert_equal(lighting.toon_at(away, ORIGIN, three_tones()).r, Float32(0.2))
    # Alpha is not light and stays at one, as everywhere else.
    assert_equal(lighting.toon_at(away, ORIGIN, no_ramp()).a, Float32(1))


def test_a_toon_point_light_is_stepped_and_still_falls_off() raises:
    # The ramp replaces the cosine; the distance still attenuates, because
    # three.js folds the falloff into the light's color before the ramp
    # multiplies it.
    var lighting = bulb_at(0, 2, 0)
    # Two meters below, facing up: full tone, a quarter of the light.
    var below = lighting.toon_at(Vector3(0, 1, 0), ORIGIN, no_ramp())
    assert_almost_equal(below.r, Float32(0.25), atol=TOLERANCE)
    # Facing away: the ramp's low tone, still quartered.
    var away = lighting.toon_at(Vector3(0, -1, 0), ORIGIN, no_ramp())
    assert_almost_equal(away.r, Float32(0.25) * TOON_SHADE, atol=TOLERANCE)
    # A surface exactly on the bulb has no direction to be lit from, and is
    # skipped rather than dividing by zero.
    var on_it = lighting.toon_at(Vector3(0, 1, 0), Vector3(0, 2, 0), no_ramp())
    assert_equal(on_it.r, Float32(0))
    # A ramp of its own is read the same way.
    assert_almost_equal(
        lighting.toon_at(Vector3(0, -1, 0), ORIGIN, three_tones()).r,
        Float32(0.25) * 0.2,
        atol=TOLERANCE,
    )


def test_a_toon_spot_light_is_stepped_inside_its_cone_alone() raises:
    # The cone gates the light as it always did -- three.js's
    # `directLight.visible` -- and the ramp decides what arrives inside it.
    var scene = scene_with_lamp_at(0, 2, 0)
    scene.add_light(spot_light(WHITE, NodeId(0), 1.0, 0.0, Angle(30.0, DEGREE)))
    var lighting = Lighting(scene)
    var inside = lighting.toon_at(Vector3(0, 1, 0), ORIGIN, no_ramp())
    assert_almost_equal(inside.r, Float32(0.25), atol=TOLERANCE)
    # Facing away inside the cone: the low tone, not nothing.
    var shaded_side = lighting.toon_at(Vector3(0, -1, 0), ORIGIN, no_ramp())
    assert_almost_equal(
        shaded_side.r, Float32(0.25) * TOON_SHADE, atol=TOLERANCE
    )
    # Outside the cone nothing arrives, whatever the ramp says.
    var outside = lighting.toon_at(
        Vector3(0, 1, 0), Vector3(4, 0, 0), no_ramp()
    )
    assert_equal(outside.r, Float32(0))
    # And a surface exactly on the bulb is skipped.
    var on_it = lighting.toon_at(Vector3(0, 1, 0), Vector3(0, 2, 0), no_ramp())
    assert_equal(on_it.r, Float32(0))


def test_a_toon_surface_takes_its_indirect_light_unstepped() raises:
    # three.js reflects an ambient light and a hemisphere light through
    # `RE_IndirectDiffuse`, which no ramp touches. So both reach a toon
    # surface exactly as they reach a lambert one.
    var scene = scene_with_lamp_at(0, 4, 0)
    scene.add_light(ambient_light(WHITE, 0.25))
    scene.add_light(hemisphere_light(WHITE, Color(0, 0, 0), NodeId(0), 1.0))
    var lighting = Lighting(scene)
    for facing in [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 0, 0)]:
        assert_equal(
            lighting.toon_at(facing, ORIGIN, no_ramp()).r,
            lighting.intensity_at(facing, ORIGIN).r,
        )
    # Facing the sky: a quarter ambient plus all of the sky.
    var up = lighting.toon_at(Vector3(0, 1, 0), ORIGIN, no_ramp())
    assert_almost_equal(up.r, Float32(1.25), atol=TOLERANCE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
