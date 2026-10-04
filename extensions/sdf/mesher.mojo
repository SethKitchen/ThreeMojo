# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Narrow-band surface nets: procedural-animals' `core/sdf/mesher.js`.

A coarse pass samples the corners of blocks of cells and keeps the
blocks the surface can reach. Only those blocks are sampled finely, each
with the primitives that can change the field inside it. Each cell the
surface crosses gets one vertex: the mean of its edge crossings, walked
onto the true surface by two Newton steps. Its normal is the field's
gradient. Each crossed lattice edge makes one quad, split along its
shorter diagonal.

procedural-animals stores the whole fine lattice. This port stores only
the active blocks, so a fine cell size costs memory in proportion to the
surface, not the volume. Blocks are sampled and vertices are placed on
several threads. The mesh is the same for any number of them.
"""

from extensions.sdf.field import SdfModel
from extensions.sdf.vector import (
    V3,
    length,
)
from render.tasks import TaskGroup
from std.math import ceil, isfinite, sqrt
from std.sys import num_logical_cores, size_of
from units.si import METER, Length

# Coarse blocks per side of a super-block, the unit of the first cull.
comptime SUPER = 4
# Maximum sample-and-spill rounds. Exhaustion must not emit a partial mesh.
comptime SPILL_ROUNDS = 8
# A block wakes at first when a corner is this many half-diagonals from
# the surface or nearer. Each field is exact or a lower bound, so the
# surface cannot reach a block whose corners are all farther than one; the
# rest is slack. The spill wakes any block the first pass still missed.
comptime ACTIVE_MARGIN = 1.15
# A sample value no field takes: "not sampled".
comptime UNSAMPLED = Float32(3.0e38)


@fieldwise_init
struct Lattice(ImplicitlyCopyable):
    """The fine lattice: an origin, a cell size and a block grid.

    Point `(gx, gy, gz)` is `origin + (gx, gy, gz) * cell`. Each block is
    `block` cells on a side, and there are `bx` by `by` by `bz` blocks.
    """

    var origin: V3
    var cell: Float64
    var block: Int
    var bx: Int
    var by: Int
    var bz: Int

    def point(self, gx: Int, gy: Int, gz: Int) -> V3:
        """Return one lattice point.

        Args:
            gx: The x index.
            gy: The y index.
            gz: The z index.

        Returns:
            Its position in meters.
        """
        return (
            self.origin + V3(Float64(gx), Float64(gy), Float64(gz)) * self.cell
        )

    def block_index(self, i: Int, j: Int, k: Int) -> Int:
        """Return the linear index of a block.

        Args:
            i: The block's x index.
            j: The block's y index.
            k: The block's z index.

        Returns:
            `i + bx (j + by k)`.
        """
        return i + self.bx * (j + self.by * k)


struct SurfaceMesh(Movable):
    """One meshed surface and the culled primitive lists that made it.

    `vertex_block` gives each vertex's block slot. That slot's primitives
    are `lists[list_start[slot] : list_start[slot] + list_count[slot]]`.
    The coat reads them to find what a vertex lies on.
    """

    var positions: List[Float32]
    var normals: List[Float32]
    var indices: List[Int]
    var vertex_block: List[Int]
    var list_start: List[Int]
    var list_count: List[Int]
    var lists: List[Int]

    def __init__(out self):
        """Make an empty mesh."""
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.indices = List[Int]()
        self.vertex_block = List[Int]()
        self.list_start = List[Int]()
        self.list_count = List[Int]()
        self.lists = List[Int]()

    def vertex_count(self) -> Int:
        """Return how many vertices the mesh has.

        Returns:
            The count.
        """
        return len(self.positions) // 3

    def vertex(self, v: Int) -> V3:
        """Return one vertex.

        Args:
            v: The vertex.

        Returns:
            Its position.
        """
        return V3(
            Float64(self.positions[v * 3]),
            Float64(self.positions[v * 3 + 1]),
            Float64(self.positions[v * 3 + 2]),
        )

    def normal(self, v: Int) -> V3:
        """Return one vertex normal.

        Args:
            v: The vertex.

        Returns:
            Its unit normal.
        """
        return V3(
            Float64(self.normals[v * 3]),
            Float64(self.normals[v * 3 + 1]),
            Float64(self.normals[v * 3 + 2]),
        )


def _blocks(span: Float64, cell: Float64, block: Int) raises -> Int:
    var fine = ceil(span / cell)
    # Float64(Int.MAX) rounds up to 2**63. An exclusive bound keeps the
    # conversion defined and leaves room for padding and block rounding.
    if not (fine >= 0.0 and fine < Float64(Int.MAX)):
        raise Error("Mesh cell count cannot fit in Int")
    var cells = Int(fine) + 4
    return (cells + block - 1) // block


def _checked_count(count: Int, factor: Int) raises -> Int:
    """Multiply a nonnegative count by a positive factor without overflow."""
    if count < 0 or factor <= 0:
        raise Error("Mesh counts need a nonnegative count and positive factor")
    if count > Int.MAX // factor:
        raise Error("Mesh grid exceeds addressable storage")
    return count * factor


def _check_grid_sizes(lattice: Lattice) raises:
    # Check the dense block-corner allocation before allocating slot_of.
    # This also bounds the smaller block and super-block grids.
    var corners = _checked_count(lattice.bx + 1, lattice.by + 1)
    corners = _checked_count(corners, lattice.bz + 1)
    _ = _checked_count(corners, size_of[Float64]())
    # Fine cells have linear Int indexes even though storage is sparse.
    var cells = _checked_count(lattice.bx, lattice.by)
    cells = _checked_count(cells, lattice.bz)
    _ = _checked_count(cells, lattice.block * lattice.block * lattice.block)


def check_cell(cell: Length, block: Int) raises:
    """Refuse a cell size or a block size the mesher cannot use.

    Args:
        cell: The fine cell size.
        block: Fine cells per block side.

    Raises:
        Error: If the cell is not positive and finite, or the block is not
            from 2 to 16.
    """
    var h = Float64(cell.to(METER))
    if not (h > 0.0 and h < 1e3):
        raise Error("A mesh cell must be positive and finite")
    if block < 2 or block > 16:
        raise Error("A mesh block must be from 2 to 16 cells")


async def _sample_task(
    model: Pointer[SdfModel, ImmutAnyOrigin],
    lattice: Lattice,
    active: MutPointer[Int, MutAnyOrigin],
    starts: MutPointer[Int, MutAnyOrigin],
    counts: MutPointer[Int, MutAnyOrigin],
    lists: Pointer[List[Int], MutAnyOrigin],
    samples: MutPointer[Float32, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Sample every lattice point of a run of active blocks.

    Each slot has its own run of samples, so no two tasks write one.
    """
    var f = lattice.block
    var side = f + 1
    var per = side * side * side
    for slot in range(first, past):  # pragma: no branch
        var b = active[unsafe_offset=slot]
        var i = b % lattice.bx
        var j = (b // lattice.bx) % lattice.by
        var k = b // (lattice.bx * lattice.by)
        var start = starts[unsafe_offset=slot]
        var end = start + counts[unsafe_offset=slot]
        for n in range(per):  # pragma: no branch
            var p = lattice.point(
                i * f + n % side,
                j * f + (n // side) % side,
                k * f + n // (side * side),
            )
            samples[unsafe_offset=slot * per + n] = Float32(
                model[].eval_span(lists[], start, end, p)
            )


async def _vertex_task(
    model: Pointer[SdfModel, ImmutAnyOrigin],
    lattice: Lattice,
    cells: MutPointer[Int, MutAnyOrigin],
    blocks: MutPointer[Int, MutAnyOrigin],
    starts: MutPointer[Int, MutAnyOrigin],
    counts: MutPointer[Int, MutAnyOrigin],
    lists: Pointer[List[Int], MutAnyOrigin],
    samples: MutPointer[Float32, MutAnyOrigin],
    positions: MutPointer[Float32, MutAnyOrigin],
    normals: MutPointer[Float32, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Place the vertex of each of a run of crossed cells."""
    var f = lattice.block
    var side = f + 1
    var per = side * side * side
    var h = lattice.cell
    var e_place = min(0.0006, 0.6 * h)
    var e_normal = min(0.0008, 0.8 * h)
    var tolerance = min(2e-5, 0.02 * h)
    var nx = lattice.bx * f
    var ny = lattice.by * f
    for v in range(first, past):  # pragma: no branch
        var cell = cells[unsafe_offset=v]
        var slot = blocks[unsafe_offset=v]
        var gx = cell % nx
        var gy = (cell // nx) % ny
        var gz = cell // (nx * ny)
        var lx = gx % f
        var ly = gy % f
        var lz = gz % f
        var base = slot * per
        var corner = SIMD[DType.float64, 8](0.0)
        for c in range(8):  # pragma: no branch
            corner[c] = Float64(
                samples[
                    unsafe_offset=base
                    + (lx + (c & 1))
                    + side
                    * ((ly + ((c >> 1) & 1)) + side * (lz + ((c >> 2) & 1)))
                ]
            )
        var sum = V3(0.0, 0.0, 0.0)
        var crossings = 0
        for edge in range(12):  # pragma: no branch
            var a = _edge_start(edge)
            var b = a + _edge_step(edge)
            var va = corner[a]
            var vb = corner[b]
            if (va < 0.0) == (vb < 0.0):
                continue
            var t = va / (va - vb)
            var pa = V3(Float64(a & 1), Float64((a >> 1) & 1), Float64(a >> 2))
            var pb = V3(Float64(b & 1), Float64((b >> 1) & 1), Float64(b >> 2))
            sum = sum + pa + (pb - pa) * t
            crossings += 1
        var local = sum * (1.0 / Float64(crossings))
        var low = lattice.point(gx, gy, gz)
        var p = low + local * h
        var start = starts[unsafe_offset=slot]
        var end = start + counts[unsafe_offset=slot]
        for _step in range(2):  # pragma: no branch
            var d = model[].eval_span(lists[], start, end, p)
            if abs(d) < tolerance:
                break
            var g = model[].gradient_span(lists[], start, end, p, e_place)
            var g2 = g.x * g.x + g.y * g.y + g.z * g.z + 1e-12
            var move = g * (-d / g2)
            var l = length(move)
            p = p + move * (min(1.0, h / l))
        # Keep the vertex inside its cell, grown by 0.35 cells, so quads
        # do not fold.
        var grow = 0.35 * h
        p = V3(
            min(max(p.x, low.x - grow), low.x + h + grow),
            min(max(p.y, low.y - grow), low.y + h + grow),
            min(max(p.z, low.z - grow), low.z + h + grow),
        )
        var n = model[].gradient_span(lists[], start, end, p, e_normal)
        var nl = length(n)
        n = n * (1.0 / nl) if nl > 0.0 else V3(0.0, 1.0, 0.0)
        positions[unsafe_offset=v * 3] = Float32(p.x)
        positions[unsafe_offset=v * 3 + 1] = Float32(p.y)
        positions[unsafe_offset=v * 3 + 2] = Float32(p.z)
        normals[unsafe_offset=v * 3] = Float32(n.x)
        normals[unsafe_offset=v * 3 + 1] = Float32(n.y)
        normals[unsafe_offset=v * 3 + 2] = Float32(n.z)


def _edge_start(edge: Int) -> Int:
    # Edges 0-3 run along x, 4-7 along y, 8-11 along z. The corner bits
    # are x, y and z.
    var axis = edge // 4
    var n = edge % 4
    var lower = n & 1
    var upper = n >> 1
    return (lower << 1 | upper << 2) if axis == 0 else (
        (lower | upper << 2) if axis == 1 else (lower | upper << 1)
    )


def _edge_step(edge: Int) -> Int:
    return 1 << (edge // 4)


struct _Grid:
    """The block grid while it is built: which blocks are active, their
    culled lists, their samples and their cell vertices."""

    var lattice: Lattice
    var slot_of: List[Int]
    var active: List[Int]
    var list_start: List[Int]
    var list_count: List[Int]
    var lists: List[Int]
    var samples: List[Float32]
    var vertex_of: List[Int]

    def __init__(out self, lattice: Lattice):
        self.lattice = lattice
        self.slot_of = List[Int](
            length=lattice.bx * lattice.by * lattice.bz, fill=-1
        )
        self.active = List[Int]()
        self.list_start = List[Int]()
        self.list_count = List[Int]()
        self.lists = List[Int]()
        self.samples = List[Float32]()
        self.vertex_of = List[Int]()

    def sample(self, gx: Int, gy: Int, gz: Int) -> Float32:
        """Return one lattice sample, or `UNSAMPLED` outside every block.

        A point on a face between blocks belongs to both. The block below
        it is read when the block above it is not active.
        """
        var f = self.lattice.block
        var side = f + 1
        for n in range(8):  # pragma: no branch
            var i = min((gx - (n & 1)) // f, self.lattice.bx - 1)
            var j = min((gy - ((n >> 1) & 1)) // f, self.lattice.by - 1)
            var k = min((gz - (n >> 2)) // f, self.lattice.bz - 1)
            if min(i, min(j, k)) < 0:
                continue
            var slot = self.slot_of[self.lattice.block_index(i, j, k)]
            if slot >= 0:
                var local = (gx - i * f) + side * (
                    (gy - j * f) + side * (gz - k * f)
                )
                return self.samples[slot * side * side * side + local]
        return UNSAMPLED

    def vertex(self, gx: Int, gy: Int, gz: Int) -> Int:
        """Return the vertex of one cell, or -1."""
        var f = self.lattice.block
        var slot = self.slot_of[
            self.lattice.block_index(gx // f, gy // f, gz // f)
        ]
        if slot < 0:
            return -1
        var local = gx % f + f * (gy % f + f * (gz % f))
        return self.vertex_of[slot * f * f * f + local]


def mesh_part(
    model: SdfModel,
    part: List[Int],
    low: V3,
    high: V3,
    cell: Length,
    block: Int = 6,
    workers: Int = 1,
) raises -> SurfaceMesh:
    """Mesh the zero set of some primitives inside a box.

    Args:
        model: The sculpt.
        part: The primitives to mesh, in model order.
        low: The box's least corner, in meters.
        high: The box's greatest corner, in meters.
        cell: The fine cell size.
        block: Fine cells per block side.
        workers: How many threads share the work. Zero or less means one
            per logical core. The mesh is the same for any count.

    Returns:
        The surface. It is empty when the box holds no surface.

    Raises:
        Error: If `check_cell` refuses the cell or the block, the box is
            nonfinite or empty, `part` is empty or names no primitive,
            a grid size cannot fit in addressable storage, or the spill
            budget is exhausted.
    """
    return _mesh_part(
        model, part, low, high, cell, block, workers, ACTIVE_MARGIN
    )


def _mesh_part(
    model: SdfModel,
    part: List[Int],
    low: V3,
    high: V3,
    cell: Length,
    block: Int,
    workers: Int,
    margin: Float64,
) raises -> SurfaceMesh:
    # `mesh_part` with the first pass's margin, in half-diagonals.
    check_cell(cell, block)
    if not (
        isfinite(low.x)
        and isfinite(low.y)
        and isfinite(low.z)
        and isfinite(high.x)
        and isfinite(high.y)
        and isfinite(high.z)
    ):
        raise Error("A mesh box must have finite coordinates")
    if not (high.x > low.x and high.y > low.y and high.z > low.z):
        raise Error("A mesh box must not be empty")
    if len(part) == 0:
        raise Error("A mesh part needs at least one primitive")
    var kmax = 0.0
    for i in part:  # pragma: no branch
        if i < 0 or i >= len(model.prims):
            raise Error("Mesh part index names no primitive")
        kmax = max(kmax, model.prims[i].k)
    var h = Float64(cell.to(METER))
    var threads = workers if workers > 0 else num_logical_cores()
    var lattice = Lattice(
        low - V3(2.0 * h, 2.0 * h, 2.0 * h),
        h,
        block,
        _blocks(high.x - low.x, h, block),
        _blocks(high.y - low.y, h, block),
        _blocks(high.z - low.z, h, block),
    )
    _check_grid_sizes(lattice)
    var grid = _Grid(lattice)
    _find_active(model, part, grid, kmax, margin)
    _sample_band(model, part, grid, kmax, threads)
    var out = SurfaceMesh()
    var cells = List[Int]()
    _number_vertices(grid, cells, out.vertex_block)
    var count = len(cells)
    _ = _checked_count(count, 3 * size_of[Float32]())
    out.positions = List[Float32](length=count * 3, fill=0.0)
    out.normals = List[Float32](length=count * 3, fill=0.0)
    var tasks = max(1, min(threads, count))
    var placers = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        placers.create_task(
            _vertex_task(
                Pointer(to=model).unsafe_origin_cast[ImmutAnyOrigin](),
                lattice,
                cells.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                out.vertex_block.unsafe_ptr().unsafe_origin_cast[
                    MutAnyOrigin
                ](),
                grid.list_start.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                grid.list_count.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                Pointer(to=grid.lists).unsafe_origin_cast[MutAnyOrigin](),
                grid.samples.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                out.positions.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                out.normals.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                task * count // tasks,
                (task + 1) * count // tasks,
            )
        )
    placers.wait()
    _ = len(cells)
    _faces(grid, cells, out)
    out.list_start = grid.list_start.copy()
    out.list_count = grid.list_count.copy()
    out.lists = grid.lists.copy()
    return out^


def _sample_band(
    model: SdfModel,
    part: List[Int],
    mut grid: _Grid,
    kmax: Float64,
    threads: Int,
) raises:
    """Sample and share active blocks until no sleeping block wakes.

    Refuse an unfinished frontier at the budget. Newly woken blocks have
    no samples yet, so vertex numbering must not read them.
    """
    var sampled = 0
    for _round in range(SPILL_ROUNDS):  # pragma: no branch
        _sample_blocks(model, grid, threads, sampled)
        sampled = len(grid.active)
        _share_faces(grid)
        if _spill(model, part, grid, kmax) == 0:
            return
    raise Error("Mesh spill budget exhausted before all blocks were sampled")


def _find_active(
    model: SdfModel,
    part: List[Int],
    mut grid: _Grid,
    kmax: Float64,
    margin: Float64,
):
    """Sample the block corners and keep the blocks near the surface."""
    var lt = grid.lattice
    var big = lt.cell * Float64(lt.block)
    var cx = lt.bx + 1
    var cy = lt.by + 1
    var corners = List[Float64](length=cx * cy * (lt.bz + 1), fill=0.0)
    var sx = (lt.bx + SUPER - 1) // SUPER
    var sy = (lt.by + SUPER - 1) // SUPER
    var sz = (lt.bz + SUPER - 1) // SUPER
    var super_size = big * Float64(SUPER)
    var super_rho = super_size * sqrt(3.0) * 0.5
    var super_lists = List[List[Int]]()
    for sk in range(sz):  # pragma: no branch
        for sj in range(sy):  # pragma: no branch
            for si in range(sx):  # pragma: no branch
                var center = (
                    lt.origin
                    + V3(
                        Float64(si) + 0.5, Float64(sj) + 0.5, Float64(sk) + 0.5
                    )
                    * super_size
                )
                super_lists.append(model.cull(part, center, super_rho, kmax))
    for k in range(lt.bz + 1):  # pragma: no branch
        for j in range(cy):  # pragma: no branch
            for i in range(cx):  # pragma: no branch
                var s = min(i // SUPER, sx - 1) + sx * (
                    min(j // SUPER, sy - 1) + sy * min(k // SUPER, sz - 1)
                )
                corners[i + cx * (j + cy * k)] = model.eval_list(
                    super_lists[s],
                    lt.point(i * lt.block, j * lt.block, k * lt.block),
                )
    var reach = big * sqrt(3.0) * margin * 0.5
    var rho = big * sqrt(3.0) * 0.5
    for k in range(lt.bz):  # pragma: no branch
        for j in range(lt.by):  # pragma: no branch
            for i in range(lt.bx):  # pragma: no branch
                var nearest = 1e9
                var inside = 0
                for c in range(8):  # pragma: no branch
                    var v = corners[
                        (i + (c & 1))
                        + cx * ((j + ((c >> 1) & 1)) + cy * (k + (c >> 2)))
                    ]
                    nearest = min(nearest, abs(v))
                    inside += Int(v < 0.0)
                var crossed = inside % 8 != 0
                if not crossed and nearest >= reach:
                    continue
                var s = i // SUPER + sx * (j // SUPER + sy * (k // SUPER))
                var center = lt.point(
                    i * lt.block, j * lt.block, k * lt.block
                ) + V3(big * 0.5, big * 0.5, big * 0.5)
                var list = model.cull(super_lists[s], center, rho, kmax)
                grid.slot_of[lt.block_index(i, j, k)] = len(grid.active)
                grid.active.append(lt.block_index(i, j, k))
                grid.list_start.append(len(grid.lists))
                grid.list_count.append(len(list))
                for id in list:  # pragma: no branch
                    grid.lists.append(id)


def _sample_blocks(
    model: SdfModel, mut grid: _Grid, threads: Int, first: Int
) raises:
    """Sample every lattice point of the active blocks from slot `first`."""
    var side = grid.lattice.block + 1
    var per = side * side * side
    _ = _checked_count(len(grid.active), per * size_of[Float32]())
    var count = len(grid.active) - first
    for _ in range(count * per):
        grid.samples.append(UNSAMPLED)
    var tasks = max(1, min(threads, count))
    var samplers = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        samplers.create_task(
            _sample_task(
                Pointer(to=model).unsafe_origin_cast[ImmutAnyOrigin](),
                grid.lattice,
                grid.active.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                grid.list_start.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                grid.list_count.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                Pointer(to=grid.lists).unsafe_origin_cast[MutAnyOrigin](),
                grid.samples.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                first + task * count // tasks,
                first + (task + 1) * count // tasks,
            )
        )
    samplers.wait()
    _ = len(grid.active)


def _share_faces(mut grid: _Grid):
    """Give each lattice point one value in every block that holds it.

    Neighboring blocks sample their shared faces apart, each with its own
    culled solids, and rounding can tell the two apart in sign. The
    block a point lies in by floor division owns it, and every other
    active block takes the owner's value. A cell then sees the same
    crossings as its neighbors, and the surface has no pinholes.
    """
    var lt = grid.lattice
    var f = lt.block
    var side = f + 1
    var per = side * side * side
    for slot in range(len(grid.active)):
        var b = grid.active[slot]
        var bi = b % lt.bx
        var bj = (b // lt.bx) % lt.by
        var bk = b // (lt.bx * lt.by)
        for n in range(per):  # pragma: no branch
            var lx = n % side
            var ly = (n // side) % side
            var lz = n // (side * side)
            if max(lx, max(ly, lz)) < f:
                continue
            var oi = min(bi + lx // f, lt.bx - 1)
            var oj = min(bj + ly // f, lt.by - 1)
            var ok = min(bk + lz // f, lt.bz - 1)
            var owner = grid.slot_of[lt.block_index(oi, oj, ok)]
            if owner < 0 or owner == slot:
                continue
            var local = (bi * f + lx - oi * f) + side * (
                (bj * f + ly - oj * f) + side * (bk * f + lz - ok * f)
            )
            grid.samples[slot * per + n] = grid.samples[owner * per + local]


def _spill(
    model: SdfModel, part: List[Int], mut grid: _Grid, kmax: Float64
) -> Int:
    """Wake each sleeping block next to a face the surface crosses.

    Returns:
        How many blocks woke.
    """
    var lt = grid.lattice
    var f = lt.block
    var side = f + 1
    var per = side * side * side
    var woke = 0
    var count = len(grid.active)
    for slot in range(count):
        var b = grid.active[slot]
        var bi = b % lt.bx
        var bj = (b // lt.bx) % lt.by
        var bk = b // (lt.bx * lt.by)
        for face in range(6):  # pragma: no branch
            var axis = face // 2
            var step = 1 if face % 2 == 1 else -1
            var ni = bi + (step if axis == 0 else 0)
            var nj = bj + (step if axis == 1 else 0)
            var nk = bk + (step if axis == 2 else 0)
            var outside = min(ni, min(nj, nk)) < 0
            outside = outside or ni >= lt.bx or nj >= lt.by or nk >= lt.bz
            if outside:
                continue
            if grid.slot_of[lt.block_index(ni, nj, nk)] >= 0:
                continue
            var at = f if step > 0 else 0
            var inside = 0
            for m in range(side * side):  # pragma: no branch
                var u = m % side
                var v = m // side
                var lx = at if axis == 0 else u
                var ly = at if axis == 1 else (v if axis == 0 else u)
                var lz = at if axis == 2 else v
                var local = lx + side * (ly + side * lz)
                inside += Int(grid.samples[slot * per + local] < 0.0)
            if inside % (side * side) == 0:
                continue
            _wake(model, part, grid, kmax, ni, nj, nk)
            woke += 1
    return woke


def _wake(
    model: SdfModel,
    part: List[Int],
    mut grid: _Grid,
    kmax: Float64,
    i: Int,
    j: Int,
    k: Int,
):
    """Make one block active, with the solids that can change it."""
    var lt = grid.lattice
    var big = lt.cell * Float64(lt.block)
    var center = lt.point(i * lt.block, j * lt.block, k * lt.block) + V3(
        big * 0.5, big * 0.5, big * 0.5
    )
    var list = model.cull(part, center, big * sqrt(3.0) * 0.5, kmax)
    grid.slot_of[lt.block_index(i, j, k)] = len(grid.active)
    grid.active.append(lt.block_index(i, j, k))
    grid.list_start.append(len(grid.lists))
    grid.list_count.append(len(list))
    for id in list:  # pragma: no branch
        grid.lists.append(id)


def _number_vertices(
    mut grid: _Grid, mut cells: List[Int], mut blocks: List[Int]
) raises:
    """Give each crossed cell of each active block a vertex number."""
    var lt = grid.lattice
    var f = lt.block
    var side = f + 1
    var per = side * side * side
    var nx = lt.bx * f
    var ny = lt.by * f
    _ = _checked_count(len(grid.active), f * f * f * size_of[Int]())
    grid.vertex_of = List[Int](length=len(grid.active) * f * f * f, fill=-1)
    for slot in range(len(grid.active)):  # pragma: no branch
        var b = grid.active[slot]
        var bi = b % lt.bx
        var bj = (b // lt.bx) % lt.by
        var bk = b // (lt.bx * lt.by)
        var base = slot * per
        for n in range(f * f * f):  # pragma: no branch
            var lx = n % f
            var ly = (n // f) % f
            var lz = n // (f * f)
            var inside = 0
            for c in range(8):  # pragma: no branch
                var at = (
                    base
                    + (lx + (c & 1))
                    + side * ((ly + ((c >> 1) & 1)) + side * (lz + (c >> 2)))
                )
                inside += Int(grid.samples[at] < 0.0)
            if inside % 8 == 0:
                continue
            grid.vertex_of[slot * f * f * f + n] = len(cells)
            cells.append(
                (bi * f + lx) + nx * ((bj * f + ly) + ny * (bk * f + lz))
            )
            blocks.append(slot)


def _faces(grid: _Grid, cells: List[Int], mut mesh: SurfaceMesh):
    """Emit one quad for each crossed lattice edge, as two triangles."""
    var lt = grid.lattice
    var nx = lt.bx * lt.block
    var ny = lt.by * lt.block
    var nz = lt.bz * lt.block
    for v in range(len(cells)):  # pragma: no branch
        var c = cells[v]
        var gx = c % nx
        var gy = (c // nx) % ny
        var gz = c // (nx * ny)
        for a in range(3):  # pragma: no branch
            # The edge runs along axis `a` from the cell's far corner in
            # the other two axes, `b` and `cc`. The four cells round it
            # are this one, one step along `b`, one along `cc`, and both.
            var ux = Int(a == 0)
            var uy = Int(a == 1)
            var uz = Int(a == 2)
            var bx = Int(a == 2)
            var by = Int(a == 0)
            var bz = Int(a == 1)
            var cx = 1 - ux - bx
            var cy = 1 - uy - by
            var cz = 1 - uz - bz
            var x0 = gx + bx + cx
            var y0 = gy + by + cy
            var z0 = gz + bz + cz
            # Past the lattice there is nothing to join.
            var beyond = (
                Int(x0 + ux >= nx) + Int(y0 + uy >= ny) + Int(z0 + uz >= nz)
            )
            if beyond > 0:
                continue
            var v0 = grid.sample(x0, y0, z0)
            var v1 = grid.sample(x0 + ux, y0 + uy, z0 + uz)
            if (v0 < 0) == (v1 < 0):
                continue
            var qb = grid.vertex(gx + bx, gy + by, gz + bz)
            var qc = grid.vertex(gx + bx + cx, gy + by + cy, gz + bz + cz)
            var qd = grid.vertex(gx + cx, gy + cy, gz + cz)
            if min(qb, min(qc, qd)) < 0:
                continue
            _emit(mesh, v, qb, qc, qd, v0 < 0)


def _emit(mut mesh: SurfaceMesh, a: Int, b: Int, c: Int, d: Int, flip: Bool):
    """Append a quad as two triangles.

    The split is the diagonal whose two triangles both face the way their
    vertex normals do; on a tie, the shorter one. Where a projected vertex
    folds a triangle over anyway, its winding is turned to face out, so
    it leaves no pinhole in a mesh drawn front faces only.
    """
    var q1 = b if flip else d
    var q3 = d if flip else b
    var along_ac = min(_facing(mesh, a, q1, c), _facing(mesh, a, c, q3))
    var along_bd = min(_facing(mesh, a, q1, q3), _facing(mesh, q1, c, q3))
    var shorter = _squared(mesh, a, c) <= _squared(mesh, q1, q3)
    var use_ac = along_ac > along_bd or (along_ac == along_bd and shorter)
    if use_ac:
        _triangle(mesh, a, q1, c)
        _triangle(mesh, a, c, q3)
    else:
        _triangle(mesh, a, q1, q3)
        _triangle(mesh, q1, c, q3)


def _facing(mesh: SurfaceMesh, a: Int, b: Int, c: Int) -> Float64:
    # The cosine between the face's normal and its corners' mean normal.
    var pa = mesh.vertex(a)
    var f = (mesh.vertex(b) - pa).cross(mesh.vertex(c) - pa)
    var n = mesh.normal(a) + mesh.normal(b) + mesh.normal(c)
    var lf = f.length() * n.length()
    return f.dot(n) / lf if lf > 0.0 else 0.0


def _triangle(mut mesh: SurfaceMesh, a: Int, b: Int, c: Int):
    var outward = _facing(mesh, a, b, c) >= 0.0
    mesh.indices.append(a)
    mesh.indices.append(b if outward else c)
    mesh.indices.append(c if outward else b)


def _squared(mesh: SurfaceMesh, a: Int, b: Int) -> Float64:
    var d = mesh.vertex(a) - mesh.vertex(b)
    return d.x * d.x + d.y * d.y + d.z * d.z


def merge(mut into: SurfaceMesh, other: SurfaceMesh):
    """Append one surface to another.

    The second surface's vertex, block and list indexes are shifted past
    the first's.

    Args:
        into: The surface that grows.
        other: The surface appended.
    """
    var v0 = into.vertex_count()
    var s0 = len(into.list_start)
    var l0 = len(into.lists)
    for x in other.positions:
        into.positions.append(x)
    for x in other.normals:
        into.normals.append(x)
    for i in other.indices:
        into.indices.append(i + v0)
    for b in other.vertex_block:
        into.vertex_block.append(b + s0)
    for s in other.list_start:
        into.list_start.append(s + l0)
    for c in other.list_count:
        into.list_count.append(c)
    for id in other.lists:
        into.lists.append(id)
