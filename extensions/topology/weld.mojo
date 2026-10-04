# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Merge points that lie within a tolerance of each other.

A `Welder` keeps a list of distinct points and a hash grid of cells one
tolerance wide. `weld` returns the index of a kept point within the
tolerance of the new one, or keeps the new point. Two points closer than
the tolerance are one point; two points farther apart than twice the
tolerance are never merged.
"""

from std.math import floor, isfinite
from generators.utils import Vec3d


def _cell(value: Float64, size: Float64) -> Int:
    """Return the grid cell index of one coordinate."""
    return Int(floor(value / size))


def _key(ix: Int, iy: Int, iz: Int) -> Int:
    """Return a hash key for a grid cell."""
    return (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791)


struct Welder(Movable):
    """Distinct points, merged within a tolerance."""

    var points: List[Vec3d]
    var tolerance: Float64
    var _grid: Dict[Int, List[Int]]

    def __init__(out self, tolerance: Float64) raises:
        """Create an empty welder.

        Args:
            tolerance: The merge distance, in meters. Positive and finite.

        Raises:
            Error: If the tolerance is not positive and finite.
        """
        if not (tolerance > 0 and isfinite(tolerance)):
            raise Error("A weld tolerance must be positive and finite")
        self.points = List[Vec3d]()
        self.tolerance = tolerance
        self._grid = Dict[Int, List[Int]]()

    def find(self, p: Vec3d) raises -> Int:
        """Return the index of a kept point within the tolerance, or -1.

        Args:
            p: The point.

        Returns:
            The index of the nearest kept point within the tolerance, or
            -1 if there is none.

        Raises:
            Error: Never, for a welder made by this module.
        """
        var ix = _cell(p.x, self.tolerance)
        var iy = _cell(p.y, self.tolerance)
        var iz = _cell(p.z, self.tolerance)
        var best = -1
        var best_distance = self.tolerance
        for dx in range(-1, 2):  # pragma: no branch
            for dy in range(-1, 2):  # pragma: no branch
                for dz in range(-1, 2):  # pragma: no branch
                    var key = _key(ix + dx, iy + dy, iz + dz)
                    if key not in self._grid:
                        continue
                    ref bucket = self._grid[key]
                    for k in range(len(bucket)):  # pragma: no branch
                        var d = self.points[bucket[k]].distance_to(p)
                        if d <= best_distance:
                            best_distance = d
                            best = bucket[k]
        return best

    def weld(mut self, p: Vec3d) raises -> Int:
        """Return the index of a kept point within the tolerance, keeping
        the point if there is none.

        Args:
            p: The point. Its coordinates must be finite.

        Returns:
            The index of the kept point.

        Raises:
            Error: If a coordinate is not finite.
        """
        if not (isfinite(p.x) and isfinite(p.y) and isfinite(p.z)):
            raise Error("A point must have finite coordinates")
        var found = self.find(p)
        if found >= 0:
            return found
        var index = len(self.points)
        self.points.append(p)
        var key = _key(
            _cell(p.x, self.tolerance),
            _cell(p.y, self.tolerance),
            _cell(p.z, self.tolerance),
        )
        if key in self._grid:
            self._grid[key].append(index)
        else:
            self._grid[key] = [index]
        return index
