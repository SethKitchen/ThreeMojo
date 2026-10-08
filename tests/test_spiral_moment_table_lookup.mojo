# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# SOURCE ONLY. Keep the original TestSuite five-second per-test gate.

from extensions.carla.curve_bounds import (
    _geometry_distance,
    _spiral_counts,
    _reference_jet,
)
from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.geometry import RoadGeometry, SPIRAL
from extensions.carla.spiral_moment_proof import _try_build_spiral_moments
from extensions.carla.spiral_moment_table import (
    _SpiralMomentProof,
    _try_lookup_spiral_moments,
    _try_spiral_moment_expansion,
)
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_true, assert_false, assert_equal


def _same_interval(one: _Interval, two: _Interval) raises:
    assert_equal(bitcast[DType.uint64](one.low), bitcast[DType.uint64](two.low))
    assert_equal(
        bitcast[DType.uint64](one.high), bitcast[DType.uint64](two.high)
    )


def _same_jet(one: _Jet, two: _Jet) raises:
    _same_interval(one.value, two.value)
    _same_interval(one.first, two.first)
    _same_interval(one.second, two.second)
    assert_equal(
        bitcast[DType.uint64](one.error), bitcast[DType.uint64](two.error)
    )


def _compare_builder(count: Int) raises:
    var dynamic_spent = 0
    var dynamic = _try_build_spiral_moments(count, dynamic_spent, 110 * count)
    if not dynamic:
        raise Error("Dynamic control proof unavailable")
    assert_equal(dynamic_spent, 110 * count)
    var table_spent = 0
    var table = _try_lookup_spiral_moments(count, table_spent, 22)
    if not table:
        raise Error("Table control proof unavailable")
    assert_equal(table_spent, 22)
    assert_equal(table.value().pieces, count)
    for index in range(11):
        var cosine = table.value().coefficient(False, index)
        var sine = table.value().coefficient(True, index)
        assert_true(cosine.is_finite())
        assert_true(sine.is_finite())
        assert_true(dynamic.value().cosine[index].contains(cosine.low))
        assert_true(dynamic.value().cosine[index].contains(cosine.high))
        assert_true(dynamic.value().sine[index].contains(sine.low))
        assert_true(dynamic.value().sine[index].contains(sine.high))


def _table_or_generic(
    geometry: RoadGeometry, distance: _Jet, available: Bool
) -> Tuple[_Jet, _Jet, _Jet]:
    # Test-only caller: the miss path is exactly the original evaluator.
    var d = _geometry_distance(geometry, distance)
    var counts = _spiral_counts(geometry, d)
    var spent = 0
    var proof = _try_lookup_spiral_moments(counts[0], spent, 22, available)
    if proof:
        var candidate = _try_spiral_moment_expansion(
            proof.value(), geometry, d, counts, Vector3(0, 0, 0)
        )
        if candidate:
            return candidate.value()
    return _reference_jet(geometry, distance, Vector3(0, 0, 0))


def _assert_generic_fallback(
    geometry: RoadGeometry, distance: _Jet, available: Bool
) raises:
    var actual = _table_or_generic(geometry, distance, available)
    var expected = _reference_jet(geometry, distance, Vector3(0, 0, 0))
    _same_jet(actual[0], expected[0])
    _same_jet(actual[1], expected[1])
    _same_jet(actual[2], expected[2])


def test_missing_table_preserves_budget_and_generic_fallback() raises:
    var spent = 17
    var missing = _try_lookup_spiral_moments(4, spent, 1000, False)
    if missing:
        raise Error("Disabled table returned a view")
    assert_equal(spent, 17)
    var geometry = RoadGeometry(SPIRAL, 0.0, 0.0, 100.0, 0.0, 20.0)
    geometry.curvature_end = 0.05
    _assert_generic_fallback(geometry, _Jet.variable(2.125, 2.125), False)


def test_table_invalid_accessor_never_indexes_storage() raises:
    var invalid: List[Int] = [-1, 0, 65]
    for count in invalid:
        var proof = _SpiralMomentProof(count)
        assert_false(proof.coefficient(False, 0).is_finite())
        assert_false(proof.coefficient(True, 10).is_finite())
    var boundaries: List[Int] = [1, 64]
    for count in boundaries:
        var proof = _SpiralMomentProof(count)
        assert_false(proof.coefficient(False, -1).is_finite())
        assert_false(proof.coefficient(True, 11).is_finite())
        assert_true(proof.coefficient(False, 0).is_finite())
        assert_true(proof.coefficient(True, 10).is_finite())


def test_count64_hit_count65_miss_preserves_generic() raises:
    var geometry = RoadGeometry(SPIRAL, 0.0, 0.0, 100.0, 0.0, 128.0)
    geometry.curvature_end = 0.0
    var d = _geometry_distance(geometry, _Jet.variable(62.5, 62.5))
    var counts = _spiral_counts(geometry, d)
    assert_equal(counts[0], 64)
    assert_equal(counts[1], 64)
    var spent = 0
    var proof = _try_lookup_spiral_moments(64, spent, 22)
    if not proof:
        raise Error("Count64 boundary unavailable")
    var accepted = _try_spiral_moment_expansion(
        proof.value(), geometry, d, counts, Vector3(0, 0, 0)
    )
    if not accepted:
        raise Error("Eligible count64 boundary rejected")
    assert_equal(accepted.value()[0].error, inf[DType.float64]())
    assert_equal(accepted.value()[1].error, inf[DType.float64]())
    var unsupported = _Jet.variable(63.5, 63.5)
    var count65 = _spiral_counts(
        geometry, _geometry_distance(geometry, unsupported)
    )
    assert_equal(count65[0], 65)
    assert_equal(count65[1], 65)
    _assert_generic_fallback(geometry, unsupported, True)


def test_count_clamp_quadrant_misses_preserve_generic() raises:
    var geometry = RoadGeometry(SPIRAL, 0.0, 0.0, 100.0, 0.0, 20.0)
    geometry.curvature_end = 0.0
    _assert_generic_fallback(geometry, _Jet.variable(0.99, 1.01), True)
    _assert_generic_fallback(geometry, _Jet.variable(0.0, 0.0), True)
    _assert_generic_fallback(geometry, _Jet.variable(20.0, 20.0), True)
    geometry.curvature_end = 0.1
    _assert_generic_fallback(geometry, _Jet.variable(19.0, 19.0), True)


def _word_pair(
    proof: _SpiralMomentProof, sine: Bool, index: Int, low: UInt64, high: UInt64
) raises:
    var actual = proof.coefficient(sine, index)
    assert_equal(bitcast[DType.uint64](actual.low), low)
    assert_equal(bitcast[DType.uint64](actual.high), high)


def test_table_builder_and_exact_words_count_1() raises:
    _compare_builder(1)
    var proof = _SpiralMomentProof(1)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB9999999999999), UInt64(0xBFB9999999999998)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F65), UInt64(0x3F72F684BDA12F66)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1BFF7537CA47FF), UInt64(0xBF1BFF7537CA47FE)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB859BA6A404194), UInt64(0x3EB859BA6A404195)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4B90465AC514BE), UInt64(0xBE4B90465AC514BD)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD5B62AEA85CBDD), UInt64(0x3DD5B62AEA85CBDE)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5907D83D18103A), UInt64(0xBD5907D83D181039)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CD5F7CC2AB4E47C), UInt64(0x3CD5F7CC2AB4E47D)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC4E4B08B4586127), UInt64(0xBC4E4B08B4586126)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC0D4BDF483BB65), UInt64(0x3BC0D4BDF483BB66)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618616), UInt64(0xBF98618618618615)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D2E7EED59D6B), UInt64(0x3F48D2E7EED59D6C)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBB1845FC9B189), UInt64(0xBEEBB1845FC9B188)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E833D4E779AF2EE), UInt64(0x3E833D4E779AF2EF)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE1209B3A4F5256D), UInt64(0xBE1209B3A4F5256C)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D982CD206F6E1C2), UInt64(0x3D982CD206F6E1C3)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1836090ADA71E7), UInt64(0xBD1836090ADA71E6)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C92C47E5E54FDB1), UInt64(0x3C92C47E5E54FDB2)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC072A5DE37A8E01), UInt64(0xBC072A5DE37A8E00)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B774B5C52353452), UInt64(0x3B774B5C52353453)
    )


