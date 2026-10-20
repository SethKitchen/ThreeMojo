# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A canonical building model fitted to a scan.

`fit_building` turns the levels of a scan into storeys, and each storey
into one space, and gives them to `assemble` with a construction kit. The
model then has walls, slabs and a roof of the kit's constructions, and
every view of `extensions.building` reads it.

- **Storeys.** Each floor starts a storey. A storey ends at the next
  floor. The top storey ends at the first ceiling above its floor, or at
  the top of the scan when it has none.
- **Plans.** A storey's plan is the rectangle that holds its floor faces:
  the plan columns whose floor-layer voxel is a floor face. A
  fraction `trim` of those columns is left out at each end of each axis,
  so a few stray voxels do not stretch it. Furniture hides the floor
  under it, so the rectangle is the floor and not only what the scan saw.
  `fill` gives the share of the rectangle that the scan saw as floor.
- **Outside scans.** The plan is the rectangle of the columns that hold a
  solid voxel at least half of `min_storey` above the ground.

The plan is a rectangle on the building axes. Turn a scan's frame by its
estimated heading first, so its walls lie along x and y.

The model records where its numbers came from in `notes`: the scale
source of the frame, the fill of each storey and the kit.
"""

from extensions.building.kits import ConstructionKit
from extensions.building.kinds import SpaceUse
from extensions.building.model import (
    Building,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
)
from extensions.building.scan.levels import (
    LevelOptions,
    ScanLevels,
    clear_layers,
    is_floor_face,
    separation_layers,
)
from extensions.scan.frame import SCALE_ASSUMED, SCALE_DECLARED, ScaleSource
from extensions.scan.occupancy import OccupancyGrid
from extensions.topology.arrangement import Point2
from std.math import floor
from units.si import Length64, METER


@fieldwise_init
struct ScanFitOptions(Copyable, Movable):
    """How a scan becomes a building model."""

    var name: String
    """The model's name."""
    var site: Site
    """Where the building stands."""
    var use: SpaceUse
    """What each storey's space is used for."""
    var trim: Float64
    """The fraction, 0 to under one half, of floor columns left out at each end of each axis."""
    var levels: LevelOptions
    """The levels' options: an outside scan's plan starts half the least storey above the ground."""

    def check(self) raises:
        """Refuse options that cannot fit a model.

        Raises:
            Error: If the site, the use or the level options are not valid,
                or the trim is not 0 to under one half.
        """
        self.site.check()
        if not self.use.is_valid():
            raise Error("Scan fit: a space use is not valid")
        if not (self.trim >= 0 and self.trim < 0.5):
            raise Error("Scan fit: the trim must be 0 to under one half")
        self.levels.check()


struct ScanFit(Movable):
    """A building model fitted to a scan, and how well it fits."""

    var building: Building
    """The model."""
    var levels: ScanLevels
    """The levels it was fitted to."""
    var fill: List[Float64]
    """For each storey, the share of its rectangle that the scan saw as floor, or as the building for an outside scan."""
    var scale: ScaleSource
    """Where the scan's unit came from."""
    var notes: List[String]
    """What a reader must know before using the model's numbers."""

    def __init__(
        out self,
        var building: Building,
        var levels: ScanLevels,
        var fill: List[Float64],
        scale: ScaleSource,
        var notes: List[String],
    ):
        """Hold a fitted model.

        Args:
            building: The model.
            levels: Its levels.
            fill: Each storey's fill.
            scale: The scale source.
            notes: The notes.
        """
        self.building = building^
        self.levels = levels^
        self.fill = fill^
        self.scale = scale
        self.notes = notes^


@fieldwise_init
struct _Plan(ImplicitlyCopyable):
    """A storey's rectangle, as voxel columns, and its fill."""

    var i0: Int
    """The first column along x."""
    var i1: Int
    """The last column along x."""
    var j0: Int
    """The first column along y."""
    var j1: Int
    """The last column along y."""
    var fill: Float64
    """The share of the rectangle's columns that are set."""


def _trimmed_index(values: List[Int], trim: Float64) -> Tuple[Int, Int]:
    """Return the range of indexes with a fraction left out at each end.

    Args:
        values: At least one index.
        trim: The fraction, 0 to under one half.

    Returns:
        The least and the most of the kept indexes.
    """
    var sorted = values.copy()
    sort(sorted)
    var cut = Int(floor(trim * Float64(len(sorted))))
    return (sorted[cut], sorted[len(sorted) - 1 - cut])


def _plan(grid: OccupancyGrid, mask: List[Bool], trim: Float64) raises -> _Plan:
    """Return the rectangle that holds a plan mask.

    Args:
        grid: The grid.
        mask: One flag for each plan column, x fastest.
        trim: The fraction left out at each end.

    Returns:
        The rectangle.

    Raises:
        Error: If no column is set.
    """
    var xs = List[Int]()
    var ys = List[Int]()
    for j in range(grid.ny):  # pragma: no branch
        for i in range(grid.nx):  # pragma: no branch
            if mask[j * grid.nx + i]:
                xs.append(i)
                ys.append(j)
    if len(xs) == 0:
        raise Error("Scan fit: a storey has no floor to fit")
    var x = _trimmed_index(xs, trim)
    var y = _trimmed_index(ys, trim)
    var inside = 0
    for j in range(y[0], y[1] + 1):  # pragma: no branch
        for i in range(x[0], x[1] + 1):  # pragma: no branch
            if mask[j * grid.nx + i]:
                inside += 1
    var cells = (x[1] - x[0] + 1) * (y[1] - y[0] + 1)
    return _Plan(x[0], x[1], y[0], y[1], Float64(inside) / Float64(cells))


