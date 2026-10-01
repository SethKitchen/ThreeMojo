# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clearwater's seamless pebble photograph, sampled in linear light.

The page stores a 1024 by 1024 sRGB JPEG and reads it as an sRGB texture,
so a sample is linear before the bed shader mixes sand and weed. The file
is `assets/pebbles.jpg`. It tiles every 0.78 m. The page also builds
mipmaps and samples them with anisotropy 16.
"""

from extensions.water.filter import anisotropic_step
from render.png import DecodedImage
from render.srgb import srgb_to_linear
from std.math import floor


struct PebbleSample(ImplicitlyCopyable):
    """One linear pebble color."""

    var r: Float32
    var g: Float32
    var b: Float32

    def __init__(out self, r: Float32, g: Float32, b: Float32):
        """Store one linear sample.

        Args:
            r: Linear red.
            g: Linear green.
            b: Linear blue.
        """
        self.r = r
        self.g = g
        self.b = b


struct PebbleBed(Movable):
    """The pebble photograph in linear RGB, row-major from the top."""

    var width: Int
    var height: Int
    var pixels: List[Float32]
    var mip_w: List[Int]
    var mip_h: List[Int]
    var mip_off: List[Int]
    var mip_px: List[Float32]

    def __init__(
        out self, width: Int, height: Int, var pixels: List[Float32]
    ) raises:
        """Adopt a linear RGB image.

        Args:
            width: Texels across. It must be positive.
            height: Texels down. It must be positive.
            pixels: `width * height * 3` linear channels, row-major.

        Raises:
            Error: If a dimension is not positive, or the buffer length
                does not match the dimensions.
        """
        if width <= 0:
            raise Error("Pebble image width must be positive")
        if height <= 0:
            raise Error("Pebble image height must be positive")
        if len(pixels) != width * height * 3:
            raise Error("Pebble image length does not match its dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels^
        self.mip_w = List[Int]()
        self.mip_h = List[Int]()
        self.mip_off = List[Int]()
        self.mip_px = List[Float32]()
        _fill_mips(self)


def pebble_bed(image: DecodedImage) raises -> PebbleBed:
    """Return a pebble bed from an sRGB image.

    Args:
        image: Eight-bit RGBA. Color bytes are sRGB, as a JPEG stores them.

    Returns:
        Linear RGB. Alpha is dropped.

    Raises:
        Error: If a dimension is not positive, or the buffer is not one
            RGBA sample per texel.
    """
    if image.width <= 0:
        raise Error("Pebble image width must be positive")
    if image.height <= 0:
        raise Error("Pebble image height must be positive")
    if len(image.pixels) != image.width * image.height * DecodedImage.CHANNELS:
        raise Error("Pebble image length does not match its dimensions")
    var count = image.width * image.height
    var pixels = List[Float32](length=count * 3, fill=0.0)
    for index in range(count):  # pragma: no branch
        var at = index * DecodedImage.CHANNELS
        pixels[index * 3] = srgb_to_linear(Float32(image.pixels[at]) / 255.0)
        pixels[index * 3 + 1] = srgb_to_linear(
            Float32(image.pixels[at + 1]) / 255.0
        )
        pixels[index * 3 + 2] = srgb_to_linear(
            Float32(image.pixels[at + 2]) / 255.0
        )
    return PebbleBed(image.width, image.height, pixels^)


def sample_pebble(bed: PebbleBed, u: Float32, v: Float32) -> PebbleSample:
    """Return one bilinear pebble sample. The texture repeats.

    Args:
        bed: A linear pebble image.
        u: Horizontal texture coordinate. It repeats every 1.
        v: Vertical texture coordinate. It repeats every 1.

    Returns:
        The filtered linear color.
    """
    var fu = u - floor(u)
    var fv = v - floor(v)
    var x = fu * Float32(bed.width)
    var y = fv * Float32(bed.height)
    var x0 = Int(floor(x)) % bed.width
    var y0 = Int(floor(y)) % bed.height
    var x1 = (x0 + 1) % bed.width
    var y1 = (y0 + 1) % bed.height
    var tx = x - floor(x)
    var ty = y - floor(y)
    var s00 = _texel(bed, x0, y0)
    var s10 = _texel(bed, x1, y0)
    var s01 = _texel(bed, x0, y1)
    var s11 = _texel(bed, x1, y1)
    var top = _mix_sample(s00, s10, tx)
    var bottom = _mix_sample(s01, s11, tx)
    return _mix_sample(top, bottom, ty)


def _texel(bed: PebbleBed, x: Int, y: Int) -> PebbleSample:
    var at = (y * bed.width + x) * 3
    return PebbleSample(bed.pixels[at], bed.pixels[at + 1], bed.pixels[at + 2])


def _mix_sample(a: PebbleSample, b: PebbleSample, t: Float32) -> PebbleSample:
    var s = 1.0 - t
    return PebbleSample(a.r * s + b.r * t, a.g * s + b.g * t, a.b * s + b.b * t)


def sample_pebble_grad(
    bed: PebbleBed,
    u: Float32,
    v: Float32,
    du_dx: Float32,
    dv_dx: Float32,
    du_dy: Float32,
    dv_dy: Float32,
) -> PebbleSample:
    """Return one anisotropic mipmapped pebble sample.

    Args:
        bed: A linear pebble image.
        u: Horizontal texture coordinate. It repeats every 1.
        v: Vertical texture coordinate. It repeats every 1.
        du_dx: Change in `u` for one pixel to the right.
        dv_dx: Change in `v` for one pixel to the right.
        du_dy: Change in `u` for one pixel up.
        dv_dy: Change in `v` for one pixel up.

    Returns:
        The filtered linear color. A zero footprint is the bilinear sample.
    """
    var step = anisotropic_step(
        du_dx,
        dv_dx,
        du_dy,
        dv_dy,
        Float32(bed.width),
        Float32(bed.height),
        16.0,
        0.0,
        Float32(len(bed.mip_w)),
    )
    var acc = PebbleSample(0.0, 0.0, 0.0)
    var count = step.taps
    for i in range(count):  # pragma: no branch
        var o = (Float32(i) + 0.5) / Float32(count) - 0.5
        var sample = _trilinear(bed, u + step.du * o, v + step.dv * o, step.lod)
        acc = _mix_add(acc, sample)
    var inv = 1.0 / Float32(count)
    return PebbleSample(acc.r * inv, acc.g * inv, acc.b * inv)


def _mix_add(a: PebbleSample, b: PebbleSample) -> PebbleSample:
    return PebbleSample(a.r + b.r, a.g + b.g, a.b + b.b)


def _trilinear(
    bed: PebbleBed, u: Float32, v: Float32, lod: Float32
) -> PebbleSample:
    var levels = len(bed.mip_w)
    var i0 = Int(floor(lod))
    var i1 = i0 + 1
    if i1 > levels:
        i1 = levels
    var frac = lod - Float32(i0)
    var a = _sample_level(bed, i0, u, v)
    var b = _sample_level(bed, i1, u, v)
    return _mix_sample(a, b, frac)


def _sample_level(
    bed: PebbleBed, level: Int, u: Float32, v: Float32
) -> PebbleSample:
    var w = bed.width
    var h = bed.height
    if level > 0:
        w = bed.mip_w[level - 1]
        h = bed.mip_h[level - 1]
    var fu = u - floor(u)
    var fv = v - floor(v)
    var x = fu * Float32(w)
    var y = fv * Float32(h)
    var x0 = Int(floor(x)) % w
    var y0 = Int(floor(y)) % h
    var x1 = (x0 + 1) % w
    var y1 = (y0 + 1) % h
    var tx = x - floor(x)
    var ty = y - floor(y)
    var s00 = _level_texel(bed, level, x0, y0)
    var s10 = _level_texel(bed, level, x1, y0)
    var s01 = _level_texel(bed, level, x0, y1)
    var s11 = _level_texel(bed, level, x1, y1)
    var top = _mix_sample(s00, s10, tx)
    var bottom = _mix_sample(s01, s11, tx)
    return _mix_sample(top, bottom, ty)


def _level_texel(bed: PebbleBed, level: Int, x: Int, y: Int) -> PebbleSample:
    if level <= 0:
        return _texel(bed, x, y)
    var w = bed.mip_w[level - 1]
    var at = bed.mip_off[level - 1] + (y * w + x) * 3
    return PebbleSample(bed.mip_px[at], bed.mip_px[at + 1], bed.mip_px[at + 2])


def _fill_mips(mut bed: PebbleBed):
    var w = bed.width
    var h = bed.height
    var level = 0
    for _step in range(16):  # pragma: no branch
        if w <= 1:
            if h <= 1:
                break
        var nw = w // 2
        var nh = h // 2
        if nw < 1:
            nw = 1
        if nh < 1:
            nh = 1
        var dst = List[Float32](length=nw * nh * 3, fill=0.0)
        for y in range(nh):  # pragma: no branch
            var y0 = y * h // nh
            var y1 = (y + 1) * h // nh
            for x in range(nw):  # pragma: no branch
                var x0 = x * w // nw
                var x1 = (x + 1) * w // nw
                var r = Float32(0.0)
                var g = Float32(0.0)
                var b = Float32(0.0)
                var count = Float32(0.0)
                for sy in range(y0, y1):  # pragma: no branch
                    for sx in range(x0, x1):  # pragma: no branch
                        var sample = _level_texel(bed, level, sx, sy)
                        r += sample.r
                        g += sample.g
                        b += sample.b
                        count += 1.0
                var inv = 1.0 / count
                var at = (y * nw + x) * 3
                dst[at] = r * inv
                dst[at + 1] = g * inv
                dst[at + 2] = b * inv
        bed.mip_off.append(len(bed.mip_px))
        bed.mip_w.append(nw)
        bed.mip_h.append(nh)
        for index in range(len(dst)):  # pragma: no branch
            bed.mip_px.append(dst[index])
        w = nw
        h = nh
        level += 1
