# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scanned site cut into parts: weighed, stood in a physics world, used
again, and drawn with levels of detail on every core.

    mojo run -I . examples/scan_parts.mojo [path.png] [SCAN]

SCAN is the id of a cached scan in `assets/building_scans/manifest.json`,
or the path of a scan file of any format that `extensions.scan.files`
reads. Fetch a scan first:

    sh tools/tool.sh .venv/bin/mojo building_scans fetch studio-11 --pin

With no SCAN the example makes a scan of a hillside with a hall and a
tower on it, so it runs with no download and its picture is always the
same.

The steps:

1. Read or make the splats and the scan's frame.
2. Fill an occupancy grid. Find the ground: the floor of a scan with a
   ceiling, or else the terrain as a surface, which goes on under each
   building at the foot of its lowest wall.
3. Cut the grid into parts above the ground, and weigh the largest of
   them at the density of the scan's kit, as a shell one voxel thick.
   Take each one's weight down to the ground.
4. Make the largest part a dynamic rigid body on its bed: the ground,
   less what the body's convex hull holds, as a static collider. Let it
   stand for two seconds, and report how far it moved.
5. Copy the largest part's splats out of the scan, and place the copy
   beside the scan.
6. Build a level-of-detail tree over the scan and over the copy. Draw
   them, turning, on every core, into an animated PNG, and time each
   frame. Time one frame of every splat too, for comparison.

The report goes to the standard error, one JSON object a line.
"""

from cameras.fit_sphere import fit_sphere
from cameras.perspective_camera import PerspectiveCamera
from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
)
from core.object3d import Object3D
from core.scene import Scene
from extensions.building.kits import CONCRETE_KIT, KitKind, construction_kit
from extensions.building.scan.catalog import (
    CATALOG_CACHE,
    CATALOG_MANIFEST,
    ScanCatalog,
)
from extensions.building.scan.levels import default_level_options, detect_levels
from extensions.physics.shape import PhysicsMaterial
from extensions.physics.world import PhysicsWorld
from extensions.scan.colliders import add_scan_collider
from extensions.scan.files import read_scan
from extensions.scan.frame import (
    ScanFrame,
    axis_vector,
    supersplat_frame,
)
from extensions.scan.occupancy import (
    OccupancyGrid,
    default_occupancy_options,
    occupancy_grid,
    trimmed_region,
)
from extensions.scan.parts import (
    PART_SHELL,
    part_bed,
    part_body,
    part_footing,
    part_mass,
    part_splats,
    scan_parts_on,
)
from extensions.scan.terrain import (
    GroundSurface,
    TerrainOptions,
    column_tops,
    flat_ground,
    terrain_ground,
)
from generators.utils import Vec3d
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.splat_lod import SplatLod, build_splat_lod, prepare_splat_lod
from render.splat_raster import draw_gaussian_splat, rasterize_splats
from render.working_space import resolve_srgb_working, srgb_working_target
from std.math import cos, exp, pi, sin
from std.pathlib import Path
from std.sys import argv, num_logical_cores, stderr
from std.time import perf_counter_ns
from units.si import (
    Acceleration64,
    Angle,
    Area64,
    DEGREE,
    DEGREE64,
    Duration,
    KILOGRAM,
    KILOPASCAL,
    Length,
    Length64,
    METER,
    METER_PER_SECOND_SQUARED,
    SECOND,
    SQUARE_METER,
)

comptime DEFAULT_OUTPUT = "out/scan-parts.png"
comptime WIDTH = 320
comptime HEIGHT = 200
comptime FRAMES = 30
comptime DELAY_MS = 70
comptime BACKGROUND = Color(7, 8, 15)
comptime VOXEL_M: Float64 = 0.5
"""The voxel edge to start from: it grows until the grid fits."""
comptime MAX_VOXELS = 1 << 22
"""The most voxels the example's grid holds."""
comptime GROUND_STEP_M: Float64 = 2.0
"""The most rise between two columns of one surface: a slope of up to 63
degrees at half-meter voxels is ground, and a wall is not."""
comptime GROUND_SHARE: Float64 = 0.25
"""The least share of the plan that a surface covers to be ground: more
than any roof, less than the hillside."""
comptime MIN_PART_VOXELS = 20
"""The fewest voxels of a part that the example weighs."""
comptime REPORTED_PARTS = 3
"""How many of the largest parts the report weighs."""
comptime GRAVITY: Float64 = 9.80665
comptime SPACING: Float64 = 0.25
"""The demo scan's splats are this far apart, in meters."""


def _hill(x: Float64, y: Float64) -> Float64:
    """Return the height of the demo hillside.

    Args:
        x: East, in meters.
        y: North, in meters.

    Returns:
        A slope of one in ten up to the east, with a knoll on it.
    """
    var dx = x - 45
    var dy = y - 15
    return 0.1 * x + 1.5 * exp(-(dx * dx + dy * dy) / 150)


