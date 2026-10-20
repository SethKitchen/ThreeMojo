# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scanned building as a model that stands, carries load and collides.

    mojo run -I . examples/building_scan.mojo [path.png] [SCAN]

SCAN is the id of a scan in `assets/building_scans/manifest.json`, such as
`studio-11`, or the path of a scan file of any format that
`extensions.scan.files` reads, such as a `.sog` bundle or a `meta.json`.
Fetch a scan
first:

    sh tools/tool.sh .venv/bin/mojo building_scans fetch studio-11 --pin

With no SCAN the example makes a scan of a two-storey room 4 m by 5 m, so
it runs with no download and its picture is always the same. A SCAN that
is not cached gets the same room, and a note that says how to fetch it.

The steps are those of the Scanned buildings page:

1. Read the splats and the scan's frame, and turn the frame by the walls'
   estimated heading.
2. Fill an occupancy grid, and find the floors and the ceilings.
3. Fit a building model of the scan's construction kit, and take the
   gravity load down its walls.
4. Make a static collider of the grid, and drop a ball 1.5 m above the
   first floor. It must come to rest on the floor.
5. Draw the fitted model, turning, into an animated PNG.

The report goes to the standard error, one JSON object a line.
"""

from tools._example_output import gallery_camera, spin_daylight

from core.assets import Assets
from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
)
from core.object3d import Object3D
from core.scene import Scene
from extensions.building.kits import (
    ConstructionKit,
    MASONRY_KIT,
    construction_kit,
)
from extensions.building.kinds import LIVING, SpaceUse
from extensions.building.model import Site
from extensions.building.scan.catalog import (
    CATALOG_CACHE,
    CATALOG_MANIFEST,
    ScanCatalog,
)
from extensions.building.scan.fit import ScanFitOptions, fit_building
from extensions.building.scan.levels import default_level_options, detect_levels
from extensions.building.views.bearing import (
    bearing_check,
    default_bearing_options,
)
from extensions.building.views.render import FULL, RenderOptions, add_building
from extensions.physics.body import DYNAMIC, RigidBody
from extensions.physics.shape import PhysicsMaterial, Shape
from extensions.physics.world import PhysicsWorld
from extensions.scan.colliders import add_scan_collider
from extensions.scan.frame import ScanFrame, estimate_heading, supersplat_frame
from extensions.scan.occupancy import (
    default_occupancy_options,
    occupancy_grid,
    trimmed_region,
)
from extensions.scan.files import read_scan
from generators.utils import Vec3d
from math.quaternion import Quaternion
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import cos, sin, sqrt
from std.sys import argv, stderr
from units.si import (
    Angle,
    Angle64,
    DEGREE,
    DEGREE64,
    Duration,
    KILOGRAM,
    Length,
    Length64,
    Mass,
    METER,
    SECOND,
    SQUARE_METER,
)

comptime DEFAULT_OUTPUT = "out/scanned-buildings.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 70
comptime MAX_VOXELS = 1 << 25
"""The most voxels the example's grid holds: the voxel grows to fit."""


struct _Scan(Movable):
    """A scan to fit: its splats, its frame, its kit, its use and a name."""

    var splats: GaussianSplatGeometry
    var frame: ScanFrame
    var kit: ConstructionKit
    var use: SpaceUse
    var name: String

    def __init__(
        out self,
        var splats: GaussianSplatGeometry,
        frame: ScanFrame,
        var kit: ConstructionKit,
        use: SpaceUse,
        var name: String,
    ):
        self.splats = splats^
        self.frame = frame
        self.kit = kit^
        self.use = use
        self.name = name^


