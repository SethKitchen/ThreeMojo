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

from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from lights.light import (
    AMBIENT,
    DIRECTIONAL,
    POINT,
    Light,
    LightKind,
    ambient_light,
    directional_light,
    point_light,
)
from lights.lighting import Lighting
from math.vector3 import Vector3
from units.si import Angle, DEGREE
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


def test_a_light_carries_its_kind_and_colour() raises:
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
    # And a mid-grey light is decoded before being scaled: byte 128 is about
    # 0.2158 of the light.
    var grey = ambient_light(Color(128, 128, 128)).radiance()
    assert_almost_equal(grey.r, Float32(0.215861), atol=Float64(1e-5))


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


def test_a_face_turned_towards_the_light_keeps_its_colour() raises:
    var lighting = Lighting(lit_from(0, 1, 0))
    var lit = shaded(lighting, Color(200, 100, 50), Vector3(0, 1, 0)).encode()
    assert_equal(lit.r, UInt8(200))


def test_a_face_turned_away_gets_only_the_ambient() raises:
    # A quarter of the *light* of byte 200 displays as 106 -- not a quarter
    # of the byte, which would be 50. Dimming the encoded value is the
    # classic colour-space error: it makes shadows far too dark.
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


def test_a_coloured_light_tints_the_surface() raises:
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


def test_uniform_lighting_leaves_a_colour_alone() raises:
    # The identity for the multiply a fragment does, and the default both
    # rasterizers take. The same idea as the blank texture sampling opaque
    # white: it makes "no lighting" a value rather than a branch, so a
    # hand-built triangle asking about coverage or depth gets the colours it
    # passed in rather than black.
    var plain = Lighting.uniform()
    assert_equal(plain.count(), 0)
    var arriving = plain.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(arriving.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(arriving.b, Float32(1), atol=TOLERANCE)
    # Whichever way the surface faces: there is no direction in it.
    var behind = plain.intensity_at(Vector3(0, -1, 0), ORIGIN)
    assert_almost_equal(behind.g, Float32(1), atol=TOLERANCE)
    # And a surface keeps its own colour exactly.
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
    # Two metres below the bulb, facing up: a quarter of it.
    var below = lighting.intensity_at(Vector3(0, 1, 0), ORIGIN)
    assert_almost_equal(below.r, Float32(0.25), atol=TOLERANCE)
    # One metre away: all of it.
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
    # Cut off at four metres, measured at two: the inverse square quarter is
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
    # Five centimetres away the inverse square would be four hundred; the
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


def test_point_light_shades_a_colour_at_a_position() raises:
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
    scene.add_light(Light(LightKind(7), WHITE, 1.0, NO_PARENT, 0.0, 0.0))
    with assert_raises():
        _ = Lighting(scene)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