def test_table_builder_and_exact_words_count_2() raises:
    _compare_builder(2)
    var proof = _SpiralMomentProof(2)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999A), UInt64(0xBFB9999999999999)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F67), UInt64(0x3F72F684BDA12F68)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01BF6A6C8AFD), UInt64(0xBF1C01BF6A6C8AFC)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB879E2F88F1BED), UInt64(0x3EB879E2F88F1BEE)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2CD879091889), UInt64(0xBE4C2CD879091888)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6EEF99E8B9699), UInt64(0x3DD6EEF99E8B969A)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BC120C380F2EE), UInt64(0xBD5BC120C380F2ED)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CD9E96FD7FCF8A0), UInt64(0x3CD9E96FD7FCF8A1)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5333B92409AA34), UInt64(0xBC5333B92409AA33)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC71BCAA8BA1C37), UInt64(0x3BC71BCAA8BA1C38)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618618), UInt64(0xBF98618618618617)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D30186C88232), UInt64(0x3F48D30186C88233)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD714721DABC), UInt64(0xBEEBBD714721DABB)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E8377283C1FF648), UInt64(0x3E8377283C1FF649)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B458C4A07528), UInt64(0xBE12B458C4A07527)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A1D6852216324), UInt64(0x3D9A1D6852216325)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BA5CDE8372ECF), UInt64(0xBD1BA5CDE8372ECE)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C96ECA44A92FFE1), UInt64(0x3C96ECA44A92FFE2)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0E89BD1F5B80FD), UInt64(0xBC0E89BD1F5B80FC)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B80AD76CF0FD991), UInt64(0x3B80AD76CF0FD992)
    )


def test_table_builder_and_exact_words_count_3() raises:
    _compare_builder(3)
    var proof = _SpiralMomentProof(3)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999A), UInt64(0xBFB9999999999999)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F67), UInt64(0x3F72F684BDA12F68)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C018D40356), UInt64(0xBF1C01C018D40355)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB879FF75D87787), UInt64(0x3EB879FF75D87788)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E2632E93452), UInt64(0xBE4C2E2632E93451)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F4130FAB2B20), UInt64(0x3DD6F4130FAB2B21)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD46AC7D9961B), UInt64(0xBD5BD46AC7D9961A)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA143A23D4EE9E), UInt64(0x3CDA143A23D4EE9F)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC53724140300A8F), UInt64(0xBC53724140300A8E)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC79DC81E8AE813), UInt64(0x3BC79DC81E8AE814)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D13A9FB), UInt64(0x3F48D3018D13A9FC)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD77740594BC), UInt64(0xBEEBBD77740594BB)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777A356B4E91), UInt64(0x3E83777A356B4E92)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B6609EC5AE57), UInt64(0xBE12B6609EC5AE56)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A281C8E223021), UInt64(0x3D9A281C8E223022)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC441A0EF5A49), UInt64(0xBD1BC441A0EF5A48)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C9722D7C148EFF3), UInt64(0x3C9722D7C148EFF4)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F0E49C02B9528), UInt64(0xBC0F0E49C02B9527)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B812425C0EFDE9D), UInt64(0x3B812425C0EFDE9E)
    )


def test_table_builder_and_exact_words_count_4() raises:
    _compare_builder(4)
    var proof = _SpiralMomentProof(4)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999A), UInt64(0xBFB9999999999999)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01BD36D0D), UInt64(0xBF1C01C01BD36D0C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A000E951135), UInt64(0x3EB87A000E951136)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E2FA355B4DF), UInt64(0xBE4C2E2FA355B4DE)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F444A6CF8EC2), UInt64(0x3DD6F444A6CF8EC3)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD55F85EC68A5), UInt64(0xBD5BD55F85EC68A4)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA16EA647163F0), UInt64(0x3CDA16EA647163F1)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC53771C03EED7B0), UInt64(0xBC53771C03EED7AF)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7A9F9A57C9C75), UInt64(0x3BC7A9F9A57C9C76)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D2E7EED), UInt64(0x3F48D3018D2E7EEE)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779162876D), UInt64(0xBEEBBD779162876C)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C327005C7), UInt64(0x3E83777C327005C8)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B671B72E9C7B), UInt64(0xBE12B671B72E9C7A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A2893E7931B0F), UInt64(0x3D9A2893E7931B10)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC5F62488F012), UInt64(0xBD1BC5F62488F011)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C9726A3B99CBA2C), UInt64(0x3C9726A3B99CBA2D)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F19A0FD9D6C90), UInt64(0xBC0F19A0FD9D6C8F)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B81304B36034DF9), UInt64(0x3B81304B36034DFA)
    )


def test_table_builder_and_exact_words_count_5() raises:
    _compare_builder(5)
    var proof = _SpiralMomentProof(5)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01BFCC065), UInt64(0xBF1C01C01BFCC064)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A0017604566), UInt64(0x3EB87A0017604567)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E303FB5421A), UInt64(0xBE4C2E303FB54219)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448588A4D75), UInt64(0x3DD6F448588A4D76)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD5748FE12B60), UInt64(0xBD5BD5748FE12B5F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA172E3B9914D0), UInt64(0x3CDA172E3B9914D1)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377A745F36A37), UInt64(0xBC5377A745F36A36)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7AB83D2FB8B10), UInt64(0x3BC7AB83D2FB8B11)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D2FECCF), UInt64(0x3F48D3018D2FECD0)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD77930201D1), UInt64(0xBEEBBD77930201D0)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C515BEEF2), UInt64(0x3E83777C515BEEF3)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B672E6A61358), UInt64(0xBE12B672E6A61357)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289D75C2923B), UInt64(0x3D9A289D75C2923C)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC61E5D71504F), UInt64(0xBD1BC61E5D71504E)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C972709FD0394B2), UInt64(0x3C972709FD0394B3)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1AFAB6305647), UInt64(0xBC0F1AFAB6305646)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B8131EABABC5CED), UInt64(0x3B8131EABABC5CEE)
    )


def test_table_builder_and_exact_words_count_6() raises:
    _compare_builder(6)
    var proof = _SpiralMomentProof(6)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C00F0DF), UInt64(0xBF1C01C01C00F0DE)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00184BA058), UInt64(0x3EB87A00184BA059)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3050FEFFA7), UInt64(0xBE4C2E3050FEFFA6)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448C915007F), UInt64(0x3DD6F448C9150080)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD57747C93EDF), UInt64(0xBD5BD57747C93EDE)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA1737C4D81EDD), UInt64(0x3CDA1737C4D81EDE)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377BC88D3F68F), UInt64(0xBC5377BC88D3F68E)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABC4FBB55D31), UInt64(0x3BC7ABC4FBB55D32)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3011B7), UInt64(0x3F48D3018D3011B8)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD77932CA254), UInt64(0xBEEBBD77932CA253)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C54AC9D87), UInt64(0x3E83777C54AC9D88)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B673096656A7), UInt64(0xBE12B673096656A6)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EA4E7F7C5), UInt64(0x3D9A289EA4E7F7C6)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC623C9312514), UInt64(0xBD1BC623C9312513)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C972718F9787FA7), UInt64(0x3C972718F9787FA8)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B31A8997E79), UInt64(0xBC0F1B31A8997E78)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B8132321A62C63D), UInt64(0x3B8132321A62C63E)
    )


def test_table_builder_and_exact_words_count_7() raises:
    _compare_builder(7)
    var proof = _SpiralMomentProof(7)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C0193AE), UInt64(0xBF1C01C01C0193AD)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00186FF5AD), UInt64(0x3EB87A00186FF5AE)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3053BFB720), UInt64(0xBE4C2E3053BFB71F)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448DBC78D37), UInt64(0x3DD6F448DBC78D38)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577C15A57E6), UInt64(0xBD5BD577C15A57E5)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173987124A55), UInt64(0x3CDA173987124A56)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C0ADF77ABE), UInt64(0xBC5377C0ADF77ABD)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD2682C618D), UInt64(0x3BC7ABD2682C618E)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D30174D), UInt64(0x3F48D3018D30174E)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD77933325C1), UInt64(0xBEEBBD77933325C0)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C5531752B), UInt64(0x3E83777C5531752C)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B6730F0B8B1D), UInt64(0xBE12B6730F0B8B1C)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289ED88342B2), UInt64(0x3D9A289ED88342B3)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC624C23405AB), UInt64(0xBD1BC624C23405AA)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271BD0E91AA9), UInt64(0x3C97271BD0E91AAA)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B3CABFE8D87), UInt64(0xBC0F1B3CABFE8D86)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813241361A1F38), UInt64(0x3B813241361A1F39)
    )


def test_table_builder_and_exact_words_count_8() raises:
    _compare_builder(8)
    var proof = _SpiralMomentProof(8)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01B469), UInt64(0xBF1C01C01C01B468)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187756DD), UInt64(0x3EB87A00187756DE)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E30545196AD), UInt64(0xBE4C2E30545196AC)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448DFC1021F), UInt64(0x3DD6F448DFC10220)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577DC0B9438), UInt64(0xBD5BD577DC0B9437)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA1739ED9637BC), UInt64(0x3CDA1739ED9637BD)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C1A91473AD), UInt64(0xBC5377C1A91473AC)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD5B6177015), UInt64(0x3BC7ABD5B6177016)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D30186C), UInt64(0x3F48D3018D30186D)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD7793347652), UInt64(0xBEEBBD7793347651)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C554CAAF7), UInt64(0x3E83777C554CAAF8)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B673103A6F52), UInt64(0xBE12B673103A6F51)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE3A7AC12), UInt64(0x3D9A289EE3A7AC13)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC624F9DC3BF6), UInt64(0xBD1BC624F9DC3BF5)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271C79BD2E3B), UInt64(0x3C97271C79BD2E3C)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B3F5470C85A), UInt64(0xBC0F1B3F5470C859)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B8132450128B0F6), UInt64(0x3B8132450128B0F7)
    )


