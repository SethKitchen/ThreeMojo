# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An equirectangular environment sampled for screen-space reflections:
three.js r186's `ImportanceSampledEnvironment`, from
`examples/jsm/tsl/display/ImportanceSampledEnvironment.js`, and the
helpers it takes from `tsl/utils/SpecularHelpers.js`.

**The map.** The environment is kept as three.js keeps it: each channel
rounded to a half float, and its rows turned over when the texture's
`flipY` is on. It wraps across and is held at the poles.

**The distributions.** With importance sampling on, the map's luminance
gives a distribution over its rows and, in each row, over its texels.
Each is tabulated as three.js tabulates it: for each of `n` even steps
of the cumulative distribution, the texture coordinate of the row or the
texel where the step is first reached, rounded to a half float.

**The three samples.** `sample_reflect` reads the map along a reflected
ray. `sample_environment_brdf` weighs that by the GGX lobe's Fresnel and
shadowing, divided by the lobe's own shadowing toward the viewer.
`sample_environment_mis` adds a second sample, drawn from the map's
distributions, and weighs the two by the power heuristic.

**One difference.** three.js passes the drawn texture coordinate to
`equirectUV`, which takes a direction. This port turns the coordinate into
its direction with `equirectUvToDir`, which is what the code means.

No composer pass reads this: three.js's SSR node reads it in its
environment mode, which `postprocessing.ssr_node` does not port.
"""

from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from postprocessing.display_nodes import luminance_of
from render.framebuffer import FloatColor
from std.math import asin, atan2, cos, floor, isfinite, max, min, pi, pow, sin
from std.math import sqrt


def half(value: Float32) -> Float32:
    """Return a number rounded to a half float, three.js's
    `DataUtils.toHalfFloat` read back with `fromHalfFloat`.

    Args:
        value: The number.

    Returns:
        The nearest half float.
    """
    return value.cast[DType.float16]().cast[DType.float32]()


def color_to_luminance(r: Float32, g: Float32, b: Float32) -> Float32:
    """Return three.js's `colorToLuminance`, the rec. 709 weights to four
    places.

    Args:
        r: Red.
        g: Green.
        b: Blue.

    Returns:
        The luminance.
    """
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def closest_index(
    values: List[Float32], target: Float32, offset: Int, count: Int
) -> Int:
    """Return where a target is first reached in a sorted run of a list:
    three.js's `binarySearchFindClosestIndexOf`.

    Args:
        values: The list, ascending over the run.
        target: The value to find.
        offset: Where the run starts.
        count: How long it is.

    Returns:
        The first place in the run, counted from its start, whose value is
        at least the target, or the last place.
    """
    var lower = offset
    var upper = offset + count - 1
    while lower < upper:
        var mid = (lower + upper) >> 1
        if values[mid] < target:
            lower = mid + 1
        else:
            upper = mid
    return lower - offset


struct EquirectEnvironment(Copyable, Movable):
    """An equirectangular map and its distributions, as three.js's
    `EnvMapCDFGenerator` keeps them."""

    var width: Int
    var height: Int
    # The texels, rounded to half floats, row by row as the texture reads
    # them after the flip.
    var texels: List[FloatColor]
    # The row each step of the rows' distribution lands on, as a texture
    # coordinate, `height` of them; empty without importance sampling.
    var marginal: List[Float32]
    # The texel each step of a row's distribution lands on, `width` a row.
    var conditional: List[Float32]
    # The luminance summed over the map, `totalSum`.
    var total: Float32
    # What every sample is scaled by, `intensity`.
    var intensity: Float32

    def __init__(
        out self,
        width: Int,
        height: Int,
        texels: List[FloatColor],
        flip_y: Bool = False,
        importance_sampling: Bool = False,
    ) raises:
        """Take a map as three.js's `updateFrom` takes it.

        Args:
            width: The map's width in texels.
            height: Its height.
            texels: Its texels, linear, row by row as the image holds them.
            flip_y: The texture's `flipY`: whether the rows are turned over.
            importance_sampling: Whether the distributions are built.

        Raises:
            Error: If a size is not positive, or the texels are not one a
                texel of the size.
        """
        if width <= 0 or height <= 0:
            raise Error("An environment's size must be positive")
        if len(texels) != width * height:
            raise Error("An environment needs one texel a texel")
        self.width = width
        self.height = height
        self.texels = List[FloatColor](capacity=width * height)
        for y in range(height):  # pragma: no branch
            var row = height - 1 - y if flip_y else y
            for x in range(width):  # pragma: no branch
                var t = texels[row * width + x]
                self.texels.append(
                    FloatColor(half(t.r), half(t.g), half(t.b), half(t.a))
                )
        self.marginal = List[Float32]()
        self.conditional = List[Float32]()
        self.total = 0
        self.intensity = 1
        if importance_sampling:
            self._distribute()

    def _distribute(mut self):
        """Build the rows' and each row's distribution, three.js's
        `updateFrom`."""
        var w = self.width
        var h = self.height
        var cdf_row = List[Float32](length=w * h, fill=0)
        var cdf_marginal = List[Float32](length=h, fill=0)
        var total = Float32(0)
        var running = Float32(0)
        for y in range(h):  # pragma: no branch
            var row_sum = Float32(0)
            for x in range(w):  # pragma: no branch
                var t = self.texels[y * w + x]
                var weight = color_to_luminance(t.r, t.g, t.b)
                row_sum += weight
                total += weight
                cdf_row[y * w + x] = row_sum
            if row_sum != 0:
                for x in range(w):  # pragma: no branch
                    cdf_row[y * w + x] /= row_sum
            running += row_sum
            cdf_marginal[y] = running
        if running != 0:
            for y in range(h):  # pragma: no branch
                cdf_marginal[y] /= running
        self.marginal = List[Float32](capacity=h)
        for i in range(h):  # pragma: no branch
            var step = Float32(i + 1) / Float32(h)
            var row = closest_index(cdf_marginal, step, 0, h)
            self.marginal.append(half((Float32(row) + 0.5) / Float32(h)))
        self.conditional = List[Float32](capacity=w * h)
        for y in range(h):  # pragma: no branch
            for x in range(w):  # pragma: no branch
                var step = Float32(x + 1) / Float32(w)
                var column = closest_index(cdf_row, step, y * w, w)
                self.conditional.append(
                    half((Float32(column) + 0.5) / Float32(w))
                )
        self.total = total

    def sample(self, u: Float32, v: Float32) -> FloatColor:
        """Return the map at a texture coordinate, bilinear, wrapping across
        and held at the poles: `RepeatWrapping` and `ClampToEdgeWrapping`.

        Args:
            u: Across, wrapping.
            v: Along the rows, zero at the first.

        Returns:
            The texel blend.
        """
        var px = u * Float32(self.width) - 0.5
        var py = min(
            max(v * Float32(self.height) - 0.5, 0), Float32(self.height - 1)
        )
        var fx0 = floor(px)
        var x0 = Int(fx0)
        var fx = px - fx0
        var y0 = Int(py)
        var fy = py - Float32(y0)
        var y1 = min(y0 + 1, self.height - 1)
        var a = self._at(x0, y0)
        var b = self._at(x0 + 1, y0)
        var c = self._at(x0, y1)
        var d = self._at(x0 + 1, y1)
        return FloatColor(
            _lerp(_lerp(a.r, b.r, fx), _lerp(c.r, d.r, fx), fy),
            _lerp(_lerp(a.g, b.g, fx), _lerp(c.g, d.g, fx), fy),
            _lerp(_lerp(a.b, b.b, fx), _lerp(c.b, d.b, fx), fy),
            _lerp(_lerp(a.a, b.a, fx), _lerp(c.a, d.a, fx), fy),
        )

    def _at(self, x: Int, y: Int) -> FloatColor:
        """Return a texel, its column wrapped."""
        var column = ((x % self.width) + self.width) % self.width
        return self.texels[y * self.width + column]

    def table(self, values: List[Float32], count: Int, at: Float32) -> Float32:
        """Return a distribution's table read linear at a coordinate, held
        at its ends, as three.js's `LinearFilter` reads it.

        Args:
            values: The table, `count` long from its start.
            count: How long it is.
            at: The coordinate, zero to one.

        Returns:
            The blend of the two nearest entries.
        """
        var p = min(max(at * Float32(count) - 0.5, 0), Float32(count - 1))
        var i = Int(p)
        var f = p - Float32(i)
        var j = min(i + 1, count - 1)
        return _lerp(values[i], values[j], f)


def _lerp(a: Float32, b: Float32, t: Float32) -> Float32:
    """Return GLSL's `mix` of two numbers."""
    return a + (b - a) * t


