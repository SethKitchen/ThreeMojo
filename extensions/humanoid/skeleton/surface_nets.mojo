# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A smooth, narrow-band surface-nets mesh of a skin's zero set.

Marching tetrahedra puts each vertex on a straight line between two
samples, which leaves a skin faceted and lumpy where the field curves
between them, and it makes many thin triangles. This mesher puts one
vertex in each cell the surface crosses, then walks it onto the true
surface along the field's gradient. The normal is that gradient, so
the shading is as smooth as the field. Each crossed edge of the grid
makes one quad, split along its shorter diagonal.

Only the blocks of the grid near the surface are sampled finely: a
coarse pass finds them first. A distance field changes by no more than
the distance moved, so a block whose corners all lie farther from the
surface than the block is wide holds none of it.

Texture coordinates are cylindrical around y: `u` around, from the back
through one half straight ahead, and `v` up. A triangle that crosses
the seam at the back
gets its own copies of the corners, with `u` past one, so the texture
does not smear across it.

`detail` sets how many cells run along the long axis, times
`REFINE`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from extensions.humanoid.skeleton.field import DistanceField, cross
from extensions.humanoid.skeleton.isosurface import check_detail
from math.vector3 import Vector3
from render.tasks import TaskGroup
from std.collections import Dict
from std.sys import num_logical_cores
from std.math import atan2, ceil, max, min, pi, sqrt

# Fine cells per unit of `detail` along the long axis.
comptime REFINE = 4
# Fine cells along each side of a coarse block.
comptime BLOCK = 4
# How many Newton steps walk a vertex onto the surface.
comptime PROJECT_STEPS = 3
# A value no sample takes: "not sampled".
comptime UNSAMPLED = Float32(3.0e38)


@fieldwise_init
struct _Grid(ImplicitlyCopyable):
    """The fine lattice: cell counts, sizes and the corner."""

    var low: Vector3
    var cell: Float32
    var nx: Int
    var ny: Int
    var nz: Int

    def point(self, i: Int, j: Int, k: Int) -> Vector3:
        """Return lattice point `(i, j, k)`."""
        return Vector3(
            self.low.x + Float32(i) * self.cell,
            self.low.y + Float32(j) * self.cell,
            self.low.z + Float32(k) * self.cell,
        )

    def index(self, i: Int, j: Int, k: Int) -> Int:
        """Return where lattice point `(i, j, k)` is stored."""
        return i + (self.nx + 1) * (j + (self.ny + 1) * k)

    def cell_index(self, i: Int, j: Int, k: Int) -> Int:
        """Return where cell `(i, j, k)` is stored."""
        return i + self.nx * (j + self.ny * k)


def _blocks(span: Float32, cell: Float32) -> Int:
    """Return how many whole blocks hold `span` at `cell`, at least one."""
    return max(1, Int(ceil(span / (cell * Float32(BLOCK)))))


def surface_gradient[
    F: DistanceField
](field: F, point: Vector3, step: Float32) -> Vector3:
    """Return the field's gradient at `point`, not normalized.

    It takes four samples at the corners of a tetrahedron, which costs
    less than the six of central differences and is as accurate.

    Args:
        field: The implicit solid.
        point: Where to take the gradient, in meters.
        step: How far each sample lies from `point`, in meters.

    Returns:
        The gradient: about a unit vector where the field is a distance.
    """
    var a = field.distance(
        Vector3(point.x + step, point.y - step, point.z - step)
    )
    var b = field.distance(
        Vector3(point.x - step, point.y - step, point.z + step)
    )
    var c = field.distance(
        Vector3(point.x - step, point.y + step, point.z - step)
    )
    var d = field.distance(
        Vector3(point.x + step, point.y + step, point.z + step)
    )
    var scale = Float32(0.25) / step
    return Vector3(
        (a - b - c + d) * scale,
        (-a - b + c + d) * scale,
        (-a + b - c + d) * scale,
    )


