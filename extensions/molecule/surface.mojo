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
accessible surface.

`excluded_surface` gives the solvent excluded surface, which molecular
viewers show by default: the surface where the probe touches the atoms.
An exact Euclidean distance transform of the grid finds it, as EDTSurf
does.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.chemistry.quantities import ANGSTROM
from extensions.humanoid.skeleton.isosurface import SampleGrid, mesh_samples
from extensions.molecule.ids import ModelId
from extensions.molecule.structure import Structure
from extensions.sdf.vector import V3, distance, dot, length, v3
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


struct _SasGrid(Movable):
    """The grown spheres of a model sampled on a grid."""

    var field: List[Float32]
    """The distance to the nearest grown sphere, held at two steps."""
    var owner: List[Int]
    """The atom of that sphere, from the model's first atom, or -1."""
    var low: V3
    var step: Float64
    var px: Int
    var py: Int
    var pz: Int
    var first: Int

    def __init__(
        out self,
        var field: List[Float32],
        var owner: List[Int],
        low: V3,
        step: Float64,
        px: Int,
        py: Int,
        pz: Int,
        first: Int,
    ):
        self.field = field^
        self.owner = owner^
        self.low = low
        self.step = step
        self.px = px
        self.py = py
        self.pz = pz
        self.first = first


def _sas_grid(
    structure: Structure, model: ModelId, probe: Length64, spacing: Length64
) raises -> _SasGrid:
    """Sample the distance to the grown spheres of a model on a grid."""
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
    return _SasGrid(field^, owner^, low, step, px, py, pz, span[0])


def _mesh(
    values: List[Float32], grid: _SasGrid, structure: Structure, name: String
) raises -> BufferGeometry:
    """Mesh the zero set of grid values and color it by the nearest atom."""
    var step = Float32(grid.step)
    var sample = SampleGrid(
        grid.px - 1,
        grid.py - 1,
        grid.pz - 1,
        step,
        step,
        step,
        grid.px,
        grid.py,
        grid.pz,
        step * Float32(grid.py - 1),
    )
    var corner = Vector3(
        Float32(grid.low.x), Float32(grid.low.y), Float32(grid.low.z)
    )
    var geometry = mesh_samples(values, corner, sample, name)
    var colors = _owner_colors(
        geometry.attribute_view(String(POSITION)).data,
        grid.owner,
        grid.low,
        grid.step,
        grid.px,
        grid.py,
        structure,
        grid.first,
    )
    geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^


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
    var grid = _sas_grid(structure, model, probe, spacing)
    return _mesh(grid.field, grid, structure, "molecular surface")


# A squared distance, in steps, larger than any on a grid.
comptime _FAR_SQUARE = 1.0e18


def _meet(f: List[Float64], p: Int, q: Int) -> Float64:
    """Return where the parabolas of positions `p` and `q` cross."""
    var a = f[q] + Float64(q * q)
    var b = f[p] + Float64(p * p)
    return (a - b) / Float64(2 * q - 2 * p)


def _pass(
    mut d: List[Float64],
    mut feature: List[Int],
    start: Int,
    stride: Int,
    n: Int,
    mut v: List[Int],
    mut z: List[Float64],
    mut f: List[Float64],
    mut g: List[Int],
):
    """Run the one-dimensional transform of Felzenszwalb and Huttenlocher
    along one line, keeping the nearest seed of each point."""
    for q in range(n):  # pragma: no branch
        f[q] = d[start + q * stride]
        g[q] = feature[start + q * stride]
    var k = 0
    v[0] = 0
    z[0] = -_FAR_SQUARE
    z[1] = _FAR_SQUARE
    for q in range(1, n):  # pragma: no branch
        var s = _meet(f, v[k], q)
        while s <= z[k]:
            k -= 1
            s = _meet(f, v[k], q)
        k += 1
        v[k] = q
        z[k] = s
        z[k + 1] = _FAR_SQUARE
    k = 0
    for q in range(n):  # pragma: no branch
        while z[k + 1] < Float64(q):
            k += 1
        var p = v[k]
        d[start + q * stride] = Float64((q - p) * (q - p)) + f[p]
        feature[start + q * stride] = g[p]


