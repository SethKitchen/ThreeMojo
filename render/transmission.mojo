# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a transmissive physical surface shows through itself, from three.js's
`transmission_pars_fragment`.

three.js draws a transmissive surface in two passes. First the renderer draws
every opaque object into a render target of its own, three.js's
`transmissionRenderTarget`, and builds that target's mip chain. Then a
transmissive fragment follows the refracted ray through a slab as thick as the
material says, projects where the ray leaves onto that target, and reads it
there, blurred by a level of the chain its roughness picks
(`getIBLVolumeRefraction`). The light is dimmed by Beer's law along the way
(`volumeAttenuation`), and with dispersion each channel is refracted at its own
index (`USE_DISPERSION`).

`TransmissionTarget` is that target: the opaque scene as a mipmapped float
texture, and the matrix that takes a world position to a place on it.
`Renderer.render_into` fills one before it draws a frame that transmits, and
both rasterizers read it through `volume_refraction`, which is written once,
here, over any `TransmissionSource`. The host's source is the texture itself
and the kernel's is the device's copy of it, so the two backends run the same
arithmetic in the same order.

**Where this differs from three.js.** The target is the renderer's own size
and the matrix maps onto the viewport's part of it, where three.js sizes the
target to the viewport. With the viewport the whole target, as it is by
default, the two agree. A lookup past the chain's last level reads the last
level, where WebGL leaves `textureSize` of a level that is not there
undefined. A ray that travels no distance is not dimmed at all, where
three.js's Beer's law divides zero by zero for a black attenuation color.
"""

from lights.lighting import environment_brdf
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from render.target import RenderTarget
from render.texture import BILINEAR, CLAMP, COVERAGE, Texture, float_texture
from std.math import exp, floor, isinf, log, log2, max, min, sqrt

# How far apart dispersion spreads the three channels' indices, per unit of
# `dispersion` and per unit of the index above one: three.js's `0.025` in
# `getIBLVolumeRefraction`.
comptime DISPERSION_SPREAD = Float32(0.025)
# How many floats the world-to-target matrix takes: sixteen, column-major,
# as `Matrix4` holds them.
comptime VIEW_FLOATS = 16


trait TransmissionSource:
    """Where the opaque scene is read: the host's texture, or the kernel's
    copy of it. `volume_refraction` asks these three things and nothing
    else, so both backends run the one function."""

    def level_count(self) -> Int:
        """Return how many images the chain holds, at least one.

        Returns:
            The level count.
        """
        ...

    def level_size(self, level: Int) -> Vector2:
        """Return the size of one level of the chain.

        Args:
            level: A level the chain holds.

        Returns:
            The width and the height in texels.
        """
        ...

    def fetch_level(self, u: Float32, v: Float32, level: Int) -> FloatColor:
        """Return the color at a coordinate on one level, filtered
        bilinearly and clamped at the edges.

        Args:
            u: Across, from zero at the left edge.
            v: Up, from zero at the bottom edge.
            level: A level the chain holds.

        Returns:
            The color, straight alpha.
        """
        ...


struct HostSource[origin: Origin[mut=False]](TransmissionSource):
    """The host's `TransmissionSource`: a borrowed texture."""

    var image: Pointer[Texture, Self.origin]

    def __init__(out self, image: Pointer[Texture, Self.origin]):
        """Borrow a texture for as long as the caller keeps it.

        Args:
            image: The chain to read.
        """
        self.image = image

    def level_count(self) -> Int:
        """Return how many images the texture's chain holds.

        Returns:
            The level count.
        """
        return self.image[].levels

    def level_size(self, level: Int) -> Vector2:
        """Return the size of one level, as `Texture.level_width` and
        `Texture.level_height` give it.

        Args:
            level: A level the chain holds.

        Returns:
            The width and the height in texels.
        """
        return Vector2(
            Float32(self.image[].level_width(level)),
            Float32(self.image[].level_height(level)),
        )

    def fetch_level(self, u: Float32, v: Float32, level: Int) -> FloatColor:
        """Return the texture's bilinear sample on one level.

        Args:
            u: Across, from zero at the left edge.
            v: Up, from zero at the bottom edge.
            level: A level the chain holds.

        Returns:
            The color, straight alpha.
        """
        return self.image[]._sample_at(
            u, v, level, self.image[].filter_at(level)
        )


