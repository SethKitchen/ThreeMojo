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

**On three.js's reciprocal pi.** three.js divides every diffuse term by
pi, `BRDF_Lambert`, direct and indirect alike, and its specular lobe too,
`D_BlinnPhong`. A white surface square on to a white light of intensity one
therefore reflects `1 / pi` of it, about 0.318, and a light meant to read
as full white is given an intensity of about three -- which is what
three.js's own examples do since its lights became physically correct. The
same holds here: `Lighting(scene)` carries the factor as `scale`, applied
once to each sum, so that emissive, basic and matcap surfaces -- which
three.js does not divide -- stand in the same ratio to lit ones as there.
`Lighting.uniform` carries a scale of one instead: it is the identity for
the multiply a fragment does, and a scale would make it something else.
`blinn_phong` itself drops its factor of pi and `specular_at` applies the
scale, so the highlight and the diffuse term move together.
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
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import cos, exp2, log2, max, min, pi, sqrt

# What every lit sum is multiplied by: three.js's `RECIPROCAL_PI`, the
# factor in `BRDF_Lambert` and `D_BlinnPhong`. See the module docstring.
comptime RECIPROCAL_PI = Float32(1) / Float32(pi)

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


# Where three.js's fallback toon ramp steps, and how lit its low tone is:
# `mix(vec3(0.7), vec3(1.0), smoothstep(0.7 - fw, 0.7 + fw, coord))` in
# three.js's `lights_toon_pars_fragment`. The two numbers are the same 0.7
# by coincidence of three.js's choice, so they are named apart.
comptime TOON_EDGE = Float32(0.7)
comptime TOON_SHADE = Float32(0.7)


def toon_coord(dot_nl: Float32) -> Float32:
    """Return where a cosine falls on a toon ramp, three.js's `coord`.

    **A toon surface never fades to black.** three.js reads its ramp at
    `dot(N, L) * 0.5 + 0.5`, so a surface turned fully away from a lamp
    reads the ramp's left end rather than zero. A Lambert term clamps the
    cosine at zero and a toon ramp does not, which is why a toon surface
    keeps a flat shaded tone where a Lambert one goes dark.

    Shared by both rasterizers, as `falloff` is, so that neither can read a
    ramp somewhere the other does not.

    Args:
        dot_nl: The cosine between the surface normal and the direction
            toward the light, from minus one to one.

    Returns:
        Where to read the ramp, from zero to one.
    """
    return dot_nl * 0.5 + 0.5


def toon_step(coord: Float32) -> Float32:
    """Return three.js's fallback ramp at `coord`: two tones, one edge.

    three.js antialiases the edge with `fwidth`, a screen-space derivative
    of the coordinate. A software rasterizer shades one fragment at a time
    and has no neighboring fragment to take a derivative against, so the
    edge is hard here. That is the one difference, and it shows only on the
    single row of fragments the edge crosses.

    Args:
        coord: Where on the ramp to read, from `toon_coord`.

    Returns:
        `TOON_SHADE` below the edge, one at or above it.
    """
    if coord < TOON_EDGE:
        return TOON_SHADE
    return 1.0


def toon_index(coord: Float32, count: Int) -> Int:
    """Return which tone of a ramp of `count` tones `coord` reads.

    Nearest, with both ends clamped: a ramp is a lookup table rather than a
    picture, so it is never filtered and never wrapped. three.js's own
    gradient maps are built `NearestFilter` and `ClampToEdgeWrapping` for
    the same reason.

    Shared by both rasterizers, so that a ramp of three tones cannot step
    at one coordinate on the host and another on the device.

    Args:
        coord: Where on the ramp to read, from `toon_coord`.
        count: How many tones the ramp holds, one or more.

    Returns:
        The tone to read, from zero to `count` minus one.
    """
    var slot = Int(coord * Float32(count))
    if slot < 0:
        return 0
    if slot >= count:
        return count - 1
    return slot