def distance_transform(
    seeds: List[Bool], px: Int, py: Int, pz: Int
) raises -> Tuple[List[Float64], List[Int]]:
    """Return the exact Euclidean distance from each grid point to a seed.

    This is the separable transform of Felzenszwalb and Huttenlocher, run
    along x, then y, then z. It also keeps the nearest seed.

    Args:
        seeds: One flag per point, `i` fastest.
        px: Points along x. At least one.
        py: Points along y. At least one.
        pz: Points along z. At least one.

    Returns:
        The squared distance to the nearest seed, in grid steps, and the
        index of that seed. A grid with no seed gives distances of 1e18
        or more and indexes of -1.

    Raises:
        Error: If a size is not positive, or the flags do not fill the
            grid.
    """
    if px < 1 or py < 1 or pz < 1:
        raise Error("A distance transform needs at least one point a side")
    if len(seeds) != px * py * pz:
        raise Error("The seeds must fill the grid")
    var count = px * py * pz
    var d = List[Float64](length=count, fill=_FAR_SQUARE)
    var feature = List[Int](length=count, fill=-1)
    for index in range(count):  # pragma: no branch
        if seeds[index]:
            d[index] = 0
            feature[index] = index
    var longest = max(px, max(py, pz))
    var v = List[Int](length=longest, fill=0)
    var z = List[Float64](length=longest + 1, fill=0)
    var f = List[Float64](length=longest, fill=0)
    var g = List[Int](length=longest, fill=0)
    for k in range(pz):  # pragma: no branch
        for j in range(py):  # pragma: no branch
            _pass(d, feature, px * (j + py * k), 1, px, v, z, f, g)
    for k in range(pz):  # pragma: no branch
        for i in range(px):  # pragma: no branch
            _pass(d, feature, i + px * py * k, px, py, v, z, f, g)
    for j in range(py):  # pragma: no branch
        for i in range(px):  # pragma: no branch
            _pass(d, feature, i + px * j, px * py, pz, v, z, f, g)
    return (d^, feature^)