# --- SpecularHelpers ---------------------------------------------------------


def equirect_uv(direction: Vector3) -> Vector2:
    """Return three.js's `equirectUV`: a direction's texture coordinate on
    an equirectangular map.

    Args:
        direction: The direction, unit length.

    Returns:
        `atan(z, x) / 2 pi + 1 / 2` across and `asin(y) / pi + 1 / 2` up.
    """
    return Vector2(
        atan2(direction.z, direction.x) * Float32(1 / (2 * pi)) + 0.5,
        asin(min(max(direction.y, -1), 1)) * Float32(1 / pi) + 0.5,
    )


def equirect_uv_to_dir(uv: Vector2) -> Vector3:
    """Return three.js's `equirectUvToDir`: the direction at a texture
    coordinate on an equirectangular map.

    Args:
        uv: The coordinate.

    Returns:
        The unit direction.
    """
    var phi = uv.x * Float32(pi * 2) - Float32(pi)
    var lat = (uv.y - 0.5) * Float32(pi)
    var out = Vector3(cos(lat) * cos(phi), sin(lat), cos(lat) * sin(phi))
    out.normalize()
    return out


def equirect_dir_pdf(direction: Vector3) -> Float32:
    """Return three.js's `equirectDirPdf`: the solid-angle density of a
    direction drawn evenly over an equirectangular map's texels.

    Args:
        direction: The direction.

    Returns:
        `1 / (2 pi^2 sin(theta))`, or zero at a pole.
    """
    var sin_theta = sin(equirect_uv(direction).y * Float32(pi))
    if abs(sin_theta) < 1e-6:
        return 0
    return 1 / (Float32(2 * pi * pi) * sin_theta)