def _splat(
    mut centers: List[Float32],
    mut covariances: List[Float32],
    mut colors: List[UInt8],
    p: Vec3d,
    thin: Int,
    color: SIMD[DType.uint8, 4],
):
    """Add one flat splat at a building point, thin along one axis; in
    SuperSplat's frame building x, y and z are scan -x, -z and -y.

    Args:
        centers: The centers so far.
        covariances: The covariances so far.
        colors: The colors so far.
        p: The point, in building coordinates.
        thin: The building axis the splat is thin along: 0, 1 or 2.
        color: Its color and opacity.
    """
    centers.extend([Float32(-p.x), Float32(-p.z), Float32(-p.y)])
    var v = List[Float32](length=3, fill=Float32(0.6 * SPACING) ** 2)
    v[thin] = 0.01 * 0.01
    # Scan xx, xy, xz, yy, yz, zz from building xx, zz and yy.
    covariances.extend([v[0], 0, 0, v[2], 0, v[1]])
    colors.extend([color[0], color[1], color[2], color[3]])


def _inside(x: Float64, y: Float64, box: SIMD[DType.float64, 4]) -> Bool:
    """Return whether a plan point is inside a footprint.

    Args:
        x: East.
        y: North.
        box: The footprint's least x and y, and its most x and y.

    Returns:
        Whether the point is inside it, edges included.
    """
    return x >= box[0] and x <= box[2] and y >= box[1] and y <= box[3]


def _building(
    mut centers: List[Float32],
    mut covariances: List[Float32],
    mut colors: List[UInt8],
    box: SIMD[DType.float64, 4],
    height: Float64,
    color: SIMD[DType.uint8, 4],
):
    """Add the walls and the flat roof of a box building on the hillside.

    Each wall stands on the hillside where it is, and the roof is `height`
    above the highest of its feet.

    Args:
        centers: The centers so far.
        covariances: The covariances so far.
        colors: The colors so far.
        box: The footprint: least x and y, most x and y.
        height: The roof's height above the highest foot.
        color: The walls' and the roof's color and opacity.
    """
    var roof = max(_hill(box[0], box[3]), _hill(box[2], box[3]))
    roof = max(roof, max(_hill(box[0], box[1]), _hill(box[2], box[1])))
    roof += height
    var across = Int((box[2] - box[0]) / SPACING)
    var deep = Int((box[3] - box[1]) / SPACING)
    for a in range(across + 1):
        var x = box[0] + Float64(a) * SPACING
        for y in [box[1], box[3]]:
            var z = _hill(x, y)
            while z < roof:
                _splat(centers, covariances, colors, Vec3d(x, y, z), 1, color)
                z += SPACING
    for b in range(deep + 1):
        var y = box[1] + Float64(b) * SPACING
        for x in [box[0], box[2]]:
            var z = _hill(x, y)
            while z < roof:
                _splat(centers, covariances, colors, Vec3d(x, y, z), 0, color)
                z += SPACING
    for a in range(across + 1):
        for b in range(deep + 1):
            var p = Vec3d(
                box[0] + Float64(a) * SPACING,
                box[1] + Float64(b) * SPACING,
                roof,
            )
            _splat(centers, covariances, colors, p, 2, color)


def _demo_site() raises -> GaussianSplatGeometry:
    """Return the demo scan: a hillside 60 m on a side, and on it a hall
    12 m by 10 m by 6 m and a tower 4 m square and 12 m tall, in
    SuperSplat's frame. The scan sees no ground under the buildings."""
    var centers = List[Float32]()
    var covariances = List[Float32]()
    var colors = List[UInt8]()
    var hall = SIMD[DType.float64, 4](12, 20, 24, 30)
    var tower = SIMD[DType.float64, 4](36, 36, 40, 40)
    var count = Int(60 / SPACING)
    for a in range(count + 1):
        for b in range(count + 1):
            var x = Float64(a) * SPACING
            var y = Float64(b) * SPACING
            if _inside(x, y, hall) or _inside(x, y, tower):
                continue
            var z = _hill(x, y)
            # Earth, a little lighter higher up, in a fine pattern.
            var shade = UInt8(Int(z * 6) + (a * 7 + b * 13) % 23)
            _splat(
                centers,
                covariances,
                colors,
                Vec3d(x, y, z),
                2,
                SIMD[DType.uint8, 4](130 + shade, 104 + shade, 72, 235),
            )
    _building(
        centers,
        covariances,
        colors,
        hall,
        6,
        SIMD[DType.uint8, 4](206, 200, 190, 240),
    )
    _building(
        centers,
        covariances,
        colors,
        tower,
        12,
        SIMD[DType.uint8, 4](168, 150, 138, 240),
    )
    return create_gaussian_splat_geometry(centers^, covariances^, colors^)


