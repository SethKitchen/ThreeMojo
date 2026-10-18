# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The studio an anatomy example draws in.

A soft shadow map, filmic tone mapping, the five tissue materials, and a
room environment at intensity 0.55.
"""

from core.assets import Assets
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
from lights.shadow import PCF_SOFT_SHADOW_MAP
from materials.material import MaterialId
from render.framebuffer import Color
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers


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
    var renderer = Renderer(width, height, workers=available_workers())
    renderer.set_background(Color(20, 21, 24))
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


def main():
    return
