# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The GLSL 614 reference tool builds the committed catalog.

CI has no EGL, so these tests check the parts that do not render: the
catalog, the analytical sampler, the comparison and the file reader. The
expected digits are those of the committed TSV files and of CPython 3.13.
docs/fixtures/glsl614/README.md has the rendered comparison.
"""

from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

from tools._python_math import hypot, log2, power
from tools.reference_glsl614 import (
    TOLERANCE,
    Case,
    TextureRecipe,
    catalog,
    compare,
    float_tsv,
    hex4,
    hex8,
    little_endian_hex,
    load_library,
    read_cases,
    sample_level,
    texture_expected,
    uint_tsv,
    wrap_index,
)

comptime FIXTURES = "docs/fixtures/glsl614/"


def _find(cases: List[Case], name: String) raises -> Int:
    """Return the position of a case by name."""
    for i in range(len(cases)):
        if cases[i].id == name:
            return i
    raise Error("no case " + name)


def test_catalog_has_the_committed_counts() raises:
    var cases = catalog()
    assert_equal(len(cases), 150)
    var counts: List[Int] = [0, 0, 0]
    for fixture in cases:
        if fixture.category == "uint":
            counts[0] += 1
        elif fixture.category == "loops":
            counts[1] += 1
        elif fixture.category == "textureGrad":
            counts[2] += 1
    assert_equal(counts[0], 87)
    assert_equal(counts[1], 35)
    assert_equal(counts[2], 28)
    assert_equal(cases[0].id, "uint_literal_boundaries")
    assert_equal(cases[149].id, "textureGrad_constant_arguments")


def test_catalog_writes_the_committed_tsv_files() raises:
    var cases = catalog()
    assert_equal(
        uint_tsv(cases), Path(FIXTURES + "expected_uint32.tsv").read_text()
    )
    assert_equal(
        float_tsv(cases), Path(FIXTURES + "expected_float32.tsv").read_text()
    )


def test_catalog_matches_the_recorded_cases() raises:
    var generated = catalog()
    var recorded = read_cases(Path(FIXTURES + "fixtures.json").read_text())
    assert_equal(len(recorded), len(generated))
    for i in range(len(generated)):
        ref a = generated[i]
        ref b = recorded[i]
        assert_equal(a.id, b.id)
        assert_equal(a.fragment_source, b.fragment_source)
        assert_equal(a.comparison, b.comparison)
        assert_true(a.expected_ints == b.expected_ints)
        assert_true(a.expected_floats == b.expected_floats)
        assert_equal(a.analytic_lod, b.analytic_lod)
        assert_equal(len(a.uniforms), len(b.uniforms))
        assert_equal(a.texture.min_filter, b.texture.min_filter)
        assert_equal(a.texture.wrap_s, b.texture.wrap_s)


def test_selected_expectations() raises:
    var cases = catalog()
    var wrap = cases[_find(cases, "uint_uniform_wrap")].expected_ints.copy()
    assert_true(wrap == [0, 1, 4278190079, 1])
    var shifted = cases[
        _find(cases, "uint_uniform_shift_left")
    ].expected_ints.copy()
    assert_true(shifted == [16777217, 33554434, 65536, 2147483648])
    ref effects = cases[_find(cases, "while_condition_effects_256")]
    assert_true(effects.expected_ints == [256, 32896, 257, 1])
    ref bound = cases[_find(cases, "do_runtime_bound_65")]
    assert_true(bound.expected_ints == [65, 1090519099, 16777217, 65])
    ref source = cases[_find(cases, "uint_payload_1_constant")].fragment_source
    assert_true(
        "uvec4(0x7fc00001u, 0xff800000u, 0xffffffffu, 0x007fffffu)" in source
    )


def test_wrap_index_follows_python_modulo() raises:
    assert_equal(wrap_index(-3, 16, "clamp"), 0)
    assert_equal(wrap_index(20, 16, "clamp"), 15)
    assert_equal(wrap_index(-3, 16, "repeat"), 13)
    assert_equal(wrap_index(21, 16, "repeat"), 5)
    assert_equal(wrap_index(-3, 8, "mirror"), 2)
    assert_equal(wrap_index(10, 8, "mirror"), 5)
    assert_equal(wrap_index(21, 16, "mirror"), 10)


def test_sample_level_nearest_and_bilinear() raises:
    var clamp = TextureRecipe("nearest_mipmap_nearest", "clamp", "clamp")
    var nearest = sample_level(0, [0.34375, 0.6875], clamp, False)
    assert_true(nearest == [0.125, 0.3125, 0.625, 1.0])
    var mirror = TextureRecipe("nearest_mipmap_nearest", "mirror", "mirror")
    var mirrored = sample_level(0, [1.34375, -0.3125], mirror, False)
    assert_true(mirrored == [0.125, 0.625, 0.25, 1.0])
    var linear = TextureRecipe("linear_mipmap_linear", "clamp", "clamp")
    var filtered = sample_level(0, [0.375, 0.625], linear, True)
    assert_true(filtered == [0.125, 0.34375, 0.5625, 1.0])


def test_texture_expected_matches_the_committed_digits() raises:
    var diagonal = texture_expected(
        [0.34375, 0.6875],
        [Float64(Float32(0.15)), Float64(Float32(0.4))],
        [0.0, 0.0],
        TextureRecipe("nearest_mipmap_nearest", "clamp", "clamp"),
    )
    assert_true(diagonal[0] == [0.375, 0.0625, 0.125, 1.0])
    assert_equal(String(diagonal[1]), "2.00000003439653")
    var trilinear = texture_expected(
        [0.375, 0.625],
        [Float64(Float32(power(2.0, 1.5) / 16.0)), 0.0],
        [0.0, 0.0],
        TextureRecipe("linear_mipmap_linear", "clamp", "clamp"),
    )
    assert_equal(String(trilinear[1]), "1.4999999753093258")
    assert_equal(String(trilinear[0][0]), "0.3124999969136657")
    assert_equal(String(trilinear[0][1]), "0.10937500231475071")
    assert_equal(String(trilinear[0][2]), "0.17187500385791785")


def test_python_math_digits() raises:
    # repr(math.hypot(...)) and repr(math.log2(...)) from CPython 3.13.
    assert_equal(
        String(hypot(2.4000000953674316, 3.200000047683716)),
        "4.000000095367432",
    )
    assert_equal(String(hypot(-3.0, 4.0)), "5.0")
    assert_equal(String(hypot(0.0, 0.0)), "0.0")
    assert_equal(String(log2(4.000000095367432)), "2.00000003439653")


def test_compare_exact_and_float() raises:
    var cases = catalog()
    var exact = cases[_find(cases, "uint_literal_boundaries")].copy()
    var passed = compare(exact, [16777215, 16777216, 16777217, 4294967295])
    assert_true(passed.passed)
    assert_false(compare(exact, [16777215, 16777216, 16777217, 0]).passed)
    var lanes = cases[_find(cases, "textureGrad_mip_0")].copy()
    assert_equal(lanes.tolerance, TOLERANCE)
    # 0.125, 0.3125, 0.625 and 1.0 as float32 words.
    var words: List[Int] = [0x3E000000, 0x3EA00000, 0x3F200000, 0x3F800000]
    var outcome = compare(lanes, words)
    assert_true(outcome.passed)
    assert_true(outcome.floats == [0.125, 0.3125, 0.625, 1.0])
    words[0] = 0x3E000100
    assert_false(compare(lanes, words).passed)
    words[0] = 0x7FC00000
    assert_false(compare(lanes, words).passed)


def test_hex_text() raises:
    assert_equal(hex8(0x7F800000), "7f800000")
    assert_equal(hex4(0x3001), "3001")
    assert_equal(hex4(0x502), "0502")
    assert_equal(
        little_endian_hex([16777215, 1, 0, 4294967295]),
        "ffffff000100000000000000ffffffff",
    )


def test_reader_keeps_uniform_values() raises:
    var cases = read_cases(Path(FIXTURES + "short_circuit.json").read_text())
    assert_equal(len(cases), 19)
    for fixture in cases:
        assert_true(fixture.exact())
        assert_equal(len(fixture.expected_ints), 4)
    var recorded = read_cases(Path(FIXTURES + "fixtures.json").read_text())
    var uv = recorded[_find(recorded, "textureGrad_diagonal")].uniforms.copy()
    assert_equal(uv[0].name, "dx")
    assert_true(uv[0].floats == [0.15000000596046448, 0.4000000059604645])


def test_a_missing_library_has_a_clear_error() raises:
    try:
        _ = load_library("libthreemojo_missing_egl.so.1")
    except error:
        var message = String(error)
        assert_true("cannot load libthreemojo_missing_egl.so.1" in message)
        assert_true("Mesa" in message)
        return
    raise Error("a missing library loaded")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