struct TransmissionTarget(Movable):
    """The opaque scene a transmissive surface looks through: three.js's
    `transmissionRenderTarget` with its mip chain, and where on it a world
    position lands.

    Empty until built from a `RenderTarget`, and an empty one is what a
    frame with nothing transmissive passes. A frame that transmits and
    passes an empty one is refused by `check_transmission`.
    """

    # The opaque scene as linear floats, straight alpha, clamped, bilinear
    # and mipmapped: three.js's `HalfFloatType` target with
    # `LinearMipmapLinearFilter`. The blank texture when empty.
    var image: Texture
    # World position to target coordinate, column-major, `u` across from
    # the left and `v` up from the bottom, divided by the fourth row as a
    # projection is: three.js's `projectionMatrix * viewMatrix` followed by
    # its `* 0.5 + 0.5`.
    var view: SIMD[DType.float32, VIEW_FLOATS]

    def __init__(out self):
        """Create an empty target, for a frame with nothing transmissive."""
        self.image = Texture()
        self.view = SIMD[DType.float32, VIEW_FLOATS](0)

    def __init__(out self, target: RenderTarget, view: Matrix4) raises:
        """Capture what `target` holds, and build its chain.

        Args:
            target: The opaque scene, drawn. Its colors are unpremultiplied
                into the texture, so a pixel nothing covered keeps the
                clear color's alpha.
            view: The transform from a world position to a coordinate on
                the target: `u` from zero at the left edge to one at the
                right, `v` from zero at the bottom to one at the top.

        Raises:
            Error: If a pixel holds light that is not finite, which no
                filter of the chain could average.
        """
        var data = List[Float32](capacity=target.width * target.height * 4)
        for slot in range(len(target.colors)):  # pragma: no branch
            var straight = target.straight_at(slot)
            data.append(straight.r)
            data.append(straight.g)
            data.append(straight.b)
            data.append(straight.a)
        self.image = float_texture(
            target.width,
            target.height,
            data^,
            CLAMP,
            BILINEAR,
            True,
            COVERAGE,
        )
        self.view = SIMD[DType.float32, VIEW_FLOATS](0)
        for index in range(VIEW_FLOATS):  # pragma: no branch
            self.view[index] = view.elements[index]

    def is_ready(self) -> Bool:
        """Return True if this target holds a scene to look through."""
        return not self.image.is_blank()


def refracted(incident: Vector3, normal: Vector3, eta: Float32) -> Vector3:
    """Return the direction light bends into across a surface: GLSL's
    `refract`.

    Args:
        incident: The unit direction the light travels in.
        normal: The surface's unit normal, facing the light.
        eta: The ratio of the two indices, outside over inside.

    Returns:
        The refracted direction, or zero where the light is totally
        reflected. `eta` at or below one, as three.js passes it, never
        reflects totally.
    """
    var cosine = normal.dot(incident)
    var k = 1 - eta * eta * (1 - cosine * cosine)
    if k < 0:
        return Vector3(0, 0, 0)
    var along = eta * cosine + sqrt(k)
    return Vector3(
        incident.x * eta - normal.x * along,
        incident.y * eta - normal.y * along,
        incident.z * eta - normal.z * along,
    )


def transmission_ray(
    normal: Vector3, toward_eye: Vector3, thickness: Vector3, ior: Float32
) -> Vector3:
    """Return the path the light takes through the slab: three.js's
    `getVolumeTransmissionRay`.

    The view refracted at `1 / ior`, made a unit vector, and scaled per
    axis by the thickness times the model's scale.

    Args:
        normal: The surface's unit normal, in world space.
        toward_eye: The unit vector from the surface to the camera.
        thickness: The material's thickness, times any map, times the
            length of each of the model matrix's three axes: three.js's
            `thickness * modelScale`.
        ior: The index the light is refracted at.

    Returns:
        The ray from the surface to where the light leaves, in world
        space. Zero if no light is refracted.
    """
    var bent = refracted(-toward_eye, normal, 1 / ior)
    var length = bent.length()
    if length == 0:
        return Vector3(0, 0, 0)
    return Vector3(
        bent.x / length * thickness.x,
        bent.y / length * thickness.y,
        bent.z / length * thickness.z,
    )