def _crossing(a: Vector3, b: Vector3, da: Float32, db: Float32) -> Vector3:
    """Return where the field crosses zero between two samples."""
    var t = da / (da - db)
    return a + (b - a) * t


def _u_of(point: Vector3) -> Float32:
    """Return the cylindrical `u` of a point, 0 through 1.

    `u` is one half straight ahead, so the seam falls at the back.
    """
    return atan2(point.x, point.z) / (pi * Float32(2)) + Float32(0.5)


def _near(
    values: List[Float32], grid: _Grid, i: Int, j: Int, k: Int, reach: Float32
) -> Bool:
    """Return True if a corner of block `(i, j, k)` lies within `reach`."""
    for c in range(8):  # pragma: no branch
        var ci = (i + (c & 1)) * BLOCK
        var cj = (j + ((c >> 1) & 1)) * BLOCK
        var ck = (k + ((c >> 2) & 1)) * BLOCK
        if abs(values[grid.index(ci, cj, ck)]) < reach:
            return True
    return False


def _corner(grid: _Grid, i: Int, j: Int, k: Int, c: Int) -> Vector3:
    """Return corner `c` of cell `(i, j, k)`: bit 0 is x, 1 is y, 2 is z."""
    return grid.point(i + (c & 1), j + ((c >> 1) & 1), k + (c >> 2))


# The cell's twelve edges, as pairs of corners: bit 0 of a corner is x,
# bit 1 is y and bit 2 is z.
comptime _EDGES = SIMD[DType.int8, 32](
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    0,
    2,
    1,
    3,
    4,
    6,
    5,
    7,
    0,
    4,
    1,
    5,
    2,
    6,
    3,
    7,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
)


def _cell_guess(
    values: List[Float32], grid: _Grid, i: Int, j: Int, k: Int
) -> Vector3:
    """Return the mean of the crossings on a crossed cell's edges."""
    var corner = SIMD[DType.float32, 8](0)
    for c in range(8):  # pragma: no branch
        corner[c] = values[
            grid.index(i + (c & 1), j + ((c >> 1) & 1), k + (c >> 2))
        ]
    var sum = Vector3(0, 0, 0)
    var crossings = 0
    for edge in range(12):  # pragma: no branch
        var c = Int(_EDGES[edge * 2])
        var other = Int(_EDGES[edge * 2 + 1])
        if (corner[c] < 0) == (corner[other] < 0):
            continue
        sum = sum + _crossing(
            _corner(grid, i, j, k, c),
            _corner(grid, i, j, k, other),
            corner[c],
            corner[other],
        )
        crossings += 1
    return sum * (Float32(1) / Float32(crossings))


def project_to_surface[
    F: DistanceField
](
    field: F, start: Vector3, low: Vector3, high: Vector3, step: Float32
) -> Vector3:
    """Walk a point onto the field's surface along its gradient.

    Each step is one Newton step. The point is held inside a box, so a
    field that is not a true distance cannot throw it far. Where the
    gradient vanishes the walk stops.

    Args:
        field: The implicit solid.
        start: Where to start, in meters.
        low: The box's minimum corner.
        high: The box's maximum corner.
        step: The gradient's sample distance, in meters.

    Returns:
        The point on the surface, or as near it as the box allows.
    """
    var p = start
    for _ in range(PROJECT_STEPS):  # pragma: no branch
        var gradient = surface_gradient(field, p, step)
        var g2 = gradient.dot(gradient)
        if g2 < Float32(1e-12):
            break
        p = p - gradient * (field.distance(p) / g2)
        p = Vector3(
            min(max(p.x, low.x), high.x),
            min(max(p.y, low.y), high.y),
            min(max(p.z, low.z), high.z),
        )
    return p


