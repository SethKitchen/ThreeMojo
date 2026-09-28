# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Baking a box of light probes, from three.js
`examples/jsm/lighting/LightProbeGridUtils.js`.

three.js bakes a `LightProbeGrid` by drawing the scene into a cube at
each probe with a `CubeCamera` and projecting the cube onto the nine
spherical harmonic terms. `bake_light_probe_grid` does the same with
`renderers.environment.scene_cube` and `lights.light_probe.sh_from_cube`.
It is here, beside the renderer, and not in `lights/`, because it draws.

Each probe is drawn with the renderer's settings and without its own
probe grid, so a grid is not baked from its own light. Bake again when
the scene's lights or objects move.
"""

from core.assets import Assets
from core.scene import Scene
from lights.light_probe import sh_from_cube
from lights.light_probe_grid import LightProbeGrid
from renderers.environment import scene_cube
from renderers.renderer import Renderer
from units.si import Length, METER

# How many texels a side each probe's cube is by default. The nine terms
# keep only the blur of the light, so a small cube loses little.
comptime DEFAULT_PROBE_CUBE_SIZE = 16
# Each probe's cube's planes by default: a tenth of a meter to a hundred,
# as `renderers.environment` draws a scene.
comptime DEFAULT_PROBE_NEAR = Length(0.1, METER)
comptime DEFAULT_PROBE_FAR = Length(100.0, METER)


def bake_light_probe_grid(
    mut grid: LightProbeGrid,
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    size: Int = DEFAULT_PROBE_CUBE_SIZE,
    near: Length = DEFAULT_PROBE_NEAR,
    far: Length = DEFAULT_PROBE_FAR,
) raises:
    """Measure the light at every probe of a grid, three.js's
    `LightProbeGrid` bake.

    Args:
        grid: The grid. Its probes are replaced.
        renderer: What to take the drawing settings from.
        scene: The scene to measure, updated.
        assets: The geometry, materials and textures it names.
        size: How many texels a side each probe's cube is.
        near: Each cube's near plane.
        far: Each cube's far plane.

    Raises:
        Error: If the grid is refused by `LightProbeGrid.validate`, or
            `scene_cube` or `sh_from_cube` refuses a probe's cube.
    """
    grid.validate()
    for index in range(grid.count()):  # pragma: no branch
        var cube = scene_cube(
            renderer, scene, assets, near, far, size, grid.position(index)
        )
        grid.probes[index] = sh_from_cube(cube)
