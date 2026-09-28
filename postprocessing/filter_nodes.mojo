# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Filters from three.js r186's TSL display nodes, run as composer passes:
`CRT.js` with `Shape.js`'s `circle`, `radialBlur`, `BilateralBlurNode`,
`depthAwareBlur` and `depthAwareBlend`.

**The texture coordinate.** three.js's WebGPU `uv()` grows down the image.
Every function here takes `v_down` in that sense and reads the frame
through `sample_down`, so the arithmetic is three.js's as written.

**The CRT.** `CRT.js` gives five functions and no node. `crt_pixel` runs
them in the order three.js's documentation names them: the texture
coordinate is bent by `barrelUV`, the color is read there with
`colorBleeding`, darkened by `scanlines` and `vignette` at the bent
coordinate, and cut to black outside the screen by `barrelMask`.

**The depth-aware filters.** `depthAwareBlur` filters one channel, the
red. The pass runs it across and then down over red, green and blue alike.
`depthAwareBlend` mixes a color over the frame by a blend texture's red.
The pass reads that texture from the assets, as a texture pass reads its
own. Both read the depth through `perspectiveDepthToViewZ`, as three.js's
functions do, whatever the camera.
"""

from postprocessing.display_nodes import (
    exp_f,
    gaussian_coefficients,
    luminance_of,
)
from postprocessing.sampling import LightView, u_of
from postprocessing.screen_space import DepthView
from render.framebuffer import FloatColor
from render.target import RenderTarget
from std.math import floor, isfinite, max, min, sin, sqrt
from units.si import Length, METER


# --- the settings ------------------------------------------------------------


struct FilterSettings(ImplicitlyCopyable):
    """What the filter passes read, named as three.js names their
    parameters, with its defaults. Each pass reads its own settings."""

    # `barrelUV`'s `curvature`, `colorBleeding`'s `amount`, `scanlines`'
    # `intensity`, `count` and `speed`, and `vignette`'s `intensity` and
    # `smoothness`.
    var curvature: Float32
    var bleeding: Float32
    var scanline_intensity: Float32
    var scanline_count: Float32
    var scanline_speed: Float32
    var vignette_intensity: Float32
    var vignette_smoothness: Float32
    # The CRT's clock, three.js's `time`, in seconds: the composer moves it
    # on by each frame's time.
    var time: Float32
    # `radialBlur`'s `center`, down from the top as three.js's uv runs,
    # `weight`, `decay`, `count` and `exposure`, and `premultipliedAlpha`.
    var center_u: Float32
    var center_v: Float32
    var weight: Float32
    var decay: Float32
    var count: Int
    var exposure: Float32
    var premultiplied_alpha: Bool
    # `bilateralBlur`'s `directionNode`, `sigma` and `sigmaColor`.
    var direction: Float32
    var sigma: Float32
    var sigma_color: Float32
    # `depthAwareBlur`'s `sharpness` and `radius`.
    var sharpness: Float32
    var radius: Length
    # `depthAwareBlend`'s `blendColor`, linear, `edgeRadius` and
    # `edgeStrength`.
    var blend_r: Float32
    var blend_g: Float32
    var blend_b: Float32
    var edge_radius: Int
    var edge_strength: Float32

    def __init__(out self):
        """Start with three.js's defaults."""
        self.curvature = 0.1
        self.bleeding = 0.002
        self.scanline_intensity = 0.3
        self.scanline_count = 240
        self.scanline_speed = 0
        self.vignette_intensity = 0.4
        self.vignette_smoothness = 0.5
        self.time = 0
        self.center_u = 0.5
        self.center_v = 0.5
        self.weight = 0.9
        self.decay = 0.95
        self.count = 32
        self.exposure = 5
        self.premultiplied_alpha = False
        self.direction = 1
        self.sigma = 4
        self.sigma_color = 0.1
        self.sharpness = 2
        self.radius = Length(1, METER)
        self.blend_r = 1
        self.blend_g = 1
        self.blend_b = 1
        self.edge_radius = 2
        self.edge_strength = 2


