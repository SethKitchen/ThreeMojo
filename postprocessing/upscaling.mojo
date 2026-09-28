# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Spatial upscaling and sharpening: three.js r186's `SharpenNode` and
`FSR1Node`, from `examples/jsm/tsl/display/`.

**RCAS.** `SharpenNode` is AMD FidelityFX's robust contrast-adaptive
sharpening. Each pixel reads itself and its four neighbors in a cross. The
ring's darkest and brightest channels limit how far a negative lobe can
push the pixel before it rings. `sharpness` scales the lobe by
`2^-sharpness`: zero sharpens most, two hardly at all. With `denoise` on,
the lobe is weighed down where the ring's luminance is noisy.

**EASU.** `FSR1Node` runs edge-adaptive spatial upsampling first: each
output pixel reads twelve input texels round it, finds the direction and
the strength of the edge from their luminance, and weighs the texels by an
approximate Lanczos kernel stretched along the edge. The result is clamped
to the four nearest texels, so it does not ring. Then RCAS sharpens it.

**Two things this port adds.** A texel past the edge of the image is the
edge texel, as WebGPU's robust `textureLoad` gives it. And where a GPU's
`min` and `max` would meet a NaN from a division by zero, as RCAS's limits
do on a black ring, these take the other operand, as IEEE's `minNum` and
`maxNum` do. Both backends call the same functions.

**What each reads.** Both nodes read the texture three.js keeps straight,
so each tap is unpremultiplied first and the result is premultiplied
again for the frame. FSR1 reads the frame at `resolution_scale` of its
size, as a scene pass with `setResolutionScale` hands it over, and writes
it at the frame's size.
"""

from postprocessing.display_nodes import scaled_size
from postprocessing.sampling import LightView, u_of, v_of
from render.framebuffer import FloatColor
from render.target import RenderTarget
from std.math import floor, isfinite, pow, sqrt


# `RCAS_LIMIT`: how far the negative lobe may go, `0.25 - 1 / 16`.
comptime RCAS_LIMIT = Float32(0.25 - 1.0 / 16.0)


struct UpscaleSettings(ImplicitlyCopyable):
    """What a sharpen or an FSR1 pass reads, named as three.js names the
    nodes' parameters, with their defaults."""

    # `sharpness`: zero sharpens most, two hardly at all.
    var sharpness: Float32
    # `denoise`: whether the lobe is weighed down where the ring is noisy.
    var denoise: Bool
    # The share of the frame's size the FSR1 pass reads its input at, as
    # the scene pass it follows would have drawn it.
    var resolution_scale: Float32

    def __init__(out self):
        """Start with three.js's defaults."""
        self.sharpness = 0.2
        self.denoise = False
        self.resolution_scale = 1


def check_upscale(settings: UpscaleSettings) raises:
    """Refuse settings no sharpen or FSR1 pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the sharpness is negative or not finite, which could put
            RCAS's divisor at zero, or the resolution scale is not a
            positive finite number of at most one.
    """
    if not (isfinite(settings.sharpness) and settings.sharpness >= 0):
        raise Error("A sharpen pass's sharpness must not be negative")
    if not (
        isfinite(settings.resolution_scale)
        and settings.resolution_scale > 0
        and settings.resolution_scale <= 1
    ):
        raise Error("An FSR1 pass's resolution scale must be in (0, 1]")


def max_num(a: Float32, b: Float32) -> Float32:
    """Return the larger of two numbers, or the one that is a number when
    the other is a NaN: IEEE's `maxNum`, what a GPU's `max` gives.

    Args:
        a: The first operand.
        b: The second.

    Returns:
        The larger, ignoring a NaN.
    """
    if a != a:
        return b
    if b != b:
        return a
    return a if a > b else b


def min_num(a: Float32, b: Float32) -> Float32:
    """Return the smaller of two numbers, or the one that is a number when
    the other is a NaN: IEEE's `minNum`.

    Args:
        a: The first operand.
        b: The second.

    Returns:
        The smaller, ignoring a NaN.
    """
    if a != a:
        return b
    if b != b:
        return a
    return a if a < b else b


def load_straight(view: LightView, x: Int, y: Int) -> FloatColor:
    """Return a texel straight, the edge texel's past the edge: three.js's
    `textureLoad` on a texture it keeps straight, with WebGPU's robust
    access.

    Args:
        view: The frame, premultiplied.
        x: The column.
        y: The row, down from the top.

    Returns:
        The straight color.
    """
    var cx = min(max(x, 0), view.width - 1)
    var cy = min(max(y, 0), view.height - 1)
    return view.at(cx, cy).unpremultiplied()