def toon_tone(dot_nl: Float32, ramp: List[Float32]) -> Float32:
    """Return how lit a toon surface looks at this cosine.

    The host's spelling of what the kernel does with the same three
    functions. An empty ramp means the material named none, and three.js's
    fallback applies.

    Args:
        dot_nl: The cosine between the surface normal and the direction
            toward the light.
        ramp: The tones of the material's gradient map, left to right, or
            empty for the fallback.

    Returns:
        How lit the surface looks, from zero to one.
    """
    var coord = toon_coord(dot_nl)
    if len(ramp) == 0:
        return toon_step(coord)
    return ramp[toon_index(coord, len(ramp))]


# three.js's `G_BlinnPhong_Implicit`: the geometric term of the Blinn-Phong
# BRDF, a constant there and here.
comptime BLINN_PHONG_G = Float32(0.25)
# The two numbers in three.js's `F_Schlick`, which approximates how much
# more a surface reflects at a grazing angle.
comptime _FRESNEL_SLOPE = Float32(-5.55473)
comptime _FRESNEL_OFFSET = Float32(-6.98316)
# The roughness a physical surface is never smoother than: three.js's
# 0.0525, the base mip of a 256-texel cube map, below which a GGX lobe
# is narrower than a pixel and sparkles.
comptime ROUGHNESS_FLOOR = Float32(0.0525)
# What a dielectric reflects head on, per channel: three.js's `vec3(0.04)`,
# the reflectance of an index of refraction of one and a half.
comptime DIELECTRIC_F0 = Vector3(0.04, 0.04, 0.04)
# What a clear coat reflects head on: the same, three.js's `clearcoatF0`.
comptime CLEARCOAT_F0 = Vector3(0.04, 0.04, 0.04)
# Where the GGX visibility term's denominator is held off zero: three.js's
# `EPSILON`.
comptime GGX_EPSILON = Float32(1e-6)
# The average Fresnel over the hemisphere, one twenty-first, as
# `computeMultiscattering` uses it.
comptime MULTISCATTER_MEAN = Float32(0.047619)


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
    var fresnel = f_schlick(specular, 1, grazing)
    # three.js's D_BlinnPhong, without its reciprocal pi.
    var lobe = (shininess * 0.5 + 1) * exp2(shininess * log2(facing))
    var scale = BLINN_PHONG_G * lobe
    return Vector3(fresnel.x * scale, fresnel.y * scale, fresnel.z * scale)


def f_schlick(f0: Vector3, f90: Float32, cos_vh: Float32) -> Vector3:
    """Return how much a surface reflects at an angle: three.js's `F_Schlick`.

    A surface reflects `f0` of the light head on and `f90` at a grazing
    angle, and Schlick's approximation rises from the one to the other by
    the fifth power of one minus the cosine. three.js spells that power as
    `exp2` of a quadratic in the cosine, and so does this, so the kernel
    and the host compute it from one intrinsic both already have.

    Args:
        f0: The reflectance head on, per channel, linear.
        f90: The reflectance at a grazing angle, one for every surface but
            a physical one with a specular intensity below one.
        cos_vh: The cosine between the eye and the half vector, from zero
            to one.

    Returns:
        The reflectance per channel.
    """
    var fresnel = exp2((_FRESNEL_SLOPE * cos_vh + _FRESNEL_OFFSET) * cos_vh)
    var keep = 1 - fresnel
    return Vector3(
        f0.x * keep + f90 * fresnel,
        f0.y * keep + f90 * fresnel,
        f0.z * keep + f90 * fresnel,
    )


def _saturated(value: Float32) -> Float32:
    """Return `value` clamped to zero through one: GLSL's `saturate`."""
    return max(Float32(0), min(Float32(1), value))


