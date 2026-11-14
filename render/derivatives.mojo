# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Screen-space derivatives of a value that a fragment computes: GLSL's
`fwidth`, and the ramps that three.js builds on it.

A GPU shades pixels in blocks of two by two. It takes `dFdx` and `dFdy` as
the difference between two fragments of one block. This port shades each
fragment alone, on the host and in the kernel. It computes the value again
at the pixel to the right and at the pixel above, from the triangle's own
plane, and subtracts. `render.rasterizer.mip_level` measures a texture
footprint the same way, and a node's `dfdx` and `dfdy` do too.

Both rasterizers call the functions here, so the two agree by construction.
Nothing here allocates, raises or reads a buffer.

The values are measured on the triangle's plane: the normal before any map,
the position, the coordinates and the corner colors, each interpolated at
the neighboring pixel. A normal map, a bump map and a normal node do not
change a width. `render.fragment_flags.surface_steps` gathers those
attributes from either rasterizer's `NodeSource`.

- `fwidth` is GLSL's `fwidth`: `abs(dFdx(v)) + abs(dFdy(v))`.
- `alpha_test_ramp` is three.js's `alphatest_fragment` under
  `ALPHA_TO_COVERAGE`.
- `edge_ramp_alpha` is the alpha of three.js's `LineMaterial` under
  `USE_ALPHA_TO_COVERAGE`: the disc of a round cap, or the capsule of a
  line whose width is in the world.
