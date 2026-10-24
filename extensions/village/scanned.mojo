# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scanned building in the village: cut out of its scan, and stood on a
lot.

A scan of a building holds its ground too: a churchyard's paths and
graves, a lawn, a street. `cut_building` keeps only the building. It fills
an occupancy grid of the scan, finds its ground as a terrain surface, cuts
the grid into parts above the ground, and copies the splats of the
largest part: see `extensions.scan.parts`. A village's buildings are seen
from outside, so a scan of a room, whose ground is its floor, is not for
it.

`stand_scan` stands the cut building in a scene as one node: the middle of
its footprint at a point, turned about +y, and its foot `SINK` below the
lowest ground under its corners, so no gap shows on a slope. It returns
the lot the building stands on, so the meadow grows nothing there.

**Colors.** A scan's colors are what a screen shows: sRGB. The renderer
blends splats as light, and tone maps the frame after, as it does the
meadow. So `stand_scan` gives the scene a copy whose colors are turned to
linear light first (`linear_splats`). The copy carries no spherical
harmonics: their shading adds to the sRGB color, and has no exact linear
form. The building loses its view-dependent sheen and keeps its colors.
"""

from core.gaussian_splat_utils import GaussianSplatGeometry
from core.object3d import Object3D
from core.scene import Scene
from extensions.scan.frame import ScanFrame
from extensions.scan.occupancy import (
    OccupancyGrid,
    ScanRegion,
    default_occupancy_options,
    occupancy_grid,
    trimmed_region,
)
from extensions.scan.parts import part_splats, scan_parts_on
from extensions.scan.place import scan_placement
from extensions.scan.terrain import (
    GroundSurface,
    TerrainOptions,
    column_tops,
    terrain_ground,
)
from extensions.vegetation.ground import Ground, Lot
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from render.srgb import srgb_to_linear
from std.math import cos, sin
from units.si import (
    METER,
    RADIAN,
    SQUARE_METER,
    Angle,
    Area64,
    Length,
    Length64,
)

# The most voxels the grid holds. A scan too large for it gets larger
# voxels.
comptime MAX_VOXELS = 1 << 22
# The most that the tops of two columns of one ground surface differ by,
# in meters, and the least share of the plan that a ground covers.
comptime GROUND_STEP = Float64(2.0)
comptime GROUND_SHARE = Float64(0.25)
# The fewest voxels of a part.
comptime MIN_PART_VOXELS = 20
# How far a building's foot sinks below the lowest ground under it, in
# meters.
comptime SINK = Float32(0.15)


struct CutBuilding(Movable):
    """The splats of a building, cut out of its scan, and where it is."""

    var splats: GaussianSplatGeometry
    # The scan's frame, which places the splats.
    var frame: ScanFrame
    # The building's box, in building coordinates: x east, y north and z
    # up, in meters.
    var region: ScanRegion

    def __init__(
        out self,
        var splats: GaussianSplatGeometry,
        frame: ScanFrame,
        region: ScanRegion,
    ):
        """Hold a cut building.

        Args:
            splats: Its splats, in the scan's coordinates.
            frame: The scan's frame.
            region: Its box, in building coordinates.
        """
        self.splats = splats^
        self.frame = frame
        self.region = region


def _ground(grid: OccupancyGrid) raises -> GroundSurface:
    """Return the ground of a grid as a terrain surface: the largest
    surface of column tops that covers `GROUND_SHARE` of the plan."""
    var covered = 0
    var tops = column_tops(grid)
    for index in range(len(tops)):  # pragma: no branch
        if tops[index] >= 0:
            covered += 1
    var edge = grid.voxel.to(METER)
    return terrain_ground(
        grid,
        TerrainOptions(
            Length64(GROUND_STEP, METER),
            Area64(Float64(covered) * edge * edge * GROUND_SHARE, SQUARE_METER),
        ),
    )


def cut_building(
    geometry: GaussianSplatGeometry, frame: ScanFrame, voxel: Length
) raises -> CutBuilding:
    """Cut a scan's building out of its ground.

    Args:
        geometry: The scan's splats.
        frame: The scan's frame.
        voxel: The voxel edge to start from. It doubles until the grid
            holds at most `MAX_VOXELS`.

    Returns:
        The largest part above the ground: its splats and its box.

    Raises:
        Error: If the grid cannot be filled, no ground is found, or no
            part stands above the ground.
    """
    var options = default_occupancy_options()
    options.voxel = Length64(Float64(voxel.to(METER)), METER)
    options.max_voxels = MAX_VOXELS
    var region = trimmed_region(geometry, frame, options)
    var size = region.high - region.low
    var edge = Float64(voxel.to(METER))
    while (size.x / edge) * (size.y / edge) * (size.z / edge) > Float64(
        MAX_VOXELS
    ):
        edge *= 2
    options.voxel = Length64(edge, METER)
    var grid = occupancy_grid(geometry, frame, options, region)
    var parts = scan_parts_on(grid, _ground(grid), MIN_PART_VOXELS)
    if len(parts.parts) == 0:
        raise Error("A scan with no part above its ground has no building")
    var splats = part_splats(geometry, frame, grid, parts, 0, 1)
    return CutBuilding(splats^, frame, parts.parts[0].region(grid))


def linear_splats(geometry: GaussianSplatGeometry) -> GaussianSplatGeometry:
    """Return a copy of splats with their colors in linear light and no
    spherical harmonics.

    Args:
        geometry: The splats, with sRGB colors.

    Returns:
        The copy. Each color byte is the sRGB byte turned to linear light,
        rounded. Opacity is kept.
    """
    var copy = geometry.copy()
    var table = List[UInt8](length=256, fill=0)
    for value in range(256):  # pragma: no branch
        var light = srgb_to_linear(Float32(value) / 255)
        table[value] = UInt8(Int(light * 255 + 0.5))
    for index in range(len(copy.colors)):  # pragma: no branch
        if index % 4 != 3:
            copy.colors[index] = table[Int(copy.colors[index])]
    copy.sh1 = List[UInt8]()
    copy.sh2 = List[UInt8]()
    copy.sh3 = List[UInt8]()
    return copy^


def scan_lot(building: CutBuilding, x: Float32, z: Float32, turn: Angle) -> Lot:
    """Return the lot a cut building stands on.

    Args:
        building: The building.
        x: Where the middle of its footprint stands, along x, in meters.
        z: The same along z.
        turn: How far it is turned about +y.

    Returns:
        Its footprint, turned.
    """
    ref box = building.region
    return Lot(
        x,
        z,
        Float32((box.high.x - box.low.x) / 2),
        Float32((box.high.y - box.low.y) / 2),
        turn.to(RADIAN),
    )


def stand_scan(
    mut scene: Scene,
    building: CutBuilding,
    x: Float32,
    z: Float32,
    turn: Angle,
    ground: Ground,
) raises -> Lot:
    """Stand a cut building in a scene on the ground.

    Args:
        scene: The scene. A node and a Gaussian splat object, with a copy
            of the building's splats in linear light, are added.
        building: The building.
        x: Where the middle of its footprint stands, along x, in meters.
        z: The same along z.
        turn: How far it is turned about +y.
        ground: The ground it stands on.

    Returns:
        The lot it stands on: its footprint, turned.

    Raises:
        Error: If the frame is not valid, or the splats cannot be drawn.
    """
    var placement = scan_placement(building.frame)
    var lot = scan_lot(building, x, z, turn)
    ref box = building.region
    # The middle of the footprint's foot, in the scene's axes.
    var foot = Vector3(
        Float32((box.low.x + box.high.x) / 2),
        Float32(box.low.z),
        Float32(-(box.low.y + box.high.y) / 2),
    )
    var angle = turn.to(RADIAN)
    var c = cos(angle)
    var s = sin(angle)
    var lowest = Float32(1.0e30)
    for k in range(4):  # pragma: no branch
        var u = lot.half_width * (Float32(1) if k % 2 == 0 else Float32(-1))
        var v = lot.half_depth * (Float32(1) if k < 2 else Float32(-1))
        lowest = min(
            lowest, ground.height_at(x + u * c + v * s, z - u * s + v * c)
        )
    var turned = Quaternion.from_axis_angle(Vector3(0, 1, 0), turn)
    var stand = Object3D()
    stand.set_quaternion(turned * placement.rotation)
    stand.set_scale(placement.scale, placement.scale, placement.scale)
    var place = Vector3(x, lowest - SINK, z) + turned.rotate(
        placement.position - foot
    )
    stand.set_position(place.x, place.y, place.z)
    var node = scene.add(stand^)
    scene.add_gaussian_splat(
        GaussianSplat(linear_splats(building.splats), node)
    )
    return lot
