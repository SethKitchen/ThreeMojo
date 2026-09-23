# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The three layers a `PHYSICAL` surface adds to its GGX lobe: sheen,
iridescence and anisotropy, from three.js
`src/renderers/shaders/ShaderChunk/lights_physical_pars_fragment.glsl.js`,
`iridescence_fragment.glsl.js` and `lights_physical_fragment.glsl.js`.

**Sheen** is a second lobe for cloth and velvet: the Charlie distribution
of Estevez and Kulla with Neubelt's visibility term, tinted by the sheen
color. Its fitted hemispherical integral lights it from the environment,
and the layer under it is dimmed by three.js's albedo scaling, one minus
0.157 times the brightest channel of the sheen color.

**Iridescence** is a thin film over the surface. Belcour and Barla's
Fresnel term for a film of some thickness and index replaces Schlick's,
weighted by how much film there is. It depends on the angle to the eye
and not on the light, so it is worked out once per fragment.

**Anisotropy** stretches the GGX lobe along one direction of the surface:
Kulla and Conty's anisotropic distribution and visibility, along a
tangent turned by the material's rotation and a map. The environment is
read along a normal bent toward that direction, as Filament bends it.

`layers_of` resolves all three for one fragment into a `PhysicalLayers`, and
`lights.lighting` reads it in `ggx`, `physical_light` and
`physical_outgoing`. Both rasterizers call these functions, so the kernel
and the host form every product in one order.

three.js divides the Charlie distribution by pi, and this drops that
factor for the reason `lights.lighting.blinn_phong` drops it: the lit sum
is scaled by `Lighting.scale` once, at the end.
"""

from math.smoothstep import smoothstep
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import cos, exp, exp2, log2, max, min, pi, sqrt

# The smallest sheen roughness three.js lets the Charlie lobe see:
# `clamp( sheenRoughness, 0.07, 1.0 )` in `lights_physical_fragment`.
comptime SHEEN_ROUGHNESS_FLOOR = Float32(0.07)
# What the brightest channel of the sheen color takes from the layer
# under it: three.js's `sheenEnergyComp = 1.0 - 0.157 * max3( sheenColor )`.
comptime SHEEN_ALBEDO_LOSS = Float32(0.157)
# Where the Charlie distribution's sine squared is held off zero: three.js's
# `0.0078125`, two to the minus seven.
comptime SHEEN_SINE_FLOOR = Float32(0.0078125)
# The index of refraction of what lies over the film: air, three.js's
# `evalIridescence( 1.0, ... )`.
comptime OUTSIDE_IOR = Float32(1)
# What a triangle with no anisotropy map reads in its place: a direction
# of one along the tangent at full strength, which turns the material's
# own vector by nothing and scales it by one, exactly. See `layers_of`.
comptime NO_ANISOTROPY_TEXEL = Vector3(1, 0.5, 1)
# The two numbers in three.js's `F_Schlick`, as `lights.lighting` holds
# them. Held here as well, because that module imports this one.
comptime _FRESNEL_SLOPE = Float32(-5.55473)
comptime _FRESNEL_OFFSET = Float32(-6.98316)


def _saturated(value: Float32) -> Float32:
    """Return `value` clamped to zero through one: GLSL's `saturate`."""
    return max(Float32(0), min(Float32(1), value))


def _schlick(f0: Float32, f90: Float32, cosine: Float32) -> Float32:
    """Return three.js's scalar `F_Schlick`, spelled as `f_schlick` is."""
    var fresnel = exp2((_FRESNEL_SLOPE * cosine + _FRESNEL_OFFSET) * cosine)
    return f0 * (1 - fresnel) + f90 * fresnel