struct _Scan(Movable):
    """A scan to cut: its splats, its frame, its kit and a name."""

    var splats: GaussianSplatGeometry
    var frame: ScanFrame
    var kit: KitKind
    var name: String

    def __init__(
        out self,
        var splats: GaussianSplatGeometry,
        frame: ScanFrame,
        kit: KitKind,
        var name: String,
    ):
        self.splats = splats^
        self.frame = frame
        self.kit = kit
        self.name = name^


def _scan(words: List[String]) raises -> _Scan:
    """Return the scan the command line names, or the demo site.

    Args:
        words: The command line.

    Returns:
        The scan.

    Raises:
        Error: If a named scan is not cached, or cannot be read.
    """
    if len(words) < 3:
        return _Scan(
            _demo_site(), supersplat_frame(), CONCRETE_KIT, "demo site"
        )
    var wanted = words[2]
    var catalog = ScanCatalog.open(CATALOG_MANIFEST, CATALOG_CACHE)
    for entry in catalog.entries:
        if entry.id == wanted:
            var path = catalog.scene(wanted)
            if not path:
                raise Error(
                    "The scan '"
                    + wanted
                    + "' is not cached: sh tools/tool.sh .venv/bin/mojo"
                    " building_scans fetch "
                    + wanted
                    + " --pin"
                )
            return _Scan(
                read_scan(path.value()).geometry.copy(),
                entry.frame,
                entry.kit,
                entry.title,
            )
    return _Scan(
        read_scan(wanted).geometry.copy(),
        supersplat_frame(),
        CONCRETE_KIT,
        wanted,
    )


def _ground(grid: OccupancyGrid) raises -> GroundSurface:
    """Return the ground of a grid: the first floor of a scan with a
    ceiling, or else the terrain.

    Args:
        grid: The grid.

    Returns:
        The ground.

    Raises:
        Error: Everything `terrain_ground` raises.
    """
    try:
        var levels = detect_levels(grid, default_level_options())
        if not levels.exterior:
            return flat_ground(grid, levels.floors[0])
    except:
        pass
    var covered = 0
    for top in column_tops(grid):
        if top >= 0:
            covered += 1
    var edge = grid.voxel.to(METER)
    return terrain_ground(
        grid,
        TerrainOptions(
            Length64(GROUND_STEP_M, METER),
            Area64(Float64(covered) * edge * edge * GROUND_SHARE, SQUARE_METER),
        ),
    )


