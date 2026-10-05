# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A small two-storey building model, cut away above its ground floor.

    mojo run -I . examples/building_model.mojo [path.png]

The page is Building model. `assemble` builds the model from two storey
plans. A window, a door, a column and a beam are added. The render view
draws the ground storey only, so the rooms show.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, DEGREE64, METER, Angle, Length
from extensions.building.construction import Construction, Layer, double_glazing
from extensions.building.ids import (
    ConstructionId,
    ElementId,
    MaterialId,
    StoreyId,
)
from extensions.building.kinds import CORRIDOR, DOOR, OFFICE, WALL, WINDOW
from extensions.building.material import (
    BuildingMaterial,
    brick,
    concrete,
    gypsum_board,
    mineral_wool,
    steel,
)
from extensions.building.model import (
    Building,
    ConstructionSet,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
    i_shape,
)
from extensions.building.views.render import FULL, RenderOptions, add_building
from extensions.topology.arrangement import Point2
from units.si import Angle64, Length64

comptime DEFAULT_OUTPUT = "out/building-model.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 70


def _m(v: Float64) -> Length64:
    """Return meters.

    Args:
        v: The number of meters.

    Returns:
        The length.
    """
    return Length64(v, METER)


def _rect(x0: Float64, y0: Float64, x1: Float64, y1: Float64) -> List[Point2]:
    """Return a rectangle's corners.

    Args:
        x0: The low x.
        y0: The low y.
        x1: The high x.
        y1: The high y.

    Returns:
        The four corners, counterclockwise.
    """
    return [Point2(x0, y0), Point2(x1, y0), Point2(x1, y1), Point2(x0, y1)]


def _model() raises -> Building:
    """Return the building model.

    Returns:
        The model with its openings, column and beam.

    Raises:
        Error: If the model is not valid.
    """
    var materials = List[BuildingMaterial]()
    materials.append(brick())
    materials.append(mineral_wool())
    materials.append(gypsum_board())
    materials.append(concrete())
    materials.append(steel())
    var constructions = List[Construction]()
    constructions.append(
        Construction(
            "exterior wall",
            [
                Layer(MaterialId(0), _m(0.2)),
                Layer(MaterialId(1), _m(0.1)),
                Layer(MaterialId(2), _m(0.0125)),
            ],
        )
    )
    constructions.append(
        Construction("partition", [Layer(MaterialId(2), _m(0.1))])
    )
    constructions.append(Construction("slab", [Layer(MaterialId(3), _m(0.2))]))
    var plans = List[StoreyPlan]()
    var ground = List[SpacePlan]()
    ground.append(SpacePlan("office", OFFICE, _rect(-4, -2.5, 2, 2.5)))
    ground.append(SpacePlan("corridor", CORRIDOR, _rect(2, -2.5, 4, 2.5)))
    plans.append(StoreyPlan("ground", _m(3.2), ground^))
    var first = List[SpacePlan]()
    first.append(SpacePlan("hall", OFFICE, _rect(-4, -2.5, 4, 2.5)))
    plans.append(StoreyPlan("first", _m(3), first^))
    var b = assemble(
        "example",
        Site(Angle64(40, DEGREE64), Angle64(-105, DEGREE64), _m(0), Angle64(0)),
        _m(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(
            ConstructionId(0),
            ConstructionId(1),
            ConstructionId(2),
            ConstructionId(2),
            ConstructionId(2),
        ),
        _m(1e-6),
    )
    var wall = ElementId(0)
    while (
        b.elements[wall.value].kind != WALL or b.wall_frame(wall).length < 5.9
    ):
        wall = ElementId(wall.value + 1)
    _ = b.add_opening(
        WINDOW, wall, _m(0.6), _m(0.9), _m(1.4), _m(1.3), double_glazing()
    )
    _ = b.add_opening(DOOR, wall, _m(3.6), _m(0), _m(0.9), _m(2.1), None)
    var section = i_shape(_m(0.2), _m(0.3), _m(0.012), _m(0.008))
    _ = b.add_column(StoreyId(0), Point2(-1, 0), section, MaterialId(4))
    _ = b.add_beam(
        StoreyId(0), Point2(-4, 0), Point2(4, 0), section, MaterialId(4)
    )
    return b^


def _build(mut scene: Scene, mut assets: Assets) raises -> NodeId:
    """Add the building, cut away above its ground storey.

    Args:
        scene: The scene.
        assets: The asset store.

    Returns:
        The building's node.

    Raises:
        Error: If the model or the render is not valid.
    """
    var b = _model()
    return add_building(scene, assets, b, RenderOptions(FULL, 0)).root


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
        Length(0.1, METER),
        Length(100, METER),
    )
    camera.place(Vector3(10, 8.5, 11), Vector3(0, 1.2, 0))
    return camera^


def _light(mut scene: Scene) raises:
    """Add a sky fill and a sun.

    Args:
        scene: The scene to light.

    Raises:
        Error: If the scene refuses a node.
    """
    scene.add_light(ambient_light(Color(214, 222, 232), 0.5))
    var sun = Object3D()
    sun.set_position(30, 60, 40)
    scene.add_light(
        directional_light(Color(255, 246, 230), scene.add(sun^), 1.6)
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
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(150, 182, 214))
    var assets = Assets()
    var scene = Scene()
    var root = _build(scene, assets)
    _light(scene)
    var camera = _camera()
    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        scene.node(root).rotate_y(step)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    _write(frames)
