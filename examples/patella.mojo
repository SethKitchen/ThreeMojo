# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gallery of patellas at different proportions, turning under a lamp.

    mojo run -I . examples/patella.mojo [path.png]

The page is Patella. Four adults stand in a row: a five-foot female, a
five-foot-six female, a six-foot male and a six-foot-six male. Size is an
authored fraction of stature. The surface is the cortical bone map. The
program also prints each bone's tissue mass and Earth weight.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_albedo, bone_phong
from extensions.humanoid.skeleton.leg.patella.geometry import patella
from extensions.humanoid.skeleton.leg.patella.mass import patella_mass
from lights.light import ambient_light, directional_light
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import (
    Angle,
    DEGREE,
    FOOT,
    GRAM,
    Length,
    METER,
    NEWTON,
    POUND_FORCE,
)

comptime DEFAULT_OUTPUT = "out/patella.png"
comptime WIDTH = 320
comptime HEIGHT = 200
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DETAIL = 14
comptime SPACING = Float32(0.09)


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the gallery by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        node: The parent of every patella.
        step: How much further to turn this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def add_patella(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    stature: Length,
    sex: Sex,
    x: Float32,
    paint: MaterialId,
) raises:
    """Place one patella on the gallery row and print its mass.

    Args:
        scene: The scene that receives the node and the mesh.
        assets: Geometry store for the new mesh.
        parent: Shared parent that turns every bone together.
        stature: Standing height of this adult.
        sex: `MALE` or `FEMALE`.
        x: Position along the row, in meters.
        paint: Material id of the cortical look.

    Raises:
        Error: If the spec, the mesh or the scene is invalid.
    """
    var person = HumanoidSpec(stature, sex)
    var report = patella_mass(person)
    var label = "female"
    if sex == MALE:
        label = "male"
    print(
        stature.to(FOOT),
        "ft",
        label,
        "-",
        report.mass.to(GRAM),
        "g,",
        report.weight().to(NEWTON),
        "N,",
        report.weight().to(POUND_FORCE),
        "lbf on Earth",
    )
    var shape = assets.geometries.add(patella(person, detail=DETAIL))
    var placed = Object3D()
    placed.set_position(x, 0, 0)
    placed.set_euler(
        Angle(12.0, DEGREE), Angle(0.0, DEGREE), Angle(-8.0, DEGREE)
    )
    var node = scene.attach(placed^, parent)
    scene.add_mesh(Mesh(shape, paint, node))


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(18, 16, 14))

    var assets = Assets()
    var map = assets.textures.add(bone_albedo(64))
    var paint = assets.materials.add(bone_phong(map))

    var scene = Scene()
    var pivot = scene.add(Object3D())
    add_patella(
        scene,
        assets,
        pivot,
        Length(5.0, FOOT),
        FEMALE,
        Float32(-1.5) * SPACING,
        paint,
    )
    add_patella(
        scene,
        assets,
        pivot,
        Length(5.5, FOOT),
        FEMALE,
        Float32(-0.5) * SPACING,
        paint,
    )
    add_patella(
        scene,
        assets,
        pivot,
        Length(6.0, FOOT),
        MALE,
        Float32(0.5) * SPACING,
        paint,
    )
    add_patella(
        scene,
        assets,
        pivot,
        Length(6.5, FOOT),
        MALE,
        Float32(1.5) * SPACING,
        paint,
    )

    var lamp = Object3D()
    lamp.set_position(0.12, 0.10, 0.22)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 248, 235), 0.52))
    scene.add_light(directional_light(Color(255, 244, 220), lamp_node, 2.55))

    var camera = PerspectiveCamera(
        Angle(32.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.02, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.08, 0.01, 0.42), Vector3(0.0, 0.0, 0.0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
