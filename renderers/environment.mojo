# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The environments a scene reads through a PMREM, prefiltered once, from
three.js `src/renderers/webgl/WebGLCubeUVMaps.js`.

three.js's renderer prefilters an environment the first time a standard
or physical surface reflects it, or a blurred background shows it: a cube,
or a panorama with an equirectangular mapping, becomes a PMREM that
`WebGLCubeUVMaps` keeps beside the texture. Here the assets are the one
owner of every cube texture, and `Renderer.render` only reads them, so the
same work is one call before the frame: `prefilter_environments` gives
every such cube its PMREM, in place. A cube made from a panorama is
prefiltered from the panorama, as three.js's `fromEquirectangular` does,
and every other reader still samples the panorama directly.

A cube that is not prefiltered still draws: a physical surface then reads
down its mip chain, the stand-in `CubeTexture.sample_rough` describes.
`render.pmrem` builds the PMREM, and `loaders.object_loader` prefilters
what a scene JSON document names when it reads it.
"""

from core.assets import Assets
from core.background import CUBE_BACKGROUND
from core.scene import Scene
from materials.material import MaterialId
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from render.pmrem import pmrem_from_cube


def _prefilter(mut assets: Assets, id: CubeTextureId) raises -> Int:
    """Give one cube its PMREM unless it has one, and return how many were
    built: one or none.

    Raises:
        Error: If the id names no cube texture, or `pmrem_from_cube`
            refuses the cube.
    """
    if assets.cube_textures.get(id).is_prefiltered():
        return 0
    assets.cube_textures.textures[id.value] = pmrem_from_cube(
        assets.cube_textures.get(id)
    )
    return 1


def prefilter_environments(scene: Scene, mut assets: Assets) raises -> Int:
    """Give every environment a PMREM reader needs its PMREM, as three.js's
    renderer builds one on first use.

    The environments are each cube a standard or physical material names,
    the scene's `environment` when such a material reflects it, and the
    background's cube when `background_blurriness` is above zero. A cube
    that has a PMREM already is left as it is.

    Args:
        scene: The scene, for its environment and background.
        assets: Where the materials and the cube textures live.

    Returns:
        How many PMREMs were built.

    Raises:
        Error: If a material or the scene names a cube texture that is not
            there, `Scene.validate_environment` refuses the scene, or
            `pmrem_from_cube` refuses a cube.
    """
    scene.validate_environment()
    var built = 0
    for index in range(assets.materials.count()):
        var material = assets.materials.get(MaterialId(index))
        if not material.is_physical():
            continue
        var env = material.env_map
        if env == SCENE_ENVIRONMENT:
            env = scene.environment
        if env != NO_CUBE_TEXTURE:
            built += _prefilter(assets, env)
    var blurred = scene.background_blurriness > 0
    if blurred and scene.background.kind == CUBE_BACKGROUND:
        built += _prefilter(assets, scene.background.cube)
    return built
