# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the scanned-building examples share: opening a cached scan, cleaning
it, and filling its occupancy grid.

`open_scan` takes a catalog id or the path of a scan file, reads it, leaves
out the splats that are not the building (`clean_scan`), and gives the
catalog's frame, or SuperSplat's frame for a path. `fill_grid` fills the
occupancy grid of the cleaned splats, with the voxel grown until the grid
fits, and finds the floor.
"""

from core.gaussian_splat_utils import GaussianSplatGeometry
from extensions.building.scan.catalog import (
    CATALOG_CACHE,
    CATALOG_MANIFEST,
    ScanCatalog,
)
from extensions.building.scan.levels import default_level_options, detect_levels
from extensions.scan.clean import CleanReport, clean_scan, default_clean_options
from extensions.scan.files import read_scan
from extensions.scan.frame import ScanFrame, estimate_heading, supersplat_frame
from extensions.scan.occupancy import (
    OccupancyGrid,
    ScanRegion,
    default_occupancy_options,
    occupancy_grid,
    trimmed_region,
)
from units.si import Length64, METER

comptime DEFAULT_MAX_VOXELS = 1 << 25
"""The most voxels an example's grid holds."""


struct OpenedScan(Movable):
    """A scan, cleaned, with its frame and its credit."""

    var splats: GaussianSplatGeometry
    """The kept splats, in the scan's coordinates."""
    var frame: ScanFrame
    """The scan's frame."""
    var title: String
    """The scan's title, or the path that was given."""
    var author: String
    """The scan's author, or empty for a path."""
    var report: CleanReport
    """What the cleaning kept and left out."""

    def __init__(
        out self,
        var splats: GaussianSplatGeometry,
        frame: ScanFrame,
        var title: String,
        var author: String,
        report: CleanReport,
    ):
        """Hold an opened scan.

        Args:
            splats: The kept splats.
            frame: The frame.
            title: The title.
            author: The author.
            report: The cleaning report.
        """
        self.splats = splats^
        self.frame = frame
        self.title = title^
        self.author = author^
        self.report = report


def open_scan(wanted: String) raises -> OpenedScan:
    """Read and clean a scan.

    Args:
        wanted: The id of a scan in the catalog, or the path of a scan file
            of any format that `extensions.scan.files` reads.

    Returns:
        The cleaned scan, with its frame.

    Raises:
        Error: If the id is in the catalog and the scan is not cached, the
            file cannot be read, or the cleaning keeps no splat.
    """
    var catalog = ScanCatalog.open(CATALOG_MANIFEST, CATALOG_CACHE)
    var path = wanted
    var frame = supersplat_frame()
    var title = wanted
    var author = String()
    for entry in catalog.entries:
        if entry.id == wanted:
            var cached = catalog.scene(wanted)
            if not cached:
                raise Error(
                    "The scan '"
                    + wanted
                    + "' is not cached: sh tools/tool.sh .venv/bin/mojo"
                    " building_scans fetch "
                    + wanted
                    + " --pin"
                )
            path = cached.value()
            frame = entry.frame
            title = entry.title
            author = entry.author
    var scan = read_scan(path)
    var cleaned = clean_scan(scan.geometry, default_clean_options())
    return OpenedScan(
        cleaned.geometry.copy(), frame, title^, author^, cleaned.report
    )


struct FilledGrid(Movable):
    """A scan's occupancy grid, its box and its floor."""

    var grid: OccupancyGrid
    """The grid, in building coordinates."""
    var region: ScanRegion
    """The box of the scan, in meters."""
    var floor: Length64
    """The elevation of the first floor."""

    def __init__(
        out self,
        var grid: OccupancyGrid,
        region: ScanRegion,
        floor: Length64,
    ):
        """Hold a filled grid.

        Args:
            grid: The grid.
            region: The box.
            floor: The first floor's elevation.
        """
        self.grid = grid^
        self.region = region
        self.floor = floor


def fill_grid(
    mut scan: OpenedScan, max_voxels: Int = DEFAULT_MAX_VOXELS
) raises -> FilledGrid:
    """Fill the occupancy grid of an opened scan and find its first floor.

    The scan's frame is turned onto the walls' heading first. The voxel
    starts at 0.1 m and doubles until the grid has at most `max_voxels`.

    Args:
        scan: The scan; its frame's heading is set.
        max_voxels: The most voxels the grid may hold.

    Returns:
        The grid, its box and its floor.

    Raises:
        Error: If the heading cannot be found, no floor is found, or the
            grid cannot be filled.
    """
    scan.frame.heading = estimate_heading(scan.splats, scan.frame)
    var options = default_occupancy_options()
    options.max_voxels = max_voxels
    var region = trimmed_region(scan.splats, scan.frame, options)
    var size = region.high - region.low
    var edge = options.voxel.to(METER)
    while (size.x / edge) * (size.y / edge) * (size.z / edge) > Float64(
        max_voxels
    ):
        edge *= 2
    options.voxel = Length64(edge, METER)
    var grid = occupancy_grid(scan.splats, scan.frame, options, region)
    var levels = detect_levels(grid, default_level_options())
    var floor = levels.floor_elevation(grid, 0)
    return FilledGrid(grid^, region, floor)
