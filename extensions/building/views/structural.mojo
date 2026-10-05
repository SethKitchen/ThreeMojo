# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The structural view of a building: a frame, with gravity loads.

`structural_view` turns a `Building` into a `StructuralModel`:

- Each column and beam becomes frame members. Ends closer than the
  tolerance share one node. A member is split where another member's end
  lies on it, so the frame is connected.
- The lowest column bases are fixed in all six degrees of freedom.
- The dead load case holds the weight of the members and of each floor
  and roof construction. The live load case holds a live load for the use
  of the space above each floor, and a roof live load.
- By default, each floor and roof carries its load to the beams at its
  level by tributary area: each point of the slab goes to the nearest
  beam. With `shell_divisions` above zero, each floor and roof becomes a
  mesh of flat shells instead, and carries its own load.

The view drops the walls, the openings and the ground slabs. It records
what it drops in `notes`.

The live loads are typical values from ASCE/SEI 7-16, "Minimum Design
Loads and Associated Criteria for Buildings and Other Structures", table
4.3-1. They are not design values. A project must use the loads of its own
code and occupancy.
"""

from std.math import isfinite
from extensions.building.ids import ElementId
from extensions.building.kinds import BEAM, COLUMN, SpaceUse, WALL
from extensions.building.material import BuildingMaterial
from extensions.building.model import Building
from extensions.structure.ids import LoadCaseId, MemberId, NodeId, ShellId
from extensions.structure.kinds import UZ
from extensions.structure.model import StructuralModel
from extensions.topology.ids import FaceId
from geometries.earcut import earcut
from generators.utils import Vec3d
from units.si import (
    Acceleration64,
    Density64,
    KILOPASCAL,
    Length64,
    LineLoad64,
    METER,
    METER_PER_SECOND_SQUARED,
    PASCAL,
    Pressure64,
)

# The grid of samples across each slab's bounding box, per side.
comptime _SAMPLES = 32
# The most divisions of each slab triangle.
comptime _MAX_DIVISIONS = 16


def live_load(use: SpaceUse) raises -> Pressure64:
    """Return a typical uniform live load for a space use.

    The values are from ASCE/SEI 7-16, table 4.3-1: an office 2.40 kPa; a
    corridor, a core with stairs, a lobby, the first floor of a retail
    store and a meeting room with movable seats 4.79 kPa; a dwelling's
    rooms 1.92 kPa; light storage 6.00 kPa. The table has no row for a
    mechanical room, so it gets 7.18 kPa, the value of a library stack
    room. These are typical values, not design values.

    Args:
        use: The use of the space.

    Returns:
        The live load per floor area.

    Raises:
        Error: If the use is not valid.
    """
    if not use.is_valid():
        raise Error("A space use is not valid")
    var kpa: List[Float64] = [
        2.40,
        4.79,
        4.79,
        4.79,
        4.79,
        1.92,
        1.92,
        1.92,
        1.92,
        6.00,
        7.18,
        4.79,
    ]
    return Pressure64(kpa[use.value], KILOPASCAL)


def roof_live_load() -> Pressure64:
    """Return a typical live load for a flat roof.

    Returns:
        0.96 kPa, the ordinary flat roof of ASCE/SEI 7-16, table 4.3-1.
    """
    return Pressure64(0.96, KILOPASCAL)


@fieldwise_init
struct StructuralViewOptions(ImplicitlyCopyable):
    """How `structural_view` builds its model."""

    # Points closer than this are one node.
    var tolerance: Length64
    # Zero to load the beams by tributary area. From 1 to 16 to make each
    # floor and roof a shell mesh, with each triangle of its earcut split
    # into that many divisions per side.
    var shell_divisions: Int
    # The acceleration of gravity for the weights.
    var gravity: Acceleration64

    def check(self) raises:
        """Refuse options that cannot build a model.

        Raises:
            Error: If the tolerance is not positive and finite, the shell
                divisions are outside 0 to 16, or the gravity is negative
                or not finite.
        """
        var t = self.tolerance.to(METER)
        if not (t > 0 and isfinite(t)):
            raise Error("A tolerance must be positive and finite")
        if self.shell_divisions < 0 or self.shell_divisions > _MAX_DIVISIONS:
            raise Error("The shell divisions must be from 0 to 16")
        var g = self.gravity.to(METER_PER_SECOND_SQUARED)
        if not (g >= 0 and isfinite(g)):
            raise Error("A gravity must be zero or more and finite")


def default_options() -> StructuralViewOptions:
    """Return the usual options.

    Returns:
        A 1 mm tolerance, tributary loads and standard gravity.
    """
    return StructuralViewOptions(
        Length64(0.001, METER),
        0,
        Acceleration64(9.80665, METER_PER_SECOND_SQUARED),
    )


struct StructuralView(Movable):
    """A structural model derived from a building, with what it dropped."""

    var model: StructuralModel
    var dead: LoadCaseId
    var live: LoadCaseId
    # The column or beam that each member comes from.
    var member_element: List[ElementId]
    # The floor or roof that each shell comes from.
    var shell_element: List[ElementId]
    # One sentence for each thing the view dropped or simplified.
    var notes: List[String]

    def __init__(
        out self,
        var model: StructuralModel,
        dead: LoadCaseId,
        live: LoadCaseId,
        var member_element: List[ElementId],
        var shell_element: List[ElementId],
        var notes: List[String],
    ):
        """Hold a view. `structural_view` makes these.

        Args:
            model: The structural model.
            dead: The dead load case.
            live: The live load case.
            member_element: The building element of each member.
            shell_element: The building element of each shell.
            notes: What the view dropped or simplified.
        """
        self.model = model^
        self.dead = dead
        self.live = live
        self.member_element = member_element^
        self.shell_element = shell_element^
        self.notes = notes^


def _node_at(
    mut model: StructuralModel, p: Vec3d, tolerance: Float64
) raises -> NodeId:
    """Return the node within the tolerance of a point, or a new one."""
    for i in range(len(model.nodes)):
        if model.nodes[i].distance_to(p) <= tolerance:
            return NodeId(i)
    return model.add_node(p)


def _plan_distance(p: Vec3d, a: Vec3d, b: Vec3d) -> Float64:
    """Return the plan distance from a point to a segment."""
    var dx = b.x - a.x
    var dy = b.y - a.y
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    var ex = a.x + t * dx - p.x
    var ey = a.y + t * dy - p.y
    return (ex * ex + ey * ey) ** 0.5


def _inside(polygon: List[Vec3d], p: Vec3d) -> Bool:
    """Return True if a point is inside a plan polygon, by ray casting."""
    var inside = False
    var j = len(polygon) - 1
    for i in range(len(polygon)):  # pragma: no branch
        var a = polygon[i]
        var b = polygon[j]
        if (a.y > p.y) != (b.y > p.y):
            var x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
            if p.x < x:
                inside = not inside
        j = i
    return inside


def _on_or_inside(polygon: List[Vec3d], p: Vec3d, tolerance: Float64) -> Bool:
    """Return True if a point is inside a polygon or on its boundary."""
    var j = len(polygon) - 1
    for i in range(len(polygon)):  # pragma: no branch
        if _plan_distance(p, polygon[j], polygon[i]) <= tolerance:
            return True
        j = i
    return _inside(polygon, p)


@fieldwise_init
struct _Slab(Copyable, Movable):
    """A floor or roof that carries load: its face, level and loads."""

    var element: Int
    var face: FaceId
    var dead: Float64
    var live: Float64
    var material: BuildingMaterial
    var thickness: Float64


def _slab(building: Building, element: Int, g: Float64) raises -> _Slab:
    """Return the loads and the equivalent shell material of a slab.

    The material is the thickest layer's, with its density set so that the
    shell's mass per area equals the construction's.
    """
    ref e = building.elements[element]
    var face = e.faces[0]
    ref construction = building.constructions[e.construction.value().value]
    var areal = Float64(0)
    var thickness = Float64(0)
    var thickest = 0
    for i in range(len(construction.layers)):  # pragma: no branch
        ref layer = construction.layers[i]
        var t = layer.thickness.to(METER)
        areal += building.materials[layer.material.value].density.value * t
        thickness += t
        if t > construction.layers[thickest].thickness.to(METER):
            thickest = i
    var material = building.materials[
        construction.layers[thickest].material.value
    ].copy()
    material.density = Density64(areal / thickness)
    ref above = building.topology.complex.faces[face.value].positive
    var live = roof_live_load()
    if above:
        live = live_load(building.spaces[above.value().value].use)
    return _Slab(
        element, face, areal * g, live.to(PASCAL), material^, thickness
    )


def _mesh(points: List[Vec3d], divisions: Int) raises -> List[Vec3d]:
    """Return a slab polygon as triangles, three corners each.

    Each triangle of the polygon's earcut is split into `divisions` parts
    per side.
    """
    var data = List[Float64](capacity=2 * len(points))
    for i in range(len(points)):  # pragma: no branch
        data.append(points[i].x)
        data.append(points[i].y)
    var cut = earcut(data)
    var z = points[0].z
    var out = List[Vec3d]()
    var n = Float64(divisions)
    for k in range(len(cut) // 3):  # pragma: no branch
        var a = points[cut[3 * k]]
        var ab = points[cut[3 * k + 1]] - a
        var ac = points[cut[3 * k + 2]] - a
        for i in range(divisions):  # pragma: no branch
            for j in range(divisions - i):  # pragma: no branch
                var fi = Float64(i)
                var fj = Float64(j)
                var p00 = a + ab * (fi / n) + ac * (fj / n)
                var p10 = a + ab * ((fi + 1) / n) + ac * (fj / n)
                var p01 = a + ab * (fi / n) + ac * ((fj + 1) / n)
                out.append(Vec3d(p00.x, p00.y, z))
                out.append(Vec3d(p10.x, p10.y, z))
                out.append(Vec3d(p01.x, p01.y, z))
                if i + j < divisions - 1:
                    var p11 = a + ab * ((fi + 1) / n) + ac * ((fj + 1) / n)
                    out.append(Vec3d(p10.x, p10.y, z))
                    out.append(Vec3d(p11.x, p11.y, z))
                    out.append(Vec3d(p01.x, p01.y, z))
    return out^


def _tributary(
    mut model: StructuralModel,
    building: Building,
    slab: _Slab,
    dead: LoadCaseId,
    live: LoadCaseId,
    tolerance: Float64,
    mut notes: List[String],
) raises:
    """Load the beams at a slab's level with the slab's loads.

    Each grid point inside the slab goes to the nearest beam in plan. A
    beam takes the share of the slab area that its points have, as a
    uniform load along its length. The face centroid is one more point, so
    every slab has one.
    """
    ref complex = building.topology.complex
    var polygon = complex.face_points(slab.face)
    var z = polygon[0].z
    var beams = List[Int]()
    for m in range(len(model.members)):
        var a = model.nodes[model.members[m].start.value]
        var b = model.nodes[model.members[m].end.value]
        var middle = (a + b) * 0.5
        if (
            abs(a.z - z) <= tolerance
            and abs(b.z - z) <= tolerance
            and _on_or_inside(polygon, middle, tolerance)
        ):
            beams.append(m)
    if len(beams) == 0:
        notes.append(
            String(
                "The ",
                building.elements[slab.element].name,
                " has no beam at its level, so its load is dropped.",
            )
        )
        return
    var counts = List[Int](length=len(beams), fill=0)
    var low = polygon[0]
    var high = polygon[0]
    for i in range(len(polygon)):  # pragma: no branch
        low = Vec3d(min(low.x, polygon[i].x), min(low.y, polygon[i].y), z)
        high = Vec3d(max(high.x, polygon[i].x), max(high.y, polygon[i].y), z)
    var samples: List[Vec3d] = [complex.face_centroid(slab.face)]
    for gi in range(_SAMPLES):  # pragma: no branch
        for gj in range(_SAMPLES):  # pragma: no branch
            var p = Vec3d(
                low.x + (high.x - low.x) * (Float64(gi) + 0.5) / _SAMPLES,
                low.y + (high.y - low.y) * (Float64(gj) + 0.5) / _SAMPLES,
                z,
            )
            if _inside(polygon, p):
                samples.append(p)
    for s in range(len(samples)):  # pragma: no branch
        var best = 0
        var best_distance = Float64.MAX
        for k in range(len(beams)):  # pragma: no branch
            ref member = model.members[beams[k]]
            var d = _plan_distance(
                samples[s],
                model.nodes[member.start.value],
                model.nodes[member.end.value],
            )
            if d < best_distance:
                best = k
                best_distance = d
        counts[best] += 1
    var area = complex.face_area(slab.face)
    for k in range(len(beams)):  # pragma: no branch
        ref member = model.members[beams[k]]
        var length = model.nodes[member.start.value].distance_to(
            model.nodes[member.end.value]
        )
        var share = area * Float64(counts[k]) / Float64(len(samples)) / length
        model.add_line_load(
            dead, MemberId(beams[k]), UZ, LineLoad64(-slab.dead * share)
        )
        model.add_line_load(
            live, MemberId(beams[k]), UZ, LineLoad64(-slab.live * share)
        )


def structural_view(
    building: Building, options: StructuralViewOptions
) raises -> StructuralView:
    """Return the structural model of a building.

    Args:
        building: The building. Its columns and beams form the frame.
        options: The tolerance, the slab model and the gravity.

    Returns:
        The model, its dead and live load cases, where each member and
        shell comes from, and notes on what the view dropped.

    Raises:
        Error: If the building or options are not valid, or a member
            or shell cannot be made.
    """
    building.validate()
    options.check()
    var tol = options.tolerance.to(METER)
    var g = options.gravity.to(METER_PER_SECOND_SQUARED)
    var model = StructuralModel()
    var notes = List[String]()
    var frames = List[Int]()
    var slabs = List[_Slab]()
    var walls = 0
    var ground = 0
    for i in range(len(building.elements)):
        ref e = building.elements[i]
        if e.kind == COLUMN or e.kind == BEAM:
            # Building.validate checked both fields before any model mutation.
            frames.append(i)
            _ = _node_at(model, e.start, tol)
            _ = _node_at(model, e.end, tol)
        elif e.kind == WALL:
            walls += 1
        elif building.topology.face_level[e.faces[0].value] == 0:
            ground += 1
        else:
            slabs.append(_slab(building, i, g))
    notes.append(
        String(walls, " walls are not structural in this view and add no load.")
    )
    notes.append(String(len(building.openings), " openings are ignored."))
    notes.append(
        String(ground, " ground slabs bear on the ground and are dropped.")
    )
    # Shell corners become nodes before the members, so a beam is split
    # where a shell corner lies on it.
    var corners = List[Vec3d]()
    var owner = List[Int]()
    for s in range(len(slabs) if options.shell_divisions > 0 else 0):
        var triangles = _mesh(
            building.topology.complex.face_points(slabs[s].face),
            options.shell_divisions,
        )
        for k in range(len(triangles)):  # pragma: no branch
            corners.append(triangles[k])
            _ = _node_at(model, triangles[k], tol)
        for _ in range(len(triangles) // 3):  # pragma: no branch
            owner.append(s)
    var member_element = List[ElementId]()
    var lowest = Float64.MAX
    for f in range(len(frames)):
        ref e = building.elements[frames[f]]
        if e.kind == COLUMN:
            lowest = min(lowest, e.start.z)
        var a = e.start
        var d = e.end - e.start
        var length = d.length()
        var along = List[Float64]()
        var nodes = List[NodeId]()
        along.append(0)
        nodes.append(_node_at(model, e.start, tol))
        for n in range(len(model.nodes)):  # pragma: no branch
            var p = model.nodes[n]
            var s = (p - a).dot(d) / length
            var gap = (p - (a + d * (s / length))).length()
            if s > tol and s < length - tol and gap <= tol:
                # Insert in order along the member.
                var k = len(along)
                along.append(s)
                nodes.append(NodeId(n))
                while along[k - 1] > s:
                    along[k] = along[k - 1]
                    nodes[k] = nodes[k - 1]
                    k -= 1
                along[k] = s
                nodes[k] = NodeId(n)
        nodes.append(_node_at(model, e.end, tol))
        var material = building.materials[e.material.value().value].copy()
        for k in range(len(nodes) - 1):  # pragma: no branch
            _ = model.add_member(
                nodes[k],
                nodes[k + 1],
                e.section.value(),
                material,
                Vec3d(0, 0, 1),
            )
            member_element.append(ElementId(frames[f]))
    var bases = 0
    for f in range(len(frames)):
        ref e = building.elements[frames[f]]
        if e.kind == COLUMN and abs(e.start.z - lowest) <= tol:
            model.fix(_node_at(model, e.start, tol))
            bases += 1
    notes.append(String(bases, " column bases are fixed."))
    var dead = model.add_load_case("dead")
    var live = model.add_load_case("live")
    model.add_self_weight(dead, options.gravity)
    var shell_element = List[ElementId]()
    for k in range(len(owner)):
        ref slab = slabs[owner[k]]
        var shell = model.add_shell(
            _node_at(model, corners[3 * k], tol),
            _node_at(model, corners[3 * k + 1], tol),
            _node_at(model, corners[3 * k + 2], tol),
            Length64(slab.thickness),
            slab.material,
        )
        # A positive pressure pushes against the normal, so the sign of
        # the normal's z keeps the load downward.
        var up = model.shell_element(shell).axes.z.z
        model.add_pressure(live, shell, Pressure64(slab.live * up))
        shell_element.append(ElementId(slab.element))
    for s in range(len(slabs) if options.shell_divisions == 0 else 0):
        _tributary(model, building, slabs[s], dead, live, tol, notes)
    return StructuralView(
        model^, dead, live, member_element^, shell_element^, notes^
    )
