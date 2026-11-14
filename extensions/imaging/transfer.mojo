# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Map volume values to gray levels, colors and opacities.

`WindowLevel` is the `LINEAR_EXACT` VOI function of DICOM PS3.3
C.11.2.1.3.2: a value at or below `center - width / 2` is black, a value
above `center + width / 2` is white, and the values between rise in a
straight line. It takes any positive width, so it suits values that are
not whole numbers.

`TransferFunction` holds control points, each a value with a color and
an opacity. A value between two points blends them in a straight line.
A value below the first point takes the first point. A value above the
last point takes the last point. The colors are display values from
zero to one. They are not linear light.
"""

from std.math import isfinite, max, min, pow


@fieldwise_init
struct Rgba(Equatable, ImplicitlyCopyable, Writable):
    """A color and an opacity, each from zero to one."""

    var r: Float32
    """Red."""
    var g: Float32
    """Green."""
    var b: Float32
    """Blue."""
    var a: Float32
    """Opacity. Zero is clear and one is solid."""


struct WindowLevel(ImplicitlyCopyable):
    """The DICOM linear window: a center and a width."""

    var center: Float64
    """The value at the middle of the gray ramp."""
    var width: Float64
    """The span of the gray ramp. Positive."""

    def __init__(out self, center: Float64, width: Float64) raises:
        """Create a window.

        Args:
            center: The value at the middle of the ramp.
            width: The span of the ramp. Positive.

        Raises:
            Error: If the center is not finite, or the width is not positive
                and finite.
        """
        if not isfinite(center):
            raise Error("A window center must be finite")
        if not (width > 0) or not isfinite(width):
            raise Error("A window width must be positive and finite")
        self.center = center
        self.width = width

    def apply(self, value: Float64) -> Float64:
        """Return the gray level of a value, from zero to one.

        Args:
            value: The value to show.

        Returns:
            Zero at or below the ramp, one above it, and the straight line
            between.
        """
        var low = self.center - self.width / 2.0
        var high = self.center + self.width / 2.0
        if value <= low:
            return 0.0
        if value > high:
            return 1.0
        return (value - self.center) / self.width + 0.5


def _require_unit(value: Float32, name: String) raises:
    """Refuse a color channel or an opacity outside zero to one."""
    if not (value >= 0) or not (value <= 1):
        raise Error("A transfer function " + name + " must be from 0 to 1")


struct TransferFunction(Copyable, Movable):
    """Control points that give each value a color and an opacity."""

    var values: List[Float64]
    """The value of each point, in increasing order."""
    var colors: List[Rgba]
    """The color and opacity of each point."""

    def __init__(out self):
        """Create a function with no points."""
        self.values = List[Float64]()
        self.colors = List[Rgba]()

    def add_point(mut self, value: Float64, color: Rgba) raises:
        """Add a control point.

        A point at a value that already has points goes after them, so
        two points at one value make a step.

        Args:
            value: The volume value of the point.
            color: Its color and opacity.

        Raises:
            Error: If `value` is not finite, or a channel or the opacity is
                outside zero to one.
        """
        if not isfinite(value):
            raise Error("A transfer function point needs a finite value")
        _require_unit(color.r, "red")
        _require_unit(color.g, "green")
        _require_unit(color.b, "blue")
        _require_unit(color.a, "opacity")
        var at = len(self.values)
        while at > 0 and self.values[at - 1] > value:
            at -= 1
        self.values.insert(at, value)
        self.colors.insert(at, color)

    def sample(self, value: Float64) raises -> Rgba:
        """Return the color and opacity of a value.

        Args:
            value: The volume value.

        Returns:
            The blend of the two points around the value.

        Raises:
            Error: If the function has no points.
        """
        var count = len(self.values)
        if count == 0:
            raise Error("A transfer function needs at least one point")
        if value <= self.values[0]:
            return self.colors[0]
        if value >= self.values[count - 1]:
            return self.colors[count - 1]
        var high = 1
        while self.values[high] < value:
            high += 1
        var low = high - 1
        var span = self.values[high] - self.values[low]
        var t = Float32((value - self.values[low]) / span)
        ref a = self.colors[low]
        ref b = self.colors[high]
        return Rgba(
            a.r + (b.r - a.r) * t,
            a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t,
            a.a + (b.a - a.a) * t,
        )

    def table(
        self, low: Float64, high: Float64, size: Int
    ) raises -> List[Rgba]:
        """Return the function sampled at evenly spaced values.

        Entry `n` is the sample at `low + n * (high - low) / (size - 1)`.

        Args:
            low: The value of the first entry.
            high: The value of the last entry. Above `low`.
            size: The number of entries. At least two.

        Returns:
            The entries.

        Raises:
            Error: If the function has no points, `size` is less than two,
                or `high` is not above `low`.
        """
        if size < 2:
            raise Error("A transfer table needs at least two entries")
        if not (high > low):
            raise Error("A transfer table needs a range that rises")
        var out = List[Rgba]()
        var step = (high - low) / Float64(size - 1)
        for index in range(size):  # pragma: no branch
            out.append(self.sample(low + Float64(index) * step))
        return out^


def corrected_opacity(alpha: Float32, step_ratio: Float64) -> Float32:
    """Return the opacity of a step of another length.

    An opacity is given for a step of one voxel. A step of `step_ratio`
    voxels passes `(1 - alpha)^step_ratio` of the light.

    Args:
        alpha: The opacity for one voxel, from zero to one.
        step_ratio: The step length in voxels. Positive.

    Returns:
        `1 - (1 - alpha)^step_ratio`.
    """
    var clear = max(Float64(1) - Float64(alpha), 0.0)
    return Float32(1.0 - pow(clear, step_ratio))


def clamp_unit(value: Float32) -> Float32:
    """Return a value held between zero and one.

    Args:
        value: The value.

    Returns:
        The value, held between zero and one.
    """
    return min(max(value, 0), 1)