def ggx(
    toward_light: Vector3,
    toward_eye: Vector3,
    normal: Vector3,
    f0: Vector3,
    f90: Float32,
    roughness: Float32,
) -> Vector3:
    """Return the fraction of light arriving from one direction that a
    physical surface sends toward another: three.js's `BRDF_GGX`.

    Three factors multiply, each three.js's own: `F_Schlick` for the
    Fresnel rise, `V_GGX_SmithCorrelated` for how much of the surface's
    microfacets shadow each other, and `D_GGX` for how many of them face the
    half vector -- with one factor of pi dropped from the last, for the
    reason `blinn_phong` drops it. The roughness is squared first, Disney's
    reparameterization, as three.js squares it. A surface turned away from
    the light or from the eye reflects nothing and returns early, which
    also keeps the visibility term's denominator off zero.

    Args:
        toward_light: Unit vector from the surface toward the light.
        toward_eye: Unit vector from the surface toward the camera.
        normal: The surface's unit normal.
        f0: The surface's reflectance head on, per channel, linear.
        f90: Its reflectance at a grazing angle.
        roughness: How rough the surface is, from zero to one. The
            caller floors it; see `ROUGHNESS_FLOOR`.

    Returns:
        The reflected fraction per channel. Above one at the center of a
        tight highlight, which is what a highlight is.
    """
    var half = toward_light + toward_eye
    if half.length() == 0:
        return Vector3(0, 0, 0)
    half.normalize()
    var alpha = roughness * roughness
    var dot_nl = _saturated(normal.dot(toward_light))
    var dot_nv = _saturated(normal.dot(toward_eye))
    var dot_nh = _saturated(normal.dot(half))
    var dot_vh = _saturated(toward_eye.dot(half))
    if dot_nl == 0 or dot_nv == 0:
        return Vector3(0, 0, 0)
    var fresnel = f_schlick(f0, f90, dot_vh)
    # three.js's V_GGX_SmithCorrelated.
    var a2 = alpha * alpha
    var gv = dot_nl * sqrt(a2 + (1 - a2) * dot_nv * dot_nv)
    var gl = dot_nv * sqrt(a2 + (1 - a2) * dot_nl * dot_nl)
    var visibility = 0.5 / max(gv + gl, GGX_EPSILON)
    # three.js's D_GGX, without its reciprocal pi.
    var denominator = dot_nh * dot_nh * (a2 - 1) + 1
    var lobe = a2 / (denominator * denominator)
    var scale = visibility * lobe
    return Vector3(fresnel.x * scale, fresnel.y * scale, fresnel.z * scale)


def dfg_approx(dot_nv: Float32, roughness: Float32) -> Vector2:
    """Return the two numbers that sum an environment's reflection over a
    rough lobe: three.js's `DFGApprox`, Karis's fit to the split-sum table.

    Args:
        dot_nv: The cosine between the normal and the eye, from zero to one.
        roughness: How rough the surface is, from zero to one.

    Returns:
        What to multiply the reflectance head on by, and what to add to it
        scaled by the grazing reflectance.
    """
    var r_x = roughness * -1 + 1
    var r_y = roughness * -0.0275 + 0.0425
    var r_z = roughness * -0.572 + 1.04
    var r_w = roughness * 0.022 + -0.04
    var a004 = min(r_x * r_x, exp2(-9.28 * dot_nv)) * r_x + r_y
    return Vector2(-1.04 * a004 + r_z, 1.04 * a004 + r_w)


def environment_brdf(
    dot_nv: Float32, f0: Vector3, f90: Float32, roughness: Float32
) -> Vector3:
    """Return how much of an environment's radiance a rough surface sends
    toward the eye: three.js's `EnvironmentBRDF`.

    Args:
        dot_nv: The cosine between the normal and the eye, from zero to one.
        f0: The reflectance head on, per channel, linear.
        f90: The reflectance at a grazing angle.
        roughness: How rough the surface is, from zero to one.

    Returns:
        The fraction per channel.
    """
    var fab = dfg_approx(dot_nv, roughness)
    return Vector3(
        f0.x * fab.x + f90 * fab.y,
        f0.y * fab.x + f90 * fab.y,
        f0.z * fab.x + f90 * fab.y,
    )