def _edge_quad(
    values: List[Float32],
    cells: List[Int32],
    grid: _Grid,
    i: Int,
    j: Int,
    k: Int,
    axis: Int,
) -> SIMD[DType.int64, 4]:
    """Return the four vertices round the edge from `(i, j, k)` along
    `axis`, in order round it, or minus ones if it makes no quad.

    The edge must end inside the lattice."""
    var none = SIMD[DType.int64, 4](-1)
    var step = SIMD[DType.int64, 4](0)
    step[axis] = 1
    var here = values[grid.index(i, j, k)]
    if here == UNSAMPLED:
        return none
    var there = values[
        grid.index(i + Int(step[0]), j + Int(step[1]), k + Int(step[2]))
    ]
    if there == UNSAMPLED:
        return none
    if (here < 0) == (there < 0):
        return none
    # The two axes across the edge, and the four cells round it in
    # order: (0, 0), (1, 0), (1, 1), (0, 1).
    var first = (axis + 1) % 3
    var second = (axis + 2) % 3
    var turns = SIMD[DType.int64, 8](0, 0, 1, 0, 1, 1, 0, 1)
    var q = SIMD[DType.int64, 4](-1)
    for n in range(4):  # pragma: no branch
        var at = SIMD[DType.int64, 4](Int64(i), Int64(j), Int64(k), 0)
        at[first] -= turns[n * 2]
        at[second] -= turns[n * 2 + 1]
        var v = cells[grid.cell_index(Int(at[0]), Int(at[1]), Int(at[2]))]
        if v < 0:
            return none
        q[n] = Int64(v)
    return q


