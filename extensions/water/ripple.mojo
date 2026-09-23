# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The local wave equation Clearwater runs under a tap.

One step is the ripple shader: a damped average of the four neighbors, an
optional cosine drop, and a fade at the border of the window. The normal
pass stores height, both slopes and the Laplacian the caustic term reads.
"""

from extensions.water.resolution import require_resolution, SpectrumResolution
from std.math import cos, floor, sqrt
from units.si import Length


def clearwater_ripple_size() -> Length:
    """Return the ripple window, 7 m on a side.

    Returns:
        Clearwater's `RSIZE`.
    """
    return Length(7.0)


struct RippleField(Movable):
    """One ripple window: height, velocity and the normal texture."""

    var n: Int
    var size: Float32
    var center_x: Float32
    var center_z: Float32
    var height: List[Float32]
    var velocity: List[Float32]
    var normal: List[Float32]

    def __init__(out self, resolution: SpectrumResolution, size: Length) raises:
        """Allocate a calm window.

        Args:
            resolution: Texels on one side.
            size: The window length, in meters. It must be positive.

        Raises:
            Error: If the resolution is not valid, or `size` is not positive.
        """
        if size.value <= 0.0:
            raise Error("Ripple window length must be positive")
        require_resolution(resolution)
        var side = resolution.value
        self.n = side
        self.size = size.value
        self.center_x = 0.0
        self.center_z = 0.0
        self.height = List[Float32](length=side * side, fill=0.0)
        self.velocity = List[Float32](length=side * side, fill=0.0)
        self.normal = List[Float32](length=side * side * 4, fill=0.0)

    def _at(self, x: Int, y: Int) -> Int:
        return y * self.n + x


def _clamp_index(i: Int, n: Int) -> Int:
    if i < 0:
        return 0
    if i >= n:
        return n - 1
    return i


@fieldwise_init
struct _HeightVelocity(ImplicitlyCopyable):
    var height: Float32
    var velocity: Float32


@fieldwise_init
struct RippleSample(ImplicitlyCopyable):
    """Height, slopes and Laplacian at one point of the ripple window."""

    var height: Float32
    var slope_x: Float32
    var slope_z: Float32
    var laplacian: Float32


def _sample_height(
    field: RippleField, u: Float32, v: Float32
) -> _HeightVelocity:
    """Bilinear height and velocity. Coordinates outside the window are zero."""
    if u < 0.0 or v < 0.0 or u > 1.0 or v > 1.0:
        return _HeightVelocity(0.0, 0.0)
    var n = field.n
    var px = u * Float32(n) - 0.5
    var py = v * Float32(n) - 0.5
    var x0 = Int(floor(px))
    var y0 = Int(floor(py))
    var fx = px - Float32(x0)
    var fy = py - Float32(y0)
    var x1 = _clamp_index(x0 + 1, n)
    var y1 = _clamp_index(y0 + 1, n)
    x0 = _clamp_index(x0, n)
    y0 = _clamp_index(y0, n)
    var h00 = field.height[field._at(x0, y0)]
    var h10 = field.height[field._at(x1, y0)]
    var h01 = field.height[field._at(x0, y1)]
    var h11 = field.height[field._at(x1, y1)]
    var v00 = field.velocity[field._at(x0, y0)]
    var v10 = field.velocity[field._at(x1, y0)]
    var v01 = field.velocity[field._at(x0, y1)]
    var v11 = field.velocity[field._at(x1, y1)]
    var h0 = h00 + (h10 - h00) * fx
    var h1 = h01 + (h11 - h01) * fx
    var vel0 = v00 + (v10 - v00) * fx
    var vel1 = v01 + (v11 - v01) * fx
    return _HeightVelocity(h0 + (h1 - h0) * fy, vel0 + (vel1 - vel0) * fy)


def step_ripple(
    mut field: RippleField,
    shift_u: Float32,
    shift_v: Float32,
    drop_u: Float32,
    drop_v: Float32,
    drop_radius: Float32,
    drop_strength: Float32,
):
    """Advance the wave equation one step and rebuild the normal texture.

    Args:
        field: The window. Height and velocity are replaced.
        shift_u: How far the window scrolled, in texels over `n`.
        shift_v: The same scroll on z.
        drop_u: Drop position in window coordinates, 0 to 1.
        drop_v: Drop position in window coordinates, 0 to 1.
        drop_radius: Drop radius in window coordinates.
        drop_strength: How far the drop pulls the surface down. Zero skips it.
    """
    var n = field.n
    var next_h = List[Float32](length=n * n, fill=0.0)
    var next_v = List[Float32](length=n * n, fill=0.0)
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var u = (Float32(x) + 0.5) / Float32(n)
            var v = (Float32(y) + 0.5) / Float32(n)
            var su = u + shift_u
            var sv = v + shift_v
            var c = _sample_height(field, su, sv)
            var px = 1.0 / Float32(n)
            var avg = (
                _sample_height(field, su + px, sv).height
                + _sample_height(field, su - px, sv).height
                + _sample_height(field, su, sv + px).height
                + _sample_height(field, su, sv - px).height
            ) * 0.25
            var vel = c.velocity + (avg - c.height) * 0.9
            vel *= 0.9955
            var h = c.height + vel
            h *= 0.9985
            if drop_strength != 0.0:
                var du = u - drop_u
                var dv = v - drop_v
                var d = sqrt(du * du + dv * dv)
                if d < drop_radius:
                    var lobe = 0.5 + 0.5 * cos(
                        Float32(3.141592653589793) * d / drop_radius
                    )
                    h -= drop_strength * lobe
            var edge_u = u
            if edge_u > 0.5:
                edge_u = 1.0 - edge_u
            var edge_v = v
            if edge_v > 0.5:
                edge_v = 1.0 - edge_v
            var edge = edge_u
            if edge_v < edge:
                edge = edge_v
            var fade = _smooth_border(edge)
            h *= fade
            vel *= fade
            if su < 0.0 or sv < 0.0 or su > 1.0 or sv > 1.0:
                h = 0.0
                vel = 0.0
            var i = y * n + x
            next_h[i] = h
            next_v[i] = vel
    field.height = next_h^
    field.velocity = next_v^
    _write_normals(field)


def _smooth_border(edge: Float32) -> Float32:
    # smoothstep(0, 0.06, edge) mixes 0.9 at the border toward 1 inside.
    # Texel centers are inside the window, so `edge` stays positive.
    var t = edge / 0.06
    if t >= 1.0:
        return 1.0
    t = t * t * (3.0 - 2.0 * t)
    return 0.9 + 0.1 * t


def _write_normals(mut field: RippleField):
    var n = field.n
    var texel = field.size / Float32(n)
    for y in range(n):  # pragma: no branch
        for x in range(n):  # pragma: no branch
            var u = (Float32(x) + 0.5) / Float32(n)
            var v = (Float32(y) + 0.5) / Float32(n)
            var px = 1.0 / Float32(n)
            var hx = (
                _sample_height(field, u + px, v).height
                - _sample_height(field, u - px, v).height
            )
            var hz = (
                _sample_height(field, u, v + px).height
                - _sample_height(field, u, v - px).height
            )
            var h = _sample_height(field, u, v).height
            var lap = (
                _sample_height(field, u + px, v).height
                + _sample_height(field, u - px, v).height
                + _sample_height(field, u, v + px).height
                + _sample_height(field, u, v - px).height
                - 4.0 * h
            ) / (texel * texel)
            var i = (y * n + x) * 4
            field.normal[i] = h
            field.normal[i + 1] = hx / (2.0 * texel)
            field.normal[i + 2] = hz / (2.0 * texel)
            field.normal[i + 3] = lap


def sample_ripple(field: RippleField, x: Float32, z: Float32) -> RippleSample:
    """Sample height, slopes and Laplacian at one world position.

    Args:
        field: A window after at least one step. A calm window is zero.
        x: World x, in meters.
        z: World z, in meters.

    Returns:
        Height, `∂h/∂x`, `∂h/∂z` and Laplacian. Outside the window every
        channel is zero.
    """
    var u = (x - field.center_x) / field.size + 0.5
    var v = (z - field.center_z) / field.size + 0.5
    if u < 0.0 or v < 0.0 or u > 1.0 or v > 1.0:
        return RippleSample(0.0, 0.0, 0.0, 0.0)
    var n = field.n
    var px = u * Float32(n) - 0.5
    var py = v * Float32(n) - 0.5
    var x0 = Int(floor(px))
    var y0 = Int(floor(py))
    var fx = px - Float32(x0)
    var fy = py - Float32(y0)
    var x1 = _clamp_index(x0 + 1, n)
    var y1 = _clamp_index(y0 + 1, n)
    x0 = _clamp_index(x0, n)
    y0 = _clamp_index(y0, n)
    return _blend_normal(field, x0, y0, x1, y1, fx, fy)


def _blend_normal(
    field: RippleField,
    x0: Int,
    y0: Int,
    x1: Int,
    y1: Int,
    fx: Float32,
    fy: Float32,
) -> RippleSample:
    var n = field.n
    var w00 = (1.0 - fx) * (1.0 - fy)
    var w10 = fx * (1.0 - fy)
    var w01 = (1.0 - fx) * fy
    var w11 = fx * fy
    var h = Float32(0.0)
    var sx = Float32(0.0)
    var sz = Float32(0.0)
    var lap = Float32(0.0)
    h += _normal_at(field, n, x0, y0, 0) * w00
    sx += _normal_at(field, n, x0, y0, 1) * w00
    sz += _normal_at(field, n, x0, y0, 2) * w00
    lap += _normal_at(field, n, x0, y0, 3) * w00
    h += _normal_at(field, n, x1, y0, 0) * w10
    sx += _normal_at(field, n, x1, y0, 1) * w10
    sz += _normal_at(field, n, x1, y0, 2) * w10
    lap += _normal_at(field, n, x1, y0, 3) * w10
    h += _normal_at(field, n, x0, y1, 0) * w01
    sx += _normal_at(field, n, x0, y1, 1) * w01
    sz += _normal_at(field, n, x0, y1, 2) * w01
    lap += _normal_at(field, n, x0, y1, 3) * w01
    h += _normal_at(field, n, x1, y1, 0) * w11
    sx += _normal_at(field, n, x1, y1, 1) * w11
    sz += _normal_at(field, n, x1, y1, 2) * w11
    lap += _normal_at(field, n, x1, y1, 3) * w11
    return RippleSample(h, sx, sz, lap)


def _normal_at(
    field: RippleField, n: Int, x: Int, y: Int, channel: Int
) -> Float32:
    return field.normal[(y * n + x) * 4 + channel]
