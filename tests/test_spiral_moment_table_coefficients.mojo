# ADAPTED table-lookup control. Original oracle words, fixtures,
# assertions and the five-second gate are retained. Only imports,
# coefficient access and the optional lookup-unit debit differ.
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# GENERATED source-only controls; not compiled or run by the oracle author.
# Immutable words come from derive_controls.py, direct exact-rational quadrature.
# Never alter the TestSuite default per-test five-second duration gate.

from extensions.carla.curve_bounds import _geometry_distance, _spiral_counts, _reference_jet
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL, LINE, _GL_NODES
from extensions.carla.curve_trig import _INV_HALF_PI, _PHASE_LIMIT
from extensions.carla.spiral_moment_table import (
    _SpiralMomentProof, _try_lookup_spiral_moments,
    _try_spiral_moment_expansion, _all_spiral_nodes_quadrant_zero,
)
from math.vector3 import Vector3
from std.math import floor, inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_true, assert_false, assert_equal


def _f64(word: UInt64) -> Float64:
    return bitcast[DType.float64](word)


def _encloses(bound: _Interval, low: UInt64, high: UInt64) raises:
    assert_true(bound.is_finite())
    assert_true(bound.contains(_f64(low)))
    assert_true(bound.contains(_f64(high)))


def _same_interval(one: _Interval, two: _Interval) raises:
    assert_equal(bitcast[DType.uint64](one.low), bitcast[DType.uint64](two.low))
    assert_equal(bitcast[DType.uint64](one.high), bitcast[DType.uint64](two.high))


def _same_jet(one: _Jet, two: _Jet) raises:
    _same_interval(one.value, two.value)
    _same_interval(one.first, two.first)
    _same_interval(one.second, two.second)
    assert_equal(bitcast[DType.uint64](one.error), bitcast[DType.uint64](two.error))


def _each_original_node_quadrant_zero(geometry: RoadGeometry, d: _Jet, pieces: Int) raises:
    # Independent enumeration of the original rounded operation graph.
    # The proof's constant-time envelope is not reused to establish this fact.
    var nodes = materialize[_GL_NODES]()
    var rate = _Jet.constant((geometry.curvature_end - geometry.curvature_start) / geometry.length)
    var step = d / _Jet.constant(Float64(pieces))
    for piece in range(pieces):
        var start = step * _Jet.constant(Float64(piece))
        for i in range(5):
            var t = start + step * _Jet.constant(0.5) * _Jet.constant(1.0 + nodes[i])
            var theta = _Jet.constant(geometry.heading) + t * (
                _Jet.constant(geometry.curvature_start) + _Jet.constant(0.5) * rate * t
            )
            var phase = theta.rounded_value()
            assert_true(phase.is_finite())
            assert_true(phase.magnitude() <= _PHASE_LIMIT)
            var selection = (theta * _Jet.constant(_INV_HALF_PI) + _Jet.constant(0.5)).rounded_value()
            assert_equal(floor(selection.low), 0.0)
            assert_equal(floor(selection.high), 0.0)


def _proof(count: Int) raises -> _SpiralMomentProof:
    var spent = 0
    var found = _try_lookup_spiral_moments(count, spent, 22)
    if not found:
        raise Error("Expected bounded count payload")
    assert_equal(spent, 22)
    return found.value().copy()


def _geometry() raises -> RoadGeometry:
    var result = RoadGeometry(SPIRAL, 0.0, 0.0, 100.0, 0.0, 20.0)
    result.curvature_end = 0.05
    return result^



