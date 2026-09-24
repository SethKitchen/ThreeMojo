# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for light probes: `light_probe` in `lights.light`, its place in
`Lighting`, and `lights.light_probe`, three.js's `LightProbeGenerator`.

A probe of a uniform sky must light every surface alike, with the
irradiance pi times the sky's radiance. A probe of a sky that is bright
on one side must light the surfaces facing that side more.
"""

from core.layers import Layers
from core.scene import Scene
from lights.light import (
    AMBIENT,
    LIGHT_PROBE,
    LightKind,
    ambient_light,
    light_probe,
)
from lights.light_probe import light_probe_from_cube, sh_from_cube
from lights.lighting import RECIPROCAL_PI, Lighting
from math.spherical_harmonics3 import SphericalHarmonics3
from math.vector3 import Vector3
from render.cube_texture import POSITIVE_Y, CubeTexture
from render.framebuffer import Color
from render.srgb import SRGB
from render.texture import (
    BILINEAR,
    CLAMP,
    IGNORED,
    REPEAT,
    Texture,
    float_texture,
)
from std.math import inf, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def a_float_cube(
    size: Int, values: List[Float32], alpha: Float32 = 1
) raises -> CubeTexture:
    """Return a cube whose face `f` is gray at `values[f]` everywhere."""
    var faces = List[Texture]()
    for face in range(6):
        var data = List[Float32]()
        for _ in range(size * size):
            data.append(values[face])
            data.append(values[face])
            data.append(values[face])
            data.append(alpha)
        faces.append(
            float_texture(size, size, data^, CLAMP, BILINEAR, False, IGNORED)
        )
    return CubeTexture(faces^)


def a_byte_cube(color: Color) raises -> CubeTexture:
    """Return a cube of 4x4 sRGB faces, every texel `color`."""
    var faces = List[Texture]()
    for _ in range(6):
        var pixels = List[UInt8]()
        for _ in range(16):
            pixels.append(color.r)
            pixels.append(color.g)
            pixels.append(color.b)
            pixels.append(255)
        faces.append(Texture(4, 4, pixels^, CLAMP, BILINEAR, SRGB, False))
    return CubeTexture(faces^)


def test_a_probe_is_a_light_of_its_own_kind() raises:
    var sh = SphericalHarmonics3()
    sh.set_coefficient(0, Vector3(1, 2, 3))
    var probe = light_probe(sh, 0.5)
    assert_equal(probe.kind, LIGHT_PROBE)
    assert_true(LIGHT_PROBE.is_valid())
    assert_true(probe.sh == sh)
    assert_equal(probe.intensity, 0.5)
    assert_equal(probe.layers, Layers())
    # Every other kind carries darkness.
    assert_true(ambient_light(Color(1, 1, 1)).sh == SphericalHarmonics3())


def test_a_probe_with_numbers_it_cannot_use_is_refused() raises:
    var sh = SphericalHarmonics3()
    sh.set_coefficient(4, Vector3(0, inf[DType.float32](), 0))
    with assert_raises():
        _ = light_probe(sh)
    with assert_raises():
        _ = light_probe(SphericalHarmonics3(), -1)
    # A light of another kind is not asked about its harmonics.
    var fill = ambient_light(Color(1, 1, 1))
    fill.sh = sh
    fill.validate()
    # A probe cannot cast a shadow.
    var probe = light_probe(SphericalHarmonics3())
    probe.cast_shadow = True
    with assert_raises():
        probe.validate()


def test_probes_add_their_coefficients_times_their_intensity() raises:
    var one = SphericalHarmonics3()
    one.set_coefficient(0, Vector3(2, 0, 0))
    var two = SphericalHarmonics3()
    two.set_coefficient(0, Vector3(0, 4, 0))
    two.set_coefficient(1, Vector3(1, 1, 1))
    var scene = Scene()
    scene.add_light(light_probe(one, 3))
    scene.add_light(light_probe(two, 0.5))
    # A probe the camera does not see is left out.
    var hidden = light_probe(one, 100)
    hidden.layers = Layers(UInt32(2))
    scene.add_light(hidden)
    scene.update()
    var lighting = Lighting(scene, Layers())
    assert_equal(lighting.probe.coefficient(0).x, 6)
    assert_equal(lighting.probe.coefficient(0).y, 2)
    assert_equal(lighting.probe.coefficient(1).z, 0.5)
    # No probe, no coefficients.
    assert_true(Lighting(Scene()).probe == SphericalHarmonics3())


def test_a_probe_adds_to_the_ambient_term() raises:
    var sh = SphericalHarmonics3()
    sh.set_coefficient(0, Vector3(1, 1, 1))
    sh.set_coefficient(1, Vector3(0.5, 0.5, 0.5))
    var scene = Scene()
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(light_probe(sh))
    scene.update()
    var lighting = Lighting(scene)
    var up = Vector3(0, 1, 0)
    var expected = 0.25 + 0.886227 + 2 * 0.511664 * 0.5
    assert_almost_equal(lighting.ambient_at(up).r, Float32(expected), atol=1e-5)
    # Scaled once, by the reciprocal of pi, on every path a matte or a
    # physical surface takes.
    var scaled = Float32(expected) * RECIPROCAL_PI
    assert_almost_equal(
        lighting.intensity_at(up, Vector3(0, 0, 0)).g, scaled, atol=1e-5
    )
    assert_almost_equal(lighting.indirect_at(up).b, scaled, atol=1e-5)
    assert_almost_equal(
        lighting.toon_at(up, Vector3(0, 0, 0), List[Float32]()).r,
        scaled,
        atol=1e-5,
    )
    # A surface facing down catches less: band one leans the light up.
    var down = lighting.indirect_at(Vector3(0, -1, 0)).r
    assert_true(down < lighting.indirect_at(up).r)


def test_a_uniform_sky_projects_to_band_zero() raises:
    # A sky of radiance two everywhere: band zero is two times sqrt(4 pi),
    # every other band is zero, and the irradiance is two pi whichever way
    # a surface faces.
    var sh = sh_from_cube(a_float_cube(8, [2, 2, 2, 2, 2, 2]))
    assert_almost_equal(sh.coefficient(0).x, Float32(7.0898154), atol=1e-3)
    for index in range(1, 9):
        assert_almost_equal(sh.coefficient(index).y, Float32(0), atol=1e-4)
    for normal in [Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0.6, 0.8)]:
        assert_almost_equal(
            sh.get_irradiance_at(normal).z, Float32(2 * pi), atol=1e-2
        )


def test_a_sky_bright_above_lights_the_top_more() raises:
    var values: List[Float32] = [0, 0, 0, 0, 0, 0]
    values[POSITIVE_Y] = 3
    var sh = sh_from_cube(a_float_cube(8, values))
    var up = sh.get_irradiance_at(Vector3(0, 1, 0)).x
    var side = sh.get_irradiance_at(Vector3(1, 0, 0)).x
    var down = sh.get_irradiance_at(Vector3(0, -1, 0)).x
    assert_true(up > side)
    assert_true(side > down)
    # Band one points the light up the y axis, which is coefficient one.
    assert_true(sh.coefficient(1).x > 0)
    assert_almost_equal(sh.coefficient(3).x, Float32(0), atol=1e-4)
    # Alpha is not light: a translucent cube projects the same.
    var faint = sh_from_cube(a_float_cube(8, values, 0.25))
    assert_true(faint == sh)


def test_a_byte_cube_is_read_in_linear_light() raises:
    # sRGB 188 is linear 0.5, so the irradiance is half of pi.
    var sh = sh_from_cube(a_byte_cube(Color(188, 188, 188)))
    assert_almost_equal(
        sh.get_irradiance_at(Vector3(0, 0, 1)).x,
        Float32(0.5 * pi),
        atol=2e-2,
    )


def test_a_probe_from_a_cube_is_a_light() raises:
    var probe = light_probe_from_cube(a_float_cube(4, [1, 1, 1, 1, 1, 1]), 2)
    assert_equal(probe.kind, LIGHT_PROBE)
    assert_equal(probe.intensity, 2)
    var scene = Scene()
    scene.add_light(probe)
    scene.update()
    # Two times radiance one times pi, over pi.
    assert_almost_equal(
        Lighting(scene).indirect_at(Vector3(0, 1, 0)).g,
        Float32(2),
        atol=1e-2,
    )


def test_a_cube_edited_into_nonsense_is_refused() raises:
    var cube = a_float_cube(4, [1, 1, 1, 1, 1, 1])
    cube.faces[2].set_wrap(REPEAT)
    with assert_raises():
        _ = sh_from_cube(cube)
    with assert_raises():
        _ = light_probe_from_cube(a_float_cube(4, [1, 1, 1, 1, 1, 1]), -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