@fieldwise_init
struct PhysicalLayers(ImplicitlyCopyable):
    """What a fragment's sheen, iridescence and anisotropy come to, once
    their maps have been read: three.js's `PhysicalMaterial` fields of the
    same names, as `lights_physical_fragment` leaves them.

    `PhysicalLayers()` has none of the three, and `ggx`, `physical_light` and
    `physical_outgoing` then compute what they computed before any layer
    existed, bit for bit.
    """

    # Whether a sheen lobe is added: the sheen color is not black.
    var sheen: Bool
    # The sheen color, linear, times its map, and the sheen roughness,
    # floored and times its map.
    var sheen_color: Vector3
    var sheen_roughness: Float32
    # How much film there is, from zero to one, and its Fresnel term,
    # three.js's `iridescence` and `iridescenceFresnel`. Zero film leaves
    # the Fresnel term unread.
    var iridescence: Float32
    var iridescence_fresnel: Vector3
    # Whether the lobe is anisotropic at all, three.js's `USE_ANISOTROPY`,
    # and how strongly, from zero to one.
    var anisotropic: Bool
    var anisotropy: Float32
    # The directions the lobe is stretched along and across, three.js's
    # `anisotropyT` and `anisotropyB`, and the roughness squared along the
    # stretch, three.js's `alphaT`.
    var tangent: Vector3
    var bitangent: Vector3
    var alpha_t: Float32

    def __init__(out self):
        """Describe a fragment with no sheen, no film and no stretch."""
        self.sheen = False
        self.sheen_color = Vector3(0, 0, 0)
        self.sheen_roughness = 1
        self.iridescence = 0
        self.iridescence_fresnel = Vector3(0, 0, 0)
        self.anisotropic = False
        self.anisotropy = 0
        self.tangent = Vector3(0, 0, 0)
        self.bitangent = Vector3(0, 0, 0)
        self.alpha_t = 0


def charlie_sheen(
    toward_light: Vector3,
    toward_eye: Vector3,
    normal: Vector3,
    color: Vector3,
    roughness: Float32,
) -> Vector3:
    """Return the fraction of light a sheen sends from one direction toward
    another: three.js's `BRDF_Sheen`, without its reciprocal pi.

    `D_Charlie` times `V_Neubelt`, times the sheen color. The distribution
    raises the sine squared of the half angle to half the reciprocal of
    alpha, the roughness squared, and spells that power as `exp2` of
    `log2`, as `blinn_phong` does. The sine squared is held off zero, as
    three.js holds it, so the logarithm is finite.

    **A roughness of zero reflects nothing here.** three.js divides by
    it. As the roughness falls toward zero the distribution falls to zero
    everywhere but on the horizon, so zero is its limit. Only a sheen
    roughness map can reach zero: the material's own number is floored.

    Args:
        toward_light: Unit vector from the surface toward the light.
        toward_eye: Unit vector from the surface toward the camera.
        normal: The surface's unit normal.
        color: The sheen color, linear.
        roughness: The sheen roughness, from zero to one.

    Returns:
        The reflected fraction per channel.
    """
    var alpha = roughness * roughness
    var half = toward_light + toward_eye
    if alpha == 0 or half.length() == 0:
        return Vector3(0, 0, 0)
    half.normalize()
    var dot_nl = _saturated(normal.dot(toward_light))
    var dot_nv = _saturated(normal.dot(toward_eye))
    var dot_nh = _saturated(normal.dot(half))
    var inverse = 1 / alpha
    var sin2h = max(1 - dot_nh * dot_nh, SHEEN_SINE_FLOOR)
    # three.js's D_Charlie, without its reciprocal pi.
    var lobe = (2 + inverse) * exp2(log2(sin2h) * inverse * 0.5) / 2
    # three.js's V_Neubelt. The sum is zero only when both cosines are,
    # and then GLSL's saturate of an infinity is one.
    var denominator = 4 * (dot_nl + dot_nv - dot_nl * dot_nv)
    var visibility = Float32(1)
    if denominator > 0:
        visibility = _saturated(1 / denominator)
    return color * (lobe * visibility)