def test_table_builder_and_exact_words_count_9() raises:
    _compare_builder(9)
    var proof = _SpiralMomentProof(9)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01BC82), UInt64(0xBF1C01C01C01BC81)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A0018792D40), UInt64(0x3EB87A0018792D41)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054765D42), UInt64(0xBE4C2E3054765D41)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E0C61715), UInt64(0x3DD6F448E0C61716)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E30C0703), UInt64(0xBD5BD577E30C0702)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A092AB71E), UInt64(0x3CDA173A092AB71F)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C1EE86070A), UInt64(0xBC5377C1EE860709)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD6A6DF2760), UInt64(0x3BC7ABD6A6DF2761)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018B3), UInt64(0x3F48D3018D3018B4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334C9C7), UInt64(0xBEEBBD779334C9C6)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55537AFA), UInt64(0x3E83777C55537AFB)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310876D62), UInt64(0xBE12B67310876D61)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE68B5AA2), UInt64(0x3D9A289EE68B5AA3)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC62508A40124), UInt64(0xBD1BC62508A40123)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CA7C76EBF), UInt64(0x3C97271CA7C76EC0)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4013534F3B), UInt64(0xBC0F1B4013534F3A)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B81324619A5D256), UInt64(0x3B81324619A5D257)
    )


def test_table_builder_and_exact_words_count_10() raises:
    _compare_builder(10)
    var proof = _SpiralMomentProof(10)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01BEDB), UInt64(0xBF1C01C01C01BEDA)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A001879B650), UInt64(0x3EB87A001879B651)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054812C49), UInt64(0xBE4C2E3054812C48)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E113C70F), UInt64(0x3DD6F448E113C710)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E529C33B), UInt64(0xBD5BD577E529C33A)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A11A7D744), UInt64(0x3CDA173A11A7D745)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C204555EBE), UInt64(0xBC5377C204555EBD)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD6F4245B9F), UInt64(0x3BC7ABD6F4245BA0)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018C8), UInt64(0x3F48D3018D3018C9)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334E207), UInt64(0xBEEBBD779334E206)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C5555791A), UInt64(0x3E83777C5555791B)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B673109E2FA7), UInt64(0xBE12B673109E2FA6)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE76917D2), UInt64(0x3D9A289EE76917D3)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250D25B558), UInt64(0xBD1BC6250D25B557)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CB617239D), UInt64(0x3C97271CB617239E)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B404FEAFE47), UInt64(0xBC0F1B404FEAFE46)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B81324674AB513A), UInt64(0x3B81324674AB513B)
    )


def test_table_builder_and_exact_words_count_11() raises:
    _compare_builder(11)
    var proof = _SpiralMomentProof(11)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01BFA1), UInt64(0xBF1C01C01C01BFA0)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A001879E392), UInt64(0x3EB87A001879E393)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E305484C3B8), UInt64(0xBE4C2E305484C3B7)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E12DD2FA), UInt64(0x3DD6F448E12DD2FB)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E5E17A1B), UInt64(0xBD5BD577E5E17A1A)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A1492D029), UInt64(0x3CDA173A1492D02A)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C20BF1E880), UInt64(0xBC5377C20BF1E87F)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD70F8E6C39), UInt64(0x3BC7ABD70F8E6C3A)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018CF), UInt64(0x3F48D3018D3018D0)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EA05), UInt64(0xBEEBBD779334EA04)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55562205), UInt64(0x3E83777C55562206)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310A5C7AF), UInt64(0xBE12B67310A5C7AE)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7B3D727), UInt64(0x3D9A289EE7B3D728)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250EAF830B), UInt64(0xBD1BC6250EAF830A)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBB0BD5CD), UInt64(0x3C97271CBB0BD5CE)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B40653C71B1), UInt64(0xBC0F1B40653C71B0)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246953DA9B0), UInt64(0x3B813246953DA9B1)
    )


def test_table_builder_and_exact_words_count_12() raises:
    _compare_builder(12)
    var proof = _SpiralMomentProof(12)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01BFE9), UInt64(0xBF1C01C01C01BFE8)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A001879F41F), UInt64(0x3EB87A001879F420)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E305486157D), UInt64(0xBE4C2E305486157C)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E1377509), UInt64(0x3DD6F448E137750A)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E6260240), UInt64(0xBD5BD577E626023F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A15AC55BA), UInt64(0x3CDA173A15AC55BB)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C20ED8E646), UInt64(0xBC5377C20ED8E645)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD71A24ECAB), UInt64(0x3BC7ABD71A24ECAC)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D1), UInt64(0x3F48D3018D3018D2)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334ECF0), UInt64(0xBEEBBD779334ECEF)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55565FEA), UInt64(0x3E83777C55565FEB)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310A89413), UInt64(0xBE12B67310A89412)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7CF9912), UInt64(0x3D9A289EE7CF9913)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250F43244E), UInt64(0xBD1BC6250F43244D)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBCECB52F), UInt64(0x3C97271CBCECB530)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B406D6A818A), UInt64(0xBC0F1B406D6A8189)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246A1E7DA2F), UInt64(0x3B813246A1E7DA30)
    )


def test_table_builder_and_exact_words_count_13() raises:
    _compare_builder(13)
    var proof = _SpiralMomentProof(13)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C006), UInt64(0xBF1C01C01C01C005)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A001879FAB6), UInt64(0x3EB87A001879FAB7)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054869C65), UInt64(0xBE4C2E3054869C64)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13B5314), UInt64(0x3DD6F448E13B5315)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E641B497), UInt64(0xBD5BD577E641B496)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A161F0567), UInt64(0x3CDA173A161F0568)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2100A5BB3), UInt64(0xBC5377C2100A5BB2)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD71E8A983F), UInt64(0x3BC7ABD71E8A9840)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D2), UInt64(0x3F48D3018D3018D3)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EE19), UInt64(0xBEEBBD779334EE18)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55567896), UInt64(0x3E83777C55567897)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310A9B2E3), UInt64(0xBE12B67310A9B2E2)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7DAC6DA), UInt64(0x3D9A289EE7DAC6DB)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250F7F08D2), UInt64(0xBD1BC6250F7F08D1)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBDB179F8), UInt64(0x3C97271CBDB179F9)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4070CBAFD3), UInt64(0xBC0F1B4070CBAFD2)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246A73192DC), UInt64(0x3B813246A73192DD)
    )


def test_table_builder_and_exact_words_count_14() raises:
    _compare_builder(14)
    var proof = _SpiralMomentProof(14)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C012), UInt64(0xBF1C01C01C01C011)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A001879FD86), UInt64(0x3EB87A001879FD87)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E305486D63A), UInt64(0xBE4C2E305486D639)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13CFD35), UInt64(0x3DD6F448E13CFD36)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E64DB05F), UInt64(0xBD5BD577E64DB05E)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A1650F4F5), UInt64(0x3CDA173A1650F4F6)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2109054A5), UInt64(0xBC5377C2109054A4)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD7207C54BA), UInt64(0x3BC7ABD7207C54BB)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D2), UInt64(0x3F48D3018D3018D3)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EE98), UInt64(0xBEEBBD779334EE97)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568326), UInt64(0x3E83777C55568327)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA2E11), UInt64(0xBE12B67310AA2E10)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7DF99A6), UInt64(0x3D9A289EE7DF99A7)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250F9906E1), UInt64(0xBD1BC6250F9906E0)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE077469), UInt64(0x3C97271CBE07746A)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B407248A826), UInt64(0xBC0F1B407248A825)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246A98ABE6D), UInt64(0x3B813246A98ABE6E)
    )


def test_table_builder_and_exact_words_count_15() raises:
    _compare_builder(15)
    var proof = _SpiralMomentProof(15)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C018), UInt64(0xBF1C01C01C01C017)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A001879FECE), UInt64(0x3EB87A001879FECF)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E305486F091), UInt64(0xBE4C2E305486F090)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13DBFEB), UInt64(0x3DD6F448E13DBFEC)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E6533008), UInt64(0xBD5BD577E6533007)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A1667FCA0), UInt64(0x3CDA173A1667FCA1)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C210CE7B8B), UInt64(0xBC5377C210CE7B8A)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72164C4B9), UInt64(0x3BC7ABD72164C4BA)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EED2), UInt64(0xBEEBBD779334EED1)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C555687F3), UInt64(0x3E83777C555687F4)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA6641), UInt64(0xBE12B67310AA6640)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E1CEFD), UInt64(0x3D9A289EE7E1CEFE)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FA4FB8F), UInt64(0xBD1BC6250FA4FB8E)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE2F3868), UInt64(0x3C97271CBE2F3869)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4072F9F6F2), UInt64(0xBC0F1B4072F9F6F1)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246AAA47A97), UInt64(0x3B813246AAA47A98)
    )


