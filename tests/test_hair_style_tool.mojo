# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the hairstyle converter, `tools/hair_style.mojo`."""

from std.math import cos, pi, sin, sqrt
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)

from tools._process import run_program
from tools._struct import pack_f32, pack_u32, unpack_f32, unpack_u32
from tools.hair_style import (
    Encoded,
    V3,
    convert,
    cranium_frame,
    fit_cranium,
    fit_crest,
    layered,
    mohawk,
    ordered_sum,
    read_tfx,
    resample,
    run,
    write,
)


def _tfx_bytes(strands: List[List[V3]]) raises -> List[UInt8]:
    """Return strands as a TressFX 4 file: its header, then each point as
    four floats."""
    var body = List[UInt8]()
    pack_f32(body, 4.0)
    pack_u32(body, len(strands))
    pack_u32(body, len(strands[0]))
    pack_u32(body, 160)
    while len(body) < 160:
        body.append(0)
    for strand in strands:
        for p in strand:
            pack_f32(body, p.x)
            pack_f32(body, p.y)
            pack_f32(body, p.z)
            pack_f32(body, 1.0)
    return body^


def _write(path: String, data: List[UInt8]) raises:
    """Write bytes to a file."""
    Path(path).write_bytes(Span(data))


def _head(
    radii: V3 = V3(0.08, 0.09, 0.1),
    center: V3 = V3(0.0, 1.5, 0.0),
    count: Int = 12,
) -> List[List[V3]]:
    """Return strands rooted on an ellipsoid's upper half, each hanging
    straight down four centimeters."""
    var strands = List[List[V3]]()
    for i in range(count):
        for j in range(1, 4):
            var a = 2 * pi * Float64(i) / Float64(count)
            var b = pi / 2 * Float64(j) / 4
            var q = V3(cos(b) * cos(a), sin(b), cos(b) * sin(a))
            var root = V3(
                center.x + q.x * radii.x,
                center.y + q.y * radii.y,
                center.z + q.z * radii.z,
            )
            var strand = List[V3]()
            for t in range(5):
                strand.append(V3(root.x, root.y - 0.01 * Float64(t), root.z))
            strands.append(strand^)
    return strands^


def _crest(first: Int = -28, last: Int = 150) -> List[List[V3]]:
    """Return strands rooted round a circle in the midline's plane, from
    the brow back past the nape, each standing straight out."""
    var strands = List[List[V3]]()
    for step in range(first, last, 10):
        var angle = Float64(step) * pi / 180
        # Up along y and back along minus z from the center (0, 1, 0).
        var root = V3(0.0, 1.0 + 0.2 * cos(angle), -0.2 * sin(angle))
        var out = V3(0.0, cos(angle), -sin(angle))
        var strand = List[V3]()
        for t in range(3):
            var s = 0.02 * Float64(t)
            strand.append(
                V3(root.x + out.x * s, root.y + out.y * s, root.z + out.z * s)
            )
        strands.append(strand^)
    return strands^


def _close(a: Float64, b: Float64, places: Int = 7) raises:
    """Assert as `assertAlmostEqual` does: equal to `places` decimals."""
    var tolerance = 0.5
    for _ in range(places):
        tolerance /= 10
    assert_true(abs(a - b) <= tolerance, String(a) + " != " + String(b))


def _line() -> List[List[V3]]:
    """Return one strand of three points along y."""
    return [[V3(0, 0, 0), V3(0, 1, 0), V3(0, 3, 0)]]


def _assert_line(strands: List[List[V3]]) raises:
    """Assert that strands are `_line()`."""
    assert_equal(len(strands), 1)
    var expected = _line()
    assert_equal(len(strands[0]), 3)
    for i in range(3):
        assert_true(strands[0][i] == expected[0][i])


def _folder() raises -> String:
    """Return a new temporary folder."""
    return mkdtemp(prefix="hair style test ")