@fieldwise_init
struct Reflected(ImplicitlyCopyable):
    """What a physical surface sends toward the camera, split the way
    three.js's `ReflectedLight` splits it, so the environment can join
    each part on its own terms.

    Linear light per channel, as a `Vector3` because the kernel has no
    color type. Alpha is coverage, not light, and never appears here.
    """

    # Light scattered by the surface's color: the Lambert term.
    var diffuse: Vector3
    # Light bounced off the surface's microfacets: the GGX lobe.
    var specular: Vector3
    # Light bounced off the clear coat over the surface, on the surface's
    # unperturbed normal. Zero for a surface without one.
    var clearcoat: Vector3


def physical_surface(
    base: Vector3,
    f0: Vector3,
    metalness: Float32,
    specular_intensity: Float32,
) -> Reflected:
    """Return a physical surface's three colors from its base color and
    its metalness: three.js's `lights_physical_fragment`.

    A metal has no diffuse color and reflects its own color; a dielectric
    scatters its color and reflects `f0`. The two are mixed by the
    metalness, as three.js mixes them. The grazing reflectance rides in
    `clearcoat.x`, since a `Reflected` has no fourth slot and this is what
    both rasterizers unpack.

    Args:
        base: The surface's color, linear, with any map applied.
        f0: Its reflectance head on, linear: `Material.base_reflectance`.
        metalness: How much of a metal it is, from zero to one.
        specular_intensity: What scales the reflectance, three.js's
            `specularIntensity`; one for a `STANDARD` surface.

    Returns:
        `diffuse` as the color that scatters, `specular` as the color that
        reflects head on, and `clearcoat.x` as the reflectance at a grazing
        angle.
    """
    var keep = 1 - metalness
    var f90 = specular_intensity + (1 - specular_intensity) * metalness
    return Reflected(
        Vector3(base.x * keep, base.y * keep, base.z * keep),
        Vector3(
            f0.x + (base.x - f0.x) * metalness,
            f0.y + (base.y - f0.y) * metalness,
            f0.z + (base.z - f0.z) * metalness,
        ),
        Vector3(f90, 0, 0),
    )


def floored_roughness(roughness: Float32) -> Float32:
    """Return a roughness never below `ROUGHNESS_FLOOR` and never above one,
    as three.js's `lights_physical_fragment` clamps it.

    three.js adds a geometric roughness from how fast the normal changes
    across the pixel, which needs the neighboring pixels' normals; this
    project shades each pixel alone and adds none.

    Args:
        roughness: The authored roughness, times any map.

    Returns:
        The roughness the lobe is evaluated with.
    """
    return min(max(roughness, ROUGHNESS_FLOOR), Float32(1))


