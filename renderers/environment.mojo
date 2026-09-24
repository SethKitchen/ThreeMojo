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

**An environment can be a scene.** `pmrem_from_scene` is three.js's
`PMREMGenerator.fromScene`: it draws a scene six times from one point in
linear light, with no tone mapping, and prefilters the six faces. A scene
of glowing panels, such as `environments.room_environment`, lights a
physical surface as a studio would.
"""

from cameras.cube_camera import CubeCamera
from core.assets import Assets
from core.background import CUBE_BACKGROUND
from core.scene import Scene
from materials.material import MaterialId
from math.vector3 import Vector3
from render.cube_texture import FACE_COUNT, CubeTexture
from render.target import FLOAT_TARGET, RenderTarget
from render.texture import BILINEAR, CLAMP, IGNORED, Texture, float_texture
from renderers.renderer import Renderer
from units.si import Angle, Length, METER, RADIAN
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from render.pmrem import pmrem_from_cube, pmrem_from_faces

# three.js's `fromScene` defaults: a face 256 texels a side, seen from a
# tenth of a meter to a hundred.
comptime DEFAULT_SCENE_SIZE = 256
comptime DEFAULT_SCENE_NEAR = Length(0.1, METER)
comptime DEFAULT_SCENE_FAR = Length(100.0, METER)


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


def pmrem_from_scene(
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    sigma: Angle = Angle(0.0, RADIAN),
    near: Length = DEFAULT_SCENE_NEAR,
    far: Length = DEFAULT_SCENE_FAR,
    size: Int = DEFAULT_SCENE_SIZE,
    position: Vector3 = Vector3(0, 0, 0),
) raises -> CubeTexture:
    """Draw a scene into a cube around a point and prefilter it for every
    roughness: three.js's `PMREMGenerator.fromScene`.

    Each face is drawn through a ninety-degree camera by a renderer of the
    face's size with `renderer`'s background, shading, depth mode, clipping
    and workers, into a float target, so light above one survives: a
    panel that glows at fifty stays at fifty. Nothing is tone mapped, as
    three.js turns the tone mapping off. The background is the scene's
    color, or the renderer's when the scene has none, as three.js paints
    its clear color behind the scene. Only layer zero is drawn, as
    three.js's cube camera draws only it.

    Args:
        renderer: What to take the drawing settings from.
        scene: The scene to draw, updated.
        assets: The geometry, materials and textures it names.
        sigma: How far to blur the sharpest copy before the rest are
            made, a standard deviation on the sphere. Zero, the default,
            blurs nothing.
        near: Each face's near plane.
        far: Each face's far plane.
        size: How many texels a side each face is; the PMREM's sharpest
            copy is this rounded down to a power of two.
        position: Where to stand, in world space.

    Returns:
        The six faces as float textures, with the PMREM in `cube_uv`.
        Name it as a scene's environment or a material's env map.

    Raises:
        Error: If `CubeCamera` refuses the size or the planes, `render_into`
            refuses the scene, or `pmrem_from_faces` refuses the sigma.
    """
    var camera = CubeCamera(near, far, size)
    camera.place(position)
    var side = Renderer(size, size, renderer.workers)
    side.background = renderer.background
    side.shading = renderer.shading
    side.depth_mode = renderer.depth_mode
    side.local_clipping_enabled = renderer.local_clipping_enabled
    side.shadow_map_type = renderer.shadow_map_type
    var faces = List[Texture]()
    for face in range(FACE_COUNT):  # pragma: no branch
        var target = RenderTarget(
            size, size, side.clear_color(scene), FLOAT_TARGET
        )
        side.render_into(target, scene, assets, camera.face_camera(face, scene))
        var data = List[Float32](capacity=size * size * 4)
        for slot in range(size * size):  # pragma: no branch
            var seen = target.straight_at(slot)
            data.append(seen.r)
            data.append(seen.g)
            data.append(seen.b)
            data.append(1)
        faces.append(
            float_texture(size, size, data^, CLAMP, BILINEAR, False, IGNORED)
        )
    return pmrem_from_faces(CubeTexture(faces^), sigma)