def ior_roughness(roughness: Float32, ior: Float32) -> Float32:
    """Return the roughness the transmitted light is blurred by: three.js's
    `applyIorToRoughness`, none at an index of one and all of it from 1.5.

    Args:
        roughness: The floored roughness.
        ior: The index of refraction.

    Returns:
        The roughness scaled by `clamp(ior * 2 - 2, 0, 1)`.
    """
    return roughness * min(max(ior * 2 - 2, Float32(0)), Float32(1))


def transmission_level(
    width: Float32, roughness: Float32, ior: Float32
) -> Float32:
    """Return the mip level the transmitted light is read at: three.js's
    `log2(transmissionSamplerSize.x) * applyIorToRoughness(...)`.

    Args:
        width: The target's width in texels.
        roughness: The floored roughness.
        ior: The index of refraction.

    Returns:
        The level, fractional, from zero.
    """
    return log2(width) * ior_roughness(roughness, ior)


def volume_attenuation(
    distance: Float32, color: Vector3, attenuation_distance: Float32
) -> Vector3:
    """Return how much of each channel survives a path through the volume:
    three.js's `volumeAttenuation`, Beer's law.

    Args:
        distance: How far the light travels inside.
        color: The color white light becomes after `attenuation_distance`,
            linear, three.js's `attenuationColor`.
        attenuation_distance: How far that takes; infinity for no
            attenuation at all.

    Returns:
        The fraction per channel. One everywhere for an infinite distance,
        and one for a path of no length, where three.js divides zero by
        zero for a black channel.
    """
    if isinf(attenuation_distance) or distance == 0:
        return Vector3(1, 1, 1)
    return Vector3(
        exp(log(color.x) / attenuation_distance * distance),
        exp(log(color.y) / attenuation_distance * distance),
        exp(log(color.z) / attenuation_distance * distance),
    )


def target_coordinate(
    view: SIMD[DType.float32, VIEW_FLOATS], position: Vector3
) -> Vector2:
    """Return where a world position lands on the transmission target:
    three.js's `ndcPos.xy / ndcPos.w`, then `+ 1` and `/ 2`.

    Args:
        view: `TransmissionTarget.view`.
        position: The point, in world space.

    Returns:
        `u` across and `v` up, each zero to one inside the target.
    """
    var x = position.x
    var y = position.y
    var z = position.z
    var w = view[3] * x + view[7] * y + view[11] * z + view[15]
    return Vector2(
        (view[0] * x + view[4] * y + view[8] * z + view[12]) / w,
        (view[1] * x + view[5] * y + view[9] * z + view[13]) / w,
    )


def dispersed_iors(ior: Float32, dispersion: Float32) -> Vector3:
    """Return the index each channel is refracted at: three.js's `iors`,
    red the lowest and blue the highest.

    Args:
        ior: The material's index of refraction.
        dispersion: How far the channels spread, three.js's `dispersion`.

    Returns:
        `ior` less, at and more than half the spread.
    """
    var half = (ior - 1) * DISPERSION_SPREAD * dispersion
    return Vector3(ior - half, ior, ior + half)


def _w0(a: Float32) -> Float32:
    """Return the first cubic B-spline weight, three.js's `w0`."""
    return (Float32(1) / 6) * (a * (a * (-a + 3) - 3) + 1)


def _w1(a: Float32) -> Float32:
    """Return the second cubic B-spline weight, three.js's `w1`."""
    return (Float32(1) / 6) * (a * a * (3 * a - 6) + 4)


def _w2(a: Float32) -> Float32:
    """Return the third cubic B-spline weight, three.js's `w2`."""
    return (Float32(1) / 6) * (a * (a * (-3 * a + 3) + 3) + 1)


def _w3(a: Float32) -> Float32:
    """Return the fourth cubic B-spline weight, three.js's `w3`."""
    return (Float32(1) / 6) * (a * a * a)


def _weighted(
    sum: FloatColor, color: FloatColor, weight: Float32
) -> FloatColor:
    """Return `sum` plus `color` times `weight`, every channel alike, as
    GLSL adds two `vec4`s."""
    return FloatColor(
        sum.r + color.r * weight,
        sum.g + color.g * weight,
        sum.b + color.b * weight,
        sum.a + color.a * weight,
    )


