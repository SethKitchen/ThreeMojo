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

    def gyration(self, moment: MomentOfInertia) -> Length:
        """Return the radius of gyration of one principal moment.

        Args:
            moment: `xx`, `yy` or `zz`.

        Returns:
            The square root of the moment over the mass.
        """
        return Length(sqrt(moment.value / self.mass.value), METER)


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

    def add_cell(mut self, m: Float64, p: Vector3, widths: Vector3):
        """Add a constant-density cuboid, including its own inertia.

        Args:
            m: The cuboid's mass, in kilograms.
            p: Its center, in meters.
            widths: Its edge lengths, in meters.
        """
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

    def add(mut self, other: Self):
        """Add another tally, as if its cells were added here.

        Args:
            other: The tally to fold in.
        """
        self.mass += other.mass
        self.first += other.first
        self.second += other.second

    def result(self, length: Float32) raises -> SegmentInertia:
        """Return the tensor about the center of mass.

        Args:
            length: The segment's length, in meters, recorded with it.

        Returns:
            The mass, the center of mass and the inertia tensor.

        Raises:
            Error: If the tallied mass is not finite and positive.
        """
        var mass = self.mass
        if not isfinite(mass) or mass <= 0:
            raise Error("A sampled segment must have finite positive mass")
        var c = self.first / mass
        # Second moments about the center, by the parallel-axis theorem.
        var sxx = self.second[0] - mass * c[0] * c[0]
        var syy = self.second[1] - mass * c[1] * c[1]
        var szz = self.second[2] - mass * c[2] * c[2]
        var sxy = self.second[3] - mass * c[0] * c[1]
        var sxz = self.second[4] - mass * c[0] * c[2]
        var syz = self.second[5] - mass * c[1] * c[2]
        return SegmentInertia(
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
