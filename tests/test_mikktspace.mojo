# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.mikktspace`.

The expected numbers are what three.js 0.180's WebAssembly MikkTSpace gives
under node, for the same input built the same way. The thresholds other
than 180 degrees, which three.js cannot ask for, and the surfaces the
WebAssembly build fails on, are checked against `mikktspace.c` itself,
built with `gcc -ffp-contract=off`. The two agree with each other to
within 5e-10 on every surface both run."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, TANGENT, UV
from geometries.mikktspace import (
    SORT_SEED,
    _Edge,
    _quick_sort,
    _quick_sort_edges,
    compute_mikktspace_tangents,
    generate_tangents,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE


def normal_of(k: Int) -> List[Float32]:
    """Return one of the three normals the reference cycles through."""
    if k % 3 == 0:
        return [0, 0, 1]
    if k % 3 == 1:
        return [0, 0.6, 0.8]
    return [0.6, 0, 0.8]


def grid(n: Int, mirror: Bool) raises -> BufferGeometry:
    """Return the reference's indexed bumpy grid; `mirror` folds `u`
    about the middle column."""
    var pos = List[Float32]()
    var nor = List[Float32]()
    var uv = List[Float32]()
    var index = List[Int]()
    for j in range(n + 1):
        for i in range(n + 1):
            pos.append(Float32(Float64(i) * 0.25))
            pos.append(Float32(Float64(j) * 0.25))
            pos.append(Float32(Float64((i * 7 + j * 3) % 5) * 0.1))
            nor.extend(normal_of(i + j))
            if mirror:
                uv.append(Float32(Float64(abs(2 * i - n)) / Float64(n)))
            else:
                uv.append(Float32(Float64(i) / Float64(n)))
            uv.append(Float32(Float64(j) / Float64(n)))
    for j in range(n):
        for i in range(n):
            var a = j * (n + 1) + i
            var b = a + 1
            var c = a + n + 1
            var d = c + 1
            index.extend([a, b, d, a, d, c])
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(pos^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(nor^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uv^, 2))
    geometry.set_index(index^)
    return geometry^


def tangents_of(
    geometry: BufferGeometry, threshold: Float32 = 180
) raises -> List[Float32]:
    """Return the raw MikkTSpace tangents of a geometry's triangles."""
    var flat = geometry.to_non_indexed()
    return generate_tangents(
        flat.attribute_view(String(POSITION)).packed(),
        flat.attribute_view(String(NORMAL)).packed(),
        flat.attribute_view(String(UV)).packed(),
        Angle(threshold, DEGREE),
    )


def check_sums(tangents: List[Float32], sum: Float64, weighted: Float64) raises:
    """Check the reference's two checksums of a list of tangents: the sum,
    and the sum of magnitudes weighted by position modulo seven."""
    var s = 0.0
    var w = 0.0
    for i in range(len(tangents)):
        s += Float64(tangents[i])
        w += abs(Float64(tangents[i])) * Float64(i % 7 + 1)
    if abs(s - sum) > 1e-5 or abs(w - weighted) > 1e-5:
        raise Error(
            "sums "
            + String(s)
            + ", "
            + String(w)
            + " but expected "
            + String(sum)
            + ", "
            + String(weighted)
        )


def check(
    actual: List[Float32], expected: List[Float64], start: Int = 0
) raises:
    """Check a run of numbers from `start`, each to within 1e-6."""
    for i in range(len(expected)):
        if abs(Float64(actual[start + i]) - expected[i]) > 1e-6:
            raise Error(
                "entry "
                + String(start + i)
                + ": expected "
                + String(expected[i])
                + " but got "
                + String(actual[start + i])
            )


def test_a_grid_matches_three() raises:
    var tangents = tangents_of(grid(4, False))
    assert_equal(len(tangents), 96 * 4)
    check_sums(tangents, 165.21591144800186, 847.7962030768394)
    check(
        tangents,
        [
            1,
            0,
            0,
            1,
            0.9015231132507324,
            -0.3461848795413971,
            0.2596386671066284,
            1,
            0.7999998927116394,
            0,
            -0.6000000834465027,
            1,
        ],
    )
    check(
        tangents,
        [
            1,
            0,
            0,
            1,
            0.7999998927116394,
            0,
            -0.6000000834465027,
            1,
            0.7999998927116394,
            0,
            -0.6000001430511475,
            1,
        ],
        40,
    )


def test_a_mirrored_grid_matches_three() raises:
    var tangents = tangents_of(grid(4, True))
    check_sums(tangents, -0.17432422190904617, 853.6020163372159)
    check(
        tangents,
        [
            -1,
            0,
            0,
            -1,
            -0.7999998927116394,
            0,
            0.6000000834465027,
            -1,
            0.7999999523162842,
            0,
            -0.6000000834465027,
            1,
        ],
        40,
    )
    var signs = String()
    for corner in range(96):
        signs += "-" if tangents[corner * 4 + 3] < 0 else "+"
    var rows = String()
    for _ in range(4):
        rows += "------------++++++++++++"
    assert_equal(signs, rows)


def test_a_threshold_splits_what_turns_too_far() raises:
    var thirty = tangents_of(grid(4, True), 30)
    check_sums(thirty, -0.11341845399999984, 887.412219333)
    check(
        thirty,
        [
            -1,
            0,
            0,
            -1,
            -0.799999774,
            0,
            0.600000143,
            -1,
            0.799999952,
            0,
            -0.600000024,
            1,
        ],
        40,
    )
    var ninety = tangents_of(grid(4, True), 90)
    check_sums(ninety, -0.1743242195999981, 853.6020163441999)
    with assert_raises():
        _ = tangents_of(grid(1, False), inf[DType.float32]())


def special() raises -> BufferGeometry:
    """Return the reference's triangles with every special case, all
    facing +z: see the comment beside each."""
    var pos: List[Float32] = [
        0,
        0,
        0,
        1,
        0,
        0,
        1,
        1,
        0,  # half a quad
        0,
        0,
        0,
        1,
        1,
        0,
        0,
        1,
        0,  # the other half
        0,
        0,
        0,
        0,
        0,
        0,
        2,
        2,
        0,  # degenerate, on a good vertex
        5,
        5,
        5,
        5,
        5,
        5,
        6,
        5,
        5,  # degenerate, alone
        1,
        1,
        0,
        1,
        0,
        0,
        2,
        1,
        0,  # no area in uv, beside the first
        3,
        0,
        0,
        4,
        0,
        0,
        5,
        0,
        0,  # in a line, no u direction
        3,
        1,
        0,
        4,
        1,
        0,
        5,
        1,
        0,  # in a line, no v direction
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        -1,
        0,  # the first edge, the same way round
        7,
        0,
        0,
        8,
        0,
        0,
        7,
        1,
        0,  # three triangles on one edge
        7,
        0,
        0,
        7,
        1,
        0,
        6,
        0,
        0,
        7,
        0,
        0,
        7,
        1,
        0,
        7,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        -1,
        0,
        0,  # mirrored, beside the second
        10,
        0,
        0,
        11,
        0,
        0,
        11,
        1,
        0,  # mirrored
        11,
        1,
        0,
        11,
        0,
        0,
        12,
        1,
        0,  # no area in uv, beside that
    ]
    var uv: List[Float32] = [
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        1,
        1,
        0,
        1,
        2,
        0,
        0,
        1,
        1,
        1,
        2,
        0,
        0,
        1,
        1,
        2,
        1,
        0,
        0,
        1,
        0,
        0,
        -1,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        -1,
        0,
        0,
        0,
        0,
        1,
        0.5,
        0.5,
        0,
        0,
        0,
        1,
        1,
        0,
        0,
        0,
        -1,
        0,
        -1,
        1,
        -1,
        1,
        -1,
        0,
        -1,
        2,
    ]
    var nor = List[Float32]()
    for _ in range(42):
        nor.extend([Float32(0), 0, 1])
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(pos^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(nor^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uv^, 2))
    return geometry^


def test_every_special_case_matches_three() raises:
    var tangents = tangents_of(special())
    check_sums(tangents, 11, 332)
    for corner in range(36, 41):
        check(tangents, [-1, 0, 0, -1], corner * 4)
    check(tangents, [1, 0, 0, -1], 41 * 4)
    var signs: List[Float64] = [
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        1,
        -1,
        -1,
        -1,
        -1,
        1,
        1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        1,
        1,
        1,
        1,
        1,
        1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
    ]
    for corner in range(30):
        check(tangents, [1, 0, 0, signs[corner]], corner * 4)
    check(tangents, [0, -1, 0, -1, 0, 0, 0, -1, 0, -1, 0, -1], 120)
    for corner in range(33, 36):
        check(tangents, [-1, 0, 0, -1], corner * 4)


def test_the_quicksorts_sort_as_the_c_does() raises:
    # The seed picks the pivots, and [1, 2, 0, 3] is the first order in
    # which a pass ends with no swap left to make.
    var cases: List[List[Int]] = [
        [3, 1, 2],
        [1, 2, 0, 3],
        [5, 4, 3, 2, 1, 0, 6],
    ]
    for values in cases:
        var sorted = values.copy()
        _quick_sort(sorted, 0, len(sorted) - 1, SORT_SEED)
        for i in range(1, len(sorted)):
            assert_true(sorted[i - 1] <= sorted[i])
        var edges = List[_Edge]()
        for i in range(len(values)):
            edges.append(_Edge(values[i], 0, i))
        _quick_sort_edges(edges, 0, len(edges) - 1, 0, SORT_SEED)
        for i in range(1, len(edges)):
            assert_true(edges[i - 1].i0 <= edges[i].i0)


def flat_surface(var pos: List[Float32]) raises -> BufferGeometry:
    """Return triangles at `pos` with normals along z and uv in a
    corner, as the reference's small surfaces have."""
    var corners = len(pos) // 3
    var nor = List[Float32]()
    var uv = List[Float32]()
    for corner in range(corners):
        nor.extend([Float32(0), 0, 1])
        if corner % 3 == 0:
            uv.extend([Float32(0), 0])
        elif corner % 3 == 1:
            uv.extend([Float32(1), 0])
        else:
            uv.extend([Float32(0), 1])
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(pos^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(nor^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uv^, 2))
    return geometry^


def test_surfaces_the_web_assembly_fails_on_match_the_c() raises:
    var default: List[Float64] = [1, 0, 0, -1]
    var point = tangents_of(flat_surface([1, 1, 1, 1, 1, 1, 1, 1, 1]))
    for corner in range(3):
        check(point, default, corner * 4)
    var x = nan[DType.float32]()
    var lost = tangents_of(
        flat_surface([x, 0, 0, x, 1, 0, x, 0, 1, x, 0, 0, x, 1, 0, x, 0, 1])
    )
    for corner in range(6):
        check(lost, default, corner * 4)
    var empty = generate_tangents(
        List[Float32](), List[Float32](), List[Float32]()
    )
    assert_equal(len(empty), 0)


def test_tangents_go_on_the_geometry_as_three_puts_them() raises:
    var geometry = grid(2, False)
    compute_mikktspace_tangents(geometry)
    assert_false(geometry.is_indexed())
    ref tangents = geometry.attribute_view(String(TANGENT))
    assert_equal(tangents.count(), 24)
    check(
        tangents.packed(),
        [
            1,
            0,
            0,
            -1,
            0.9015231132507324,
            -0.3461848795413971,
            0.2596386671066284,
            -1,
        ],
    )
    var empty = BufferGeometry()
    for name in [String(POSITION), String(NORMAL)]:
        empty.set_attribute(name, BufferAttribute(List[Float32](), 3))
    empty.set_attribute(String(UV), BufferAttribute(List[Float32](), 2))
    compute_mikktspace_tangents(empty)
    assert_equal(empty.attribute_view(String(TANGENT)).count(), 0)
    var kept = grid(2, False).to_non_indexed()
    compute_mikktspace_tangents(kept, False)
    check(kept.attribute_view(String(TANGENT)).packed(), [1, 0, 0, 1])


def test_tangents_need_the_three_attributes_that_fit() raises:
    for missing in [String(POSITION), String(NORMAL), String(UV)]:
        var source = grid(1, False)
        var partial = BufferGeometry()
        for slot in range(source.attribute_count()):
            if source.names[slot] != missing:
                partial.set_attribute(
                    source.names[slot], source.values[slot].copy()
                )
        with assert_raises():
            compute_mikktspace_tangents(partial)
    var wide = grid(1, False)
    wide.set_attribute(
        String(UV), BufferAttribute(List[Float32](length=12, fill=0), 3)
    )
    with assert_raises():
        compute_mikktspace_tangents(wide)
    var flat = grid(1, False)
    flat.set_attribute(
        String(NORMAL), BufferAttribute(List[Float32](length=8, fill=0), 2)
    )
    with assert_raises():
        compute_mikktspace_tangents(flat)
    var short = grid(1, False)
    short.set_attribute(
        String(POSITION), BufferAttribute(List[Float32](length=8, fill=0), 2)
    )
    with assert_raises():
        compute_mikktspace_tangents(short)
    with assert_raises():
        _ = generate_tangents(
            List[Float32](length=6, fill=0),
            List[Float32](length=6, fill=0),
            List[Float32](length=4, fill=0),
        )
    with assert_raises():
        _ = generate_tangents(
            List[Float32](length=9, fill=0),
            List[Float32](length=6, fill=0),
            List[Float32](length=6, fill=0),
        )
    with assert_raises():
        _ = generate_tangents(
            List[Float32](length=9, fill=0),
            List[Float32](length=9, fill=0),
            List[Float32](length=4, fill=0),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
