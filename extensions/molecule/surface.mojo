# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Accessible areas and surface meshes of a molecule.

Each atom is a sphere of its van der Waals radius, from Bondi. A probe
of radius `probe` rolls over the spheres. The solvent accessible surface
is where the probe's center can go: each sphere grows by the probe.
A probe of zero gives the van der Waals surface.

`accessible_areas` uses the method of Shrake and Rupley. It puts points
on each grown sphere by the golden-section spiral. A point is accessible
when no other grown sphere holds it. The area of an atom is the area of
its grown sphere times the fraction of accessible points.

`molecular_surface` samples the distance to the nearest grown sphere on
a grid and meshes its zero set by marching tetrahedra. Each vertex takes
the CPK color of the atom whose sphere it lies on. The mesh is the
accessible surface, not the solvent excluded surface.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.chemistry.quantities import ANGSTROM
from extensions.humanoid.skeleton.isosurface import SampleGrid, mesh_samples
from extensions.molecule.ids import ModelId
from extensions.molecule.structure import Structure
from extensions.sdf.vector import V3, distance, v3
from loaders.pdb import cpk_color
from math.vector3 import Vector3
from render.srgb import srgb_to_linear
from std.math import cos, floor, isfinite, max, min, pi, sin, sqrt
from units.si import Area64, Length64, METER, SQUARE_METER

# The most grid points one surface can sample.
comptime MAX_SURFACE_POINTS = 16777216


def vdw_radius(element: String) -> Length64:
    """Return the van der Waals radius of an element, from Bondi.

    Args:
        element: The element symbol, in any case.

    Returns:
        The radius. An element that the table does not hold gets 1.8
        angstroms.
    """
    var upper = element.upper()
    var symbols: List[String] = [
        "H",
        "C",
        "N",
        "O",
        "F",
        "P",
        "S",
        "CL",
        "SE",
        "BR",
        "I",
    ]
    var radii: List[Float64] = [
        1.2,
        1.7,
        1.55,
        1.52,
        1.47,
        1.8,
        1.8,
        1.75,
        1.9,
        1.85,
        1.98,
    ]
    for index in range(len(symbols)):  # pragma: no branch
        if symbols[index] == upper:
            return Length64(radii[index], ANGSTROM)
    return Length64(1.8, ANGSTROM)


def sphere_points(count: Int) raises -> List[V3]:
    """Return points spread evenly on the unit sphere.

    Point `k` has `z = 1 - (2k + 1) / count` and turns by the golden
    angle from the point before.

    Args:
        count: The number of points, from 1 to 10000.

    Returns:
        The points.

    Raises:
        Error: If `count` is out of range.
    """
    if count < 1 or count > 10000:
        raise Error("A sphere takes from 1 to 10000 points")
    var golden = pi * (3.0 - sqrt(5.0))
    var out = List[V3]()
    for k in range(count):  # pragma: no branch
        var z = 1.0 - (2.0 * Float64(k) + 1.0) / Float64(count)
        var r = sqrt(max(1.0 - z * z, 0.0))
        var angle = golden * Float64(k)
        out.append(v3(r * cos(angle), r * sin(angle), z))
    return out^


def _axis(value: Float64, low: Float64, size: Float64, count: Int) -> Int:
    """Return the cell of a coordinate, held inside the grid."""
    var cell = Int(floor((value - low) / size))
    return min(max(cell, 0), count - 1)


