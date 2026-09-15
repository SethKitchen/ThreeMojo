# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene's lights resolved to world space, ready to evaluate per fragment.

Separate from `lights.light` so the import graph stays acyclic: `core.scene`
holds `Light` values, and this holds a `Scene`. Putting both in one module
would make the two import each other.

`falloff` lives here rather than beside either rasterizer because both call
it -- one on the host, one inside the kernel -- and the parity tests hold the
two to the same numbers. It is the one piece of shading arithmetic a point
light adds.
"""

from core.scene import Scene
from lights.light import AMBIENT, DIRECTIONAL, POINT, Light
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import exp2, log2, max, min

# Distance to the power of decay is never taken below this, so a surface
# touching the bulb is very bright rather than infinitely so. three.js's
# number.
comptime FALLOFF_FLOOR = Float32(0.01)


def falloff(distance: Float32, decay: Float32, cutoff: Float32) -> Float32:
    """Return how much of a point light's light survives `distance`.

    three.js's `getDistanceAttenuation`: one over distance to the power of
    `decay`, floored so a surface on top of the bulb is bright rather than
    infinite, and if there is a cutoff, multiplied by a smooth step that
    reaches zero exactly at it.

    Written as `exp2(decay * log2(distance))` rather than a power function so
    the kernel and the host compute it the same way from two intrinsics both
    already have.

    Args:
        distance: How far the surface is from the light; must be positive.
        decay: The power of distance to divide by.
        cutoff: Where the light stops, or zero for never.

    Returns:
        The factor to multiply the light's radiance by.
    """
    var attenuation = Float32(1) / max(
        exp2(decay * log2(distance)), FALLOFF_FLOOR
    )
    if cutoff > 0:
        var ratio = distance / cutoff
        var quartic = ratio * ratio * ratio * ratio
        var edge = max(Float32(0), min(Float32(1), 1 - quartic))
        attenuation *= edge * edge
    return attenuation


struct Lighting(Movable):
    """Every light in a scene, resolved to world space and ready to evaluate.

    Built once per frame rather than once per fragment: a light's direction
    or position needs its node's world matrix, and reading one per fragment
    would be the same work thousands of times over for an answer that cannot
    change within a frame.
    """

    # The sum of every ambient light, already decoded and scaled.
    var ambient: FloatColor
    # One entry per directional light, parallel lists.
    var directions: List[Vector3]
    var radiances: List[FloatColor]
    # One entry per point light, parallel lists: where it is, what it
    # carries, and how it falls off.
    var positions: List[Vector3]
    var point_radiances: List[FloatColor]
    var decays: List[Float32]
    var cutoffs: List[Float32]

    def __init__(out self, scene: Scene) raises:
        """Resolve a scene's lights against the world transforms it holds.

        Args:
            scene: The transform hierarchy, already updated, and the lights
                added to it.

        Raises:
            Error: If a directional or point light names a node the scene
                does not have, a directional light's node sits exactly at
                the origin — which gives no direction to shine from, and is a
                mistake rather than a dark light — or a light's kind is none
                of the three.
        """
        self.ambient = FloatColor(0.0, 0.0, 0.0, 1.0)
        self.directions = List[Vector3]()
        self.radiances = List[FloatColor]()
        self.positions = List[Vector3]()
        self.point_radiances = List[FloatColor]()
        self.decays = List[Float32]()
        self.cutoffs = List[Float32]()
        for light in scene.lights:
            if light.kind == AMBIENT:
                var fill = light.radiance()
                self.ambient = FloatColor(
                    self.ambient.r + fill.r,
                    self.ambient.g + fill.g,
                    self.ambient.b + fill.b,
                    1.0,
                )
            elif light.kind == DIRECTIONAL:
                # Where the node ended up after every transform above it.
                var pointing = scene.world_position(light.node)
                if pointing.length() == 0:
                    raise Error("A directional light needs a direction")
                pointing.normalize()
                self.directions.append(pointing)
                self.radiances.append(light.radiance())
            elif light.kind == POINT:
                # Its node's position is the answer itself, and the origin
                # is as good a place for a bulb as any.
                self.positions.append(scene.world_position(light.node))
                self.point_radiances.append(light.radiance())
                self.decays.append(light.decay)
                self.cutoffs.append(light.distance)
            else:
                # The type stops a bare integer; it does not stop
                # `LightKind(7)`, and a light that is none of the three has
                # nothing here that knows how to evaluate it.
                raise Error("A light of an unknown kind cannot be resolved")

    def __init__(out self, *, ambient: FloatColor):
        """Create lighting with a fill term and no other lights.

        Args:
            ambient: The light arriving everywhere, already linear.
        """
        self.ambient = ambient
        self.directions = List[Vector3]()
        self.radiances = List[FloatColor]()
        self.positions = List[Vector3]()
        self.point_radiances = List[FloatColor]()
        self.decays = List[Float32]()
        self.cutoffs = List[Float32]()

    @staticmethod
    def uniform() -> Lighting:
        """Return lighting that leaves a surface's own colour alone.

        Light of one in every channel, from nowhere in particular: the
        identity for the multiply a fragment does, so a caller with no lights
        in hand gets the colours it passed in rather than black.

        The same idea as the blank texture sampling opaque white. It makes
        "no lighting" a value rather than a branch, which is what lets
        `rasterize_shaded` be called with hand-built triangles -- as the
        rasterizer's own tests do, where the question is coverage or depth and
        lights would only be noise.

        A *scene* with no lights is a different thing and really does render
        black: that is `Lighting(scene)` finding nothing, and is what no
        lights means.
        """
        return Lighting(ambient=FloatColor(1.0, 1.0, 1.0, 1.0))

    def count(self) -> Int:
        """Return how many directional lights there are."""
        return len(self.directions)

    def point_count(self) -> Int:
        """Return how many point lights there are."""
        return len(self.positions)

    def intensity_at(self, normal: Vector3, position: Vector3) -> FloatColor:
        """Return how much light of each colour reaches a surface here.

        The surface's own colour is not in it: this is the light arriving,
        and multiplying by what the surface reflects is the caller's step.
        Split out because a fragment already holds its colour in linear form
        and has no byte to decode, and because the GPU kernel computes exactly
        this and must compute it the same way.

        Lambert per light -- how much a surface catches falls off with the
        cosine of the angle it is turned through -- summed, plus the ambient
        term. A point light's Lambert term is taken against the direction
        from *this* surface to the bulb, and scaled by `falloff`.

        Args:
            normal: The surface's unit normal, in world space.
            position: Where the surface is, in world space. Only a point
                light reads it: how far away the bulb is, and in which
                direction, depends on where you stand, which is the one thing
                a directional light does not have.

        Returns:
            The arriving light, linear. Alpha is not light and stays at one.
        """
        var total = self.ambient
        for index in range(len(self.directions)):
            var lambert = max(Float32(0), normal.dot(self.directions[index]))
            if lambert == 0:
                continue
            ref light = self.radiances[index]
            total = FloatColor(
                total.r + light.r * lambert,
                total.g + light.g * lambert,
                total.b + light.b * lambert,
                1.0,
            )
        for index in range(len(self.positions)):
            # From the surface to the bulb: how far, and which way.
            var toward = self.positions[index] - position
            var distance = toward.length()
            # A surface exactly on the bulb has no direction to be lit from.
            if distance == 0:
                continue
            # The dot and then the divide, in that order, because it is the
            # order the kernel uses and the two must round alike.
            var lambert = normal.dot(toward) / distance
            if lambert <= 0:
                continue
            var reach = lambert * falloff(
                distance, self.decays[index], self.cutoffs[index]
            )
            ref bulb = self.point_radiances[index]
            total = FloatColor(
                total.r + bulb.r * reach,
                total.g + bulb.g * reach,
                total.b + bulb.b * reach,
                1.0,
            )
        return total

    def shade(
        self, base: Color, normal: Vector3, position: Vector3
    ) -> FloatColor:
        """Return `base` lit by every light, in linear light.

        The base colour is decoded from sRGB first: an authored byte is not
        proportional to light, and multiplying it by a Lambert term would be
        arithmetic on the wrong numbers. See `render.srgb`.

        Nothing is clamped. A surface under two bright lamps really is over
        one, and `RenderTarget.resolve` is the single place that decides what
        a display can show. Clamping here would do it twice and lose the
        headroom in between.

        Args:
            base: The surface's own colour, as authored.
            normal: Its unit normal, in world space.
            position: Where it is, in world space, for the point lights.

        Returns:
            The lit colour, linear, with the base colour's alpha.
        """
        var total = self.intensity_at(normal, position)
        var surface = FloatColor(srgb=base)
        return FloatColor(
            surface.r * total.r,
            surface.g * total.g,
            surface.b * total.b,
            surface.a,
        )