async def _sample_task[
    F: DistanceField
](
    field: Pointer[F, ImmutAnyOrigin],
    grid: _Grid,
    values: MutPointer[Float32, MutAnyOrigin],
    blocks: MutPointer[Int, MutAnyOrigin],
    first: Int,
    past: Int,
    bx: Int,
    by: Int,
):
    """Sample every lattice point of a run of near blocks.

    Two blocks share the points on their common face. Both tasks write
    the same value there, so the order does not matter.

    Args:
        field: The implicit solid.
        grid: The fine lattice.
        values: The samples, written in place.
        blocks: The near blocks' indices.
        first: This task's first block in `blocks`.
        past: One past its last.
        bx: Blocks along x.
        by: Blocks along y.
    """
    for slot in range(first, past):  # pragma: no branch
        var block = blocks[unsafe_offset=slot]
        var i = block % bx
        var j = (block // bx) % by
        var k = block // (bx * by)
        var i0 = i * BLOCK
        var j0 = j * BLOCK
        var k0 = k * BLOCK
        for fk in range(k0, k0 + BLOCK + 1):  # pragma: no branch
            for fj in range(j0, j0 + BLOCK + 1):  # pragma: no branch
                for fi in range(i0, i0 + BLOCK + 1):  # pragma: no branch
                    var at = grid.index(fi, fj, fk)
                    if values[unsafe_offset=at] == UNSAMPLED:
                        values[unsafe_offset=at] = field[].distance(
                            grid.point(fi, fj, fk)
                        )


async def _vertex_task[
    F: DistanceField
](
    field: Pointer[F, ImmutAnyOrigin],
    grid: _Grid,
    values: Pointer[List[Float32], MutAnyOrigin],
    crossed: MutPointer[Int, MutAnyOrigin],
    positions: MutPointer[Float32, MutAnyOrigin],
    normals: MutPointer[Float32, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Place the vertex of each of a run of crossed cells.

    Args:
        field: The implicit solid.
        grid: The fine lattice.
        values: The samples.
        crossed: The crossed cells' indices.
        positions: Three floats per vertex, written in place.
        normals: Three floats per vertex, written in place.
        first: This task's first cell in `crossed`.
        past: One past its last.
    """
    var cell = grid.cell
    var step = cell * Float32(0.25)
    var half = Vector3(cell * 0.5, cell * 0.5, cell * 0.5)
    for slot in range(first, past):  # pragma: no branch
        var index = crossed[unsafe_offset=slot]
        var i = index % grid.nx
        var j = (index // grid.nx) % grid.ny
        var k = index // (grid.nx * grid.ny)
        var guess = _cell_guess(values[], grid, i, j, k)
        var p = project_to_surface(
            field[],
            guess,
            grid.point(i, j, k) - half,
            grid.point(i + 1, j + 1, k + 1) + half,
            step,
        )
        var normal = surface_gradient(field[], p, step)
        normal.normalize()
        positions[unsafe_offset=slot * 3] = p.x
        positions[unsafe_offset=slot * 3 + 1] = p.y
        positions[unsafe_offset=slot * 3 + 2] = p.z
        normals[unsafe_offset=slot * 3] = normal.x
        normals[unsafe_offset=slot * 3 + 1] = normal.y
        normals[unsafe_offset=slot * 3 + 2] = normal.z


def _crosses(
    values: List[Float32], grid: _Grid, i: Int, j: Int, k: Int
) -> Bool:
    """Return True if the surface crosses cell `(i, j, k)`."""
    var inside = 0
    for c in range(8):  # pragma: no branch
        if (
            values[grid.index(i + (c & 1), j + ((c >> 1) & 1), k + (c >> 2))]
            < 0
        ):
            inside += 1
    if inside == 0:
        return False
    return inside != 8


def mesh_surface[
    F: DistanceField
](
    field: F,
    low: Vector3,
    high: Vector3,
    detail: Int,
    name: String,
    workers: Int = 1,
    smoothing: Int = 1,
) raises -> BufferGeometry:
    """Return a smooth mesh of `field`'s zero set inside a box.

    The field is sampled and the vertices are placed on `workers`
    threads. The mesh is the same for any number of them.

    Args:
        field: The implicit solid.
        low: Minimum corner of the solid.
        high: Maximum corner of the solid.
        detail: Eight through sixty-four. `detail * REFINE` cells run
            along the box's y.
        name: Name used in the error text.
        workers: How many threads share the work. One by default; zero
            means one per logical core. The coverage run needs one: two
            threads' probes would interleave.
        smoothing: How many times each normal is averaged with its
            neighbors'. One by default; zero keeps the exact gradient.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If `detail` is out of range, or the field makes no
            surface in the box.
    """
    check_detail(detail, name)
    var threads = workers
    if threads < 1:
        threads = num_logical_cores()
    var span_y = high.y - low.y
    var cell = span_y / Float32(detail * REFINE)
    # Room round the solid, so its surface closes inside the grid.
    var pad = cell * Float32(2)
    var start = Vector3(low.x - pad, low.y - pad, low.z - pad)
    var bx = _blocks(high.x - low.x + 2 * pad, cell)
    var by = _blocks(span_y + 2 * pad, cell)
    var bz = _blocks(high.z - low.z + 2 * pad, cell)
    var grid = _Grid(start, cell, bx * BLOCK, by * BLOCK, bz * BLOCK)
    var total = (grid.nx + 1) * (grid.ny + 1) * (grid.nz + 1)
    var values = List[Float32](length=total, fill=UNSAMPLED)
    # The coarse pass: every block corner.
    for k in range(bz + 1):  # pragma: no branch
        for j in range(by + 1):  # pragma: no branch
            for i in range(bx + 1):  # pragma: no branch
                values[
                    grid.index(i * BLOCK, j * BLOCK, k * BLOCK)
                ] = field.distance(grid.point(i * BLOCK, j * BLOCK, k * BLOCK))
    # A block is near the surface if a corner lies within its
    # diagonal, with room for a field that is not an exact distance.
    var reach = Float32(BLOCK) * cell * Float32(2.2)
    var active = List[Bool](length=bx * by * bz, fill=False)
    var near = List[Int]()
    for k in range(bz):  # pragma: no branch
        for j in range(by):  # pragma: no branch
            for i in range(bx):  # pragma: no branch
                if _near(values, grid, i, j, k, reach):
                    active[i + bx * (j + by * k)] = True
                    near.append(i + bx * (j + by * k))
    var tasks = max(1, min(threads, len(near)))
    var samplers = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        samplers.create_task(
            _sample_task(
                Pointer(to=field).unsafe_origin_cast[ImmutAnyOrigin](),
                grid,
                values.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                near.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                task * len(near) // tasks,
                (task + 1) * len(near) // tasks,
                bx,
                by,
            )
        )
    samplers.wait()
    _ = len(near)
    # One vertex in each crossed cell, walked onto the surface.
    var cells = List[Int32](length=grid.nx * grid.ny * grid.nz, fill=-1)
    var crossed = List[Int]()
    for k in range(grid.nz):  # pragma: no branch
        for j in range(grid.ny):  # pragma: no branch
            for i in range(grid.nx):  # pragma: no branch
                if not active[
                    i // BLOCK + bx * (j // BLOCK + by * (k // BLOCK))
                ]:
                    continue
                if _crosses(values, grid, i, j, k):
                    cells[grid.cell_index(i, j, k)] = Int32(len(crossed))
                    crossed.append(grid.cell_index(i, j, k))
    var count = len(crossed)
    var positions = List[Float32](length=count * 3, fill=0)
    var normals = List[Float32](length=count * 3, fill=0)
    tasks = max(1, min(threads, count))
    var placers = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        placers.create_task(
            _vertex_task(
                Pointer(to=field).unsafe_origin_cast[ImmutAnyOrigin](),
                grid,
                Pointer(to=values).unsafe_origin_cast[MutAnyOrigin](),
                crossed.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                positions.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                normals.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                task * count // tasks,
                (task + 1) * count // tasks,
            )
        )
    placers.wait()
    _ = len(crossed)
    # One quad for each crossed edge, from the four cells round it.
    var indices = List[Int]()
    for k in range(1, grid.nz):  # pragma: no branch
        for j in range(1, grid.ny):  # pragma: no branch
            for i in range(1, grid.nx):  # pragma: no branch
                for axis in range(3):  # pragma: no branch
                    var q = _edge_quad(values, cells, grid, i, j, k, axis)
                    if q[0] >= 0:
                        _emit_quad(indices, positions, normals, q)
    if len(indices) == 0:
        raise Error("The " + name + " field produced no surface")
    _smooth_normals(normals, indices, smoothing)
    return finish_surface(positions^, normals^, indices^, low.y, span_y)


def _smooth_normals(
    mut normals: List[Float32], indices: List[Int], passes: Int
):
    """Average each normal with its neighbors' `passes` times.

    A field made of fitted sections can wave by a fraction of a
    millimeter between them; the exact gradient shows that as bands.
    One or two passes take the bands out and leave the forms.
    """
    var count = len(normals) // 3
    for _ in range(passes):
        var sums = normals.copy()
        var corner = 0
        while corner < len(indices):  # pragma: no branch
            for n in range(3):  # pragma: no branch
                var a = indices[corner + n]
                var b = indices[corner + (n + 1) % 3]
                for axis in range(3):  # pragma: no branch
                    sums[a * 3 + axis] += normals[b * 3 + axis]
            corner += 3
        for vertex in range(count):  # pragma: no branch
            var n = _vertex(sums, vertex)
            n.normalize()
            normals[vertex * 3] = n.x
            normals[vertex * 3 + 1] = n.y
            normals[vertex * 3 + 2] = n.z


def _vertex(positions: List[Float32], index: Int) -> Vector3:
    """Return vertex `index` of a flat position list."""
    return Vector3(
        positions[index * 3], positions[index * 3 + 1], positions[index * 3 + 2]
    )


def _emit_quad(
    mut indices: List[Int],
    positions: List[Float32],
    normals: List[Float32],
    q: SIMD[DType.int64, 4],
):
    """Append a quad as two triangles, split on its shorter diagonal and
    wound to face along the vertex normals."""
    var q0 = Int(q[0])
    var q1 = Int(q[1])
    var q2 = Int(q[2])
    var q3 = Int(q[3])
    var a = _vertex(positions, q0)
    var b = _vertex(positions, q1)
    var c = _vertex(positions, q2)
    var d = _vertex(positions, q3)
    var mean = (
        _vertex(normals, q0)
        + _vertex(normals, q1)
        + _vertex(normals, q2)
        + _vertex(normals, q3)
    )
    var ac = c - a
    var bd = d - b
    var face = cross(b - a, c - a) + cross(c - a, d - a)
    var flip = face.dot(mean) < 0
    var first: List[Int]
    if ac.dot(ac) <= bd.dot(bd):
        first = [q0, q1, q2, q0, q2, q3]
    else:
        first = [q0, q1, q3, q1, q2, q3]
    for t in range(2):  # pragma: no branch
        var i0 = first[t * 3]
        var i1 = first[t * 3 + 1]
        var i2 = first[t * 3 + 2]
        if flip:
            indices.append(i0)
            indices.append(i2)
            indices.append(i1)
        else:
            indices.append(i0)
            indices.append(i1)
            indices.append(i2)


def finish_surface(
    var positions: List[Float32],
    var normals: List[Float32],
    var indices: List[Int],
    base: Float32,
    span: Float32,
) raises -> BufferGeometry:
    """Add texture coordinates, split the seam, and build the geometry.

    `u` runs round the vertical axis, with its seam at the back; `v` is
    the height over `span` from `base`. A triangle across the seam gets
    copies of its corners.

    Args:
        positions: Three floats a vertex, in meters.
        normals: Three floats a vertex.
        indices: Three vertices a triangle.
        base: The height where `v` is zero, in meters.
        span: The height over which `v` runs to one, in meters.

    Returns:
        A geometry with `position`, `normal` and `uv`.

    Raises:
        Error: If the geometry refuses the attributes.
    """
    var uvs = List[Float32]()
    var count = len(positions) // 3
    for index in range(count):  # pragma: no branch
        var p = _vertex(positions, index)
        uvs.append(_u_of(p))
        uvs.append(max(Float32(0), min(Float32(1), (p.y - base) / span)))
    # A triangle across the seam gets copies of its corners on the low
    # side, moved past one.
    var copies = Dict[Int, Int]()
    var corner = 0
    while corner < len(indices):  # pragma: no branch
        var lowest = Float32(2)
        var highest = Float32(-1)
        for n in range(3):  # pragma: no branch
            var u = uvs[indices[corner + n] * 2]
            lowest = min(lowest, u)
            highest = max(highest, u)
        if highest - lowest > Float32(0.5):
            for n in range(3):  # pragma: no branch
                var index = indices[corner + n]
                if uvs[index * 2] >= Float32(0.5):
                    continue
                var copy = copies.get(index, -1)
                if copy < 0:
                    copy = len(positions) // 3
                    for axis in range(3):  # pragma: no branch
                        positions.append(positions[index * 3 + axis])
                        normals.append(normals[index * 3 + axis])
                    uvs.append(uvs[index * 2] + Float32(1))
                    uvs.append(uvs[index * 2 + 1])
                    copies[index] = copy
                indices[corner + n] = copy
        corner += 3
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(indices^)
    return geometry^


def share_height(
    mut geometry: BufferGeometry, low: Float32, span: Float32
) raises:
    """Set each vertex's `v` from its height over a whole skin.

    A skin meshed in parts measures `v` over each part's own height, so
    the texture would not meet across the parts.

    Args:
        geometry: A geometry with `position` and `uv`.
        low: The height where `v` is zero, in meters.
        span: The height over which `v` runs to one, in meters.

    Raises:
        Error: If the geometry lacks `position` or `uv`.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    ref uvs = geometry.attribute_view(String(UV))
    var shared = List[Float32]()
    for index in range(positions.count()):  # pragma: no branch
        shared.append(uvs.component(index, 0))
        var v = (positions.vector3(index).y - low) / span
        shared.append(max(Float32(0), min(Float32(1), v)))
    geometry.set_attribute(String(UV), BufferAttribute(shared^, 2))