struct _Cells(Movable):
    """The atoms of a model sorted into cubic cells."""

    var low: V3
    var size: Float64
    var nx: Int
    var ny: Int
    var nz: Int
    var start: List[Int]
    var atoms: List[Int]

    def __init__(out self, centers: List[V3], size: Float64):
        var low = centers[0]
        var high = centers[0]
        for c in centers:  # pragma: no branch
            low = v3(min(low.x, c.x), min(low.y, c.y), min(low.z, c.z))
            high = v3(max(high.x, c.x), max(high.y, c.y), max(high.z, c.z))
        var nx = Int((high.x - low.x) / size) + 1
        var ny = Int((high.y - low.y) / size) + 1
        var nz = Int((high.z - low.z) / size) + 1
        var cells = List[Int]()
        for c in centers:  # pragma: no branch
            var i = _axis(c.x, low.x, size, nx)
            var j = _axis(c.y, low.y, size, ny)
            var k = _axis(c.z, low.z, size, nz)
            cells.append(i + nx * (j + ny * k))
        var count = nx * ny * nz
        var start = List[Int](length=count + 1, fill=0)
        for cell in cells:  # pragma: no branch
            start[cell + 1] += 1
        for index in range(count):  # pragma: no branch
            start[index + 1] += start[index]
        var fill = start.copy()
        var atoms = List[Int](length=len(centers), fill=0)
        for index in range(len(centers)):  # pragma: no branch
            atoms[fill[cells[index]]] = index
            fill[cells[index]] += 1
        self.low = low
        self.size = size
        self.nx = nx
        self.ny = ny
        self.nz = nz
        self.start = start^
        self.atoms = atoms^

    def near(self, p: V3) -> List[Int]:
        """Return the atoms in the 27 cells around a point."""
        var i = _axis(p.x, self.low.x, self.size, self.nx)
        var j = _axis(p.y, self.low.y, self.size, self.ny)
        var k = _axis(p.z, self.low.z, self.size, self.nz)
        var out = List[Int]()
        for z in range(max(k - 1, 0), min(k + 2, self.nz)):  # pragma: no branch
            for y in range(
                max(j - 1, 0), min(j + 2, self.ny)
            ):  # pragma: no branch
                for x in range(
                    max(i - 1, 0), min(i + 2, self.nx)
                ):  # pragma: no branch
                    var cell = x + self.nx * (y + self.ny * z)
                    for at in range(self.start[cell], self.start[cell + 1]):
                        out.append(self.atoms[at])
        return out^


def _require_probe(probe: Length64) raises:
    """Refuse a probe radius that is negative or not finite."""
    var meters = probe.to(METER)
    if not (meters >= 0) or not isfinite(meters):
        raise Error("A probe radius must be zero or more and finite")


def _grown(
    structure: Structure, first: Int, count: Int, probe: Length64
) -> Tuple[List[V3], List[Float64]]:
    """Return the centers and the grown radii of a run of atoms, in meters."""
    var centers = List[V3]()
    var radii = List[Float64]()
    for index in range(first, first + count):  # pragma: no branch
        ref atom = structure.atoms[index]
        centers.append(atom.position)
        radii.append(vdw_radius(atom.element).to(METER) + probe.to(METER))
    return (centers^, radii^)


def accessible_areas(
    structure: Structure, model: ModelId, probe: Length64, points: Int
) raises -> List[Area64]:
    """Return the solvent accessible area of each atom of a model.

    Args:
        structure: The structure.
        model: The model.
        probe: The probe radius. 1.4 angstroms is a water molecule.
        points: The points on each sphere, from 1 to 10000. A few
            hundred give a few percent.

    Returns:
        One area for each atom of the model, in the model's atom order.

    Raises:
        Error: If the model id names no model, the probe is negative or
            not finite, or `points` is out of range.
    """
    _require_probe(probe)
    var unit = sphere_points(points)
    var span = structure.model_atoms(model)
    var grown = _grown(structure, span[0], span[1], probe)
    ref centers = grown[0]
    ref radii = grown[1]
    var largest = 0.0
    for r in radii:  # pragma: no branch
        largest = max(largest, r)
    var cells = _Cells(centers, 2.0 * largest)
    var out = List[Area64]()
    for a in range(len(centers)):  # pragma: no branch
        var neighbors = List[Int]()
        for b in cells.near(centers[a]):  # pragma: no branch
            var reach = radii[a] + radii[b]
            if b != a and distance(centers[a], centers[b]) < reach:
                neighbors.append(b)
        var open = 0
        for u in unit:  # pragma: no branch
            var p = centers[a] + u * radii[a]
            var buried = False
            for b in neighbors:
                if distance(p, centers[b]) < radii[b]:
                    buried = True
                    break
            if not buried:
                open += 1
        var sphere = 4.0 * pi * radii[a] * radii[a]
        out.append(
            Area64(sphere * Float64(open) / Float64(points), SQUARE_METER)
        )
    return out^