def _luma2(color: FloatColor) -> Float32:
    """Return RCAS's luminance, times two: `g + (b + r) / 2`."""
    return color.g + (color.b + color.r) * 0.5


def _lobe_channel(
    b: Float32, d: Float32, e: Float32, f: Float32, h: Float32
) -> Float32:
    """Return one channel's `max(-hitMin, hitMax)`: how far the lobe may go
    before the channel leaves its ring's range."""
    var low = min_num(min_num(b, d), min_num(f, h))
    var high = max_num(max_num(b, d), max_num(f, h))
    var hit_min = min_num(low, e) / (high * 4)
    var hit_max = (1 - max_num(high, e)) / (low * 4 - 4)
    return max_num(-hit_min, hit_max)


def rcas_pixel(
    source: LightView, x: Int, y: Int, sharpness: Float32, denoise: Bool
) -> FloatColor:
    """Return one pixel of three.js's RCAS, `SharpenNode`'s only pass and
    `FSR1Node`'s second. Both the composer and the GPU composer call this.

    Args:
        source: The image, premultiplied, at the output's size.
        x: The column.
        y: The row, down from the top.
        sharpness: `sharpness`, zero or more.
        denoise: `denoise`.

    Returns:
        The sharpened pixel, premultiplied, with the pixel's own alpha.
    """
    var e = load_straight(source, x, y)
    var b = load_straight(source, x, y - 1)
    var d = load_straight(source, x - 1, y)
    var f = load_straight(source, x + 1, y)
    var h = load_straight(source, x, y + 1)
    var bl = _luma2(b)
    var dl = _luma2(d)
    var el = _luma2(e)
    var fl = _luma2(f)
    var hl = _luma2(h)
    var con = pow(Float32(2), -sharpness)
    var lobe_r = _lobe_channel(b.r, d.r, e.r, f.r, h.r)
    var lobe_g = _lobe_channel(b.g, d.g, e.g, f.g, h.g)
    var lobe_b = _lobe_channel(b.b, d.b, e.b, f.b, h.b)
    var lobe = (
        max_num(
            -RCAS_LIMIT,
            min_num(max_num(lobe_r, max_num(lobe_g, lobe_b)), Float32(0)),
        )
        * con
    )
    if denoise:
        var nz = (bl + dl + fl + hl) * 0.25 - el
        var nz_range = max(max(bl, dl), max(el, max(fl, hl))) - min(
            min(bl, dl), min(el, min(fl, hl))
        )
        var ratio = abs(nz) / max(nz_range, Float32(1.0 / 65536.0))
        lobe *= 1 - min(max(ratio, Float32(0)), Float32(1)) * 0.5
    var divisor = lobe * 4 + 1
    return FloatColor(
        ((b.r + d.r + f.r + h.r) * lobe + e.r) / divisor,
        ((b.g + d.g + f.g + h.g) * lobe + e.g) / divisor,
        ((b.b + d.b + f.b + h.b) * lobe + e.b) / divisor,
        e.a,
    ).premultiplied()


def sharpen_light(mut frame: RenderTarget, settings: UpscaleSettings):
    """Run three.js's `SharpenNode` over the frame, every pixel reading the
    frame as it was before the pass.

    Args:
        frame: The frame, replaced.
        settings: The sharpness and whether it denoises.
    """
    var before = frame.colors.copy()
    var view = LightView(before, frame.width, frame.height)
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            frame.colors[slot] = rcas_pixel(
                view, x, y, settings.sharpness, settings.denoise
            )
            frame.data[slot] = False
    _ = before^


# --- EASU --------------------------------------------------------------------


struct EasuEdge(ImplicitlyCopyable):
    """The edge EASU finds round an output pixel: its direction, not yet
    normalized, and its length, summed over four bilinear quadrants."""

    var dir_x: Float32
    var dir_y: Float32
    var length: Float32

    def __init__(out self):
        """Start with no edge."""
        self.dir_x = 0
        self.dir_y = 0
        self.length = 0

    def add(
        mut self,
        w: Float32,
        a: Float32,
        b: Float32,
        c: Float32,
        d: Float32,
        e: Float32,
    ):
        """Add one quadrant's edge: three.js's `_accumulateEdge`, over the
        luminance of the texels above, left of, at, right of and below
        its center.

        Args:
            w: The quadrant's bilinear weight.
            a: The texel above.
            b: The texel to the left.
            c: The center texel.
            d: The texel to the right.
            e: The texel below.
        """
        var tiny = Float32(1.0 / 65536.0)
        var dir_x = d - b
        var len_x = max(abs(d - c), abs(c - b))
        var s_len_x = min(abs(dir_x) / max(len_x, tiny), Float32(1))
        self.dir_x += dir_x * w
        self.length += s_len_x * s_len_x * w
        var dir_y = e - a
        var len_y = max(abs(e - c), abs(c - a))
        var s_len_y = min(abs(dir_y) / max(len_y, tiny), Float32(1))
        self.dir_y += dir_y * w
        self.length += s_len_y * s_len_y * w