def mis_power_heuristic(pdf_a: Float32, pdf_b: Float32) -> Float32:
    """Return three.js's `misPowerHeuristic`, `a^2 / (a^2 + b^2)`.

    Args:
        pdf_a: The density of the technique the sample came from.
        pdf_b: The other technique's density.

    Returns:
        The weight.
    """
    return pdf_a * pdf_a / (pdf_a * pdf_a + pdf_b * pdf_b)


def d_gtr(roughness: Float32, n_dot_h: Float32, k: Float32) -> Float32:
    """Return three.js's `D_GTR`, the generalized Trowbridge-Reitz normal
    distribution: GGX for `k` of two.

    Args:
        roughness: The GGX alpha.
        n_dot_h: The cosine between the normal and the half vector.
        k: The tail's power.

    Returns:
        `a^2 / (pi (n.h^2 (a^2 - 1) + 1)^k)`.
    """
    var a2 = roughness * roughness
    var base = n_dot_h * n_dot_h * (a2 - 1) + 1
    return a2 / (Float32(pi) * pow(base, k))


def smith_g(n_dot_x: Float32, alpha: Float32) -> Float32:
    """Return three.js's `SmithG`, Heitz's shadowing of one direction.

    Args:
        n_dot_x: The cosine between the normal and the direction.
        alpha: The GGX alpha.

    Returns:
        `2 n.x / (n.x + sqrt(a^2 + (1 - a^2) n.x^2))`.
    """
    var a2 = alpha * alpha
    return 2 * n_dot_x / (n_dot_x + sqrt(a2 + (1 - a2) * n_dot_x * n_dot_x))


def geometry_term(
    n_dot_l: Float32, n_dot_v: Float32, alpha: Float32
) -> Float32:
    """Return three.js's `GeometryTerm`: the shadowing of both directions.

    Args:
        n_dot_l: The cosine toward the light.
        n_dot_v: The cosine toward the viewer.
        alpha: The GGX alpha.

    Returns:
        `SmithG(n.v) SmithG(n.l)`.
    """
    return smith_g(n_dot_v, alpha) * smith_g(n_dot_l, alpha)


