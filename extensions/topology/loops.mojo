# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Split a face loop that runs along bridges into an outer ring and holes.

An arrangement face with a hole is one loop: it runs along a bridge edge
to the hole, around the hole and back along the bridge. An exchange file
and a triangulator want the outer ring and the holes apart. A bridge is
an edge whose reverse is also in the loop. Removing the bridges leaves
cycles. A cycle that winds the same way as the whole loop is the outer
ring; the others are holes.

The corners are compared exactly: the corners of a face are welded
vertices, so a corner that the loop visits twice has the same coordinates
both times.
"""

from generators.utils import Vec3d


struct LoopParts(Movable):
    """The outer ring and the holes of a face loop."""

    var outer: List[Vec3d]
    var holes: List[List[Vec3d]]

    def __init__(
        out self, var outer: List[Vec3d], var holes: List[List[Vec3d]]
    ):
        """Hold the parts.

        Args:
            outer: The outer ring, in the loop's direction.
            holes: The holes, each winding the other way.
        """
        self.outer = outer^
        self.holes = holes^


def _same(a: Vec3d, b: Vec3d) -> Bool:
    """Return True if two corners have the same coordinates."""
    return a.x == b.x and a.y == b.y and a.z == b.z


def vector_area(points: List[Vec3d]) -> Vec3d:
    """Return a loop's normal scaled by its area, by Newell's method.

    Args:
        points: The corners in order.

    Returns:
        The vector area, in square meters.
    """
    var total = Vec3d(0, 0, 0)
    var n = len(points)
    for i in range(n):
        var a = points[i]
        var b = points[(i + 1) % n]
        total = total + Vec3d(
            (a.y - b.y) * (a.z + b.z),
            (a.z - b.z) * (a.x + b.x),
            (a.x - b.x) * (a.y + b.y),
        )
    return total * 0.5


def split_bridged(points: List[Vec3d]) raises -> LoopParts:
    """Return the outer ring and the holes of a face loop.

    Args:
        points: The loop's corners in order. A loop with no bridge is
            returned whole as the outer ring.

    Returns:
        The outer ring and the holes.

    Raises:
        Error: If the loop has fewer than three corners.
    """
    var n = len(points)
    if n < 3:
        raise Error("A face loop needs three corners or more")
    var bridge = List[Bool](capacity=n)
    for i in range(n):  # pragma: no branch
        var p = points[i]
        var q = points[(i + 1) % n]
        var found = False
        for k in range(n):  # pragma: no branch
            if _same(points[k], q) and _same(points[(k + 1) % n], p):
                found = True
        bridge.append(found)
    var used = List[Bool](capacity=n)
    for _ in range(n):  # pragma: no branch
        used.append(False)
    var cycles = List[List[Vec3d]]()
    for start in range(n):  # pragma: no branch
        if bridge[start] or used[start]:
            continue
        var cycle = List[Vec3d]()
        var e = start
        while True:
            used[e] = True
            cycle.append(points[e])
            # The next kept edge starts where this one ends.
            var end = points[(e + 1) % n]
            var next = -1
            for k in range(n):  # pragma: no branch
                if not bridge[k] and not used[k] and _same(points[k], end):
                    next = k
            if next < 0:
                # Removing pairs of opposite edges leaves every corner with
                # as many edges in as out, so the trace closes.
                debug_assert(_same(points[start], end), "an open cycle")
                break
            e = next
        cycles.append(cycle^)
    var whole = vector_area(points)
    var outer = List[Vec3d]()
    var holes = List[List[Vec3d]]()
    for c in range(len(cycles)):  # pragma: no branch
        if vector_area(cycles[c]).dot(whole) > 0 and len(outer) == 0:
            outer = cycles[c].copy()
        else:
            holes.append(cycles[c].copy())
    return LoopParts(outer^, holes^)