def _remove(folder: String) raises:
    """Remove a temporary folder."""
    _ = run_program(["rm", "-rf", folder], 10)


def test_recipe_summation_has_explicit_rounding_order() raises:
    # Built-in sum uses compensated addition starting with Python 3.12.
    # The production recipe must keep its original one-step rounding.
    assert_equal(ordered_sum([1e16, 1.0, -1e16]), 0.0)
    assert_equal(ordered_sum([1e16, -1e16, 1.0]), 1.0)
    assert_equal(ordered_sum(List[Float64]()), 0.0)


def test_reads_and_resamples_a_tfx_file() raises:
    var folder = _folder()
    var path = folder + "/hair.tfx"
    var data = _tfx_bytes(_line())
    _write(path, data)
    _assert_line(read_tfx(path))
    var short = List[UInt8](data[:8])
    var cut = List[UInt8](data[: len(data) - 4])
    var empty = List[UInt8]()
    pack_f32(empty, 4.0)
    pack_u32(empty, 0)
    pack_u32(empty, 3)
    pack_u32(empty, 16)
    for content in [short^, cut^, empty^]:
        _write(folder + "/bad", content)
        with assert_raises():
            _ = read_tfx(folder + "/bad")
    _remove(folder)
    var even = resample(_line()[0], 4)
    for k in range(4):
        _close(even[k].y, Float64(k))
    # A strand of no length stays at its root.
    var still = resample([V3(1, 1, 1), V3(1, 1, 1)], 3)
    assert_equal(len(still), 3)
    for p in still:
        assert_true(p == V3(1, 1, 1))
    with assert_raises(contains="two points"):
        _ = resample([V3(1, 1, 1)], 3)


def _with_float(
    data: List[UInt8], at: Int, value: Float64
) raises -> List[UInt8]:
    """Return a copy with a float packed at an offset."""
    var bytes = List[UInt8]()
    pack_f32(bytes, value)
    var out = data.copy()
    for k in range(4):
        out[at + k] = bytes[k]
    return out^


def _with_u32(data: List[UInt8], at: Int, value: Int) raises -> List[UInt8]:
    """Return a copy with an unsigned 32-bit integer packed at an offset."""
    var bytes = List[UInt8]()
    pack_u32(bytes, value)
    var out = data.copy()
    for k in range(4):
        out[at + k] = bytes[k]
    return out^


def test_rejects_invalid_versions_offsets_and_nonfinite_positions() raises:
    var folder = _folder()
    var path = folder + "/hair.tfx"
    var valid = _tfx_bytes(_line())
    var inf = Float64.MAX_FINITE * 2
    var nan = inf - inf
    var malformed = List[List[UInt8]]()
    for version in [3.0, 5.0, 99.0, nan, inf]:
        malformed.append(_with_float(valid, 0, version))
    for offset in [0, 16, 152, 161, len(valid) + 8]:
        malformed.append(_with_u32(valid, 12, offset))
    # Counts so large that their product would overflow.
    malformed.append(_with_u32(_with_u32(valid, 4, 0xFFFFFFFF), 8, 0xFFFFFFFF))
    for component in range(3):
        for value in [nan, inf, -inf]:
            malformed.append(_with_float(valid, 160 + component * 4, value))
    malformed.append(List[UInt8](valid[:159]))
    var target = folder + "/existing.bin"
    Path(target).write_text("preserve")
    for data in malformed:
        _write(path, data)
        with assert_raises():
            _ = read_tfx(path)
        with assert_raises():
            _ = convert("layered", path, target)
        assert_equal(Path(target).read_text(), "preserve")
    var padded = List[UInt8](valid[:160])
    for _ in range(8):
        padded.append(0)
    padded.extend(List[UInt8](valid[160:]))
    padded = _with_u32(_with_float(padded, 0, 4.1), 12, 168)
    _write(path, padded)
    _assert_line(read_tfx(path))
    _remove(folder)