def check_filters(settings: FilterSettings) raises:
    """Refuse settings no filter pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a number is not finite; the curvature is a half or more,
            where the barrel's corners fold; a radial blur counts no taps;
            a bilateral blur's sigmas are not positive; a depth-aware
            blur's radius is not positive; or a depth-aware blend's edge
            radius is negative.
    """
    var finite = (
        isfinite(settings.curvature)
        and isfinite(settings.bleeding)
        and isfinite(settings.scanline_intensity)
        and isfinite(settings.scanline_count)
        and isfinite(settings.scanline_speed)
        and isfinite(settings.vignette_intensity)
        and isfinite(settings.vignette_smoothness)
        and isfinite(settings.time)
        and isfinite(settings.center_u)
        and isfinite(settings.center_v)
        and isfinite(settings.weight)
        and isfinite(settings.decay)
        and isfinite(settings.exposure)
        and isfinite(settings.direction)
        and isfinite(settings.sigma)
        and isfinite(settings.sigma_color)
        and isfinite(settings.sharpness)
        and isfinite(settings.radius.value)
        and isfinite(settings.blend_r)
        and isfinite(settings.blend_g)
        and isfinite(settings.blend_b)
        and isfinite(settings.edge_strength)
    )
    if not finite:
        raise Error("A filter pass setting must be finite")
    if settings.curvature >= 0.5:
        raise Error("A CRT's curvature must be below a half")
    if settings.count < 1:
        raise Error("A radial blur takes at least one tap")
    if not (settings.sigma > 0 and settings.sigma_color > 0):
        raise Error("A bilateral blur's sigmas must be positive")
    if not (settings.radius.value > 0):
        raise Error("A depth-aware blur's radius must be positive")
    if settings.edge_radius < 0:
        raise Error("A depth-aware blend's edge radius must not be negative")


# --- reading the frame -------------------------------------------------------


def sample_down(view: LightView, u: Float32, v_down: Float32) -> FloatColor:
    """Return the light at a texture coordinate that grows down the image,
    as three.js's WebGPU `texture` reads it.

    Args:
        view: The frame.
        u: Across, zero at the left edge.
        v_down: Down, zero at the top edge.

    Returns:
        The bilinear blend there, held at the edges.
    """
    return view.tap(
        u * Float32(view.width) - 0.5, v_down * Float32(view.height) - 0.5
    )


def interleaved_gradient_noise(x: Float32, y: Float32) -> Float32:
    """Return three.js's `interleavedGradientNoise` at a screen position.

    Args:
        x: The column, at the pixel's center: `screenCoordinate.x`.
        y: The row, down from the top, at the center.

    Returns:
        A number from zero up to one.
    """
    var inner = x * Float32(0.06711056) + y * Float32(0.00583715)
    inner = inner - floor(inner)
    var outer = Float32(52.9829189) * inner
    return outer - floor(outer)


# --- CRT ---------------------------------------------------------------------


def barrel_uv(
    curvature: Float32, u: Float32, v: Float32
) -> Tuple[Float32, Float32]:
    """Return a texture coordinate bent outward from the center: three.js's
    `barrelUV`.

    Args:
        curvature: How far the screen bulges; zero is flat.
        u: Across.
        v: Down.

    Returns:
        The bent coordinate, with the corners kept in place.
    """
    var cx = (u - 0.5) * 2
    var cy = (v - 0.5) * 2
    var r2 = cx * cx + cy * cy
    var distortion = 1 - r2 * curvature
    var corner = 1 - curvature * 2
    return (
        cx / distortion * corner * 0.5 + 0.5,
        cy / distortion * corner * 0.5 + 0.5,
    )


def barrel_mask(u: Float32, v: Float32) -> Float32:
    """Return one inside the screen and zero outside it: three.js's
    `barrelMask`.

    Args:
        u: Across.
        v: Down.

    Returns:
        The mask.
    """
    if u < 0 or u > 1 or v < 0 or v > 1:
        return 0
    return 1