def test_exact_count_1_coefficients() raises:
    var proof = _proof(1)
    _encloses(proof.coefficient(False, 0), UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(proof.coefficient(False, 1), UInt64(0xBFB9999999999999), UInt64(0xBFB9999999999998))
    _encloses(proof.coefficient(False, 2), UInt64(0x3F72F684BDA12F65), UInt64(0x3F72F684BDA12F66))
    _encloses(proof.coefficient(False, 3), UInt64(0xBF1BFF7537CA47FF), UInt64(0xBF1BFF7537CA47FE))
    _encloses(proof.coefficient(False, 4), UInt64(0x3EB859BA6A404194), UInt64(0x3EB859BA6A404195))
    _encloses(proof.coefficient(False, 5), UInt64(0xBE4B90465AC514BE), UInt64(0xBE4B90465AC514BD))
    _encloses(proof.coefficient(False, 6), UInt64(0x3DD5B62AEA85CBDD), UInt64(0x3DD5B62AEA85CBDE))
    _encloses(proof.coefficient(False, 7), UInt64(0xBD5907D83D18103A), UInt64(0xBD5907D83D181039))
    _encloses(proof.coefficient(False, 8), UInt64(0x3CD5F7CC2AB4E47C), UInt64(0x3CD5F7CC2AB4E47D))
    _encloses(proof.coefficient(False, 9), UInt64(0xBC4E4B08B4586127), UInt64(0xBC4E4B08B4586126))
    _encloses(proof.coefficient(False, 10), UInt64(0x3BC0D4BDF483BB65), UInt64(0x3BC0D4BDF483BB66))
    _encloses(proof.coefficient(True, 0), UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556))
    _encloses(proof.coefficient(True, 1), UInt64(0xBF98618618618616), UInt64(0xBF98618618618615))
    _encloses(proof.coefficient(True, 2), UInt64(0x3F48D2E7EED59D6B), UInt64(0x3F48D2E7EED59D6C))
    _encloses(proof.coefficient(True, 3), UInt64(0xBEEBB1845FC9B189), UInt64(0xBEEBB1845FC9B188))
    _encloses(proof.coefficient(True, 4), UInt64(0x3E833D4E779AF2EE), UInt64(0x3E833D4E779AF2EF))
    _encloses(proof.coefficient(True, 5), UInt64(0xBE1209B3A4F5256D), UInt64(0xBE1209B3A4F5256C))
    _encloses(proof.coefficient(True, 6), UInt64(0x3D982CD206F6E1C2), UInt64(0x3D982CD206F6E1C3))
    _encloses(proof.coefficient(True, 7), UInt64(0xBD1836090ADA71E7), UInt64(0xBD1836090ADA71E6))
    _encloses(proof.coefficient(True, 8), UInt64(0x3C92C47E5E54FDB1), UInt64(0x3C92C47E5E54FDB2))
    _encloses(proof.coefficient(True, 9), UInt64(0xBC072A5DE37A8E01), UInt64(0xBC072A5DE37A8E00))
    _encloses(proof.coefficient(True, 10), UInt64(0x3B774B5C52353452), UInt64(0x3B774B5C52353453))


