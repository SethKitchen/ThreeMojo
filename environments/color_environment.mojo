# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An environment of one color, from three.js
`examples/jsm/environments/ColorEnvironment.js`.

`color_environment` is a scene that holds one unlit sphere, seen from
inside, in one color: three.js's `SphereGeometry( 1, 16, 16 )` with a
`MeshBasicMaterial` on its `BackSide`. Drawn into a cube by
`renderers.environment.pmrem_from_scene`, it gives an environment that is
the same in every direction. A physical surface then reflects the color
and is lit by it evenly, with no image file and no light.

    var white = color_environment(assets, Color(255, 255, 255))
    scene.environment = assets.cube_textures.add(
        pmrem_from_scene(renderer, white, assets)
    )

The sphere is `BASIC`, so no light changes its color. Its color is
decoded from sRGB to linear light, as every color of a material is. Its
radius is one meter, between the default near and far planes of
`pmrem_from_scene`, and it hides the background in every direction.

**Where this differs from three.js.** `dispose` has no counterpart, as
the assets own the geometry and the material.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from materials.material import BACK_SIDE, BASIC, Material
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import Length, METER

# three.js's sphere: a radius of one, and sixteen segments each way.
comptime COLOR_ENVIRONMENT_RADIUS = Length(1.0, METER)
comptime COLOR_ENVIRONMENT_SEGMENTS = 16


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
    var geometry = assets.geometries.add(
        sphere(
            COLOR_ENVIRONMENT_RADIUS,
            COLOR_ENVIRONMENT_SEGMENTS,
            COLOR_ENVIRONMENT_SEGMENTS,
        )
    )
    var paint = assets.materials.add(
        Material(color, side=BACK_SIDE, kind=BASIC)
    )
    scene.add_mesh(Mesh(geometry, paint, scene.add(Object3D())))
    scene.update()
    return scene^