def f_schlick(f0: Vector3, cosine: Float32) -> Vector3:
    """Return three.js's `F_Schlick`.

    Args:
        f0: The reflectance at normal incidence.
        cosine: The cosine between the viewer and the half vector.

    Returns:
        `f0 + (1 - f0) (1 - cos)^5`.
    """
    var m = 1 - cosine
    var m5 = m * m * m * m * m
    return Vector3(
        f0.x + (1 - f0.x) * m5, f0.y + (1 - f0.y) * m5, f0.z + (1 - f0.z) * m5
    )


def _to_world(direction: Vector3, camera_world: Matrix4) -> Vector3:
    """Return a view-space direction in the world, unit length:
    `(cameraWorldMatrix * vec4( d, 0 )).xyz.normalize()`."""
    var world = camera_world.transform_point(direction) - (
        camera_world.transform_point(Vector3(0, 0, 0))
    )
    world.normalize()
    return world


def _rgb(color: FloatColor) -> Vector3:
    """Return a color's red, green and blue."""
    return Vector3(color.r, color.g, color.b)


def sample_reflect(
    env: EquirectEnvironment,
    camera_world: Matrix4,
    view_reflect_dir: Vector3,
    weight: Float32 = 1,
) -> Vector3:
    """Return the map along a reflected ray, three.js's `sampleReflect`.

    Args:
        env: The environment.
        camera_world: The camera's world matrix.
        view_reflect_dir: The reflected ray, in the camera's space.
        weight: What the sample is scaled by, `sampleWeight`.

    Returns:
        The light.
    """
    var uv = equirect_uv(_to_world(view_reflect_dir, camera_world))
    return _rgb(env.sample(uv.x, uv.y)) * (env.intensity * weight)


def sample_environment_brdf(
    env: EquirectEnvironment,
    camera_world: Matrix4,
    view_reflect_dir: Vector3,
    normal: Vector3,
    view_dir: Vector3,
    alpha: Float32,
    f0: Vector3,
) -> Vector3:
    """Return the map along a reflected ray weighed by the GGX lobe:
    three.js's `sampleEnvironmentBRDF`.

    Args:
        env: The environment.
        camera_world: The camera's world matrix.
        view_reflect_dir: The reflected ray, in the camera's space.
        normal: The surface's normal, in the camera's space.
        view_dir: The direction toward the viewer, in the camera's space.
        alpha: The GGX alpha.
        f0: The reflectance at normal incidence.

    Returns:
        The light.
    """
    var n = _to_world(normal, camera_world)
    var v = _to_world(view_dir, camera_world)
    var n_dot_v = max(Float32(0), n.dot(v))
    var l = _to_world(view_reflect_dir, camera_world)
    var uv = equirect_uv(l)
    var color = _rgb(env.sample(uv.x, uv.y))
    var h = v + l
    h.normalize()
    var n_dot_l = max(Float32(0), n.dot(l))
    var v_dot_h = max(Float32(0), v.dot(h))
    var scale = geometry_term(n_dot_l, n_dot_v, alpha) / max(
        smith_g(n_dot_v, alpha), Float32(1e-4)
    )
    var fresnel = f_schlick(f0, v_dot_h)
    return Vector3(
        color.x * fresnel.x, color.y * fresnel.y, color.z * fresnel.z
    ) * (scale * env.intensity)


