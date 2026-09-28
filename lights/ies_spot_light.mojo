# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A spot light shaped by a measured profile, from three.js
`src/lights/webgpu/IESSpotLight.js` and `IESSpotLightNode.js`.

An IES file says how bright a lamp is at each angle from its axis.
`loaders.ies.ies_texture` stores it as a texture, one texel for each
whole degree from zero to 179 across, one row for each horizontal
degree. three.js's `IESSpotLightNode.getSpotAttenuation` reads the first
row at `acos(angleCos) / pi` and takes its red, where a plain spot light
takes `smoothstep` of its cone:

    const angle = angleCosine.acos().mul( 1.0 / Math.PI );
    spotAttenuation = texture( iesMap, vec2( angle, 0 ), 0 ).r;

The profile replaces the cone. The light keeps its distance falloff, its
shadow and its map. With no profile the light keeps its cone, as
three.js's does when `iesMap` is null.

**Both backends read the same texel.** `ies_coordinate` gives the
coordinate. The host reads the texture with `Texture.sample_level`, and
the kernel reads the store's own copy through the same filter, as it
reads a spot light's map. The first row is read at its outer edge, where
a clamped texture gives the first row alone, as three.js's texture one
row high does. See `lights.spot_profile`.

**Where this port differs.** The cosine is clamped to minus one to one
before its arc is taken. GLSL leaves the arc of a number past one
undefined, and a dot product of two unit vectors can round past it.
"""

from core.object3d import NO_PARENT, NodeId
from lights.light import (
    DEFAULT_SPOT_ANGLE,
    IES_SPOT,
    Light,
    NO_CUTOFF,
    PHYSICAL_DECAY,
    spot_light,
)
from render.framebuffer import Color
from render.texture import row_coordinate
from render.texture_store import TextureId
from std.math import acos, max, min, pi
from units.si import Angle


@fieldwise_init
struct IesCoordinate(ImplicitlyCopyable):
    """Where an IES profile is read for one angle from the axis."""

    # Across the profile: the angle from the axis, from zero on the axis
    # to one straight back.
    var u: Float32
    # Down the texture: the first row, in the texture's own sense of `v`.
    var v: Float32


def ies_coordinate(angle_cos: Float32, flip_y: Bool) -> IesCoordinate:
    """Return where an IES profile is read for a cosine off the axis,
    three.js's `vec2( angleCosine.acos().mul( 1.0 / Math.PI ), 0 )`.

    Both backends call it.

    Args:
        angle_cos: The cosine of the angle between the way to the light
            and the light's axis. Clamped to minus one to one.
        flip_y: The texture's `flip_y`, so that `v` lands on its first
            row either way.

    Returns:
        The coordinate.
    """
    var clamped = min(max(angle_cos, Float32(-1)), Float32(1))
    return IesCoordinate(
        acos(clamped) * Float32(1.0 / pi), row_coordinate(0, flip_y)
    )


def ies_spot_light(
    color: Color,
    node: NodeId,
    ies_map: TextureId,
    intensity: Float32 = 1.0,
    distance: Float32 = NO_CUTOFF,
    angle: Angle = DEFAULT_SPOT_ANGLE,
    penumbra: Float32 = 0.0,
    decay: Float32 = PHYSICAL_DECAY,
    target: NodeId = NO_PARENT,
) raises -> Light:
    """Return a spot light whose beam is an IES profile, three.js's
    `IESSpotLight` with its `iesMap`.

    The numbers are `spot_light`'s, in its order. The angle still sets
    the shadow camera and the map's frame, as in three.js. The profile
    alone sets how bright the beam is off its axis.

    Args:
        color: Its color.
        node: The node whose world position the light shines from.
        ies_map: The profile, a texture from `loaders.ies.ies_texture`
            in the store, or `NO_TEXTURE` to keep the cone.
        intensity: How bright at one meter, multiplying the color.
        distance: Where the light stops. Zero for no cutoff.
        angle: Half the width of the cone.
        penumbra: How much of the cone is a soft rim.
        decay: The power of distance the light is divided by.
        target: The node the light points at, or `NO_PARENT` for the
            world origin.

    Returns:
        The light, a `SPOT` of shape `IES_SPOT`.

    Raises:
        Error: If `spot_light` refuses the numbers. See `Light.validate`.
    """
    var light = spot_light(
        color, node, intensity, distance, angle, penumbra, decay, target
    )
    light.spot_shape = IES_SPOT
    light.ies_map = ies_map
    light.validate()
    return light