def color_bleeding(
    source: LightView, u: Float32, v: Float32, amount: Float32
) -> FloatColor:
    """Return the color with the colors to its left smeared into it:
    three.js's `colorBleeding`, red furthest and blue least.

    Args:
        source: The frame, premultiplied.
        u: Across.
        v: Down.
        amount: How far apart the smeared taps are, in texture widths.

    Returns:
        The color, straight, each channel from zero to one, with the
        pixel's alpha.
    """
    var here = sample_down(source, u, v).unpremultiplied()
    var left1 = sample_down(source, u - amount, v).unpremultiplied()
    var left2 = sample_down(source, u - amount * 2, v).unpremultiplied()
    var left3 = sample_down(source, u - amount * 3, v).unpremultiplied()
    var r = here.r + left1.r * 0.4 + left2.r * 0.2 + left3.r * 0.1
    var g = here.g + left1.g * 0.25 + left2.g * 0.1
    var b = here.b + left1.b * 0.15
    return FloatColor(
        min(max(r / 1.7, 0), 1),
        min(max(g / 1.35, 0), 1),
        min(max(b / 1.15, 0), 1),
        here.a,
    )


def scanlines(
    intensity: Float32,
    count: Float32,
    speed: Float32,
    time: Float32,
    v: Float32,
) -> Float32:
    """Return what a scanline scales the color by: three.js's `scanlines`.

    Args:
        intensity: How dark the lines are.
        count: How many lines there are.
        speed: How fast they roll.
        time: The clock, in seconds.
        v: Down.

    Returns:
        The scale, `1 - (sin((v - time * speed) * count) / 2 + 1 / 2) *
        intensity`.
    """
    var line = sin((v - time * speed) * count)
    return 1 - (line * 0.5 + 0.5) * intensity


def circle(
    scale: Float32, softness: Float32, u: Float32, v: Float32
) -> Float32:
    """Return three.js's `circle`: one at the center, falling to zero past
    `scale`, over the last `softness` of it.

    Args:
        scale: The circle's size.
        softness: How soft its edge is.
        u: Across.
        v: Down.

    Returns:
        The gradient.
    """
    var du = u - 0.5
    var dv = v - 0.5
    var dist = sqrt(du * du + dv * dv) * 2
    return _smoothstep_any(scale, scale - softness * scale, dist)


def _smoothstep_any(edge0: Float32, edge1: Float32, x: Float32) -> Float32:
    """Return GLSL's `smoothstep` for edges in either order."""
    var t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)


def crt_vignette(
    intensity: Float32, smoothness: Float32, u: Float32, v: Float32
) -> Float32:
    """Return what the CRT's vignette scales the color by: three.js's
    `vignette`, one at the center and `1 - intensity` at the edge.

    Args:
        intensity: How dark the edge is.
        smoothness: How soft the falloff is.
        u: Across.
        v: Down.

    Returns:
        The scale.
    """
    var mask = circle(1.42, smoothness, u, v)
    return (1 - intensity) + intensity * mask


def crt_pixel(
    source: LightView, x: Int, y: Int, settings: FilterSettings
) -> FloatColor:
    """Return one pixel of the CRT. Both the composer and the GPU composer
    call this.

    Args:
        source: The frame, premultiplied.
        x: The column.
        y: The row, down from the top.
        settings: The curvature, bleeding, scanlines, vignette and clock.

    Returns:
        The pixel, premultiplied.
    """
    var u = u_of(x, source.width)
    var v = (Float32(y) + 0.5) / Float32(source.height)
    var bent = barrel_uv(settings.curvature, u, v)
    var bu = bent[0]
    var bv = bent[1]
    var color = color_bleeding(source, bu, bv, settings.bleeding)
    var scale = (
        scanlines(
            settings.scanline_intensity,
            settings.scanline_count,
            settings.scanline_speed,
            settings.time,
            bv,
        )
        * crt_vignette(
            settings.vignette_intensity, settings.vignette_smoothness, bu, bv
        )
        * barrel_mask(bu, bv)
    )
    return FloatColor(
        color.r * scale, color.g * scale, color.b * scale, color.a
    ).premultiplied()