def _owner_colors(
    positions: List[Float32],
    owner: List[Int],
    low: V3,
    step: Float64,
    px: Int,
    py: Int,
    structure: Structure,
    first: Int,
) -> List[Float32]:
    """Return the linear CPK color of the atom nearest each vertex's grid
    point."""
    var colors = List[Float32]()
    for v in range(len(positions) // 3):  # pragma: no branch
        var i = Int((Float64(positions[3 * v]) - low.x) / step + 0.5)
        var j = Int((Float64(positions[3 * v + 1]) - low.y) / step + 0.5)
        var k = Int((Float64(positions[3 * v + 2]) - low.z) / step + 0.5)
        # A vertex lies within one step of its atom's sphere, and each atom
        # writes every grid point within two steps of its sphere, so the
        # nearest grid point always has an owner.
        var a = owner[i + px * (j + py * k)]
        var rgb = cpk_color(structure.atoms[first + a].element.lower())
        if rgb[0] < 0:
            rgb = (200, 200, 200)
        colors.append(srgb_to_linear(Float32(rgb[0]) / 255))
        colors.append(srgb_to_linear(Float32(rgb[1]) / 255))
        colors.append(srgb_to_linear(Float32(rgb[2]) / 255))
    return colors^


def molecular_surface(
    structure: Structure, model: ModelId, probe: Length64, spacing: Length64
) raises -> BufferGeometry:
    """Return the accessible surface of a model as a colored mesh.

    Args:
        structure: The structure.
        model: The model.
        probe: The probe radius. Zero gives the van der Waals surface.
        spacing: The grid step, such as 0.5 angstroms.

    Returns:
        A triangle mesh in meters with `position`, `normal`, `uv` and
        `color` attributes. The colors are linear CPK colors.

    Raises:
        Error: If the model id names no model, the probe is negative or
            not finite, the spacing is not positive and finite, or the
            grid would hold more than 2^24 points.
    """
    _require_probe(probe)
    var step = spacing.to(METER)
    if not (step > 0) or not isfinite(step):
        raise Error("A surface spacing must be positive and finite")
    var span = structure.model_atoms(model)
    var grown = _grown(structure, span[0], span[1], probe)
    ref centers = grown[0]
    ref radii = grown[1]
    var bounds = structure.bounds(model)
    var largest = 0.0
    for r in radii:  # pragma: no branch
        largest = max(largest, r)
    var margin = largest + 2.0 * step
    var low = bounds[0] - v3(margin, margin, margin)
    var high = bounds[1] + v3(margin, margin, margin)
    var px = Int((high.x - low.x) / step) + 2
    var py = Int((high.y - low.y) / step) + 2
    var pz = Int((high.z - low.z) / step) + 2
    if px > MAX_SURFACE_POINTS // py // pz:
        raise Error("A surface grid can hold at most 2^24 points")
    var far = 2.0 * step
    var field = List[Float32](length=px * py * pz, fill=Float32(far))
    var owner = List[Int](length=px * py * pz, fill=-1)
    for a in range(len(centers)):  # pragma: no branch
        var c = centers[a]
        var reach = radii[a] + far
        var i0 = max(Int((c.x - reach - low.x) / step), 0)
        var j0 = max(Int((c.y - reach - low.y) / step), 0)
        var k0 = max(Int((c.z - reach - low.z) / step), 0)
        var i1 = min(Int((c.x + reach - low.x) / step) + 1, px - 1)
        var j1 = min(Int((c.y + reach - low.y) / step) + 1, py - 1)
        var k1 = min(Int((c.z + reach - low.z) / step) + 1, pz - 1)
        for k in range(k0, k1 + 1):  # pragma: no branch
            for j in range(j0, j1 + 1):  # pragma: no branch
                for i in range(i0, i1 + 1):  # pragma: no branch
                    var p = low + v3(
                        Float64(i) * step, Float64(j) * step, Float64(k) * step
                    )
                    var d = distance(p, c) - radii[a]
                    var at = i + px * (j + py * k)
                    if d < Float64(field[at]):
                        field[at] = Float32(d)
                        owner[at] = a
    var grid = SampleGrid(
        px - 1,
        py - 1,
        pz - 1,
        Float32(step),
        Float32(step),
        Float32(step),
        px,
        py,
        pz,
        Float32(step * Float64(py - 1)),
    )
    var corner = Vector3(Float32(low.x), Float32(low.y), Float32(low.z))
    var geometry = mesh_samples(field, corner, grid, "molecular surface")
    var colors = _owner_colors(
        geometry.attribute_view(String(POSITION)).data,
        owner,
        low,
        step,
        px,
        py,
        structure,
        span[0],
    )
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^