def sample_environment_mis(
    env: EquirectEnvironment,
    camera_world: Matrix4,
    view_reflect_dir: Vector3,
    normal: Vector3,
    view_dir: Vector3,
    alpha: Float32,
    f0: Vector3,
    xi_z: Float32,
    xi_w: Float32,
) -> Vector3:
    """Return the environment's light by two samples weighed by the power
    heuristic: three.js's `sampleEnvironmentMIS`.

    The first sample is the reflected ray, weighed as
    `sample_environment_brdf` weighs it. The second is drawn from the
    map's distributions by two random numbers, for a lobe rougher than an
    alpha of a hundredth.

    Args:
        env: The environment, with its distributions.
        camera_world: The camera's world matrix.
        view_reflect_dir: The reflected ray, in the camera's space.
        normal: The surface's normal, in the camera's space.
        view_dir: The direction toward the viewer, in the camera's space.
        alpha: The GGX alpha.
        f0: The reflectance at normal incidence.
        xi_z: The random number that picks the row, `Xi2.z`.
        xi_w: The random number that picks the texel, `Xi2.w`.

    Returns:
        The light.
    """
    var w = Float32(env.width)
    var h = Float32(env.height)
    var n = _to_world(normal, camera_world)
    var v = _to_world(view_dir, camera_world)
    var n_dot_v = max(Float32(0), n.dot(v))
    var l1 = _to_world(view_reflect_dir, camera_world)
    var uv1 = equirect_uv(l1)
    var color1 = _rgb(env.sample(uv1.x, uv1.y))
    var h1 = v + l1
    h1.normalize()
    var n_dot_l1 = max(Float32(0), n.dot(l1))
    var n_dot_h1 = max(Float32(0), n.dot(h1))
    var v_dot_h1 = max(Float32(0), v.dot(h1))
    var pdf_brdf1 = max(
        d_gtr(alpha, n_dot_h1, 2)
        * smith_g(n_dot_v, alpha)
        / max(Float32(1e-6), 4 * n_dot_v),
        Float32(1e-8),
    )
    var pdf_env1 = max(
        w
        * h
        * (luminance_of(color1.x, color1.y, color1.z) / env.total)
        * equirect_dir_pdf(l1),
        Float32(1e-8),
    )
    var w1 = mis_power_heuristic(pdf_brdf1, pdf_env1)
    var scale1 = geometry_term(n_dot_l1, n_dot_v, alpha) / max(
        smith_g(n_dot_v, alpha), Float32(1e-4)
    )
    var fresnel1 = f_schlick(f0, v_dot_h1)
    var result = Vector3(
        color1.x * fresnel1.x, color1.y * fresnel1.y, color1.z * fresnel1.z
    ) * (scale1 * w1)
    if alpha > 0.01:
        var v_cdf = env.table(env.marginal, env.height, xi_z)
        var u_cdf = conditional_at(env, xi_w, v_cdf)
        var dir = equirect_uv_to_dir(Vector2(u_cdf, v_cdf))
        var half_vector = v + dir
        half_vector.normalize()
        var n_dot_l = max(Float32(0), n.dot(dir))
        var n_dot_h = max(Float32(0), n.dot(half_vector))
        var v_dot_h = max(Float32(0), v.dot(half_vector))
        if n_dot_l > 0.001:
            var d = d_gtr(alpha, n_dot_h, 2)
            var color = _rgb(env.sample(u_cdf, v_cdf))
            var pdf_env2 = max(
                w
                * h
                * (luminance_of(color.x, color.y, color.z) / env.total)
                * equirect_dir_pdf(dir),
                Float32(1e-8),
            )
            var pdf_brdf2 = max(
                d * smith_g(n_dot_v, alpha) / max(Float32(1e-6), 4 * n_dot_v),
                Float32(1e-8),
            )
            var w2 = mis_power_heuristic(pdf_env2, pdf_brdf2)
            var spec = (
                d
                * geometry_term(n_dot_l, n_dot_v, alpha)
                / max(Float32(1e-6), 4 * n_dot_l * n_dot_v)
            )
            var fresnel = f_schlick(f0, v_dot_h)
            var share = spec * n_dot_l / pdf_env2 * w2
            result = result + Vector3(
                color.x * fresnel.x * share,
                color.y * fresnel.y * share,
                color.z * fresnel.z * share,
            )
    return result * env.intensity


def conditional_at(env: EquirectEnvironment, u: Float32, v: Float32) -> Float32:
    """Return the rows' conditional table read bilinear, held at its edges,
    as three.js's `LinearFilter` reads the conditional texture.

    Args:
        env: The environment, with its distributions.
        u: Across the table: the random number that picks the texel.
        v: Down the table: the row's texture coordinate.

    Returns:
        The texel's texture coordinate across.
    """
    var w = env.width
    var h = env.height
    var px = min(max(u * Float32(w) - 0.5, 0), Float32(w - 1))
    var py = min(max(v * Float32(h) - 0.5, 0), Float32(h - 1))
    var x0 = Int(px)
    var y0 = Int(py)
    var fx = px - Float32(x0)
    var fy = py - Float32(y0)
    var x1 = min(x0 + 1, w - 1)
    var y1 = min(y0 + 1, h - 1)
    var top = _lerp(
        env.conditional[y0 * w + x0], env.conditional[y0 * w + x1], fx
    )
    var bottom = _lerp(
        env.conditional[y1 * w + x0], env.conditional[y1 * w + x1], fx
    )
    return _lerp(top, bottom, fy)
