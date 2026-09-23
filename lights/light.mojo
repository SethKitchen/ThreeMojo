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
of one type; the other kinds carry zeros they never read.

**A hemisphere light is the fourth: a sky and a ground.** Outdoors, a
surface that faces up sees the sky and one that faces down sees the ground,
and they are not the same color. three.js's `HemisphereLight` is two colors
blended by how far a surface is turned toward the sky, a term that adds like
the ambient one and, like it, has no Lambert cutoff: a surface facing
straight down is lit by the ground, not by nothing. Its node says which way
the sky is, exactly as a directional light's node says which way the sun is.

**A spot light is the fifth: a bulb with a cone.** three.js's `SpotLight`
is a point light that shines only within `angle` of the way it points, with
a rim that is hard when `penumbra` is zero and softens toward the axis as it
grows. It points from its node toward its `target`, which is the world
origin unless another node is named -- and a directional light can name a
target the same way, three.js's `DirectionalLight.target`.

**A light probe is the seventh: the light around a point, as nine colors.**
three.js's `LightProbe` holds `SphericalHarmonics3`, the irradiance of an
environment reduced to bands zero to two. It adds like the ambient term,
but with a direction in it: a surface facing a bright sky catches more than
one facing the ground. It has no position and no node. Its `color` is not
read, as three.js does not read it; its `intensity` scales every
coefficient. `lights.light_probe.light_probe_from_cube` builds one from a
cube texture, three.js's `LightProbeGenerator.fromCubeTexture`.
"""

from core.layers import Layers
from core.object3d import NO_PARENT, NodeId
from lights.shadow import LightShadow
from math.spherical_harmonics3 import SphericalHarmonics3
from render.framebuffer import Color, FloatColor
from render.srgb import srgb_to_linear
from render.texture_store import NO_TEXTURE, TextureId
from std.math import cos, isfinite
from units.si import Angle, DEGREE, Length, METER, RADIAN


@fieldwise_init
struct LightKind(Equatable, ImplicitlyCopyable, Writable):
    """Which of the seven kinds of light this is, as a type rather than an
    int.

    See `core.object3d.NodeId` for why. The type stops a bare integer at
    compile time; it does not stop `LightKind(7)`, which `Lighting` refuses
    when the lights are resolved.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `AMBIENT`, `DIRECTIONAL`, `POINT`,
        `HEMISPHERE`, `SPOT`, `RECT_AREA` or `LIGHT_PROBE`."""
        return (
            self == AMBIENT
            or self == DIRECTIONAL
            or self == POINT
            or self == HEMISPHERE
            or self == SPOT
            or self == RECT_AREA
            or self == LIGHT_PROBE
        )


# Fills every surface equally, whichever way it faces. No direction, no node.
comptime AMBIENT = LightKind(0)
# Parallel rays from infinitely far away: the sun. Its direction comes from
# its node's world position, pointing from there towards its target, which
# is the world origin unless a node is named -- what three.js's default
# target gives.
comptime DIRECTIONAL = LightKind(1)
# Light spreading out from a point: a bulb. Its node's world position is where
# it is, and its light falls off with distance from there.
comptime POINT = LightKind(2)
# A sky color from one side and a ground color from the other, blended by
# how far a surface is turned toward the sky. Its node's world position,
# seen from the origin, is which way the sky is.
comptime HEMISPHERE = LightKind(3)
# A bulb that shines only within a cone: a point light with an angle, a
# penumbra and a target it points at.
comptime SPOT = LightKind(4)
# A rectangle that glows, `width` by `height` meters, shining along its
# node's -z: three.js's `RectAreaLight`. Only a `STANDARD` or `PHYSICAL`
# surface is lit by one, as only three.js's physical materials are, through
# linearly transformed cosines; see `lights.ltc`.
comptime RECT_AREA = LightKind(5)
# The light around a point, as nine spherical harmonic coefficients:
# three.js's `LightProbe`. It adds to every surface as the ambient term does,
# weighted by which way the surface faces. No node.
comptime LIGHT_PROBE = LightKind(6)
# three.js's default `width` and `height` for a rectangle of light.
comptime DEFAULT_RECT_SIZE = Length(10.0, METER)

# three.js's default `decay`: the inverse-square law, which is what light does
# in the real world.
comptime PHYSICAL_DECAY = Float32(2.0)
# three.js's default `distance`: no cutoff, the light reaches everything.
comptime NO_CUTOFF = Float32(0.0)
# three.js's default spot `angle`, a third of pi: sixty degrees from the axis
# to the rim.
comptime DEFAULT_SPOT_ANGLE = Angle(60.0, DEGREE)
# The widest cone three.js allows: a quarter turn from the axis, so the cone
# is at most a half space.
comptime WIDEST_SPOT_ANGLE = Angle(90.0, DEGREE)
# What the kinds that have no cone, no ground and no target carry there.
comptime _NO_ANGLE = Angle(0.0, RADIAN)
comptime _NO_LENGTH = Length(0.0, METER)
comptime _BLACK = Color(0, 0, 0)


@fieldwise_init
struct Light(ImplicitlyCopyable):
    """One light in a scene: a kind, a color, a strength, and maybe a node.

    A tagged struct rather than a trait with five implementations, for the
    reason `Material.side` is a small value type: there are five kinds, they
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
    # How fast a point or spot light's light falls off: it is divided by
    # distance to this power. Two is physically correct and the default; zero
    # means it does not fall off at all. Read only by those two kinds.
    var decay: Float32
    # Beyond this distance a point or spot light contributes nothing, and it
    # fades smoothly to nothing on the way there. Zero, the default, means no
    # cutoff. Read only by those two kinds.
    var distance: Float32
    # Which layers the light is on. A camera lights its meshes with only
    # the lights that share a layer with it, as three.js's `projectObject`
    # tests a light's own `layers` -- the light's, not its node's, so an
    # ambient light with no node has layers like any other. Layer zero
    # alone to begin with, so a scene that never mentions layers lights as
    # it did before.
    var layers: Layers
    # The color of the light from below, three.js's `groundColor`, scaled by
    # the same intensity as `color`, which is the sky. Read only by a
    # hemisphere light; black on every other kind.
    var ground: Color
    # Half the width of a spot light's cone, from its axis to its rim.
    # three.js's `angle`. An `Angle` rather than a number, so degrees and
    # radians cannot be confused. Read only by a spot light; zero elsewhere.
    var angle: Angle
    # How much of a spot light's cone is a soft rim: zero for a hard edge,
    # one for a fade all the way in from the rim to the axis. three.js's
    # `penumbra`. Read only by a spot light.
    var penumbra: Float32
    # Which node a directional or spot light shines toward, three.js's
    # `target`, or `NO_PARENT` for the world origin. Read only by those two.
    var target: NodeId
    # Whether this light draws a shadow map and the surfaces it lights
    # compare against it, three.js's `castShadow`, and how it draws it,
    # three.js's `shadow`. Off by default, as there. A directional, a
    # point or a spot light can cast; a point light draws six faces of a
    # cube. An ambient, hemisphere or rect area light cannot. See
    # `lights.shadow`.
    var cast_shadow: Bool
    var shadow: LightShadow
    # How wide and how tall a rectangle of light is, in meters, three.js's
    # `width` and `height`. Read only by a rect area light; zero elsewhere.
    var width: Length
    var height: Length
    # The picture a spot light projects, three.js's `SpotLight.map`: its
    # color multiplies the light's where a surface lands on it, seen
    # through the light's shadow camera. `NO_TEXTURE`, the default, for
    # none. Only a spot light can carry one. See `lights.shadow`.
    var map: TextureId
    # The light around a point, linear, three.js's `LightProbe.sh`. Read
    # only by a light probe, and scaled by `intensity` as three.js scales
    # it; darkness, every coefficient zero, on every other kind.
    var sh: SphericalHarmonics3

    def radiance(self) -> FloatColor:
        """Return the light this contributes, decoded and scaled.

        Linear, because it is about to be multiplied by a surface color and
        added to other lights, and neither is arithmetic you can do on bytes.
        Alpha is not light and is left at one.
        """
        return _radiance(self.color, self.intensity)

    def validate(self) raises:
        """Refuse numbers this light's kind cannot use.

        Every builder asks this of what it makes, and `Lighting` asks it
        again of every light in the scene, because the fields are open
        and a light in a persistent scene is there to be edited. Only
        the numbers the kind reads are checked: a point light's angle is
        a placeholder. The kind itself is not checked here; `Lighting`
        refuses one it cannot resolve.

        A spot light's cone must be wide enough to resolve. The fragment
        compares cosines, and the cosine of a half-angle below about
        fourteen thousandths of a degree rounds to exactly one in
        `Float32`, where a surface on the axis could not be told from
        one on the rim and came out dark on the axis of a valid light.
        Such an angle is refused rather than drawn wrong.

        Raises:
            Error: If the intensity is negative or not finite; a point or
                spot light's decay or distance is negative or not finite;
                a spot light's angle is not finite, not above zero, or
                past a quarter turn, its cosine rounds to one, or its
                penumbra is not finite or outside zero to one; a rect
                area light's width or height is not a positive finite
                length; the light casts a shadow and is not directional,
                point or spot; a light that is not a spot light names a
                map; the light casts or names a map and its `shadow` is
                refused by `LightShadow.validate`; such a point or spot
                light has a distance that does not lie beyond its shadow's
                near plane, where three.js puts the far plane; or a light
                probe's coefficients are not all finite.
        """
        if not isfinite(self.intensity) or self.intensity < 0:
            raise Error("A light's intensity must be finite and not negative")
        if self.kind == LIGHT_PROBE and not self.sh.is_finite():
            raise Error("A light probe's coefficients must be finite")
        if self.kind == RECT_AREA:
            var width = self.width.to(METER)
            var height = self.height.to(METER)
            if (
                not isfinite(width)
                or not isfinite(height)
                or width <= 0
                or height <= 0
            ):
                raise Error(
                    "A rect area light's width and height must be positive"
                    " lengths"
                )
        var mapped = self.map != NO_TEXTURE
        if mapped and self.kind != SPOT:
            raise Error("Only a spot light projects a map")
        if self.cast_shadow:
            if (
                self.kind != DIRECTIONAL
                and self.kind != POINT
                and self.kind != SPOT
            ):
                raise Error(
                    "Only a directional, a point or a spot light casts a"
                    " shadow: an ambient, hemisphere or rect area light has"
                    " no one place to draw from"
                )
        if self.cast_shadow or mapped:
            self.shadow.validate()
            if self.distance > 0 and self.distance <= self.shadow.near.to(
                METER
            ):
                raise Error(
                    "A light's distance must lie beyond its shadow's near"
                    " plane: it is where the shadow camera's far plane goes"
                )
        if self.kind == POINT or self.kind == SPOT:
            if not isfinite(self.decay) or self.decay < 0:
                raise Error("A light's decay must be finite and not negative")
            if not isfinite(self.distance) or self.distance < 0:
                raise Error(
                    "A light's distance must be finite and not negative"
                )
        if self.kind == SPOT:
            var half = self.angle.value
            if (
                not isfinite(half)
                or half <= 0
                or self.angle > WIDEST_SPOT_ANGLE
            ):
                raise Error(
                    "A spot light's angle must be above zero and at most a"
                    " quarter turn"
                )
            if cos(half) >= 1:
                raise Error(
                    "A spot light's angle is too narrow to resolve: its"
                    " cosine rounds to one"
                )
            if (
                not isfinite(self.penumbra)
                or self.penumbra < 0
                or self.penumbra > 1
            ):
                raise Error(
                    "A spot light's penumbra must be between zero and one"
                )

    def shadow_far(self) -> Length:
        """Return where this light's shadow camera puts its far plane:
        three.js's `light.distance || camera.far`, the light's distance
        when it has one and its shadow's far plane when not.

        Returns:
            The far plane.
        """
        if self.distance > 0:
            return Length(self.distance, METER)
        return self.shadow.far

    def ground_radiance(self) -> FloatColor:
        """Return the light a hemisphere light's ground contributes, decoded
        and scaled by the same intensity as its sky.

        Black for every other kind, which carries a black ground.
        """
        return _radiance(self.ground, self.intensity)