def crt_light(mut frame: RenderTarget, settings: FilterSettings):
    """Run the CRT over the frame, every pixel reading the frame as it was
    before the pass.

    Args:
        frame: The frame, replaced.
        settings: The CRT's settings.
    """
    var before = frame.colors.copy()
    var view = LightView(before, frame.width, frame.height)
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            frame.colors[slot] = crt_pixel(view, x, y, settings)
            frame.data[slot] = False
    _ = before^


# --- radialBlur --------------------------------------------------------------


def _radial_tap(
    source: LightView, u: Float32, v: Float32, premultiplied: Bool
) -> FloatColor:
    """Return a radial blur's tap: the straight color three.js's texture
    holds, premultiplied again when the option asks."""
    var color = sample_down(source, u, v)
    if premultiplied:
        return color
    return color.unpremultiplied()


def radial_blur_pixel(
    source: LightView, x: Int, y: Int, settings: FilterSettings
) -> FloatColor:
    """Return one pixel of three.js's `radialBlur`: `count` taps walked
    toward the center, each weighed by `weight` times `decay` to the tap's
    number, started a noise's share of a step along, and mixed with twice
    the pixel. Both the composer and the GPU composer call this.

    Args:
        source: The frame, premultiplied.
        x: The column.
        y: The row, down from the top.
        settings: The center, weight, decay, count, exposure and whether
            the blur works on premultiplied light.

    Returns:
        The pixel, premultiplied.
    """
    var u = u_of(x, source.width)
    var v = (Float32(y) + 0.5) / Float32(source.height)
    var premultiplied = settings.premultiplied_alpha
    var base = _radial_tap(source, u, v, premultiplied)
    var count = Float32(settings.count)
    var step_u = (settings.center_u - u) / count
    var step_v = (settings.center_v - v) / count
    var noise = interleaved_gradient_noise(Float32(x) + 0.5, Float32(y) + 0.5)
    var su = u + step_u * noise
    var sv = v + step_v * noise
    var w = settings.weight
    var r = Float32(0)
    var g = Float32(0)
    var b = Float32(0)
    var a = Float32(0)
    for _ in range(settings.count):  # pragma: no branch
        su += step_u
        sv += step_v
        var tap = _radial_tap(source, su, sv, premultiplied)
        r += tap.r * w
        g += tap.g * w
        b += tap.b * w
        a += tap.a * w
        w *= settings.decay
    var scale = settings.exposure / count * 0.5
    var out = FloatColor(
        r * scale + base.r,
        g * scale + base.g,
        b * scale + base.b,
        a * scale + base.a,
    )
    # three.js's `unpremultiplyAlpha` with the option on; its color is
    # straight either way. The alpha the sum carries past one is shown as
    # one, as a canvas shows it.
    if premultiplied:
        out = out.unpremultiplied()
    return FloatColor(out.r, out.g, out.b, min(out.a, 1)).premultiplied()


def radial_blur_light(mut frame: RenderTarget, settings: FilterSettings):
    """Run `radialBlur` over the frame, every pixel reading the frame as
    it was before the pass.

    Args:
        frame: The frame, replaced.
        settings: The radial blur's settings.
    """
    var before = frame.colors.copy()
    var view = LightView(before, frame.width, frame.height)
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            frame.colors[slot] = radial_blur_pixel(view, x, y, settings)
            frame.data[slot] = False
    _ = before^


# --- BilateralBlurNode -------------------------------------------------------


