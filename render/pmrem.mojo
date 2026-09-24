# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Prefiltered, mipmapped radiance environment maps, from three.js
`src/extras/PMREMGenerator.js`.

A rough surface reflects its environment blurred by its lobe: the rougher,
the wider. Blurring per fragment is far too slow, so three.js blurs once,
ahead of time, for a ladder of roughnesses, and a fragment reads the two
rungs either side of its own and mixes them. That ladder is a PMREM. Its
layout, and how a roughness picks its rungs, is `render.cube_uv`.

`pmrem_from_cube` and `pmrem_from_equirectangular` are three.js's
`fromCubemap` and `fromEquirectangular`. Each returns a `CubeTexture` that
holds the source's six faces, which every reader but a physical surface
still reads, and the prefiltered image in `cube_uv`. Name it as an env map
or as a scene's environment as any cube is named. three.js's `fromScene`
is `Renderer.render_cube` followed by `pmrem_from_cube`.

**The arithmetic is three.js's, run on the host.** The sharpest copy is the
source read in every texel's own direction. Each copy after it is the one
before blurred by a Gaussian on the sphere, whose angle grows with the
copy so that the blurs compound to the copy's own `sigma`: `1 / size` for
the halving copies and three.js's `EXTRA_LOD_SIGMA` for the six beyond
them. three.js chose those numbers to approximate the GGX (Trowbridge-
Reitz) lobe times its shadowing term at each roughness, and
`roughness_to_mip` is the matching table. Each blur is two passes, around a
pole and then toward it, about one of ten axes spread over the sphere,
a different one each time so no pole's error piles up.

