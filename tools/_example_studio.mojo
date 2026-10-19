# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The studio an anatomy example draws in.

A soft shadow map, filmic tone mapping, the five tissue materials, a
room environment at intensity 0.55, a gray floor, and one sun.
"""

from tools._example_output import gallery_renderer

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.humanoid.skeleton.bone import bone_albedo, bone_physical
from extensions.humanoid.skeleton.look import (
    cartilage_physical,
    ligament_physical,
    muscle_albedo,
    muscle_physical,
    tendon_physical,
)
from geometries.plane import plane
from lights.light import directional_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import MaterialId, standard_material
from objects.mesh import Mesh
from render.framebuffer import Color
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer
from units.si import DEGREE, METER, Angle, Length


@fieldwise_init
struct TissueMaterials(Copyable, Movable):
    """Bone, cartilage, ligament, muscle, and tendon materials."""

    var bone: MaterialId
    var cartilage: MaterialId
    var ligament: MaterialId
    var muscle: MaterialId
    var tendon: MaterialId


def studio_renderer(width: Int, height: Int) raises -> Renderer:
    """Return a renderer for an anatomy still.

    Args:
        width: Image width in pixels.
        height: Image height in pixels.

    Returns:
        A renderer with a dark background, filmic tone mapping, and a
        soft shadow map.

    Raises:
        Error: If the renderer cannot be created.
    """
    var renderer = gallery_renderer(width, height, Color(20, 21, 24))
    renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
    renderer.tone_mapping_exposure = 1.1
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    return renderer^


def tissue_materials(mut assets: Assets) raises -> TissueMaterials:
    """Store the five tissue materials and return their ids.

    Args:
        assets: The scene's materials and textures.

    Returns:
        The five ids, in tissue order.

    Raises:
        Error: If a texture or a material cannot be stored.
    """
    return TissueMaterials(
        assets.materials.add(
            bone_physical(assets.textures.add(bone_albedo(64)))
        ),
        assets.materials.add(cartilage_physical()),
        assets.materials.add(ligament_physical()),
        assets.materials.add(
            muscle_physical(assets.textures.add(muscle_albedo(64)))
        ),
        assets.materials.add(tendon_physical()),
    )


def room_lit_scene(renderer: Renderer, mut assets: Assets) raises -> Scene:
    """Return a scene lit by a room environment.

    Args:
        renderer: The renderer the light probe is drawn with.
        assets: Receives the room and the environment texture.

    Returns:
        A scene whose environment intensity is 0.55.

    Raises:
        Error: If the room or the probe cannot be built.
    """
    var room = room_environment(assets)
    room.update()
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)
    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.55
    return scene^


def cast_received_shadows(mut scene: Scene):
    """Make every mesh cast and receive shadows.

    Args:
        scene: The scene.
    """
    for index in range(len(scene.meshes)):
        scene.meshes[index].cast_shadow = True
        scene.meshes[index].receive_shadow = True


def studio_floor(mut scene: Scene, mut assets: Assets, span: Length) raises:
    """Add a gray floor under the scene.

    Args:
        scene: The scene.
        assets: Receives the floor geometry and material.
        span: The floor's width and depth.

    Raises:
        Error: If the floor cannot be stored.
    """
    var floor = Object3D()
    floor.rotate_x(Angle(-90.0, DEGREE))
    var ground_shape = assets.geometries.add(plane(span, span))
    var ground_look = assets.materials.add(
        standard_material(Color(92, 90, 86), roughness=0.85)
    )
    scene.add_mesh(
        Mesh(ground_shape, ground_look, scene.add(floor^), receive_shadow=True)
    )


def studio_sun(
    mut scene: Scene, x: Float32, y: Float32, z: Float32, extent: Length
) raises:
    """Add the studio's shadow-casting sun.

    Args:
        scene: The scene.
        x: The lamp's x, in meters.
        y: The lamp's y, in meters.
        z: The lamp's z, in meters.
        extent: How wide the shadow map is.

    Raises:
        Error: If the light cannot be added.
    """
    var lamp = Object3D()
    lamp.set_position(x, y, z)
    var lamp_node = scene.add(lamp^)
    var sun = directional_light(Color(255, 244, 228), lamp_node, 2.2)
    sun.cast_shadow = True
    sun.shadow.map_size = 1024
    sun.shadow.bias = -0.0005
    sun.shadow.normal_bias = 0.01
    sun.shadow.set_extent(extent)
    sun.shadow.near = Length(0.5, METER)
    sun.shadow.far = Length(8.0, METER)
    scene.add_light(sun)