def ibl_sheen(dot_nv: Float32, roughness: Float32) -> Float32:
    """Return how much of the environment a sheen sends toward the eye:
    three.js's `IBLSheenBRDF`, a curve fitted to the Charlie lobe's
    integral over the hemisphere.

    Two exponentials, one for a roughness below a quarter and one above,
    with its reciprocal pi inside the clamp, as three.js has it.

    Args:
        dot_nv: The cosine between the normal and the eye, from zero to one.
        roughness: The sheen roughness, from zero to one.

    Returns:
        The fraction, from zero to one.
    """
    var r2 = roughness * roughness
    var a = -8.48 * r2 + 14.3 * roughness - 9.95
    var b = 1.97 * r2 - 3.27 * roughness + 0.72
    var rise = 0.1 * (roughness - 0.25)
    if roughness < 0.25:
        a = -339.2 * r2 + 161.4 * roughness - 25.9
        b = 44.0 * r2 - 23.7 * roughness + 3.26
        rise = 0
    var dg = exp(a * dot_nv + b) + rise
    return _saturated(dg * (1 / Float32(pi)))


def sheen_scaling(color: Vector3) -> Float32:
    """Return what a sheen leaves of the light under it: three.js's
    `sheenEnergyComp`, one minus 0.157 times the brightest channel.

    Args:
        color: The sheen color, linear.

    Returns:
        The factor the layer under the sheen is multiplied by.
    """
    return 1 - SHEEN_ALBEDO_LOSS * max(max(color.x, color.y), color.z)


def sheen_roughness_of(authored: Float32, texel: Float32) -> Float32:
    """Return the sheen roughness a fragment sees: the material's, clamped
    to `SHEEN_ROUGHNESS_FLOOR` through one, times its map's *alpha*, as
    `lights_physical_fragment` works it out.

    Args:
        authored: The material's sheen roughness.
        texel: The sheen roughness map's alpha, or one for none.

    Returns:
        The sheen roughness.
    """
    return min(max(authored, SHEEN_ROUGHNESS_FLOOR), Float32(1)) * texel


def iridescence_thickness(
    minimum: Float32, maximum: Float32, texel: Float32, mapped: Bool
) -> Float32:
    """Return how thick the film is at a fragment, in nanometers: three.js's
    `iridescenceThickness`.

    With a thickness map, its *green* channel mixes the range's two ends.
    Without one, the film is the range's maximum, as three.js takes it.

    Args:
        minimum: The thickness at a texel of zero, in nanometers.
        maximum: The thickness at a texel of one, in nanometers.
        texel: The thickness map's green channel. Read only when `mapped`.
        mapped: Whether the triangle names a thickness map.

    Returns:
        The thickness, in nanometers.
    """
    if mapped:
        return (maximum - minimum) * texel + minimum
    return maximum


def _sensitivity(opd: Float32, shift: Vector3) -> Vector3:
    """Return three.js's `evalSensitivity`: the eye's response to a phase
    difference, as a linear sRGB color, from a Gaussian fit to the CIE
    curves in Fourier space."""
    var phase = 2 * Float32(pi) * opd * 1.0e-9
    var phase2 = phase * phase
    var x = (
        Float32(5.4856e-13)
        * sqrt(2 * Float32(pi) * Float32(4.3278e09))
        * cos(Float32(1.6810e06) * phase + shift.x)
        * exp(-phase2 * Float32(4.3278e09))
    )
    var y = (
        Float32(4.4201e-13)
        * sqrt(2 * Float32(pi) * Float32(9.3046e09))
        * cos(Float32(1.7953e06) * phase + shift.y)
        * exp(-phase2 * Float32(9.3046e09))
    )
    var z = (
        Float32(5.2481e-13)
        * sqrt(2 * Float32(pi) * Float32(6.6121e09))
        * cos(Float32(2.2084e06) * phase + shift.z)
        * exp(-phase2 * Float32(6.6121e09))
    )
    x += (
        Float32(9.7470e-14)
        * sqrt(2 * Float32(pi) * Float32(4.5282e09))
        * cos(Float32(2.2399e06) * phase + shift.x)
        * exp(-Float32(4.5282e09) * phase2)
    )
    x /= Float32(1.0685e-7)
    y /= Float32(1.0685e-7)
    z /= Float32(1.0685e-7)
    # three.js's XYZ_TO_REC709, read by rows.
    return Vector3(
        Float32(3.2404542) * x
        + Float32(-1.5371385) * y
        + Float32(-0.4985314) * z,
        Float32(-0.9692660) * x
        + Float32(1.8760108) * y
        + Float32(0.0415560) * z,
        Float32(0.0556434) * x
        + Float32(-0.2040259) * y
        + Float32(1.0572252) * z,
    )


