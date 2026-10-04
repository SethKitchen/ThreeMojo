# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An office floor's rooms through a summer day, colored by temperature.

    mojo run -I . examples/heat.mojo [path.png]

The page is Building energy. The thermal view turns a generated floor
into zones. `simulate` runs the heat balance through a clear July day
with no cooling. Each frame is one hour: each room's floor is colored
from 20 degrees Celsius, blue, to 34, red.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from generators.utils import Vec3d
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin, sqrt
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length
from extensions.building.construction import Construction, Layer, double_glazing
from extensions.building.generate.openings import (
    WindowOptions,
    add_doors,
    add_windows,
)
from extensions.building.generate.plan import (
    OFFICE_FLOOR,
    default_plan_options,
    plan_floor,
)
from extensions.building.ids import ConstructionId, MaterialId
from extensions.building.material import (
    BuildingMaterial,
    brick,
    concrete,
    gypsum_board,
    mineral_wool,
)
from extensions.building.model import (
    ConstructionSet,
    Site,
    StoreyPlan,
    assemble,
)
from extensions.building.views.render import FULL, RenderOptions, add_building
from extensions.building.views.thermal import (
    default_thermal_options,
    thermal_view,
)
from extensions.energy.ids import ZoneId
from extensions.energy.simulation import default_options, simulate
from extensions.energy.weather import WeatherLocation, design_day
from extensions.topology.arrangement import Point2
from units.si import (
    Angle64,
    Duration64,
    HOUR,
    Length64,
    METER_PER_SECOND,
    Velocity64,
)
from units.temperature import CELSIUS, Temperature64

comptime DEFAULT_OUTPUT = "out/building-energy.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 24
comptime DELAY_MS = 160


struct Triangles(Movable):
    """Colored triangles under construction, in model coordinates, z up."""

    var positions: List[Float32]
    var normals: List[Float32]
    var colors: List[Float32]

    def __init__(out self):
        """Start with no triangles."""
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.colors = List[Float32]()

    def triangle(mut self, a: Vec3d, b: Vec3d, c: Vec3d, color: Vec3d):
        """Add one flat triangle, converting z up to y up.

        Args:
            a: The first corner.
            b: The second corner.
            c: The third corner.
            color: The linear color, each channel zero to one.
        """
        var n = (b - a).cross(c - a).normalized()
        var corners = [a, b, c]
        for k in range(3):
            var p = corners[k]
            self.positions.append(Float32(p.x))
            self.positions.append(Float32(p.z))
            self.positions.append(Float32(-p.y))
            self.normals.append(Float32(n.x))
            self.normals.append(Float32(n.z))
            self.normals.append(Float32(-n.y))
            self.colors.append(Float32(color.x))
            self.colors.append(Float32(color.y))
            self.colors.append(Float32(color.z))

    def box(mut self, start: Vec3d, end: Vec3d, size: Float64, color: Vec3d):
        """Add a square bar from one point to another.

        Args:
            start: One end of the bar's axis.
            end: The other end.
            size: The bar's width and depth.
            color: The linear color.
        """
        var axis = end - start
        var along = axis.normalized()
        var helper = Vec3d(0, 0, 1) if abs(along.z) < 0.9 else Vec3d(1, 0, 0)
        var u = along.cross(helper).normalized() * (size / 2)
        var v = along.cross(u).normalized() * (size / 2)
        var c: List[Vec3d] = [
            start - u - v,
            start + u - v,
            start + u + v,
            start - u + v,
        ]
        for k in range(4):
            var p = c[k]
            var q = c[(k + 1) % 4]
            self.triangle(p, q, q + axis, color)
            self.triangle(p, q + axis, p + axis, color)
        self.triangle(c[0], c[2], c[1], color)
        self.triangle(c[0], c[3], c[2], color)
        self.triangle(c[0] + axis, c[1] + axis, c[2] + axis, color)
        self.triangle(c[0] + axis, c[2] + axis, c[3] + axis, color)

    def add_to(
        self, mut scene: Scene, mut assets: Assets, parent: NodeId
    ) raises:
        """Add the triangles as one mesh under a node.

        Args:
            scene: The scene.
            assets: The asset store.
            parent: The node to hang the mesh from.

        Raises:
            Error: If the scene refuses the mesh.
        """
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(self.positions.copy(), 3)
        )
        geometry.set_attribute(
            String(NORMAL), BufferAttribute(self.normals.copy(), 3)
        )
        geometry.set_attribute(
            String(COLOR), BufferAttribute(self.colors.copy(), 3)
        )
        var node = Object3D()
        node.parent = parent
        var id = scene.add(node^)
        scene.add_mesh(
            Mesh(
                assets.geometries.add(geometry^),
                assets.materials.add(
                    Material(Color(255, 255, 255), vertex_colors=True)
                ),
                id,
            )
        )