**Where this differs from three.js.** The image holds 32-bit floats where
three.js renders half floats, so light keeps more precision. A source
smaller than sixteen texels a face is read at sixteen, where three.js's
layout breaks down. A mirror read of a prefiltered cube reads its faces
rather than the sharpest copy, which holds the same image.
"""

from math.vector3 import Vector3
from render.framebuffer import FloatColor
from render.cube_texture import (
    CubeTexture,
    cube_from_equirectangular,
    cube_uv_width,
    equirect_uv,
)
from render.cube_uv import (
    CUBE_UV_EXTRA_COPIES,
    CUBE_UV_MIN_MIP,
    CubeUvCopy,
    cube_uv_copy,
    cube_uv_direction,
)
from render.texture import (
    BILINEAR,
    CLAMP,
    CUBE_UV_REFLECTION_MAPPING,
    IGNORED,
    Texture,
    float_texture,
)
from std.math import cos, exp, floor, log2, pi, sin, sqrt

# The most taps either side of the center a blur takes: three.js's
# `MAX_SAMPLES`.
comptime MAX_SAMPLES = 20
# Where a blur's taps stop, in standard deviations.
comptime STANDARD_DEVIATIONS = 3
# The golden ratio and its inverse, for the dodecahedron's axes.
comptime _PHI = Float32(1.6180339887498949)
comptime _INV_PHI = Float32(0.6180339887498949)


def extra_lod_sigma() -> List[Float32]:
    """Return the standard deviations, in radians, of the six copies past
    the last halving: three.js's `EXTRA_LOD_SIGMA`.

    Returns:
        Six angles, rising, chosen by three.js to approximate the GGX lobe
        at the roughnesses `roughness_to_mip` maps onto those copies.
    """
    return [0.125, 0.215, 0.35, 0.446, 0.526, 0.582]


def pole_axis(index: Int) -> Vector3:
    """Return one of the ten axes a blur turns about: three.js's
    `_axisDirections`, the vertices of a dodecahedron less their
    opposites.

    Args:
        index: Zero to nine; taken modulo ten.

    Returns:
        The axis, not normalized.
    """
    var at = index % 10
    if at == 0:
        return Vector3(-_PHI, _INV_PHI, 0)
    if at == 1:
        return Vector3(_PHI, _INV_PHI, 0)
    if at == 2:
        return Vector3(-_INV_PHI, 0, _PHI)
    if at == 3:
        return Vector3(_INV_PHI, 0, _PHI)
    if at == 4:
        return Vector3(0, _PHI, -_INV_PHI)
    if at == 5:
        return Vector3(0, _PHI, _INV_PHI)
    if at == 6:
        return Vector3(-1, 1, -1)
    if at == 7:
        return Vector3(1, 1, -1)
    if at == 8:
        return Vector3(-1, 1, 1)
    return Vector3(1, 1, 1)


def pmrem_lod_max(size: Int) -> Int:
    """Return the sharpest copy's mip for a source of some size: three.js's
    `_setSize`, which rounds down to a power of two.

    Args:
        size: The face size, or a quarter of a panorama's width.

    Returns:
        The base-two logarithm, rounded down, and at least four: a source
        smaller than sixteen texels is read at sixteen.
    """
    var lod = CUBE_UV_MIN_MIP
    while (2 << lod) <= size:
        lod += 1
    return lod


@fieldwise_init
struct _Ladder(Movable):
    """Every copy's tile size and its blur, three.js's `_createPlanes`."""

    var sizes: List[Int]
    var sigmas: List[Float32]


def _ladder(lod_max: Int) -> _Ladder:
    """Return the tile size and standard deviation of every copy."""
    var sizes = List[Int]()
    var sigmas = List[Float32]()
    var extra = extra_lod_sigma()
    var lod = lod_max
    var total = lod_max - CUBE_UV_MIN_MIP + 1 + CUBE_UV_EXTRA_COPIES
    for index in range(total):  # pragma: no branch
        var size = 1 << lod
        sizes.append(size)
        var sigma = Float32(1) / Float32(size)
        if index > lod_max - CUBE_UV_MIN_MIP:
            sigma = extra[index - lod_max + CUBE_UV_MIN_MIP - 1]
        elif index == 0:
            sigma = 0
        sigmas.append(sigma)
        lod = max(lod - 1, CUBE_UV_MIN_MIP)
    return _Ladder(sizes^, sigmas^)


@fieldwise_init
struct _Region(ImplicitlyCopyable):
    """Where one copy sits in the layout image, from the bottom left."""

    var x: Int
    var y: Int
    var size: Int


def _region(index: Int, size: Int, lod_max: Int) -> _Region:
    """Return where copy `index` of tile size `size` sits: three.js's
    viewport for it."""
    var extra = max(index - (lod_max - CUBE_UV_MIN_MIP), 0)
    return _Region(3 * size * extra, 4 * ((1 << lod_max) - size), size)


def _texel_direction(region: _Region, face: Int, x: Int, y: Int) -> Vector3:
    """Return the direction a texel of one tile stands for, the border
    included: three.js's plane corners interpolated to the texel's center.

    `x` and `y` count from the tile's bottom left.
    """
    var texel = Float32(1) / Float32(region.size - 2)
    var span = 1 + 2 * texel
    var u = -texel + (Float32(x) + 0.5) / Float32(region.size) * span
    var v = -texel + (Float32(y) + 0.5) / Float32(region.size) * span
    return cube_uv_direction(u, v, face)


def _store(
    mut image: Texture,
    column: Int,
    row_up: Int,
    red: Float32,
    green: Float32,
    blue: Float32,
):
    """Write one texel, counting rows up from the bottom as three.js's
    viewport does, alpha one."""
    var at = ((image.height - 1 - row_up) * image.width + column) * 4
    image.data[at] = red
    image.data[at + 1] = green
    image.data[at + 2] = blue
    image.data[at + 3] = 1


def _blank_layout(lod_max: Int) raises -> Texture:
    """Return a layout image of the right size, every texel zero."""
    var width = cube_uv_width(lod_max)
    var height = 4 << lod_max
    var data = List[Float32](length=width * height * 4, fill=0)
    var layout = float_texture(
        width, height, data^, CLAMP, BILINEAR, False, IGNORED
    )
    # three.js's PMREM texture is `CubeUVReflectionMapping`.
    layout.mapping = CUBE_UV_REFLECTION_MAPPING
    return layout^


def blur_axis(latitudinal: Bool, pole: Vector3, direction: Vector3) -> Vector3:
    """Return the axis one blur pass turns a texel's direction about: the
    top of three.js's `SphericalGaussianBlur` shader.

    Around the pole for the latitudinal pass, and across it for the
    longitudinal one. A direction along the pole has no across, and turns
    about the axis three.js falls back on.

    Args:
        latitudinal: True for the first pass, False for the second.
        pole: The pass's axis, `pole_axis`.
        direction: The texel's direction.

    Returns:
        The unit axis.
    """
    var axis = pole
    if not latitudinal:
        axis.cross(direction)
    if axis.x == 0 and axis.y == 0 and axis.z == 0:
        axis = Vector3(direction.z, 0, -direction.x)
    axis.normalize()
    return axis


@fieldwise_init
struct _Taps(Movable):
    """One blur pass's taps, worked out once for every texel of the pass:
    step `index` turns by `index` pixels' worth of angle either way."""

    # Each step's weight, already divided by the sum of them all.
    var weights: List[Float32]
    # The cosine and sine of each step's turn, the plus side and the minus.
    var plus_cosines: List[Float32]
    var plus_sines: List[Float32]
    var minus_cosines: List[Float32]
    var minus_sines: List[Float32]


