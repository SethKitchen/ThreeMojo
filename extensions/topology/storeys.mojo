# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cell complex from a stack of storey plans.

Each storey is a plan of regions between two levels. Every region becomes
a prism-shaped cell. The plan's arrangement gives the walls: one vertical
face for each arrangement edge that has different regions on its two
sides, shared by both. The overlay of each plan on the plan below gives
the floors: one horizontal face for each overlay face, shared by the cell
below and the cell above. The ground under the first storey and the roof
over the last are horizontal faces with the outside on one side.

The complex is watertight. A vertex of one plan that lies on an edge of
the plan above or below splits the wall faces along that edge, so the
wall's bottom or top edge meets the floor faces at the same vertices.

Coordinates are z up: a plan point (x, y) lies at height z.
"""

from std.math import isfinite
from extensions.topology.arrangement import (
    Arrangement,
    Point2,
    Region,
    arrange,
)
from extensions.topology.complex import (
    CellComplex,
    HORIZONTAL,
    VERTICAL,
)
from extensions.topology.ids import CellId, FaceId, RegionId, VertexId
from generators.utils import Vec3d
from units.si import Length64, METER


struct StoreyComplex(Movable):
    """A cell complex built from storey plans, and where each cell came from."""

    var complex: CellComplex
    # The storey and the region of each cell.
    var cell_storey: List[Int]
    var cell_region: List[RegionId]
    # The storey of each vertical face, or the level of each horizontal
    # face: level i is the bottom of storey i.
    var face_level: List[Int]

    def __init__(out self, var complex: CellComplex):
        """Hold a complex. `build_storeys` makes these.

        Args:
            complex: The empty complex to fill.
        """
        self.complex = complex^
        self.cell_storey = List[Int]()
        self.cell_region = List[RegionId]()
        self.face_level = List[Int]()

    def cell_of(self, storey: Int, region: RegionId) -> Optional[CellId]:
        """Return the cell of a region on a storey, if there is one.

        Args:
            storey: The storey index.
            region: The region's id.

        Returns:
            The cell, or None if the storey has no such region.
        """
        for c in range(len(self.cell_storey)):
            if self.cell_storey[c] == storey and self.cell_region[c] == region:
                return CellId(c)
        return None


def _vertex(mut complex: CellComplex, p: Point2, z: Float64) raises -> VertexId:
    """Return the complex's vertex at a plan point and a height."""
    return complex.add_vertex(Vec3d(p.x, p.y, z))


def _points_on(
    overlay: Arrangement, a: Point2, b: Point2, tolerance: Float64
) -> List[Point2]:
    """Return the overlay vertices strictly inside a segment, from a to b."""
    var d = b - a
    var length_squared = d.dot(d)
    var found_t = List[Float64]()
    var found = List[Point2]()
    for i in range(len(overlay.points)):  # pragma: no branch
        var p = overlay.points[i]
        var t = (p - a).dot(d) / length_squared
        var foot = Point2(a.x + t * d.x, a.y + t * d.y)
        var offset = p - foot
        var near_end = (
            t * t * length_squared <= tolerance * tolerance
            or (1 - t) * (1 - t) * length_squared <= tolerance * tolerance
        )
        if offset.dot(offset) <= tolerance * tolerance and not near_end:
            if t > 0 and t < 1:
                var k = len(found)
                found.append(p)
                found_t.append(t)
                while k > 0 and found_t[k - 1] > t:
                    found_t[k] = found_t[k - 1]
                    found[k] = found[k - 1]
                    k -= 1
                found_t[k] = t
                found[k] = p
    return found^


