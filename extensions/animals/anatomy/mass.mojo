# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Segment mass, center of mass and inertia, sampled from the sculpt.

The sculpt is sampled on a grid of cubic cells. A cell's share of
flesh is `clamp(1/2 - d / h, 0, 1)`, with `d` the signed distance of
its center and `h` its side: a cell the surface halves is half full.
The coat is not flesh: solids of hair, wool and feathers are left out,
and the furred surfaces are pulled in by the species' coat depth before
they are sampled.

Each cell takes the density of the solid nearest it and is added to the
bone that solid rides. `extensions/anatomy/inertia.mojo` sums the cells
and moves the tensor to the center of mass, so each bone's mass, center
and inertia come from one pass. The whole body is the sum of its bones.
"""

from extensions.anatomy.inertia import InertiaTally, SegmentInertia
from extensions.animals.anatomy.body import (
    BODY_LENGTH,
    SHOULDER_HEIGHT,
    ReferenceKind,
    species_body,
)
from extensions.animals.anatomy.density import (
    IN_BODY,
    ON_WITHERS,
    solid_densities,
    solid_roles,
)
from extensions.animals.build import Animal, part_box
from extensions.animals.parts import EYEBALL, HORN, TEETH, TONGUE, WATTLE
from extensions.animals.rig import Pose
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import SURFACE_PART_COUNT, SurfacePart
from extensions.sdf.vector import V3
from math.vector3 import Vector3
from render.tasks import TaskGroup
from std.math import ceil, sqrt
from std.sys import num_logical_cores
from units.si import CUBIC_METER, METER, Length, Volume

# Cells per block side. A block is culled and skipped as a whole.
comptime BLOCK = 8
# The coat reaches at most this share of a solid's smallest radius into
# it. A design choice: hair is short where a limb is thin.
comptime COAT_SHARE = 0.3


struct BodyMass(Movable):
    """The sampled mass properties of one animal, bone by bone.

    Positions are in the sculpt's frame: meters, `+y` up, `+z` forward
    and `+x` to the animal's left.
    """

    # One tally per bone, by bone index.
    var bones: List[InertiaTally]
    # The cell side the sculpt was sampled at.
    var step: Length
    # The flesh volume, coat left out.
    var volume: Volume
    # The lowest point of the flesh: the ground under the feet.
    var ground: Length
    # The top of the withers: the highest flesh over the shoulders.
    var withers: Length
    # Nose to rump along `z`, head and trunk only.
    var body_length: Length
    # Nose to the tip of the tail along `z`, coat and fins included.
    var total_length: Length

    def __init__(
        out self,
        var bones: List[InertiaTally],
        step: Length,
        stats: SIMD[DType.float64, STATS],
    ):
        """Hold the tallies and extents of a sampled sculpt.

        Args:
            bones: One tally per bone.
            step: The cell side.
            stats: The volume and the extents, in meters.
        """
        self.bones = bones^
        self.step = step
        self.volume = Volume(Float32(stats[VOLUME]), CUBIC_METER)
        self.ground = Length(Float32(stats[GROUND]), METER)
        self.withers = Length(Float32(stats[WITHERS]), METER)
        var body = max(0.0, stats[BODY_HIGH] - stats[BODY_LOW])
        self.body_length = Length(Float32(body), METER)
        var total = max(0.0, stats[TOTAL_HIGH] - stats[TOTAL_LOW])
        self.total_length = Length(Float32(total), METER)

    def reference(self, kind: ReferenceKind) raises -> Length:
        """Return a reference length of the sampled sculpt.

        Args:
            kind: Which length.

        Returns:
            The shoulder height above the ground, the body length or
            the total length.

        Raises:
            Error: If the kind is not named, or the sculpt has no
                withers to measure.
        """
        if not kind.is_valid():
            raise Error("A reference length must be named")
        if kind == SHOULDER_HEIGHT:
            if self.withers.value < self.ground.value:
                raise Error("The sculpt has no withers")
            return self.withers - self.ground
        if kind == BODY_LENGTH:
            return self.body_length
        return self.total_length

    def total(self) raises -> SegmentInertia:
        """Return the whole body's mass, center of mass and inertia.

        Returns:
            The sum of the bones, about the body's center of mass.

        Raises:
            Error: If the body sampled no flesh.
        """
        var sum = InertiaTally()
        for b in self.bones:  # pragma: no branch
            sum.add(b)
        return sum.result(0.0)

    def bone(self, index: Int, length: Float32) raises -> SegmentInertia:
        """Return one bone's mass, center of mass and inertia.

        Args:
            index: The bone's index in the rig.
            length: The bone's length, in meters, recorded with it.

        Returns:
            The bone's share of the body.

        Raises:
            Error: If there is no such bone or it holds no flesh.
        """
        if index < 0 or index >= len(self.bones):
            raise Error("The body has no such bone")
        return self.bones[index].result(length)


@fieldwise_init
struct _Grid(ImplicitlyCopyable):
    var low: V3
    var h: Float64
    var nx: Int
    var ny: Int
    var nz: Int
    var bx: Int
    var by: Int
    var bz: Int

    def center(self, i: Int, j: Int, k: Int) -> V3:
        return V3(
            self.low.x + (Float64(i) + 0.5) * self.h,
            self.low.y + (Float64(j) + 0.5) * self.h,
            self.low.z + (Float64(k) + 0.5) * self.h,
        )


def _erodes(part: SurfacePart) -> Bool:
    # The surfaces a coat covers. Horn, teeth, eyes, tongue and a comb
    # or a wattle are bare.
    for bare in [HORN, TEETH, EYEBALL, TONGUE, WATTLE]:  # pragma: no branch
        if part == bare:
            return False
    return True


# The extents each task keeps: ground, withers top, body length and
# total length, as the lowest or highest coordinate seen.
comptime GROUND = 0
comptime WITHERS = 1
comptime BODY_LOW = 2
comptime BODY_HIGH = 3
comptime TOTAL_LOW = 4
comptime TOTAL_HIGH = 5
comptime VOLUME = 6
comptime STATS = 8


struct _Input(Movable):
    var parts: List[List[Int]]
    var erode: List[Float64]
    var density: List[Float64]
    var role: List[Int]
    var coat: List[Int]
    # How deep the coat may reach into each solid: a share of its
    # smallest radius, so a thin leg keeps its flesh.
    var reach: List[Float64]

    def __init__(out self):
        self.parts = List[List[Int]]()
        self.erode = List[Float64]()
        self.density = List[Float64]()
        self.role = List[Int]()
        self.coat = List[Int]()
        self.reach = List[Float64]()


def _fresh_stats() -> SIMD[DType.float64, STATS]:
    var s = SIMD[DType.float64, STATS](0)
    s[GROUND] = 1e30
    s[WITHERS] = -1e30
    s[BODY_LOW] = 1e30
    s[BODY_HIGH] = -1e30
    s[TOTAL_LOW] = 1e30
    s[TOTAL_HIGH] = -1e30
    return s


async def _sample_task(
    model: Pointer[SdfModel, ImmutAnyOrigin],
    input: Pointer[_Input, ImmutAnyOrigin],
    grid: _Grid,
    tallies: MutPointer[InertiaTally, MutAnyOrigin],
    stats: MutPointer[Float64, MutAnyOrigin],
    bones: Int,
    task: Int,
    first: Int,
    past: Int,
):
    """Sample a run of blocks into this task's own tallies and stats."""
    var h = grid.h
    var rho = 0.5 * sqrt(3.0) * Float64(BLOCK) * h
    var kmax = model[].max_blend()
    var widths = Vector3(Float32(h), Float32(h), Float32(h))
    var cell_volume = h * h * h
    var s = _fresh_stats()
    var lists = List[List[Int]]()
    for b in range(first, past):  # pragma: no branch
        var bi = b % grid.bx
        var bj = (b // grid.bx) % grid.by
        var bk = b // (grid.bx * grid.by)
        var c = grid.low + V3(
            (Float64(bi) + 0.5) * Float64(BLOCK) * h,
            (Float64(bj) + 0.5) * Float64(BLOCK) * h,
            (Float64(bk) + 0.5) * Float64(BLOCK) * h,
        )
        lists.clear()
        var near = 1e30
        for p in range(len(input[].parts)):  # pragma: no branch
            # A part's nearest solid always survives its own cull.
            var cand = model[].cull(input[].parts[p], c, rho, kmax)
            near = min(near, model[].eval_list(cand, c))
            lists.append(cand^)
        var coat = model[].cull(input[].coat, c, rho, kmax)
        if len(coat) > 0:
            near = min(near, model[].eval_list(coat, c))
        if near > 1.5 * rho + h:
            continue
        for n in range(BLOCK * BLOCK * BLOCK):  # pragma: no branch
            var i = bi * BLOCK + n % BLOCK
            var j = bj * BLOCK + (n // BLOCK) % BLOCK
            var k = bk * BLOCK + n // (BLOCK * BLOCK)
            if i >= grid.nx or j >= grid.ny or k >= grid.nz:
                continue
            var q = grid.center(i, j, k)
            if len(coat) > 0:
                var d = model[].eval_list(coat, q)
                if d < 0.0 and d > -h:
                    s[TOTAL_LOW] = min(s[TOTAL_LOW], q.z + d)
                    s[TOTAL_HIGH] = max(s[TOTAL_HIGH], q.z - d)
            var best = 1e30
            var at = -1
            for p in range(len(lists)):  # pragma: no branch
                var d = model[].eval_list(lists[p], q)
                if d < best:
                    best = d
                    at = p
            if best > 0.5 * h:
                continue
            var solid = model[].nearest(lists[at], q)
            best += min(input[].erode[at], input[].reach[solid])
            var share = min(1.0, max(0.0, 0.5 - best / h))
            if share <= 0.0:
                continue
            var m = share * cell_volume * input[].density[solid]
            var bone = model[].prims[solid].bone.value
            var spot = Vector3(Float32(q.x), Float32(q.y), Float32(q.z))
            tallies[unsafe_offset=task * bones + bone].add_cell(m, spot, widths)
            s[VOLUME] += share * cell_volume
            if best >= 0.0 or best < -h:
                continue
            # Just inside the skin the field is the distance to it, so
            # `q - |d|` reaches the skin. Deeper in, a blend overstates
            # the depth, and the cell is left out.
            s[GROUND] = min(s[GROUND], q.y + best)
            s[TOTAL_LOW] = min(s[TOTAL_LOW], q.z + best)
            s[TOTAL_HIGH] = max(s[TOTAL_HIGH], q.z - best)
            var role = input[].role[solid]
            if role & ON_WITHERS != 0:
                s[WITHERS] = max(s[WITHERS], q.y - best)
            if role & IN_BODY != 0:
                s[BODY_LOW] = min(s[BODY_LOW], q.z + best)
                s[BODY_HIGH] = max(s[BODY_HIGH], q.z - best)
    for n in range(STATS):  # pragma: no branch
        stats[unsafe_offset=task * STATS + n] = s[n]


def _launch(
    model: SdfModel,
    input: _Input,
    grid: _Grid,
    mut tallies: List[InertiaTally],
    mut stats: List[Float64],
    bones: Int,
):
    var tasks = len(stats) // STATS
    var blocks = grid.bx * grid.by * grid.bz
    var group = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        group.create_task(
            _sample_task(
                Pointer(to=model).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=input).unsafe_origin_cast[ImmutAnyOrigin](),
                grid,
                tallies.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                stats.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                bones,
                task,
                task * blocks // tasks,
                (task + 1) * blocks // tasks,
            )
        )
    group.wait()


def sample_mass(
    animal: Animal, pose: Pose, step: Length, workers: Int = 0
) raises -> BodyMass:
    """Sample an animal's flesh into per-bone mass properties.

    Args:
        animal: The individual.
        pose: How its bones are turned. The bind pose stands it on the
            ground.
        step: The cell side. A fortieth of the reference length gives
            the mass to a few percent.
        workers: How many threads sample it. Zero or less means one per
            logical core. The result does not depend on the count, up
            to rounding.

    Returns:
        One tally per bone, the flesh volume and the reference extents.

    Raises:
        Error: If the step is not positive and finite, the grid would be
            larger than 400 cells a side, the pose is for another rig,
            or the sculpt has no flesh.
    """
    var h = Float64(step.to(METER))
    if not (h > 0.0 and h < 1e3):
        raise Error("A mass step must be positive and finite")
    var body = species_body(animal.species)
    var coat = Float64(body.coat_depth.to(METER))
    var world = pose.world(animal.rig)
    var posed = animal.model.moved(world)
    var input = _Input()
    input.density = solid_densities(animal)
    input.role = solid_roles(animal)
    for p in posed.prims:  # pragma: no branch
        input.reach.append(COAT_SHARE * min(p.r.x, min(p.r.y, p.r.z)))
    var low = V3(1e30, 1e30, 1e30)
    var high = V3(-1e30, -1e30, -1e30)
    for part in range(SURFACE_PART_COUNT):  # pragma: no branch
        var ids = List[Int]()
        var solids = 0
        for i in posed.part_list(SurfacePart(part)):
            if input.density[i] > 0.0 or posed.prims[i].carve:
                ids.append(i)
                solids += 0 if posed.prims[i].carve else 1
            else:
                # Weightless solids still bound the total length.
                input.coat.append(i)
        if solids == 0:
            continue
        var box = part_box(posed, ids)
        low = V3(
            min(low.x, box[0].x), min(low.y, box[0].y), min(low.z, box[0].z)
        )
        high = V3(
            max(high.x, box[1].x), max(high.y, box[1].y), max(high.z, box[1].z)
        )
        input.erode.append(coat if _erodes(SurfacePart(part)) else 0.0)
        input.parts.append(ids^)
    if len(input.parts) == 0:
        raise Error("The sculpt has no flesh to weigh")
    if len(input.coat) > 0:
        var box = part_box(posed, input.coat)
        low = V3(
            min(low.x, box[0].x), min(low.y, box[0].y), min(low.z, box[0].z)
        )
        high = V3(
            max(high.x, box[1].x), max(high.y, box[1].y), max(high.z, box[1].z)
        )
    var nx = Int(ceil((high.x - low.x) / h))
    var ny = Int(ceil((high.y - low.y) / h))
    var nz = Int(ceil((high.z - low.z) / h))
    if max(nx, max(ny, nz)) > 400:
        raise Error("A mass grid must be at most 400 cells a side")
    var grid = _Grid(
        low,
        h,
        nx,
        ny,
        nz,
        (nx + BLOCK - 1) // BLOCK,
        (ny + BLOCK - 1) // BLOCK,
        (nz + BLOCK - 1) // BLOCK,
    )
    var blocks = grid.bx * grid.by * grid.bz
    var threads = workers if workers > 0 else num_logical_cores()
    var tasks = max(1, min(threads, blocks))
    var bones = len(animal.rig.bones)
    var tallies = List[InertiaTally](capacity=tasks * bones)
    for _ in range(tasks * bones):  # pragma: no branch
        tallies.append(InertiaTally())
    var stats = List[Float64](length=tasks * STATS, fill=0.0)
    _launch(posed, input, grid, tallies, stats, bones)
    var out = List[InertiaTally](capacity=bones)
    for b in range(bones):  # pragma: no branch
        var sum = InertiaTally()
        for task in range(tasks):  # pragma: no branch
            sum.add(tallies[task * bones + b])
        out.append(sum^)
    var total = _fresh_stats()
    for task in range(tasks):  # pragma: no branch
        var at = task * STATS
        total[GROUND] = min(total[GROUND], stats[at + GROUND])
        total[WITHERS] = max(total[WITHERS], stats[at + WITHERS])
        total[BODY_LOW] = min(total[BODY_LOW], stats[at + BODY_LOW])
        total[BODY_HIGH] = max(total[BODY_HIGH], stats[at + BODY_HIGH])
        total[TOTAL_LOW] = min(total[TOTAL_LOW], stats[at + TOTAL_LOW])
        total[TOTAL_HIGH] = max(total[TOTAL_HIGH], stats[at + TOTAL_HIGH])
        total[VOLUME] += stats[at + VOLUME]
    if total[VOLUME] <= 0.0:
        raise Error("The sculpt has no flesh to weigh")
    return BodyMass(out^, step, total)
