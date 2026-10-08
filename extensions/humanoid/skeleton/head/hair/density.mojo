# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bounded, moving strand-density approximation for hair self-shadow.

Each cell holds fiber projected area per volume, in inverse meters.
Segments deposit their length times the fiber diameter along their path.
A ray toward a light integrates that field. The Beer-Lambert transmission
is exp(-optical_depth). This is a coarse volume approximation, not a
strand-exact visibility solver or a constitutive hair model.

The grid is rebuilt from the current positions. It owns its allocation
and reuses it across frames with the same resolution. No reference data
or third-party implementation is added by this module.
"""

from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from math.vector3 import Vector3
from std.math import ceil, floor, isfinite, max, min
from units.si import Length, METER

comptime MIN_HAIR_DENSITY_RESOLUTION = 4
comptime MAX_HAIR_DENSITY_RESOLUTION = 64


def _checked_density_point(point: Vector3) raises -> Vector3:
    """Return the unchanged point after checking all three coordinates."""
    if not isfinite(point.x) or not isfinite(point.y) or not isfinite(point.z):
        raise Error("Hair density needs finite positions")
    return point


struct HairDensity(Movable):
    """A uniform grid of the current strands' projected-area density."""

    var resolution: Int
    var diameter: Length
    var low: Vector3
    var cell: Float32
    var coefficients: List[Float32]
    var populated: Bool

    def __init__(
        out self,
        resolution: Int = 24,
        diameter: Length = Length(0.00008, METER),
    ) raises:
        """Allocate one bounded density grid.

        Args:
            resolution: Cells on each axis, from four through 64.
            diameter: The physical fiber diameter, finite and positive.

        Raises:
            Error: If the resolution or diameter is refused.
        """
        self.resolution = resolution
        self.diameter = diameter
        self.low = Vector3(0, 0, 0)
        self.cell = 1
        self.populated = False
        self.coefficients = List[Float32]()
        self.validate()
        self.coefficients = List[Float32](
            length=resolution * resolution * resolution, fill=0
        )

    def validate(self) raises:
        """Check the public grid settings before using them.

        Raises:
            Error: If the resolution or diameter is outside its domain.
        """
        if (
            self.resolution < MIN_HAIR_DENSITY_RESOLUTION
            or self.resolution > MAX_HAIR_DENSITY_RESOLUTION
        ):
            raise Error("Hair density needs four through 64 cells per axis")
        var diameter = self.diameter.to(METER)
        if not isfinite(diameter) or diameter <= 0:
            raise Error("Hair density needs a finite positive fiber diameter")

    def rebuild(mut self, groom: HairGroom) raises:
        """Replace the volume with the current strand positions.

        Args:
            groom: The current strands. Their starts must partition points.

        Raises:
            Error: If settings, topology, positions or computed scales are
                not finite and representable, or topology is malformed.
        """
        self.validate()
        var count = self.resolution * self.resolution * self.resolution
        if len(self.coefficients) != count:
            self.coefficients = List[Float32](length=count, fill=0)
        else:
            for index in range(count):
                self.coefficients[index] = 0
        self.populated = False
        if len(groom.starts) == 0 or groom.starts[0] != 0:
            raise Error("Hair density needs a starts array beginning at zero")
        if groom.starts[len(groom.starts) - 1] != len(groom.points):
            raise Error("Hair density starts must end at the point count")
        for strand in range(len(groom)):
            if groom.starts[strand] > groom.starts[strand + 1]:
                raise Error("Hair density starts must be ordered")
        if len(groom.points) == 0:
            return
        var low = _checked_density_point(groom.points[0])
        var high = low
        for index in range(1, len(groom.points)):
            var p = _checked_density_point(groom.points[index])
            low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
            high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
        var span = high - low
        var longest = max(span.x, max(span.y, span.z))
        # Keep a clear boundary cell. Four cells use a single interior
        # cell, with the same finite floor.
        var cell = max(
            max(self.diameter.to(METER), Float32(1e-5)),
            longest / Float32(max(1, self.resolution - 4)),
        )
        var volume = cell * cell * cell
        # On the validated rebuild path with ordinary Float32 rounding and
        # gradual underflow, the cell floor keeps both products positive.
        # The finite-volume check also bounds the cell above.
        if not isfinite(cell) or not isfinite(volume):
            raise Error("Hair density grid scale is not representable")
        self.cell = cell
        self.low = low - Vector3(cell, cell, cell)
        # Diameter is at most cell, which is at least Float32(1e-5).
        # Thus diameter / volume stays finite even for tiny diameters.
        var deposit = self.diameter.to(METER) / volume
        for strand in range(len(groom)):
            for index in range(
                groom.starts[strand], groom.starts[strand + 1] - 1
            ):
                var start = groom.points[index]
                var delta = groom.points[index + 1] - start
                var length = delta.length()
                # Finite cubic volume and resolution at most 64 bound
                # segment length below 2^50 and sample count at most 211.
                var samples = max(1, Int(ceil(length / (cell * 0.5))))
                var added = length * deposit / Float32(samples)
                for sample in range(samples):
                    var p = start + delta * (
                        (Float32(sample) + 0.5) / Float32(samples)
                    )
                    # With stable validated groom storage, rounded lower
                    # padding is between zero and twice cell. Bounded span
                    # and interpolation rounding keep samples in the grid.
                    var slot = self._slot(p)
                    # Each increment is below 2^16. Float32 additions from
                    # zero cannot cross 2^42, even for many valid deposits.
                    self.coefficients[slot] += added
        self.populated = True

    def _slot(self, point: Vector3) -> Int:
        """Return a containing cell's index, or minus one outside the grid."""
        var relative = (point - self.low) / self.cell
        var size = Float32(self.resolution)
        if (
            relative.x < 0
            or relative.y < 0
            or relative.z < 0
            or relative.x >= size
            or relative.y >= size
            or relative.z >= size
        ):
            return -1
        var x = Int(floor(relative.x))
        var y = Int(floor(relative.y))
        var z = Int(floor(relative.z))
        return (z * self.resolution + y) * self.resolution + x

    def optical_depth(
        self, point: Vector3, direction: Vector3
    ) raises -> Float32:
        """Integrate density from an interior point toward a light.

        One cell is skipped to suppress the point's own deposited fiber.
        Midpoint steps are half a cell long, bounded by the grid diagonal.
        This bias also misses nearby fibers. It is an explicit resolution
        limit of this self-shadow approximation.

        Args:
            point: A current groom point inside the grid, in meters.
            direction: The finite unit direction toward a distant light.

        Returns:
            Dimensionless optical depth, or zero for an empty volume,
            an exterior point or a zero direction.

        Raises:
            Error: If the point or direction is not finite.
        """
        if (
            not isfinite(point.x)
            or not isfinite(point.y)
            or not isfinite(point.z)
        ):
            raise Error("Hair optical depth needs a finite point")
        if (
            not isfinite(direction.x)
            or not isfinite(direction.y)
            or not isfinite(direction.z)
        ):
            raise Error("Hair optical depth needs a finite light direction")
        if not self.populated or self._slot(point) < 0:
            return 0
        var length = direction.length()
        if not isfinite(length) or length == 0:
            return 0
        var step = direction * (self.cell * 0.5 / length)
        var p = point + step * 2.5
        var total = Float32(0)
        for _ in range(self.resolution * 4):
            var slot = self._slot(p)
            if slot < 0:
                break
            total += self.coefficients[slot] * self.cell * 0.5
            p = p + step
        return total