def test_exact_count_2_coefficients() raises:
    var proof = _proof(2)
    _encloses(proof.coefficient(False, 0), UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(proof.coefficient(False, 1), UInt64(0xBFB999999999999A), UInt64(0xBFB9999999999999))
    _encloses(proof.coefficient(False, 2), UInt64(0x3F72F684BDA12F67), UInt64(0x3F72F684BDA12F68))
    _encloses(proof.coefficient(False, 3), UInt64(0xBF1C01BF6A6C8AFD), UInt64(0xBF1C01BF6A6C8AFC))
    _encloses(proof.coefficient(False, 4), UInt64(0x3EB879E2F88F1BED), UInt64(0x3EB879E2F88F1BEE))
    _encloses(proof.coefficient(False, 5), UInt64(0xBE4C2CD879091889), UInt64(0xBE4C2CD879091888))
    _encloses(proof.coefficient(False, 6), UInt64(0x3DD6EEF99E8B9699), UInt64(0x3DD6EEF99E8B969A))
    _encloses(proof.coefficient(False, 7), UInt64(0xBD5BC120C380F2EE), UInt64(0xBD5BC120C380F2ED))
    _encloses(proof.coefficient(False, 8), UInt64(0x3CD9E96FD7FCF8A0), UInt64(0x3CD9E96FD7FCF8A1))
    _encloses(proof.coefficient(False, 9), UInt64(0xBC5333B92409AA34), UInt64(0xBC5333B92409AA33))
    _encloses(proof.coefficient(False, 10), UInt64(0x3BC71BCAA8BA1C37), UInt64(0x3BC71BCAA8BA1C38))
    _encloses(proof.coefficient(True, 0), UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556))
    _encloses(proof.coefficient(True, 1), UInt64(0xBF98618618618618), UInt64(0xBF98618618618617))
    _encloses(proof.coefficient(True, 2), UInt64(0x3F48D30186C88232), UInt64(0x3F48D30186C88233))
    _encloses(proof.coefficient(True, 3), UInt64(0xBEEBBD714721DABC), UInt64(0xBEEBBD714721DABB))
    _encloses(proof.coefficient(True, 4), UInt64(0x3E8377283C1FF648), UInt64(0x3E8377283C1FF649))
    _encloses(proof.coefficient(True, 5), UInt64(0xBE12B458C4A07528), UInt64(0xBE12B458C4A07527))
    _encloses(proof.coefficient(True, 6), UInt64(0x3D9A1D6852216324), UInt64(0x3D9A1D6852216325))
    _encloses(proof.coefficient(True, 7), UInt64(0xBD1BA5CDE8372ECF), UInt64(0xBD1BA5CDE8372ECE))
    _encloses(proof.coefficient(True, 8), UInt64(0x3C96ECA44A92FFE1), UInt64(0x3C96ECA44A92FFE2))
    _encloses(proof.coefficient(True, 9), UInt64(0xBC0E89BD1F5B80FD), UInt64(0xBC0E89BD1F5B80FC))
    _encloses(proof.coefficient(True, 10), UInt64(0x3B80AD76CF0FD991), UInt64(0x3B80AD76CF0FD992))


def test_exact_count_3_coefficients() raises:
    var proof = _proof(3)
    _encloses(proof.coefficient(False, 0), UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(proof.coefficient(False, 1), UInt64(0xBFB999999999999A), UInt64(0xBFB9999999999999))
    _encloses(proof.coefficient(False, 2), UInt64(0x3F72F684BDA12F67), UInt64(0x3F72F684BDA12F68))
    _encloses(proof.coefficient(False, 3), UInt64(0xBF1C01C018D40356), UInt64(0xBF1C01C018D40355))
    _encloses(proof.coefficient(False, 4), UInt64(0x3EB879FF75D87787), UInt64(0x3EB879FF75D87788))
    _encloses(proof.coefficient(False, 5), UInt64(0xBE4C2E2632E93452), UInt64(0xBE4C2E2632E93451))
    _encloses(proof.coefficient(False, 6), UInt64(0x3DD6F4130FAB2B20), UInt64(0x3DD6F4130FAB2B21))
    _encloses(proof.coefficient(False, 7), UInt64(0xBD5BD46AC7D9961B), UInt64(0xBD5BD46AC7D9961A))
    _encloses(proof.coefficient(False, 8), UInt64(0x3CDA143A23D4EE9E), UInt64(0x3CDA143A23D4EE9F))
    _encloses(proof.coefficient(False, 9), UInt64(0xBC53724140300A8F), UInt64(0xBC53724140300A8E))
    _encloses(proof.coefficient(False, 10), UInt64(0x3BC79DC81E8AE813), UInt64(0x3BC79DC81E8AE814))
    _encloses(proof.coefficient(True, 0), UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556))
    _encloses(proof.coefficient(True, 1), UInt64(0xBF98618618618619), UInt64(0xBF98618618618618))
    _encloses(proof.coefficient(True, 2), UInt64(0x3F48D3018D13A9FB), UInt64(0x3F48D3018D13A9FC))
    _encloses(proof.coefficient(True, 3), UInt64(0xBEEBBD77740594BC), UInt64(0xBEEBBD77740594BB))
    _encloses(proof.coefficient(True, 4), UInt64(0x3E83777A356B4E91), UInt64(0x3E83777A356B4E92))
    _encloses(proof.coefficient(True, 5), UInt64(0xBE12B6609EC5AE57), UInt64(0xBE12B6609EC5AE56))
    _encloses(proof.coefficient(True, 6), UInt64(0x3D9A281C8E223021), UInt64(0x3D9A281C8E223022))
    _encloses(proof.coefficient(True, 7), UInt64(0xBD1BC441A0EF5A49), UInt64(0xBD1BC441A0EF5A48))
    _encloses(proof.coefficient(True, 8), UInt64(0x3C9722D7C148EFF3), UInt64(0x3C9722D7C148EFF4))
    _encloses(proof.coefficient(True, 9), UInt64(0xBC0F0E49C02B9528), UInt64(0xBC0F0E49C02B9527))
    _encloses(proof.coefficient(True, 10), UInt64(0x3B812425C0EFDE9D), UInt64(0x3B812425C0EFDE9E))