def _base_ior(f0: Float32) -> Float32:
    """Return the index of refraction a head-on reflectance means, against
    air: three.js's `Fresnel0ToIor`, with the reflectance held below one."""
    var root = sqrt(min(max(f0, Float32(0)), Float32(0.9999)))
    return (1 + root) / (1 - root)


def _to_f0(transmitted: Float32, incident: Float32) -> Float32:
    """Return the head-on reflectance of an interface: three.js's
    `IorToFresnel0`."""
    var ratio = (transmitted - incident) / (transmitted + incident)
    return ratio * ratio


def iridescence_fresnel(
    outside_ior: Float32,
    film_ior: Float32,
    cos_theta1: Float32,
    thickness: Float32,
    base_f0: Vector3,
) -> Vector3:
    """Return how much a surface under a thin film reflects toward the
    eye: three.js's `evalIridescence`, after Belcour and Barla.

    Light reflects off the film's top and off the surface under it, and
    the two interfere by how far apart they are in phase. The first two
    orders of that interference are summed and turned from the eye's
    response into color. A film that thins to nothing takes on the
    outside's index, so a thickness of zero adds no color, and total
    internal reflection reflects everything.

    Args:
        outside_ior: The index of refraction over the film: one, air.
        film_ior: The film's own index, three.js's `iridescenceIOR`.
        cos_theta1: The cosine between the normal and the eye, from zero
            to one.
        thickness: How thick the film is, in nanometers.
        base_f0: What the surface under the film reflects head on, per
            channel, three.js's `specularColor`.

    Returns:
        The reflectance per channel, never below zero.
    """
    var ior = outside_ior + (film_ior - outside_ior) * smoothstep(
        0, 0.03, thickness
    )
    var ratio = outside_ior / ior
    var sin_theta2_sq = ratio * ratio * (1 - cos_theta1 * cos_theta1)
    var cos_theta2_sq = 1 - sin_theta2_sq
    if cos_theta2_sq < 0:
        return Vector3(1, 1, 1)
    var cos_theta2 = sqrt(cos_theta2_sq)
    # The first interface, from the outside into the film.
    var r12 = _schlick(_to_f0(ior, outside_ior), 1, cos_theta1)
    var t121 = 1 - r12
    var phi12 = Float32(0)
    if ior < outside_ior:
        phi12 = Float32(pi)
    var phi21 = Float32(pi) - phi12
    # The second, from the film into the surface, per channel.
    var base_x = _base_ior(base_f0.x)
    var base_y = _base_ior(base_f0.y)
    var base_z = _base_ior(base_f0.z)
    var r23 = Vector3(
        _schlick(_to_f0(base_x, ior), 1, cos_theta2),
        _schlick(_to_f0(base_y, ior), 1, cos_theta2),
        _schlick(_to_f0(base_z, ior), 1, cos_theta2),
    )
    var phi = Vector3(
        phi21 + (Float32(pi) if base_x < ior else 0),
        phi21 + (Float32(pi) if base_y < ior else 0),
        phi21 + (Float32(pi) if base_z < ior else 0),
    )
    # The phase difference one trip through the film makes.
    var opd = 2 * ior * thickness * cos_theta2
    var r123 = Vector3(
        min(max(r12 * r23.x, Float32(1e-5)), Float32(0.9999)),
        min(max(r12 * r23.y, Float32(1e-5)), Float32(0.9999)),
        min(max(r12 * r23.z, Float32(1e-5)), Float32(0.9999)),
    )
    var root = Vector3(sqrt(r123.x), sqrt(r123.y), sqrt(r123.z))
    var through = t121 * t121
    var rs = Vector3(
        through * r23.x / (1 - r123.x),
        through * r23.y / (1 - r123.y),
        through * r23.z / (1 - r123.z),
    )
    # The order zero term, and then the first two orders of interference.
    var total = Vector3(r12 + rs.x, r12 + rs.y, r12 + rs.z)
    var cm = Vector3(rs.x - t121, rs.y - t121, rs.z - t121)
    # Two orders, always, so the loop never runs zero times.
    for order in range(1, 3):  # pragma: no branch
        cm = Vector3(cm.x * root.x, cm.y * root.y, cm.z * root.z)
        var sm = _sensitivity(Float32(order) * opd, phi * Float32(order))
        total = Vector3(
            total.x + cm.x * 2 * sm.x,
            total.y + cm.y * 2 * sm.y,
            total.z + cm.z * 2 * sm.z,
        )
    return Vector3(
        max(total.x, Float32(0)),
        max(total.y, Float32(0)),
        max(total.z, Float32(0)),
    )