def bicubic[
    S: TransmissionSource
](source: S, uv: Vector2, level: Int) -> FloatColor:
    """Return a bicubic sample of one level from four bilinear ones: three.js's
    `bicubic`, after N8's mipped bicubic filter.

    Args:
        source: Where the level is read.
        uv: The coordinate, `u` across and `v` up.
        level: Which level, one the chain holds.

    Returns:
        The filtered color, straight channels summed as GLSL sums them.
    """
    var size = source.level_size(level)
    var x = uv.x * size.x + 0.5
    var y = uv.y * size.y + 0.5
    var ix = floor(x)
    var iy = floor(y)
    var fx = x - ix
    var fy = y - iy
    var g0x = _w0(fx) + _w1(fx)
    var g1x = _w2(fx) + _w3(fx)
    var h0x = -1 + _w1(fx) / (_w0(fx) + _w1(fx))
    var h1x = 1 + _w3(fx) / (_w2(fx) + _w3(fx))
    var h0y = -1 + _w1(fy) / (_w0(fy) + _w1(fy))
    var h1y = 1 + _w3(fy) / (_w2(fy) + _w3(fy))
    var g0y = _w0(fy) + _w1(fy)
    var g1y = _w2(fy) + _w3(fy)
    var left = (ix + h0x - 0.5) / size.x
    var right = (ix + h1x - 0.5) / size.x
    var low = (iy + h0y - 0.5) / size.y
    var high = (iy + h1y - 0.5) / size.y
    var none = FloatColor(0.0, 0.0, 0.0, 0.0)
    var bottom = _weighted(
        _weighted(none, source.fetch_level(left, low, level), g0x),
        source.fetch_level(right, low, level),
        g1x,
    )
    var top = _weighted(
        _weighted(none, source.fetch_level(left, high, level), g0x),
        source.fetch_level(right, high, level),
        g1x,
    )
    return _weighted(_weighted(none, bottom, g0y), top, g1y)


def texture_bicubic[
    S: TransmissionSource
](source: S, uv: Vector2, lod: Float32) -> FloatColor:
    """Return a bicubic sample between two levels: three.js's
    `textureBicubic`.

    The level below `lod` and the one above, each read bicubically, mixed
    by the fraction. A level past the chain reads the last level.

    Args:
        source: Where the chain is read.
        uv: The coordinate, `u` across and `v` up.
        lod: The level, fractional, from zero.

    Returns:
        The filtered color.
    """
    var last = source.level_count() - 1
    var lower = min(Int(floor(lod)), last)
    var fine = bicubic(source, uv, lower)
    var fraction = lod - floor(lod)
    if fraction == 0:
        return fine
    var coarse = bicubic(source, uv, min(lower + 1, last))
    return FloatColor(
        fine.r + (coarse.r - fine.r) * fraction,
        fine.g + (coarse.g - fine.g) * fraction,
        fine.b + (coarse.b - fine.b) * fraction,
        fine.a + (coarse.a - fine.a) * fraction,
    )


def _transmission_sample[
    S: TransmissionSource
](
    source: S,
    view: SIMD[DType.float32, VIEW_FLOATS],
    position: Vector3,
    ray: Vector3,
    roughness: Float32,
    ior: Float32,
) -> FloatColor:
    """Return what the light leaving at the end of `ray` shows: three.js's
    projection of `refractedRayExit` and `getTransmissionSample`."""
    var place = target_coordinate(view, position + ray)
    var width = source.level_size(0).x
    return texture_bicubic(
        source, place, transmission_level(width, roughness, ior)
    )