def _demo_room() raises -> GaussianSplatGeometry:
    """Return flat splats on the floors, ceilings and walls of a two-storey
    room 4 m by 5 m, 3 m floor to floor, in SuperSplat's frame."""
    var centers = List[Float32]()
    var covariances = List[Float32]()
    var colors = List[UInt8]()
    var step = 0.1
    for storey in range(2):
        var floor = Float64(storey) * 3
        var ceiling = floor + 2.7
        for a in range(41):
            for b in range(51):
                for z in [floor, ceiling]:
                    _splat(
                        centers,
                        covariances,
                        colors,
                        Vec3d(Float64(a) * step, Float64(b) * step, z),
                        2,
                    )
        for c in range(1, 27):
            var z = floor + Float64(c) * step
            for a in range(41):
                _splat(
                    centers,
                    covariances,
                    colors,
                    Vec3d(Float64(a) * step, 0, z),
                    1,
                )
                _splat(
                    centers,
                    covariances,
                    colors,
                    Vec3d(Float64(a) * step, 5, z),
                    1,
                )
            for b in range(51):
                _splat(
                    centers,
                    covariances,
                    colors,
                    Vec3d(0, Float64(b) * step, z),
                    0,
                )
                _splat(
                    centers,
                    covariances,
                    colors,
                    Vec3d(4, Float64(b) * step, z),
                    0,
                )
    return create_gaussian_splat_geometry(centers^, covariances^, colors^)


def _splat(
    mut centers: List[Float32],
    mut covariances: List[Float32],
    mut colors: List[UInt8],
    p: Vec3d,
    thin: Int,
):
    """Add one flat splat at a building point, thin along one axis; in
    SuperSplat's frame building x, y and z are scan -x, -z and -y."""
    centers.extend([Float32(-p.x), Float32(-p.z), Float32(-p.y)])
    var v = List[Float32](length=3, fill=0.12 * 0.12)
    v[thin] = 0.004 * 0.004
    # Scan xx, xy, xz, yy, yz, zz from building xx, zz and yy.
    covariances.extend([v[0], 0, 0, v[2], 0, v[1]])
    colors.extend([196, 188, 176, 230])


def _scan(words: List[String]) raises -> _Scan:
    """Return the scan the command line names, or the demo room."""
    if len(words) < 3:
        return _Scan(
            _demo_room(),
            supersplat_frame(),
            construction_kit(MASONRY_KIT),
            LIVING,
            "demo room",
        )
    var wanted = words[2]
    var catalog = ScanCatalog.open(CATALOG_MANIFEST, CATALOG_CACHE)
    var named = False
    for entry in catalog.entries:
        named = named or entry.id == wanted
    if not named:
        return _Scan(
            read_scan(wanted).geometry.copy(),
            supersplat_frame(),
            construction_kit(MASONRY_KIT),
            LIVING,
            wanted,
        )
    var entry = catalog.find(wanted)
    var path = catalog.scene(wanted)
    if path:
        print(
            '{"scan": "',
            entry.title,
            '", "by": "',
            entry.author,
            '"}',
            sep="",
            file=stderr,
        )
        return _Scan(
            read_scan(path.value()).geometry.copy(),
            entry.frame,
            construction_kit(entry.kit),
            entry.use,
            entry.title,
        )
    print(
        '{"note": "',
        wanted,
        " is not cached; fetch it with sh tools/tool.sh",
        " .venv/bin/mojo building_scans fetch ",
        wanted,
        ' --pin. Using a scanned demo room."}',
        sep="",
        file=stderr,
    )
    return _Scan(
        _demo_room(),
        supersplat_frame(),
        construction_kit(MASONRY_KIT),
        LIVING,
        "demo room",
    )