def main() raises:
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    var destination = String(DEFAULT_OUTPUT)
    if len(words) > 1:
        destination = words[1]

    # 1. The splats and the frame.
    var start = perf_counter_ns()
    var scan = _scan(words)
    var frame = scan.frame
    print(
        '{"scan": "',
        scan.name,
        '", "splats": ',
        scan.splats.count(),
        ', "read_ms": ',
        Float64(perf_counter_ns() - start) / 1e6,
        "}",
        sep="",
        file=stderr,
    )

    # 2. The grid, with the voxel grown until it fits, and the ground.
    var options = default_occupancy_options()
    options.voxel = Length64(VOXEL_M, METER)
    options.max_voxels = MAX_VOXELS
    var region = trimmed_region(scan.splats, frame, options)
    var size = region.high - region.low
    var edge = VOXEL_M
    while (size.x / edge) * (size.y / edge) * (size.z / edge) > Float64(
        MAX_VOXELS
    ):
        edge *= 2
    options.voxel = Length64(edge, METER)
    var grid = occupancy_grid(scan.splats, frame, options, region)
    var ground = _ground(grid)
    print(
        '{"grid": [',
        grid.nx,
        ", ",
        grid.ny,
        ", ",
        grid.nz,
        '], "voxel_m": ',
        edge,
        ', "solid_voxels": ',
        grid.solid_count(),
        "}",
        sep="",
        file=stderr,
    )

    # 3. The parts, weighed at the kit's density.
    # The kit's first material is what it builds its walls of.
    var density = construction_kit(scan.kit).materials[0].density
    var parts = scan_parts_on(grid, ground, MIN_PART_VOXELS)
    if len(parts.parts) == 0:
        raise Error("The scan has no part above its ground")
    var gravity = Acceleration64(GRAVITY, METER_PER_SECOND_SQUARED)
    for label in range(min(REPORTED_PARTS, len(parts.parts))):
        var mass = part_mass(grid, parts, label, density, PART_SHELL)
        var footing = part_footing(grid, parts, label, mass, gravity)
        var box = parts.parts[label].region(grid)
        print(
            '{"part": ',
            label,
            ', "voxels": ',
            parts.parts[label].count(),
            ', "size_m": [',
            box.high.x - box.low.x,
            ", ",
            box.high.y - box.low.y,
            ", ",
            box.high.z - box.low.z,
            '], "mass_t": ',
            mass.mass.to(KILOGRAM) / 1000,
            ', "base_m2": ',
            footing.area.to(SQUARE_METER),
            ', "pressure_kpa": ',
            footing.pressure.to(KILOPASCAL),
            ', "tip_deg": ',
            footing.tip.to(DEGREE64),
            ', "stands": ',
            "true" if footing.stands() else "false",
            "}",
            sep="",
            file=stderr,
        )

    # 4. The largest part, standing on its bed for two seconds.
    var mass = part_mass(grid, parts, 0, density, PART_SHELL)
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, Float32(-GRAVITY))
    _ = add_scan_collider(
        world, part_bed(grid, parts, 0, mass), PhysicsMaterial.default()
    )
    var body = world.add_body(
        part_body(grid, parts, 0, mass, PhysicsMaterial.default())
    )
    var placed = world.bodies[body.value].position
    for _ in range(120):
        world.step(Duration(1.0 / 60, SECOND))
    print(
        '{"part_0_moved_m": ',
        (world.bodies[body.value].position - placed).length(),
        "}",
        sep="",
        file=stderr,
    )

    # 5. The largest part's splats, copied out of the scan.
    var copy = part_splats(scan.splats, frame, grid, parts, 0, 1)
    print('{"part_0_splats": ', copy.count(), "}", sep="", file=stderr)

    # 6. The scan and the copy beside it, turning. Each node turns the
    # scan's up to the scene's.
    var up = axis_vector(frame.up)
    var upright = Quaternion.from_unit_vectors(
        Vector3(Float32(up.x), Float32(up.y), Float32(up.z)), Vector3(0, 1, 0)
    )
    var scene = Scene()
    var standing = Object3D()
    standing.set_quaternion(upright)
    var node = scene.add(standing^)
    var beside = Object3D()
    beside.set_quaternion(upright)
    var box = parts.parts[0].region(grid)
    var shift = Float32((box.high.x - box.low.x) * 1.4 / frame.unit.to(METER))
    beside.set_position(shift, 0, 0)
    var other = scene.add(beside^)
    scene.update()
    var whole = GaussianSplat(scan.splats.copy(), node)
    var built = perf_counter_ns()
    var lods = List[SplatLod]()
    lods.append(build_splat_lod(scan.splats, node))
    lods.append(build_splat_lod(copy, other))
    print(
        '{"lod_build_ms": ',
        Float64(perf_counter_ns() - built) / 1e6,
        ', "lod_splats": ',
        lods[0].splat.count() + lods[1].splat.count(),
        "}",
        sep="",
        file=stderr,
    )
    var part = GaussianSplat(copy^, other)
    whole.compute_bounding_sphere()
    var sphere = whole.bounding_sphere.value()
    var center = scene.world_matrix(node).transform_point(sphere.center)
    center.x += shift / 2
    var radius = sphere.radius + shift / 2
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(1000.0, METER),
    )
    var workers = num_logical_cores()
    # One frame of every splat, for comparison.
    _ = fit_sphere(
        camera,
        center,
        Length(radius, METER),
        Vector3(0, Float32(0.45), 1),
        Float32(0.6),
    )
    var every = srgb_working_target(WIDTH, HEIGHT, BACKGROUND)
    var began = perf_counter_ns()
    draw_gaussian_splat(every, scene, whole, camera, None, workers)
    draw_gaussian_splat(every, scene, part, camera, None, workers)
    var every_ms = Float64(perf_counter_ns() - began) / 1e6
    var frames = List[Framebuffer]()
    var spent = Float64(0)
    var drawn = 0
    for index in range(FRAMES):
        var angle = Float32(2 * pi) * Float32(index) / Float32(FRAMES)
        var side = Vector3(sin(angle), Float32(0.45), cos(angle))
        _ = fit_sphere(
            camera, center, Length(radius, METER), side, Float32(0.6)
        )
        var target = srgb_working_target(WIDTH, HEIGHT, BACKGROUND)
        began = perf_counter_ns()
        for at in range(len(lods)):
            var splats = prepare_splat_lod(
                scene,
                lods[at],
                camera,
                WIDTH,
                HEIGHT,
                target.depth_mode,
                None,
                workers,
            )
            drawn += len(splats)
            rasterize_splats(target, splats, workers)
        spent += Float64(perf_counter_ns() - began) / 1e6
        frames.append(resolve_srgb_working(target))
    print(
        '{"workers": ',
        workers,
        ', "every_splat_frame_ms": ',
        every_ms,
        ', "frame_ms": ',
        spent / Float64(FRAMES),
        ', "fps": ',
        1000 * Float64(FRAMES) / spent,
        ', "splats_drawn": ',
        drawn // FRAMES,
        "}",
        sep="",
        file=stderr,
    )
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