def _floor_mask(grid: OccupancyGrid, layer: Int, clear: Int) -> List[Bool]:
    """Return the plan columns whose voxel in a layer is a floor face.

    Args:
        grid: The grid.
        layer: The floor's layer.
        clear: The least number of empty layers above a floor face.

    Returns:
        One flag for each column, x fastest.
    """
    var mask = List[Bool](length=grid.nx * grid.ny, fill=False)
    for j in range(grid.ny):  # pragma: no branch
        for i in range(grid.nx):  # pragma: no branch
            mask[j * grid.nx + i] = is_floor_face(grid, i, j, layer, clear)
    return mask^


def _mass_mask(grid: OccupancyGrid, start: Int) -> List[Bool]:
    """Return the plan columns that hold a solid voxel from a layer up.

    Args:
        grid: The grid.
        start: The lowest layer looked at.

    Returns:
        One flag for each column, x fastest.
    """
    var mask = List[Bool](length=grid.nx * grid.ny, fill=False)
    for j in range(grid.ny):  # pragma: no branch
        for i in range(grid.nx):  # pragma: no branch
            for k in range(start, grid.nz):
                if grid.is_solid(i, j, k):
                    mask[j * grid.nx + i] = True
                    break
    return mask^


def _height(
    grid: OccupancyGrid, levels: ScanLevels, storey: Int
) raises -> Length64:
    """Return a storey's height: to the next floor, the first ceiling
    above, or the top of the scan.

    Args:
        grid: The grid.
        levels: The levels.
        storey: Which storey.

    Returns:
        The height.

    Raises:
        Error: If the storey has no height.
    """
    var floor = levels.floor_elevation(grid, storey)
    var end = levels.top_elevation(grid)
    if storey + 1 < len(levels.floors):
        end = levels.floor_elevation(grid, storey + 1)
    else:
        for c in range(len(levels.ceilings)):
            if levels.ceilings[c] > levels.floors[storey]:
                end = levels.ceiling_elevation(grid, c)
                break
    var height = end - floor
    if height.to(METER) <= 0:
        raise Error("Scan fit: storey " + String(storey) + " has no height")
    return height


def fit_building(
    grid: OccupancyGrid,
    levels: ScanLevels,
    kit: ConstructionKit,
    scale: ScaleSource,
    options: ScanFitOptions,
) raises -> ScanFit:
    """Return a building model fitted to a scan's levels.

    Args:
        grid: The scan's occupancy grid.
        levels: Its floors and ceilings, from `detect_levels`.
        kit: The constructions the model is made of.
        scale: Where the scan's unit came from.
        options: The name, the site, the use and the trim.

    Returns:
        The model; see the module docstring.

    Raises:
        Error: If the options, the kit or the scale source are not valid,
            the levels have no floor, a storey has no floor or no height,
            or `assemble` refuses the plans.
    """
    options.check()
    kit.check()
    if not scale.is_valid():
        raise Error("Scan fit: a scale source is 0 to 2")
    if len(levels.floors) == 0:
        raise Error("Scan fit: the levels have no floor")
    var edge = grid.voxel.to(METER)
    var plans = List[StoreyPlan]()
    var fill = List[Float64]()
    var notes = List[String]()
    for storey in range(len(levels.floors)):  # pragma: no branch
        var mask: List[Bool]
        if levels.exterior:
            var rise = separation_layers(grid, options.levels) // 2
            mask = _mass_mask(grid, levels.floors[storey] + 1 + rise)
        else:
            mask = _floor_mask(
                grid, levels.floors[storey], clear_layers(grid, options.levels)
            )
        var plan = _plan(grid, mask, options.trim)
        var x0 = grid.origin.x + Float64(plan.i0) * edge
        var x1 = grid.origin.x + Float64(plan.i1 + 1) * edge
        var y0 = grid.origin.y + Float64(plan.j0) * edge
        var y1 = grid.origin.y + Float64(plan.j1 + 1) * edge
        var outline: List[Point2] = [
            Point2(x0, y0),
            Point2(x1, y0),
            Point2(x1, y1),
            Point2(x0, y1),
        ]
        var spaces = List[SpacePlan]()
        spaces.append(
            SpacePlan(String("scanned space ", storey), options.use, outline^)
        )
        plans.append(
            StoreyPlan(
                String("storey ", storey),
                _height(grid, levels, storey),
                spaces^,
            )
        )
        fill.append(plan.fill)
        notes.append(
            String(
                "Storey ",
                storey,
                " is the rectangle that holds its floor; the scan saw ",
                Int(plan.fill * 100 + 0.5),
                " percent of it.",
            )
        )
    if levels.exterior:
        notes.append(
            "No floor has a ceiling above it, so the scan is an outside"
            " view: one storey from the ground to the top."
        )
    if scale == SCALE_DECLARED:
        notes.append(
            "The scale is declared, not measured: check one length in the"
            " place before using a load or a mass."
        )
    elif scale == SCALE_ASSUMED:
        notes.append(
            "The scale comes from an assumed length: every length,"
            " load and mass follows that assumption."
        )
    notes.append(
        String(
            "The constructions are the ",
            kit.kind.name(),
            " kit's, assumed and not measured.",
        )
    )
    var building = assemble(
        options.name,
        options.site,
        levels.floor_elevation(grid, 0),
        plans,
        kit.materials.copy(),
        kit.constructions.copy(),
        kit.defaults,
        Length64(1e-6, METER),
    )
    return ScanFit(building^, levels.copy(), fill^, scale, notes^)
