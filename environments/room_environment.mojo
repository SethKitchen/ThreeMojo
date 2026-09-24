# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scenes made to be environments, from three.js
`examples/jsm/environments/RoomEnvironment.js` and `DebugEnvironment.js`.

A physical surface reflects its environment. A photograph of a room is
one environment; a scene drawn into a cube is another, and a small
synthetic scene lights a model evenly with no image file at all.
`room_environment` is three.js's `RoomEnvironment`: a white room with six
boxes on its floor and six glowing panels on its walls and ceiling, lit
by one bulb. `debug_environment` is three.js's `DebugEnvironment`: a room
with a red, a green and a blue panel, so each side of a reflection shows
which way it faces.

Draw either through `renderers.environment.pmrem_from_scene` and name the
result as a scene's `environment`:

    var room = room_environment(assets)
    scene.environment = assets.cube_textures.add(
        pmrem_from_scene(renderer, room, assets, sigma=Angle(0.04, RADIAN))
    )

The panels glow by their emissive intensity, fifty or a hundred times
white. `pmrem_from_scene` draws into floats, so that light survives.

**Where this differs from three.js.** three.js deletes the box's texture
coordinates; they stay here, as nothing reads them. `dispose` has no
counterpart, as the assets own the geometry and the materials.
"""

from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import point_light
from materials.material import BACK_SIDE, LAMBERT, Material, standard_material
from math.matrix4 import Matrix4, rotation_y, scaling, translation
from objects.instanced_mesh import InstancedMesh
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import Angle, Length, METER, RADIAN

comptime _WHITE = Color(255, 255, 255)
comptime _BLACK = Color(0, 0, 0)


def glowing_panel(color: Color, intensity: Float32) raises -> Material:
    """Return a material that only glows, three.js's
    `createAreaLightMaterial` and the panels of `DebugEnvironment`.

    A `LAMBERT` material whose emissive is white at `intensity`. A room's
    panels are black, so they reflect nothing and only glow.

    Args:
        color: The surface's own color, black for a room's panel.
        intensity: How bright the white glow is.

    Returns:
        The material.

    Raises:
        Error: If `Material` refuses the intensity.
    """
    return Material(
        color, kind=LAMBERT, emissive=_WHITE, emissive_intensity=intensity
    )


def _placed(
    mut scene: Scene,
    x: Float32,
    y: Float32,
    z: Float32,
    width: Float32,
    height: Float32,
    depth: Float32,
) raises -> NodeId:
    """Add a node at a position with a scale, and return it."""
    var node = Object3D()
    node.set_position(x, y, z)
    node.set_scale(width, height, depth)
    return scene.add(node^)


def _box_at(
    x: Float32,
    y: Float32,
    z: Float32,
    turn: Float32,
    width: Float32,
    height: Float32,
    depth: Float32,
) -> Matrix4:
    """Return one box's transform: three.js's `updateMatrix` of a position,
    a turn about y in radians and a scale."""
    var placed = translation(x, y, z)
    placed.multiply(rotation_y(Angle(turn, RADIAN)))
    placed.multiply(scaling(width, height, depth))
    return placed


def room_environment(mut assets: Assets) raises -> Scene:
    """Return three.js's `RoomEnvironment`: a room with six boxes, six
    glowing panels and one bulb, with three.js's numbers.

    The room is a unit box seen from inside, scaled about 32 by 28 by 29
    meters, white and fully rough. The boxes stand on its floor, one
    `InstancedMesh`. The panels glow at 50, 50, 17, 43, 20 and 100. The
    bulb is a white point light of intensity 900, reaching 28 meters,
    falling off with the square of the distance.

    Args:
        assets: Where the geometry and the materials go.

    Returns:
        The scene, updated. Draw it with
        `renderers.environment.pmrem_from_scene`.

    Raises:
        Error: If a material, a mesh or the light is refused.
    """
    var scene = Scene()
    var geometry = assets.geometries.add(cube(Length(1.0, METER)))
    var room_paint = assets.materials.add(
        standard_material(_WHITE, side=BACK_SIDE)
    )
    var box_paint = assets.materials.add(standard_material(_WHITE))
    var bulb = Object3D()
    bulb.set_position(0.418, 16.199, 0.300)
    scene.add_light(point_light(_WHITE, scene.add(bulb^), 900, 2, 28))
    scene.add_mesh(
        Mesh(
            geometry,
            room_paint,
            _placed(scene, -0.757, 13.219, 0.717, 31.713, 28.305, 28.591),
        )
    )
    var boxes = InstancedMesh(geometry, box_paint, scene.add(Object3D()), 6)
    boxes.set_matrix_at(
        0, _box_at(-10.906, 2.009, 1.846, -0.195, 2.328, 7.905, 4.651)
    )
    boxes.set_matrix_at(
        1, _box_at(-5.607, -0.754, -0.758, 0.994, 1.970, 1.534, 3.955)
    )
    boxes.set_matrix_at(
        2, _box_at(6.167, 0.857, 7.803, 0.561, 3.927, 6.285, 3.687)
    )
    boxes.set_matrix_at(
        3, _box_at(-2.017, 0.018, 6.124, 0.333, 2.002, 4.566, 2.064)
    )
    boxes.set_matrix_at(
        4, _box_at(2.291, -0.756, -2.621, -0.286, 1.546, 1.552, 1.496)
    )
    boxes.set_matrix_at(
        5, _box_at(-2.193, -0.369, -5.547, 0.516, 3.875, 3.487, 2.986)
    )
    scene.add_instanced_mesh(boxes^)
    _panel(
        scene, assets, geometry, 50, -16.116, 14.37, 8.208, 0.1, 2.428, 2.739
    )
    _panel(
        scene, assets, geometry, 50, -16.109, 18.021, -8.207, 0.1, 2.425, 2.751
    )
    _panel(
        scene, assets, geometry, 17, 14.904, 12.198, -1.832, 0.15, 4.265, 6.331
    )
    _panel(
        scene, assets, geometry, 43, -0.462, 8.89, 14.520, 4.38, 5.441, 0.088
    )
    _panel(scene, assets, geometry, 20, 3.235, 11.486, -12.541, 2.5, 2.0, 0.1)
    _panel(scene, assets, geometry, 100, 0.0, 20.0, 0.0, 1.0, 0.1, 1.0)
    scene.update()
    return scene^


def _panel(
    mut scene: Scene,
    mut assets: Assets,
    geometry: GeometryId,
    intensity: Float32,
    x: Float32,
    y: Float32,
    z: Float32,
    width: Float32,
    height: Float32,
    depth: Float32,
) raises:
    """Add one black panel glowing white at `intensity`."""
    var paint = assets.materials.add(glowing_panel(_BLACK, intensity))
    scene.add_mesh(
        Mesh(geometry, paint, _placed(scene, x, y, z, width, height, depth))
    )


def debug_environment(mut assets: Assets) raises -> Scene:
    """Return three.js's `DebugEnvironment`: a room ten meters across with
    a red panel on its -x side, a green one above and a blue one on its +z
    side, and a bulb in the middle.

    The room is white, fully rough and not metal. Each panel glows white
    at ten over its own color. The bulb is a white point light of
    intensity 50 with no cutoff.

    Args:
        assets: Where the geometry and the materials go.

    Returns:
        The scene, updated. Draw it with
        `renderers.environment.pmrem_from_scene`.

    Raises:
        Error: If a material, a mesh or the light is refused.
    """
    var scene = Scene()
    var geometry = assets.geometries.add(cube(Length(1.0, METER)))
    var room_paint = assets.materials.add(
        standard_material(_WHITE, metalness=0, side=BACK_SIDE)
    )
    scene.add_mesh(
        Mesh(geometry, room_paint, _placed(scene, 0, 0, 0, 10, 10, 10))
    )
    scene.add_light(point_light(_WHITE, scene.add(Object3D()), 50, 2, 0))
    var red = assets.materials.add(glowing_panel(Color(255, 0, 0), 10))
    scene.add_mesh(Mesh(geometry, red, _placed(scene, -5, 2, 0, 0.1, 1, 1)))
    var green = assets.materials.add(glowing_panel(Color(0, 255, 0), 10))
    scene.add_mesh(Mesh(geometry, green, _placed(scene, 0, 5, 0, 1, 0.1, 1)))
    var blue = assets.materials.add(glowing_panel(Color(0, 0, 255), 10))
    scene.add_mesh(Mesh(geometry, blue, _placed(scene, 2, 1, 5, 1.5, 2, 0.1)))
    scene.update()
    return scene^
