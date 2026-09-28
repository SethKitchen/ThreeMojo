# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What shapes the beam of an IES spot light or a projector, resolved for
one frame.

A plain spot light's beam is two cosines, which `Lighting` works out
from the light alone. An IES spot light's beam is a texture, and a
projector's is its shadow camera, whose aspect can come from its map's
size. Both need the textures, which `Lighting` does not hold. So
`Renderer.spot_profiles` builds one `SpotProfile` for each such light,
as `Renderer.spot_light_maps` builds the maps, and `Lighting` takes them
in its `profiles` argument.

`SpotProfile.attenuation` is the host's half. The kernel reads the same
numbers from the light buffer and calls the same functions:
`lights.ies_spot_light.ies_coordinate` and
`lights.projector_light.projector_attenuation`. See
[GPU backend](GPU-backend).
"""

from lights.ies_spot_light import ies_coordinate
from lights.light import IES_SPOT, Light, PROJECTOR_SPOT, SPOT, SpotShape
from lights.projector_light import projector_attenuation
from math.vector3 import Vector3
from render.texture import Texture
from render.texture_store import NO_TEXTURE, TextureId


struct SpotProfile(Copyable, Movable):
    """The beam of one IES spot light or projector for one frame."""

    # Which of the scene's lights it shapes: its index in `scene.lights`.
    var light: Int
    # `IES_SPOT` or `PROJECTOR_SPOT`.
    var shape: SpotShape
    # The IES profile's slot in the store, for the kernel, or
    # `NO_TEXTURE` for a projector.
    var texture: TextureId
    # The profile itself, for the host. Blank for a projector.
    var image: Texture
    # World space to the light's clip space, column major: the shadow
    # camera, with its aspect. Read only by a projector.
    var frame: SIMD[DType.float32, 16]

    def __init__(
        out self,
        light: Int,
        shape: SpotShape,
        texture: TextureId,
        var image: Texture,
        frame: SIMD[DType.float32, 16],
    ) raises:
        """Adopt a light's beam.

        Args:
            light: Which of the scene's lights it shapes.
            shape: `IES_SPOT` or `PROJECTOR_SPOT`.
            texture: The IES profile's slot in the store, or `NO_TEXTURE`
                for a projector.
            image: The profile, or a blank texture for a projector.
            frame: World space to the light's clip space, column major.

        Raises:
            Error: If the shape is neither `IES_SPOT` nor
                `PROJECTOR_SPOT`, or an IES profile names no texture or
                a blank one.
        """
        if shape != IES_SPOT and shape != PROJECTOR_SPOT:
            raise Error("A spot profile is an IES profile or a projector")
        if shape == IES_SPOT and (texture == NO_TEXTURE or image.is_blank()):
            raise Error("An IES profile must hold a texture")
        self.light = light
        self.shape = shape
        self.texture = texture
        self.image = image^
        self.frame = frame

    def __init__(out self, *, copy: Self):
        """Copy another profile, its texture included.

        Args:
            copy: The profile to copy.
        """
        self.light = copy.light
        self.shape = copy.shape
        self.texture = copy.texture
        self.image = Texture(copy=copy.image)
        self.frame = copy.frame

    def attenuation(
        self, angle_cos: Float32, position: Vector3, penumbra_cos: Float32
    ) -> Float32:
        """Return how much of the light's beam reaches a surface, where a
        cone spot light takes `smoothstep` of its two cosines.

        Args:
            angle_cos: The cosine of the angle between the way to the
                light and its axis. Read by an IES profile.
            position: Where the surface is, in world space. Read by a
                projector.
            penumbra_cos: `cos( angle * ( 1 - penumbra ) )`. Read by a
                projector.

        Returns:
            The IES profile's red at the angle, or the projector's fade.
        """
        if self.shape == IES_SPOT:
            var place = ies_coordinate(angle_cos, self.image.flip_y)
            return self.image.sample_level(place.u, place.v, 0).r
        return projector_attenuation(self.frame, position, penumbra_cos)


def needs_profile(light: Light) -> Bool:
    """Return True if a light's beam needs a `SpotProfile`: an IES spot
    light that names a profile, or a projector.

    An IES spot light with no profile keeps its cone, as three.js's does
    when `iesMap` is null.

    Args:
        light: The light.

    Returns:
        Whether `Renderer.spot_profiles` builds one for it.
    """
    if light.kind != SPOT:
        return False
    if light.spot_shape == PROJECTOR_SPOT:
        return True
    return light.spot_shape == IES_SPOT and light.ies_map != NO_TEXTURE