def test_table_builder_and_exact_words_count_16() raises:
    _compare_builder(16)
    var proof = _SpiralMomentProof(16)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01A), UInt64(0xBF1C01C01C01C019)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A001879FF6B), UInt64(0x3EB87A001879FF6C)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E305486FD36), UInt64(0xBE4C2E305486FD35)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E1DA1), UInt64(0x3DD6F448E13E1DA2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E655D7D2), UInt64(0xBD5BD577E655D7D1)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A16732799), UInt64(0x3CDA173A1673279A)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C210ECC483), UInt64(0xBC5377C210ECC482)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD721D6A590), UInt64(0x3BC7ABD721D6A591)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EEED), UInt64(0xBEEBBD779334EEEC)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568A41), UInt64(0x3E83777C55568A42)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA8142), UInt64(0xBE12B67310AA8141)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E2DF82), UInt64(0x3D9A289EE7E2DF83)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FAAC48F), UInt64(0xBD1BC6250FAAC48E)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE428C80), UInt64(0x3C97271CBE428C81)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073509754), UInt64(0xBC0F1B4073509753)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246AB2EE9F0), UInt64(0x3B813246AB2EE9F1)
    )


def test_table_builder_and_exact_words_count_17() raises:
    _compare_builder(17)
    var proof = _SpiralMomentProof(17)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01C), UInt64(0xBF1C01C01C01C01B)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A001879FFBA), UInt64(0x3EB87A001879FFBB)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870390), UInt64(0xBE4C2E305487038F)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E4CD4), UInt64(0x3DD6F448E13E4CD5)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E6572F2B), UInt64(0xBD5BD577E6572F2A)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A1678D092), UInt64(0x3CDA173A1678D093)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C210FC2D9E), UInt64(0xBC5377C210FC2D9D)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72210DB51), UInt64(0x3BC7ABD72210DB52)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EEFB), UInt64(0xBEEBBD779334EEFA)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568B69), UInt64(0x3E83777C55568B6A)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA8ED8), UInt64(0xBE12B67310AA8ED7)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E368F3), UInt64(0x3D9A289EE7E368F4)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FADB1D0), UInt64(0xBD1BC6250FADB1CF)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE4C5D21), UInt64(0x3C97271CBE4C5D22)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B40737CC4AA), UInt64(0xBC0F1B40737CC4A9)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246AB75D968), UInt64(0x3B813246AB75D969)
    )


def test_table_builder_and_exact_words_count_18() raises:
    _compare_builder(18)
    var proof = _SpiralMomentProof(18)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01C), UInt64(0xBF1C01C01C01C01B)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A001879FFE3), UInt64(0x3EB87A001879FFE4)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E30548706E4), UInt64(0xBE4C2E30548706E3)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E6593), UInt64(0x3DD6F448E13E6594)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E657E39B), UInt64(0xBD5BD577E657E39A)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167BCC3E), UInt64(0x3CDA173A167BCC3F)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110453D8), UInt64(0xBC5377C2110453D7)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD7222FC1A3), UInt64(0x3BC7ABD7222FC1A4)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF02), UInt64(0xBEEBBD779334EF01)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568C04), UInt64(0x3E83777C55568C05)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA95F5), UInt64(0xBE12B67310AA95F4)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E3B117), UInt64(0x3D9A289EE7E3B118)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FAF3C1C), UInt64(0xBD1BC6250FAF3C1B)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE518B8A), UInt64(0x3C97271CBE518B8B)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073942C46), UInt64(0xBC0F1B4073942C45)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246AB9B94E5), UInt64(0x3B813246AB9B94E6)
    )


def test_table_builder_and_exact_words_count_19() raises:
    _compare_builder(19)
    var proof = _SpiralMomentProof(19)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A001879FFF9), UInt64(0x3EB87A001879FFFA)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E30548708B2), UInt64(0xBE4C2E30548708B1)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E7305), UInt64(0x3DD6F448E13E7306)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E65845D9), UInt64(0xBD5BD577E65845D8)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167D6D08), UInt64(0x3CDA173A167D6D09)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C21108C9AD), UInt64(0xBC5377C21108C9AC)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72240B91D), UInt64(0x3BC7ABD72240B91E)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF06), UInt64(0xBEEBBD779334EF05)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568C58), UInt64(0x3E83777C55568C59)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA99D2), UInt64(0xBE12B67310AA99D1)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E3D854), UInt64(0x3D9A289EE7E3D855)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB01308), UInt64(0xBD1BC6250FB01307)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE546071), UInt64(0x3C97271CBE546072)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073A100C0), UInt64(0xBC0F1B4073A100BF)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABB05621), UInt64(0x3B813246ABB05622)
    )


def test_table_builder_and_exact_words_count_20() raises:
    _compare_builder(20)
    var proof = _SpiralMomentProof(20)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0006), UInt64(0x3EB87A00187A0007)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E30548709B5), UInt64(0xBE4C2E30548709B4)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E7A91), UInt64(0x3DD6F448E13E7A92)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E6587D0F), UInt64(0xBD5BD577E6587D0E)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167E57BE), UInt64(0x3CDA173A167E57BF)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110B4E3F), UInt64(0xBC5377C2110B4E3E)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD7224A53D2), UInt64(0x3BC7ABD7224A53D3)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF08), UInt64(0xBEEBBD779334EF07)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568C87), UInt64(0x3E83777C55568C88)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9BFD), UInt64(0xBE12B67310AA9BFC)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E3EE5B), UInt64(0x3D9A289EE7E3EE5C)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB08BEF), UInt64(0xBD1BC6250FB08BEE)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE55F924), UInt64(0x3C97271CBE55F925)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073A84157), UInt64(0xBC0F1B4073A84156)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABBC1A4C), UInt64(0x3B813246ABBC1A4D)
    )


def test_table_builder_and_exact_words_count_21() raises:
    _compare_builder(21)
    var proof = _SpiralMomentProof(21)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A000D), UInt64(0x3EB87A00187A000E)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870A4A), UInt64(0xBE4C2E3054870A49)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E7EEC), UInt64(0x3DD6F448E13E7EED)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E6589CFC), UInt64(0xBD5BD577E6589CFB)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167EDFB4), UInt64(0x3CDA173A167EDFB5)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110CC46C), UInt64(0xBC5377C2110CC46B)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD7224FEA7F), UInt64(0x3BC7ABD7224FEA80)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0A), UInt64(0xBEEBBD779334EF09)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CA2), UInt64(0x3E83777C55568CA3)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9D3D), UInt64(0xBE12B67310AA9D3C)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E3FB16), UInt64(0x3D9A289EE7E3FB17)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB0D1E8), UInt64(0xBD1BC6250FB0D1E7)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE56E622), UInt64(0x3C97271CBE56E623)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073AC7856), UInt64(0xBC0F1B4073AC7855)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABC2F54C), UInt64(0x3B813246ABC2F54D)
    )


def test_table_builder_and_exact_words_count_22() raises:
    _compare_builder(22)
    var proof = _SpiralMomentProof(22)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0011), UInt64(0x3EB87A00187A0012)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870AA2), UInt64(0xBE4C2E3054870AA1)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E8181), UInt64(0x3DD6F448E13E8182)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658AFEE), UInt64(0xBD5BD577E658AFED)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167F3083), UInt64(0x3CDA173A167F3084)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110DA335), UInt64(0xBC5377C2110DA334)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD722534019), UInt64(0x3BC7ABD72253401A)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0A), UInt64(0xBEEBBD779334EF09)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CB2), UInt64(0x3E83777C55568CB3)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9DFA), UInt64(0xBE12B67310AA9DF9)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E402A3), UInt64(0x3D9A289EE7E402A4)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB0FB75), UInt64(0xBD1BC6250FB0FB74)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE57731C), UInt64(0x3C97271CBE57731D)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073AEFB6C), UInt64(0xBC0F1B4073AEFB6B)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABC70D95), UInt64(0x3B813246ABC70D96)
    )


