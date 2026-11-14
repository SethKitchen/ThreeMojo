# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A synthetic head of ten ellipsoids, for tests and examples.

The table is the modified three-dimensional Shepp-Logan phantom: the
ten ellipsoids of the Shepp-Logan head, with the higher contrast of
Toft's modification. Each ellipsoid adds its intensity inside it. The
skull is 1, the brain 0.2, the two ventricles 0 and the small features
0.3 or 0.4.

The coordinates are fractions of half the field of view: the phantom
fills the cube from -1 to 1. This module turns each ellipsoid about z
only, by the angle of the two-dimensional phantom. The phantom does not
claim a tissue, a scanner or a patient.
"""

from extensions.imaging.image_volume import ImageVolume
from extensions.sdf.vector import v3
from std.math import cos, pi, sin
from units.si import Length64, METER


struct Ellipsoid(ImplicitlyCopyable):
    """One ellipsoid of the phantom, in fractions of half the field."""

    var intensity: Float64
    """The value that the ellipsoid adds inside it."""
    var a: Float64
    """The semi-axis along x before the turn."""
    var b: Float64
    """The semi-axis along y before the turn."""
    var c: Float64
    """The semi-axis along z."""
    var x0: Float64
    """The center on x."""
    var y0: Float64
    """The center on y."""
    var z0: Float64
    """The center on z."""
    var turn_degrees: Float64
    """The turn about z, in degrees."""
    var cos_turn: Float64
    """The cosine of the turn."""
    var sin_turn: Float64
    """The sine of the turn."""

    def __init__(
        out self,
        intensity: Float64,
        a: Float64,
        b: Float64,
        c: Float64,
        x0: Float64,
        y0: Float64,
        z0: Float64,
        turn_degrees: Float64,
    ):
        """Create an ellipsoid.

        Args:
            intensity: The value that it adds inside it.
            a: The semi-axis along x before the turn.
            b: The semi-axis along y before the turn.
            c: The semi-axis along z.
            x0: The center on x.
            y0: The center on y.
            z0: The center on z.
            turn_degrees: The turn about z, in degrees.
        """
        self.intensity = intensity
        self.a = a
        self.b = b
        self.c = c
        self.x0 = x0
        self.y0 = y0
        self.z0 = z0
        self.turn_degrees = turn_degrees
        var angle = turn_degrees * pi / 180.0
        self.cos_turn = cos(angle)
        self.sin_turn = sin(angle)

    def contains(self, x: Float64, y: Float64, z: Float64) -> Bool:
        """Return whether a point is inside the ellipsoid or on it.

        Args:
            x: The point on x.
            y: The point on y.
            z: The point on z.

        Returns:
            Whether the point is inside.
        """
        var dx = x - self.x0
        var dy = y - self.y0
        var u = (dx * self.cos_turn + dy * self.sin_turn) / self.a
        var w = (dy * self.cos_turn - dx * self.sin_turn) / self.b
        var h = (z - self.z0) / self.c
        return u * u + w * w + h * h <= 1.0


def shepp_logan_table() -> List[Ellipsoid]:
    """Return the ten ellipsoids of the modified 3D Shepp-Logan phantom.

    Returns:
        The skull, the brain, the two ventricles and six small features.
    """
    return [
        Ellipsoid(1.0, 0.69, 0.92, 0.81, 0.0, 0.0, 0.0, 0.0),
        Ellipsoid(-0.8, 0.6624, 0.874, 0.78, 0.0, -0.0184, 0.0, 0.0),
        Ellipsoid(-0.2, 0.11, 0.31, 0.22, 0.22, 0.0, 0.0, -18.0),
        Ellipsoid(-0.2, 0.16, 0.41, 0.28, -0.22, 0.0, 0.0, 18.0),
        Ellipsoid(0.1, 0.21, 0.25, 0.41, 0.0, 0.35, -0.15, 0.0),
        Ellipsoid(0.1, 0.046, 0.046, 0.05, 0.0, 0.1, 0.25, 0.0),
        Ellipsoid(0.1, 0.046, 0.046, 0.05, 0.0, -0.1, 0.25, 0.0),
        Ellipsoid(0.1, 0.046, 0.023, 0.05, -0.08, -0.605, 0.0, 0.0),
        Ellipsoid(0.1, 0.023, 0.023, 0.02, 0.0, -0.606, 0.0, 0.0),
        Ellipsoid(0.1, 0.023, 0.046, 0.02, 0.06, -0.605, 0.0, 0.0),
    ]


def phantom_value(x: Float64, y: Float64, z: Float64) -> Float64:
    """Return the phantom's value at a point.

    Args:
        x: The point on x, from -1 to 1.
        y: The point on y, from -1 to 1.
        z: The point on z, from -1 to 1.

    Returns:
        The sum of the intensities of the ellipsoids that hold the point.
    """
    return _value(shepp_logan_table(), x, y, z)


def _value(
    table: List[Ellipsoid], x: Float64, y: Float64, z: Float64
) -> Float64:
    """Return the sum of the intensities of the ellipsoids that hold a point."""
    var total = 0.0
    # The table always holds ten ellipsoids.
    for ellipsoid in table:  # pragma: no branch
        if ellipsoid.contains(x, y, z):
            total += ellipsoid.intensity
    return total


def shepp_logan(size: Int, field: Length64, samples: Int) raises -> ImageVolume:
    """Return the phantom sampled on a cube of voxels.

    The volume is centered on the patient origin. Voxel centers sit at
    `-field / 2 + (i + 0.5) * field / size`. Each voxel is the mean of
    `samples` cubed points spread evenly through it, so an edge that cuts a
    voxel gives a value between the two sides, as a scanner's partial
    volume does. The window shows the brain: center 0.25, width 0.5.

    Args:
        size: Voxels along each axis.
        field: The edge of the cube.
        samples: Points along each axis of a voxel, from 1 to 4.

    Returns:
        The volume.

    Raises:
        Error: If `size` is not positive or too large, `field` is not
            positive and finite, or `samples` is not from 1 to 4.
    """
    if samples < 1 or samples > 4:
        raise Error("A phantom voxel takes from 1 to 4 samples an axis")
    var spacing = Length64(field.to(METER) / Float64(size), METER)
    var volume = ImageVolume(size, size, size, spacing, spacing, spacing)
    var start = -1.0 + 1.0 / Float64(size)
    var step = 2.0 / Float64(size)
    var half = field.to(METER) / 2.0
    var corner = -half + spacing.to(METER) / 2.0
    volume.origin = v3(corner, corner, corner)
    var table = shepp_logan_table()
    var offsets = List[Float64]()
    for n in range(samples):  # pragma: no branch
        offsets.append((Float64(n) + 0.5) / Float64(samples) - 0.5)
    var weight = 1.0 / Float64(samples * samples * samples)
    for k in range(size):  # pragma: no branch
        var z = start + Float64(k) * step
        for j in range(size):  # pragma: no branch
            var y = start + Float64(j) * step
            for i in range(size):  # pragma: no branch
                var x = start + Float64(i) * step
                var total = 0.0
                for dz in offsets:  # pragma: no branch
                    for dy in offsets:  # pragma: no branch
                        for dx in offsets:  # pragma: no branch
                            total += _value(
                                table,
                                x + dx * step,
                                y + dy * step,
                                z + dz * step,
                            )
                volume.values[volume.index(i, j, k)] = Float32(total * weight)
    volume.window_center = 0.25
    volume.window_width = 0.5
    return volume^