def test_exact_count_4_coefficients() raises:
    var proof = _proof(4)
    _encloses(proof.coefficient(False, 0), UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(proof.coefficient(False, 1), UInt64(0xBFB999999999999A), UInt64(0xBFB9999999999999))
    _encloses(proof.coefficient(False, 2), UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69))
    _encloses(proof.coefficient(False, 3), UInt64(0xBF1C01C01BD36D0D), UInt64(0xBF1C01C01BD36D0C))
    _encloses(proof.coefficient(False, 4), UInt64(0x3EB87A000E951135), UInt64(0x3EB87A000E951136))
    _encloses(proof.coefficient(False, 5), UInt64(0xBE4C2E2FA355B4DF), UInt64(0xBE4C2E2FA355B4DE))
    _encloses(proof.coefficient(False, 6), UInt64(0x3DD6F444A6CF8EC2), UInt64(0x3DD6F444A6CF8EC3))
    _encloses(proof.coefficient(False, 7), UInt64(0xBD5BD55F85EC68A5), UInt64(0xBD5BD55F85EC68A4))
    _encloses(proof.coefficient(False, 8), UInt64(0x3CDA16EA647163F0), UInt64(0x3CDA16EA647163F1))
    _encloses(proof.coefficient(False, 9), UInt64(0xBC53771C03EED7B0), UInt64(0xBC53771C03EED7AF))
    _encloses(proof.coefficient(False, 10), UInt64(0x3BC7A9F9A57C9C75), UInt64(0x3BC7A9F9A57C9C76))
    _encloses(proof.coefficient(True, 0), UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556))
    _encloses(proof.coefficient(True, 1), UInt64(0xBF98618618618619), UInt64(0xBF98618618618618))
    _encloses(proof.coefficient(True, 2), UInt64(0x3F48D3018D2E7EED), UInt64(0x3F48D3018D2E7EEE))
    _encloses(proof.coefficient(True, 3), UInt64(0xBEEBBD779162876D), UInt64(0xBEEBBD779162876C))
    _encloses(proof.coefficient(True, 4), UInt64(0x3E83777C327005C7), UInt64(0x3E83777C327005C8))
    _encloses(proof.coefficient(True, 5), UInt64(0xBE12B671B72E9C7B), UInt64(0xBE12B671B72E9C7A))
    _encloses(proof.coefficient(True, 6), UInt64(0x3D9A2893E7931B0F), UInt64(0x3D9A2893E7931B10))
    _encloses(proof.coefficient(True, 7), UInt64(0xBD1BC5F62488F012), UInt64(0xBD1BC5F62488F011))
    _encloses(proof.coefficient(True, 8), UInt64(0x3C9726A3B99CBA2C), UInt64(0x3C9726A3B99CBA2D))
    _encloses(proof.coefficient(True, 9), UInt64(0xBC0F19A0FD9D6C90), UInt64(0xBC0F19A0FD9D6C8F))
    _encloses(proof.coefficient(True, 10), UInt64(0x3B81304B36034DF9), UInt64(0x3B81304B36034DFA))


