# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact comparison of two sets of splats, for the scan reader tests.

A scan reader must make the splats that `loaders.gaussian_splat_ply` makes
from the PLY file that splat-transform writes from the same scan. These
helpers name the first value that differs.
"""

from core.gaussian_splat_utils import GaussianSplatGeometry
from std.testing import assert_equal


def same_floats(
    found: List[Float32], expected: List[Float32], what: String
) raises:
    """Assert two float arrays are equal, naming the first difference.

    Args:
        found: The values read.
        expected: The values required.
        what: What the values are.

    Raises:
        Error: If the lengths or a value differ.
    """
    assert_equal(len(found), len(expected), what + " length")
    for index in range(len(found)):
        if found[index] != expected[index]:
            raise Error(
                what
                + " differ at "
                + String(index)
                + ": "
                + String(found[index])
                + " and "
                + String(expected[index])
            )


def same_bytes(found: List[UInt8], expected: List[UInt8], what: String) raises:
    """Assert two byte arrays are equal, naming the first difference.

    Args:
        found: The bytes read.
        expected: The bytes required.
        what: What the bytes are.

    Raises:
        Error: If the lengths or a byte differ.
    """
    assert_equal(len(found), len(expected), what + " length")
    for index in range(len(found)):
        if found[index] != expected[index]:
            raise Error(
                what
                + " differ at "
                + String(index)
                + ": "
                + String(found[index])
                + " and "
                + String(expected[index])
            )


def same_splats(
    found: GaussianSplatGeometry, expected: GaussianSplatGeometry
) raises:
    """Assert two geometries hold the same splats.

    Args:
        found: The splats read.
        expected: The splats required.

    Raises:
        Error: If a center, a covariance, a color byte or a harmonics byte
            differs.
    """
    same_floats(found.centers, expected.centers, "centers")
    same_floats(found.covariances, expected.covariances, "covariances")
    same_bytes(found.colors, expected.colors, "colors")
    same_bytes(found.sh1, expected.sh1, "band 1")
    same_bytes(found.sh2, expected.sh2, "band 2")
    same_bytes(found.sh3, expected.sh3, "band 3")