def test_table_builder_and_exact_words_count_23() raises:
    _compare_builder(23)
    var proof = _SpiralMomentProof(23)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0014), UInt64(0x3EB87A00187A0015)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870AD8), UInt64(0xBE4C2E3054870AD7)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E8312), UInt64(0x3DD6F448E13E8313)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658BB70), UInt64(0xBD5BD577E658BB6F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167F61AD), UInt64(0x3CDA173A167F61AE)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110E2AF5), UInt64(0xBC5377C2110E2AF4)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72255492A), UInt64(0x3BC7ABD72255492B)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0B), UInt64(0xBEEBBD779334EF0A)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CBC), UInt64(0x3E83777C55568CBD)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9E6D), UInt64(0xBE12B67310AA9E6C)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40738), UInt64(0x3D9A289EE7E40739)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB114B9), UInt64(0xBD1BC6250FB114B8)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE57C8F0), UInt64(0x3C97271CBE57C8F1)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B0839F), UInt64(0xBC0F1B4073B0839E)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABC98E20), UInt64(0x3B813246ABC98E21)
    )


def test_table_builder_and_exact_words_count_24() raises:
    _compare_builder(24)
    var proof = _SpiralMomentProof(24)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0015), UInt64(0x3EB87A00187A0016)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870AF9), UInt64(0xBE4C2E3054870AF8)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E840B), UInt64(0x3DD6F448E13E840C)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658C296), UInt64(0xBD5BD577E658C295)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167F803B), UInt64(0x3CDA173A167F803C)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110E7F72), UInt64(0xBC5377C2110E7F71)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD722568DFA), UInt64(0x3BC7ABD722568DFB)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0B), UInt64(0xBEEBBD779334EF0A)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CC2), UInt64(0x3E83777C55568CC3)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9EB5), UInt64(0xBE12B67310AA9EB4)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40A10), UInt64(0x3D9A289EE7E40A11)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1246A), UInt64(0xBD1BC6250FB12469)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE57FE52), UInt64(0x3C97271CBE57FE53)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B177E6), UInt64(0xBC0F1B4073B177E5)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCB1DC2), UInt64(0x3B813246ABCB1DC3)
    )


def test_table_builder_and_exact_words_count_25() raises:
    _compare_builder(25)
    var proof = _SpiralMomentProof(25)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0016), UInt64(0x3EB87A00187A0017)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B0E), UInt64(0xBE4C2E3054870B0D)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E84A8), UInt64(0x3DD6F448E13E84A9)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658C71C), UInt64(0xBD5BD577E658C71B)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167F9399), UInt64(0x3CDA173A167F939A)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110EB50F), UInt64(0xBC5377C2110EB50E)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD722575C64), UInt64(0x3BC7ABD722575C65)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0B), UInt64(0xBEEBBD779334EF0A)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CC6), UInt64(0x3E83777C55568CC7)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9EE2), UInt64(0xBE12B67310AA9EE1)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40BDD), UInt64(0x3D9A289EE7E40BDE)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB12E5A), UInt64(0xBD1BC6250FB12E59)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE58202C), UInt64(0x3C97271CBE58202D)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B21306), UInt64(0xBC0F1B4073B21305)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCC1BE9), UInt64(0x3B813246ABCC1BEA)
    )


def test_table_builder_and_exact_words_count_26() raises:
    _compare_builder(26)
    var proof = _SpiralMomentProof(26)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0017), UInt64(0x3EB87A00187A0018)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B1C), UInt64(0xBE4C2E3054870B1B)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E850D), UInt64(0x3DD6F448E13E850E)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CA07), UInt64(0xBD5BD577E658CA06)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FA018), UInt64(0x3CDA173A167FA019)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110ED7B3), UInt64(0xBC5377C2110ED7B2)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72257E1E9), UInt64(0x3BC7ABD72257E1EA)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0B), UInt64(0xBEEBBD779334EF0A)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CC8), UInt64(0x3E83777C55568CC9)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9EFF), UInt64(0xBE12B67310AA9EFE)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40D06), UInt64(0x3D9A289EE7E40D07)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB134C4), UInt64(0xBD1BC6250FB134C3)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE583609), UInt64(0x3C97271CBE58360A)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B2774E), UInt64(0xBC0F1B4073B2774D)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCCC06D), UInt64(0x3B813246ABCCC06E)
    )


def test_table_builder_and_exact_words_count_27() raises:
    _compare_builder(27)
    var proof = _SpiralMomentProof(27)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B25), UInt64(0xBE4C2E3054870B24)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E8550), UInt64(0x3DD6F448E13E8551)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CBF0), UInt64(0xBD5BD577E658CBEF)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FA84C), UInt64(0x3CDA173A167FA84D)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110EEE74), UInt64(0xBC5377C2110EEE73)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD7225839B7), UInt64(0x3BC7ABD7225839B8)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCA), UInt64(0x3E83777C55568CCB)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F12), UInt64(0xBE12B67310AA9F11)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40DC9), UInt64(0x3D9A289EE7E40DCA)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB138F9), UInt64(0xBD1BC6250FB138F8)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE584463), UInt64(0x3C97271CBE584464)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B2B936), UInt64(0xBC0F1B4073B2B935)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCD2CAD), UInt64(0x3B813246ABCD2CAE)
    )


def test_table_builder_and_exact_words_count_28() raises:
    _compare_builder(28)
    var proof = _SpiralMomentProof(28)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B2A), UInt64(0xBE4C2E3054870B29)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E857C), UInt64(0x3DD6F448E13E857D)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CD36), UInt64(0xBD5BD577E658CD35)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FADC3), UInt64(0x3CDA173A167FADC4)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110EFDA1), UInt64(0xBC5377C2110EFDA0)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD722587457), UInt64(0x3BC7ABD722587458)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCB), UInt64(0x3E83777C55568CCC)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F1E), UInt64(0xBE12B67310AA9F1D)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40E4A), UInt64(0x3D9A289EE7E40E4B)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB13BC6), UInt64(0xBD1BC6250FB13BC5)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE584DF4), UInt64(0x3C97271CBE584DF5)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B2E532), UInt64(0xBC0F1B4073B2E531)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCD74FE), UInt64(0x3B813246ABCD74FF)
    )


def test_table_builder_and_exact_words_count_29() raises:
    _compare_builder(29)
    var proof = _SpiralMomentProof(29)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B2E), UInt64(0xBE4C2E3054870B2D)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E859A), UInt64(0x3DD6F448E13E859B)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CE13), UInt64(0xBD5BD577E658CE12)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB176), UInt64(0x3CDA173A167FB177)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F07E6), UInt64(0xBC5377C2110F07E5)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD722589C0C), UInt64(0x3BC7ABD722589C0D)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCC), UInt64(0x3E83777C55568CCD)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F27), UInt64(0xBE12B67310AA9F26)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40EA2), UInt64(0x3D9A289EE7E40EA3)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB13DAB), UInt64(0xBD1BC6250FB13DAA)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE58546D), UInt64(0x3C97271CBE58546E)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B302F8), UInt64(0xBC0F1B4073B302F7)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCDA5FE), UInt64(0x3B813246ABCDA5FF)
    )


def test_table_builder_and_exact_words_count_30() raises:
    _compare_builder(30)
    var proof = _SpiralMomentProof(30)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B31), UInt64(0xBE4C2E3054870B30)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85AE), UInt64(0x3DD6F448E13E85AF)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CEAA), UInt64(0xBD5BD577E658CEA9)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB3FE), UInt64(0x3CDA173A167FB3FF)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F0EF1), UInt64(0xBC5377C2110F0EF0)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258B74B), UInt64(0x3BC7ABD72258B74C)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCC), UInt64(0x3E83777C55568CCD)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F2D), UInt64(0xBE12B67310AA9F2C)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40EDE), UInt64(0x3D9A289EE7E40EDF)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB13EF7), UInt64(0xBD1BC6250FB13EF6)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5858DD), UInt64(0x3C97271CBE5858DE)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B31764), UInt64(0xBC0F1B4073B31763)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCDC7A3), UInt64(0x3B813246ABCDC7A4)
    )


def test_table_builder_and_exact_words_count_31() raises:
    _compare_builder(31)
    var proof = _SpiralMomentProof(31)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B33), UInt64(0xBE4C2E3054870B32)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85BD), UInt64(0x3DD6F448E13E85BE)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CF12), UInt64(0xBD5BD577E658CF11)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB5C0), UInt64(0x3CDA173A167FB5C1)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F13D5), UInt64(0xBC5377C2110F13D4)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258CA3A), UInt64(0x3BC7ABD72258CA3B)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCC), UInt64(0x3E83777C55568CCD)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F31), UInt64(0xBE12B67310AA9F30)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F08), UInt64(0x3D9A289EE7E40F09)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB13FDD), UInt64(0xBD1BC6250FB13FDC)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE585BF1), UInt64(0x3C97271CBE585BF2)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B32594), UInt64(0xBC0F1B4073B32593)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCDDF05), UInt64(0x3B813246ABCDDF06)
    )