def test_exact_count_6_coefficients() raises:
    var proof = _proof(6)
    _encloses(proof.coefficient(False, 0), UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(proof.coefficient(False, 1), UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A))
    _encloses(proof.coefficient(False, 2), UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69))
    _encloses(proof.coefficient(False, 3), UInt64(0xBF1C01C01C00F0DF), UInt64(0xBF1C01C01C00F0DE))
    _encloses(proof.coefficient(False, 4), UInt64(0x3EB87A00184BA058), UInt64(0x3EB87A00184BA059))
    _encloses(proof.coefficient(False, 5), UInt64(0xBE4C2E3050FEFFA7), UInt64(0xBE4C2E3050FEFFA6))
    _encloses(proof.coefficient(False, 6), UInt64(0x3DD6F448C915007F), UInt64(0x3DD6F448C9150080))
    _encloses(proof.coefficient(False, 7), UInt64(0xBD5BD57747C93EDF), UInt64(0xBD5BD57747C93EDE))
    _encloses(proof.coefficient(False, 8), UInt64(0x3CDA1737C4D81EDD), UInt64(0x3CDA1737C4D81EDE))
    _encloses(proof.coefficient(False, 9), UInt64(0xBC5377BC88D3F68F), UInt64(0xBC5377BC88D3F68E))
    _encloses(proof.coefficient(False, 10), UInt64(0x3BC7ABC4FBB55D31), UInt64(0x3BC7ABC4FBB55D32))
    _encloses(proof.coefficient(True, 0), UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556))
    _encloses(proof.coefficient(True, 1), UInt64(0xBF98618618618619), UInt64(0xBF98618618618618))
    _encloses(proof.coefficient(True, 2), UInt64(0x3F48D3018D3011B7), UInt64(0x3F48D3018D3011B8))
    _encloses(proof.coefficient(True, 3), UInt64(0xBEEBBD77932CA254), UInt64(0xBEEBBD77932CA253))
    _encloses(proof.coefficient(True, 4), UInt64(0x3E83777C54AC9D87), UInt64(0x3E83777C54AC9D88))
    _encloses(proof.coefficient(True, 5), UInt64(0xBE12B673096656A7), UInt64(0xBE12B673096656A6))
    _encloses(proof.coefficient(True, 6), UInt64(0x3D9A289EA4E7F7C5), UInt64(0x3D9A289EA4E7F7C6))
    _encloses(proof.coefficient(True, 7), UInt64(0xBD1BC623C9312514), UInt64(0xBD1BC623C9312513))
    _encloses(proof.coefficient(True, 8), UInt64(0x3C972718F9787FA7), UInt64(0x3C972718F9787FA8))
    _encloses(proof.coefficient(True, 9), UInt64(0xBC0F1B31A8997E79), UInt64(0xBC0F1B31A8997E78))
    _encloses(proof.coefficient(True, 10), UInt64(0x3B8132321A62C63D), UInt64(0x3B8132321A62C63E))


