# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Separable Gaussian kernels, and the convolution of one axis with the
nearest or the reflected values past each edge."""

from extensions.imaging.ids import (
    EDGE_NEAREST,
    EDGE_REFLECT,
    EdgeMode,
    require_edge_mode,
)
from extensions.imaging.separable import GaussianKernel, convolve_axis
from std.math import exp, inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_kernels() raises:
    var smooth = GaussianKernel.smoothing(1.0, 2)
    assert_equal(len(smooth.weights), 5)
    assert_false(smooth.odd)
    # exp(-t^2 / 2) over its sum.
    var total = 1.0 + 2.0 * exp(-0.5) + 2.0 * exp(-2.0)
    assert_almost_equal(smooth.weights[2], 1.0 / total, rtol=1e-15)
    assert_almost_equal(smooth.weights[0], exp(-2.0) / total, rtol=1e-15)
    var sum = 0.0
    for w in smooth.weights:
        sum += w
    assert_almost_equal(sum, 1.0, rtol=1e-15)
    # The derivative is -t / sigma^2 times the Gaussian: odd in t.
    var slope = GaussianKernel.derivative(2.0, 3)
    assert_true(slope.odd)
    assert_equal(slope.weights[3], 0.0)
    for t in range(1, 4):
        assert_equal(slope.weights[3 + t], -slope.weights[3 - t])
    var single = GaussianKernel.smoothing(0.5, 0)
    assert_equal(len(single.weights), 1)
    assert_equal(single.weights[0], 1.0)


def test_convolve_edges() raises:
    # A line of four along y, in a volume of 1 by 4 by 1.
    var values: List[Float64] = [1.0, 2.0, 3.0, 4.0]
    var shape: List[Int] = [1, 4, 1]
    var kernel = GaussianKernel.smoothing(1.0, 1)
    var w0 = kernel.weights[1]
    var w1 = kernel.weights[0]
    var nearest = convolve_axis(values, shape, 1, kernel, EDGE_NEAREST)
    # Past the first edge, nearest reads 1 again, and reflect reads 1.
    assert_almost_equal(nearest[0], w0 * 1.0 + w1 * (1.0 + 2.0), rtol=1e-15)
    assert_almost_equal(nearest[3], w0 * 4.0 + w1 * (3.0 + 4.0), rtol=1e-15)
    assert_almost_equal(nearest[1], 2.0, rtol=1e-15)
    var kernel2 = GaussianKernel.smoothing(1.0, 2)
    var reflect = convolve_axis(values, shape, 1, kernel2, EDGE_REFLECT)
    # Two past the first edge, reflect reads 2: `2 1 | 1 2 3 4`.
    var k = kernel2.weights.copy()
    assert_almost_equal(
        reflect[0],
        k[2] * 1.0 + k[3] * (1.0 + 2.0) + k[4] * (2.0 + 3.0),
        rtol=1e-15,
    )
    # A derivative of a ramp along x is the same everywhere inside.
    var ramp: List[Float64] = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    var slope = GaussianKernel.derivative(1.0, 1)
    var d = convolve_axis(ramp, [7, 1, 1], 0, slope, EDGE_REFLECT)
    assert_almost_equal(d[3], d[2], rtol=1e-15)
    assert_true(d[3] > 0)
    # Along z, a stride of nx ny.
    var column: List[Float64] = [0.0, 0.0, 6.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    var z = convolve_axis(column, [2, 1, 4], 2, kernel, EDGE_NEAREST)
    assert_almost_equal(z[0], w1 * 6.0, rtol=1e-15)
    assert_almost_equal(z[2], w0 * 6.0, rtol=1e-15)
    assert_equal(z[1], 0.0)


def test_refusals() raises:
    var widths: List[Float64] = [
        0.0,
        -1.0,
        inf[DType.float64](),
        nan[DType.float64](),
    ]
    for w in widths:
        with assert_raises(contains="positive and finite"):
            _ = GaussianKernel.smoothing(w, 1)
    with assert_raises(contains="radius must be 0 or more"):
        _ = GaussianKernel.derivative(1.0, -1)
    var values: List[Float64] = [1.0, 2.0]
    var kernel = GaussianKernel.smoothing(1.0, 1)
    with assert_raises(contains="edge mode must be 0 or 1"):
        _ = convolve_axis(values, [2, 1, 1], 0, kernel, EdgeMode(2))
    with assert_raises(contains="edge mode must be 0 or 1"):
        require_edge_mode(EdgeMode(-1))
    var axes: List[Int] = [-1, 3]
    for a in axes:
        with assert_raises(contains="axis must be 0, 1 or 2"):
            _ = convolve_axis(values, [2, 1, 1], a, kernel, EDGE_NEAREST)
    var shapes: List[List[Int]] = [
        [2, 1],
        [0, 1, 1],
        [2, 0, 1],
        [2, 1, 0],
        [1, 1, 1],
    ]
    for s in shapes:
        with assert_raises(contains="three sizes that hold the values"):
            _ = convolve_axis(values, s, 0, kernel, EDGE_NEAREST)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