def _radiance(color: Color, intensity: Float32) -> FloatColor:
    """Return `color` decoded from sRGB and scaled by `intensity`."""
    return FloatColor(
        srgb_to_linear(Float32(color.r) / 255) * intensity,
        srgb_to_linear(Float32(color.g) / 255) * intensity,
        srgb_to_linear(Float32(color.b) / 255) * intensity,
        1.0,
    )


def _bare(
    kind: LightKind, color: Color, intensity: Float32, node: NodeId
) -> Light:
    """Return a light of `kind` with every kind-specific number at its zero,
    on layer zero alone, aimed at the origin."""
    return Light(
        kind,
        color,
        intensity,
        node,
        0.0,
        0.0,
        Layers(),
        _BLACK,
        _NO_ANGLE,
        0.0,
        NO_PARENT,
        False,
        LightShadow(),
        _NO_LENGTH,
        _NO_LENGTH,
        NO_TEXTURE,
        SphericalHarmonics3(),
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
            a light that removes light, or not finite.
    """
    var light = _bare(AMBIENT, color, intensity, NO_PARENT)
    light.validate()
    return light


def directional_light(
    color: Color,
    node: NodeId,
    intensity: Float32 = 1.0,
    target: NodeId = NO_PARENT,
) raises -> Light:
    """Return a light shining from a node's position towards its target.

    The node gives the direction and nothing else: a directional light is
    infinitely far away, so only which way it points matters, and moving it
    twice as far changes nothing. Naming a node rather than a bare vector is
    what lets the light be parented, and so carried by whatever it is
    attached to.

    Args:
        color: Its color.
        node: The node whose world position points away from the light.
        intensity: How bright, multiplying the color.
        target: The node the light shines toward, three.js's `target`, or
            `NO_PARENT` for the world origin, which is where three.js's
            default target sits.

    Returns:
        The light.

    Raises:
        Error: If the intensity is negative or not finite.
    """
    var light = _bare(DIRECTIONAL, color, intensity, node)
    light.target = target
    light.validate()
    return light


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
        Error: If the intensity, decay or distance is negative or not
            finite.
    """
    var light = _bare(POINT, color, intensity, node)
    light.decay = decay
    light.distance = distance
    light.validate()
    return light


def hemisphere_light(
    sky: Color, ground: Color, node: NodeId, intensity: Float32 = 1.0
) raises -> Light:
    """Return a light that is one color from the sky and another from the
    ground.

    three.js's `HemisphereLight`. A surface facing the sky gets the sky
    color, one facing the ground gets the ground color, and one edge-on gets
    half of each. Neither has a Lambert cutoff: it is the light of a whole
    hemisphere, not of one lamp, so it adds to every surface as the ambient
    term does. The node's world position, seen from the origin, is which way
    the sky is, as a directional light's node is which way the sun is; a
    node straight above the origin puts the sky up.

    Args:
        sky: The color from above.
        ground: The color from below.
        node: The node whose world position points at the sky.
        intensity: How bright, multiplying both colors.

    Returns:
        The light.

    Raises:
        Error: If the intensity is negative or not finite.
    """
    var light = _bare(HEMISPHERE, sky, intensity, node)
    light.ground = ground
    light.validate()
    return light


def spot_light(
    color: Color,
    node: NodeId,
    intensity: Float32 = 1.0,
    distance: Float32 = NO_CUTOFF,
    angle: Angle = DEFAULT_SPOT_ANGLE,
    penumbra: Float32 = 0.0,
    decay: Float32 = PHYSICAL_DECAY,
    target: NodeId = NO_PARENT,
) raises -> Light:
    """Return a bulb that shines only within a cone.

    three.js's `SpotLight`, with its numbers in its constructor's order and
    at its defaults. The node is where the bulb is, and the light points
    from there toward `target`. A surface is lit as a point light lights it,
    scaled by how far inside the cone it lies: fully within `angle * (1 -
    penumbra)` of the axis, not at all beyond `angle`, and smoothly between.

    Args:
        color: Its color.
        node: The node whose world position the light shines from.
        intensity: How bright at one meter, multiplying the color.
        distance: Where the light stops, fading smoothly to nothing as it
            gets there. Zero for no cutoff.
        angle: Half the width of the cone, from its axis to its rim. At most
            a quarter turn.
        penumbra: How much of the cone is a soft rim, from zero for a hard
            edge to one for a fade all the way in to the axis.
        decay: The power of distance the light is divided by. Two is the
            inverse-square law of a real bulb.
        target: The node the light points at, or `NO_PARENT` for the world
            origin.

    Returns:
        The light.

    Raises:
        Error: If the intensity, distance or decay is negative or not
            finite; the angle is not above zero and at most a quarter
            turn -- a cone of nothing lights nothing, and one past a half
            space is no longer a cone -- or so narrow that its cosine
            rounds to one; or the penumbra is outside zero to one. See
            `Light.validate`.
    """
    var light = _bare(SPOT, color, intensity, node)
    light.distance = distance
    light.angle = angle
    light.penumbra = penumbra
    light.decay = decay
    light.target = target
    light.validate()
    return light


def rect_area_light(
    color: Color,
    node: NodeId,
    intensity: Float32 = 1.0,
    width: Length = DEFAULT_RECT_SIZE,
    height: Length = DEFAULT_RECT_SIZE,
) raises -> Light:
    """Return a rectangle that glows, three.js's `RectAreaLight`.

    The node is where the rectangle's center is and which way it faces:
    it shines along the node's -z, its width along the node's x and its
    height along its y, turned and scaled by the node's world matrix as
    three.js turns `halfWidth` and `halfHeight`. Aim it as a camera is
    aimed, by turning its node. It has no target, no falloff of its own
    beyond the geometry of a rectangle seen from further away, and no
    shadow, as three.js's has none.

    Only a `STANDARD` or `PHYSICAL` surface is lit by one, as only
    three.js's physical materials are; every other kind leaves it out.
    The scene's renderer must hold the LTC tables, `lights.ltc`, or the
    lighting refuses to resolve it.

    Args:
        color: Its color.
        node: The node at its center, facing the way it shines.
        intensity: How bright, multiplying the color.
        width: How wide, three.js's `width`. Ten meters by default.
        height: How tall, three.js's `height`. Ten meters by default.

    Returns:
        The light.

    Raises:
        Error: If the intensity is negative or not finite, or the width or
            height is not a positive finite length.
    """
    var light = _bare(RECT_AREA, color, intensity, node)
    light.width = width
    light.height = height
    light.validate()
    return light


def light_probe(
    sh: SphericalHarmonics3, intensity: Float32 = 1.0
) raises -> Light:
    """Return the light around a point as nine colors, three.js's
    `LightProbe`.

    Every surface catches `sh.get_irradiance_at` of its normal, times the
    intensity, added to the ambient term and scattered the same way: by
    `BRDF_Lambert` into a matte surface's diffuse color, and by a physical
    surface's diffuse term. It has no node, as an ambient light has none:
    three.js reads no position from a probe. Its color is white and is
    not read.

    Args:
        sh: The coefficients, linear. `light_probe_from_cube` in
            `lights.light_probe` works them out from a cube texture.
        intensity: What every coefficient is multiplied by.

    Returns:
        The light.

    Raises:
        Error: If the intensity is negative or not finite, or a
            coefficient is not finite.
    """
    var light = _bare(LIGHT_PROBE, Color(255, 255, 255), intensity, NO_PARENT)
    light.sh = sh
    light.validate()
    return light
