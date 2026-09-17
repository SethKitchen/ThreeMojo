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
light adds. A spot light adds one more, the rim of its cone, and that is
`math.smoothstep`, shared the same way. `blinn_phong` is the third, and
belongs to a `PHONG` material rather than to a light.

**On three.js's reciprocal pi.** three.js divides its diffuse term by pi,
`BRDF_Lambert`, and its specular lobe too, `D_BlinnPhong`. The diffuse term
here does not: `intensity_at` returns what a surface facing a white light of
one reflects, which is its own color rather than that over pi. So
`blinn_phong` drops the same factor, which keeps the *ratio* of highlight to
diffuse exactly three.js's -- the number that decides how a surface looks.
Both conventions are consistent on their own; mixing them is what would not
be.
"""

from core.layers import Layers
from core.object3d import NO_PARENT
from core.scene import Scene
from lights.light import (
    AMBIENT,
    DIRECTIONAL,
    HEMISPHERE,
    POINT,
    SPOT,
    Light,
)
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import cos, exp2, log2, max, min

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


# What `Lighting.toward_eye` holds when a camera's rays converge on a
# point, which is a perspective camera: there is no single direction toward
# it, so each fragment works its own out from `Lighting.eye`. A zero vector,
# the same idiom as `NO_PARENT` and `NO_TEXTURE`.
comptime PERSPECTIVE_VIEW = Vector3(0, 0, 0)


def toward_eye_at(
    eye: Vector3, parallel: Vector3, position: Vector3
) -> Vector3:
    """Return the unit direction from a surface toward the camera:
    three.js's `geometryViewDir`.

    **The two projections answer differently, and that is the point.** A
    perspective camera's rays converge on `eye`, so the direction depends on
    where the surface stands. An orthographic camera's rays run parallel, so
    one direction serves every fragment and `eye` says nothing about it --
    moving such a camera along its own axis changes no highlight at all.
    three.js draws the same distinction in `lights_fragment_begin`, where
    `geometryViewDir` is `vec3(0, 0, 1)` under an orthographic projection
    and the normalized view position otherwise.

    Shared by both rasterizers, as `falloff` is, so that neither can see a
    surface from somewhere the other does not.

    Args:
        eye: Where the camera is, in world space. Read only when the rays
            converge.
        parallel: The one direction toward the camera, already a unit
            vector, or `PERSPECTIVE_VIEW` when the rays converge.
        position: Where the surface is, in world space.

    Returns:
        The unit direction toward the camera, or a zero vector when the
        surface sits exactly at a converging camera and there is none.
    """
    if parallel.length() != 0:
        return parallel
    var toward = eye - position
    if toward.length() == 0:
        return Vector3(0, 0, 0)
    toward.normalize()
    return toward^


# three.js's `G_BlinnPhong_Implicit`: the geometric term of the Blinn-Phong
# BRDF, a constant there and here.
comptime BLINN_PHONG_G = Float32(0.25)
# The two numbers in three.js's `F_Schlick`, which approximates how much
# more a surface reflects at a grazing angle.
comptime _FRESNEL_SLOPE = Float32(-5.55473)
comptime _FRESNEL_OFFSET = Float32(-6.98316)


def blinn_phong(
    toward_light: Vector3,
    toward_eye: Vector3,
    normal: Vector3,
    specular: Vector3,
    shininess: Float32,
) -> Vector3:
    """Return the fraction of light arriving from one direction that a
    surface sends toward another: three.js's `BRDF_BlinnPhong`.

    Blinn's half vector rather than Phong's reflection, as three.js uses:
    the highlight is brightest where the normal points half way between the
    light and the eye. Three factors multiply, each three.js's own --
    `F_Schlick` for the Fresnel rise at a grazing angle, the constant
    `G_BlinnPhong_Implicit`, and `D_BlinnPhong` for the lobe -- with one
    factor of pi dropped from the last, for the reason the module docstring
    gives.

    The power is spelled as `exp2` of `log2` rather than a power function,
    so the kernel and the host compute it from two intrinsics both already
    have, as `falloff` is. A surface turned away from the half vector
    reflects nothing and returns early, which also keeps `log2` off zero.

    Args:
        toward_light: Unit vector from the surface toward the light.
        toward_eye: Unit vector from the surface toward the camera.
        normal: The surface's unit normal.
        specular: How much the surface reflects in each channel, linear.
        shininess: How tight the highlight is; must not be negative. Zero
            spreads it over the whole lit side, as three.js allows.

    Returns:
        The reflected fraction per channel. Above one at the center of a
        tight highlight, which is what a highlight is; `RenderTarget.resolve`
        decides what a display can show.
    """
    var half = toward_light + toward_eye
    # Light and eye exactly opposite leave no half direction, and nothing is
    # reflected toward the camera from there.
    if half.length() == 0:
        return Vector3(0, 0, 0)
    half.normalize()
    var facing = normal.dot(half)
    # three.js saturates both dots. Below zero the lobe is zero anyway, and
    # returning here keeps the logarithm off it.
    if facing <= 0:
        return Vector3(0, 0, 0)
    if facing > 1:
        facing = 1
    var grazing = max(Float32(0), min(Float32(1), toward_eye.dot(half)))
    # three.js's F_Schlick with an f90 of one: the surface reflects its own
    # color head on and white at a grazing angle.
    var fresnel = exp2((_FRESNEL_SLOPE * grazing + _FRESNEL_OFFSET) * grazing)
    var keep = 1 - fresnel
    # three.js's D_BlinnPhong, without its reciprocal pi.
    var lobe = (shininess * 0.5 + 1) * exp2(shininess * log2(facing))
    var scale = BLINN_PHONG_G * lobe
    return Vector3(
        (specular.x * keep + fresnel) * scale,
        (specular.y * keep + fresnel) * scale,
        (specular.z * keep + fresnel) * scale,
    )


def _aimed_at(scene: Scene, light: Light) raises -> Vector3:
    """Return where `light` points, in world space: its target node's
    position, or the origin when it names none.

    Raises:
        Error: If the target is a node the scene does not have.
    """
    if light.target == NO_PARENT:
        return Vector3(0, 0, 0)
    return scene.world_position(light.target)


struct Lighting(Movable):
    """Every light in a scene, resolved to world space and ready to evaluate.

    Built once per frame rather than once per fragment: a light's direction
    or position needs its node's world matrix, and reading one per fragment
    would be the same work thousands of times over for an answer that cannot
    change within a frame.
    """

    # Where the camera is, in world space: what a `PHONG` material measures
    # its highlight against, three.js's `cameraPosition`. Camera-dependent
    # like `visible` is, and set by `Renderer.render` from the camera it
    # draws through. The origin by default, which only a highlight notices.
    var eye: Vector3
    # The one direction toward that camera when its rays run parallel, or
    # `PERSPECTIVE_VIEW` when they converge on `eye` instead. Normalized on
    # the way in, so a fragment never has to. See `toward_eye_at`.
    var toward_eye: Vector3
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
    # One entry per hemisphere light, parallel lists: which way the sky is,
    # as a unit vector, and what the sky and the ground each carry.
    var sky_directions: List[Vector3]
    var skies: List[FloatColor]
    var grounds: List[FloatColor]
    # One entry per spot light, parallel lists: where it is; which way it
    # points, as a unit vector from its target toward it, the way three.js
    # holds it, so that the dot with the direction to the bulb is the cosine
    # of the angle off the axis; what it carries; how it falls off; and its
    # cone as the cosines of its rim and of where the rim starts to soften.
    var spot_positions: List[Vector3]
    var spot_directions: List[Vector3]
    var spot_radiances: List[FloatColor]
    var spot_decays: List[Float32]
    var spot_cutoffs: List[Float32]
    var cone_cosines: List[Float32]
    var penumbra_cosines: List[Float32]

    def __init__(
        out self,
        scene: Scene,
        visible: Layers = Layers.all(),
        eye: Vector3 = Vector3(0, 0, 0),
        toward_eye: Vector3 = PERSPECTIVE_VIEW,
    ) raises:
        """Resolve a scene's lights against the world transforms it holds.

        Resolved once per frame for one camera: a light on a layer the
        camera does not watch is left out here, as three.js's
        `projectObject` leaves it out of the frame's light list, so a mesh
        the camera draws is lit by exactly the lights the camera sees.

        Args:
            scene: The transform hierarchy, already updated, and the lights
                added to it.
            visible: The layers to take lights from, a camera's
                `visible_layers`. Every layer, the default, resolves every
                light in the scene.
            eye: Where the camera is, in world space. Only a `PHONG`
                material reads it, for the direction its highlight is
                measured along. `Renderer.render` passes the camera's own
                position; the origin, the default, is what a scene with no
                Phong surface wants.
            toward_eye: The one direction toward that camera, for a camera
                whose rays run parallel, or `PERSPECTIVE_VIEW`, the
                default, for one whose rays converge. `Renderer.render`
                passes `toward_camera`, which asks the camera's own
                projection. Normalized here, so a caller need not.

        Raises:
            Error: If a light's numbers are refused by `Light.validate`,
                whatever layer it is on; a light names a node or a target
                the scene does not have; a directional, hemisphere or spot
                light has no direction, because its node sits exactly
                where it points from — the origin, or its target — which
                is a mistake rather than a dark light; or a light's kind
                is none of the five.
        """
        self.eye = eye
        # Normalized here rather than at every fragment, and left alone when
        # it is the zero vector that means a converging view.
        self.toward_eye = toward_eye
        if self.toward_eye.length() != 0:
            self.toward_eye.normalize()
        self.ambient = FloatColor(0.0, 0.0, 0.0, 1.0)
        self.directions = List[Vector3]()
        self.radiances = List[FloatColor]()
        self.positions = List[Vector3]()
        self.point_radiances = List[FloatColor]()
        self.decays = List[Float32]()
        self.cutoffs = List[Float32]()
        self.sky_directions = List[Vector3]()
        self.skies = List[FloatColor]()
        self.grounds = List[FloatColor]()
        self.spot_positions = List[Vector3]()
        self.spot_directions = List[Vector3]()
        self.spot_radiances = List[FloatColor]()
        self.spot_decays = List[Float32]()
        self.spot_cutoffs = List[Float32]()
        self.cone_cosines = List[Float32]()
        self.penumbra_cosines = List[Float32]()
        for light in scene.lights:
            # Asked of every light, on the camera's layers or not: the
            # fields are open, a light in a persistent scene is there to
            # be edited, and a wrong light is a wrong asset rather than a
            # wrong frame.
            light.validate()
            if not light.layers.test(visible):
                continue
            if light.kind == AMBIENT:
                var fill = light.radiance()
                self.ambient = FloatColor(
                    self.ambient.r + fill.r,
                    self.ambient.g + fill.g,
                    self.ambient.b + fill.b,
                    1.0,
                )
            elif light.kind == DIRECTIONAL:
                # Where the node ended up after every transform above it,
                # seen from what it shines at.
                var pointing = scene.world_position(light.node) - _aimed_at(
                    scene, light
                )
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
            elif light.kind == HEMISPHERE:
                # Which way the sky is: the node's position seen from the
                # origin, as three.js reads it off the light's world matrix.
                var up = scene.world_position(light.node)
                if up.length() == 0:
                    raise Error(
                        "A hemisphere light needs a direction for its sky"
                    )
                up.normalize()
                self.sky_directions.append(up)
                self.skies.append(light.radiance())
                self.grounds.append(light.ground_radiance())
            elif light.kind == SPOT:
                var at = scene.world_position(light.node)
                # From the target toward the bulb, as three.js holds it.
                var axis = at - _aimed_at(scene, light)
                if axis.length() == 0:
                    raise Error(
                        "A spot light needs a direction: its node sits on"
                        " its target"
                    )
                axis.normalize()
                self.spot_positions.append(at)
                self.spot_directions.append(axis)
                self.spot_radiances.append(light.radiance())
                self.spot_decays.append(light.decay)
                self.spot_cutoffs.append(light.distance)
                # The cone as three.js's `coneCos` and `penumbraCos`: the
                # rim, and where the rim starts to soften, as cosines so
                # the fragment compares a dot product and takes no arc.
                self.cone_cosines.append(cos(light.angle.value))
                self.penumbra_cosines.append(
                    cos(light.angle.value * (1 - light.penumbra))
                )
            else:
                # The type stops a bare integer; it does not stop
                # `LightKind(7)`, and a light that is none of the five has
                # nothing here that knows how to evaluate it.
                raise Error("A light of an unknown kind cannot be resolved")

    def __init__(out self, *, ambient: FloatColor):
        """Create lighting with a fill term and no other lights.

        Args:
            ambient: The light arriving everywhere, already linear.
        """
        self.eye = Vector3(0, 0, 0)
        self.toward_eye = PERSPECTIVE_VIEW
        self.ambient = ambient
        self.directions = List[Vector3]()
        self.radiances = List[FloatColor]()
        self.positions = List[Vector3]()
        self.point_radiances = List[FloatColor]()
        self.decays = List[Float32]()
        self.cutoffs = List[Float32]()
        self.sky_directions = List[Vector3]()
        self.skies = List[FloatColor]()
        self.grounds = List[FloatColor]()
        self.spot_positions = List[Vector3]()
        self.spot_directions = List[Vector3]()
        self.spot_radiances = List[FloatColor]()
        self.spot_decays = List[Float32]()
        self.spot_cutoffs = List[Float32]()
        self.cone_cosines = List[Float32]()
        self.penumbra_cosines = List[Float32]()

    @staticmethod
    def uniform() -> Lighting:
        """Return lighting that leaves a surface's own color alone.

        Light of one in every channel, from nowhere in particular: the
        identity for the multiply a fragment does, so a caller with no lights
        in hand gets the colors it passed in rather than black.

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

    def hemisphere_count(self) -> Int:
        """Return how many hemisphere lights there are."""
        return len(self.sky_directions)

    def spot_count(self) -> Int:
        """Return how many spot lights there are."""
        return len(self.spot_positions)

    def intensity_at(self, normal: Vector3, position: Vector3) -> FloatColor:
        """Return how much light of each color reaches a surface here.

        The surface's own color is not in it: this is the light arriving,
        and multiplying by what the surface reflects is the caller's step.
        Split out because a fragment already holds its color in linear form
        and has no byte to decode, and because the GPU kernel computes exactly
        this and must compute it the same way.

        Lambert per light -- how much a surface catches falls off with the
        cosine of the angle it is turned through -- summed, plus the ambient
        term. A point light's Lambert term is taken against the direction
        from *this* surface to the bulb, and scaled by `falloff`. A
        hemisphere light adds its ground and sky mixed by how far the surface
        is turned toward the sky, with no cutoff. A spot light is a point
        light scaled by how far inside its cone the surface lies.

        The kinds are summed in this order on both backends, because
        floating-point addition is not associative and the parity tests ask
        for the same bits.

        Args:
            normal: The surface's unit normal, in world space.
            position: Where the surface is, in world space. Only a point or
                spot light reads it: how far away the bulb is, and in which
                direction, depends on where you stand, which is the one
                thing a directional light does not have.

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
        for index in range(len(self.sky_directions)):
            # How far the surface is turned toward the sky: one facing it,
            # zero facing the ground, a half edge-on. three.js's
            # `getHemisphereLightIrradiance`, ground to sky by that weight.
            var weight = 0.5 * normal.dot(self.sky_directions[index]) + 0.5
            ref sky = self.skies[index]
            ref ground = self.grounds[index]
            var lift = FloatColor(
                ground.r + (sky.r - ground.r) * weight,
                ground.g + (sky.g - ground.g) * weight,
                ground.b + (sky.b - ground.b) * weight,
                1.0,
            )
            total = FloatColor(
                total.r + lift.r, total.g + lift.g, total.b + lift.b, 1.0
            )
        for index in range(len(self.spot_positions)):
            var toward = self.spot_positions[index] - position
            var distance = toward.length()
            if distance == 0:
                continue
            # The cosine of the angle between the way to the bulb and the
            # cone's axis, and from it how far inside the cone this is:
            # three.js's `getSpotAttenuation`.
            var angle_cos = toward.dot(self.spot_directions[index]) / distance
            var rim = smoothstep(
                self.cone_cosines[index],
                self.penumbra_cosines[index],
                angle_cos,
            )
            if rim <= 0:
                continue
            var lambert = normal.dot(toward) / distance
            if lambert <= 0:
                continue
            var reach = (
                lambert
                * rim
                * falloff(
                    distance, self.spot_decays[index], self.spot_cutoffs[index]
                )
            )
            ref bulb = self.spot_radiances[index]
            total = FloatColor(
                total.r + bulb.r * reach,
                total.g + bulb.g * reach,
                total.b + bulb.b * reach,
                1.0,
            )
        return total

    def specular_at(
        self,
        normal: Vector3,
        position: Vector3,
        specular: Vector3,
        shininess: Float32,
    ) -> FloatColor:
        """Return the highlight a `PHONG` surface here sends to the camera.

        The specular half of three.js's `RE_Direct_BlinnPhong`, summed over
        the lights that have a direction. An ambient light has none, and a
        hemisphere light is an ambient term with a gradient, so neither
        makes a highlight; three.js reflects both through
        `RE_IndirectDiffuse` and nothing else.

        Separate from `intensity_at` rather than folded into it, so that a
        `LAMBERT` surface pays nothing for a term it has not got and every
        number this project already asserts stays where it was. The kinds
        are summed in the same fixed order, for the same reason.

        The surface's own color is not in it. A highlight is light bouncing
        off the surface rather than coming out of it, so the material's
        `specular` tints it and its `color` does not -- which is why a red
        plastic ball has a white highlight.

        Args:
            normal: The surface's unit normal, in world space.
            position: Where the surface is, in world space.
            specular: How much the surface reflects per channel, linear.
            shininess: How tight the highlight is.

        Returns:
            The reflected light, linear. Alpha is not light and stays at one.
        """
        # Which way the camera lies from here: one fixed direction under a
        # parallel projection, and the way to `eye` under a converging one.
        var toward_eye = toward_eye_at(self.eye, self.toward_eye, position)
        # A surface exactly at a converging camera has no direction to be
        # seen along.
        if toward_eye.length() == 0:
            return FloatColor(0.0, 0.0, 0.0, 1.0)
        var red = Float32(0)
        var green = Float32(0)
        var blue = Float32(0)
        for index in range(len(self.directions)):
            var lambert = max(Float32(0), normal.dot(self.directions[index]))
            if lambert == 0:
                continue
            var sent = blinn_phong(
                self.directions[index],
                toward_eye,
                normal,
                specular,
                shininess,
            )
            ref light = self.radiances[index]
            red += light.r * lambert * sent.x
            green += light.g * lambert * sent.y
            blue += light.b * lambert * sent.z
        for index in range(len(self.positions)):
            var toward = self.positions[index] - position
            var distance = toward.length()
            if distance == 0:
                continue
            var lambert = normal.dot(toward) / distance
            if lambert <= 0:
                continue
            var reach = lambert * falloff(
                distance, self.decays[index], self.cutoffs[index]
            )
            toward.normalize()
            var sent = blinn_phong(
                toward, toward_eye, normal, specular, shininess
            )
            ref bulb = self.point_radiances[index]
            red += bulb.r * reach * sent.x
            green += bulb.g * reach * sent.y
            blue += bulb.b * reach * sent.z
        for index in range(len(self.spot_positions)):
            var toward = self.spot_positions[index] - position
            var distance = toward.length()
            if distance == 0:
                continue
            var angle_cos = toward.dot(self.spot_directions[index]) / distance
            var rim = smoothstep(
                self.cone_cosines[index],
                self.penumbra_cosines[index],
                angle_cos,
            )
            if rim <= 0:
                continue
            var lambert = normal.dot(toward) / distance
            if lambert <= 0:
                continue
            var reach = (
                lambert
                * rim
                * falloff(
                    distance, self.spot_decays[index], self.spot_cutoffs[index]
                )
            )
            toward.normalize()
            var sent = blinn_phong(
                toward, toward_eye, normal, specular, shininess
            )
            ref bulb = self.spot_radiances[index]
            red += bulb.r * reach * sent.x
            green += bulb.g * reach * sent.y
            blue += bulb.b * reach * sent.z
        return FloatColor(red, green, blue, 1.0)

    def shade(
        self, base: Color, normal: Vector3, position: Vector3
    ) -> FloatColor:
        """Return `base` lit by every light, in linear light.

        The base color is decoded from sRGB first: an authored byte is not
        proportional to light, and multiplying it by a Lambert term would be
        arithmetic on the wrong numbers. See `render.srgb`.

        Nothing is clamped. A surface under two bright lamps really is over
        one, and `RenderTarget.resolve` is the single place that decides what
        a display can show. Clamping here would do it twice and lose the
        headroom in between.

        Args:
            base: The surface's own color, as authored.
            normal: Its unit normal, in world space.
            position: Where it is, in world space, for the point lights.

        Returns:
            The lit color, linear, with the base color's alpha.
        """
        var total = self.intensity_at(normal, position)
        var surface = FloatColor(srgb=base)
        return FloatColor(
            surface.r * total.r,
            surface.g * total.g,
            surface.b * total.b,
            surface.a,
        )
