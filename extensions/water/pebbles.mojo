# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clearwater's seamless pebble photograph, sampled in linear light.

The page stores a 1024 by 1024 sRGB JPEG and reads it as an sRGB texture,
so a sample is linear before the bed shader mixes sand and weed. The file
is `assets/pebbles.jpg`. It tiles every 0.78 m. The page also builds
mipmaps and samples them with anisotropy 16. `sample_pebble_grad` reads
texels through `PebbleTexels`, so the same arithmetic runs on a
`PebbleBed` and on a copy in device memory.
"""

from extensions.water.filter import (
    anisotropic_step,
    lod_blend,
    major_axis_offset,
)
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

    def mix(self, other: Self, t: Float32) -> Self:
        """Return this sample moved toward `other` by `t`.

        Args:
            other: The sample at `t` of one.
            t: How far from this sample toward `other`.

        Returns:
            The blend.
        """
        var s = 1.0 - t
        return Self(
            self.r * s + other.r * t,
            self.g * s + other.g * t,
            self.b * s + other.b * t,
        )


trait PebbleTexels:
    """Read access to the pebble photograph and its mipmaps.

    Level 0 is the photograph. Level `k` is the `k`th coarser mip.
    """

    def pebble_levels(self) -> Int:
        """Return how many mip levels follow the photograph.

        Returns:
            The count of coarser levels.
        """
        ...

    def pebble_width(self, level: Int) -> Int:
        """Return the texels across a level.

        Args:
            level: The level. Zero or less is the photograph.

        Returns:
            The width.
        """
        ...

    def pebble_height(self, level: Int) -> Int:
        """Return the texels down a level.

        Args:
            level: The level. Zero or less is the photograph.

        Returns:
            The height.
        """
        ...

    def pebble_texel(self, level: Int, x: Int, y: Int) -> PebbleSample:
        """Return one linear texel of a level.

        Args:
            level: The level. Zero or less is the photograph.
            x: Column inside that level.
            y: Row inside that level.

        Returns:
            The linear color.
        """
        ...


struct PebbleBed(Movable, PebbleTexels):
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

    def pebble_levels(self) -> Int:
        """Return how many mip levels follow the photograph.

        Returns:
            The count of coarser levels.
        """
        return len(self.mip_w)

    def pebble_width(self, level: Int) -> Int:
        """Return the texels across a level.

        Args:
            level: The level. Zero or less is the photograph.

        Returns:
            The width.
        """
        if level <= 0:
            return self.width
        return self.mip_w[level - 1]

    def pebble_height(self, level: Int) -> Int:
        """Return the texels down a level.

        Args:
            level: The level. Zero or less is the photograph.

        Returns:
            The height.
        """
        if level <= 0:
            return self.height
        return self.mip_h[level - 1]

    def pebble_texel(self, level: Int, x: Int, y: Int) -> PebbleSample:
        """Return one linear texel of a level.

        Args:
            level: The level. Zero or less is the photograph.
            x: Column inside that level.
            y: Row inside that level.

        Returns:
            The linear color.
        """
        return _level_texel(self, level, x, y)


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
    var x = fu * Float32(bed.width) - 0.5
    var y = fv * Float32(bed.height) - 0.5
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
    var top = s00.mix(s10, tx)
    var bottom = s01.mix(s11, tx)
    return top.mix(bottom, ty)


def _texel(bed: PebbleBed, x: Int, y: Int) -> PebbleSample:
    var at = (y * bed.width + x) * 3
    return PebbleSample(bed.pixels[at], bed.pixels[at + 1], bed.pixels[at + 2])


def sample_pebble_grad[
    B: PebbleTexels
](
    bed: B,
    u: Float32,
    v: Float32,
    du_dx: Float32,
    dv_dx: Float32,
    du_dy: Float32,
    dv_dy: Float32,
) -> PebbleSample:
    """Return one anisotropic mipmapped pebble sample.

    Parameters:
        B: The photograph storage.

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
        Float32(bed.pebble_width(0)),
        Float32(bed.pebble_height(0)),
        16.0,
        0.0,
        Float32(bed.pebble_levels()),
    )
    var acc = PebbleSample(0.0, 0.0, 0.0)
    var count = step.taps
    for i in range(count):  # pragma: no branch
        var o = major_axis_offset(i, count)
        var sample = _trilinear(bed, u + step.du * o, v + step.dv * o, step.lod)
        acc = _mix_add(acc, sample)
    var inv = 1.0 / Float32(count)
    return PebbleSample(acc.r * inv, acc.g * inv, acc.b * inv)


def _mix_add(a: PebbleSample, b: PebbleSample) -> PebbleSample:
    return PebbleSample(a.r + b.r, a.g + b.g, a.b + b.b)


def _trilinear[
    B: PebbleTexels
](bed: B, u: Float32, v: Float32, lod: Float32) -> PebbleSample:
    var levels = bed.pebble_levels()
    var i0, i1, frac = lod_blend(lod, levels)
    var a = _sample_level(bed, i0, u, v)
    var b = _sample_level(bed, i1, u, v)
    return a.mix(b, frac)


def _sample_level[
    B: PebbleTexels
](bed: B, level: Int, u: Float32, v: Float32) -> PebbleSample:
    var w = bed.pebble_width(level)
    var h = bed.pebble_height(level)
    var fu = u - floor(u)
    var fv = v - floor(v)
    var x = fu * Float32(w) - 0.5
    var y = fv * Float32(h) - 0.5
    var x0 = Int(floor(x)) % w
    var y0 = Int(floor(y)) % h
    var x1 = (x0 + 1) % w
    var y1 = (y0 + 1) % h
    var tx = x - floor(x)
    var ty = y - floor(y)
    var s00 = bed.pebble_texel(level, x0, y0)
    var s10 = bed.pebble_texel(level, x1, y0)
    var s01 = bed.pebble_texel(level, x0, y1)
    var s11 = bed.pebble_texel(level, x1, y1)
    var top = s00.mix(s10, tx)
    var bottom = s01.mix(s11, tx)
    return top.mix(bottom, ty)


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
