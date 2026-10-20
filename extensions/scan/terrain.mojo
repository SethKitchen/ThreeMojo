# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ground of a scanned place, as a height for each plan column, so
that the parts of a scan of a hillside stand on the hill.

A room has a flat floor, and `detect_levels` finds it as one layer. A
hillside has no flat layer: its ground slopes.
`terrain_ground` finds that ground as a surface:

1. The top of a column is its highest solid voxel.
2. Two columns side by side are on one surface when their tops differ by
   `TerrainOptions.step` or less. A wall is a larger step, so the roof of
   a building is a surface of its own.
3. A surface whose plan area is `TerrainOptions.min_area` or more is
   ground. A roof is smaller than that, and a hillside is larger.
4. A column of the ground keeps its top. Each other column takes its
   height from the nearest columns of the ground: the lowest of them. So
   the ground goes on under a building, at the foot of its lowest wall.

The ground under a building is not seen, so the foot of a wall on a slope
can be a layer or two above the height that its column takes. The
surface's tolerance is the layers in one step: a foot that close to the
ground bears on it.

`flat_ground` gives a surface at one layer, such as the floor that
`detect_levels` finds. `scan_parts_on` in `extensions.scan.parts` cuts a
grid into the parts above a surface.
"""

from extensions.scan.occupancy import OccupancyGrid
from math.finite import require_positive_finite
from std.math import floor
from units.si import Area64, Length64, METER, SQUARE_METER


@fieldwise_init
struct TerrainOptions(ImplicitlyCopyable):
    """How `terrain_ground` finds the ground; see the module docstring."""

    var step: Length64
    """The most that the tops of two columns side by side on one surface differ by."""
    var min_area: Area64
    """The least plan area of a surface that is ground."""

    def check(self) raises:
        """Refuse options that cannot find a ground.

        Raises:
            Error: If the step or the area is not positive and finite.
        """
        require_positive_finite(
            self.step.to(METER), "Terrain: the step must be positive"
        )
        require_positive_finite(
            self.min_area.to(SQUARE_METER),
            "Terrain: the least area must be positive",
        )


struct GroundSurface(Copyable, Movable):
    """The ground's top layer in each plan column of a grid."""

    var nx: Int
    """How many columns along x."""
    var ny: Int
    """How many columns along y."""
    var layers: List[Int]
    """For each column, `j * nx + i`, the ground's top layer, or -1 where no voxel is ground."""
    var tolerance: Int
    """How many layers above the ground the foot of a part can be and still bear on it."""

    def __init__(
        out self, nx: Int, ny: Int, var layers: List[Int], tolerance: Int
    ) raises:
        """Hold a ground surface.

        Args:
            nx: Columns along x.
            ny: Columns along y.
            layers: The top layer of each column, `nx * ny` of them.
            tolerance: The layers between the ground and a foot that
                bears on it, 0 or more.

        Raises:
            Error: If a count is not positive, there is not one layer for
                each column, or the tolerance is negative.
        """
        if nx < 1 or ny < 1:
            raise Error("Terrain: a ground has one column at least each way")
        if len(layers) != nx * ny:
            raise Error(
                "Terrain: a ground of "
                + String(nx * ny)
                + " columns has "
                + String(len(layers))
                + " layers"
            )
        if tolerance < 0:
            raise Error("Terrain: a tolerance is 0 layers or more")
        self.nx = nx
        self.ny = ny
        self.layers = layers^
        self.tolerance = tolerance

    def layer(self, i: Int, j: Int) -> Int:
        """Return the ground's top layer in a column.

        Args:
            i: The column's index along x, 0 to below `nx`.
            j: The column's index along y, 0 to below `ny`.

        Returns:
            The layer, or -1.
        """
        return self.layers[j * self.nx + i]

    def check(self, grid: OccupancyGrid) raises:
        """Refuse a surface that is not a ground of a grid.

        Args:
            grid: The grid.

        Raises:
            Error: If the surface has other columns than the grid, or a
                layer is not -1 to the grid's top layer.
        """
        if self.nx != grid.nx or self.ny != grid.ny:
            raise Error(
                "Terrain: a ground of "
                + String(self.nx)
                + " by "
                + String(self.ny)
                + " columns is not the ground of a grid of "
                + String(grid.nx)
                + " by "
                + String(grid.ny)
            )
        for layer in self.layers:  # pragma: no branch
            if layer < -1 or layer >= grid.nz:
                raise Error(
                    "Terrain: a ground layer must be -1 to "
                    + String(grid.nz - 1)
                )


def flat_ground(grid: OccupancyGrid, layer: Int) raises -> GroundSurface:
    """Return a flat ground: one layer in each column, with no
    tolerance.

    Args:
        grid: The grid.
        layer: The ground's layer: a voxel in it or below it is ground.
            -1 counts no voxel as ground.

    Returns:
        The surface.

    Raises:
        Error: If the layer is not -1 to the grid's top layer.
    """
    if layer < -1 or layer >= grid.nz:
        raise Error(
            "Terrain: a ground layer must be -1 to " + String(grid.nz - 1)
        )
    return GroundSurface(
        grid.nx, grid.ny, List[Int](length=grid.nx * grid.ny, fill=layer), 0
    )