def bilateral_pixel(
    source: LightView,
    x: Int,
    y: Int,
    step_u: Float32,
    step_v: Float32,
    weights: List[Float32],
    sigma_color: Float32,
) -> FloatColor:
    """Return one pixel of one of `BilateralBlurNode`'s two passes: the
    spatial Gaussian's taps, each weighed down by how unlike the center
    its luminance is.

    Args:
        source: What the pass reads, straight.
        x: The column.
        y: The row, down from the top.
        step_u: The step across, in texture widths.
        step_v: The step down, in texture heights.
        weights: The spatial weights, the center first.
        sigma_color: `sigmaColor`.

    Returns:
        The weighted mean, straight.
    """
    var u = u_of(x, source.width)
    var v = (Float32(y) + 0.5) / Float32(source.height)
    var center = sample_down(source, u, v)
    var center_luma = luminance_of(center.r, center.g, center.b)
    var total = weights[0]
    var r = center.r * weights[0]
    var g = center.g * weights[0]
    var b = center.b * weights[0]
    var a = center.a * weights[0]
    var factor = Float32(-0.5) / (sigma_color * sigma_color)
    for i in range(1, len(weights)):  # pragma: no branch
        var du = step_u * Float32(i)
        var dv = step_v * Float32(i)
        var ahead = sample_down(source, u + du, v + dv)
        var behind = sample_down(source, u - du, v - dv)
        var d1 = abs(luminance_of(ahead.r, ahead.g, ahead.b) - center_luma)
        var d2 = abs(luminance_of(behind.r, behind.g, behind.b) - center_luma)
        var w1 = weights[i] * exp_f(d1 * d1 * factor)
        var w2 = weights[i] * exp_f(d2 * d2 * factor)
        r += ahead.r * w1 + behind.r * w2
        g += ahead.g * w1 + behind.g * w2
        b += ahead.b * w1 + behind.b * w2
        a += ahead.a * w1 + behind.a * w2
        total += w1 + w2
    var share = max(total, Float32(0.0001))
    return FloatColor(r / share, g / share, b / share, a / share)


def bilateral_blur_light(mut frame: RenderTarget, settings: FilterSettings):
    """Run `BilateralBlurNode` over the frame: across, then down over what
    the first pass wrote.

    Args:
        frame: The frame, replaced.
        settings: The direction and the two sigmas.
    """
    var w = frame.width
    var h = frame.height
    var weights = gaussian_coefficients(settings.sigma)
    var straight = List[FloatColor](capacity=w * h)
    for slot in range(w * h):  # pragma: no branch
        straight.append(frame.straight_at(slot))
    var view = LightView(straight, w, h)
    var across = List[FloatColor](capacity=w * h)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            across.append(
                bilateral_pixel(
                    view,
                    x,
                    y,
                    settings.direction / Float32(w),
                    0,
                    weights,
                    settings.sigma_color,
                )
            )
    var across_view = LightView(across, w, h)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var slot = y * w + x
            frame.colors[slot] = bilateral_pixel(
                across_view,
                x,
                y,
                0,
                settings.direction / Float32(h),
                weights,
                settings.sigma_color,
            ).premultiplied()
            frame.data[slot] = False
    _ = straight^
    _ = across^


# --- depthAwareBlur and depthAwareBlend --------------------------------------


def perspective_depth_to_view_z(
    depth: Float32, near: Float32, far: Float32
) -> Float32:
    """Return three.js's `perspectiveDepthToViewZ`.

    Args:
        depth: The window depth.
        near: The camera's near distance.
        far: Its far distance.

    Returns:
        The view-space z, negative in front of the camera.
    """
    return (near * far) / ((far - near) * depth - far)


def view_z_to_orthographic_depth(
    view_z: Float32, near: Float32, far: Float32
) -> Float32:
    """Return three.js's `viewZToOrthographicDepth`.

    Args:
        view_z: The view-space z.
        near: The camera's near distance.
        far: Its far distance.

    Returns:
        The linear depth, zero at the near plane and one at the far.
    """
    return (view_z + near) / (near - far)


def _view_z_down(view: DepthView, u: Float32, v_down: Float32) -> Float32:
    """Return `perspectiveDepthToViewZ` of the depth at a coordinate that
    grows down."""
    return perspective_depth_to_view_z(
        view.depth_at(u, 1 - v_down), view.near, view.far
    )