def test_exact_count_7_coefficients() raises:
    var proof = _proof(7)
    _encloses(proof.coefficient(False, 0), UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(proof.coefficient(False, 1), UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A))
    _encloses(proof.coefficient(False, 2), UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69))
    _encloses(proof.coefficient(False, 3), UInt64(0xBF1C01C01C0193AE), UInt64(0xBF1C01C01C0193AD))
    _encloses(proof.coefficient(False, 4), UInt64(0x3EB87A00186FF5AD), UInt64(0x3EB87A00186FF5AE))
    _encloses(proof.coefficient(False, 5), UInt64(0xBE4C2E3053BFB720), UInt64(0xBE4C2E3053BFB71F))
    _encloses(proof.coefficient(False, 6), UInt64(0x3DD6F448DBC78D37), UInt64(0x3DD6F448DBC78D38))
    _encloses(proof.coefficient(False, 7), UInt64(0xBD5BD577C15A57E6), UInt64(0xBD5BD577C15A57E5))
    _encloses(proof.coefficient(False, 8), UInt64(0x3CDA173987124A55), UInt64(0x3CDA173987124A56))
    _encloses(proof.coefficient(False, 9), UInt64(0xBC5377C0ADF77ABE), UInt64(0xBC5377C0ADF77ABD))
    _encloses(proof.coefficient(False, 10), UInt64(0x3BC7ABD2682C618D), UInt64(0x3BC7ABD2682C618E))
    _encloses(proof.coefficient(True, 0), UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556))
    _encloses(proof.coefficient(True, 1), UInt64(0xBF98618618618619), UInt64(0xBF98618618618618))
    _encloses(proof.coefficient(True, 2), UInt64(0x3F48D3018D30174D), UInt64(0x3F48D3018D30174E))
    _encloses(proof.coefficient(True, 3), UInt64(0xBEEBBD77933325C1), UInt64(0xBEEBBD77933325C0))
    _encloses(proof.coefficient(True, 4), UInt64(0x3E83777C5531752B), UInt64(0x3E83777C5531752C))
    _encloses(proof.coefficient(True, 5), UInt64(0xBE12B6730F0B8B1D), UInt64(0xBE12B6730F0B8B1C))
    _encloses(proof.coefficient(True, 6), UInt64(0x3D9A289ED88342B2), UInt64(0x3D9A289ED88342B3))
    _encloses(proof.coefficient(True, 7), UInt64(0xBD1BC624C23405AB), UInt64(0xBD1BC624C23405AA))
    _encloses(proof.coefficient(True, 8), UInt64(0x3C97271BD0E91AA9), UInt64(0x3C97271BD0E91AAA))
    _encloses(proof.coefficient(True, 9), UInt64(0xBC0F1B3CABFE8D87), UInt64(0xBC0F1B3CABFE8D86))
    _encloses(proof.coefficient(True, 10), UInt64(0x3B813241361A1F38), UInt64(0x3B813241361A1F39))


def test_exact_count_11_coefficients() raises:
    var proof = _proof(11)
    _encloses(proof.coefficient(False, 0), UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(proof.coefficient(False, 1), UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A))
    _encloses(proof.coefficient(False, 2), UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69))
    _encloses(proof.coefficient(False, 3), UInt64(0xBF1C01C01C01BFA1), UInt64(0xBF1C01C01C01BFA0))
    _encloses(proof.coefficient(False, 4), UInt64(0x3EB87A001879E392), UInt64(0x3EB87A001879E393))
    _encloses(proof.coefficient(False, 5), UInt64(0xBE4C2E305484C3B8), UInt64(0xBE4C2E305484C3B7))
    _encloses(proof.coefficient(False, 6), UInt64(0x3DD6F448E12DD2FA), UInt64(0x3DD6F448E12DD2FB))
    _encloses(proof.coefficient(False, 7), UInt64(0xBD5BD577E5E17A1B), UInt64(0xBD5BD577E5E17A1A))
    _encloses(proof.coefficient(False, 8), UInt64(0x3CDA173A1492D029), UInt64(0x3CDA173A1492D02A))
    _encloses(proof.coefficient(False, 9), UInt64(0xBC5377C20BF1E880), UInt64(0xBC5377C20BF1E87F))
    _encloses(proof.coefficient(False, 10), UInt64(0x3BC7ABD70F8E6C39), UInt64(0x3BC7ABD70F8E6C3A))
    _encloses(proof.coefficient(True, 0), UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556))
    _encloses(proof.coefficient(True, 1), UInt64(0xBF98618618618619), UInt64(0xBF98618618618618))
    _encloses(proof.coefficient(True, 2), UInt64(0x3F48D3018D3018CF), UInt64(0x3F48D3018D3018D0))
    _encloses(proof.coefficient(True, 3), UInt64(0xBEEBBD779334EA05), UInt64(0xBEEBBD779334EA04))
    _encloses(proof.coefficient(True, 4), UInt64(0x3E83777C55562205), UInt64(0x3E83777C55562206))
    _encloses(proof.coefficient(True, 5), UInt64(0xBE12B67310A5C7AF), UInt64(0xBE12B67310A5C7AE))
    _encloses(proof.coefficient(True, 6), UInt64(0x3D9A289EE7B3D727), UInt64(0x3D9A289EE7B3D728))
    _encloses(proof.coefficient(True, 7), UInt64(0xBD1BC6250EAF830B), UInt64(0xBD1BC6250EAF830A))
    _encloses(proof.coefficient(True, 8), UInt64(0x3C97271CBB0BD5CD), UInt64(0x3C97271CBB0BD5CE))
    _encloses(proof.coefficient(True, 9), UInt64(0xBC0F1B40653C71B1), UInt64(0xBC0F1B40653C71B0))
    _encloses(proof.coefficient(True, 10), UInt64(0x3B813246953DA9B0), UInt64(0x3B813246953DA9B1))


