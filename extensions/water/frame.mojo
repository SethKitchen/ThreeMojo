# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One Clearwater frame: intersect the waves, shade, then grade.

The camera, the sun and the field of view match the page. A fixed clock
holds the camera still, which is what `?t=` does. Sway is the idle motion
the page adds while time is running.
"""

from extensions.water.caustics import CausticField, render_caustics
from extensions.water.glare import apply_glare, glare_kernels
from extensions.water.optics import (
    Refracted,
    aces_channel,
    bed_color,
    beckmann,
    clamp01,
    floor_depth,
    fresnel,
    hash12,
    max,
    refract,
    sky_radiance,
    smith_visibility,
    smoothstep,
    sun_direction,
    water_ior,
)
from extensions.water.resolution import SpectrumResolution
from extensions.water.ripple import (
    RippleField,
    clearwater_ripple_size,
    sample_ripple,
    step_ripple,
)
from extensions.water.surface import (
    SurfaceField,
    sample_surface,
    shader_time,
    slope_variance,
    water_surface,
)
from extensions.water.view import (
    CAUSTICS,
    FRAME,
    GLARE,
    LINEAR,
    WaterView,
    require_view,
)
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor, Framebuffer
from std.math import cos, exp, pow, sin, sqrt, tan
from units.si import DEGREE, SECOND, Angle, Duration, Length


@fieldwise_init
struct CameraLook(ImplicitlyCopyable):
    """An orthonormal camera and its position, in meters."""

    var fx: Float32
    var fy: Float32
    var fz: Float32
    var rx: Float32
    var ry: Float32
    var rz: Float32
    var ux: Float32
    var uy: Float32
    var uz: Float32
    var px: Float32
    var py: Float32
    var pz: Float32


def camera_look(clock: Duration, sway: Bool) -> CameraLook:
    """Return the page's camera at one clock time.

    Args:
        clock: Seconds since the start. The screenshot clock is 5.
        sway: True adds the idle bob. `?t=` on the page sets this false.

    Returns:
        The basis and the eye position. Y is up.
    """
    var yaw = Float32(0.0)
    var pitch = Float32(-0.72)
    var roll = Float32(0.0)
    var x = Float32(0.0)
    var y = Float32(1.55)
    var z = Float32(0.0)
    var t = clock.value
    if sway:
        yaw += 0.010 * sin(t * 0.31) + 0.005 * sin(t * 0.83 + 1.3)
        pitch += 0.007 * sin(t * 0.47 + 2.0) + 0.003 * sin(t * 1.13)
        roll += 0.006 * sin(t * 0.39 + 0.4)
        x = 0.03 * sin(t * 0.21)
        y += 0.015 * sin(t * 0.57)
        z = 0.03 * cos(t * 0.17)
    var fx = sin(yaw) * cos(pitch)
    var fy = sin(pitch)
    var fz = -cos(yaw) * cos(pitch)
    var rx = cos(yaw)
    var ry = Float32(0.0)
    var rz = sin(yaw)
    var ux = ry * fz - rz * fy
    var uy = rz * fx - rx * fz
    var uz = rx * fy - ry * fx
    var cr = cos(roll)
    var sr = sin(roll)
    return CameraLook(
        fx,
        fy,
        fz,
        rx * cr + ux * sr,
        ry * cr + uy * sr,
        rz * cr + uz * sr,
        ux * cr - rx * sr,
        uy * cr - ry * sr,
        uz * cr - rz * sr,
        x,
        y,
        z,
    )


def water_radiance(
    look: CameraLook,
    ndc_x: Float32,
    ndc_y: Float32,
    aspect: Float32,
    surface: SurfaceField,
    ripples: RippleField,
    caustics: CausticField,
    clock: Duration,
) -> Vector3:
    """Shade one view ray.

    Args:
        look: The camera basis.
        ndc_x: Horizontal normalized coordinate, -1 to 1.
        ndc_y: Vertical normalized coordinate, -1 at the bottom.
        aspect: Width over height.
        surface: The ocean FFT surface.
        ripples: The local wave-equation window.
        caustics: The refracted-grid texture.
        clock: Frame time, used by the suspended specks.

    Returns:
        Linear radiance before grading.
    """
    var tan_f = tan(Angle(32.0, DEGREE).value)
    var rdx = (
        look.fx + ndc_x * aspect * tan_f * look.rx + ndc_y * tan_f * look.ux
    )
    var rdy = (
        look.fy + ndc_x * aspect * tan_f * look.ry + ndc_y * tan_f * look.uy
    )
    var rdz = (
        look.fz + ndc_x * aspect * tan_f * look.rz + ndc_y * tan_f * look.uz
    )
    var rd = _unit(rdx, rdy, rdz)
    var wdy = rd.y
    if wdy > -0.0015:
        wdy = -0.0015
    var wd = _unit(rd.x, wdy, rd.z)
    var t = -look.py / wd.y
    var hit_x = Float32(0.0)
    var hit_z = Float32(0.0)
    var height = Float32(0.0)
    for _step in range(3):  # pragma: no branch
        hit_x = look.px + wd.x * t
        hit_z = look.pz + wd.z * t
        height = _wave_height(surface, ripples, hit_x, hit_z)
        t = (height - look.py) / wd.y
    var slope = _wave_slope(surface, ripples, hit_x, hit_z, t)
    var normal = _unit(-slope.x, 1.0, -slope.y)
    var vx = -wd.x
    var vy = -wd.y
    var vz = -wd.z
    var nv = normal.x * vx + normal.y * vy + normal.z * vz
    if nv < 0.02:
        normal = _unit(
            normal.x + vx * (0.02 - nv),
            normal.y + vy * (0.02 - nv),
            normal.z + vz * (0.02 - nv),
        )
        nv = normal.x * vx + normal.y * vy + normal.z * vz
    var ior = water_ior()
    var f = fresnel(nv, ior)
    var reflected = _reflect(wd.x, wd.y, wd.z, normal)
    if reflected.y < 0.0:
        reflected = Vector3(reflected.x, -reflected.y, reflected.z)
    var sun = sun_direction()
    var sky = sky_radiance(reflected.x, reflected.y, reflected.z, sun)
    var refl = sky * 1.25
    var variance = slope.z
    var alpha2 = 0.00012 + 1.2 * variance
    var hx = vx + sun.x
    var hy = vy + sun.y
    var hz = vz + sun.z
    var half_v = _unit(hx, hy, hz)
    var nh = normal.x * half_v.x + normal.y * half_v.y + normal.z * half_v.z
    var nl = normal.x * sun.x + normal.y * sun.y + normal.z * sun.z
    if nh < 0.0:
        nh = 0.0
    if nl < 0.0:
        nl = 0.0
    var dist = beckmann(nh, alpha2)
    var vis = smith_visibility(nl, nv, alpha2)
    var fh = fresnel(
        max(half_v.x * vx + half_v.y * vy + half_v.z * vz, 0.0), ior
    )
    var spec = dist * vis * fh * nl
    var sun_rgb = Vector3(1.0, 0.90, 0.74) * (6.0 * spec)
    var under = _underwater(
        hit_x,
        hit_z,
        height,
        wd,
        normal,
        sun,
        caustics,
        ripples,
        clock,
    )
    var color = Vector3(
        f * refl.x + (1.0 - f) * under.x + sun_rgb.x,
        f * refl.y + (1.0 - f) * under.y + sun_rgb.y,
        f * refl.z + (1.0 - f) * under.z + sun_rgb.z,
    )
    var haze = 1.0 - exp(-t * 0.004)
    var flat = _unit(wd.x, 0.0, wd.z)
    var muh = flat.x * sun.x + flat.z * sun.z
    if muh < 0.0:
        muh = 0.0
    var haze_c = Vector3(0.60, 0.71, 0.82) + Vector3(1.0, 0.86, 0.66) * (
        0.22 * pow(muh, Float32(6)) + 0.3 * pow(muh, Float32(64))
    )
    var haze_w = haze * 0.8
    color = Vector3(
        color.x + (haze_c.x * 0.95 - color.x) * haze_w,
        color.y + (haze_c.y * 0.95 - color.y) * haze_w,
        color.z + (haze_c.z * 0.95 - color.z) * haze_w,
    )
    var above = sky_radiance(rd.x, rd.y, rd.z, sun)
    var mu = rd.x * sun.x + rd.y * sun.y + rd.z * sun.z
    var disc = smoothstep(0.99996, 0.999985, mu) * 18.0
    above = above + Vector3(1.0, 0.90, 0.74) * (6.0 * disc)
    var horizon = smoothstep(-0.0005, 0.0015, rd.y)
    return Vector3(
        color.x + (above.x - color.x) * horizon,
        color.y + (above.y - color.y) * horizon,
        color.z + (above.z - color.z) * horizon,
    )


def _wave_height(
    surface: SurfaceField, ripples: RippleField, x: Float32, z: Float32
) -> Float32:
    var a = sample_surface(surface, x, z)
    var b_uv_x = (0.8 * x + 0.6 * z) / (surface.patch.value * 0.41) + 0.37
    var b_uv_z = (-0.6 * x + 0.8 * z) / (surface.patch.value * 0.41) + 0.37
    var b = sample_surface(
        surface, b_uv_x * surface.patch.value, b_uv_z * surface.patch.value
    )
    var ripple = sample_ripple(ripples, x, z)
    return a.height + 0.10 * 0.41 * b.height + ripple.height


def _wave_slope(
    surface: SurfaceField,
    ripples: RippleField,
    x: Float32,
    z: Float32,
    dist: Float32,
) -> Vector3:
    var a = sample_surface(surface, x, z)
    # The second tile is `(M * xz) / (L * 0.41) + 0.37` in texture space.
    var b_uv_x = (0.8 * x + 0.6 * z) / (surface.patch.value * 0.41) + 0.37
    var b_uv_z = (-0.6 * x + 0.8 * z) / (surface.patch.value * 0.41) + 0.37
    var b = sample_surface(
        surface, b_uv_x * surface.patch.value, b_uv_z * surface.patch.value
    )
    var ripple = sample_ripple(ripples, x, z)
    var sx = (
        a.slope_x + 0.10 * (0.8 * b.slope_x + 0.6 * b.slope_z) + ripple.slope_x
    )
    var sz = (
        a.slope_z + 0.10 * (-0.6 * b.slope_x + 0.8 * b.slope_z) + ripple.slope_z
    )
    var c_uv_x = (0.28 * x - 0.96 * z) / (surface.patch.value * 0.13) + 0.71
    var c_uv_z = (0.96 * x + 0.28 * z) / (surface.patch.value * 0.13) + 0.71
    var c = sample_surface(
        surface, c_uv_x * surface.patch.value, c_uv_z * surface.patch.value
    )
    var detail = 0.13 * exp(-dist * 0.18)
    sx += detail * (0.28 * c.slope_x - 0.96 * c.slope_z)
    sz += detail * (0.96 * c.slope_x + 0.28 * c.slope_z)
    var variance = slope_variance(a) + 0.01 * slope_variance(b)
    return Vector3(sx, sz, variance)


def _underwater(
    x: Float32,
    z: Float32,
    height: Float32,
    wd: Vector3,
    normal: Vector3,
    sun: Vector3,
    caustics: CausticField,
    ripples: RippleField,
    clock: Duration,
) -> Vector3:
    # Air into water cannot totally reflect, and a downward view stays downward.
    var ray = refract(
        wd.x, wd.y, wd.z, normal.x, normal.y, normal.z, 1.0 / water_ior()
    )
    var bed_x = x
    var bed_z = z
    var travel = Float32(0.0)
    for _i in range(2):  # pragma: no branch
        var depth = floor_depth(bed_x, bed_z)
        travel = (-depth - height) / ray.y
        if travel < 0.0:
            travel = 0.0
        bed_x = x + ray.x * travel
        bed_z = z + ray.z * travel
    var bed = bed_color(bed_x, bed_z)
    var sun_ray = refract(0.0, -1.0, 0.0, 0.0, 1.0, 0.0, 1.0 / water_ior())
    var ts = 1.0 - fresnel(sun.y, water_ior())
    var column = height - (-floor_depth(bed_x, bed_z))
    if column < 0.0:
        column = 0.0
    var cu = (bed_x - caustics.shift_x) / caustics.patch
    var cv = (bed_z - caustics.shift_z) / caustics.patch
    var caus = _caustic_at(caustics, cu, cv)
    var entered = sample_ripple(ripples, bed_x, bed_z)
    var focus = 1.0 / (1.0 + 0.12 * column * entered.laplacian)
    if focus < 0.45:
        focus = 0.45
    if focus > 3.0:
        focus = 3.0
    caus = Vector3(caus.x * focus, caus.y * focus, caus.z * focus)
    var sig_a = Vector3(0.40, 0.074, 0.088)
    var sig_s = Vector3(0.028, 0.052, 0.068)
    var sig_t = sig_a + sig_s
    # A vertical sun ray refracts straight down, so its y component is -1.
    var sun_t_y = sun_ray.y
    var absorb = _exp3(sig_t * (column / -sun_t_y))
    var ao = 0.55 + 0.45 * smoothstep(0.08, 0.42, bed.height)
    var sun_light = Vector3(6.0, 5.4, 4.44) * ts
    var esun = Vector3(
        sun_light.x * absorb.x * caus.x * (-sun_t_y) * (0.75 + 0.25 * ao),
        sun_light.y * absorb.y * caus.y * (-sun_t_y) * (0.75 + 0.25 * ao),
        sun_light.z * absorb.z * caus.z * (-sun_t_y) * (0.75 + 0.25 * ao),
    )
    var sky_abs = _exp3((sig_a + sig_s * 0.4) * (column * 1.25))
    var sky_gain = Float32(3.14159265 * 0.22) * ao
    var esky = Vector3(
        0.62 * sky_gain * sky_abs.x,
        0.70 * sky_gain * sky_abs.y,
        0.78 * sky_gain * sky_abs.z,
    )
    var pi = Float32(3.141592653589793)
    var floor_l = Vector3(
        bed.r / pi * (esun.x + esky.x),
        bed.g / pi * (esun.y + esky.y),
        bed.b / pi * (esun.z + esky.z),
    )
    var view_abs = _exp3(sig_t * travel)
    var cos_s = (
        sun_ray.x * (-ray.x) + sun_ray.y * (-ray.y) + sun_ray.z * (-ray.z)
    )
    var g = Float32(0.8)
    var phase = (1.0 - g * g) / (
        4.0 * pi * pow(1.0 + g * g - 2.0 * g * cos_s, Float32(1.5))
    )
    var mid = sun_light * ts * phase
    var scatter = Vector3(
        sig_s.x / sig_t.x * mid.x * (1.0 - view_abs.x) * 3.2,
        sig_s.y / sig_t.y * mid.y * (1.0 - view_abs.y) * 3.2,
        sig_s.z / sig_t.z * mid.z * (1.0 - view_abs.z) * 3.2,
    )
    var color = Vector3(
        floor_l.x * view_abs.x + scatter.x,
        floor_l.y * view_abs.y + scatter.y,
        floor_l.z * view_abs.z + scatter.z,
    )
    return _specks(color, x, z, ray, travel, clock, sun_light * ts)


def _specks(
    color: Vector3,
    x: Float32,
    z: Float32,
    ray: Refracted,
    travel: Float32,
    clock: Duration,
    sun: Vector3,
) -> Vector3:
    var out = color
    var t = clock.value
    for k in range(3):  # pragma: no branch
        var dz = 0.22 + 0.38 * Float32(k)
        var denom = -ray.y
        if denom < 0.05:
            denom = 0.05
        var tt = dz / denom
        var qx = (
            (x + ray.x * tt) * 48.0
            + t * (0.05 + 0.03 * Float32(k))
            + Float32(k) * 17.0
        )
        var qz = (z + ray.z * tt) * 48.0 + t * 0.02 + Float32(k) * 17.0
        var ix = floor_f(qx)
        var iz = floor_f(qz)
        var fx = qx - ix - 0.5
        var fz = qz - iz - 0.5
        var chance = hash12(ix + Float32(k) * 13.1, iz)
        var ox = hash12(ix + 3.1, iz) - 0.5
        var oz = hash12(ix, iz + 7.7) - 0.5
        var d = sqrt(
            (fx - ox * 0.6) * (fx - ox * 0.6)
            + (fz - oz * 0.6) * (fz - oz * 0.6)
        )
        if chance > 0.988 and d < 0.10 and tt <= travel:
            var tint = Vector3(0.9, 1.0, 0.95)
            if chance > 0.992:
                tint = Vector3(0.4, 0.35, 0.3)
            var gain = exp(-0.074 * tt * 2.0) * 0.022
            out = out + tint * gain * sun.x
    return out


def floor_f(value: Float32) -> Float32:
    """Return the greatest integer float not above `value`.

    Args:
        value: Any finite float.

    Returns:
        `floor(value)` as a float. Exposed so a test can pin the speck grid.
    """
    from std.math import floor

    return floor(value)


def _caustic_at(field: CausticField, u: Float32, v: Float32) -> Vector3:
    var fu = u - _floor_wrap(u)
    var fv = v - _floor_wrap(v)
    var n = field.n
    # `fu` is in `[0, 1)`, so the product stays inside the texture.
    var x = Int(fu * Float32(n)) % n
    var y = Int(fv * Float32(n)) % n
    return Vector3(
        field.channel(x, y, 0), field.channel(x, y, 1), field.channel(x, y, 2)
    )


def _floor_wrap(value: Float32) -> Float32:
    from std.math import floor

    return floor(value)


def _exp3(v: Vector3) -> Vector3:
    return Vector3(exp(-v.x), exp(-v.y), exp(-v.z))


def _reflect(ix: Float32, iy: Float32, iz: Float32, normal: Vector3) -> Vector3:
    var dot = normal.x * ix + normal.y * iy + normal.z * iz
    return Vector3(
        ix - 2.0 * dot * normal.x,
        iy - 2.0 * dot * normal.y,
        iz - 2.0 * dot * normal.z,
    )


def _unit(x: Float32, y: Float32, z: Float32) -> Vector3:
    var out = Vector3(x, y, z)
    out.normalize()
    return out


def grade_pixel(
    r: Float32,
    g: Float32,
    b: Float32,
    glare_r: Float32,
    glare_g: Float32,
    glare_b: Float32,
    bloom_r: Float32,
    bloom_g: Float32,
    bloom_b: Float32,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    clock: Duration,
    view: WaterView,
) -> Vector3:
    """Apply Clearwater's tone curve to one pixel.

    Args:
        r: Linear red.
        g: Linear green.
        b: Linear blue.
        glare_r: Diffraction red, before the page's `1e3` gain.
        glare_g: Diffraction green.
        glare_b: Diffraction blue.
        bloom_r: Bloom red.
        bloom_g: Bloom green.
        bloom_b: Bloom blue.
        x: Pixel column.
        y: Pixel row, top down.
        width: Image width.
        height: Image height.
        clock: Frame time, mixed into the grain.
        view: `FRAME`, `LINEAR` or `GLARE`.

    Returns:
        Display-ready RGB in 0 to 1, already gamma encoded.
    """
    var cr = r
    var cg = g
    var cb = b
    if view == GLARE:
        cr = glare_r * 0.55 * 20.0 * 1000.0
        cg = glare_g * 0.55 * 20.0 * 1000.0
        cb = glare_b * 0.55 * 20.0 * 1000.0
    elif view == FRAME:
        cr += glare_r * 0.9 * 1000.0
        cg += glare_g * 0.9 * 1000.0
        cb += glare_b * 0.9 * 1000.0
        cr += bloom_r * 0.035
        cg += bloom_g * 0.035
        cb += bloom_b * 0.035
    cr *= 0.63
    cg *= 0.63
    cb *= 0.63
    var u = (Float32(x) + 0.5) / Float32(width) - 0.5
    var v = (Float32(y) + 0.5) / Float32(height) - 0.5
    var vig = 1.0 - 0.22 * (u * u + (v * 0.8) * (v * 0.8)) * 2.2
    cr *= vig
    cg *= vig
    cb *= vig
    cr = aces_channel(cr)
    cg = aces_channel(cg)
    cb = aces_channel(cb)
    var lum = cr * 0.2126 + cg * 0.7152 + cb * 0.0722
    cr = lum + (cr - lum) * 0.90
    cg = lum + (cg - lum) * 0.90
    cb = lum + (cb - lum) * 0.90
    var shadow = 1.0 - smoothstep(0.0, 0.35, lum)
    cr = cr + (cr * 0.96 - cr) * shadow
    cg = cg + (cg * 1.0 - cg) * shadow
    cb = cb + (cb * 1.05 - cb) * shadow
    var gamma = Float32(0.45454545)
    cr = pow(max(cr, 0.0), gamma)
    cg = pow(max(cg, 0.0), gamma)
    cb = pow(max(cb, 0.0), gamma)
    var grain = (
        hash12(Float32(x) + _fract_time(clock) * 917.0, Float32(y)) - 0.5
    )
    var amp = 0.018 * (1.0 - cr * 0.6)
    return Vector3(cr + grain * amp, cg + grain * amp, cb + grain * amp)


def _fract_time(clock: Duration) -> Float32:
    var t = clock.value * 7.13
    return t - floor_f(t)


def render_water(
    width: Int,
    height: Int,
    clock: Duration,
    view: WaterView,
    sway: Bool,
    ocean: SpectrumResolution,
    caustic_grid: Int,
    caustic_resolution: Int,
    glare_resolution: SpectrumResolution,
    drop: Bool,
) raises -> Framebuffer:
    """Draw one Clearwater picture.

    Args:
        width: Image width in pixels. It must be positive.
        height: Image height in pixels. It must be positive.
        clock: Seconds since the start.
        view: Which picture. See `WaterView`.
        sway: True adds the idle camera bob.
        ocean: Spectrum resolution.
        caustic_grid: Ray-grid cells on one side.
        caustic_resolution: Caustic texels on one side.
        glare_resolution: Diffraction FFT size.
        drop: True places one tap at the middle of the ripple window.

    Returns:
        A framebuffer of display-ready pixels. `CAUSTICS` is the raw
        texture scaled by 0.25, without the tone curve.

    Raises:
        Error: If a size or the view is not valid.
    """
    if width <= 0 or height <= 0:
        raise Error("Water image dimensions must be positive")
    require_view(view)
    var patch = Length(4.6)
    var depth = Length(1.6)
    var surface = water_surface(ocean, patch, shader_time(clock), 0.078)
    var ripples = RippleField(ocean, clearwater_ripple_size())
    var strength = Float32(0.0)
    if drop:
        strength = 0.07
    step_ripple(ripples, 0.0, 0.0, 0.5, 0.5, 0.022, strength)
    var sun = sun_direction()
    var caustics = render_caustics(
        surface, sun, depth, caustic_grid, caustic_resolution
    )
    if view == CAUSTICS:
        return _caustic_picture(width, height, caustics)
    var hdr = List[Float32](length=width * height * 3, fill=0.0)
    var look = camera_look(clock, sway)
    var aspect = Float32(width) / Float32(height)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var ndc_x = ((Float32(x) + 0.5) / Float32(width)) * 2.0 - 1.0
            var ndc_y = 1.0 - ((Float32(y) + 0.5) / Float32(height)) * 2.0
            var rgb = water_radiance(
                look, ndc_x, ndc_y, aspect, surface, ripples, caustics, clock
            )
            var p = (y * width + x) * 3
            hdr[p] = rgb.x
            hdr[p + 1] = rgb.y
            hdr[p + 2] = rgb.z
    var bright = _highlights(hdr, width, height, 2.5)
    var bloom = _blur(_blur(bright, width, height, True), width, height, False)
    var glare = List[Float32](length=width * height * 3, fill=0.0)
    if view == FRAME or view == GLARE:
        var kernels = glare_kernels(glare_resolution)
        var sparks = _highlights(hdr, width, height, 14.0)
        for i in range(len(sparks)):  # pragma: no branch
            sparks[i] *= 0.001
        glare = apply_glare(sparks, width, height, kernels)
    var image = Framebuffer(width, height, Color(0, 0, 0))
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var p = (y * width + x) * 3
            var graded = grade_pixel(
                hdr[p],
                hdr[p + 1],
                hdr[p + 2],
                glare[p],
                glare[p + 1],
                glare[p + 2],
                bloom[p],
                bloom[p + 1],
                bloom[p + 2],
                x,
                y,
                width,
                height,
                clock,
                view,
            )
            image.set_pixel(
                x,
                y,
                FloatColor(
                    clamp01(graded.x), clamp01(graded.y), clamp01(graded.z), 1.0
                ).quantize(),
            )
    return image^


def _caustic_picture(
    width: Int, height: Int, field: CausticField
) raises -> Framebuffer:
    var image = Framebuffer(width, height, Color(0, 0, 0))
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var u = (Float32(x) + 0.5) / Float32(width)
            var v = (Float32(y) + 0.5) / Float32(height)
            var sample = _caustic_at(field, u, v)
            image.set_pixel(
                x,
                y,
                FloatColor(
                    clamp01(sample.x * 0.25),
                    clamp01(sample.y * 0.25),
                    clamp01(sample.z * 0.25),
                    1.0,
                ).quantize(),
            )
    return image^


def _highlights(
    hdr: List[Float32], width: Int, height: Int, threshold: Float32
) -> List[Float32]:
    var out = List[Float32](length=width * height * 3, fill=0.0)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var r = Float32(0.0)
            var g = Float32(0.0)
            var b = Float32(0.0)
            var count = Float32(0.0)
            for oy in range(-1, 2):  # pragma: no branch
                for ox in range(-1, 2):  # pragma: no branch
                    var sx = x + ox
                    var sy = y + oy
                    if sx >= 0 and sy >= 0 and sx < width and sy < height:
                        var p = (sy * width + sx) * 3
                        r += hdr[p]
                        g += hdr[p + 1]
                        b += hdr[p + 2]
                        count += 1.0
            r /= count
            g /= count
            b /= count
            var l = max(r, max(g, b))
            var k = l - threshold
            if k < 0.0:
                k = 0.0
            # The brightest glint in this model stays under the page's 160 cap.
            k /= max(l, Float32(1e-4))
            out[(y * width + x) * 3] = r * k
            out[(y * width + x) * 3 + 1] = g * k
            out[(y * width + x) * 3 + 2] = b * k
    return out^


def _blur(
    src: List[Float32], width: Int, height: Int, horizontal: Bool
) -> List[Float32]:
    var out = List[Float32](length=width * height * 3, fill=0.0)
    var offsets = List[Int](length=5, fill=0)
    var weights = List[Float32](length=5, fill=0.0)
    offsets[0] = 0
    weights[0] = 0.2270270270
    offsets[1] = 1
    weights[1] = 0.3162162162
    offsets[2] = -1
    weights[2] = 0.3162162162
    offsets[3] = 3
    weights[3] = 0.0702702703
    offsets[4] = -3
    weights[4] = 0.0702702703
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var r = Float32(0.0)
            var g = Float32(0.0)
            var b = Float32(0.0)
            for tap in range(5):  # pragma: no branch
                var sx = x
                var sy = y
                if horizontal:
                    sx = x + offsets[tap]
                else:
                    sy = y + offsets[tap]
                if sx < 0:
                    sx = 0
                if sy < 0:
                    sy = 0
                if sx >= width:
                    sx = width - 1
                if sy >= height:
                    sy = height - 1
                var p = (sy * width + sx) * 3
                r += src[p] * weights[tap]
                g += src[p + 1] * weights[tap]
                b += src[p + 2] * weights[tap]
            var o = (y * width + x) * 3
            out[o] = r
            out[o + 1] = g
            out[o + 2] = b
    return out^
