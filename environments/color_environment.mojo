# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An environment of one color, from three.js
`examples/jsm/environments/ColorEnvironment.js`.

`color_environment` is a scene that holds one unlit box, seen from
inside, in one color. Drawn into a cube by
`renderers.environment.pmrem_from_scene`, it gives an environment that is
the same in every direction. A physical surface then reflects the color
and is lit by it evenly, with no image file and no light.

    var white = color_environment(assets, Color(255, 255, 255))
    scene.environment = assets.cube_textures.add(
        pmrem_from_scene(renderer, white, assets)
    )

The box is `BASIC`, so no light changes its color. Its color is decoded
from sRGB to linear light, as every color of a material is. The box is
two meters across, between the default near and far planes of
`pmrem_from_scene`, and it hides the background in every direction.

**Where this differs from three.js.** `dispose` has no counterpart, as
the assets own the geometry and the material.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import BACK_SIDE, BASIC, Material
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import Length, METER

# How far each face of the box is from its middle.
comptime COLOR_ENVIRONMENT_EXTENT = Length(1.0, METER)


def color_environment(
    mut assets: Assets, color: Color = Color(255, 255, 255)
) raises -> Scene:
    """Return three.js's `ColorEnvironment`: a scene that is one color in
    every direction.

    Args:
        assets: Where the geometry and the material go.
        color: The color, sRGB. White by default, as three.js's.

    Returns:
        The scene, updated. Draw it with
        `renderers.environment.pmrem_from_scene`.

    Raises:
        Error: If the material or the mesh is refused.
    """
    var scene = Scene()
    var geometry = assets.geometries.add(cube(COLOR_ENVIRONMENT_EXTENT.scaled(2)))
    var paint = assets.materials.add(
        Material(color, side=BACK_SIDE, kind=BASIC)
    )
    scene.add_mesh(Mesh(geometry, paint, scene.add(Object3D())))
    scene.update()
    return scene^