def physical_outgoing(
    direct: Reflected,
    indirect: Vector3,
    surface: Reflected,
    roughness: Float32,
    dot_nv: Float32,
    reflects: Bool,
    radiance: Vector3,
    irradiance: Vector3,
    glow: Vector3,
    clearcoat: Float32,
    clearcoat_roughness: Float32,
    dot_nv_coat: Vector3,
    coat_radiance: Vector3,
) -> Vector3:
    """Return the light a physical surface sends toward the camera, from
    its direct light, its indirect light and its environment: three.js's
    `RE_IndirectDiffuse_Physical`, `RE_IndirectSpecular_Physical` and the
    end of `meshphysical_frag`, in that order.

    The indirect light scatters through the diffuse color. The environment
    reflects through the split sum, and Fdez-Aguera's multiple scattering
    hands the energy a single bounce loses back as a second one, which
    darkens the diffuse by what the lobe kept. The clear coat, when there
    is one, dims everything under it by its own Fresnel and adds its own
    reflection on top, which is why a coated red surface is red under a
    white gloss. Shared by both rasterizers, as `combine_light` is.

    Args:
        direct: The three sums over the lights, from `Lighting.physical_at`.
        indirect: The ambient and hemisphere light arriving, already scaled.
        surface: The three colors from `physical_surface`.
        roughness: The floored roughness.
        dot_nv: The cosine between the normal and the eye, from zero to one.
        reflects: Whether an environment was sampled at all.
        radiance: What the environment shows along the rough reflection,
            times the env map intensity. Read only when `reflects`.
        irradiance: What the environment shows around the normal, times
            the intensity: the cosine-weighted irradiance, which three.js
            multiplies by pi and divides again. Read only when `reflects`.
        glow: The emissive term, times its map.
        clearcoat: How much clear coat there is, from zero to one; zero
            for none.
        clearcoat_roughness: Its floored roughness.
        dot_nv_coat: The cosine between the coat's normal and the eye in
            `.x`; the other two are unused. A vector so a kernel with no
            optional can pass one shape.
        coat_radiance: What the environment shows along the coat's own
            reflection, times the intensity. Read only when `reflects`.

    Returns:
        The outgoing light, linear.
    """
    var diffuse = Vector3(
        direct.diffuse.x + surface.diffuse.x * indirect.x,
        direct.diffuse.y + surface.diffuse.y * indirect.y,
        direct.diffuse.z + surface.diffuse.z * indirect.z,
    )
    var specular = direct.specular
    var coat = direct.clearcoat
    var f90 = surface.clearcoat.x
    if reflects:
        # three.js's `computeMultiscattering`.
        var fab = dfg_approx(dot_nv, roughness)
        var single = Vector3(
            surface.specular.x * fab.x + f90 * fab.y,
            surface.specular.y * fab.x + f90 * fab.y,
            surface.specular.z * fab.x + f90 * fab.y,
        )
        var ess = fab.x + fab.y
        var ems = 1 - ess
        var average = Vector3(
            surface.specular.x + (1 - surface.specular.x) * MULTISCATTER_MEAN,
            surface.specular.y + (1 - surface.specular.y) * MULTISCATTER_MEAN,
            surface.specular.z + (1 - surface.specular.z) * MULTISCATTER_MEAN,
        )
        var multi = Vector3(
            single.x * average.x / (1 - ems * average.x) * ems,
            single.y * average.y / (1 - ems * average.y) * ems,
            single.z * average.z / (1 - ems * average.z) * ems,
        )
        var total = max(
            max(single.x + multi.x, single.y + multi.y), single.z + multi.z
        )
        var kept = 1 - total
        specular = Vector3(
            specular.x + radiance.x * single.x + multi.x * irradiance.x,
            specular.y + radiance.y * single.y + multi.y * irradiance.y,
            specular.z + radiance.z * single.z + multi.z * irradiance.z,
        )
        diffuse = Vector3(
            diffuse.x + surface.diffuse.x * kept * irradiance.x,
            diffuse.y + surface.diffuse.y * kept * irradiance.y,
            diffuse.z + surface.diffuse.z * kept * irradiance.z,
        )
        if clearcoat > 0:
            var sheen = environment_brdf(
                dot_nv_coat.x, CLEARCOAT_F0, 1, clearcoat_roughness
            )
            coat = Vector3(
                coat.x + coat_radiance.x * sheen.x,
                coat.y + coat_radiance.y * sheen.y,
                coat.z + coat_radiance.z * sheen.z,
            )
    var outgoing = Vector3(
        diffuse.x + specular.x + glow.x,
        diffuse.y + specular.y + glow.y,
        diffuse.z + specular.z + glow.z,
    )
    if clearcoat > 0:
        var fresnel = f_schlick(CLEARCOAT_F0, 1, dot_nv_coat.x)
        outgoing = Vector3(
            outgoing.x * (1 - clearcoat * fresnel.x) + coat.x * clearcoat,
            outgoing.y * (1 - clearcoat * fresnel.y) + coat.y * clearcoat,
            outgoing.z * (1 - clearcoat * fresnel.z) + coat.z * clearcoat,
        )
    return outgoing