def _easu_luma(color: FloatColor) -> Float32:
    """Return EASU's luminance: `r / 2 + g + b / 2`."""
    return color.r * 0.5 + color.g + color.b * 0.5


def easu_weight(
    offset_x: Float32,
    offset_y: Float32,
    dir_x: Float32,
    dir_y: Float32,
    len2_x: Float32,
    len2_y: Float32,
    lob: Float32,
    clp: Float32,
) -> Float32:
    """Return one tap's weight, three.js's `_accumulateTap`: an approximate
    Lanczos2 of the tap's distance, turned to the edge and stretched.

    Args:
        offset_x: The tap's offset from the output pixel, in texels across.
        offset_y: Its offset down.
        dir_x: The edge's direction, across.
        dir_y: Its direction down.
        len2_x: How far the kernel stretches along the edge.
        len2_y: How far it reaches across the edge.
        lob: The negative lobe's strength.
        clp: The distance squared past which the kernel is flat.

    Returns:
        The weight, negative in the lobe.
    """
    var vx = offset_x * dir_x + offset_y * dir_y
    var vy = -offset_x * dir_y + offset_y * dir_x
    var sx = vx * len2_x
    var sy = vy * len2_y
    var d2 = min(sx * sx + sy * sy, clp)
    var w_b = d2 * Float32(2.0 / 5.0) - 1
    var w_a = d2 * lob - 1
    return (
        (w_b * w_b * Float32(25.0 / 16.0) - Float32(25.0 / 16.0 - 1.0))
        * w_a
        * w_a
    )