def anisotropic_ggx(
    toward_light: Vector3,
    toward_eye: Vector3,
    half: Vector3,
    dot_nl: Float32,
    dot_nv: Float32,
    dot_nh: Float32,
    alpha: Float32,
    layers: PhysicalLayers,
) -> Float32:
    """Return the visibility times the distribution of a stretched GGX
    lobe: three.js's `V_GGX_SmithCorrelated_Anisotropic` times
    `D_GGX_Anisotropic`, without the latter's reciprocal pi.

    Args:
        toward_light: Unit vector from the surface toward the light.
        toward_eye: Unit vector from the surface toward the camera.
        half: The unit half vector between the two.
        dot_nl: The cosine between the normal and the light, above zero.
        dot_nv: The cosine between the normal and the eye, above zero.
        dot_nh: The cosine between the normal and the half vector.
        alpha: The roughness squared across the stretch, three.js's
            `alphaB`.
        layers: The fragment's stretch: its tangent, bitangent and
            `alpha_t`.

    Returns:
        The product, which `ggx` multiplies the Fresnel term by.
    """
    var alpha_t = layers.alpha_t
    var dot_tl = layers.tangent.dot(toward_light)
    var dot_tv = layers.tangent.dot(toward_eye)
    var dot_th = layers.tangent.dot(half)
    var dot_bl = layers.bitangent.dot(toward_light)
    var dot_bv = layers.bitangent.dot(toward_eye)
    var dot_bh = layers.bitangent.dot(half)
    var gv = dot_nl * Vector3(alpha_t * dot_tv, alpha * dot_bv, dot_nv).length()
    var gl = dot_nv * Vector3(alpha_t * dot_tl, alpha * dot_bl, dot_nl).length()
    var visibility = _saturated(0.5 / (gv + gl))
    var a2 = alpha_t * alpha
    var v = Vector3(alpha * dot_th, alpha_t * dot_bh, a2 * dot_nh)
    var w2 = a2 / v.dot(v)
    return visibility * (a2 * w2 * w2)


def bent_normal(
    normal: Vector3,
    toward_eye: Vector3,
    layers: PhysicalLayers,
    roughness: Float32,
) -> Vector3:
    """Return the normal an anisotropic surface reads its environment
    along: three.js's `getIBLAnisotropyRadiance`, after Filament.

    The normal is bent toward the plane the stretch and the eye span, and
    back toward the true normal as the stretch weakens or the surface
    smooths. A surface with no stretch reads along its own normal.

    **Where three.js normalizes a zero vector, this leaves it zero.**
    When the eye looks straight along the stretch there is no plane to
    bend toward, and GLSL's `normalize` of zero is undefined. Here the
    plane's direction stays zero, so the normal alone is left, since the
    floored roughness keeps its weight above zero.

    Args:
        normal: The surface's unit normal.
        toward_eye: Unit vector from the surface toward the camera.
        layers: The fragment's stretch.
        roughness: The floored roughness.

    Returns:
        The unit normal to read the environment along.
    """
    if not layers.anisotropic:
        return normal
    var across = layers.bitangent
    across.cross(toward_eye)
    across.cross(layers.bitangent)
    across.normalize()
    var fade = 1 - layers.anisotropy * (1 - roughness)
    fade = fade * fade
    fade = fade * fade
    var bent = Vector3(
        across.x + (normal.x - across.x) * fade,
        across.y + (normal.y - across.y) * fade,
        across.z + (normal.z - across.z) * fade,
    )
    bent.normalize()
    return bent