"""

from core.ordinal import ordinal_valid, require_valid
from math.smoothstep import smoothstep
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import sqrt


@fieldwise_init
struct EdgeRamp(Equatable, ImplicitlyCopyable, Writable):
    """Which antialiased edge a fragment's alpha takes from its texture
    coordinates, as a type rather than a bare int: three.js's
    `LineMaterial` under `alphaToCoverage`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three edge ramps.

        Returns:
            Whether the value names an edge ramp.
        """
        return ordinal_valid(self.value, 2)


# No ramp: the alpha is left alone. Every surface that is not a wide line.
comptime NO_EDGE_RAMP = EdgeRamp(0)
# A round cap of a line whose width is in pixels. The coordinates are the
# cap's own, in half widths from the segment's end, and the ramp is on
# their squared length about one.
comptime DISC_EDGE_RAMP = EdgeRamp(1)
# A line whose width is in the world. The coordinates are in half widths
# from the segment's axis or its end, and the ramp is on half their
# length about one half: three.js's `norm`.
comptime CAPSULE_EDGE_RAMP = EdgeRamp(2)


def require_edge_ramp(ramp: EdgeRamp) raises:
    """Refuse an edge ramp that is none of the three.

    Nothing. The call returns when the ramp is named.

    Args:
        ramp: The ramp to check.

    Raises:
        Error: If `ramp` is none of the three.
    """
    require_valid(ramp.is_valid(), "An edge ramp that is none of the three")


@always_inline
def fwidth(here: Float32, right: Float32, up: Float32) -> Float32:
    """Return GLSL's `fwidth` of a value: `abs(dFdx(v)) + abs(dFdy(v))`.

    Args:
        here: The value at the fragment's pixel.
        right: The value at the pixel to its right.
        up: The value at the pixel above it.

    Returns:
        The sum of the two absolute differences. Zero where the value
        does not change.
    """
    return abs(right - here) + abs(up - here)


def alpha_test_ramp(
    alpha: Float32, threshold: Float32, width: Float32
) -> Float32:
    """Return the alpha an alpha test leaves under alpha to coverage.

    three.js's `alphatest_fragment` with `ALPHA_TO_COVERAGE`:
    `smoothstep(alphaTest, alphaTest + fwidth(alpha), alpha)`. A fragment
    whose result is zero is discarded. The others keep the result as their
    alpha, and the coverage reads it.

    A width that is not above zero gives the hard step: zero at and below
    the threshold, and one above it. That is also the result for a width
    that is not a number.

    Args:
        alpha: The fragment's alpha, after its maps.
        threshold: The material's alpha test.
        width: `fwidth` of the alpha.

    Returns:
        A number from zero to one.
    """
    if not (width > 0):
        return smoothstep(threshold, threshold, alpha)
    return smoothstep(threshold, threshold + width, alpha)


@always_inline
def _edge_measure(u: Float32, v: Float32, ramp: EdgeRamp) -> Float32:
    """Return what an edge ramp reads at one pair of coordinates: the
    squared length for a disc, and half the length for a capsule."""
    var squared = u * u + v * v
    if ramp == DISC_EDGE_RAMP:
        return squared
    return sqrt(squared) * Float32(0.5)


def edge_ramp_alpha(
    ramp: EdgeRamp, here: Vector2, right: Vector2, up: Vector2
) -> Float32:
    """Return the alpha of a wide line's antialiased edge at one fragment.

    three.js's `LineMaterial` under `USE_ALPHA_TO_COVERAGE`. A round cap of
    a line in pixels reads `len2`, the squared length of its coordinates:
    `1 - smoothstep(1 - fwidth(len2), 1 + fwidth(len2), len2)`. A line in
    the world reads `norm`, half the length of its coordinates:
    `1 - smoothstep(0.5 - fwidth(norm), 0.5 + fwidth(norm), norm)`.

    Where the measure does not change, the width is zero and the edge is
    the hard one: one at and inside it, and zero outside.

    Args:
        ramp: `DISC_EDGE_RAMP` or `CAPSULE_EDGE_RAMP`. `NO_EDGE_RAMP`
            gives one.
        here: The coordinates at the fragment's pixel.
        right: The coordinates at the pixel to its right.
        up: The coordinates at the pixel above it.

    Returns:
        A number from zero to one, to multiply the alpha by.
    """
    if ramp == NO_EDGE_RAMP:
        return 1
    var edge = Float32(1) if ramp == DISC_EDGE_RAMP else Float32(0.5)
    var measure = _edge_measure(here.x, here.y, ramp)
    var width = fwidth(
        measure,
        _edge_measure(right.x, right.y, ramp),
        _edge_measure(up.x, up.y, ramp),
    )
    return 1 - smoothstep(edge - width, edge + width, measure)


struct SurfaceSteps(ImplicitlyCopyable):
    """A triangle's plane at a fragment's pixel, at the pixel to its right
    and at the pixel above it: the unit normal before any map, and the
    world position.

    A width that reads the surface takes its differences from these. The
    default holds nothing and says so, and a width from it is zero.
    """

    # Whether the six vectors were measured. False for the default.
    var measured: Bool
    # At the fragment's own pixel.
    var normal: Vector3
    var position: Vector3
    # At the pixel to the right.
    var normal_right: Vector3
    var position_right: Vector3
    # At the pixel above.
    var normal_up: Vector3
    var position_up: Vector3

    def __init__(out self):
        """Hold nothing: every width from this is zero."""
        var zero = Vector3(0, 0, 0)
        self.measured = False
        self.normal = zero
        self.position = zero
        self.normal_right = zero
        self.position_right = zero
        self.normal_up = zero
        self.position_up = zero

    def __init__(
        out self,
        normal: Vector3,
        position: Vector3,
        normal_right: Vector3,
        position_right: Vector3,
        normal_up: Vector3,
        position_up: Vector3,
    ):
        """Hold a plane's normal and position at three pixels.

        Args:
            normal: The unit normal at the fragment's pixel.
            position: The world position there.
            normal_right: The unit normal at the pixel to the right.
            position_right: The world position there.
            normal_up: The unit normal at the pixel above.
            position_up: The world position there.
        """
        self.measured = True
        self.normal = normal
        self.position = position
        self.normal_right = normal_right
        self.position_right = position_right
        self.normal_up = normal_up
        self.position_up = position_up
