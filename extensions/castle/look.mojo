# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The look of a castle: a physically based material for each surface.

A brick wall, a stone dressing, a slate roof, a meadow and a path each wear
the maps of `textures` and are shaded by the metallic-roughness model. A leaf
card is cut out by its alpha. Window glass is smooth and reflects the sky.
Timber, lead and bark are plain colors with their own roughness.

The color of the mesh at each vertex tints the albedo, so a wall can be a
little darker than the next. A tile of a texture covers a fixed size, so the
repeat is the inverse of that size in meters.
"""

from core.assets import Assets
from extensions.castle.kinds import (
    BARK,
    BRICK,
    FOLIAGE,
    GLASS,
    GRAVEL,
    LAWN,
    METAL,
    Material,
    SLATE,
    STONE,
    WATER,
    WOOD,
)
from extensions.castle.textures import (
    BRICK_TILE,
    GRASS_TILE,
    GRAVEL_TILE,
    SLATE_HEIGHT,
    SLATE_WIDTH,
    STONE_TILE,
    SurfaceMaps,
    brick_maps,
    grass_maps,
    gravel_maps,
    leaf_texture,
    needle_texture,
    slate_maps,
    stone_maps,
)
from materials.material import (
    DOUBLE_SIDE,
    FRONT_SIDE,
    STANDARD,
    MaterialId,
    Material as SurfaceMaterial,
)
from math.vector2 import Vector2
from render.cube_texture_store import SCENE_ENVIRONMENT
from render.framebuffer import Color
from render.texture_store import NO_TEXTURE


struct CastleLook(Movable):
    """The materials of a castle, one for each kind of surface."""

    # The material of each kind, by the value of the kind.
    var materials: List[MaterialId]
    # The bark of a grown tree, which has no vertex colors.
    var trunk: MaterialId
    # A spray of conifer needles, cut out by its alpha.
    var needles: MaterialId

    def __init__(
        out self,
        var materials: List[MaterialId],
        trunk: MaterialId,
        needles: MaterialId,
    ):
        self.materials = materials^
        self.trunk = trunk
        self.needles = needles

    def material(self, kind: Material) -> MaterialId:
        """Return the material of a kind of surface.

        Args:
            kind: The kind. It must be valid.

        Returns:
            The id of the material in the assets.
        """
        return self.materials[kind.value]


def _textured(
    mut assets: Assets,
    var maps: SurfaceMaps,
    repeat_u: Float64,
    repeat_v: Float64,
    normal_scale: Float32,
) raises -> SurfaceMaterial:
    """Return a physical material that wears a set of maps."""
    var ids = maps^.store(assets, Vector2(Float32(repeat_u), Float32(repeat_v)))
    return SurfaceMaterial(
        Color(255, 255, 255),
        ids[0],
        FRONT_SIDE,
        kind=STANDARD,
        vertex_colors=True,
        roughness=1.0,
        roughness_map=ids[2],
        normal_map=ids[1],
        normal_scale=Vector2(normal_scale, normal_scale),
        env_map=SCENE_ENVIRONMENT,
    )


def _plain(
    color: Color, roughness: Float32, metalness: Float32
) raises -> SurfaceMaterial:
    """Return a physical material of one color, tinted by the vertex."""
    return SurfaceMaterial(
        color,
        NO_TEXTURE,
        FRONT_SIDE,
        kind=STANDARD,
        vertex_colors=True,
        roughness=roughness,
        metalness=metalness,
        env_map=SCENE_ENVIRONMENT,
    )


def castle_look(
    mut assets: Assets, size: Int = 512, seed: Int = 1
) raises -> CastleLook:
    """Build the materials of a castle and add them to the assets.

    Args:
        assets: The stores. The textures and the materials are added.
        size: The number of texels along a side of each tile.
        seed: Where the random numbers of the textures start.

    Returns:
        The look, with one material for each kind of surface.

    Raises:
        Error: If the size is out of range or a material is refused.
    """
    var materials = List[MaterialId]()
    var brick = _textured(
        assets,
        brick_maps(size, seed),
        1.0 / BRICK_TILE,
        1.0 / BRICK_TILE,
        1.0,
    )
    var stone = _textured(
        assets,
        stone_maps(size, seed + 1),
        1.0 / STONE_TILE,
        1.0 / STONE_TILE,
        0.9,
    )
    var slate = _textured(
        assets,
        slate_maps(size, seed + 2),
        1.0 / SLATE_WIDTH,
        1.0 / SLATE_HEIGHT,
        1.0,
    )
    var lawn = _textured(
        assets,
        grass_maps(size, seed + 3),
        1.0 / GRASS_TILE,
        1.0 / GRASS_TILE,
        0.6,
    )
    var gravel = _textured(
        assets,
        gravel_maps(size, seed + 4),
        1.0 / GRAVEL_TILE,
        1.0 / GRAVEL_TILE,
        1.0,
    )
    var leaves = SurfaceMaterial(
        Color(255, 255, 255),
        assets.textures.add(leaf_texture(size // 2, seed + 5)),
        DOUBLE_SIDE,
        kind=STANDARD,
        vertex_colors=True,
        roughness=0.75,
        alpha_test=0.5,
        env_map=SCENE_ENVIRONMENT,
    )
    var needles = SurfaceMaterial(
        Color(255, 255, 255),
        assets.textures.add(needle_texture(size // 2, seed + 6)),
        DOUBLE_SIDE,
        kind=STANDARD,
        vertex_colors=True,
        roughness=0.8,
        alpha_test=0.5,
        env_map=SCENE_ENVIRONMENT,
    )
    var trunk = SurfaceMaterial(
        Color(84, 70, 60),
        NO_TEXTURE,
        FRONT_SIDE,
        kind=STANDARD,
        roughness=0.95,
        env_map=SCENE_ENVIRONMENT,
    )
    var glass = _plain(Color(255, 255, 255), 0.05, 0.0)
    glass.env_map_intensity = 1.4
    # The order is the order of the kinds.
    materials.append(assets.materials.add(brick))
    materials.append(assets.materials.add(stone))
    materials.append(assets.materials.add(slate))
    materials.append(
        assets.materials.add(_plain(Color(255, 255, 255), 0.05, 0.0))
    )
    materials.append(assets.materials.add(lawn))
    materials.append(assets.materials.add(gravel))
    materials.append(assets.materials.add(leaves))
    materials.append(assets.materials.add(glass))
    materials.append(
        assets.materials.add(_plain(Color(255, 255, 255), 0.7, 0.0))
    )
    materials.append(
        assets.materials.add(_plain(Color(255, 255, 255), 0.5, 0.25))
    )
    materials.append(
        assets.materials.add(_plain(Color(255, 255, 255), 0.95, 0.0))
    )
    return CastleLook(
        materials^,
        assets.materials.add(trunk),
        assets.materials.add(needles),
    )