def layers_of(
    sheen_color: Vector3,
    sheen_roughness: Float32,
    iridescence: Float32,
    iridescence_ior: Float32,
    thickness: Float32,
    anisotropy: Vector2,
    anisotropy_texel: Vector3,
    tangent: Vector3,
    bitangent: Vector3,
    normal: Vector3,
    toward_eye: Vector3,
    specular: Vector3,
    roughness: Float32,
) -> PhysicalLayers:
    """Return a fragment's sheen, film and stretch, from the material's
    numbers times its maps: the end of three.js's
    `lights_physical_fragment`.

    The film's Fresnel term is worked out here, once, from the angle to
    the eye: a film with no thickness is no film. The stretch is the
    material's vector, three.js's `anisotropyVector`, turned and scaled by
    the anisotropy map's texel: its red and green unpacked to a direction,
    its blue a strength. `NO_ANISOTROPY_TEXEL` leaves the vector as it
    is. The strength is the vector's length, and the direction it points
    in is laid along the tangent frame.

    Args:
        sheen_color: The sheen color, linear, times the sheen, times the
            sheen color map.
        sheen_roughness: From `sheen_roughness_of`.
        iridescence: How much film there is, times the iridescence map.
        iridescence_ior: The film's index of refraction.
        thickness: From `iridescence_thickness`, in nanometers.
        anisotropy: The material's strength along its rotation, as a
            vector. Zero is no stretch at all.
        anisotropy_texel: The anisotropy map's texel, linear, or
            `NO_ANISOTROPY_TEXEL`.
        tangent: The tangent frame's first column, three.js's `tbn[0]`:
            where `u` grows. Read only with a stretch.
        bitangent: Its second, `tbn[1]`: where `v` grows.
        normal: The surface's unit normal, after any map.
        toward_eye: Unit vector from the surface toward the camera.
        specular: The surface's reflectance head on, after the metalness:
            `physical_surface`'s `specular`.
        roughness: The floored roughness.

    Returns:
        The fragment's layers.
    """
    var layers = PhysicalLayers()
    layers.sheen_color = sheen_color
    layers.sheen_roughness = sheen_roughness
    layers.sheen = max(max(sheen_color.x, sheen_color.y), sheen_color.z) > 0
    if thickness > 0:
        layers.iridescence = _saturated(iridescence)
    if layers.iridescence > 0:
        var dot_nv = _saturated(normal.dot(toward_eye))
        layers.iridescence_fresnel = iridescence_fresnel(
            OUTSIDE_IOR, iridescence_ior, dot_nv, thickness, specular
        )
    layers.anisotropic = anisotropy.x != 0 or anisotropy.y != 0
    if layers.anisotropic:
        # three.js's `mat2( x, y, -y, x ) * normalize( 2 rg - 1 ) * b`.
        var polar = Vector2(
            anisotropy_texel.x * 2 - 1, anisotropy_texel.y * 2 - 1
        )
        polar.normalize()
        var direction = Vector2(
            (anisotropy.x * polar.x - anisotropy.y * polar.y)
            * anisotropy_texel.z,
            (anisotropy.y * polar.x + anisotropy.x * polar.y)
            * anisotropy_texel.z,
        )
        var strength = direction.length()
        if strength == 0:
            direction = Vector2(1, 0)
        else:
            direction = Vector2(direction.x / strength, direction.y / strength)
            strength = _saturated(strength)
        layers.anisotropy = strength
        var alpha = roughness * roughness
        var weight = strength * strength
        layers.alpha_t = alpha * (1 - weight) + weight
        layers.tangent = tangent * direction.x + bitangent * direction.y
        layers.bitangent = bitangent * direction.x - tangent * direction.y
    return layers
