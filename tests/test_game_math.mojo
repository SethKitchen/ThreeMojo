# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The arithmetic the renderers share: each width gives the scalar bits,
and the fast sine agrees with the C library's."""

from core.fog import EXP2_FOG, exp2_veil, fog_factor
from render.game_math import GAME_LANES, fast_sin, hemisphere_share, lambert
from render.framebuffer import FloatColor
from render.tonemap import (
    ACES_FILMIC_TONE_MAPPING,
    aces_fit,
    aces_tone,
    saturate_lanes,
    tone_map,
)
from std.math import sin
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)

comptime W = SIMD[DType.float32, GAME_LANES]


def _ramp(low: Float32, step: Float32) -> W:
    """Return lanes from `low`, `step` apart."""
    var out = W(0)
    for i in range(GAME_LANES):
        out[i] = low + Float32(i) * step
    return out


def _within_two_ulps(left: Float32, right: Float32) -> Bool:
    """Return whether two finite values are at most two float32 steps apart.

    `x86-64-v3` contracts `a * b + c` inside the sealed ACES curve. A wide
    lane and the scalar call can differ by those two steps. A sign change
    or a larger gap is a different result.

    Args:
        left: One result.
        right: The other result.

    Returns:
        True when the bits match or the gap is 1 or 2.
    """
    if left == right:
        return True
    if (left < 0) != (right < 0):
        return False
    var a = Int(bitcast[DType.uint32](abs(left)))
    var b = Int(bitcast[DType.uint32](abs(right)))
    var gap = a - b
    if gap < 0:
        gap = -gap
    return gap <= 2


def test_each_lane_gives_the_scalar_bits() raises:
    var v = _ramp(-0.5, 0.37)
    var fitted = aces_fit[GAME_LANES](v)
    var held = saturate_lanes[GAME_LANES](v)
    var toned = aces_tone[GAME_LANES](v, v * 0.5, v * 0.25, 0.8)
    var veil = exp2_veil[GAME_LANES](0.05, v * 20)
    for i in range(GAME_LANES):
        var x = SIMD[DType.float32, 1](v[i])
        assert_equal(fitted[i], aces_fit[1](x)[0])
        assert_equal(held[i], saturate_lanes[1](x)[0])
        var one = aces_tone[1](x, x * 0.5, x * 0.25, 0.8)
        assert_true(_within_two_ulps(toned[0][i], one[0][0]))
        assert_true(_within_two_ulps(toned[1][i], one[1][0]))
        assert_true(_within_two_ulps(toned[2][i], one[2][0]))
        assert_equal(veil[i], exp2_veil[1](0.05, x * 20)[0])
    assert_equal(held[0], 0)
    assert_equal(held[GAME_LANES - 1], 1)


def test_the_tone_map_and_the_fog_use_the_shared_arithmetic() raises:
    var c = tone_map(FloatColor(0.7, 0.4, 0.2), ACES_FILMIC_TONE_MAPPING, 1.0)
    var lanes = aces_tone[1](0.7, 0.4, 0.2, 1.0)
    assert_equal(c.r, lanes[0][0])
    assert_equal(c.g, lanes[1][0])
    assert_equal(c.b, lanes[2][0])
    assert_equal(fog_factor(EXP2_FOG, 7, 0, 0, 0.1), exp2_veil[1](0.1, 7.0)[0])


def test_the_fast_sine_agrees_with_the_library() raises:
    var worst = Float32(0)
    for k in range(400):
        var angles = _ramp(Float32(k) * 9.7 - 1900, 0.613)
        var got = fast_sin[GAME_LANES](angles)
        for i in range(GAME_LANES):
            worst = max(worst, abs(got[i] - sin(angles[i])))
    assert_true(worst < 2.0e-6)


def test_the_light_shares_face_the_light() raises:
    var up = SIMD[DType.float32, 4](0, 1, 0, 0)
    var nx = W(0)
    var ny = _ramp(-1, 2.0 / 15.0)
    var nz = W(0)
    var share = hemisphere_share[GAME_LANES](nx, ny, nz, up)
    var catch = lambert[GAME_LANES](nx, ny, nz, up)
    assert_almost_equal(share[0], 0, atol=1e-6)
    assert_almost_equal(share[GAME_LANES - 1], 1, atol=1e-6)
    assert_equal(catch[0], 0)
    assert_almost_equal(catch[GAME_LANES - 1], 1, atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
