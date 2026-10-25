# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The weights of the spherical harmonics of a splat, for a view direction.

A splat's color depends on where it is seen from. Its harmonics bytes give
`2 degree + 1` coefficients for each band, three channels each, and the color
is the sum of the coefficients times these weights. `objects.gaussian_splat`
sums them on the host, as three.js's `applySphericalHarmonics` does. A GPU
kernel needs the same weights without the object, so this module holds them
in a leaf module that imports nothing of the renderer. The weights are the
ones `GaussianSplat.spherical_harmonics_color` uses, and
`tests/test_splat_harmonics.mojo` holds the two to the same colors.
"""

from math.vector3 import Vector3


def sh_weights(degree: Int, d: Vector3) -> SIMD[DType.float32, 8]:
    """Return the weights of one band's coefficients for a direction, as
    three.js's `applySphericalHarmonics` writes them.

    The weights are lanes of one vector, so that no splat allocates.

    Args:
        degree: The band, 1 through 3.
        d: The unit direction from the camera to the splat.

    Returns:
        `2 degree + 1` weights in the first lanes, and zeros after them.
    """
    var x = d.x
    var y = d.y
    var z = d.z
    var w = SIMD[DType.float32, 8](0)
    if degree == 1:
        w[0] = y * -0.4886025
        w[1] = z * 0.4886025
        w[2] = x * -0.4886025
        return w
    var xx = x * x
    var yy = y * y
    var zz = z * z
    if degree == 2:
        w[0] = x * y * 1.0925484
        w[1] = y * z * -1.0925484
        w[2] = (zz * 2 - xx - yy) * 0.3153915
        w[3] = x * z * -1.0925484
        w[4] = (xx - yy) * 0.5462742
        return w
    var xy = x * y
    w[0] = y * (xx * 3 - yy) * -0.5900436
    w[1] = xy * z * 2.8906114
    w[2] = y * (zz * 4 - xx - yy) * -0.4570458
    w[3] = z * (zz * 2 - xx * 3 - yy * 3) * 0.3731763
    w[4] = x * (zz * 4 - xx - yy) * -0.4570458
    w[5] = z * (xx - yy) * 1.4453057
    w[6] = x * (xx - yy * 3) * -0.5900436
    return w
