# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Principal stresses and their directions."""

from extensions.fem.elasticity import principal_stresses, von_mises
from extensions.sdf.vector import V3, dot, length
from std.math import nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import PASCAL


def _apply(stress: List[Float64], d: V3) -> V3:
    """The stress tensor times a direction."""
    return V3(
        stress[0] * d.x + stress[5] * d.y + stress[4] * d.z,
        stress[5] * d.x + stress[1] * d.y + stress[3] * d.z,
        stress[4] * d.x + stress[3] * d.y + stress[2] * d.z,
    )


def _check(stress: List[Float64]) raises -> List[Float64]:
    """Check the eigen-pairs and return the three values."""
    var principal = principal_stresses(stress)
    var values = List[Float64]()
    for k in range(3):
        var value = principal.values[k].to(PASCAL)
        values.append(value)
        var d = principal.directions[k]
        assert_almost_equal(length(d), 1.0, atol=1e-12)
        var image = _apply(stress, d)
        assert_almost_equal(image.x, value * d.x, atol=1e-9)
        assert_almost_equal(image.y, value * d.y, atol=1e-9)
        assert_almost_equal(image.z, value * d.z, atol=1e-9)
        for other in range(k):
            assert_almost_equal(
                dot(d, principal.directions[other]), 0.0, atol=1e-12
            )
    assert_true(values[0] >= values[1] and values[1] >= values[2])
    # The trace and the von Mises stress do not depend on the axes.
    assert_almost_equal(
        values[0] + values[1] + values[2],
        stress[0] + stress[1] + stress[2],
        atol=1e-9,
    )
    var diagonal: List[Float64] = [values[0], values[1], values[2], 0, 0, 0]
    assert_almost_equal(
        von_mises(diagonal).to(PASCAL), von_mises(stress).to(PASCAL), atol=1e-6
    )
    return values^


def test_diagonal_stress_sorts() raises:
    var principal = principal_stresses([3, 1, 2, 0, 0, 0])
    assert_equal(principal.values[0].to(PASCAL), 3)
    assert_equal(principal.values[1].to(PASCAL), 2)
    assert_equal(principal.values[2].to(PASCAL), 1)
    # The directions are the axes, unchanged.
    assert_equal(principal.directions[1].z, 1)
    assert_equal(principal.directions[2].y, 1)


def test_pure_shear() raises:
    var values = _check([0, 0, 0, 0, 0, 5])
    assert_almost_equal(values[0], 5)
    assert_almost_equal(values[1], 0, atol=1e-12)
    assert_almost_equal(values[2], -5)
    var first = principal_stresses([0, 0, 0, 0, 0, 5]).directions[0]
    assert_almost_equal(abs(first.x), sqrt(0.5))
    assert_almost_equal(abs(first.y), sqrt(0.5))


def test_general_stresses() raises:
    # A plane stress with sx > sy, so the rotation angle is negative.
    var plane = _check([5, 1, 0, 0, 0, 1])
    var center = 3.0
    var radius = sqrt(4.0 + 1.0)
    assert_almost_equal(plane[0], center + radius, atol=1e-12)
    assert_almost_equal(plane[1], center - radius, atol=1e-12)
    assert_equal(plane[2], 0)
    _ = _check([120e6, -40e6, 15e6, 30e6, -25e6, 60e6])
    _ = _check([-1, 2, -3, 0.5, 0.25, -0.75])
    # Equal principal stresses: any square axes are directions.
    var round = _check([7, 7, 7, 0, 0, 0])
    assert_equal(round[0], 7)
    _ = _check([2, 2, 5, 0, 0, 1e-9])


def test_refusals() raises:
    with assert_raises(contains="six parts"):
        _ = principal_stresses([1, 2, 3])
    with assert_raises(contains="finite"):
        _ = principal_stresses([1, 2, 3, 0, nan[DType.float64](), 0])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