def depth_aware_blur_value(
    values: List[Float32],
    width: Int,
    height: Int,
    view: DepthView,
    x: Int,
    y: Int,
    step_u: Float32,
    step_v: Float32,
    settings: FilterSettings,
) -> Float32:
    """Return one value of one pass of three.js's `depthAwareBlur`: five
    taps of a Gaussian along a step, each weighed down by how far its
    depth is from the center's, relative to the radius.

    Args:
        values: The channel, one float a pixel, row by row from the top,
            read bilinear.
        width: Its width in pixels.
        height: Its height.
        view: The frame's depth.
        x: The column.
        y: The row, down from the top.
        step_u: One texel's step across, in texture widths.
        step_v: One texel's step down.
        settings: The sharpness and the radius.

    Returns:
        The filtered value.
    """
    var u = u_of(x, width)
    var v = (Float32(y) + 0.5) / Float32(height)
    var center = _view_z_down(view, u, v)
    var total = Float32(0)
    var sum = Float32(0)
    for i in range(-2, 3):  # pragma: no branch
        var fi = Float32(i)
        var su = u + step_u * fi
        var sv = v + step_v * fi
        var spatial = exp_f(fi * fi * -0.5)
        var near = exp_f(
            -abs(_view_z_down(view, su, sv) - center)
            / settings.radius.value
            * settings.sharpness
        )
        var w = spatial * near
        sum += _value_at(values, width, height, su, sv) * w
        total += w
    return sum / max(total, Float32(0.0001))


def _value_at(
    values: List[Float32], width: Int, height: Int, u: Float32, v_down: Float32
) -> Float32:
    """Return one float a pixel read bilinear at a coordinate that grows
    down, held at the edges."""
    var px = min(max(u * Float32(width) - 0.5, 0), Float32(width - 1))
    var py = min(max(v_down * Float32(height) - 0.5, 0), Float32(height - 1))
    var x0 = Int(px)
    var y0 = Int(py)
    var fx = px - Float32(x0)
    var fy = py - Float32(y0)
    var x1 = min(x0 + 1, width - 1)
    var y1 = min(y0 + 1, height - 1)
    var top = (
        values[y0 * width + x0]
        + (values[y0 * width + x1] - values[y0 * width + x0]) * fx
    )
    var bottom = (
        values[y1 * width + x0]
        + (values[y1 * width + x1] - values[y1 * width + x0]) * fx
    )
    return top + (bottom - top) * fy


def depth_aware_blur_channel(
    values: List[Float32], view: DepthView, settings: FilterSettings
) -> List[Float32]:
    """Return a channel blurred by `depthAwareBlur` across and then down.

    Args:
        values: The channel, one float a pixel, the depth view's size.
        view: The frame's depth.
        settings: The sharpness and the radius.

    Returns:
        The blurred channel.
    """
    var w = view.width
    var h = view.height
    var across = List[Float32](capacity=w * h)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            across.append(
                depth_aware_blur_value(
                    values, w, h, view, x, y, 1 / Float32(w), 0, settings
                )
            )
    var down = List[Float32](capacity=w * h)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            down.append(
                depth_aware_blur_value(
                    across, w, h, view, x, y, 0, 1 / Float32(h), settings
                )
            )
    return down^


def depth_aware_blur_light(
    mut frame: RenderTarget, view: DepthView, settings: FilterSettings
):
    """Run `depthAwareBlur` across and down over the frame's red, green
    and blue, straight, keeping each pixel's alpha.

    Args:
        frame: The frame, replaced.
        view: The frame's depth.
        settings: The sharpness and the radius.
    """
    var count = frame.width * frame.height
    var reds = List[Float32](capacity=count)
    var greens = List[Float32](capacity=count)
    var blues = List[Float32](capacity=count)
    for slot in range(count):  # pragma: no branch
        var color = frame.straight_at(slot)
        reds.append(color.r)
        greens.append(color.g)
        blues.append(color.b)
    var r = depth_aware_blur_channel(reds, view, settings)
    var g = depth_aware_blur_channel(greens, view, settings)
    var b = depth_aware_blur_channel(blues, view, settings)
    for slot in range(count):  # pragma: no branch
        var alpha = frame.straight_at(slot).a
        frame.colors[slot] = FloatColor(
            r[slot], g[slot], b[slot], alpha
        ).premultiplied()
        frame.data[slot] = False