def build_storeys(
    levels: List[Length64], plans: List[List[Region]], tolerance: Length64
) raises -> StoreyComplex:
    """Return the cell complex of a stack of storey plans.

    Storey i lies between `levels[i]` and `levels[i + 1]`. Its plan is
    `plans[i]`: regions on layer zero, with ids unique within the storey.

    Args:
        levels: The heights of the storey boundaries, strictly increasing.
            One more than the storey count.
        plans: One plan per storey.
        tolerance: Points closer than this are one point. Positive.

    Returns:
        The complex, with each cell's storey and region and each face's
        level.

    Raises:
        Error: If the levels and plans do not match, the levels do not
            increase, a plan is not a valid layer-zero arrangement, a
            region id repeats on a storey.
    """
    var storeys = len(plans)
    if len(levels) != storeys + 1:
        raise Error("There must be one more level than storeys")
    var tol = tolerance.to(METER)
    var z = List[Float64](capacity=len(levels))
    for i in range(len(levels)):  # pragma: no branch
        var value = levels[i].to(METER)
        if not isfinite(value):
            raise Error("A level must be finite")
        if i > 0 and not (value > z[i - 1] + tol):
            raise Error("Levels must increase by more than the tolerance")
        z.append(value)
    var out = StoreyComplex(CellComplex(tol))
    # The plan arrangements, and a cell per region.
    var plan_arrangements = List[Arrangement]()
    var region_cells = List[Dict[Int, Int]]()
    for s in range(storeys):
        for r in range(len(plans[s])):
            if plans[s][r].layer != 0:
                raise Error("A storey plan's regions must be on layer zero")
        var cells = Dict[Int, Int]()
        for r in range(len(plans[s])):
            var id = plans[s][r].id.value
            if id in cells:
                raise Error("A region id must not repeat on a storey")
            cells[id] = out.complex.add_cell().value
            out.cell_storey.append(s)
            out.cell_region.append(plans[s][r].id)
        region_cells.append(cells^)
        plan_arrangements.append(arrange(plans[s], 1, tolerance))
    # The overlay at each level: the plan below on layer 0, above on 1.
    var overlays = List[Arrangement]()
    for level in range(storeys + 1):  # pragma: no branch
        var both = List[Region]()
        if level > 0:
            for r in range(len(plans[level - 1])):
                ref region = plans[level - 1][r]
                both.append(Region(0, region.id, region.points.copy()))
        if level < storeys:
            for r in range(len(plans[level])):
                ref region = plans[level][r]
                both.append(Region(1, region.id, region.points.copy()))
        overlays.append(arrange(both, 2, tolerance))
    # Floors, ceilings, the ground and the roof.
    for level in range(storeys + 1):  # pragma: no branch
        ref overlay = overlays[level]
        for f in range(len(overlay.faces)):
            ref face = overlay.faces[f]
            var below = Optional[CellId](None)
            var above = Optional[CellId](None)
            if level > 0 and face.labels[0].is_valid():
                below = CellId(region_cells[level - 1][face.labels[0].value])
            if level < storeys and face.labels[1].is_valid():
                above = CellId(region_cells[level][face.labels[1].value])
            if not below and not above:
                continue
            var loop = List[VertexId]()
            for k in range(len(face.loop)):  # pragma: no branch
                loop.append(
                    _vertex(out.complex, overlay.points[face.loop[k]], z[level])
                )
            _ = out.complex.add_face(loop^, above, below, HORIZONTAL)
            out.face_level.append(level)
    # Walls: one face per plan edge with different cells on its sides.
    for s in range(storeys):
        ref plan = plan_arrangements[s]
        for e in range(len(plan.edges)):
            var edge = plan.edges[e]
            var left = _side_cell(plan, edge.left, region_cells[s])
            var right = _side_cell(plan, edge.right, region_cells[s])
            # No wall where no cell is on either side. A bridge edge has
            # the outside on both sides: a region never encloses another
            # region of its own plan.
            if not left and not right:
                continue
            var a = plan.points[edge.a]
            var b = plan.points[edge.b]
            var loop = List[VertexId]()
            loop.append(_vertex(out.complex, a, z[s]))
            var bottom = _points_on(overlays[s], a, b, tol)
            for k in range(len(bottom)):
                loop.append(_vertex(out.complex, bottom[k], z[s]))
            loop.append(_vertex(out.complex, b, z[s]))
            loop.append(_vertex(out.complex, b, z[s + 1]))
            var top = _points_on(overlays[s + 1], b, a, tol)
            for k in range(len(top)):
                loop.append(_vertex(out.complex, top[k], z[s + 1]))
            loop.append(_vertex(out.complex, a, z[s + 1]))
            # The loop runs a, b along the bottom, so its normal points
            # to the right of a to b.
            _ = out.complex.add_face(loop^, right, left, VERTICAL)
            out.face_level.append(s)
    return out^


def _side_cell(
    plan: Arrangement, face: Int, cells: Dict[Int, Int]
) raises -> Optional[CellId]:
    """Return the cell of the region on one side of a plan edge, or None."""
    if face < 0:
        return None
    var label = plan.faces[face].labels[0]
    if not label.is_valid():
        return None
    return CellId(cells[label.value])