def physical_light(
    sum: Reflected,
    light: Vector3,
    lambert: Float32,
    coat_lambert: Float32,
    toward_light: Vector3,
    toward_eye: Vector3,
    normal: Vector3,
    coat_normal: Vector3,
    surface: Reflected,
    roughness: Float32,
    clearcoat_roughness: Float32,
) -> Reflected:
    """Return `sum` with one light's contribution added: three.js's
    `RE_Direct_Physical` for one `IncidentLight`.

    Shared by `Lighting.physical_at` and the kernel's `_physical`, so the
    three products are formed in one order on both backends.

    Args:
        sum: The three sums so far.
        light: The light's radiance reaching the surface, linear, with any
            falloff and rim already applied.
        lambert: The cosine between the surface's normal and the light,
            floored at zero.
        coat_lambert: The same on the coat's normal, or zero for no coat.
        toward_light: Unit vector from the surface toward the light.
        toward_eye: Unit vector from the surface toward the camera.
        normal: The surface's unit normal.
        coat_normal: The coat's unit normal.
        surface: The surface's three colors, from `physical_surface`.
        roughness: The floored roughness.
        clearcoat_roughness: The coat's floored roughness.

    Returns:
        The three sums with this light added.
    """
    var f90 = surface.clearcoat.x
    var diffuse = sum.diffuse
    var specular = sum.specular
    var coat = sum.clearcoat
    if lambert > 0:
        var irradiance = Vector3(
            light.x * lambert, light.y * lambert, light.z * lambert
        )
        var lobe = ggx(
            toward_light, toward_eye, normal, surface.specular, f90, roughness
        )
        specular = Vector3(
            specular.x + irradiance.x * lobe.x,
            specular.y + irradiance.y * lobe.y,
            specular.z + irradiance.z * lobe.z,
        )
        diffuse = Vector3(
            diffuse.x + irradiance.x * surface.diffuse.x,
            diffuse.y + irradiance.y * surface.diffuse.y,
            diffuse.z + irradiance.z * surface.diffuse.z,
        )
    if coat_lambert > 0:
        var lobe = ggx(
            toward_light,
            toward_eye,
            coat_normal,
            CLEARCOAT_F0,
            1,
            clearcoat_roughness,
        )
        coat = Vector3(
            coat.x + light.x * coat_lambert * lobe.x,
            coat.y + light.y * coat_lambert * lobe.y,
            coat.z + light.z * coat_lambert * lobe.z,
        )
    return Reflected(diffuse, specular, coat)


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
    # Which way is up for the camera, in world space: the frame a `MATCAP`
    # surface is looked up in. three.js measures that frame against the
    # view space +y axis, and this is that axis in world coordinates, so
    # the two reach the same coordinate. World up, the default, is what a
    # scene with no matcap wants and what an upright camera has anyway.
    var up: Vector3
    # The sum of every ambient light, already decoded and scaled.
    var ambient: FloatColor
    # What each sum of arriving light is multiplied by before it is
    # returned: `RECIPROCAL_PI` for a scene's lights, as three.js's BRDF
    # has it, and one for `uniform`, the identity. Crosses to the kernel
    # in the light buffer, so both backends scale the same sums.
    var scale: Float32
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
        up: Vector3 = Vector3(0, 1, 0),
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
            up: Which way is up for that camera, in world space. Only a
                `MATCAP` material reads it, for the frame it is looked up
                in. `Renderer.render` passes `camera_up`. World up, the
                default, is what an upright camera has. Normalized here.

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
        # Normalized here rather than at every fragment, as `toward_eye` is.
        # A zero vector is left alone: it names no frame, and `matcap_uv`
        # answers the middle of the image for one.
        self.up = up
        if self.up.length() != 0:
            self.up.normalize()
        self.ambient = FloatColor(0.0, 0.0, 0.0, 1.0)
        self.scale = RECIPROCAL_PI
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
        self.up = Vector3(0, 1, 0)
        self.ambient = ambient
        self.scale = 1
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
        return total.scaled(self.scale)

    def toon_at(
        self, normal: Vector3, position: Vector3, ramp: List[Float32]
    ) -> FloatColor:
        """Return how much light of each color reaches a `TOON` surface here.

        `intensity_at` with every cosine read off a ramp, three.js's
        `RE_Direct_Toon`. The lights that have a direction are stepped;
        the ambient term and the hemisphere lights are not, because
        three.js reflects those through `RE_IndirectDiffuse` and a ramp is
        a direct term. The kinds are summed in the same order as there, so
        the two methods round alike wherever they agree.

        **A light that the surface is turned away from still counts.** The
        ramp is read at `dot(N, L) * 0.5 + 0.5`, which has no zero to clamp
        at, so a lamp behind the surface reads the ramp's left end. That is
        what keeps a toon surface flat on its shaded side instead of black.
        A point or spot light is still cut off by distance and by its cone,
        because three.js's `directLight.visible` is false there.

        Separate from `intensity_at` rather than folded into it, for the
        reason `specular_at` is separate: a `LAMBERT` surface pays nothing
        for a ramp it has not got, and every number already asserted of
        `intensity_at` stays where it was.

        Args:
            normal: The surface's unit normal, in world space.
            position: Where the surface is, in world space. Only a point or
                spot light reads it.
            ramp: The tones of the material's gradient map, left to right,
                or empty for three.js's two-tone fallback.

        Returns:
            The arriving light, linear. Alpha is not light and stays at one.
        """
        var total = self.ambient
        for index in range(len(self.directions)):
            var tone = toon_tone(normal.dot(self.directions[index]), ramp)
            ref light = self.radiances[index]
            total = FloatColor(
                total.r + light.r * tone,
                total.g + light.g * tone,
                total.b + light.b * tone,
                1.0,
            )
        for index in range(len(self.positions)):
            var toward = self.positions[index] - position
            var distance = toward.length()
            # A surface exactly on the bulb has no direction to be lit from.
            if distance == 0:
                continue
            var tone = toon_tone(normal.dot(toward) / distance, ramp)
            var reach = tone * falloff(
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
            # Indirect, so it is not stepped: the same sum as `intensity_at`.
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
            var angle_cos = toward.dot(self.spot_directions[index]) / distance
            var rim = smoothstep(
                self.cone_cosines[index],
                self.penumbra_cosines[index],
                angle_cos,
            )
            if rim <= 0:
                continue
            var tone = toon_tone(normal.dot(toward) / distance, ramp)
            var reach = (
                tone
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
        return total.scaled(self.scale)

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
        return FloatColor(red, green, blue, 1.0).scaled(self.scale)

    def indirect_at(self, normal: Vector3) -> FloatColor:
        """Return the light with no direction reaching a surface here: the
        ambient term and the hemisphere lights, three.js's `irradiance` in
        `lights_fragment_begin`.

        The half of `intensity_at` that a physical surface scatters through
        its diffuse color alone: three.js's `RE_IndirectDiffuse_Physical`.
        The lights with a direction go through `physical_at` instead, where
        they make a lobe as well. Summed in the order `intensity_at` sums
        the same two kinds, and scaled once, as there.

        Args:
            normal: The surface's unit normal, in world space.

        Returns:
            The arriving light, linear. Alpha is not light and stays at one.
        """
        var total = self.ambient
        for index in range(len(self.sky_directions)):
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
        return total.scaled(self.scale)

    def physical_at(
        self,
        normal: Vector3,
        coat_normal: Vector3,
        position: Vector3,
        surface: Reflected,
        roughness: Float32,
        clearcoat: Float32,
        clearcoat_roughness: Float32,
    ) -> Reflected:
        """Return what a physical surface here sends to the camera from the
        lights that have a direction: three.js's `RE_Direct_Physical`,
        summed over them.

        Each light's irradiance, its radiance times the Lambert cosine,
        scatters through the diffuse color and reflects through `ggx` on
        the surface's normal; with a clear coat it reflects once more, on
        the coat's own normal, which is the surface's before any map
        perturbed it. The kinds are summed in the order `specular_at` sums
        them, for the reason given there, and scaled once at the end.

        Args:
            normal: The surface's unit normal, in world space, after any
                normal or bump map.
            coat_normal: The unperturbed unit normal the clear coat lies
                on. Read only when `clearcoat` is above zero.
            position: Where the surface is, in world space.
            surface: Its three colors, from `physical_surface`.
            roughness: Its floored roughness.
            clearcoat: How much clear coat there is; zero for none.
            clearcoat_roughness: The coat's floored roughness.

        Returns:
            The diffuse, specular and clear coat sums, linear, each scaled.
        """
        var none = Reflected(
            Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0)
        )
        var toward_eye = toward_eye_at(self.eye, self.toward_eye, position)
        if toward_eye.length() == 0:
            return none
        var sum = none
        for index in range(len(self.directions)):
            var lambert = max(Float32(0), normal.dot(self.directions[index]))
            var coat_lambert = Float32(0)
            if clearcoat > 0:
                coat_lambert = max(
                    Float32(0), coat_normal.dot(self.directions[index])
                )
            if lambert == 0 and coat_lambert == 0:
                continue
            ref light = self.radiances[index]
            sum = physical_light(
                sum,
                Vector3(light.r, light.g, light.b),
                lambert,
                coat_lambert,
                self.directions[index],
                toward_eye,
                normal,
                coat_normal,
                surface,
                roughness,
                clearcoat_roughness,
            )
        for index in range(len(self.positions)):
            var toward = self.positions[index] - position
            var distance = toward.length()
            if distance == 0:
                continue
            var lambert = max(Float32(0), normal.dot(toward) / distance)
            var coat_lambert = Float32(0)
            if clearcoat > 0:
                coat_lambert = max(
                    Float32(0), coat_normal.dot(toward) / distance
                )
            if lambert == 0 and coat_lambert == 0:
                continue
            var reach = falloff(
                distance, self.decays[index], self.cutoffs[index]
            )
            toward.normalize()
            ref bulb = self.point_radiances[index]
            sum = physical_light(
                sum,
                Vector3(bulb.r * reach, bulb.g * reach, bulb.b * reach),
                lambert,
                coat_lambert,
                toward,
                toward_eye,
                normal,
                coat_normal,
                surface,
                roughness,
                clearcoat_roughness,
            )
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
            var lambert = max(Float32(0), normal.dot(toward) / distance)
            var coat_lambert = Float32(0)
            if clearcoat > 0:
                coat_lambert = max(
                    Float32(0), coat_normal.dot(toward) / distance
                )
            if lambert == 0 and coat_lambert == 0:
                continue
            var reach = rim * falloff(
                distance, self.spot_decays[index], self.spot_cutoffs[index]
            )
            toward.normalize()
            ref bulb = self.spot_radiances[index]
            sum = physical_light(
                sum,
                Vector3(bulb.r * reach, bulb.g * reach, bulb.b * reach),
                lambert,
                coat_lambert,
                toward,
                toward_eye,
                normal,
                coat_normal,
                surface,
                roughness,
                clearcoat_roughness,
            )
        return Reflected(
            sum.diffuse * self.scale,
            sum.specular * self.scale,
            sum.clearcoat * self.scale,
        )

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