def test_exact_count_21_coefficients() raises:
    var proof = _proof(21)
    _encloses(proof.coefficient(False, 0), UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(proof.coefficient(False, 1), UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A))
    _encloses(proof.coefficient(False, 2), UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69))
    _encloses(proof.coefficient(False, 3), UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C))
    _encloses(proof.coefficient(False, 4), UInt64(0x3EB87A00187A000D), UInt64(0x3EB87A00187A000E))
    _encloses(proof.coefficient(False, 5), UInt64(0xBE4C2E3054870A4A), UInt64(0xBE4C2E3054870A49))
    _encloses(proof.coefficient(False, 6), UInt64(0x3DD6F448E13E7EEC), UInt64(0x3DD6F448E13E7EED))
    _encloses(proof.coefficient(False, 7), UInt64(0xBD5BD577E6589CFC), UInt64(0xBD5BD577E6589CFB))
    _encloses(proof.coefficient(False, 8), UInt64(0x3CDA173A167EDFB4), UInt64(0x3CDA173A167EDFB5))
    _encloses(proof.coefficient(False, 9), UInt64(0xBC5377C2110CC46C), UInt64(0xBC5377C2110CC46B))
    _encloses(proof.coefficient(False, 10), UInt64(0x3BC7ABD7224FEA7F), UInt64(0x3BC7ABD7224FEA80))
    _encloses(proof.coefficient(True, 0), UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556))
    _encloses(proof.coefficient(True, 1), UInt64(0xBF98618618618619), UInt64(0xBF98618618618618))
    _encloses(proof.coefficient(True, 2), UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4))
    _encloses(proof.coefficient(True, 3), UInt64(0xBEEBBD779334EF0A), UInt64(0xBEEBBD779334EF09))
    _encloses(proof.coefficient(True, 4), UInt64(0x3E83777C55568CA2), UInt64(0x3E83777C55568CA3))
    _encloses(proof.coefficient(True, 5), UInt64(0xBE12B67310AA9D3D), UInt64(0xBE12B67310AA9D3C))
    _encloses(proof.coefficient(True, 6), UInt64(0x3D9A289EE7E3FB16), UInt64(0x3D9A289EE7E3FB17))
    _encloses(proof.coefficient(True, 7), UInt64(0xBD1BC6250FB0D1E8), UInt64(0xBD1BC6250FB0D1E7))
    _encloses(proof.coefficient(True, 8), UInt64(0x3C97271CBE56E622), UInt64(0x3C97271CBE56E623))
    _encloses(proof.coefficient(True, 9), UInt64(0xBC0F1B4073AC7856), UInt64(0xBC0F1B4073AC7855))
    _encloses(proof.coefficient(True, 10), UInt64(0x3B813246ABC2F54C), UInt64(0x3B813246ABC2F54D))


