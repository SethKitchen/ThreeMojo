# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The floors and the ceilings of a scanned place, from its occupancy
grid.

Look down one column of voxels. A solid voxel with an empty voxel above
it has a face that looks up. It is a floor face when the next solid voxel
above it, the ceiling that the scanner saw from inside, is at least
`min_clear` above it. The face on top of the highest ceiling looks up at
nothing, so it is not a floor. The top of a ceiling, under the unseen
inside of a slab, has the floor above it too close, so it is not a floor
either. In the same way, a solid voxel with an empty voxel below it has a
ceiling face when the next solid voxel below it is at least `min_clear`
below.

The faces are counted layer by layer. A layer is a floor when its count
is at least `min_fraction` of the plan columns that hold a solid voxel.
Floors closer than `min_storey` are one floor: the layer with the most
faces is kept, and a tie keeps the lower layer. Ceilings are found the
same way.

**Outside scans.** A drone flies around a building, not through it, so
no floor has a ceiling above it. Then the lowest layer whose upward faces
reach `min_fraction` is the ground, and `exterior` is True.
"""

from extensions.scan.occupancy import OccupancyGrid
from math.finite import require_positive_finite
from std.math import ceil
from units.si import Length64, METER


@fieldwise_init
struct LevelOptions(ImplicitlyCopyable):
    """How floors and ceilings are found; see the module docstring."""

    var min_fraction: Float64
    """The least share, above 0 and at most 1, of the plan columns that a floor or a ceiling covers."""
    var min_storey: Length64
    """The least distance between two floors, or two ceilings."""
    var min_clear: Length64
    """The least empty height above a floor face, or below a ceiling face."""

    def check(self) raises:
        """Refuse options that find no level.

        Raises:
            Error: If the fraction is not above 0 and at most 1, or the
                storey or the clear height is not positive and finite.
        """
        if not (self.min_fraction > 0 and self.min_fraction <= 1):
            raise Error("Levels: the fraction must be above 0 and at most 1")
        require_positive_finite(
            self.min_storey.to(METER), "Levels: the storey must be positive"
        )
        require_positive_finite(
            self.min_clear.to(METER),
            "Levels: the clear height must be positive",
        )


def default_level_options() -> LevelOptions:
    """Return options for rooms and storeys.

    Returns:
        A quarter of the plan, two meters between levels and one meter of
        clear height.
    """
    return LevelOptions(0.25, Length64(2, METER), Length64(1, METER))


struct ScanLevels(Copyable, Movable):
    """The voxel layers of a scan's floors and ceilings."""

    var floors: List[Int]
    """The layer whose top face is each floor, from the lowest up."""
    var ceilings: List[Int]
    """The layer whose bottom face is each ceiling, from the lowest up."""
    var top: Int
    """The highest layer that holds a solid voxel."""
    var columns: Int
    """How many plan columns hold a solid voxel."""
    var exterior: Bool
    """True when no floor has a ceiling above it, and the one floor is the ground of an outside scan."""

    def __init__(
        out self,
        var floors: List[Int],
        var ceilings: List[Int],
        top: Int,
        columns: Int,
        exterior: Bool,
    ):
        """Hold the levels.

        Args:
            floors: The floor layers.
            ceilings: The ceiling layers.
            top: The highest solid layer.
            columns: The solid plan columns.
            exterior: Whether the scan is an outside scan.
        """
        self.floors = floors^
        self.ceilings = ceilings^
        self.top = top
        self.columns = columns
        self.exterior = exterior

    def floor_elevation(self, grid: OccupancyGrid, floor: Int) -> Length64:
        """Return the elevation of a floor's face.

        Args:
            grid: The grid the levels came from.
            floor: Which floor, from zero.

        Returns:
            The top of the floor's layer.
        """
        var edge = grid.voxel.to(METER)
        return Length64(
            grid.origin.z + Float64(self.floors[floor] + 1) * edge, METER
        )

    def ceiling_elevation(self, grid: OccupancyGrid, ceiling: Int) -> Length64:
        """Return the elevation of a ceiling's face.

        Args:
            grid: The grid the levels came from.
            ceiling: Which ceiling, from zero.

        Returns:
            The bottom of the ceiling's layer.
        """
        var edge = grid.voxel.to(METER)
        return Length64(
            grid.origin.z + Float64(self.ceilings[ceiling]) * edge, METER
        )

    def top_elevation(self, grid: OccupancyGrid) -> Length64:
        """Return the elevation of the top of the highest solid layer.

        Args:
            grid: The grid the levels came from.

        Returns:
            The elevation.
        """
        var edge = grid.voxel.to(METER)
        return Length64(grid.origin.z + Float64(self.top + 1) * edge, METER)


