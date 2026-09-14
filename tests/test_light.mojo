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
    Light,
    ambient_light,
    directional_light,
)
from lights.lighting import Lighting
from math.vector3 import Vector3
from units.si import Angle, DEGREE
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-6)
comptime WHITE = Color(255, 255, 255)


def scene_with_lamp_at(x: Float32, y: Float32, z: Float32) raises -> Scene:
    """Return a scene whose only node sits at a point, ready to light from."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(x, y, z)
    _ = scene.add(lamp^)
    scene.update()
    return scene^


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
    var shaded = lighting.shade(Color(200, 100, 50), Vector3(0, 1, 0))
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


def test_an_unknown_light_kind_is_rejected() raises:
    var scene = scene_with_lamp_at(0, 1, 0)
    scene.add_light(Light(9, WHITE, 1.0, NodeId(0)))
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
    var lit = lighting.shade(Color(200, 100, 50), Vector3(0, 1, 0)).encode()
    assert_equal(lit.r, UInt8(200))


def test_a_face_turned_away_gets_only_the_ambient() raises:
    # A quarter of the *light* of byte 200 displays as 106 -- not a quarter
    # of the byte, which would be 50. Dimming the encoded value is the
    # classic colour-space error: it makes shadows far too dark.
    var scene = lit_from(0, 1, 0)
    scene.add_light(ambient_light(WHITE, 0.25))
    var lighting = Lighting(scene)
    var dim = lighting.shade(Color(200, 100, 50), Vector3(0, -1, 0)).encode()
    assert_equal(dim.r, UInt8(106))


def test_lambert_falls_off_with_the_angle() raises:
    # Ninety degrees away catches nothing; the surface is edge-on.
    var lighting = Lighting(lit_from(0, 1, 0))
    var edge = lighting.shade(Color(200, 0, 0), Vector3(1, 0, 0)).encode()
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
    var lit = lighting.shade(WHITE, Vector3(0, 1, 0)).encode()
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
    var lit = lighting.shade(WHITE, Vector3(0, 1, 0)).encode()
    assert_equal(lit.r, UInt8(255))
    assert_equal(lit.g, UInt8(0))
    assert_equal(lit.b, UInt8(0))


def test_a_blue_ambient_tints_the_shadows() raises:
    var scene = Scene()
    scene.add_light(ambient_light(Color(0, 0, 255), 0.5))
    var lighting = Lighting(scene)
    var shadow = lighting.shade(WHITE, Vector3(0, -1, 0)).encode()
    assert_equal(shadow.r, UInt8(0))
    assert_true(shadow.b > 180)


def test_a_fully_lit_white_face_clamps_rather_than_wrapping() raises:
    # Rounding pushes 255 to 255.5, which must clamp rather than overflow.
    var lighting = Lighting(lit_from(0, 1, 0))
    var lit = lighting.shade(WHITE, Vector3(0, 1, 0)).encode()
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
    var over = lighting.shade(WHITE, Vector3(0, 1, 0))
    assert_almost_equal(over.r, Float32(2), atol=TOLERANCE)
    assert_equal(over.encode().r, UInt8(255))


def test_shading_preserves_alpha() raises:
    var lighting = Lighting(lit_from(0, 1, 0))
    var shaded = lighting.shade(
        Color(200, 100, 50, 128), Vector3(0, 1, 0)
    ).encode()
    assert_equal(shaded.a, UInt8(128))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