def test_table_builder_and_exact_words_count_32() raises:
    _compare_builder(32)
    var proof = _SpiralMomentProof(32)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B34), UInt64(0xBE4C2E3054870B33)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85C7), UInt64(0x3DD6F448E13E85C8)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CF5C), UInt64(0xBD5BD577E658CF5B)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB6FC), UInt64(0x3CDA173A167FB6FD)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F1744), UInt64(0xBC5377C2110F1743)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258D788), UInt64(0x3BC7ABD72258D789)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F34), UInt64(0xBE12B67310AA9F33)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F25), UInt64(0x3D9A289EE7E40F26)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1407F), UInt64(0xBD1BC6250FB1407E)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE585E1B), UInt64(0x3C97271CBE585E1C)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B32F8C), UInt64(0xBC0F1B4073B32F8B)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCDEF77), UInt64(0x3B813246ABCDEF78)
    )


def test_table_builder_and_exact_words_count_33() raises:
    _compare_builder(33)
    var proof = _SpiralMomentProof(33)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B35), UInt64(0xBE4C2E3054870B34)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85CE), UInt64(0x3DD6F448E13E85CF)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CF90), UInt64(0xBD5BD577E658CF8F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB7DC), UInt64(0x3CDA173A167FB7DD)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F19B5), UInt64(0xBC5377C2110F19B4)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258E0FD), UInt64(0x3BC7ABD72258E0FE)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F36), UInt64(0xBE12B67310AA9F35)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F39), UInt64(0x3D9A289EE7E40F3A)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB140F2), UInt64(0xBD1BC6250FB140F1)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE585FA4), UInt64(0x3C97271CBE585FA5)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B336A1), UInt64(0xBC0F1B4073B336A0)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCDFB27), UInt64(0x3B813246ABCDFB28)
    )


def test_table_builder_and_exact_words_count_34() raises:
    _compare_builder(34)
    var proof = _SpiralMomentProof(34)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B36), UInt64(0xBE4C2E3054870B35)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85D3), UInt64(0x3DD6F448E13E85D4)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CFB5), UInt64(0xBD5BD577E658CFB4)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB87D), UInt64(0x3CDA173A167FB87E)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F1B75), UInt64(0xBC5377C2110F1B74)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258E7C7), UInt64(0x3BC7ABD72258E7C8)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F37), UInt64(0xBE12B67310AA9F36)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F48), UInt64(0x3D9A289EE7E40F49)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14144), UInt64(0xBD1BC6250FB14143)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5860BE), UInt64(0x3C97271CBE5860BF)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B33BB6), UInt64(0xBC0F1B4073B33BB5)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE038C), UInt64(0x3B813246ABCE038D)
    )


def test_table_builder_and_exact_words_count_35() raises:
    _compare_builder(35)
    var proof = _SpiralMomentProof(35)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B36), UInt64(0xBE4C2E3054870B35)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85D6), UInt64(0x3DD6F448E13E85D7)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CFD0), UInt64(0xBD5BD577E658CFCF)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB8F1), UInt64(0x3CDA173A167FB8F2)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F1CB9), UInt64(0xBC5377C2110F1CB8)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258ECB3), UInt64(0x3BC7ABD72258ECB4)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F38), UInt64(0xBE12B67310AA9F37)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F53), UInt64(0x3D9A289EE7E40F54)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14180), UInt64(0xBD1BC6250FB1417F)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE58618A), UInt64(0x3C97271CBE58618B)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B33F64), UInt64(0xBC0F1B4073B33F63)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE09A2), UInt64(0x3B813246ABCE09A3)
    )


def test_table_builder_and_exact_words_count_36() raises:
    _compare_builder(36)
    var proof = _SpiralMomentProof(36)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B37), UInt64(0xBE4C2E3054870B36)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85D9), UInt64(0x3DD6F448E13E85DA)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CFE4), UInt64(0xBD5BD577E658CFE3)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB946), UInt64(0x3CDA173A167FB947)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F1DA7), UInt64(0xBC5377C2110F1DA6)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258F04C), UInt64(0x3BC7ABD72258F04D)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F39), UInt64(0xBE12B67310AA9F38)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F5B), UInt64(0x3D9A289EE7E40F5C)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB141AB), UInt64(0xBD1BC6250FB141AA)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE58621F), UInt64(0x3C97271CBE586220)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34216), UInt64(0xBC0F1B4073B34215)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE0E16), UInt64(0x3B813246ABCE0E17)
    )


def test_table_builder_and_exact_words_count_37() raises:
    _compare_builder(37)
    var proof = _SpiralMomentProof(37)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B37), UInt64(0xBE4C2E3054870B36)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85DB), UInt64(0x3DD6F448E13E85DC)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CFF3), UInt64(0xBD5BD577E658CFF2)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB985), UInt64(0x3CDA173A167FB986)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F1E56), UInt64(0xBC5377C2110F1E55)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258F2F4), UInt64(0x3BC7ABD72258F2F5)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3A), UInt64(0xBE12B67310AA9F39)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F61), UInt64(0x3D9A289EE7E40F62)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB141CB), UInt64(0xBD1BC6250FB141CA)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE58628D), UInt64(0x3C97271CBE58628E)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34413), UInt64(0xBC0F1B4073B34412)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE115F), UInt64(0x3B813246ABCE1160)
    )


def test_table_builder_and_exact_words_count_38() raises:
    _compare_builder(38)
    var proof = _SpiralMomentProof(38)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B37), UInt64(0xBE4C2E3054870B36)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85DC), UInt64(0x3DD6F448E13E85DD)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658CFFE), UInt64(0xBD5BD577E658CFFD)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB9B4), UInt64(0x3CDA173A167FB9B5)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F1ED8), UInt64(0xBC5377C2110F1ED7)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258F4EE), UInt64(0x3BC7ABD72258F4EF)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3A), UInt64(0xBE12B67310AA9F39)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F65), UInt64(0x3D9A289EE7E40F66)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB141E3), UInt64(0xBD1BC6250FB141E2)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5862DF), UInt64(0x3C97271CBE5862E0)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B3458D), UInt64(0xBC0F1B4073B3458C)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE13D1), UInt64(0x3B813246ABCE13D2)
    )


def test_table_builder_and_exact_words_count_39() raises:
    _compare_builder(39)
    var proof = _SpiralMomentProof(39)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B37), UInt64(0xBE4C2E3054870B36)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85DE), UInt64(0x3DD6F448E13E85DF)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D006), UInt64(0xBD5BD577E658D005)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB9D6), UInt64(0x3CDA173A167FB9D7)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F1F39), UInt64(0xBC5377C2110F1F38)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258F669), UInt64(0x3BC7ABD72258F66A)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3A), UInt64(0xBE12B67310AA9F39)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F68), UInt64(0x3D9A289EE7E40F69)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB141F5), UInt64(0xBD1BC6250FB141F4)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE58631C), UInt64(0x3C97271CBE58631D)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B346A8), UInt64(0xBC0F1B4073B346A7)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE15A6), UInt64(0x3B813246ABCE15A7)
    )


def test_table_builder_and_exact_words_count_40() raises:
    _compare_builder(40)
    var proof = _SpiralMomentProof(40)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85DE), UInt64(0x3DD6F448E13E85DF)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D00C), UInt64(0xBD5BD577E658D00B)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FB9F1), UInt64(0x3CDA173A167FB9F2)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F1F83), UInt64(0xBC5377C2110F1F82)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258F787), UInt64(0x3BC7ABD72258F788)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3A), UInt64(0xBE12B67310AA9F39)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F6B), UInt64(0x3D9A289EE7E40F6C)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14203), UInt64(0xBD1BC6250FB14202)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE58634B), UInt64(0x3C97271CBE58634C)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B3477E), UInt64(0xBC0F1B4073B3477D)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1709), UInt64(0x3B813246ABCE170A)
    )


def test_table_builder_and_exact_words_count_41() raises:
    _compare_builder(41)
    var proof = _SpiralMomentProof(41)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85DF), UInt64(0x3DD6F448E13E85E0)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D010), UInt64(0xBD5BD577E658D00F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA05), UInt64(0x3CDA173A167FBA06)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F1FBB), UInt64(0xBC5377C2110F1FBA)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258F861), UInt64(0x3BC7ABD72258F862)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F6C), UInt64(0x3D9A289EE7E40F6D)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1420D), UInt64(0xBD1BC6250FB1420C)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE58636E), UInt64(0x3C97271CBE58636F)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34821), UInt64(0xBC0F1B4073B34820)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1816), UInt64(0x3B813246ABCE1817)
    )


def test_table_builder_and_exact_words_count_42() raises:
    _compare_builder(42)
    var proof = _SpiralMomentProof(42)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85DF), UInt64(0x3DD6F448E13E85E0)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D014), UInt64(0xBD5BD577E658D013)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA14), UInt64(0x3CDA173A167FBA15)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F1FE6), UInt64(0xBC5377C2110F1FE5)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258F908), UInt64(0x3BC7ABD72258F909)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F6E), UInt64(0x3D9A289EE7E40F6F)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14215), UInt64(0xBD1BC6250FB14214)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE586389), UInt64(0x3C97271CBE58638A)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B3489E), UInt64(0xBC0F1B4073B3489D)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE18E4), UInt64(0x3B813246ABCE18E5)
    )