def main() raises:
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    var destination = String(DEFAULT_OUTPUT)
    if len(words) > 1:
        destination = words[1]
    var scan = _scan(words)

    # 1. The frame, turned so the walls lie along x and y.
    var frame = scan.frame
    frame.heading = estimate_heading(scan.splats, frame)
    # 2. The grid, with the voxel grown until the region fits.
    var options = default_occupancy_options()
    options.max_voxels = MAX_VOXELS
    var region = trimmed_region(scan.splats, frame, options)
    var size = region.high - region.low
    var edge = options.voxel.to(METER)
    while (size.x / edge) * (size.y / edge) * (size.z / edge) > Float64(
        MAX_VOXELS
    ):
        edge *= 2
    options.voxel = Length64(edge, METER)
    var grid = occupancy_grid(scan.splats, frame, options, region)
    var levels = detect_levels(grid, default_level_options())
    # 3. The model, and its load down the walls.
    var fit = fit_building(
        grid,
        levels,
        scan.kit,
        frame.scale,
        ScanFitOptions(
            scan.name,
            Site(
                Angle64(52.2, DEGREE64),
                Angle64(21.0, DEGREE64),
                Length64(100, METER),
                Angle64(0, DEGREE64),
            ),
            scan.use,
            0.01,
            default_level_options(),
        ),
    )
    var check = bearing_check(fit.building, default_bearing_options())
    print(
        '{"splats": ',
        scan.splats.count(),
        ', "heading_deg": ',
        frame.heading.to(DEGREE64),
        ', "voxel_m": ',
        edge,
        ', "storeys": ',
        len(fit.building.storeys),
        ', "floor_m2": ',
        fit.building.gross_floor_area().to(SQUARE_METER),
        ', "mass_kg": ',
        check.mass.to(KILOGRAM),
        ', "utilization": ',
        check.utilization(),
        "}",
        sep="",
        file=stderr,
    )
    for s in range(len(fit.building.storeys)):
        print(
            '{"storey": ',
            s,
            ', "elevation_m": ',
            fit.building.storeys[s].elevation.to(METER),
            ', "height_m": ',
            fit.building.storeys[s].height.to(METER),
            ', "fill": ',
            fit.fill[s],
            ', "wall_demand_kn": ',
            check.storeys[s].demand.value / 1000,
            ', "wall_capacity_kn": ',
            check.storeys[s].capacity.value / 1000,
            "}",
            sep="",
            file=stderr,
        )
    for note in fit.notes:
        print('{"note": "', note, '"}', sep="", file=stderr)

    # 4. A ball dropped on the first floor.
    var world = PhysicsWorld()
    _ = add_scan_collider(world, grid, PhysicsMaterial.default())
    var floor = levels.floor_elevation(grid, 0).to(METER)
    var outline = fit.building.spaces[0].outline.copy()
    var x = (outline[0].x + outline[2].x) / 2
    var y = (outline[0].y + outline[2].y) / 2
    var ball = world.add_body(
        RigidBody(
            DYNAMIC,
            Shape.sphere(Length(0.2)),
            Mass(4, KILOGRAM),
            Vector3(Float32(x), Float32(y), Float32(floor + 1.5)),
            Quaternion.identity(),
        )
    )
    for _ in range(180):
        world.step(Duration(1.0 / 60, SECOND))
    print(
        '{"ball_rests_m_above_floor": ',
        Float64(world.bodies[ball.value].position.z) - floor - 0.2,
        "}",
        sep="",
        file=stderr,
    )

    # 5. The fitted model, turning about its middle.
    var assets = Assets()
    var scene = Scene()
    var pivot = scene.add(Object3D())
    var rendered = add_building(
        scene, assets, fit.building, RenderOptions(FULL, 0)
    )
    scene.add(rendered.root, parent=pivot)
    ref top = fit.building.storeys[len(fit.building.storeys) - 1]
    var height = (top.elevation + top.height).to(METER) - floor
    # The model is z up and the scene y up: (x, y, z) is (x, z, -y).
    scene.node(rendered.root).position = Vector3(
        Float32(-x), Float32(-floor), Float32(y)
    )
    var reach = sqrt(
        (outline[2].x - outline[0].x) * (outline[2].x - outline[0].x)
        + (outline[2].y - outline[0].y) * (outline[2].y - outline[0].y)
        + height * height
    )
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(
            Float32(reach * 1.1), Float32(reach * 0.9), Float32(reach * 1.2)
        ),
        Vector3(0, Float32(height * 0.4), 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(Float32(reach * 10), METER),
    )
    spin_daylight(
        WIDTH,
        HEIGHT,
        Color(150, 182, 214),
        0.5,
        1.6,
        scene,
        assets,
        pivot,
        camera,
        FRAMES,
        DELAY_MS,
        destination,
    )