def test_fits_a_cranium_and_a_crest() raises:
    var radii = V3(0.08, 0.09, 0.1)
    var roots = List[V3]()
    for strand in _head(radii):
        roots.append(strand[0])
    var cranium = fit_cranium(roots)
    _close(cranium.center.y, 1.5, 6)
    for k in range(3):
        _close(cranium.radii[k], radii[k], 6)
    var crest_roots = List[V3]()
    for strand in _crest():
        crest_roots.append(strand[0])
    var crest = fit_crest(crest_roots)
    _close(crest.center.y, 1.0, 6)
    _close(crest.radius, 0.2, 6)
    # Too few points fix no circle: a pivot is zero.
    with assert_raises(contains="division by zero"):
        _ = fit_crest(List[V3]())


def test_the_cranium_frame() raises:
    var frame = cranium_frame(V3(0, 1, 0), V3(1, 1, 1))
    assert_true(frame[0] == V3(1, 0, 0))
    assert_true(frame[1] == V3(0, 1, 0))
    _close(frame[2].z, -1)
    # At the side's pole plus x is the normal: across is plus z.
    frame = cranium_frame(V3(1, 0, 0), V3(1, 1, 1))
    assert_true(frame[0] == V3(0, 0, 1))
    assert_equal(String(frame[0]), "(0.0, 0.0, 1.0)")
    with assert_raises(contains="division by zero"):
        _ = cranium_frame(V3(1, 0, 0), V3(0, 1, 1))


def test_layered_and_mohawk_styles() raises:
    var encoded = layered(_head())
    var q = encoded[0].q
    _close(sqrt(q.x * q.x + q.y * q.y + q.z * q.z), 1)
    assert_true(encoded[0].offsets[0] == V3(0, 0, 0))
    var crest = mohawk(_crest())
    # The strands before the brow and past the nape are left out.
    assert_equal(len(crest), 11)
    for item in crest:
        _close(sqrt(item.q.x**2 + item.q.y**2 + item.q.z**2), 1)
    with assert_raises(contains="crest"):
        _ = mohawk(_crest(128, 178))


def test_writes_and_converts() raises:
    var folder = _folder()
    var source = folder + "/hair.tfx"
    _write(source, _tfx_bytes(_head()))
    var target = folder + "/hair.bin"
    assert_equal(convert("layered", source, target), 36)
    var body = Path(target).read_bytes()
    assert_equal(String(unsafe_from_utf8=body[:4]), "THRS")
    assert_equal(unpack_u32(Span(body), 4), 1)
    assert_equal(unpack_u32(Span(body), 8), 36)
    assert_equal(unpack_u32(Span(body), 12), 16)
    var roots = 20 + 36 * 6
    assert_equal(len(body), roots + 36 * 16 * 6)
    _write(source, _tfx_bytes(_crest()))
    assert_equal(convert("mohawk", source, target), 11)
    with assert_raises(contains="layered or mohawk"):
        _ = convert("bun", source, target)
    # A style whose strands never leave their roots.
    var still = folder + "/still.bin"
    _ = write(still, [Encoded(V3(0, 1, 0), [V3(0, 0, 0), V3(0, 0, 0)])])
    var scale = unpack_f32(Span(Path(still).read_bytes()), 16)
    _close(scale, 1.0 / 32767)
    with assert_raises(contains="needs a strand"):
        _ = write(still, List[Encoded]())
    _remove(folder)


def test_main() raises:
    var outcome = run(["x"])
    assert_equal(outcome[0], 2)
    assert_true(outcome[2].startswith("Convert a TressFX hair file"))
    var folder = _folder()
    var source = folder + "/hair.tfx"
    _write(source, _tfx_bytes(_head()))
    var target = folder + "/hair.bin"
    outcome = run(["x", "layered", source, target])
    _remove(folder)
    assert_equal(outcome[0], 0)
    assert_equal(outcome[1], "strands: 36\n")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