def _taps(
    samples: Int, sigma_pixels: Float32, radians_per_pixel: Float32
) -> _Taps:
    """Return a pass's taps: three.js's Gaussian weights, normalized, and
    the turn of each step."""
    var weights = List[Float32]()
    var sum = Float32(0)
    for index in range(samples):  # pragma: no branch
        var x = Float32(index) / sigma_pixels
        var weight = exp(-x * x / 2)
        weights.append(weight)
        sum += weight if index == 0 else 2 * weight
    var taps = _Taps(
        List[Float32](),
        List[Float32](),
        List[Float32](),
        List[Float32](),
        List[Float32](),
    )
    # `samples` is at least one, so this never runs zero times.
    for index in range(samples):  # pragma: no branch
        var theta = radians_per_pixel * Float32(index)
        taps.weights.append(weights[index] / sum)
        taps.plus_cosines.append(cos(theta))
        taps.plus_sines.append(sin(theta))
        taps.minus_cosines.append(cos(-theta))
        taps.minus_sines.append(sin(-theta))
    return taps^


def _turned(
    direction: Vector3,
    axis: Vector3,
    dot: Float32,
    cosine: Float32,
    sine: Float32,
) -> Vector3:
    """Return `direction` turned about a unit axis by the angle whose cosine
    and sine are given: Rodrigues' rotation, as the blur shader's
    `getSample` writes it. `dot` is the axis dotted with the direction."""
    var across = axis
    across.cross(direction)
    var along = dot * (1 - cosine)
    return Vector3(
        direction.x * cosine + across.x * sine + axis.x * along,
        direction.y * cosine + across.y * sine + axis.y * along,
        direction.z * cosine + across.z * sine + axis.z * along,
    )


def _tap(
    source: Texture,
    copy: CubeUvCopy,
    direction: Vector3,
    axis: Vector3,
    dot: Float32,
    cosine: Float32,
    sine: Float32,
) -> FloatColor:
    """Return one copy of `source` read in a turned direction: the blur
    shader's `getSample`."""
    var place = copy.coordinate(_turned(direction, axis, dot, cosine, sine))
    return source.sample(place.x, place.y)


def _half_blur(
    source: Texture,
    mut target: Texture,
    ladder: _Ladder,
    lod_max: Int,
    lod_in: Int,
    lod_out: Int,
    sigma: Float32,
    latitudinal: Bool,
    pole: Vector3,
):
    """Blur copy `lod_in` of `source` into copy `lod_out` of `target`, one
    way: three.js's `_halfBlur` and its shader.

    What is the same for every texel is worked out once a pass: the
    weights, each step's sine and cosine, and where the copy sits. The
    sums run in the shader's order."""
    var pixels = ladder.sizes[lod_in] - 1
    var radians_per_pixel = Float32(pi) / Float32(2 * pixels)
    var sigma_pixels = sigma / radians_per_pixel
    var samples = min(
        1 + Int(floor(STANDARD_DEVIATIONS * sigma_pixels)), MAX_SAMPLES
    )
    var taps = _taps(samples, sigma_pixels, radians_per_pixel)
    var copy = cube_uv_copy(
        Float32(lod_max - lod_in), lod_max, source.width, source.height
    )
    var region = _region(lod_out, ladder.sizes[lod_out], lod_max)
    for face in range(6):  # pragma: no branch
        var left = region.x + (face % 3) * region.size
        var bottom = region.y + (region.size if face > 2 else 0)
        for y in range(region.size):  # pragma: no branch
            for x in range(region.size):  # pragma: no branch
                var direction = _texel_direction(region, face, x, y)
                var axis = blur_axis(latitudinal, pole, direction)
                var dot = axis.dot(direction)
                var center = _tap(
                    source,
                    copy,
                    direction,
                    axis,
                    dot,
                    taps.plus_cosines[0],
                    taps.plus_sines[0],
                )
                var weight = taps.weights[0]
                var red = weight * center.r
                var green = weight * center.g
                var blue = weight * center.b
                # At least four taps for every copy's sigma, so this loop
                # never runs zero times.
                for index in range(1, samples):  # pragma: no branch
                    weight = taps.weights[index]
                    var minus = _tap(
                        source,
                        copy,
                        direction,
                        axis,
                        dot,
                        taps.minus_cosines[index],
                        taps.minus_sines[index],
                    )
                    red += weight * minus.r
                    green += weight * minus.g
                    blue += weight * minus.b
                    var plus = _tap(
                        source,
                        copy,
                        direction,
                        axis,
                        dot,
                        taps.plus_cosines[index],
                        taps.plus_sines[index],
                    )
                    red += weight * plus.r
                    green += weight * plus.g
                    blue += weight * plus.b
                _store(target, left + x, bottom + y, red, green, blue)


