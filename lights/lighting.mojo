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
from lights.shadow import ShadowMap, SpotLightMap
from lights.light import (
    AMBIENT,
    DIRECTIONAL,
    HEMISPHERE,
    LIGHT_PROBE,
    POINT,
    RECT_AREA,
    SPOT,
    Light,
)
from lights.ltc import LtcTables, ltc_lookup, ltc_uv, rect_area_light
from math.smoothstep import smoothstep
from math.spherical_harmonics3 import SphericalHarmonics3
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import cos, exp2, log2, max, min, pi, sqrt
from units.si import METER

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

    The roughness is read as given, not floored: at zero and head on the
    distribution divides zero by zero, so the caller floors it first, as
    `floored_roughness` floors it and as three.js floors it before either
    of its lobes. Head on, the lobe is `f0 / (4 alpha^2)`, alpha being the
    roughness squared, which is what the tests hold it to.

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

    **Three roughnesses, and this is the boundary between the first two.**
    The *authored* roughness is the material's number times its map, from
    zero to one. The *BRDF* roughness is that floored, and it is what
    every lobe is evaluated with, the direct lights' included: three.js
    clamps `material.roughness` once and `RE_Direct_Physical` reads the
    clamped one, so an authored zero, 0.01 and 0.0525 make one lobe under
    a lamp, there as here. The floor is also what keeps `ggx` finite, which
    divides zero by zero at an alpha of zero head on. The third, the
    *environment* roughness, is the BRDF roughness read as a mip level by
    `render.cube_texture.reflection_level`, an approximation of its own.

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
    occlusion: Float32 = 1,
) -> Vector3:
    """Return the light a physical surface sends toward the camera, from
    its direct light, its indirect light and its environment: three.js's
    `RE_IndirectDiffuse_Physical`, `RE_IndirectSpecular_Physical` and the
    end of `meshphysical_frag`, in that order.

    The indirect light scatters through the diffuse color. The environment
    reflects through the split sum, and Fdez-Aguera's multiple scattering
    hands the energy a single bounce loses back as a second one, which
    darkens the diffuse by what the lobe kept -- by the *largest* channel
    of what it kept, as three.js's `max3(totalScattering)` takes it, so
    a red reflectance and a blue one of equal average keep the diffuse by
    the same amount only when their largest channels agree. The clear
    coat, when there is one, dims everything under it by its own Fresnel
    and adds its own reflection on top, which is why a coated red surface
    is red under a white gloss. Shared by both rasterizers, as
    `combine_light` is.

    **What the caller hands in decides how close this is to three.js.**
    `radiance` is the environment integrated over the lobe and
    `irradiance` the environment integrated over the hemisphere weighted
    by the cosine. A prefiltered cube, `render.pmrem`, gives both as
    three.js does: its PMREM read at the roughness and at roughness one.
    Any other cube gives two approximations: a mip level of the cube
    picked by the roughness, a spatial average rather than a lobe, and
    the coarsest level, each face's average. Under a sky that is one
    bright patch on black, the second over-reads: the average of the face
    the patch is on, where the cosine-weighted integral is smaller. The
    tests pin both. See `CubeTexture.sample_rough`.

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
        occlusion: How much of the indirect light reaches the surface,
            from `ambient_occlusion`: three.js's `aomap_fragment`. It
            multiplies the indirect diffuse and the coat's reflection, and
            `specular_occlusion` of it multiplies the environment's
            reflection. One, the default, occludes nothing, and each term
            is multiplied by it last, so a one leaves every bit alone.

    Returns:
        The outgoing light, linear.
    """
    var diffuse = Vector3(
        direct.diffuse.x + surface.diffuse.x * indirect.x * occlusion,
        direct.diffuse.y + surface.diffuse.y * indirect.y * occlusion,
        direct.diffuse.z + surface.diffuse.z * indirect.z * occlusion,
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
        # three.js's `computeSpecularOcclusion`, which dims a reflection
        # less than the diffuse where the surface faces the eye.
        var shade = specular_occlusion(dot_nv, occlusion, roughness)
        specular = Vector3(
            specular.x
            + radiance.x * single.x * shade
            + multi.x * irradiance.x * shade,
            specular.y
            + radiance.y * single.y * shade
            + multi.y * irradiance.y * shade,
            specular.z
            + radiance.z * single.z * shade
            + multi.z * irradiance.z * shade,
        )
        diffuse = Vector3(
            diffuse.x + surface.diffuse.x * kept * irradiance.x * occlusion,
            diffuse.y + surface.diffuse.y * kept * irradiance.y * occlusion,
            diffuse.z + surface.diffuse.z * kept * irradiance.z * occlusion,
        )
        if clearcoat > 0:
            var sheen = environment_brdf(
                dot_nv_coat.x, CLEARCOAT_F0, 1, clearcoat_roughness
            )
            coat = Vector3(
                coat.x + coat_radiance.x * sheen.x * occlusion,
                coat.y + coat_radiance.y * sheen.y * occlusion,
                coat.z + coat_radiance.z * sheen.z * occlusion,
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


def ambient_occlusion(texel: Float32, intensity: Float32) -> Float32:
    """Return how much of the indirect light reaches a surface, from an
    ambient occlusion map's red channel: three.js's `aomap_fragment`.

    `(texel - 1) * intensity + 1`, so a white texel occludes nothing, a
    black one occludes everything at an intensity of one, and an
    intensity of zero switches the map off. Shared by both rasterizers.

    Args:
        texel: The map's red channel, linear, from zero to one.
        intensity: The material's `ao_map_intensity`.

    Returns:
        The fraction of the indirect light that arrives.
    """
    return (texel - 1) * intensity + 1


def specular_occlusion(
    dot_nv: Float32, occlusion: Float32, roughness: Float32
) -> Float32:
    """Return how much of an environment's reflection reaches the eye
    from an occluded surface: three.js's `computeSpecularOcclusion`,
    after Lagarde and de Rousiers.

    `saturate(pow(dot_nv + occlusion, exp2(-16 * roughness - 1)) - 1 +
    occlusion)`. A surface that faces the eye keeps more of its reflection
    than of its diffuse light, and a smooth one more than a rough one.
    The power is spelled as `exp2` of `log2`, as `blinn_phong` spells it,
    and its base is floored at zero: an intensity above one can make the
    occlusion negative, where GLSL's `pow` is undefined. Shared by both
    rasterizers.

    Args:
        dot_nv: The cosine between the normal and the eye, from zero to one.
        occlusion: What `ambient_occlusion` returned.
        roughness: The floored roughness.

    Returns:
        The fraction of the reflection that arrives, from zero to one.
    """
    var base = max(Float32(0), dot_nv + occlusion)
    var power = exp2(exp2(-16 * roughness - 1) * log2(base))
    return _saturated(power - 1 + occlusion)


def occluded_light(
    arriving: Vector3, indirect: Vector3, baked: Vector3, occlusion: Float32
) -> Vector3:
    """Return a surface's arriving light with its indirect part occluded
    and a light map's baked light added: three.js's `lights_fragment_maps`
    and `aomap_fragment` for a shader that sums its light before the
    surface's color multiplies it.

    `arriving` holds the direct and the indirect light together, as
    `Lighting.intensity_at` and `Lighting.toon_at` return it. The indirect
    part is taken out, the baked light is added to it, and the sum is
    occluded and put back: `arriving - indirect + (indirect + baked) *
    occlusion`. The direct lights are not occluded, as three.js leaves
    `directDiffuse` alone. Shared by both rasterizers.

    Args:
        arriving: The direct and indirect light together, linear.
        indirect: The indirect part of it: `Lighting.indirect_at`.
        baked: The light map's light, already scaled, or zero for none.
        occlusion: What `ambient_occlusion` returned, or one for none.

    Returns:
        The arriving light, linear.
    """
    return Vector3(
        arriving.x - indirect.x + (indirect.x + baked.x) * occlusion,
        arriving.y - indirect.y + (indirect.y + baked.y) * occlusion,
        arriving.z - indirect.z + (indirect.z + baked.z) * occlusion,
    )


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
    # The sum of every light probe's coefficients, each times its
    # intensity, as three.js's `WebGLLights` sums them into `probe`.
    # Darkness when there is no probe.
    var probe: SphericalHarmonics3
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
    # The shadow maps the lights that cast drew this frame, and which of
    # them each directional, each point and each spot light compares
    # against, or -1 for a light that casts none. See `lights.shadow`.
    var shadows: List[ShadowMap]
    var direction_shadows: List[Int]
    var point_shadows: List[Int]
    var spot_shadows: List[Int]
    # The pictures the spot lights project this frame, and which of them
    # each spot light carries, or -1 for none. See `lights.shadow`.
    var spot_maps: List[SpotLightMap]
    var spot_map_slots: List[Int]
    # One entry per rect area light, parallel lists: where its center is,
    # from the center to the middle of a side and of the other side, in
    # world space, and what it carries. Read only by a physical surface;
    # see `lights.ltc`.
    var rect_positions: List[Vector3]
    var rect_half_widths: List[Vector3]
    var rect_half_heights: List[Vector3]
    var rect_radiances: List[FloatColor]
    # The LTC tables a rect area light is evaluated with, or none, which
    # is refused when there is such a light.
    var ltc: LtcTables

    def __init__(
        out self,
        scene: Scene,
        visible: Layers = Layers.all(),
        eye: Vector3 = Vector3(0, 0, 0),
        toward_eye: Vector3 = PERSPECTIVE_VIEW,
        up: Vector3 = Vector3(0, 1, 0),
        var shadows: List[ShadowMap] = List[ShadowMap](),
        var ltc: LtcTables = LtcTables(),
        var spot_maps: List[SpotLightMap] = List[SpotLightMap](),
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
            shadows: The shadow maps drawn this frame, each naming the
                light that drew it; `Renderer.shadow_maps` builds them.
                None by default, which lights every surface in full.
            ltc: The tables a rect area light is evaluated with,
                `lights.ltc.load_ltc_tables`. None by default, which is
                refused only when the scene holds such a light.
            spot_maps: The pictures the spot lights project this frame,
                each naming its light; `Renderer.spot_light_maps` builds
                them. None by default, which leaves every light's color
                as it is.

        Raises:
            Error: If a light's numbers are refused by `Light.validate`,
                whatever layer it is on; a light names a node or a target
                the scene does not have; a directional, hemisphere or spot
                light has no direction, because its node sits exactly
                where it points from — the origin, or its target — which
                is a mistake rather than a dark light; a light's kind
                is none of the seven; a shadow map's type is none of the
                four; a shadow map names a light that
                is not there, or one that is not directional, point or
                spot, or a point light's map is not a cube or another
                light's is; a spot light map names a light that is not
                there or is not a spot light; or the scene holds a rect
                area light and no LTC tables were given.
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
        self.probe = SphericalHarmonics3()
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
        self.shadows = shadows^
        self.direction_shadows = List[Int]()
        self.point_shadows = List[Int]()
        self.spot_shadows = List[Int]()
        self.spot_maps = spot_maps^
        self.spot_map_slots = List[Int]()
        self.rect_positions = List[Vector3]()
        self.rect_half_widths = List[Vector3]()
        self.rect_half_heights = List[Vector3]()
        self.rect_radiances = List[FloatColor]()
        self.ltc = ltc^
        for slot in range(len(self.shadows)):
            var owner = self.shadows[slot].light
            if owner < 0 or owner >= len(scene.lights):
                raise Error("A shadow map names a light that is not there")
            if not self.shadows[slot].shadow_type.is_valid():
                raise Error("A shadow map type that is none of the four")
            var kind = scene.lights[owner].kind
            if kind != DIRECTIONAL and kind != POINT and kind != SPOT:
                raise Error(
                    "A shadow map names a light that cannot cast: only a"
                    " directional, a point or a spot light draws one"
                )
            if self.shadows[slot].cube != (kind == POINT):
                raise Error(
                    "A point light's shadow must be a cube, and only a point"
                    " light's can be"
                )
        for slot in range(len(self.spot_maps)):
            var owner = self.spot_maps[slot].light
            if owner < 0 or owner >= len(scene.lights):
                raise Error("A spot light map names a light that is not there")
            if scene.lights[owner].kind != SPOT:
                raise Error("A spot light map names a light that is not a spot")
        for index in range(len(scene.lights)):
            ref light = scene.lights[index]
            # Asked of every light, on the camera's layers or not: the
            # fields are open, a light in a persistent scene is there to
            # be edited, and a wrong light is a wrong asset rather than a
            # wrong frame.
            light.validate()
            if not light.layers.test(visible):
                continue
            if not scene.light_shown(light):
                continue
            if light.kind == AMBIENT:
                var fill = light.radiance()
                self.ambient = FloatColor(
                    self.ambient.r + fill.r,
                    self.ambient.g + fill.g,
                    self.ambient.b + fill.b,
                    1.0,
                )
            elif light.kind == LIGHT_PROBE:
                # Summed as three.js sums them: each coefficient times the
                # probe's intensity, the color unread.
                self.probe.add_scaled(light.sh, light.intensity)
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
                self.direction_shadows.append(self._shadow_of(index))
            elif light.kind == POINT:
                # Its node's position is the answer itself, and the origin
                # is as good a place for a bulb as any.
                self.positions.append(scene.world_position(light.node))
                self.point_radiances.append(light.radiance())
                self.decays.append(light.decay)
                self.cutoffs.append(light.distance)
                self.point_shadows.append(self._shadow_of(index))
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
                self.spot_shadows.append(self._shadow_of(index))
                self.spot_map_slots.append(self._map_of(index))
                self.cone_cosines.append(cos(light.angle.value))
                self.penumbra_cosines.append(
                    cos(light.angle.value * (1 - light.penumbra))
                )
            elif light.kind == RECT_AREA:
                # The rectangle's center, and its half width and half
                # height turned and scaled by its node's world matrix, as
                # three.js applies `matrixWorld` to `halfWidth` and
                # `halfHeight`: a scaled node makes a larger rectangle.
                if not self.ltc.is_loaded():
                    raise Error(
                        "A rect area light needs the LTC tables: load them"
                        " with lights.ltc.load_ltc_tables and hand them to"
                        " the renderer with set_ltc_tables"
                    )
                var placed = scene.world_matrix(light.node)
                self.rect_positions.append(scene.world_position(light.node))
                self.rect_half_widths.append(
                    placed.transform_direction(
                        Vector3(light.width.to(METER) * 0.5, 0, 0)
                    )
                )
                self.rect_half_heights.append(
                    placed.transform_direction(
                        Vector3(0, light.height.to(METER) * 0.5, 0)
                    )
                )
                self.rect_radiances.append(light.radiance())
            else:
                # The type stops a bare integer; it does not stop
                # `LightKind(7)`, and a light that is none of the seven has
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
        self.probe = SphericalHarmonics3()
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
        self.shadows = List[ShadowMap]()
        self.direction_shadows = List[Int]()
        self.point_shadows = List[Int]()
        self.spot_shadows = List[Int]()
        self.spot_maps = List[SpotLightMap]()
        self.spot_map_slots = List[Int]()
        self.rect_positions = List[Vector3]()
        self.rect_half_widths = List[Vector3]()
        self.rect_half_heights = List[Vector3]()
        self.rect_radiances = List[FloatColor]()
        self.ltc = LtcTables()

    def rect_count(self) -> Int:
        """Return how many rect area lights there are."""
        return len(self.rect_positions)

    def _shadow_of(self, light: Int) -> Int:
        """Return which of the shadow maps `light` drew, or -1 for none."""
        for slot in range(len(self.shadows)):
            if self.shadows[slot].light == light:
                return slot
        return -1

    def _map_of(self, light: Int) -> Int:
        """Return which of the spot light maps `light` projects, or -1."""
        for slot in range(len(self.spot_maps)):
            if self.spot_maps[slot].light == light:
                return slot
        return -1

    def spot_tint(
        self, index: Int, position: Vector3, normal: Vector3
    ) -> Vector3:
        """Return what one spot light's color is multiplied by at a
        surface: its map's color there, three.js's `spotColor`, or one
        for a light that projects none.

        Args:
            index: Which spot light, in the order they were resolved.
            position: Where the surface is, in world space.
            normal: Its unit normal, for the map's normal bias.

        Returns:
            The red, green and blue multipliers, linear.
        """
        var slot = self.spot_map_slots[index]
        if slot < 0:
            return Vector3(1, 1, 1)
        return self.spot_maps[slot].tint(position, normal)

    def shadow_at(
        self, slot: Int, position: Vector3, normal: Vector3, receives: Bool
    ) -> Float32:
        """Return how much of one light reaches a surface, past whatever
        stands between: one for all of it, zero for none.

        Args:
            slot: Which shadow map the light drew, or -1 for none.
            position: Where the surface is, in world space.
            normal: Its unit normal, for the map's normal bias.
            receives: Whether shadows fall on this surface at all,
                three.js's `receiveShadow`. A surface that does not
                receive is lit in full whatever the map says.

        Returns:
            The fraction of the light that arrives.
        """
        if slot < 0 or not receives:
            return 1
        return self.shadows[slot].lit(position, normal)

    def shadow_mask(self, position: Vector3, normal: Vector3) -> Float32:
        """Return how much of every shadowing light reaches a surface, the
        product over the lights that cast: three.js's `getShadowMask`,
        which a `SHADOW` material shows as transparency.

        Args:
            position: Where the surface is, in world space.
            normal: Its unit normal.

        Returns:
            One where no shadow falls, zero where every shadowing light
            is blocked.
        """
        var mask = Float32(1)
        for index in range(len(self.direction_shadows)):
            mask *= self.shadow_at(
                self.direction_shadows[index], position, normal, True
            )
        for index in range(len(self.spot_shadows)):
            mask *= self.shadow_at(
                self.spot_shadows[index], position, normal, True
            )
        for index in range(len(self.point_shadows)):
            mask *= self.shadow_at(
                self.point_shadows[index], position, normal, True
            )
        return mask

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

    def intensity_at(
        self, normal: Vector3, position: Vector3, receives: Bool = True
    ) -> FloatColor:
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
            receives: Whether the lights' shadows fall on this surface;
                see `shadow_at`. A light that casts is scaled by what its
                map lets through, as three.js scales `directLight.color`.

        Returns:
            The arriving light, linear. Alpha is not light and stays at one.
        """
        var total = self.ambient_at(normal)
        for index in range(len(self.directions)):
            var lambert = max(Float32(0), normal.dot(self.directions[index]))
            if lambert == 0:
                continue
            lambert *= self.shadow_at(
                self.direction_shadows[index], position, normal, receives
            )
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
            var reach = (
                lambert
                * falloff(distance, self.decays[index], self.cutoffs[index])
                * self.shadow_at(
                    self.point_shadows[index], position, normal, receives
                )
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
                * self.shadow_at(
                    self.spot_shadows[index], position, normal, receives
                )
            )
            ref bulb = self.spot_radiances[index]
            var tint = self.spot_tint(index, position, normal)
            total = FloatColor(
                total.r + bulb.r * tint.x * reach,
                total.g + bulb.g * tint.y * reach,
                total.b + bulb.b * tint.z * reach,
                1.0,
            )
        return total.scaled(self.scale)

    def toon_at(
        self,
        normal: Vector3,
        position: Vector3,
        ramp: List[Float32],
        receives: Bool = True,
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
            receives: Whether the lights' shadows fall on this surface;
                see `shadow_at`.

        Returns:
            The arriving light, linear. Alpha is not light and stays at one.
        """
        var total = self.ambient_at(normal)
        for index in range(len(self.directions)):
            var tone = toon_tone(
                normal.dot(self.directions[index]), ramp
            ) * self.shadow_at(
                self.direction_shadows[index], position, normal, receives
            )
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
            var reach = (
                tone
                * falloff(distance, self.decays[index], self.cutoffs[index])
                * self.shadow_at(
                    self.point_shadows[index], position, normal, receives
                )
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
                * self.shadow_at(
                    self.spot_shadows[index], position, normal, receives
                )
            )
            ref bulb = self.spot_radiances[index]
            var tint = self.spot_tint(index, position, normal)
            total = FloatColor(
                total.r + bulb.r * tint.x * reach,
                total.g + bulb.g * tint.y * reach,
                total.b + bulb.b * tint.z * reach,
                1.0,
            )
        return total.scaled(self.scale)

    def specular_at(
        self,
        normal: Vector3,
        position: Vector3,
        specular: Vector3,
        shininess: Float32,
        receives: Bool = True,
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
            receives: Whether the lights' shadows fall on this surface;
                see `shadow_at`.

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
            lambert *= self.shadow_at(
                self.direction_shadows[index], position, normal, receives
            )
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
            var reach = (
                lambert
                * falloff(distance, self.decays[index], self.cutoffs[index])
                * self.shadow_at(
                    self.point_shadows[index], position, normal, receives
                )
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
                * self.shadow_at(
                    self.spot_shadows[index], position, normal, receives
                )
            )
            toward.normalize()
            var sent = blinn_phong(
                toward, toward_eye, normal, specular, shininess
            )
            ref bulb = self.spot_radiances[index]
            var tint = self.spot_tint(index, position, normal)
            red += bulb.r * tint.x * reach * sent.x
            green += bulb.g * tint.y * reach * sent.y
            blue += bulb.b * tint.z * reach * sent.z
        return FloatColor(red, green, blue, 1.0).scaled(self.scale)

    def ambient_at(self, normal: Vector3) -> FloatColor:
        """Return the ambient term and the light probes' irradiance at a
        normal, before the scale: three.js's `getAmbientLightIrradiance`
        plus `getLightProbeIrradiance`.

        The first thing each sum here starts from, and the kernel's
        `_ambient_at` starts from the same numbers: the probes' nine terms
        summed in index order by `SphericalHarmonics3.get_irradiance_at`,
        then added to the ambient color.

        Args:
            normal: The surface's unit normal, in world space.

        Returns:
            The light, linear and unscaled. Alpha is one.
        """
        var lift = self.probe.get_irradiance_at(normal)
        return FloatColor(
            self.ambient.r + lift.x,
            self.ambient.g + lift.y,
            self.ambient.b + lift.z,
            1.0,
        )

    def indirect_at(self, normal: Vector3) -> FloatColor:
        """Return the light with no direction reaching a surface here: the
        ambient term, the light probes and the hemisphere lights, three.js's
        `irradiance` in `lights_fragment_begin`.

        The half of `intensity_at` that a physical surface scatters through
        its diffuse color alone: three.js's `RE_IndirectDiffuse_Physical`.
        The lights with a direction go through `physical_at` instead, where
        they make a lobe as well. Summed in the order `intensity_at` sums
        the same kinds, and scaled once, as there.

        Args:
            normal: The surface's unit normal, in world space.

        Returns:
            The arriving light, linear. Alpha is not light and stays at one.
        """
        var total = self.ambient_at(normal)
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
        receives: Bool = True,
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
            receives: Whether the lights' shadows fall on this surface;
                see `shadow_at`.

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
            var through = self.shadow_at(
                self.direction_shadows[index], position, normal, receives
            )
            sum = physical_light(
                sum,
                Vector3(
                    light.r * through, light.g * through, light.b * through
                ),
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
            ) * self.shadow_at(
                self.point_shadows[index], position, normal, receives
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
            var reach = (
                rim
                * falloff(
                    distance, self.spot_decays[index], self.spot_cutoffs[index]
                )
                * self.shadow_at(
                    self.spot_shadows[index], position, normal, receives
                )
            )
            toward.normalize()
            ref bulb = self.spot_radiances[index]
            var tint = self.spot_tint(index, position, normal)
            sum = physical_light(
                sum,
                Vector3(
                    bulb.r * tint.x * reach,
                    bulb.g * tint.y * reach,
                    bulb.b * tint.z * reach,
                ),
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
        var scaled = Reflected(
            sum.diffuse * self.scale,
            sum.specular * self.scale,
            sum.clearcoat * self.scale,
        )
        # The rectangles, after the scale: their form factor integrates
        # the cosine over the light's outline and carries no reciprocal
        # pi, as three.js's `RE_Direct_RectArea_Physical` carries none.
        # The tables are looked up once per fragment, by the roughness
        # and the angle to the eye, and serve every rectangle.
        if len(self.rect_positions) > 0:
            var dot_nv = max(
                Float32(0), min(Float32(1), normal.dot(toward_eye))
            )
            var uv = ltc_uv(dot_nv, roughness)
            var minv = ltc_lookup(self.ltc.first, uv)
            var fresnel = ltc_lookup(self.ltc.second, uv)
            var diffuse = scaled.diffuse
            var specular = scaled.specular
            for index in range(len(self.rect_positions)):  # pragma: no branch
                var added = rect_area_light(
                    normal,
                    toward_eye,
                    position,
                    self.rect_positions[index],
                    self.rect_half_widths[index],
                    self.rect_half_heights[index],
                    surface.diffuse,
                    surface.specular,
                    minv,
                    fresnel,
                )
                ref glow = self.rect_radiances[index]
                diffuse = Vector3(
                    diffuse.x + added.diffuse.x * glow.r,
                    diffuse.y + added.diffuse.y * glow.g,
                    diffuse.z + added.diffuse.z * glow.b,
                )
                specular = Vector3(
                    specular.x + added.specular.x * glow.r,
                    specular.y + added.specular.y * glow.g,
                    specular.z + added.specular.z * glow.b,
                )
            scaled = Reflected(diffuse, specular, scaled.clearcoat)
        return scaled

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
