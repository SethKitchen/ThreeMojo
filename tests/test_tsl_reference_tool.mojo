# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The TSL reference gives the numpy transcription's values.

The expected text is what the numpy transcription printed with numpy 2.5.
"""

from std.memory import bitcast
from std.testing import TestSuite, assert_equal

from tools.tsl_reference import (
    cos32,
    half_bits,
    log32,
    pow32,
    report,
    sin32,
)


def test_the_values_match_the_numpy_transcription() raises:
    assert_equal(
        report(),
        (
            "hash 0 0.030199997127056122\nhash 1 0.6591631174087524\nhash 7 "
            "0.49376022815704346\nhash 12345 0.9545696377754211\nhash 16777215 "
            "0.16074468195438385\nbits 1.0 0x3f800000 0 16256\nbits -2.5 "
            "0xc0200000 0 49184\nbits 0.1 0x3dcccccd 52429 15820\nbits 8.0 "
            "0x41000000 0 16640\nbits 0.99999994 0x3f7fffff 65535 16255\nbits "
            "3e+38 0x7f61b1e6 45542 32609\nbits 1.1754944e-38 0x800000 0 128\n"
            "bits 123456.789 0x47f12065 8293 18417\nhalf 1.0 0x3c00\nhalf -2.0 "
            "0xc000\nhalf 65504.0 0x7bff\nhalf 65519.0 0x7bff\nhalf 65520.0 "
            "0x7c00\nhalf 1e-05 0xa8\nhalf 0.1 0x2e66\nhalf 6.1035156e-05 "
            "0x400\nhalf -0.33333334 0xb555\nhalf 5.9604645e-08 0x1\nhalf "
            "2.9802322e-08 0x0\nhalf 8.940697e-08 0x2\ntriNoise3D (0.3, 0.7, "
            "1.1) 1.0 0.5 0.402042955160141\ntriNoise3D (2.5, -1.25, 0.4) 0.3 "
            "3.0 0.06113876402378082\nsnoise (0.3, 0.7, 1.1) "
            "0.44135192036628723\nsnoiseVec3 (0.3, 0.7, 1.1) "
            "['0.08935171365737915', '-0.31853407621383667', "
            "'0.5562267899513245']\ncurl (0.3, 0.7, 1.1) "
            "['2.2955527305603027', '-0.7378667593002319', "
            "'-1.6635587215423584']\nsnoise (2.5, -1.25, 0.4) "
            "0.3145197629928589\nsnoiseVec3 (2.5, -1.25, 0.4) "
            "['0.27860206365585327', '-0.5938605666160583', "
            "'0.792390763759613']\ncurl (2.5, -1.25, 0.4) "
            "['-4.0702667236328125', '1.4919123649597168', "
            "'1.5741939544677734']\nsnoise (-3.7, 5.2, 0.05) "
            "0.5830848217010498\nsnoiseVec3 (-3.7, 5.2, 0.05) "
            "['0.426505446434021', '-0.26778411865234375', "
            "'0.6214171648025513']\ncurl (-3.7, 5.2, 0.05) "
            "['-1.1120107173919678', '4.447781562805176', "
            "'2.1441240310668945']\nvoronoi2d (0.3, 0.7) 0.0 "
            "0.07999999076128006\nhash2d (0.3, 0.7) ['0.1779956817626953', "
            "'0.9955635070800781']\nvoronoi2d (2.5, -1.25) 1.5 "
            "0.312418133020401\nhash2d (2.5, -1.25) ['0.09308719635009766', "
            "'0.5291576385498047']\nvoronoi3d (0.3, 0.7, 1.1) 0.0 "
            "0.23083476722240448\nhash3d (0.3, 0.7, 1.1) "
            "['0.6703910827636719', '0.22127437591552734', "
            "'0.10313200950622559']\nvoronoi3d (2.5, -1.25, 0.4) 1.5 "
            "0.5298106074333191\nhash3d (2.5, -1.25, 0.4) "
            "['0.9598846435546875', '0.739870548248291', "
            "'0.9663488268852234']\nrnoise (0.25, 0.75) 0 (64, 32) 0 "
            "['0.7542152404785156', '0.8825645446777344', "
            "'0.9747505187988281', '0.703155517578125']\nrnoise (0.6, 0.1) 3 "
            "(800, 600) 2 ['0.22339630126953125', '0.15919876098632812', "
            "'0.43819427490234375', '0.728118896484375']\nvndf "
            "['0.04973072186112404', '0.4235121011734009', "
            "'0.9045243263244629']\nd_gtr 0.29429537057876587\nsmith_g "
            "0.9776181578636169\npdf 0.21213679015636444\ndominant "
            "0.9914836287498474\nggx L ['-0.021214423701167107', "
            "'0.46544983983039856', '0.8848199248313904']\nggx w "
            "['0.28680139780044556', '0.17131094634532928', "
            "'0.08469309657812119']\nggx pdf nov a 0.14168685674667358 "
            "0.7680000066757202 0.25\nggx f0 ['0.2980000078678131', "
            "'0.17800000309944153', '0.08799999952316284']\n"
        ),
    )


def test_a_half_too_large_is_infinity() raises:
    assert_equal(half_bits(65520.0), 0x7C00)
    assert_equal(half_bits(-1.0e6), 0xFC00)
    assert_equal(half_bits(1.0e300), 0x7C00)
    assert_equal(half_bits(-0.0), 0x8000)
    assert_equal(half_bits(Float64.MAX), 0x7C00)
    assert_equal(half_bits(-Float64.MAX), 0xFC00)


def test_a_half_of_a_special_value() raises:
    var inf = Float64(1) / Float64(0)
    assert_equal(half_bits(inf), 0x7C00)
    assert_equal(half_bits(-inf), 0xFC00)
    assert_equal(half_bits(inf - inf) & 0x7E00, 0x7E00)
    # Below half the smallest subnormal, a value rounds to zero.
    assert_equal(half_bits(1.0e-300), 0)
    assert_equal(half_bits(5.0e-324), 0)


def test_sine_and_cosine_follow_the_quadrant() raises:
    assert_equal(sin32(0), Float32(0))
    assert_equal(cos32(0), Float32(1))
    # numpy's kernel gives these bits for pi/2 and pi in float32.
    assert_equal(
        bitcast[DType.uint32](sin32(Float32(1.5707963705062866))),
        UInt32(0x3F800000),
    )
    assert_equal(
        bitcast[DType.uint32](cos32(Float32(3.1415927410125732))),
        UInt32(0xBF800000),
    )


def test_a_large_angle_goes_to_the_c_library() raises:
    # Above the kernel's limits, numpy calls sinf and cosf. The bits are
    # numpy 2.5's.
    assert_equal(
        bitcast[DType.uint32](sin32(Float32(200000))), UInt32(0xBD92555F)
    )
    assert_equal(
        bitcast[DType.uint32](cos32(Float32(100000))), UInt32(0xBF7FD61C)
    )


def test_the_logarithm_of_powers_of_two() raises:
    assert_equal(log32(1), Float32(0))
    assert_equal(log32(2), Float32(0.6931471824645996))
    assert_equal(log32(0.5), Float32(-0.6931471824645996))


def test_power_takes_numpy_s_exact_paths() raises:
    assert_equal(pow32(3, 2), Float32(9))
    assert_equal(pow32(3, 1), Float32(3))
    assert_equal(pow32(3, 0), Float32(1))
    assert_equal(pow32(9, 0.5), Float32(3))
    assert_equal(pow32(4, -1), Float32(0.25))
    assert_equal(pow32(2, 3), Float32(8))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
