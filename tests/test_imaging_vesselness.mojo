# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hessian eigenvalues and Frangi vesselness.

`assets/vesselness/vesselness_expected.txt` holds scikit-image's values
for a synthetic volume, which `_volume` makes again. See
`assets/vesselness/make_vesselness.py`.
"""

from extensions.numerics.elementary import precise_exp
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.vesselness import hessian_eigenvalues, vesselness
from std.collections import Optional
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import MILLIMETER64, Length64

comptime NX = 20
comptime NY = 18
comptime NZ = 16


def _mm(v: Float64) -> Length64:
    return Length64(v, MILLIMETER64)


def _volume(dz: Float64) raises -> ImageVolume:
    var volume = ImageVolume(NX, NY, NZ, _mm(1.0), _mm(1.0), _mm(dz))
    var ux = 1.0
    var uy = 0.5
    var uz = 0.25
    var norm = sqrt(ux * ux + uy * uy + uz * uz)
    ux /= norm
    uy /= norm
    uz /= norm
    for k in range(NZ):
        for j in range(NY):
            for i in range(NX):
                var dx = Float64(i) - 8.0
                var dy = Float64(j) - 8.0
                var dz2 = Float64(k) - 6.0
                var along = dx * ux + dy * uy + dz2 * uz
                var d2 = dx * dx + dy * dy + dz2 * dz2 - along * along
                var v = 100.0 * precise_exp(-d2 / (2.0 * 1.2 * 1.2))
                var bx = Float64(i) - 14.0
                var by = Float64(j) - 4.0
                var bz = Float64(k) - 10.0
                v += 80.0 * precise_exp(-(bx * bx + by * by + bz * bz) / 8.0)
                if i >= 12:
                    var pz = Float64(k) - 13.0
                    v += 40.0 * precise_exp(-pz * pz / 2.0)
                volume.set(i, j, k, Float32(v))
    return volume^


def _rows(kind: String) raises -> List[List[Float64]]:
    var out = List[List[Float64]]()
    var text = open("assets/vesselness/vesselness_expected.txt", "r").read()
    for line in text.splitlines():
        var parts = line.split(" ")
        if String(parts[0]) != kind:
            continue
        var row = List[Float64]()
        for at in range(1, len(parts)):
            row.append(atof(String(parts[at])))
        out.append(row^)
    return out^


def _close_eigen(
    found: List[Float64], at: Int, row: List[Float64], first: Int
) raises:
    # Each eigenvalue agrees to 1e-10 of the largest of its voxel.
    var scale = max(abs(row[first + 2]), 1e-6)
    for e in range(3):
        assert_almost_equal(
            found[3 * at + e], row[first + e], atol=1e-10 * scale, rtol=0
        )


def test_hessian() raises:
    var volume = _volume(1.0)
    var rows = _rows("eigen")
    assert_equal(len(rows), 124)
    var one = hessian_eigenvalues(volume, _mm(1.0))
    var two = hessian_eigenvalues(volume, _mm(2.0))
    for row in rows:
        var at = Int(row[1])
        if row[0] == 1.0:
            _close_eigen(one, at, row, 2)
        else:
            _close_eigen(two, at, row, 2)


def test_anisotropic() raises:
    # Voxels twice as thick along z: sigma 2 mm is 1 voxel along z.
    var volume = _volume(2.0)
    var found = hessian_eigenvalues(volume, _mm(2.0))
    for row in _rows("anisotropic"):
        _close_eigen(found, Int(row[0]), row, 1)


def test_frangi() raises:
    var volume = _volume(1.0)
    var sigmas: List[Length64] = [_mm(1.0), _mm(2.0), _mm(3.0)]
    var found = vesselness(volume, sigmas, 0.5, 0.5, None)
    for row in _rows("frangi"):
        assert_almost_equal(
            Float64(found.values[Int(row[0])]), row[1], atol=2e-7, rtol=0
        )
    var total = 0.0
    var top = 0.0
    for v in found.values:
        total += Float64(v)
        top = max(top, Float64(v))
    var expected = _rows("total")[0].copy()
    assert_almost_equal(total, expected[0], rtol=1e-6)
    assert_almost_equal(top, expected[1], atol=2e-7)
    # The tube's center is more vessel-like than the blob's.
    assert_true(
        found.values[6 * NX * NY + 8 * NX + 8]
        > 3 * found.values[10 * NX * NY + 4 * NX + 14]
    )


def test_by_hand() raises:
    # A flat volume has no curvature and no vesselness, with any gamma.
    var flat = ImageVolume(6, 6, 6, _mm(1.0), _mm(1.0), _mm(1.0))
    var sigmas: List[Length64] = [_mm(1.5)]
    var none = vesselness(flat, sigmas, 0.5, 0.5, None)
    for v in none.values:
        assert_equal(v, 0)
    var given = vesselness(flat, sigmas, 0.5, 0.5, Optional[Float64](10.0))
    assert_equal(given.values[0], 0)
    # A ridge `-x^2`, far from the edges, has the second derivative -2
    # along x, and none along y and z.
    var ridge = ImageVolume(41, 3, 3, _mm(1.0), _mm(1.0), _mm(1.0))
    for k in range(3):
        for j in range(3):
            for i in range(41):
                var x = Float64(i) - 20.0
                ridge.set(i, j, k, Float32(-x * x))
    var eigen = hessian_eigenvalues(ridge, _mm(1.5))
    var center = 3 * (20 + 41 * (1 + 3 * 1))
    assert_almost_equal(eigen[center + 2], -2.0, atol=1e-8)
    assert_almost_equal(eigen[center], 0.0, atol=1e-10)
    # A saddle `-(x^2 + x y)` has the Hessian [[-2, -1, 0], [-1, 0, 0],
    # [0, 0, 0]], whose eigenvalues are 0 and -1 -+ sqrt(2).
    var saddle = ImageVolume(41, 41, 3, _mm(1.0), _mm(1.0), _mm(1.0))
    for k in range(3):
        for j in range(41):
            for i in range(41):
                var x = Float64(i) - 20.0
                var y = Float64(j) - 20.0
                saddle.set(i, j, k, Float32(-(x * x + x * y)))
    var found = hessian_eigenvalues(saddle, _mm(1.5))
    var middle = 3 * (20 + 41 * (20 + 41 * 1))
    assert_almost_equal(found[middle], 0.0, atol=1e-10)
    assert_almost_equal(found[middle + 1], sqrt(2.0) - 1.0, atol=1e-8)
    assert_almost_equal(found[middle + 2], -1.0 - sqrt(2.0), atol=1e-8)


def test_errors() raises:
    var volume = ImageVolume(4, 4, 4, _mm(1.0), _mm(1.0), _mm(1.0))
    var bad: List[Float64] = [
        0.0,
        inf[DType.float64](),
        nan[DType.float64](),
        101.0,
    ]
    for s in bad:
        with assert_raises():
            _ = hessian_eigenvalues(volume, _mm(s))
    with assert_raises(contains="one scale or more"):
        _ = vesselness(volume, List[Length64](), 0.5, 0.5, None)
    var sigmas: List[Length64] = [_mm(1.0)]
    var weights: List[Float64] = [0.0, inf[DType.float64]()]
    for w in weights:
        with assert_raises(contains="alpha"):
            _ = vesselness(volume, sigmas, w, 0.5, None)
        with assert_raises(contains="beta"):
            _ = vesselness(volume, sigmas, 0.5, w, None)
        with assert_raises(contains="gamma"):
            _ = vesselness(volume, sigmas, 0.5, 0.5, Optional[Float64](w))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