def test_table_builder_and_exact_words_count_43() raises:
    _compare_builder(43)
    var proof = _SpiralMomentProof(43)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E0), UInt64(0x3DD6F448E13E85E1)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D017), UInt64(0xBD5BD577E658D016)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA20), UInt64(0x3CDA173A167FBA21)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2007), UInt64(0xBC5377C2110F2006)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258F988), UInt64(0x3BC7ABD72258F989)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F6F), UInt64(0x3D9A289EE7E40F70)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1421B), UInt64(0xBD1BC6250FB1421A)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE58639D), UInt64(0x3C97271CBE58639E)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B348FE), UInt64(0xBC0F1B4073B348FD)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1983), UInt64(0x3B813246ABCE1984)
    )


def test_table_builder_and_exact_words_count_44() raises:
    _compare_builder(44)
    var proof = _SpiralMomentProof(44)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E0), UInt64(0x3DD6F448E13E85E1)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D019), UInt64(0xBD5BD577E658D018)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA29), UInt64(0x3CDA173A167FBA2A)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2020), UInt64(0xBC5377C2110F201F)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258F9EC), UInt64(0x3BC7ABD72258F9ED)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F70), UInt64(0x3D9A289EE7E40F71)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1421F), UInt64(0xBD1BC6250FB1421E)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863AE), UInt64(0x3C97271CBE5863AF)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34948), UInt64(0xBC0F1B4073B34947)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE19FF), UInt64(0x3B813246ABCE1A00)
    )


def test_table_builder_and_exact_words_count_45() raises:
    _compare_builder(45)
    var proof = _SpiralMomentProof(45)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E0), UInt64(0x3DD6F448E13E85E1)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D01A), UInt64(0xBD5BD577E658D019)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA30), UInt64(0x3CDA173A167FBA31)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2034), UInt64(0xBC5377C2110F2033)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FA39), UInt64(0x3BC7ABD72258FA3A)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F70), UInt64(0x3D9A289EE7E40F71)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14223), UInt64(0xBD1BC6250FB14222)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863BA), UInt64(0x3C97271CBE5863BB)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34982), UInt64(0xBC0F1B4073B34981)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1A5F), UInt64(0x3B813246ABCE1A60)
    )


def test_table_builder_and_exact_words_count_46() raises:
    _compare_builder(46)
    var proof = _SpiralMomentProof(46)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D01C), UInt64(0xBD5BD577E658D01B)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA36), UInt64(0x3CDA173A167FBA37)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2044), UInt64(0xBC5377C2110F2043)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FA76), UInt64(0x3BC7ABD72258FA77)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F71), UInt64(0x3D9A289EE7E40F72)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14226), UInt64(0xBD1BC6250FB14225)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863C4), UInt64(0x3C97271CBE5863C5)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B349AF), UInt64(0xBC0F1B4073B349AE)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1AAA), UInt64(0x3B813246ABCE1AAB)
    )


def test_table_builder_and_exact_words_count_47() raises:
    _compare_builder(47)
    var proof = _SpiralMomentProof(47)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D01D), UInt64(0xBD5BD577E658D01C)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA3A), UInt64(0x3CDA173A167FBA3B)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2050), UInt64(0xBC5377C2110F204F)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FAA6), UInt64(0x3BC7ABD72258FAA7)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F71), UInt64(0x3D9A289EE7E40F72)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14228), UInt64(0xBD1BC6250FB14227)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863CC), UInt64(0x3C97271CBE5863CD)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B349D3), UInt64(0xBC0F1B4073B349D2)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1AE5), UInt64(0x3B813246ABCE1AE6)
    )


def test_table_builder_and_exact_words_count_48() raises:
    _compare_builder(48)
    var proof = _SpiralMomentProof(48)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D01E), UInt64(0xBD5BD577E658D01D)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA3E), UInt64(0x3CDA173A167FBA3F)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F205A), UInt64(0xBC5377C2110F2059)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FACC), UInt64(0x3BC7ABD72258FACD)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F72), UInt64(0x3D9A289EE7E40F73)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1422A), UInt64(0xBD1BC6250FB14229)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863D2), UInt64(0x3C97271CBE5863D3)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B349EF), UInt64(0xBC0F1B4073B349EE)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1B14), UInt64(0x3B813246ABCE1B15)
    )


def test_table_builder_and_exact_words_count_49() raises:
    _compare_builder(49)
    var proof = _SpiralMomentProof(49)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D01E), UInt64(0xBD5BD577E658D01D)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA40), UInt64(0x3CDA173A167FBA41)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2062), UInt64(0xBC5377C2110F2061)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FAEA), UInt64(0x3BC7ABD72258FAEB)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F72), UInt64(0x3D9A289EE7E40F73)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1422B), UInt64(0xBD1BC6250FB1422A)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863D7), UInt64(0x3C97271CBE5863D8)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A06), UInt64(0xBC0F1B4073B34A05)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1B3A), UInt64(0x3B813246ABCE1B3B)
    )


def test_table_builder_and_exact_words_count_50() raises:
    _compare_builder(50)
    var proof = _SpiralMomentProof(50)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D01F), UInt64(0xBD5BD577E658D01E)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA43), UInt64(0x3CDA173A167FBA44)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2068), UInt64(0xBC5377C2110F2067)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB02), UInt64(0x3BC7ABD72258FB03)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F72), UInt64(0x3D9A289EE7E40F73)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1422D), UInt64(0xBD1BC6250FB1422C)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863DA), UInt64(0x3C97271CBE5863DB)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A18), UInt64(0xBC0F1B4073B34A17)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1B58), UInt64(0x3B813246ABCE1B59)
    )


def test_table_builder_and_exact_words_count_51() raises:
    _compare_builder(51)
    var proof = _SpiralMomentProof(51)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D01F), UInt64(0xBD5BD577E658D01E)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA44), UInt64(0x3CDA173A167FBA45)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F206D), UInt64(0xBC5377C2110F206C)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB15), UInt64(0x3BC7ABD72258FB16)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F72), UInt64(0x3D9A289EE7E40F73)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1422D), UInt64(0xBD1BC6250FB1422C)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863DE), UInt64(0x3C97271CBE5863DF)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A26), UInt64(0xBC0F1B4073B34A25)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1B70), UInt64(0x3B813246ABCE1B71)
    )


def test_table_builder_and_exact_words_count_52() raises:
    _compare_builder(52)
    var proof = _SpiralMomentProof(52)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D020), UInt64(0xBD5BD577E658D01F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA46), UInt64(0x3CDA173A167FBA47)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2071), UInt64(0xBC5377C2110F2070)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB25), UInt64(0x3BC7ABD72258FB26)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F72), UInt64(0x3D9A289EE7E40F73)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1422E), UInt64(0xBD1BC6250FB1422D)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863E0), UInt64(0x3C97271CBE5863E1)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A32), UInt64(0xBC0F1B4073B34A31)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1B83), UInt64(0x3B813246ABCE1B84)
    )


def test_table_builder_and_exact_words_count_53() raises:
    _compare_builder(53)
    var proof = _SpiralMomentProof(53)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D020), UInt64(0xBD5BD577E658D01F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA47), UInt64(0x3CDA173A167FBA48)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2074), UInt64(0xBC5377C2110F2073)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB32), UInt64(0x3BC7ABD72258FB33)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F72), UInt64(0x3D9A289EE7E40F73)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1422F), UInt64(0xBD1BC6250FB1422E)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863E2), UInt64(0x3C97271CBE5863E3)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A3B), UInt64(0xBC0F1B4073B34A3A)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1B93), UInt64(0x3B813246ABCE1B94)
    )


def test_table_builder_and_exact_words_count_54() raises:
    _compare_builder(54)
    var proof = _SpiralMomentProof(54)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D020), UInt64(0xBD5BD577E658D01F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA48), UInt64(0x3CDA173A167FBA49)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2077), UInt64(0xBC5377C2110F2076)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB3C), UInt64(0x3BC7ABD72258FB3D)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB1422F), UInt64(0xBD1BC6250FB1422E)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863E4), UInt64(0x3C97271CBE5863E5)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A43), UInt64(0xBC0F1B4073B34A42)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1B9F), UInt64(0x3B813246ABCE1BA0)
    )


def test_table_builder_and_exact_words_count_55() raises:
    _compare_builder(55)
    var proof = _SpiralMomentProof(55)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D020), UInt64(0xBD5BD577E658D01F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA49), UInt64(0x3CDA173A167FBA4A)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2079), UInt64(0xBC5377C2110F2078)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB44), UInt64(0x3BC7ABD72258FB45)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14230), UInt64(0xBD1BC6250FB1422F)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863E5), UInt64(0x3C97271CBE5863E6)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A49), UInt64(0xBC0F1B4073B34A48)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1BAA), UInt64(0x3B813246ABCE1BAB)
    )


