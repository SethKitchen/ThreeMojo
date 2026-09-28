# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A spot light that projects a rectangle, from three.js
`src/lights/webgpu/ProjectorLight.js` and `ProjectorLightNode.js`.

A projector is a spot light whose beam is the rectangle its shadow
camera sees, not a cone. Its `aspect` is the rectangle's width over its
height. With no aspect, three.js takes the map's width over its height,
or one with no map. The map is projected through the same camera, so a
picture keeps its own proportions.

**The beam.** three.js's `ProjectorLightNode.getSpotAttenuation` takes
the fragment through the shadow matrix. Behind the light, where `w` is
not positive, the beam is zero. In front, it measures the signed
distance of the map coordinate to the square from zero to one, `sdBox`,
and fades the light in from the edge over a band set by the penumbra:

    const projectionUV = spotLightCoord.xyz.div( spotLightCoord.w );
    const boxDist = sdBox( projectionUV.xy.sub( vec2( 0.5 ) ), vec2( 0.5 ) );
    const angleFactor = div( -1.0, sub( 1.0, acos( penumbraCos ) ).sub( 1.0 ) );
    attenuation.assign( saturate( boxDist.mul( -2.0 ).mul( angleFactor ) ) );

`penumbraCos` is `min( cos( angle * ( 1 - penumbra ) ), 0.99999 )`, as
`ProjectorLightNode.update` sets it. `projector_attenuation` is that
arithmetic, and both backends call it.

**The frame.** The shadow camera is three.js's `SpotLightShadow`: twice
the cone's angle times `focus` high, `aspect` times as wide. The
renderer builds it; see `lights.spot_profile`.
"""

from core.object3d import NO_PARENT, NodeId
from lights.light import (
    ASPECT_FROM_MAP,
    DEFAULT_SPOT_ANGLE,
    Light,
    NO_CUTOFF,
    PHYSICAL_DECAY,
    PROJECTOR_SPOT,
    spot_light,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from render.texture_store import NO_TEXTURE, TextureStore
from std.math import acos, max, min, sqrt
from units.si import Angle

# three.js's cap on a projector's penumbra cosine, so that the arc in the
# fade is never zero.
comptime PROJECTOR_PENUMBRA_CAP = Float32(0.99999)


def sd_box(x: Float32, y: Float32, half: Float32) -> Float32:
    """Return the signed distance from a point to a square about the
    origin, three.js's `sdBox`: negative inside, zero on the edge.

    Args:
        x: The point's first coordinate.
        y: The point's second coordinate.
        half: Half the square's side, three.js's `b`.

    Returns:
        `length( max( d, 0 ) ) + min( max( d.x, d.y ), 0 )`, with
        `d = abs( p ) - b`.
    """
    var dx = abs(x) - half
    var dy = abs(y) - half
    var ox = max(dx, Float32(0))
    var oy = max(dy, Float32(0))
    return sqrt(ox * ox + oy * oy) + min(max(dx, dy), Float32(0))


def projector_attenuation(
    frame: SIMD[DType.float32, 16], position: Vector3, penumbra_cos: Float32
) -> Float32:
    """Return how much of a projector's light reaches a world position,
    three.js's `ProjectorLightNode.getSpotAttenuation`.

    Both backends call it.

    Args:
        frame: World space to the light's clip space, column major, as
            `lights.shadow.ShadowMap.frame`.
        position: The world position, with no normal bias, as three.js
            reads `positionWorld`.
        penumbra_cos: `cos( angle * ( 1 - penumbra ) )`. Capped here at
            `PROJECTOR_PENUMBRA_CAP`.

    Returns:
        From zero outside the rectangle, or behind the light, to one
        well inside it.
    """
    var x = (
        frame[0] * position.x
        + frame[4] * position.y
        + frame[8] * position.z
        + frame[12]
    )
    var y = (
        frame[1] * position.x
        + frame[5] * position.y
        + frame[9] * position.z
        + frame[13]
    )
    var w = (
        frame[3] * position.x
        + frame[7] * position.y
        + frame[11] * position.z
        + frame[15]
    )
    if w <= 0:
        return 0
    # The shadow matrix's half and half: a map coordinate from zero to
    # one, less its middle, is half the normalized device coordinate.
    var u = x / w * 0.5
    var v = y / w * 0.5
    var box = sd_box(u, v, 0.5)
    var capped = min(penumbra_cos, PROJECTOR_PENUMBRA_CAP)
    var angle_factor = Float32(-1.0) / ((Float32(1.0) - acos(capped)) - 1.0)
    return min(max(box * -2.0 * angle_factor, Float32(0)), Float32(1))


def projector_aspect(light: Light, textures: TextureStore) raises -> Float32:
    """Return a spot light's shadow camera's width over its height, as
    three.js's `ProjectorLightNode.update` sets `shadow.aspect`.

    A projector's own `aspect` when it has one; else its map's width over
    its height; else one. Every other spot light is one, three.js's
    `SpotLightShadow.aspect`.

    Args:
        light: The light.
        textures: The store the map is in.

    Returns:
        The aspect.

    Raises:
        Error: If the map is not in the store.
    """
    if light.spot_shape != PROJECTOR_SPOT:
        return 1
    if light.aspect != ASPECT_FROM_MAP:
        return light.aspect
    if light.map == NO_TEXTURE:
        return 1
    ref image = textures.get(light.map)
    return Float32(image.width) / Float32(image.height)


def projector_light(
    color: Color,
    node: NodeId,
    intensity: Float32 = 1.0,
    distance: Float32 = NO_CUTOFF,
    angle: Angle = DEFAULT_SPOT_ANGLE,
    penumbra: Float32 = 0.0,
    decay: Float32 = PHYSICAL_DECAY,
    target: NodeId = NO_PARENT,
    aspect: Float32 = ASPECT_FROM_MAP,
) raises -> Light:
    """Return a spot light that projects a rectangle, three.js's
    `ProjectorLight`.

    The numbers are `spot_light`'s, in its order, and then `aspect`. Set
    `map` to project a picture as well.

    Args:
        color: Its color.
        node: The node whose world position the light shines from.
        intensity: How bright at one meter, multiplying the color.
        distance: Where the light stops. Zero for no cutoff.
        angle: Half the height of the rectangle's camera.
        penumbra: How wide the fade in from the rectangle's edge is.
        decay: The power of distance the light is divided by.
        target: The node the light points at, or `NO_PARENT` for the
            world origin.
        aspect: The rectangle's width over its height, or
            `ASPECT_FROM_MAP`, three.js's `null`.

    Returns:
        The light, a `SPOT` of shape `PROJECTOR_SPOT`.

    Raises:
        Error: If `spot_light` refuses the numbers, or the aspect is
            negative or not finite. See `Light.validate`.
    """
    var light = spot_light(
        color, node, intensity, distance, angle, penumbra, decay, target
    )
    light.spot_shape = PROJECTOR_SPOT
    light.aspect = aspect
    light.validate()
    return light
