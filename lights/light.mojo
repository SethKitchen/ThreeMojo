# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What lights a scene, from three.js `src/lights/`.

This is the third thing to be taken off `Renderer`, and it comes off for the
reason the first two did. A color lived on `Mesh`, which is otherwise pure
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
towards the surface's own color, which is not what ambient light is and
cannot have a color of its own. Here it is what three.js has: a constant term
*added* to every surface regardless of which way it faces. Two consequences,
both wanted — a scene with no lights renders black rather than half-lit, and a
blue ambient tints the shadows blue.

**Lights add, and they add in linear light.** Two lights at half strength make
one at full strength, which is only true of the numbers this renderer keeps.
Summing sRGB bytes would repeat the mistake `render.srgb` exists to prevent:
half plus half would come to 128 rather than to the full 255. Nothing here
touches a byte until `RenderTarget.resolve`.

**A light has a color.** The old one had only a direction, so lighting was
scalar dimming and a red lamp was impossible. A light's color multiplies the
surface's, per channel, which is what makes colored lighting work at all.

**A point light is the third kind.** A directional light is the sun: parallel
rays, one direction, the same everywhere. A point light is a bulb: it sits
somewhere, its light spreads out from there, and a surface gets less of it the
further away it is and none of it if it faces away. Its node gives it a
*position* rather than a direction, which is the whole difference on the scene
side. On the shading side it is the reason every fragment now knows where it
is in the world -- see `render.rasterizer.RasterVertex.world`.

Its falloff is three.js's: the light divided by distance raised to `decay`,
with the physically correct default of two, and optionally faded to nothing
at `distance`. Both numbers live on `Light` so a list of lights stays a list
of one type; the other two kinds carry zeros they never read.
"""

from core.object3d import NO_PARENT, NodeId
from render.framebuffer import Color, FloatColor
from render.srgb import srgb_to_linear


@fieldwise_init
struct LightKind(Equatable, ImplicitlyCopyable, Writable):
    """Which of the three kinds of light this is, as a type rather than an
    int.

    See `core.object3d.NodeId` for why. The type stops a bare integer at
    compile time; it does not stop `LightKind(7)`, which `Lighting` refuses
    when the lights are resolved.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `AMBIENT`, `DIRECTIONAL` or `POINT`."""
        return self == AMBIENT or self == DIRECTIONAL or self == POINT


# Fills every surface equally, whichever way it faces. No direction, no node.
comptime AMBIENT = LightKind(0)
# Parallel rays from infinitely far away: the sun. Its direction comes from
# its node's world position, pointing from there towards the world origin,
# which is what three.js's default target gives.
comptime DIRECTIONAL = LightKind(1)
# Light spreading out from a point: a bulb. Its node's world position is where
# it is, and its light falls off with distance from there.
comptime POINT = LightKind(2)

# three.js's default `decay`: the inverse-square law, which is what light does
# in the real world.
comptime PHYSICAL_DECAY = Float32(2.0)
# three.js's default `distance`: no cutoff, the light reaches everything.
comptime NO_CUTOFF = Float32(0.0)


@fieldwise_init
struct Light(ImplicitlyCopyable):
    """One light in a scene: a kind, a color, a strength, and maybe a node.

    A tagged struct rather than a trait with three implementations, for the
    reason `Material.side` is a small value type: there are three kinds, they
    differ by what they read from their node, and a list of them has to be a
    list of one type.
    """

    var kind: LightKind
    var color: Color
    # How bright, multiplying the color. Above one is allowed: two lamps can
    # overexpose a white surface, and clamping here would hide that rather
    # than let `resolve` do it once at the end.
    var intensity: Float32
    # Which node gives this light its direction, or its position. `NO_PARENT`
    # for an ambient light, which has neither.
    var node: NodeId
    # How fast a point light's light falls off: it is divided by distance to
    # this power. Two is physically correct and the default; zero means it
    # does not fall off at all. Read only by a point light.
    var decay: Float32
    # Beyond this distance a point light contributes nothing, and it fades
    # smoothly to nothing on the way there. Zero, the default, means no
    # cutoff. Read only by a point light.
    var distance: Float32

    def radiance(self) -> FloatColor:
        """Return the light this contributes, decoded and scaled.

        Linear, because it is about to be multiplied by a surface color and
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
        color: Its color.
        intensity: How bright, multiplying the color.

    Returns:
        The light.

    Raises:
        Error: If the intensity is negative, which is not a dimmer light but
            a light that removes light.
    """
    if intensity < 0:
        raise Error("A light's intensity cannot be negative")
    return Light(AMBIENT, color, intensity, NO_PARENT, 0.0, 0.0)


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
        color: Its color.
        node: The node whose world position points away from the light.
        intensity: How bright, multiplying the color.

    Returns:
        The light.

    Raises:
        Error: If the intensity is negative.
    """
    if intensity < 0:
        raise Error("A light's intensity cannot be negative")
    return Light(DIRECTIONAL, color, intensity, node, 0.0, 0.0)


def point_light(
    color: Color,
    node: NodeId,
    intensity: Float32 = 1.0,
    decay: Float32 = PHYSICAL_DECAY,
    distance: Float32 = NO_CUTOFF,
) raises -> Light:
    """Return a light shining out from a node's position in every direction.

    three.js's `PointLight`, with the same three numbers and the same
    defaults. The node is where the bulb is, and this time its position is
    what matters and not merely its direction: a surface twice as far away
    gets a quarter of the light, and a surface behind the bulb gets none.

    Args:
        color: Its color.
        node: The node whose world position the light shines from.
        intensity: How bright at one meter, multiplying the color.
        decay: The power of distance the light is divided by. Two is the
            inverse-square law of a real bulb; one falls off gently; zero not
            at all.
        distance: Where the light stops, fading smoothly to nothing as it
            gets there. Zero for no cutoff, which is the physical answer and
            the default.

    Returns:
        The light.

    Raises:
        Error: If the intensity, decay or distance is negative.
    """
    if intensity < 0:
        raise Error("A light's intensity cannot be negative")
    if decay < 0:
        raise Error("A point light's decay cannot be negative")
    if distance < 0:
        raise Error("A point light's distance cannot be negative")
    return Light(POINT, color, intensity, node, decay, distance)