def excluded_surface(
    structure: Structure, model: ModelId, probe: Length64, spacing: Length64
) raises -> BufferGeometry:
    """Return the solvent excluded surface of a model as a colored mesh.

    The excluded surface is where a rolling probe touches the atoms. It
    follows each atom's van der Waals sphere where the probe touches one
    atom, and fills each crevice that the probe is too large to enter
    with a smooth, concave patch.

    The probe's center can reach the points outside every grown sphere.
    The surface is the set of points one probe radius from that region.
    The distance to that region is at least the depth into the deepest
    grown sphere. Where the point straight out from that sphere's center
    is outside every other sphere, the distance is that depth, exactly.
    In a crevice between two spheres, the distance to the circle where
    they meet is exact when no third sphere holds the circle's nearest
    point. Elsewhere a distance transform on the grid gives the distance
    to the nearest reachable grid point, less that point's distance to
    the spheres: an upper bound within one step of the true distance.

    Args:
        structure: The structure.
        model: The model.
        probe: The probe radius, such as 1.4 angstroms for water. Zero
            gives the van der Waals surface.
        spacing: The grid step, such as 0.4 angstroms.

    Returns:
        A triangle mesh in meters with `position`, `normal`, `uv` and
        `color` attributes. Each vertex takes the linear CPK color of the
        atom nearest it.

    Raises:
        Error: If the model id names no model, the probe is negative or
            not finite, the spacing is not positive and finite, or the
            grid would hold more than 2^24 points.
    """
    var grid = _sas_grid(structure, model, probe, spacing)
    var span = structure.model_atoms(model)
    var grown = _grown(structure, span[0], span[1], probe)
    ref centers = grown[0]
    ref radii = grown[1]
    var largest = 0.0
    for r in radii:  # pragma: no branch
        largest = max(largest, r)
    var cells = _Cells(centers, 2.0 * largest)
    var count = grid.px * grid.py * grid.pz
    var reachable = List[Bool](length=count, fill=False)
    for index in range(count):  # pragma: no branch
        reachable[index] = grid.field[index] >= 0
    var transform = distance_transform(reachable, grid.px, grid.py, grid.pz)
    ref squared = transform[0]
    ref nearest = transform[1]
    var radius = probe.to(METER)
    var values = List[Float32](length=count, fill=0)
    for index in range(count):  # pragma: no branch
        var depth = Float64(grid.field[index])
        if depth >= 0:
            values[index] = Float32(radius + depth)
            continue
        # The distance to the reachable region is at least the depth into
        # the deepest sphere, and at most the grid bound.
        var reach = sqrt(squared[index]) * grid.step
        var gap = max(reach - Float64(grid.field[nearest[index]]), -depth)
        var i = index % grid.px
        var j = (index // grid.px) % grid.py
        var k = index // (grid.px * grid.py)
        var p = grid.low + v3(
            Float64(i) * grid.step,
            Float64(j) * grid.step,
            Float64(k) * grid.step,
        )
        # Deeper points are inside the surface whatever their distance.
        if -depth <= radius + 2.0 * grid.step:
            gap = _refine(
                p, grid.owner[index], -depth, gap, centers, radii, cells
            )
        values[index] = Float32(radius - gap)
    return _mesh(values, grid, structure, "excluded surface")


def _refine(
    p: V3,
    deepest: Int,
    low: Float64,
    high: Float64,
    centers: List[V3],
    radii: List[Float64],
    cells: _Cells,
) -> Float64:
    """Return a smaller upper bound on the distance from `p` to the region
    the probe's center can reach, from exact candidates."""
    if _exits(p, deepest, centers, radii, cells):
        return low
    var best = high
    for other in cells.near(p):  # pragma: no branch
        if other != deepest and distance(p, centers[other]) < radii[other]:
            best = min(best, _crease(p, deepest, other, centers, radii, cells))
    return best


def _crease(
    p: V3,
    a: Int,
    b: Int,
    centers: List[V3],
    radii: List[Float64],
    cells: _Cells,
) -> Float64:
    """Return the distance from `p` to the circle where grown spheres `a` and
    `b` meet, when the nearest point of the circle is outside every other
    grown sphere, and 1e18 when it is not."""
    var axis = centers[b] - centers[a]
    var d = length(axis)
    var along = (d * d + radii[a] * radii[a] - radii[b] * radii[b]) / (2.0 * d)
    var rho2 = radii[a] * radii[a] - along * along
    var n = axis * (1.0 / d)
    var w = p - centers[a] - n * along
    var side = w - n * dot(w, n)
    var size = length(side)
    # The spheres meet in a circle, and `p` is off its axis.
    if not (rho2 > 0) or not (size > 0):
        return _FAR_SQUARE
    var e = centers[a] + n * along + side * (sqrt(rho2) / size)
    for c in cells.near(e):  # pragma: no branch
        if c != a and c != b and distance(e, centers[c]) < radii[c]:
            return _FAR_SQUARE
    return distance(p, e)


def _exits(
    p: V3, atom: Int, centers: List[V3], radii: List[Float64], cells: _Cells
) -> Bool:
    """Return whether the point straight out from an atom's center through
    `p`, on its grown sphere, is outside every other grown sphere."""
    var outward = p - centers[atom]
    var size = length(outward)
    if size == 0:
        return False
    var e = centers[atom] + outward * (radii[atom] / size)
    for b in cells.near(e):  # pragma: no branch
        if b != atom and distance(e, centers[b]) < radii[b]:
            return False
    return True
