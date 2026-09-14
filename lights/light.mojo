# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What lights a scene, from three.js `src/lights/`.

This is the third thing to be taken off `Renderer`, and it comes off for the
reason the first two did. A colour lived on `Mesh`, which is otherwise pure
identity; a texture lived on `Renderer`, so a scene could have exactly one
image. A light lived on `Renderer` too — one direction and one ambient
fraction — so a scene could have exactly one light, and the first thing anyone
would try is two.

Being on the renderer had a second cost that is easy to miss. A light that is
not in the scene cannot be *moved* by the scene: it has no parent, no
transform, and no way to be carried along by the object it belongs to. A lamp
fixed to a turning cube is an ordinary thing to want and was not expressible.
A `DirectionalLight` here names a node, exactly as a `Mesh` does, and its
direction is read from that node's world matrix — so it inherits every
transform above it.

**Ambient is now a light rather than a fudge.** It used to be a fraction the
unlit side kept, mixed as `ambient + (1 - ambient) * lambert`. That is a lerp
towards the surface's own colour, which is not what ambient light is and
cannot have a colour of its own. Here it is what three.js has: a constant term
*added* to every surface regardless of which way it faces. Two consequences,
both wanted — a scene with no lights renders black rather than half-lit, and a
blue ambient tints the shadows blue.

**Lights add, and they add in linear light.** Two lights at half strength make
one at full strength, which is only true of the numbers this renderer keeps.
Summing sRGB bytes would repeat the mistake `render.srgb` exists to prevent:
half plus half would come to 128 rather than to the full 255. Nothing here
touches a byte until `RenderTarget.resolve`.

**A light has a colour.** The old one had only a direction, so lighting was
scalar dimming and a red lamp was impossible. A light's colour multiplies the
surface's, per channel, which is what makes coloured lighting work at all.
"""

from core.object3d import NO_PARENT, NodeId
from render.framebuffer import Color, FloatColor
from render.srgb import srgb_to_linear

# Fills every surface equally, whichever way it faces. No direction, no node.
comptime AMBIENT = 0
# Parallel rays from infinitely far away: the sun. Its direction comes from
# its node's world position, pointing from there towards the world origin,
# which is what three.js's default target gives.
comptime DIRECTIONAL = 1


@fieldwise_init
struct Light(ImplicitlyCopyable):
    """One light in a scene: a kind, a colour, a strength, and maybe a node.

    A tagged struct rather than a trait with two implementations, for the
    reason `Material.side` is an integer: there are two kinds, they differ by
    one field's meaning, and a list of them has to be a list of one type.
    """

    var kind: Int
    var color: Color
    # How bright, multiplying the colour. Above one is allowed: two lamps can
    # overexpose a white surface, and clamping here would hide that rather
    # than let `resolve` do it once at the end.
    var intensity: Float32
    # Which node gives this light its direction. `NO_PARENT` for an ambient
    # light, which has none.
    var node: NodeId

    def radiance(self) -> FloatColor:
        """Return the light this contributes, decoded and scaled.

        Linear, because it is about to be multiplied by a surface colour and
        added to other lights, and neither is arithmetic you can do on bytes.
        Alpha is not light and is left at one.
        """
        return FloatColor(
            srgb_to_linear(Float32(self.color.r) / 255) * self.intensity,
            srgb_to_linear(Float32(self.color.g) / 255) * self.intensity,
            srgb_to_linear(Float32(self.color.b) / 255) * self.intensity,
            1.0,
        )


def ambient_light(color: Color, intensity: Float32 = 1.0) raises -> Light:
    """Return a light that fills every surface equally.

    Args:
        color: Its colour.
        intensity: How bright, multiplying the colour.

    Returns:
        The light.

    Raises:
        Error: If the intensity is negative, which is not a dimmer light but
            a light that removes light.
    """
    if intensity < 0:
        raise Error("A light's intensity cannot be negative")
    return Light(AMBIENT, color, intensity, NO_PARENT)


def directional_light(
    color: Color, node: NodeId, intensity: Float32 = 1.0
) raises -> Light:
    """Return a light shining from a node's position towards the origin.

    The node gives the direction and nothing else: a directional light is
    infinitely far away, so only which way it points matters, and moving it
    twice as far changes nothing. Naming a node rather than a bare vector is
    what lets the light be parented, and so carried by whatever it is
    attached to.

    Args:
        color: Its colour.
        node: The node whose world position points away from the light.
        intensity: How bright, multiplying the colour.

    Returns:
        The light.

    Raises:
        Error: If the intensity is negative.
    """
    if intensity < 0:
        raise Error("A light's intensity cannot be negative")
    return Light(DIRECTIONAL, color, intensity, node)