def _layout(
    source: CubeTexture, lod_max: Int, panorama: Texture, from_panorama: Bool
) raises -> Texture:
    """Return the PMREM image: the sharpest copy filled from the source,
    then every copy after it blurred from the one before: three.js's
    `_textureToCubeUV` and `_applyPMREM`.

    The sharpest copy reads `panorama` at `equirect_uv` when
    `from_panorama`, and `source` in each direction otherwise."""
    var ladder = _ladder(lod_max)
    var layout = _blank_layout(lod_max)
    var ping = _blank_layout(lod_max)
    var first = _region(0, ladder.sizes[0], lod_max)
    for face in range(6):  # pragma: no branch
        var left = first.x + (face % 3) * first.size
        var bottom = first.y + (first.size if face > 2 else 0)
        for y in range(first.size):  # pragma: no branch
            for x in range(first.size):  # pragma: no branch
                var direction = _texel_direction(first, face, x, y)
                var seen: FloatColor
                if from_panorama:
                    var place = equirect_uv(direction)
                    seen = panorama.sample(place.x, place.y)
                else:
                    seen = source.sample(direction)
                _store(layout, left + x, bottom + y, seen.r, seen.g, seen.b)
    var count = len(ladder.sizes)
    # Seven copies at the least, so this never runs zero times.
    for index in range(1, count):  # pragma: no branch
        var sigma = sqrt(
            ladder.sigmas[index] * ladder.sigmas[index]
            - ladder.sigmas[index - 1] * ladder.sigmas[index - 1]
        )
        var pole = pole_axis(count - index - 1)
        _half_blur(
            layout, ping, ladder, lod_max, index - 1, index, sigma, True, pole
        )
        _half_blur(
            ping, layout, ladder, lod_max, index, index, sigma, False, pole
        )
    return layout^


def pmrem_from_cube(cube: CubeTexture) raises -> CubeTexture:
    """Return a cube texture prefiltered for every roughness: three.js's
    `PMREMGenerator.fromCubemap`.

    The copies are sized from the faces, as three.js sizes them: the
    sharpest is the face size rounded down to a power of two, and at least
    sixteen.

    Args:
        cube: The environment. Byte or float faces, any color space; it is
            read in linear light through `CubeTexture.sample`.

    Returns:
        A copy of the cube, with its PMREM in `cube_uv`.

    Raises:
        Error: If the cube is refused by `CubeTexture.validate`.
    """
    cube.validate()
    var out = CubeTexture(copy=cube)
    out.cube_uv = _layout(cube, pmrem_lod_max(cube.size), Texture(), False)
    out.validate()
    return out^


def pmrem_from_equirectangular(image: Texture) raises -> CubeTexture:
    """Return a cube texture prefiltered for every roughness from a
    panorama: three.js's `PMREMGenerator.fromEquirectangular`.

    The sharpest copy reads the panorama at `equirect_uv` of each texel's
    direction, as three.js's `EquirectangularToCubeUV` shader does, so the
    panorama is resampled once. The copies are sized from a quarter of
    its width, as three.js sizes them. The six faces are
    `cube_from_equirectangular` at the sharpest copy's size.

    Args:
        image: The panorama, byte or float.

    Returns:
        The cube texture, with its PMREM in `cube_uv`. A panorama whose
        `mapping` is equirectangular is kept in the cube too, as
        `cube_of_panorama` keeps it, so every reader but the PMREM's
        samples it directly.

    Raises:
        Error: If the panorama is blank or refused by `Texture.validate`.
    """
    var lod_max = pmrem_lod_max(image.width // 4)
    var faces = cube_from_equirectangular(image, 1 << lod_max, False)
    var layout = _layout(faces, lod_max, image, True)
    faces.cube_uv = layout^
    if image.mapping.is_equirectangular():
        faces.panorama = Texture(copy=image)
        faces.mapping = image.mapping
    faces.validate()
    return faces^