# `depthAwareBlend`'s Poisson disk, eight points.
comptime POISSON_X = SIMD[DType.float32, 8](
    0.493393,
    0.798547,
    0.259143,
    0.605322,
    -0.574681,
    -0.430397,
    -0.849487,
    0.170621,
)
comptime POISSON_Y = SIMD[DType.float32, 8](
    0.394269,
    0.885922,
    0.650754,
    0.023588,
    0.137452,
    -0.638423,
    -0.366258,
    -0.569941,
)


def depth_aware_blend_pixel(
    base: LightView,
    blend: LightView,
    view: DepthView,
    x: Int,
    y: Int,
    settings: FilterSettings,
) -> FloatColor:
    """Return one pixel of three.js's `depthAwareBlend`: the blend color
    mixed over the frame by the blend texture's red, read where the
    Poisson taps that share the pixel's depth push it.

    three.js divides the push by the count and calls `normalize` on the
    result without keeping it, so the push is the mean offset, not a unit
    one. This port keeps that.

    Args:
        base: The frame, straight.
        blend: The blend texture, at the frame's size.
        view: The frame's depth.
        x: The column.
        y: The row, down from the top.
        settings: The blend color, the edge radius and the edge strength.

    Returns:
        The pixel, straight.
    """
    var w = base.width
    var h = base.height
    var u = u_of(x, w)
    var v = (Float32(y) + 0.5) / Float32(h)
    var near = view.near
    var far = view.far
    var here = view_z_to_orthographic_depth(_view_z_down(view, u, v), near, far)
    var push_x = Float32(0)
    var push_y = Float32(0)
    var count = Float32(0)
    var reach = Float32(settings.edge_radius)
    for i in range(8):  # pragma: no branch
        var ox = POISSON_X[i] * reach
        var oy = POISSON_Y[i] * reach
        var there = view_z_to_orthographic_depth(
            _view_z_down(view, u + ox / Float32(w), v + oy / Float32(h)),
            near,
            far,
        )
        if abs(there - here) < 0.05 * here:
            push_x += ox
            push_y += oy
            count += 1
    if count == 0:
        count = 1
    push_x /= count
    push_y /= count
    var su = u
    var sv = v
    if sqrt(push_x * push_x + push_y * push_y) > 0:
        su = u + settings.edge_strength * push_x / Float32(w)
        sv = v + settings.edge_strength * push_y / Float32(h)
    var choice = sample_down(blend, su, sv).r
    var color = sample_down(base, u, v)
    return FloatColor(
        color.r + (settings.blend_r - color.r) * choice,
        color.g + (settings.blend_g - color.g) * choice,
        color.b + (settings.blend_b - color.b) * choice,
        color.a + (1 - color.a) * choice,
    )


def depth_aware_blend_light(
    mut frame: RenderTarget,
    view: DepthView,
    blend: List[FloatColor],
    settings: FilterSettings,
) raises:
    """Run `depthAwareBlend` over the frame.

    Args:
        frame: The frame, replaced.
        view: The frame's depth.
        blend: The blend texture sampled at the center of every pixel,
            row by row from the top.
        settings: The blend color, the edge radius and the edge strength.

    Raises:
        Error: If the blend texture does not have one texel a pixel.
    """
    var w = frame.width
    var h = frame.height
    if len(blend) != w * h:
        raise Error("A depth-aware blend needs one blend texel a pixel")
    var straight = List[FloatColor](capacity=w * h)
    for slot in range(w * h):  # pragma: no branch
        straight.append(frame.straight_at(slot))
    var base = LightView(straight, w, h)
    var mask = LightView(blend, w, h)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var slot = y * w + x
            frame.colors[slot] = depth_aware_blend_pixel(
                base, mask, view, x, y, settings
            ).premultiplied()
            frame.data[slot] = False
    _ = straight^