def column_tops(grid: OccupancyGrid) -> List[Int]:
    """Return the highest solid voxel of each plan column.

    Args:
        grid: The grid.

    Returns:
        For each column, `j * nx + i`, its highest solid layer, or -1 for
        a column with no solid voxel.
    """
    var columns = grid.nx * grid.ny
    var tops = List[Int](length=columns, fill=-1)
    for index in range(len(grid.weights)):  # pragma: no branch
        if Float64(grid.weights[index]) >= grid.solid_weight:
            # Layers rise with the index, so the last solid voxel is the top.
            tops[index % columns] = index // columns
    return tops^


def _beside(nx: Int, ny: Int, column: Int, side: Int) -> Int:
    """Return the column beyond a side of a column, or -1 past the grid.

    Args:
        nx: Columns along x.
        ny: Columns along y.
        column: The column, `j * nx + i`.
        side: 0 to 3: +x, -x, +y and -y.

    Returns:
        The column beside it, or -1.
    """
    var i = column % nx
    var j = column // nx
    if side == 0:
        i += 1
    elif side == 1:
        i -= 1
    elif side == 2:
        j += 1
    else:
        j -= 1
    if i < 0 or j < 0 or i >= nx or j >= ny:
        return -1
    return j * nx + i


def terrain_ground(
    grid: OccupancyGrid, options: TerrainOptions
) raises -> GroundSurface:
    """Find a grid's ground as a surface; see the module docstring.

    Args:
        grid: The grid.
        options: The largest step of a surface, and the least area of
            ground.

    Returns:
        The surface. With no surface of ground, each layer is -1. Its
        tolerance is the whole layers in a step.

    Raises:
        Error: If the options are refused.
    """
    options.check()
    var edge = grid.voxel.to(METER)
    var step = options.step.to(METER)
    var nx = grid.nx
    var ny = grid.ny
    var columns = nx * ny
    var tops = column_tops(grid)
    # Join the columns into surfaces.
    var surface = List[Int](length=columns, fill=-1)
    var sizes = List[Int]()
    var stack = List[Int]()
    for seed in range(columns):  # pragma: no branch
        if tops[seed] < 0 or surface[seed] >= 0:
            continue
        var label = len(sizes)
        var size = 0
        surface[seed] = label
        stack.append(seed)
        while len(stack) > 0:
            var column = stack.pop()
            size += 1
            for side in range(4):  # pragma: no branch
                var next = _beside(nx, ny, column, side)
                if (
                    next >= 0
                    and surface[next] < 0
                    and tops[next] >= 0
                    and Float64(abs(tops[next] - tops[column])) * edge <= step
                ):
                    surface[next] = label
                    stack.append(next)
        sizes.append(size)
    # The large surfaces are ground. The others take the height of the
    # nearest ground, breadth first, the lowest of a ring.
    var area = options.min_area.to(SQUARE_METER)
    var layers = List[Int](length=columns, fill=-1)
    var ring = List[Int](length=columns, fill=-1)
    var front = List[Int]()
    for column in range(columns):  # pragma: no branch
        if (
            tops[column] >= 0
            and Float64(sizes[surface[column]]) * edge * edge >= area
        ):
            layers[column] = tops[column]
            ring[column] = 0
            front.append(column)
    var distance = 0
    while len(front) > 0:
        distance += 1
        var next_front = List[Int]()
        for column in front:  # pragma: no branch
            for side in range(4):  # pragma: no branch
                var next = _beside(nx, ny, column, side)
                if next < 0:
                    continue
                if ring[next] < 0:
                    ring[next] = distance
                    layers[next] = layers[column]
                    next_front.append(next)
                elif ring[next] == distance:
                    layers[next] = min(layers[next], layers[column])
        front = next_front^
    return GroundSurface(nx, ny, layers^, Int(floor(step / edge)))


def ground_grid(
    grid: OccupancyGrid, ground: GroundSurface
) raises -> OccupancyGrid:
    """Return the ground as a grid: each column solid up to its ground
    layer.

    The ground goes on under each building, where the scan saw nothing,
    so a part stands on it as on the ground the building stands on.
    `extensions.scan.colliders` makes its mesh.

    Args:
        grid: The grid the ground is of.
        ground: The ground.

    Returns:
        A grid with the box, the voxel and the solid weight of `grid`.
        Each voxel in or below its column's ground layer has the solid
        weight, and each other voxel is empty.

    Raises:
        Error: If the ground is not a ground of the grid.
    """
    ground.check(grid)
    var out = OccupancyGrid(
        grid.origin, grid.voxel, grid.nx, grid.ny, grid.nz, grid.solid_weight
    )
    var columns = grid.nx * grid.ny
    for index in range(len(out.weights)):  # pragma: no branch
        if index // columns <= ground.layers[index % columns]:
            out.weights[index] = Float32(grid.solid_weight)
    return out^
