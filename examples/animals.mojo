# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Every procedural animal, one to a tile, turning.

    mojo run -I . examples/animals.mojo [path.png]

The page is Animals. Each species is built from one seed, meshed at
the `MEDIUM` tier, painted and lit by a sun and a sky. Each tile frames
its animal from three quarters in front, on its own floor, so a spider
and a horse fill their tiles alike. Four-legged animals are caught in
mid-stride and the snake and the swimmers bend in an S. Each animal
turns a whole turn.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.animals.gait import (
    is_quadruped,
    spine_count,
    undulate_pose,
    walk_pose,
)
from extensions.animals.rig import Pose
from extensions.animals.build import (
    Animal,
    animal_materials,
    create_animal,
    mesh_animal,
)
from extensions.animals.options import MEDIUM, animal_options
from extensions.animals.registry import SPECIES_COUNT, SpeciesId
from geometries.plane import plane
from lights.light import directional_light, hemisphere_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.apng import encode
from renderers.renderer import Renderer, available_workers
from std.math import max
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/animals.png"
comptime TILE_W = 240
comptime TILE_H = 180
comptime COLUMNS = 6
comptime SEED = 7
comptime FRAMES = 12
comptime DELAY_MS = 120


def pose_for(animal: Animal) raises -> Pose:
    """Return a pose that shows how the animal moves.

    A four-legged animal is caught in mid-stride. A snake, a fish or a
    shark bends in an S. Any other animal stands in its bind pose.

    Args:
        animal: The animal.

    Returns:
        The pose.

    Raises:
        Error: If the rig lacks a bone its pose needs.
    """
    if is_quadruped(animal.rig):
        return walk_pose(animal.rig, 0.3)
    if spine_count(animal.rig) > 4:
        return undulate_pose(animal.rig, 0.0, waves=1.2)
    return animal.bind_pose()


def tiles(id: SpeciesId, renderer: Renderer) raises -> List[Framebuffer]:
    """Build one species and render it turning, one tile per frame.

    Args:
        id: The species.
        renderer: The tile renderer.

    Returns:
        The tiles.

    Raises:
        Error: If the build or the render fails.
    """
    var animal = create_animal(id, animal_options(SEED, quality=MEDIUM))
    var geometry = mesh_animal(animal, pose_for(animal), workers=0)
    var box = geometry.bounding_box()
    var size = box.max - box.min
    var center = (box.max + box.min) * 0.5
    var reach = max(size.x, max(size.y, size.z))
    var assets = Assets()
    var shape = assets.geometries.add(geometry^)
    var materials = List[MaterialId]()
    for m in animal_materials():
        materials.append(assets.materials.add(m.copy()))
    var floor_size = Length(reach * 12.0, METER)
    var ground = assets.geometries.add(plane(floor_size, floor_size))
    var soil = assets.materials.add(Material(Color(128, 122, 110)))
    var scene = Scene()
    var body = scene.add(Object3D())
    scene.add_mesh(
        Mesh(shape, materials, body, cast_shadow=True, receive_shadow=True)
    )
    var floor = Object3D()
    floor.rotate_x(Angle(-90.0, DEGREE))
    floor.set_position(0, box.min.y, 0)
    scene.add_mesh(Mesh(ground, soil, scene.add(floor^), receive_shadow=True))
    var lamp = Object3D()
    lamp.set_position(reach * 2.0, reach * 4.0, reach * 2.6)
    var sun = directional_light(Color(255, 243, 228), scene.add(lamp^), 2.3)
    sun.cast_shadow = True
    sun.shadow.map_size = 512
    sun.shadow.bias = -0.0005
    sun.shadow.normal_bias = reach * 0.01
    sun.shadow.set_extent(Length(reach * 1.2, METER))
    sun.shadow.near = Length(reach * 0.5, METER)
    sun.shadow.far = Length(reach * 12.0, METER)
    scene.add_light(sun)
    var sky = Object3D()
    sky.set_position(0, 10, 0)
    scene.add_light(
        hemisphere_light(
            Color(221, 230, 242), Color(95, 90, 82), scene.add(sky^), 1.15
        )
    )
    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(TILE_W) / Float32(TILE_H),
        Length(reach * 0.05, METER),
        Length(reach * 30.0, METER),
    )
    var away = Vector3(1.05, 0.42, 1.25) * (reach * 1.15)
    camera.place(center + away, center)
    var out = List[Framebuffer]()
    var step = Angle(360.0 / Float32(FRAMES), DEGREE)
    for _ in range(FRAMES):
        scene.update()
        out.append(renderer.render(scene, assets, camera))
        scene.node(body).rotate_y(step)
    return out^


def blit(mut sheet: Framebuffer, piece: Framebuffer, x0: Int, y0: Int):
    """Copy a tile into the sheet.

    Args:
        sheet: The whole picture.
        piece: One tile.
        x0: The tile's left column in the sheet.
        y0: The tile's top row in the sheet.
    """
    var channels = len(piece.pixels) // (piece.width * piece.height)
    for y in range(piece.height):
        for x in range(piece.width):
            var src = (y * piece.width + x) * channels
            var dst = ((y0 + y) * sheet.width + x0 + x) * channels
            for c in range(channels):
                sheet.pixels[dst + c] = piece.pixels[src + c]


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    var rows = (SPECIES_COUNT + COLUMNS - 1) // COLUMNS
    var renderer = Renderer(TILE_W, TILE_H, workers=available_workers())
    renderer.set_background(Color(170, 190, 215))
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    var sheets = List[Framebuffer]()
    for _ in range(FRAMES):
        sheets.append(
            Framebuffer(TILE_W * COLUMNS, TILE_H * rows, Color(170, 190, 215))
        )
    for i in range(SPECIES_COUNT):
        var pieces = tiles(SpeciesId(i), renderer)
        for f in range(FRAMES):
            blit(
                sheets[f],
                pieces[f],
                (i % COLUMNS) * TILE_W,
                (i // COLUMNS) * TILE_H,
            )
    Path(destination).write_bytes(encode(sheets, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", SPECIES_COUNT, "animals")
