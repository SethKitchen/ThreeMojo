# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A light probe measured from a cube texture, from three.js
`examples/jsm/lights/LightProbeGenerator.js`.

`sh_from_cube` projects every texel of the six faces onto the nine
spherical harmonics, weighted by the solid angle the texel covers, which is
three.js's `LightProbeGenerator.fromCubeTexture`. The same function serves
for `fromCubeRenderTarget`: `Renderer.render_cube` returns a `CubeTexture`,
so a probe of a rendered scene is `light_probe_from_cube` of that.

**One difference, and it is the convention.** three.js walks each face with
its own table of where the texel is, one that mirrors the faces left for
right as the OpenGL cube map layout does. A cube texture here holds one
convention, the camera's, settled when its images arrive; see
`render.cube_texture`. So the direction through a texel is
`face_direction`, the same one every sampler here inverts, and a probe of a
sky that is red toward +x is red toward +x.
"""

from lights.light import Light, light_probe
from math.spherical_harmonics3 import (
    SH_COUNT,
    SphericalHarmonics3,
    sh_basis,
)
from math.vector3 import Vector3
from render.cube_texture import FACE_COUNT, CubeTexture, face_direction
from std.math import pi, sqrt


def sh_from_cube(cube: CubeTexture) raises -> SphericalHarmonics3:
    """Return the nine spherical harmonic coefficients of a cube texture's
    light: the projection at the heart of three.js's
    `LightProbeGenerator.fromCubeTexture`.

    Every texel of every face at its full size, decoded to linear light,
    times `sh_basis` of the direction through its center, times the solid
    angle it covers, `4 / length^3` of that direction on the unit cube.
    The sums are then scaled so the weights total the whole sphere, four
    pi, as three.js normalizes them. Alpha is not light and is not read.

    Args:
        cube: The environment. Its faces are read as they are held.

    Returns:
        The coefficients, linear.

    Raises:
        Error: If the cube is refused by `CubeTexture.validate`.
    """
    cube.validate()
    var sh = SphericalHarmonics3()
    var total_weight = Float32(0)
    var size = cube.size
    # Six faces, each at least one texel, so no loop here runs zero times.
    for face in range(FACE_COUNT):  # pragma: no branch
        ref image = cube.faces[face]
        for y in range(size):  # pragma: no branch
            for x in range(size):  # pragma: no branch
                var color = image.wrapped_texel(x, y, 0)
                var coord = face_direction(face, x, y, size)
                var length_sq = coord.dot(coord)
                var weight = 4 / (sqrt(length_sq) * length_sq)
                total_weight += weight
                var direction = coord
                direction.normalize()
                for index in range(SH_COUNT):  # pragma: no branch
                    var basis = sh_basis(index, direction)
                    var at = index * 3
                    sh.lanes[at] += basis * color.r * weight
                    sh.lanes[at + 1] += basis * color.g * weight
                    sh.lanes[at + 2] += basis * color.b * weight
    sh.scale(4 * Float32(pi) / total_weight)
    return sh


def light_probe_from_cube(
    cube: CubeTexture, intensity: Float32 = 1.0
) raises -> Light:
    """Return a light probe that lights a surface as a cube texture's
    environment would: three.js's `LightProbeGenerator.fromCubeTexture`.

    Add it to a scene as any light is added. Only its irradiance is kept,
    so it lights matte surfaces and the diffuse term of physical ones; a
    reflection needs the cube itself, named as an env map.

    Args:
        cube: The environment.
        intensity: What every coefficient is multiplied by.

    Returns:
        The light, of kind `LIGHT_PROBE`.

    Raises:
        Error: If the cube is refused by `CubeTexture.validate`, or the
            intensity is negative or not finite.
    """
    return light_probe(sh_from_cube(cube), intensity)