def _layers(length: Length64, grid: OccupancyGrid) -> Int:
    """Return how many layers a length spans, at least one."""
    return max(1, Int(ceil(length.to(METER) / grid.voxel.to(METER))))


def separation_layers(grid: OccupancyGrid, options: LevelOptions) -> Int:
    """Return how many layers the least storey spans.

    Args:
        grid: The grid.
        options: The least storey.

    Returns:
        At least one.
    """
    return _layers(options.min_storey, grid)


def clear_layers(grid: OccupancyGrid, options: LevelOptions) -> Int:
    """Return how many empty layers the least clear height spans.

    Args:
        grid: The grid.
        options: The least clear height.

    Returns:
        At least one.
    """
    return _layers(options.min_clear, grid)


def is_floor_face(
    grid: OccupancyGrid, i: Int, j: Int, k: Int, clear: Int
) -> Bool:
    """Return True if a voxel's top is a floor face; see the module
    docstring.

    Args:
        grid: The grid.
        i: The column's index along x.
        j: The column's index along y.
        k: The voxel's layer.
        clear: The least number of empty layers above it.

    Returns:
        Whether the voxel is solid, the `clear` layers above it are empty,
        and a solid voxel is somewhere above those.
    """
    if not grid.is_solid(i, j, k):
        return False
    for above in range(k + 1, k + clear + 1):
        if grid.is_solid(i, j, above):
            return False
    for above in range(k + clear + 1, grid.nz):
        if grid.is_solid(i, j, above):
            return True
    return False


def _peaks(counts: List[Int], threshold: Float64, separation: Int) -> List[Int]:
    """Return the layers whose count reaches a threshold, at least
    `separation` apart, the larger count first and then the lower layer.

    Args:
        counts: A count for each layer.
        threshold: The least count.
        separation: The least distance between two kept layers.

    Returns:
        The kept layers, from the lowest up.
    """
    var taken = List[Bool](length=len(counts), fill=False)
    var kept = List[Int]()
    while True:
        var best = -1
        for layer in range(len(counts)):  # pragma: no branch
            if taken[layer] or Float64(counts[layer]) < threshold:
                continue
            if best < 0 or counts[layer] > counts[best]:
                best = layer
        if best < 0:
            break
        taken[best] = True
        var near = False
        for other in kept:
            if abs(other - best) < separation:
                near = True
        if not near:
            kept.append(best)
    sort(kept)
    return kept^


def detect_levels(
    grid: OccupancyGrid, options: LevelOptions
) raises -> ScanLevels:
    """Return the floors and the ceilings of a scan.

    Args:
        grid: The scan's occupancy grid, z up.
        options: The least share of the plan and the least storey.

    Returns:
        The levels; see the module docstring.

    Raises:
        Error: If the options are not valid, no voxel is solid, or no
            layer covers enough of the plan to be a floor or the ground.
    """
    options.check()
    var clear = clear_layers(grid, options)
    var up = List[Int](length=grid.nz, fill=0)
    var down = List[Int](length=grid.nz, fill=0)
    var ground = List[Int](length=grid.nz, fill=0)
    var columns = 0
    var top = -1
    for j in range(grid.ny):  # pragma: no branch
        for i in range(grid.nx):  # pragma: no branch
            # The runs of solid voxels in the column, from the bottom up.
            var starts = List[Int]()
            var ends = List[Int]()
            for k in range(grid.nz):  # pragma: no branch
                if not grid.is_solid(i, j, k):
                    continue
                if len(ends) > 0 and ends[len(ends) - 1] == k - 1:
                    ends[len(ends) - 1] = k
                else:
                    starts.append(k)
                    ends.append(k)
            if len(starts) == 0:
                continue
            columns += 1
            top = max(top, ends[len(ends) - 1])
            for run in range(len(starts)):  # pragma: no branch
                if run + 1 == len(starts):
                    ground[ends[run]] += 1
                elif starts[run + 1] - ends[run] - 1 >= clear:
                    up[ends[run]] += 1
                if run > 0 and starts[run] - ends[run - 1] - 1 >= clear:
                    down[starts[run]] += 1
    if columns == 0:
        raise Error("Levels: no voxel is solid")
    var threshold = options.min_fraction * Float64(columns)
    var separation = separation_layers(grid, options)
    var floors = _peaks(up, threshold, separation)
    var ceilings = _peaks(down, threshold, separation)
    var exterior = False
    if len(floors) == 0:
        var grounds = _peaks(ground, threshold, separation)
        if len(grounds) == 0:
            raise Error("Levels: no layer covers enough of the plan")
        floors = [grounds[0]]
        exterior = True
    return ScanLevels(floors^, ceilings^, top, columns, exterior)
