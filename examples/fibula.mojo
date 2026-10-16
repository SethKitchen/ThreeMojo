# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gallery of fibulas at different proportions, turning under a lamp.

    mojo run -I . examples/fibula.mojo [path.png]

The page is Fibula. Four adults stand in a row: a five-foot female, a
five-foot-six female, a six-foot male and a six-foot-six male. Length
comes from Trotter and Gleser 1952. The surface is the cortical bone map.
The program also prints each bone's tissue mass and Earth weight.
"""

from examples.output import (
    example_destination,
    gallery_camera,
    spin_gallery,
    warm_lamp,
)

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_albedo, bone_phong
from extensions.humanoid.skeleton.leg.fibula.geometry import fibula
from extensions.humanoid.skeleton.leg.fibula.mass import fibula_mass
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
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

comptime DEFAULT_OUTPUT = "out/fibula.png"
comptime WIDTH = 320
comptime HEIGHT = 200
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime DETAIL = 14
comptime SPACING = Float32(0.16)


def add_fibula(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    stature: Length,
    sex: Sex,
    x: Float32,
    paint: MaterialId,
) raises:
    """Place one fibula on the gallery row and print its mass.

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
    var report = fibula_mass(person)
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
    var shape = assets.geometries.add(fibula(person, detail=DETAIL))
    var placed = Object3D()
    placed.set_position(x, 0, 0)
    placed.set_euler(
        Angle(8.0, DEGREE), Angle(0.0, DEGREE), Angle(-10.0, DEGREE)
    )
    var node = scene.attach(placed^, parent)
    scene.add_mesh(Mesh(shape, paint, node))


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(18, 16, 14))

    var assets = Assets()
    var map = assets.textures.add(bone_albedo(64))
    var paint = assets.materials.add(bone_phong(map))

    var scene = Scene()
    var pivot = scene.add(Object3D())
    add_fibula(
        scene,
        assets,
        pivot,
        Length(5.0, FOOT),
        FEMALE,
        Float32(-1.5) * SPACING,
        paint,
    )
    add_fibula(
        scene,
        assets,
        pivot,
        Length(5.5, FOOT),
        FEMALE,
        Float32(-0.5) * SPACING,
        paint,
    )
    add_fibula(
        scene,
        assets,
        pivot,
        Length(6.0, FOOT),
        MALE,
        Float32(0.5) * SPACING,
        paint,
    )
    add_fibula(
        scene,
        assets,
        pivot,
        Length(6.5, FOOT),
        MALE,
        Float32(1.5) * SPACING,
        paint,
    )

    warm_lamp(scene, 0.38, 0.42, 0.80)
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0.16, 0.04, 1.10),
        Vector3(0.0, 0.0, 0.0),
        field_of_view=Angle(28.0, DEGREE),
        far=Length(20.0, METER),
    )

    spin_gallery(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