def test_table_builder_and_exact_words_count_56() raises:
    _compare_builder(56)
    var proof = _SpiralMomentProof(56)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D020), UInt64(0xBD5BD577E658D01F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA49), UInt64(0x3CDA173A167FBA4A)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F207B), UInt64(0xBC5377C2110F207A)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB4B), UInt64(0x3BC7ABD72258FB4C)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14230), UInt64(0xBD1BC6250FB1422F)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863E6), UInt64(0x3C97271CBE5863E7)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A4E), UInt64(0xBC0F1B4073B34A4D)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1BB2), UInt64(0x3B813246ABCE1BB3)
    )


def test_table_builder_and_exact_words_count_57() raises:
    _compare_builder(57)
    var proof = _SpiralMomentProof(57)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0018), UInt64(0x3EB87A00187A0019)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D020), UInt64(0xBD5BD577E658D01F)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA4A), UInt64(0x3CDA173A167FBA4B)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F207C), UInt64(0xBC5377C2110F207B)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB51), UInt64(0x3BC7ABD72258FB52)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14230), UInt64(0xBD1BC6250FB1422F)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863E7), UInt64(0x3C97271CBE5863E8)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A53), UInt64(0xBC0F1B4073B34A52)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1BB9), UInt64(0x3B813246ABCE1BBA)
    )


def test_table_builder_and_exact_words_count_58() raises:
    _compare_builder(58)
    var proof = _SpiralMomentProof(58)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0019), UInt64(0x3EB87A00187A001A)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D021), UInt64(0xBD5BD577E658D020)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA4A), UInt64(0x3CDA173A167FBA4B)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F207D), UInt64(0xBC5377C2110F207C)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB55), UInt64(0x3BC7ABD72258FB56)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14230), UInt64(0xBD1BC6250FB1422F)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863E8), UInt64(0x3C97271CBE5863E9)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A56), UInt64(0xBC0F1B4073B34A55)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1BBF), UInt64(0x3B813246ABCE1BC0)
    )


def test_table_builder_and_exact_words_count_59() raises:
    _compare_builder(59)
    var proof = _SpiralMomentProof(59)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0019), UInt64(0x3EB87A00187A001A)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D021), UInt64(0xBD5BD577E658D020)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA4B), UInt64(0x3CDA173A167FBA4C)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F207E), UInt64(0xBC5377C2110F207D)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB59), UInt64(0x3BC7ABD72258FB5A)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14231), UInt64(0xBD1BC6250FB14230)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863E9), UInt64(0x3C97271CBE5863EA)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A59), UInt64(0xBC0F1B4073B34A58)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1BC4), UInt64(0x3B813246ABCE1BC5)
    )


def test_table_builder_and_exact_words_count_60() raises:
    _compare_builder(60)
    var proof = _SpiralMomentProof(60)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0019), UInt64(0x3EB87A00187A001A)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D021), UInt64(0xBD5BD577E658D020)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA4B), UInt64(0x3CDA173A167FBA4C)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F207F), UInt64(0xBC5377C2110F207E)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB5C), UInt64(0x3BC7ABD72258FB5D)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14231), UInt64(0xBD1BC6250FB14230)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863E9), UInt64(0x3C97271CBE5863EA)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A5B), UInt64(0xBC0F1B4073B34A5A)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1BC8), UInt64(0x3B813246ABCE1BC9)
    )


def test_table_builder_and_exact_words_count_61() raises:
    _compare_builder(61)
    var proof = _SpiralMomentProof(61)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0019), UInt64(0x3EB87A00187A001A)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D021), UInt64(0xBD5BD577E658D020)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA4B), UInt64(0x3CDA173A167FBA4C)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2080), UInt64(0xBC5377C2110F207F)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB5F), UInt64(0x3BC7ABD72258FB60)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14231), UInt64(0xBD1BC6250FB14230)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863E9), UInt64(0x3C97271CBE5863EA)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A5D), UInt64(0xBC0F1B4073B34A5C)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1BCB), UInt64(0x3B813246ABCE1BCC)
    )


def test_table_builder_and_exact_words_count_62() raises:
    _compare_builder(62)
    var proof = _SpiralMomentProof(62)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0019), UInt64(0x3EB87A00187A001A)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D021), UInt64(0xBD5BD577E658D020)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA4B), UInt64(0x3CDA173A167FBA4C)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2080), UInt64(0xBC5377C2110F207F)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB61), UInt64(0x3BC7ABD72258FB62)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14231), UInt64(0xBD1BC6250FB14230)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863EA), UInt64(0x3C97271CBE5863EB)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A5F), UInt64(0xBC0F1B4073B34A5E)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1BCE), UInt64(0x3B813246ABCE1BCF)
    )


def test_table_builder_and_exact_words_count_63() raises:
    _compare_builder(63)
    var proof = _SpiralMomentProof(63)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0019), UInt64(0x3EB87A00187A001A)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D021), UInt64(0xBD5BD577E658D020)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA4C), UInt64(0x3CDA173A167FBA4D)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2081), UInt64(0xBC5377C2110F2080)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB63), UInt64(0x3BC7ABD72258FB64)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14231), UInt64(0xBD1BC6250FB14230)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863EA), UInt64(0x3C97271CBE5863EB)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A60), UInt64(0xBC0F1B4073B34A5F)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1BD0), UInt64(0x3B813246ABCE1BD1)
    )


def test_table_builder_and_exact_words_count_64() raises:
    _compare_builder(64)
    var proof = _SpiralMomentProof(64)
    _word_pair(
        proof, False, 0, UInt64(0x3FF0000000000000), UInt64(0x3FF0000000000001)
    )
    _word_pair(
        proof, False, 1, UInt64(0xBFB999999999999B), UInt64(0xBFB999999999999A)
    )
    _word_pair(
        proof, False, 2, UInt64(0x3F72F684BDA12F68), UInt64(0x3F72F684BDA12F69)
    )
    _word_pair(
        proof, False, 3, UInt64(0xBF1C01C01C01C01D), UInt64(0xBF1C01C01C01C01C)
    )
    _word_pair(
        proof, False, 4, UInt64(0x3EB87A00187A0019), UInt64(0x3EB87A00187A001A)
    )
    _word_pair(
        proof, False, 5, UInt64(0xBE4C2E3054870B38), UInt64(0xBE4C2E3054870B37)
    )
    _word_pair(
        proof, False, 6, UInt64(0x3DD6F448E13E85E1), UInt64(0x3DD6F448E13E85E2)
    )
    _word_pair(
        proof, False, 7, UInt64(0xBD5BD577E658D021), UInt64(0xBD5BD577E658D020)
    )
    _word_pair(
        proof, False, 8, UInt64(0x3CDA173A167FBA4C), UInt64(0x3CDA173A167FBA4D)
    )
    _word_pair(
        proof, False, 9, UInt64(0xBC5377C2110F2081), UInt64(0xBC5377C2110F2080)
    )
    _word_pair(
        proof, False, 10, UInt64(0x3BC7ABD72258FB65), UInt64(0x3BC7ABD72258FB66)
    )
    _word_pair(
        proof, True, 0, UInt64(0x3FD5555555555555), UInt64(0x3FD5555555555556)
    )
    _word_pair(
        proof, True, 1, UInt64(0xBF98618618618619), UInt64(0xBF98618618618618)
    )
    _word_pair(
        proof, True, 2, UInt64(0x3F48D3018D3018D3), UInt64(0x3F48D3018D3018D4)
    )
    _word_pair(
        proof, True, 3, UInt64(0xBEEBBD779334EF0C), UInt64(0xBEEBBD779334EF0B)
    )
    _word_pair(
        proof, True, 4, UInt64(0x3E83777C55568CCD), UInt64(0x3E83777C55568CCE)
    )
    _word_pair(
        proof, True, 5, UInt64(0xBE12B67310AA9F3B), UInt64(0xBE12B67310AA9F3A)
    )
    _word_pair(
        proof, True, 6, UInt64(0x3D9A289EE7E40F73), UInt64(0x3D9A289EE7E40F74)
    )
    _word_pair(
        proof, True, 7, UInt64(0xBD1BC6250FB14231), UInt64(0xBD1BC6250FB14230)
    )
    _word_pair(
        proof, True, 8, UInt64(0x3C97271CBE5863EA), UInt64(0x3C97271CBE5863EB)
    )
    _word_pair(
        proof, True, 9, UInt64(0xBC0F1B4073B34A62), UInt64(0xBC0F1B4073B34A61)
    )
    _word_pair(
        proof, True, 10, UInt64(0x3B813246ABCE1BD2), UInt64(0x3B813246ABCE1BD3)
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