def test_exact_count_22_coefficients() raises:
    var proof = _proof(22)
    _encloses(proof.coefficient(False, 0), UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(proof.coefficient(False, 1), UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A))
    _encloses(proof.coefficient(False, 2), UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69))
    _encloses(proof.coefficient(False, 3), UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C))
    _encloses(proof.coefficient(False, 4), UInt64(0x3EB87A00187A0011), UInt64(0x3EB87A00187A0012))
    _encloses(proof.coefficient(False, 5), UInt64(0xBE4C2E3054870AA2), UInt64(0xBE4C2E3054870AA1))
    _encloses(proof.coefficient(False, 6), UInt64(0x3DD6F448E13E8181), UInt64(0x3DD6F448E13E8182))
    _encloses(proof.coefficient(False, 7), UInt64(0xBD5BD577E658AFEE), UInt64(0xBD5BD577E658AFED))
    _encloses(proof.coefficient(False, 8), UInt64(0x3CDA173A167F3083), UInt64(0x3CDA173A167F3084))
    _encloses(proof.coefficient(False, 9), UInt64(0xBC5377C2110DA335), UInt64(0xBC5377C2110DA334))
    _encloses(proof.coefficient(False, 10), UInt64(0x3BC7ABD722534019), UInt64(0x3BC7ABD72253401A))
    _encloses(proof.coefficient(True, 0), UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556))
    _encloses(proof.coefficient(True, 1), UInt64(0xBF98618618618619), UInt64(0xBF98618618618618))
    _encloses(proof.coefficient(True, 2), UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4))
    _encloses(proof.coefficient(True, 3), UInt64(0xBEEBBD779334EF0A), UInt64(0xBEEBBD779334EF09))
    _encloses(proof.coefficient(True, 4), UInt64(0x3E83777C55568CB2), UInt64(0x3E83777C55568CB3))
    _encloses(proof.coefficient(True, 5), UInt64(0xBE12B67310AA9DFA), UInt64(0xBE12B67310AA9DF9))
    _encloses(proof.coefficient(True, 6), UInt64(0x3D9A289EE7E402A3), UInt64(0x3D9A289EE7E402A4))
    _encloses(proof.coefficient(True, 7), UInt64(0xBD1BC6250FB0FB75), UInt64(0xBD1BC6250FB0FB74))
    _encloses(proof.coefficient(True, 8), UInt64(0x3C97271CBE57731C), UInt64(0x3C97271CBE57731D))
    _encloses(proof.coefficient(True, 9), UInt64(0xBC0F1B4073AEFB6C), UInt64(0xBC0F1B4073AEFB6B))
    _encloses(proof.coefficient(True, 10), UInt64(0x3B813246ABC70D95), UInt64(0x3B813246ABC70D96))


def test_exact_count_64_coefficients() raises:
    var proof = _proof(64)
    _encloses(proof.coefficient(False, 0), UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001))
    _encloses(proof.coefficient(False, 1), UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A))
    _encloses(proof.coefficient(False, 2), UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69))
    _encloses(proof.coefficient(False, 3), UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C))
    _encloses(proof.coefficient(False, 4), UInt64(0x3EB87A00187A0019), UInt64(0x3EB87A00187A001A))
    _encloses(proof.coefficient(False, 5), UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37))
    _encloses(proof.coefficient(False, 6), UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2))
    _encloses(proof.coefficient(False, 7), UInt64(0xBD5BD577E658D021), UInt64(0xBD5BD577E658D020))
    _encloses(proof.coefficient(False, 8), UInt64(0x3CDA173A167FBA4C), UInt64(0x3CDA173A167FBA4D))
    _encloses(proof.coefficient(False, 9), UInt64(0xBC5377C2110F2081), UInt64(0xBC5377C2110F2080))
    _encloses(proof.coefficient(False, 10), UInt64(0x3BC7ABD72258FB65), UInt64(0x3BC7ABD72258FB66))
    _encloses(proof.coefficient(True, 0), UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556))
    _encloses(proof.coefficient(True, 1), UInt64(0xBF98618618618619), UInt64(0xBF98618618618618))
    _encloses(proof.coefficient(True, 2), UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4))
    _encloses(proof.coefficient(True, 3), UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B))
    _encloses(proof.coefficient(True, 4), UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE))
    _encloses(proof.coefficient(True, 5), UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A))
    _encloses(proof.coefficient(True, 6), UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74))
    _encloses(proof.coefficient(True, 7), UInt64(0xBD1BC6250FB14231), UInt64(0xBD1BC6250FB14230))
    _encloses(proof.coefficient(True, 8), UInt64(0x3C97271CBE5863EA), UInt64(0x3C97271CBE5863EB))
    _encloses(proof.coefficient(True, 9), UInt64(0xBC0F1B4073B34A62), UInt64(0xBC0F1B4073B34A61))
    _encloses(proof.coefficient(True, 10), UInt64(0x3B813246ABCE1BD2), UInt64(0x3B813246ABCE1BD3))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
