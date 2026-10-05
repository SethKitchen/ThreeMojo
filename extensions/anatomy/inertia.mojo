# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Mass, center of mass and inertia tensor, tallied cell by cell.

A body's inertial properties are integrals of its density. An anatomy
samples itself on a grid, gives each cell the density of the tissue
that fills it, and adds the cell to an `InertiaTally`. Each cell is a
constant-density cuboid and adds its own inertia, `m w^2 / 12` per axis,
as well as its moment about the origin. `InertiaTally.result` moves the
second moments to the center of mass by the parallel-axis theorem.

The humanoid's limb segments and the animals' body segments both use it.
Sums are in `Float64`, so a million cells keep their precision.
"""

from math.vector3 import Vector3
from std.math import isfinite, sqrt
from units.si import (
    KILOGRAM,
    KILOGRAM_SQUARE_METER,
    METER,
    Length,
    Mass,
    MomentOfInertia,
)


def _check_second_moments(
    xx: Float64,
    yy: Float64,
    zz: Float64,
    xy: Float64,
    xz: Float64,
    yz: Float64,
    tolerance: Float64,
) raises:
    # A realizable body's central second-moment matrix is positive
    # semidefinite. This also enforces the inertia triangle inequalities.
    var scale = max(
        abs(xx), max(abs(yy), max(abs(zz), max(abs(xy), max(abs(xz), abs(yz)))))
    )
    if scale == 0.0:
        return
    var a = xx / scale
    var b = yy / scale
    var c = zz / scale
    var d = xy / scale
    var e = xz / scale
    var f = yz / scale
    if min(a, min(b, c)) < -tolerance:
        raise Error("A sampled tensor must have nonnegative second moments")
    if min(a * b - d * d, min(a * c - e * e, b * c - f * f)) < -tolerance:
        raise Error("A sampled tensor must be physically admissible")
    var determinant = (
        a * b * c + 2 * d * e * f - a * f * f - b * e * e - c * d * d
    )
    if determinant < -tolerance:
        raise Error("A sampled tensor must be physically admissible")


@fieldwise_init
struct SegmentInertia(ImplicitlyCopyable):
    """The inertial properties of one segment.

    The inertia tensor is about the center of mass, along the frame's
    axes: `xx`, `yy` and `zz` on the diagonal and the products `xy`,
    `xz` and `yz` off it, with the sign convention of a tensor, so an
    off-diagonal entry is minus the product of inertia.
    """

    var mass: Mass
    # The center of mass in the segment's frame, in meters.
    var center: Vector3
    var xx: MomentOfInertia
    var yy: MomentOfInertia
    var zz: MomentOfInertia
    var xy: MomentOfInertia
    var xz: MomentOfInertia
    var yz: MomentOfInertia
    # The segment's length, joint center to joint center.
    var length: Length

    def check(self) raises:
        """Refuse nonfinite or physically inadmissible mass properties.

        Raises:
            Error: If mass is not positive, length is negative, a value
                is not finite, or the tensor cannot describe a body.
        """
        if not (isfinite(self.mass.value) and self.mass.value > 0.0):
            raise Error("A segment must have finite positive mass")
        if not (isfinite(self.length.value) and self.length.value >= 0.0):
            raise Error("A segment length must be finite and nonnegative")
        var values: List[Float32] = [
            self.center.x,
            self.center.y,
            self.center.z,
            self.xx.value,
            self.yy.value,
            self.zz.value,
            self.xy.value,
            self.xz.value,
            self.yz.value,
        ]
        comptime for axis in range(9):
            if not isfinite(values[axis]):
                raise Error("Segment mass properties must be finite")
        if min(self.xx.value, min(self.yy.value, self.zz.value)) < 0.0:
            raise Error("An inertia diagonal must be nonnegative")
        var x = Float64(self.xx.value)
        var y = Float64(self.yy.value)
        var z = Float64(self.zz.value)
        _check_second_moments(
            (y + z - x) * 0.5,
            (x + z - y) * 0.5,
            (x + y - z) * 0.5,
            -Float64(self.xy.value),
            -Float64(self.xz.value),
            -Float64(self.yz.value),
            1e-6,
        )

    def gyration(self, moment: MomentOfInertia) raises -> Length:
        """Return the radius of gyration of one principal moment.

        Args:
            moment: `xx`, `yy` or `zz`.

        Returns:
            The square root of the moment over the mass.

        Raises:
            Error: If the mass properties, moment or SI result is invalid.
        """
        self.check()
        if not (isfinite(moment.value) and moment.value >= 0.0):
            raise Error("A gyration moment must be finite and nonnegative")
        var value = Float32(
            sqrt(Float64(moment.value) / Float64(self.mass.value))
        )
        if not isfinite(value):
            raise Error("A radius of gyration must fit a finite SI length")
        return Length(value, METER)


struct InertiaTally(Copyable, Movable):
    """Running sums of mass and of first and second moments of mass."""

    var mass: Float64
    var first: SIMD[DType.float64, 4]
    var second: SIMD[DType.float64, 8]

    def __init__(out self):
        """Start with nothing tallied."""
        self.mass = 0.0
        self.first = SIMD[DType.float64, 4](0)
        self.second = SIMD[DType.float64, 8](0)

    def add_cell(mut self, m: Float64, p: Vector3, widths: Vector3) raises:
        """Add a constant-density cuboid, including its own inertia.

        Args:
            m: The cuboid's mass, in kilograms.
            p: Its center, in meters.
            widths: Its nonnegative edge lengths, in meters. Zero permits
                an independent point-mass reference.

        Raises:
            Error: If a value is not finite, or a mass or width is negative.
        """
        if not (isfinite(m) and m >= 0.0):
            raise Error("A cell mass must be finite and nonnegative")
        comptime for axis in range(3):
            if not isfinite(p.get_component(axis)):
                raise Error("A cell center must be finite")
            var w = widths.get_component(axis)
            if not (isfinite(w) and w >= 0.0):
                raise Error("Cell widths must be finite and nonnegative")
        self._add_cell(m, p, widths)

    def _add_cell(mut self, m: Float64, p: Vector3, widths: Vector3):
        # Inner grid loop. Its caller validates density, grid and geometry
        # before workers start; result() validates the accumulated sums.
        var r = SIMD[DType.float64, 4](
            Float64(p.x), Float64(p.y), Float64(p.z), 0
        )
        var w = SIMD[DType.float64, 4](
            Float64(widths.x), Float64(widths.y), Float64(widths.z), 0
        )
        self.mass += m
        self.first += r * m
        self.second += (
            SIMD[DType.float64, 8](
                r[0] * r[0] + w[0] * w[0] / 12,
                r[1] * r[1] + w[1] * w[1] / 12,
                r[2] * r[2] + w[2] * w[2] / 12,
                r[0] * r[1],
                r[0] * r[2],
                r[1] * r[2],
                0,
                0,
            )
            * m
        )

    def add(mut self, other: Self) raises:
        """Add another tally, as if its cells were added here.

        Args:
            other: The tally to fold in.

        Raises:
            Error: If either tally has nonfinite or negative mass or moments.
        """
        self._check_sums()
        other._check_sums()
        self.mass += other.mass
        self.first += other.first
        self.second += other.second

    def _check_sums(self) raises:
        if not (isfinite(self.mass) and self.mass >= 0.0):
            raise Error("A tally mass must be finite and nonnegative")
        comptime for axis in range(3):
            if not isfinite(self.first[axis]):
                raise Error("Tally first moments must be finite")
        comptime for axis in range(6):
            if not isfinite(self.second[axis]):
                raise Error("Tally second moments must be finite")
        if self.mass == 0.0:
            comptime for axis in range(3):
                if self.first[axis] != 0.0:
                    raise Error("A zero-mass tally cannot hold first moments")
            comptime for axis in range(6):
                if self.second[axis] != 0.0:
                    raise Error("A zero-mass tally cannot hold second moments")

    def result(self, length: Float32) raises -> SegmentInertia:
        """Return the tensor about the center of mass.

        Args:
            length: The segment's length, in meters, recorded with it.

        Returns:
            The mass, the center of mass and the inertia tensor.

        Raises:
            Error: If a quantity is invalid, the tensor is not physically
                admissible, or the SI output cannot represent it.
        """
        self._check_sums()
        if not (isfinite(length) and length >= 0.0):
            raise Error("A segment length must be finite and nonnegative")
        var mass = self.mass
        # _check_sums already established finite nonnegative mass.
        if mass == 0.0:
            raise Error("A sampled segment must have finite positive mass")
        var c = self.first / mass
        # Second moments about the center, by the parallel-axis theorem.
        var sxx = self.second[0] - mass * c[0] * c[0]
        var syy = self.second[1] - mass * c[1] * c[1]
        var szz = self.second[2] - mass * c[2] * c[2]
        var sxy = self.second[3] - mass * c[0] * c[1]
        var sxz = self.second[4] - mass * c[0] * c[2]
        var syz = self.second[5] - mass * c[1] * c[2]
        _check_second_moments(sxx, syy, szz, sxy, sxz, syz, 1e-10)
        var result = SegmentInertia(
            Mass(Float32(mass), KILOGRAM),
            Vector3(Float32(c[0]), Float32(c[1]), Float32(c[2])),
            MomentOfInertia(Float32(syy + szz), KILOGRAM_SQUARE_METER),
            MomentOfInertia(Float32(sxx + szz), KILOGRAM_SQUARE_METER),
            MomentOfInertia(Float32(sxx + syy), KILOGRAM_SQUARE_METER),
            MomentOfInertia(Float32(-sxy), KILOGRAM_SQUARE_METER),
            MomentOfInertia(Float32(-sxz), KILOGRAM_SQUARE_METER),
            MomentOfInertia(Float32(-syz), KILOGRAM_SQUARE_METER),
            Length(length, METER),
        )
        result.check()
        return result
