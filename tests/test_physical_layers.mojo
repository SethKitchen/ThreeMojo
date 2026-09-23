# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the sheen, the thin film and the stretched lobe.

The reference numbers come from three.js's GLSL, transcribed line for line
into double-precision Python: `BRDF_Sheen`, `IBLSheenBRDF`,
`evalIridescence`, and the anisotropic GGX of
`lights_physical_pars_fragment`.
"""

from lights.physical_layers import (
    NO_ANISOTROPY_TEXEL,
    OUTSIDE_IOR,
    SHEEN_ROUGHNESS_FLOOR,
    PhysicalLayers,
    anisotropic_ggx,
    bent_normal,
    charlie_sheen,
    ibl_sheen,
    iridescence_fresnel,
    iridescence_thickness,
    layers_of,
    sheen_roughness_of,
    sheen_scaling,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import cos, pi, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)

comptime UP = Vector3(0, 0, 1)
comptime GRAY_F0 = Vector3(0.04, 0.04, 0.04)


def _at_sixty() -> Vector3:
    """Return a unit vector sixty degrees from the z axis, in the xz plane."""
    var angle = Float32(pi / 3)
    return Vector3(sin(angle), 0, cos(angle))


def test_no_layers_is_nothing_at_all() raises:
    var none = PhysicalLayers()
    assert_false(none.sheen)
    assert_false(none.anisotropic)
    assert_equal(none.iridescence, Float32(0))
    assert_equal(none.sheen_roughness, Float32(1))


def test_the_charlie_lobe_is_three_js_own_without_its_pi() raises:
    # Half rough, the light sixty degrees off a normal the eye looks down:
    # D_Charlie is 6 * 0.25^2 / 2 and V_Neubelt a quarter.
    var lobe = charlie_sheen(_at_sixty(), UP, UP, Vector3(1, 0.5, 0), 0.5)
    assert_almost_equal(lobe.x, Float32(0.046875), atol=1e-6)
    assert_almost_equal(lobe.y, Float32(0.0234375), atol=1e-6)
    assert_equal(lobe.z, Float32(0))


def test_a_charlie_lobe_of_no_roughness_or_no_half_vector_is_dark() raises:
    var color = Vector3(1, 1, 1)
    assert_equal(charlie_sheen(_at_sixty(), UP, UP, color, 0).x, Float32(0))
    assert_equal(charlie_sheen(-UP, UP, UP, color, 0.5).x, Float32(0))


def test_a_charlie_lobe_seen_and_lit_edge_on_saturates_its_visibility() raises:
    # Both cosines zero: three.js's saturate of one over zero is one.
    var side = Vector3(1, 0, 0)
    var lobe = charlie_sheen(side, side, UP, Vector3(1, 1, 1), 1)
    # D_Charlie at a sine squared of one and a roughness of one: 3 / 2.
    assert_almost_equal(lobe.x, Float32(1.5), atol=1e-6)


def test_the_sheen_integral_is_three_js_fit_on_either_side() raises:
    assert_almost_equal(ibl_sheen(0.5, 0.1), Float32(0.0016770317), atol=1e-6)
    assert_almost_equal(ibl_sheen(0.5, 0.6), Float32(0.0316080826), atol=1e-6)
    # Saturated where the fit runs above one.
    assert_equal(ibl_sheen(0, 0.1), Float32(1))


def test_a_sheen_scales_the_light_under_it_by_its_brightest_channel() raises:
    assert_equal(sheen_scaling(Vector3(0, 0, 0)), Float32(1))
    assert_almost_equal(
        sheen_scaling(Vector3(0.2, 1, 0.5)), Float32(0.843), atol=1e-6
    )


def test_the_sheen_roughness_is_clamped_and_then_mapped() raises:
    assert_equal(sheen_roughness_of(0, 1), SHEEN_ROUGHNESS_FLOOR)
    assert_equal(sheen_roughness_of(2, 1), Float32(1))
    assert_equal(sheen_roughness_of(0.5, 0.5), Float32(0.25))
    assert_equal(sheen_roughness_of(0.5, 0), Float32(0))


def test_a_film_is_the_maximum_unless_a_map_mixes_the_range() raises:
    assert_equal(iridescence_thickness(100, 400, 0.25, False), Float32(400))
    assert_equal(iridescence_thickness(100, 400, 0.25, True), Float32(175))
    assert_equal(iridescence_thickness(100, 400, 0, True), Float32(100))


def test_the_films_fresnel_is_three_js_eval_iridescence() raises:
    var film = iridescence_fresnel(OUTSIDE_IOR, 1.3, 0.8, 400, GRAY_F0)
    assert_equal(film.x, Float32(0))
    assert_almost_equal(film.y, Float32(0.0209204), atol=2e-5)
    assert_almost_equal(film.z, Float32(0.0419515), atol=2e-5)
    # Over a colored metal, every channel with its own index.
    var metal = iridescence_fresnel(
        OUTSIDE_IOR, 1.8, 0.5, 250, Vector3(0.9, 0.5, 0.1)
    )
    assert_almost_equal(metal.x, Float32(0.8737606), atol=2e-4)
    assert_almost_equal(metal.y, Float32(0.0816614), atol=2e-4)
    assert_almost_equal(metal.z, Float32(0.1165443), atol=2e-4)


def test_a_film_of_no_thickness_takes_the_outsides_index() raises:
    var bare = iridescence_fresnel(OUTSIDE_IOR, 1.3, 0.8, 0, GRAY_F0)
    assert_almost_equal(bare.x, Float32(0.0629727), atol=2e-5)
    assert_almost_equal(bare.y, Float32(0.0587829), atol=2e-5)
    assert_almost_equal(bare.z, Float32(0.0581585), atol=2e-5)


def test_a_film_thinner_than_what_is_outside_reflects_totally_or_turns() raises:
    # Denser outside than the film, at a grazing angle: total internal
    # reflection, everything back.
    var total = iridescence_fresnel(1.5, 1.2, 0.3, 300, GRAY_F0)
    assert_equal(total.x, Float32(1))
    assert_equal(total.z, Float32(1))
    # Nearly head on, the first interface turns the phase by pi.
    var turned = iridescence_fresnel(1.5, 1.2, 0.95, 300, GRAY_F0)
    assert_equal(turned.x, Float32(0))
    assert_almost_equal(turned.y, Float32(0.0225467), atol=2e-5)
    assert_almost_equal(turned.z, Float32(0.0486669), atol=2e-5)


def _stretched(
    alpha_t: Float32, tangent: Vector3, bitangent: Vector3
) -> PhysicalLayers:
    """Return layers with only a stretch, along the given frame."""
    var layers = PhysicalLayers()
    layers.anisotropic = True
    layers.anisotropy = 1
    layers.tangent = tangent
    layers.bitangent = bitangent
    layers.alpha_t = alpha_t
    return layers


def test_an_unstretched_anisotropic_lobe_is_the_isotropic_one() raises:
    # alphaT equal to alpha along an orthonormal frame: D_GGX and
    # V_GGX_SmithCorrelated exactly, without the reciprocal pi.
    var light = _at_sixty()
    var eye = Vector3(-0.6, 0, 0.8)
    var half = light + eye
    half.normalize()
    var alpha = Float32(0.25)
    var layers = _stretched(alpha, Vector3(1, 0, 0), Vector3(0, 1, 0))
    var dot_nl = light.z
    var dot_nv = eye.z
    var dot_nh = half.z
    var product = anisotropic_ggx(
        light, eye, half, dot_nl, dot_nv, dot_nh, alpha, layers
    )
    var a2 = alpha * alpha
    var gv = dot_nl * sqrt(a2 + (1 - a2) * dot_nv * dot_nv)
    var gl = dot_nv * sqrt(a2 + (1 - a2) * dot_nl * dot_nl)
    var denominator = dot_nh * dot_nh * (a2 - 1) + 1
    var expected = 0.5 / (gv + gl) * a2 / (denominator * denominator)
    assert_almost_equal(product, expected, atol=1e-5)


def test_a_stretched_lobe_reaches_further_along_its_tangent() raises:
    # The same light swung along the stretch and across it: the lobe
    # reaches it along the stretch and barely across.
    var eye = UP
    var along = _at_sixty()
    var across = Vector3(0, along.x, along.z)
    var layers = _stretched(1, Vector3(1, 0, 0), Vector3(0, 1, 0))
    var reach = List[Float32]()
    for light in [along, across]:
        var half = light + eye
        half.normalize()
        reach.append(
            anisotropic_ggx(
                light, eye, half, light.z, eye.z, half.z, 0.0625, layers
            )
        )
    assert_true(reach[0] > 50 * reach[1], "the stretch reached no further")


def test_the_environment_is_read_along_a_bent_normal() raises:
    # No stretch reads along the normal.
    var eye = Vector3(0.6, 0, 0.8)
    assert_equal(bent_normal(UP, eye, PhysicalLayers(), 0.5).x, Float32(0))
    # A full stretch on a smooth surface bends the normal toward the
    # eye's own plane across the bitangent.
    var layers = _stretched(1, Vector3(1, 0, 0), Vector3(0, 1, 0))
    var bent = bent_normal(UP, eye, layers, 0.1)
    assert_true(bent.x > 0.3, "the normal did not bend toward the eye")
    assert_almost_equal(bent.length(), Float32(1), atol=1e-6)
    # Looking straight along the bitangent leaves no plane: the normal.
    var along = bent_normal(UP, Vector3(0, 1, 0), layers, 0.1)
    assert_almost_equal(along.z, Float32(1), atol=1e-6)


def _resolved(
    sheen: Vector3 = Vector3(0, 0, 0),
    iridescence: Float32 = 0,
    thickness: Float32 = 400,
    anisotropy: Vector2 = Vector2(0, 0),
    texel: Vector3 = NO_ANISOTROPY_TEXEL,
) -> PhysicalLayers:
    """Return `layers_of` on a flat surface the eye looks down on, with a
    frame along x and y."""
    return layers_of(
        sheen,
        0.5,
        iridescence,
        1.3,
        thickness,
        anisotropy,
        texel,
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        UP,
        Vector3(0, 0.6, 0.8),
        GRAY_F0,
        0.5,
    )


def test_layers_of_nothing_is_no_layers() raises:
    var none = _resolved()
    assert_false(none.sheen)
    assert_equal(none.iridescence, Float32(0))
    assert_false(none.anisotropic)


def test_a_sheen_is_on_once_its_color_is_not_black() raises:
    var cloth = _resolved(sheen=Vector3(0, 0, 0.5))
    assert_true(cloth.sheen)
    assert_equal(cloth.sheen_color.z, Float32(0.5))
    assert_equal(cloth.sheen_roughness, Float32(0.5))


def test_a_film_needs_a_thickness_and_is_saturated() raises:
    assert_equal(_resolved(iridescence=1, thickness=0).iridescence, Float32(0))
    var film = _resolved(iridescence=1)
    assert_equal(film.iridescence, Float32(1))
    var expected = iridescence_fresnel(OUTSIDE_IOR, 1.3, 0.8, 400, GRAY_F0)
    assert_equal(film.iridescence_fresnel.y, expected.y)
    assert_equal(_resolved(iridescence=2).iridescence, Float32(1))


def test_a_stretch_with_no_map_follows_its_own_vector() raises:
    # A strength of a half at a quarter turn: along y, at a half.
    var layers = _resolved(anisotropy=Vector2(0, 0.5))
    assert_true(layers.anisotropic)
    assert_equal(layers.anisotropy, Float32(0.5))
    assert_equal(layers.tangent.y, Float32(1))
    assert_equal(layers.tangent.x, Float32(0))
    assert_equal(layers.bitangent.x, Float32(-1))
    # three.js's `mix( alpha, 1, anisotropy^2 )`, alpha a quarter.
    assert_equal(layers.alpha_t, Float32(0.25 * 0.75 + 0.25))


def test_a_stretch_map_turns_and_scales_the_vector() raises:
    # The map's red and green turn by a quarter, its blue halves it.
    var layers = _resolved(anisotropy=Vector2(1, 0), texel=Vector3(0.5, 1, 0.5))
    assert_almost_equal(layers.anisotropy, Float32(0.5), atol=1e-6)
    assert_almost_equal(layers.tangent.y, Float32(1), atol=1e-6)
    # A map of no strength leaves the stretch on, at nothing, along x.
    var flat = _resolved(anisotropy=Vector2(1, 0), texel=Vector3(1, 0.5, 0))
    assert_true(flat.anisotropic)
    assert_equal(flat.anisotropy, Float32(0))
    assert_equal(flat.tangent.x, Float32(1))
    assert_equal(flat.alpha_t, Float32(0.25))
    # A vector longer than one is saturated.
    var long = _resolved(anisotropy=Vector2(2, 0))
    assert_equal(long.anisotropy, Float32(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
