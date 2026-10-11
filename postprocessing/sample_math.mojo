# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scalar kernels shared by the post-processing passes.

`gaussian_pdf` is three.js's `gaussianPdf`.
"""

from std.math import exp


def gaussian_pdf(x: Float32, sigma: Float32) -> Float32:
    """Return three.js's `gaussianPdf` at `x` for `sigma`.

    Args:
        x: The distance from the center, in pixels.
        sigma: The standard deviation, in pixels.

    Returns:
        `0.39894 * exp(-0.5 * x * x / (sigma * sigma)) / sigma`.
    """
    return 0.39894 * exp(-0.5 * x * x / (sigma * sigma)) / sigma