def volume_refraction[
    S: TransmissionSource
](
    source: S,
    view: SIMD[DType.float32, VIEW_FLOATS],
    normal: Vector3,
    toward_eye: Vector3,
    roughness: Float32,
    diffuse: Vector3,
    specular: Vector3,
    f90: Float32,
    position: Vector3,
    thickness: Vector3,
    dispersion: Float32,
    ior: Float32,
    attenuation_color: Vector3,
    attenuation_distance: Float32,
) -> FloatColor:
    """Return the light a transmissive surface shows through itself, and
    how opaque that makes it: three.js's `getIBLVolumeRefraction`.

    Shared by both rasterizers over their own `source`.

    Args:
        source: The opaque scene, as a mip chain.
        view: `TransmissionTarget.view`.
        normal: The surface's unit normal, in world space.
        toward_eye: The unit vector from the surface to the camera.
        roughness: The floored roughness.
        diffuse: The surface's diffuse color, `Reflected.diffuse` of
            `physical_surface`: three.js's `material.diffuseColor`.
        specular: Its reflectance head on, `Reflected.specular`.
        f90: Its reflectance at a grazing angle.
        position: Where the fragment is, in world space.
        thickness: The thickness times any map, per world axis; see
            `transmission_ray`.
        dispersion: How far the channels spread; zero for none.
        ior: The index of refraction.
        attenuation_color: What the volume tints white light to, linear.
        attenuation_distance: How far that takes; infinity for never.

    Returns:
        The transmitted light in `r`, `g` and `b`, less what the surface
        reflects, and in `a` how opaque the surface is where the target
        was not.
    """
    var light: FloatColor
    var transmittance: Vector3
    if dispersion > 0:
        var iors = dispersed_iors(ior, dispersion)
        var red_ray = transmission_ray(normal, toward_eye, thickness, iors.x)
        var green_ray = transmission_ray(normal, toward_eye, thickness, iors.y)
        var blue_ray = transmission_ray(normal, toward_eye, thickness, iors.z)
        var red = _transmission_sample(
            source, view, position, red_ray, roughness, iors.x
        )
        var green = _transmission_sample(
            source, view, position, green_ray, roughness, iors.y
        )
        var blue = _transmission_sample(
            source, view, position, blue_ray, roughness, iors.z
        )
        light = FloatColor(
            red.r, green.g, blue.b, (red.a + green.a + blue.a) / 3
        )
        transmittance = Vector3(
            diffuse.x
            * volume_attenuation(
                red_ray.length(), attenuation_color, attenuation_distance
            ).x,
            diffuse.y
            * volume_attenuation(
                green_ray.length(), attenuation_color, attenuation_distance
            ).y,
            diffuse.z
            * volume_attenuation(
                blue_ray.length(), attenuation_color, attenuation_distance
            ).z,
        )
    else:
        var ray = transmission_ray(normal, toward_eye, thickness, ior)
        light = _transmission_sample(
            source, view, position, ray, roughness, ior
        )
        var through = volume_attenuation(
            ray.length(), attenuation_color, attenuation_distance
        )
        transmittance = Vector3(
            diffuse.x * through.x, diffuse.y * through.y, diffuse.z * through.z
        )
    var dot_nv = min(max(normal.dot(toward_eye), Float32(0)), Float32(1))
    var reflected = environment_brdf(dot_nv, specular, f90, roughness)
    var factor = (transmittance.x + transmittance.y + transmittance.z) / 3
    return FloatColor(
        (1 - reflected.x) * transmittance.x * light.r,
        (1 - reflected.y) * transmittance.y * light.g,
        (1 - reflected.z) * transmittance.z * light.b,
        1 - (1 - light.a) * factor,
    )


def host_refraction(
    target: TransmissionTarget,
    normal: Vector3,
    toward_eye: Vector3,
    roughness: Float32,
    diffuse: Vector3,
    specular: Vector3,
    f90: Float32,
    position: Vector3,
    thickness: Vector3,
    dispersion: Float32,
    ior: Float32,
    attenuation_color: Vector3,
    attenuation_distance: Float32,
) -> FloatColor:
    """Return `volume_refraction` read from the host's texture.

    Args:
        target: The opaque scene, built.
        normal: The surface's unit normal, in world space.
        toward_eye: The unit vector from the surface to the camera.
        roughness: The floored roughness.
        diffuse: The surface's diffuse color.
        specular: Its reflectance head on.
        f90: Its reflectance at a grazing angle.
        position: Where the fragment is, in world space.
        thickness: The thickness per world axis.
        dispersion: How far the channels spread.
        ior: The index of refraction.
        attenuation_color: What the volume tints white light to, linear.
        attenuation_distance: How far that takes.

    Returns:
        What `volume_refraction` returns.
    """
    var source = HostSource(Pointer(to=target.image))
    return volume_refraction(
        source,
        target.view,
        normal,
        toward_eye,
        roughness,
        diffuse,
        specular,
        f90,
        position,
        thickness,
        dispersion,
        ior,
        attenuation_color,
        attenuation_distance,
    )


def transmission_alpha(alpha: Float32, transmission: Float32) -> Float32:
    """Return what a transmissive fragment's alpha is multiplied by: three.js's
    `mix(1.0, transmitted.a, material.transmission)`.

    Args:
        alpha: The alpha `volume_refraction` returned.
        transmission: How much of the diffuse light is transmitted.

    Returns:
        The factor.
    """
    return 1 + (alpha - 1) * transmission