def easu_pixel(
    source: LightView, x: Int, y: Int, width: Int, height: Int
) -> FloatColor:
    """Return one output pixel of three.js's EASU pass, `FSR1Node`'s first.

    Args:
        source: The input, premultiplied, at its own size.
        x: The output column.
        y: The output row, down from the top.
        width: The output's width in pixels.
        height: The output's height in pixels.

    Returns:
        The upsampled pixel, straight, clamped to its four nearest texels.
    """
    var ppx = u_of(x, width) * Float32(source.width) - 0.5
    var ppy = (Float32(y) + 0.5) / Float32(height) * Float32(source.height) - 0.5
    var fpx = floor(ppx)
    var fpy = floor(ppy)
    var fx = ppx - fpx
    var fy = ppy - fpy
    var ix = Int(fpx)
    var iy = Int(fpy)
    #       b c
    #     e f g h
    #     i j k l
    #       n o
    var s_b = load_straight(source, ix, iy - 1)
    var s_c = load_straight(source, ix + 1, iy - 1)
    var s_e = load_straight(source, ix - 1, iy)
    var s_f = load_straight(source, ix, iy)
    var s_g = load_straight(source, ix + 1, iy)
    var s_h = load_straight(source, ix + 2, iy)
    var s_i = load_straight(source, ix - 1, iy + 1)
    var s_j = load_straight(source, ix, iy + 1)
    var s_k = load_straight(source, ix + 1, iy + 1)
    var s_l = load_straight(source, ix + 2, iy + 1)
    var s_n = load_straight(source, ix, iy + 2)
    var s_o = load_straight(source, ix + 1, iy + 2)
    var bl = _easu_luma(s_b)
    var cl = _easu_luma(s_c)
    var el = _easu_luma(s_e)
    var fl = _easu_luma(s_f)
    var gl = _easu_luma(s_g)
    var hl = _easu_luma(s_h)
    var il = _easu_luma(s_i)
    var jl = _easu_luma(s_j)
    var kl = _easu_luma(s_k)
    var ll = _easu_luma(s_l)
    var nl = _easu_luma(s_n)
    var ol = _easu_luma(s_o)
    var edge = EasuEdge()
    edge.add((1 - fx) * (1 - fy), bl, el, fl, gl, jl)
    edge.add(fx * (1 - fy), cl, fl, gl, hl, kl)
    edge.add((1 - fx) * fy, fl, il, jl, kl, nl)
    edge.add(fx * fy, gl, jl, kl, ll, ol)
    var dir_x = edge.dir_x
    var dir_y = edge.dir_y
    var dir_sq = dir_x * dir_x + dir_y * dir_y
    var flat = dir_sq < Float32(1.0 / 32768.0)
    var r_dir_len = 1 / sqrt(max(dir_sq, Float32(1.0 / 32768.0)))
    if flat:
        dir_x = 1
    else:
        dir_x *= r_dir_len
        dir_y *= r_dir_len
    var length = edge.length * 0.5
    length *= length
    var stretch = (dir_x * dir_x + dir_y * dir_y) / max(abs(dir_x), abs(dir_y))
    var len2_x = 1 + (stretch - 1) * length
    var len2_y = 1 - length * 0.5
    var lob = 0.5 + Float32(1.0 / 4.0 - 0.04 - 0.5) * length
    var clp = 1 / lob
    var taps = List[FloatColor](capacity=12)
    taps.append(s_b)
    taps.append(s_c)
    taps.append(s_e)
    taps.append(s_f)
    taps.append(s_g)
    taps.append(s_h)
    taps.append(s_i)
    taps.append(s_j)
    taps.append(s_k)
    taps.append(s_l)
    taps.append(s_n)
    taps.append(s_o)
    # The twelve taps' offsets from the texel `f`, across and down.
    var across = SIMD[DType.int32, 16](
        0, 1, -1, 0, 1, 2, -1, 0, 1, 2, 0, 1, 0, 0, 0, 0
    )
    var down = SIMD[DType.int32, 16](
        -1, -1, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 0, 0, 0, 0
    )
    var r = Float32(0)
    var g = Float32(0)
    var b = Float32(0)
    var a = Float32(0)
    var total = Float32(0)
    # Twelve taps, fixed.
    for at in range(12):  # pragma: no branch
        var w = easu_weight(
            Float32(Int(across[at])) - fx,
            Float32(Int(down[at])) - fy,
            dir_x,
            dir_y,
            len2_x,
            len2_y,
            lob,
            clp,
        )
        var tap = taps[at]
        r += tap.r * w
        g += tap.g * w
        b += tap.b * w
        a += tap.a * w
        total += w
    r /= total
    g /= total
    b /= total
    a /= total
    return FloatColor(
        _clamp4(r, s_f.r, s_g.r, s_j.r, s_k.r),
        _clamp4(g, s_f.g, s_g.g, s_j.g, s_k.g),
        _clamp4(b, s_f.b, s_g.b, s_j.b, s_k.b),
        _clamp4(a, s_f.a, s_g.a, s_j.a, s_k.a),
    )


def _clamp4(
    value: Float32, p: Float32, q: Float32, s: Float32, t: Float32
) -> Float32:
    """Return a value clamped to the range of four others: EASU's
    anti-ringing clamp."""
    var low = min(min(p, q), min(s, t))
    var high = max(max(p, q), max(s, t))
    return min(max(value, low), high)


def fsr1_light(mut frame: RenderTarget, settings: UpscaleSettings):
    """Run three.js's `FSR1Node` over the frame: read the frame at the
    resolution scale, upsample it back to the frame's size with EASU, and
    sharpen it with RCAS.

    Args:
        frame: The frame, replaced.
        settings: The sharpness, whether RCAS denoises, and the scale the
            input is read at.
    """
    var w = frame.width
    var h = frame.height
    var in_w = scaled_size(w, settings.resolution_scale)
    var in_h = scaled_size(h, settings.resolution_scale)
    var before = frame.colors.copy()
    var view = LightView(before, w, h)
    # The input, as a pass drawn at the scale would hand it over.
    var small = List[FloatColor](capacity=in_w * in_h)
    for y in range(in_h):  # pragma: no branch
        for x in range(in_w):  # pragma: no branch
            small.append(view.sample(u_of(x, in_w), v_of(y, in_h)))
    var small_view = LightView(small, in_w, in_h)
    var easu = List[FloatColor](capacity=w * h)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            easu.append(easu_pixel(small_view, x, y, w, h).premultiplied())
    var easu_view = LightView(easu, w, h)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var slot = y * w + x
            frame.colors[slot] = rcas_pixel(
                easu_view, x, y, settings.sharpness, settings.denoise
            )
            frame.data[slot] = False
    _ = before^
    _ = small^
    _ = easu^