def heat_color(t: Float64) -> Vec3d:
    """Return blue for zero, through white, to red for one.

    Args:
        t: The value, from zero to one.

    Returns:
        The linear color.
    """
    var s = max(0.0, min(1.0, t))
    if s < 0.5:
        var k = s * 2
        return Vec3d(0.1 + 0.85 * k, 0.25 + 0.7 * k, 0.9)
    var k = (s - 0.5) * 2
    return Vec3d(0.95, 0.95 - 0.75 * k, 0.9 - 0.8 * k)


def _camera() raises -> PerspectiveCamera:
    """Return the camera, placed to frame the scene.

    Returns:
        The camera.

    Raises:
        Error: If the camera's settings are not valid.
    """
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.5, METER),
        Length(300, METER),
    )
    camera.place(Vector3(22, 34, 30), Vector3(0, 0, 0))
    return camera^


def _light(mut scene: Scene) raises:
    """Add a sky fill and a sun.

    Args:
        scene: The scene to light.

    Raises:
        Error: If the scene refuses a node.
    """
    scene.add_light(ambient_light(Color(214, 222, 232), 0.55))
    var sun = Object3D()
    sun.set_position(30, 60, 40)
    scene.add_light(
        directional_light(Color(255, 246, 230), scene.add(sun^), 1.5)
    )


def _write(frames: List[Framebuffer]) raises:
    """Write the frames as an animated PNG.

    Args:
        frames: The frames.

    Raises:
        Error: If the file cannot be written.
    """
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", len(frames), "frames")


def main() raises:
    var m = Length64(1, METER)
    var materials = List[BuildingMaterial]()
    materials.append(brick())
    materials.append(mineral_wool())
    materials.append(gypsum_board())
    materials.append(concrete())
    var constructions = List[Construction]()
    constructions.append(
        Construction(
            "wall",
            [
                Layer(MaterialId(0), m.scaled(0.2)),
                Layer(MaterialId(1), m.scaled(0.1)),
                Layer(MaterialId(2), m.scaled(0.0125)),
            ],
        )
    )
    constructions.append(
        Construction("partition", [Layer(MaterialId(2), m.scaled(0.1))])
    )
    constructions.append(
        Construction("slab", [Layer(MaterialId(3), m.scaled(0.25))])
    )
    var footprint: List[Point2] = [
        Point2(-18, -10),
        Point2(18, -10),
        Point2(18, 10),
        Point2(-18, 10),
    ]
    var plans = List[StoreyPlan]()
    plans.append(
        StoreyPlan(
            "office",
            m.scaled(3.5),
            plan_floor(footprint, OFFICE_FLOOR, 3, default_plan_options()),
        )
    )
    var c = ConstructionId(0)
    var building = assemble(
        "office floor",
        Site(
            Angle64(40.7, DEGREE),
            Angle64(-74.0, DEGREE),
            m.scaled(10),
            Angle64(0),
        ),
        m.scaled(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(
            c,
            ConstructionId(1),
            ConstructionId(2),
            ConstructionId(2),
            ConstructionId(2),
        ),
        m.scaled(1e-6),
    )
    _ = add_doors(building, m.scaled(0.9), m.scaled(2.1))
    _ = add_windows(
        building,
        WindowOptions(
            m.scaled(2.6),
            m.scaled(0.5),
            m.scaled(0.9),
            m.scaled(1.6),
            double_glazing(),
        ),
    )
    var options = default_thermal_options()
    options.cooling_setpoint = Temperature64(60, CELSIUS)
    var view = thermal_view(building, options, List[ZoneId]())
    var weather = design_day(
        WeatherLocation(
            "New York",
            Angle64(40.7, DEGREE),
            Angle64(-74.0, DEGREE),
            Duration64(-5, HOUR),
            m.scaled(10),
        ),
        7,
        21,
        Temperature64(22, CELSIUS),
        Temperature64(33, CELSIUS),
        Temperature64(18, CELSIUS),
        Velocity64(3, METER_PER_SECOND),
        1.0,
        1,
    )
    var result = simulate(view.model, weather, default_options())
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(26, 30, 40))
    var camera = _camera()
    var frames = List[Framebuffer]()
    for hour in range(FRAMES):
        var assets = Assets()
        var scene = Scene()
        var drawn = add_building(
            scene, assets, building, RenderOptions(FULL, 0)
        )
        var mesh = Triangles()
        for s in range(len(building.spaces)):
            ref outline = building.spaces[s].outline
            var zone = view.space_zone[s]
            var t = result.air_temperature(hour, zone).to(CELSIUS)
            var color = heat_color((t - 20) / 14)
            var a = Vec3d(outline[0].x, outline[0].y, 0.03)
            for k in range(1, len(outline) - 1):
                var b = Vec3d(outline[k].x, outline[k].y, 0.03)
                var d = Vec3d(outline[k + 1].x, outline[k + 1].y, 0.03)
                if (b - a).cross(d - a).z < 0:
                    mesh.triangle(a, d, b, color)
                else:
                    mesh.triangle(a, b, d, color)
        mesh.add_to(scene, assets, drawn.root)
        _light(scene)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    _write(frames)
