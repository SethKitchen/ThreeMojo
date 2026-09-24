# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Textures with depth, from three.js `src/textures/Data3DTexture.js` and
`src/textures/DataArrayTexture.js`.

Both hold a block of texels `width` by `height` by `depth`, in a
`VolumeImage`, three.js's `texture.image`. They differ in what the third
coordinate means.

**A `Data3DTexture` is a volume.** A GLSL `sampler3D` reads it: the third
coordinate `r` runs from zero to one through the depth, as `s` and `t` run
through the width and the height. Under `BILINEAR`, three.js's
`LinearFilter`, a sample blends the eight texels around it, and `wrap_r`
resolves a coordinate outside the depth as `wrap_s` and `wrap_t` resolve
one outside the other two. A color lookup table is one: three.js's
`LUTPass` reads the frame's color as a coordinate into a cube of colors.

**A `DataArrayTexture` is a stack of images.** A GLSL `sampler2DArray`
reads it: the third coordinate is a layer number, rounded to the nearest
layer and held inside the stack, and a sample never blends two layers.

**Rows run up, as they are stored.** three.js sets `flipY` to false on
both, and WebGL does not flip a 3D upload at all. Texel `(x, y, z)` sits
at `((x + 0.5) / width, (y + 0.5) / height, (z + 0.5) / depth)`. That is
unlike `render.texture.Texture`, which reads its first row at the top.

**Filtering is straight, as a GPU filters.** GLSL's `texture` blends the
stored numbers of each channel on their own, and so does this. A 2D
`Texture` here blends premultiplied, because its alpha is coverage; a
volume's fourth channel is often density or data, and premultiplying it
would lose the color of a texel with zero alpha.

**Texels are bytes or floats.** A byte texture reads each byte as a
fraction of 255, through the sRGB curve when its color space is `SRGB`,
and alpha never through the curve. A float texture reads its numbers as
they are and must be `LINEAR`. See `render.texture.TexelType`.

**Not ported.** No mip chain: three.js turns `generateMipmaps` off for
both. One filter serves both magnification and minification. three.js's
`layerUpdates`, `addLayerUpdate` and `unpackAlignment` concern the upload
to WebGL and have no counterpart. The GPU backend's rasterizer samples
neither kind: three.js reads them only from a custom shader or from
`LUTPass`, and this port has no custom shaders. Its `LUTPass` reads a
`DecodedVolume` through the same `filter_volume` as the host.
"""

from render.framebuffer import FloatColor
from render.srgb import LINEAR, SRGB, ColorSpace, srgb_to_linear
from render.texture import (
    CLAMP,
    FLOAT_TYPE,
    NEAREST,
    UNSIGNED_BYTE_TYPE,
    Filter,
    TexelType,
    Wrap,
    mix,
    wrap_index,
)
from std.math import floor, isfinite


# How many numbers a stored texel holds: red, green, blue and alpha.
comptime VOLUME_CHANNELS = 4


def _check_extent(width: Int, height: Int, depth: Int, channels: Int) raises:
    """Refuse a block with no texels, or a channel count no format has.

    Args:
        width: Texels across.
        height: Texels up.
        depth: Texels deep, or layers.
        channels: Numbers given per texel.

    Raises:
        Error: If a dimension is not positive or `channels` is not one
            through four.
    """
    if width <= 0 or height <= 0 or depth <= 0:
        raise Error("A volume texture's dimensions must be positive")
    if channels < 1 or channels > VOLUME_CHANNELS:
        raise Error("A volume texture holds one through four numbers a texel")


struct VolumeImage(Movable):
    """The texels of a `Data3DTexture` or a `DataArrayTexture`: three.js's
    `texture.image`, `{ data, width, height, depth }`.

    Stored as RGBA, `x` fastest, then `y`, then `z`, as three.js uploads
    it. Build one with `of_bytes` or `of_floats`.
    """

    var width: Int
    var height: Int
    # Texels deep for a 3D texture, layers for an array texture.
    var depth: Int
    # Whether the texels are bytes in `pixels` or floats in `data`. The
    # other list is empty.
    var texel_type: TexelType
    var pixels: List[UInt8]
    var data: List[Float32]

    def __init__(out self, *, copy: Self):
        """Copy another image, texels included.

        Args:
            copy: The image to copy.
        """
        self.width = copy.width
        self.height = copy.height
        self.depth = copy.depth
        self.texel_type = copy.texel_type
        self.pixels = copy.pixels.copy()
        self.data = copy.data.copy()

    def __init__(
        out self,
        width: Int,
        height: Int,
        depth: Int,
        texel_type: TexelType,
        var pixels: List[UInt8],
        var data: List[Float32],
    ):
        """Hold texels as given, unchecked; `validate` checks them.

        Args:
            width: Texels across.
            height: Texels up.
            depth: Texels deep, or layers.
            texel_type: Which list holds the texels.
            pixels: RGBA bytes for `UNSIGNED_BYTE_TYPE`, else empty.
            data: RGBA floats for `FLOAT_TYPE`, else empty.
        """
        self.width = width
        self.height = height
        self.depth = depth
        self.texel_type = texel_type
        self.pixels = pixels^
        self.data = data^

    @staticmethod
    def of_bytes(
        width: Int,
        height: Int,
        depth: Int,
        pixels: List[UInt8],
        channels: Int = 4,
    ) raises -> VolumeImage:
        """Return an image of bytes, three.js's `UnsignedByteType`.

        A texel with fewer than four channels fills red first. A color
        channel it does not reach is zero and a missing alpha is 255, as
        WebGL samples a `RedFormat` or an `RGFormat` texture.

        Args:
            width: Texels across.
            height: Texels up.
            depth: Texels deep, or layers.
            pixels: `channels` bytes a texel, `x` fastest, then `y`, then
                `z`.
            channels: One through four.

        Returns:
            The image, stored RGBA.

        Raises:
            Error: If a dimension is not positive, `channels` is not one
                through four, or the length is not
                `width * height * depth * channels`.
        """
        _check_extent(width, height, depth, channels)
        var count = width * height * depth
        if len(pixels) != count * channels:
            raise Error(
                "A volume texture's length does not match its dimensions"
            )
        var stored = List[UInt8]()
        stored.reserve(count * VOLUME_CHANNELS)
        # The dimensions are positive, so neither loop runs zero times.
        for texel in range(count):  # pragma: no branch
            for channel in range(VOLUME_CHANNELS):  # pragma: no branch
                var byte = UInt8(0)
                if channel == 3:
                    byte = 255
                if channel < channels:
                    byte = pixels[texel * channels + channel]
                stored.append(byte)
        return VolumeImage(
            width,
            height,
            depth,
            UNSIGNED_BYTE_TYPE,
            stored^,
            List[Float32](),
        )

    @staticmethod
    def of_floats(
        width: Int,
        height: Int,
        depth: Int,
        data: List[Float32],
        channels: Int = 4,
    ) raises -> VolumeImage:
        """Return an image of floats, three.js's `FloatType`.

        Each number is kept as it is, above one included. A texel with
        fewer than four channels fills red first; a color channel it does
        not reach is zero and a missing alpha is one.

        Args:
            width: Texels across.
            height: Texels up.
            depth: Texels deep, or layers.
            data: `channels` numbers a texel, `x` fastest, then `y`, then
                `z`.
            channels: One through four.

        Returns:
            The image, stored RGBA.

        Raises:
            Error: If a dimension is not positive, `channels` is not one
                through four, the length is not
                `width * height * depth * channels`, or a number is not
                finite.
        """
        _check_extent(width, height, depth, channels)
        var count = width * height * depth
        if len(data) != count * channels:
            raise Error(
                "A volume texture's length does not match its dimensions"
            )
        var stored = List[Float32]()
        stored.reserve(count * VOLUME_CHANNELS)
        # The dimensions are positive, so neither loop runs zero times.
        for texel in range(count):  # pragma: no branch
            for channel in range(VOLUME_CHANNELS):  # pragma: no branch
                var value = Float32(0)
                if channel == 3:
                    value = 1
                if channel < channels:
                    value = data[texel * channels + channel]
                    # An infinity or a NaN poisons every blend that
                    # reaches it.
                    if not isfinite(value):
                        raise Error(
                            "A float volume texture holds finite numbers"
                        )
                stored.append(value)
        return VolumeImage(
            width, height, depth, FLOAT_TYPE, List[UInt8](), stored^
        )

    def validate(self) raises:
        """Refuse an image whose fields were edited into nonsense.

        The fields are open, so a caller can change a dimension or the
        texel type after `of_bytes` checked them. Every texture that holds
        the image calls this before it is sampled from outside.

        Raises:
            Error: If a dimension is not positive, the texel type is none
                of the named values, or the list it names does not hold
                four numbers a texel.
        """
        _check_extent(self.width, self.height, self.depth, VOLUME_CHANNELS)
        if not self.texel_type.is_valid():
            raise Error(
                "A volume texture's texel type must be UNSIGNED_BYTE_TYPE or"
                " FLOAT_TYPE"
            )
        var length = self.width * self.height * self.depth * VOLUME_CHANNELS
        var held = len(self.pixels)
        if self.texel_type == FLOAT_TYPE:
            held = len(self.data)
        if held != length:
            raise Error(
                "A volume texture's length does not match its dimensions"
            )

    def _offset(self, x: Int, y: Int, z: Int) -> Int:
        """Return where texel `(x, y, z)` starts, all three inside."""
        return ((z * self.height + y) * self.width + x) * VOLUME_CHANNELS

    def _texel(self, x: Int, y: Int, z: Int, space: ColorSpace) -> FloatColor:
        """Return texel `(x, y, z)` as the color it samples as, unchecked.

        Floats as they are. Bytes as a fraction of 255, the color through
        the sRGB curve when `space` is `SRGB`; alpha never.

        Args:
            x: Column, inside the image.
            y: Row, up from the first, inside the image.
            z: Slice or layer, inside the image.
            space: The texture's color space.

        Returns:
            The color.
        """
        var at = self._offset(x, y, z)
        if self.texel_type == FLOAT_TYPE:
            return FloatColor(
                self.data[at],
                self.data[at + 1],
                self.data[at + 2],
                self.data[at + 3],
            )
        var r = Float32(self.pixels[at]) / 255
        var g = Float32(self.pixels[at + 1]) / 255
        var b = Float32(self.pixels[at + 2]) / 255
        var a = Float32(self.pixels[at + 3]) / 255
        if space == SRGB:
            return FloatColor(
                srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), a
            )
        return FloatColor(r, g, b, a)

    def _fetch(
        self, x: Int, y: Int, z: Int, space: ColorSpace
    ) raises -> FloatColor:
        """Return texel `(x, y, z)`, refusing an index outside the image.

        GLSL leaves an out-of-range `texelFetch` undefined; this refuses
        it.

        Args:
            x: Column.
            y: Row, up from the first.
            z: Slice or layer.
            space: The texture's color space.

        Returns:
            The color.

        Raises:
            Error: If an index is outside the image.
        """
        if (
            x < 0
            or x >= self.width
            or y < 0
            or y >= self.height
            or z < 0
            or z >= self.depth
        ):
            raise Error("Texel coordinate out of bounds")
        return self._texel(x, y, z, space)


def mix_straight_texels(
    near: FloatColor, far: FloatColor, t: Float32
) -> FloatColor:
    """Return one texel a fraction `t` of the way to another, every
    channel on its own, as a GPU filters.

    Args:
        near: The texel at `t` of zero.
        far: The texel at `t` of one.
        t: How far along.

    Returns:
        The blend, straight.
    """
    return FloatColor(
        mix(near.r, far.r, t),
        mix(near.g, far.g, t),
        mix(near.b, far.b, t),
        mix(near.a, far.a, t),
    )


def _check_modes(
    wraps: Bool, filter: Filter, space: ColorSpace, image: VolumeImage
) raises:
    """Refuse a texture's modes, as `Texture.validate` refuses a 2D one's.

    Args:
        wraps: Whether every wrap mode is one of the named values.
        filter: The filter.
        space: The color space.
        image: The texels.

    Raises:
        Error: If a wrap mode, the filter or the color space is none of
            the named values, a float image is not `LINEAR`, or the image
            fails `VolumeImage.validate`.
    """
    if not wraps:
        raise Error(
            "A volume texture's wrap modes must be REPEAT, CLAMP or MIRROR"
        )
    if not filter.magnifies():
        raise Error("A volume texture's filter must be NEAREST or BILINEAR")
    if not space.is_decodable():
        raise Error(
            "A volume texture needs a color space it can decode: SRGB or LINEAR"
        )
    image.validate()
    if image.texel_type == FLOAT_TYPE and space != LINEAR:
        raise Error("A float texture holds linear light: it must be LINEAR")


struct Data3DTexture(Movable, VolumeSampler, VolumeTexels):
    """A volume of texels sampled by three coordinates: three.js's
    `Data3DTexture`, as a GLSL `sampler3D` reads it.

    The defaults are three.js's: every edge clamped, nearest, `LINEAR`,
    which is what three.js's `NoColorSpace` reads as.
    """

    var image: VolumeImage
    # three.js's `wrapS`, `wrapT` and `wrapR`: across, up and deep.
    var wrap_s: Wrap
    var wrap_t: Wrap
    var wrap_r: Wrap
    # three.js's `magFilter` and `minFilter`, as one.
    var filter: Filter
    var color_space: ColorSpace

    def __init__(
        out self,
        var image: VolumeImage,
        wrap: Wrap = CLAMP,
        filter: Filter = NEAREST,
        color_space: ColorSpace = LINEAR,
    ) raises:
        """Create a 3D texture: three.js's `new Data3DTexture(data, width,
        height, depth)`.

        Args:
            image: The texels.
            wrap: How a coordinate outside zero to one is resolved, on all
                three axes. Set `wrap_s`, `wrap_t` or `wrap_r` afterward to
                differ.
            filter: `NEAREST` or `BILINEAR`.
            color_space: `LINEAR` or `SRGB`.

        Raises:
            Error: Everything `validate` raises.
        """
        self.image = image^
        self.wrap_s = wrap
        self.wrap_t = wrap
        self.wrap_r = wrap
        self.filter = filter
        self.color_space = color_space
        self.validate()

    def __init__(out self, *, copy: Self):
        """Copy another 3D texture, texels included.

        Args:
            copy: The texture to copy.
        """
        self.image = VolumeImage(copy=copy.image)
        self.wrap_s = copy.wrap_s
        self.wrap_t = copy.wrap_t
        self.wrap_r = copy.wrap_r
        self.filter = copy.filter
        self.color_space = copy.color_space

    def validate(self) raises:
        """Refuse modes or texels edited into nonsense since construction.

        Raises:
            Error: If a wrap mode, the filter or the color space is none of
                the named values, a float image is not `LINEAR`, or the
                image fails `VolumeImage.validate`.
        """
        _check_modes(
            self.wrap_s.is_valid()
            and self.wrap_t.is_valid()
            and self.wrap_r.is_valid(),
            self.filter,
            self.color_space,
            self.image,
        )

    def texel_fetch(self, x: Int, y: Int, z: Int) raises -> FloatColor:
        """Return one texel by index: GLSL's `texelFetch` at level zero.

        Args:
            x: Column.
            y: Row, up from the first.
            z: Slice.

        Returns:
            The color stored there.

        Raises:
            Error: If an index is outside the image.
        """
        return self.image._fetch(x, y, z, self.color_space)

    def texel_at(self, x: Int, y: Int, z: Int) -> FloatColor:
        """Return texel `(x, y, z)` as it samples, unchecked: what
        `filter_volume` reads.

        Args:
            x: Column, inside the image.
            y: Row, up from the first, inside the image.
            z: Slice, inside the image.

        Returns:
            The color.
        """
        return self.image._texel(x, y, z, self.color_space)

    def volume_width(self) -> Int:
        """Return how many texels across the volume is: three.js's
        `lutSize` for a color lookup table."""
        return self.image.width

    def sample(self, s: Float32, t: Float32, r: Float32) -> FloatColor:
        """Return the color at a coordinate: GLSL's `texture` on a
        `sampler3D`, by `filter_volume`.

        Args:
            s: Across, zero at the first column's edge.
            t: Up, zero at the first row's edge.
            r: Deep, zero at the first slice's edge.

        Returns:
            The color, straight.
        """
        return filter_volume(
            self,
            self.image.width,
            self.image.height,
            self.image.depth,
            self.wrap_s,
            self.wrap_t,
            self.wrap_r,
            self.filter,
            s,
            t,
            r,
        )


trait VolumeTexels:
    """Something `filter_volume` can read texels from: a `Data3DTexture`,
    which decodes its bytes as it reads, or a `DecodedVolume`, which holds
    them decoded, as a GPU kernel reads them."""

    def texel_at(self, x: Int, y: Int, z: Int) -> FloatColor:
        """Return texel `(x, y, z)` as it samples, all three inside.

        Args:
            x: Column.
            y: Row, up from the first.
            z: Slice.

        Returns:
            The color.
        """
        ...


trait VolumeSampler:
    """Something a color lookup reads: a volume's width and its `texture`
    reads. Both `Data3DTexture` and `DecodedVolume` are one, so `LUTPass`'s
    arithmetic is the same on the host and on the GPU."""

    def volume_width(self) -> Int:
        """Return how many texels across the volume is.

        Returns:
            The width.
        """
        ...

    def sample(self, s: Float32, t: Float32, r: Float32) -> FloatColor:
        """Return the color at a coordinate, as a `sampler3D` reads it.

        Args:
            s: Across.
            t: Up.
            r: Deep.

        Returns:
            The color, straight.
        """
        ...


def filter_volume[
    T: VolumeTexels
](
    texels: T,
    width: Int,
    height: Int,
    depth: Int,
    wrap_s: Wrap,
    wrap_t: Wrap,
    wrap_r: Wrap,
    filter: Filter,
    s: Float32,
    t: Float32,
    r: Float32,
) -> FloatColor:
    """Return the color at a coordinate: GLSL's `texture` on a
    `sampler3D`.

    Under `NEAREST`, the texel the coordinate lands in. Under `BILINEAR`,
    the eight around it blended by distance, the texel centers at
    half-integers: trilinear in the sense of three axes, not of mip
    levels. Each index is wrapped by its axis's mode.

    Args:
        texels: Where the texels are read from.
        width: Texels across.
        height: Texels up.
        depth: Texels deep.
        wrap_s: How a column outside the image is resolved.
        wrap_t: How a row outside the image is resolved.
        wrap_r: How a slice outside the image is resolved.
        filter: `NEAREST` or `BILINEAR`.
        s: Across, zero at the first column's edge.
        t: Up, zero at the first row's edge.
        r: Deep, zero at the first slice's edge.

    Returns:
        The color, straight.
    """
    var wide = Float32(width)
    var tall = Float32(height)
    var deep = Float32(depth)
    if filter == NEAREST:
        return texels.texel_at(
            wrap_index(Int(floor(s * wide)), width, wrap_s),
            wrap_index(Int(floor(t * tall)), height, wrap_t),
            wrap_index(Int(floor(r * deep)), depth, wrap_r),
        )
    var across = s * wide - 0.5
    var up = t * tall - 0.5
    var into = r * deep - 0.5
    var x = Int(floor(across))
    var y = Int(floor(up))
    var z = Int(floor(into))
    var fx = across - Float32(x)
    var fy = up - Float32(y)
    var fz = into - Float32(z)
    var x0 = wrap_index(x, width, wrap_s)
    var x1 = wrap_index(x + 1, width, wrap_s)
    var y0 = wrap_index(y, height, wrap_t)
    var y1 = wrap_index(y + 1, height, wrap_t)
    var z0 = wrap_index(z, depth, wrap_r)
    var z1 = wrap_index(z + 1, depth, wrap_r)
    var near = mix_straight_texels(
        mix_straight_texels(
            texels.texel_at(x0, y0, z0), texels.texel_at(x1, y0, z0), fx
        ),
        mix_straight_texels(
            texels.texel_at(x0, y1, z0), texels.texel_at(x1, y1, z0), fx
        ),
        fy,
    )
    var far = mix_straight_texels(
        mix_straight_texels(
            texels.texel_at(x0, y0, z1), texels.texel_at(x1, y0, z1), fx
        ),
        mix_straight_texels(
            texels.texel_at(x0, y1, z1), texels.texel_at(x1, y1, z1), fx
        ),
        fy,
    )
    return mix_straight_texels(near, far, fz)


def decoded_texels(volume: Data3DTexture) -> List[FloatColor]:
    """Return every texel of a 3D texture as it samples, `x` fastest,
    then `y`, then `z`: what a `DecodedVolume` reads, and what the GPU
    backend uploads for a LUT pass.

    Args:
        volume: The texture.

    Returns:
        The texels, `width` times `height` times `depth` of them.
    """
    var image = VolumeImage(copy=volume.image)
    var texels = List[FloatColor](
        capacity=image.width * image.height * image.depth
    )
    var z = 0
    while z < image.depth:
        var y = 0
        while y < image.height:
            var x = 0
            while x < image.width:
                texels.append(volume.texel_at(x, y, z))
                x += 1
            y += 1
        z += 1
    return texels^


struct DecodedVolume(ImplicitlyCopyable, VolumeSampler, VolumeTexels):
    """A 3D texture's texels already decoded, with its size, wrap modes
    and filter: how a GPU kernel reads a `Data3DTexture`.

    It does not own the texels: the list or the device buffer must
    outlive every read. Build its texels with `decoded_texels`.
    """

    var texels: Pointer[FloatColor, UntrackedOrigin[mut=False]]
    var width: Int
    var height: Int
    var depth: Int
    var wrap_s: Wrap
    var wrap_t: Wrap
    var wrap_r: Wrap
    var filter: Filter

    def __init__(out self, texels: List[FloatColor], volume: Data3DTexture):
        """View decoded texels with a texture's size and modes.

        Args:
            texels: The texture's `decoded_texels`. The list must outlive
                the view.
            volume: The texture.
        """
        self.texels = texels.unsafe_ptr().unsafe_origin_cast[
            UntrackedOrigin[mut=False]
        ]()
        self.width = volume.image.width
        self.height = volume.image.height
        self.depth = volume.image.depth
        self.wrap_s = volume.wrap_s
        self.wrap_t = volume.wrap_t
        self.wrap_r = volume.wrap_r
        self.filter = volume.filter

    def __init__(
        out self,
        *,
        floats: MutPointer[Float32, MutAnyOrigin],
        width: Int,
        height: Int,
        depth: Int,
        wrap_s: Wrap,
        wrap_t: Wrap,
        wrap_r: Wrap,
        filter: Filter,
    ):
        """View four floats a texel, as a device buffer holds them.

        Args:
            floats: The first texel's red. The memory must outlive the
                view.
            width: Texels across.
            height: Texels up.
            depth: Texels deep.
            wrap_s: How a column outside the image is resolved.
            wrap_t: How a row outside the image is resolved.
            wrap_r: How a slice outside the image is resolved.
            filter: `NEAREST` or `BILINEAR`.
        """
        self.texels = (
            floats.unsafe_bitcast[FloatColor]()
            .unsafe_mut_cast[False]()
            .unsafe_origin_cast[UntrackedOrigin[mut=False]]()
        )
        self.width = width
        self.height = height
        self.depth = depth
        self.wrap_s = wrap_s
        self.wrap_t = wrap_t
        self.wrap_r = wrap_r
        self.filter = filter

    def texel_at(self, x: Int, y: Int, z: Int) -> FloatColor:
        """Return texel `(x, y, z)`, unchecked.

        Args:
            x: Column, inside the image.
            y: Row, up from the first, inside the image.
            z: Slice, inside the image.

        Returns:
            The color.
        """
        return self.texels[unsafe_offset=(z * self.height + y) * self.width + x]

    def volume_width(self) -> Int:
        """Return how many texels across the volume is.

        Returns:
            The width.
        """
        return self.width

    def sample(self, s: Float32, t: Float32, r: Float32) -> FloatColor:
        """Return the color at a coordinate, by `filter_volume`, as
        `Data3DTexture.sample` returns it.

        Args:
            s: Across, zero at the first column's edge.
            t: Up, zero at the first row's edge.
            r: Deep, zero at the first slice's edge.

        Returns:
            The color, straight.
        """
        return filter_volume(
            self,
            self.width,
            self.height,
            self.depth,
            self.wrap_s,
            self.wrap_t,
            self.wrap_r,
            self.filter,
            s,
            t,
            r,
        )


def array_layer(layer: Float32, depth: Int) -> Int:
    """Return the layer a `sampler2DArray` reads for a layer coordinate.

    The OpenGL rule: round to the nearest whole number, then hold it
    inside the stack. `floor(layer + 0.5)`, so a half rounds up.

    Args:
        layer: The coordinate, a layer number, fractional.
        depth: How many layers there are; positive.

    Returns:
        A layer, zero through `depth - 1`.
    """
    var rounded = floor(layer + 0.5)
    if rounded < 0:
        return 0
    if rounded > Float32(depth - 1):
        return depth - 1
    return Int(rounded)


struct DataArrayTexture(Movable):
    """A stack of images sampled by two coordinates and a layer: three.js's
    `DataArrayTexture`, as a GLSL `sampler2DArray` reads it.

    The defaults are three.js's: clamped, nearest, `LINEAR`.
    """

    var image: VolumeImage
    # three.js's `wrapS` and `wrapT`. A layer is never wrapped: it is held
    # inside the stack, whatever three.js's `wrapR` says.
    var wrap_s: Wrap
    var wrap_t: Wrap
    var filter: Filter
    var color_space: ColorSpace

    def __init__(
        out self,
        var image: VolumeImage,
        wrap: Wrap = CLAMP,
        filter: Filter = NEAREST,
        color_space: ColorSpace = LINEAR,
    ) raises:
        """Create an array texture: three.js's `new DataArrayTexture(data,
        width, height, depth)`.

        Args:
            image: The texels, `depth` layers of `width` by `height`.
            wrap: How a coordinate outside zero to one is resolved, across
                and up.
            filter: `NEAREST` or `BILINEAR`, within a layer.
            color_space: `LINEAR` or `SRGB`.

        Raises:
            Error: Everything `validate` raises.
        """
        self.image = image^
        self.wrap_s = wrap
        self.wrap_t = wrap
        self.filter = filter
        self.color_space = color_space
        self.validate()

    def __init__(out self, *, copy: Self):
        """Copy another array texture, texels included.

        Args:
            copy: The texture to copy.
        """
        self.image = VolumeImage(copy=copy.image)
        self.wrap_s = copy.wrap_s
        self.wrap_t = copy.wrap_t
        self.filter = copy.filter
        self.color_space = copy.color_space

    def validate(self) raises:
        """Refuse modes or texels edited into nonsense since construction.

        Raises:
            Error: If a wrap mode, the filter or the color space is none of
                the named values, a float image is not `LINEAR`, or the
                image fails `VolumeImage.validate`.
        """
        _check_modes(
            self.wrap_s.is_valid() and self.wrap_t.is_valid(),
            self.filter,
            self.color_space,
            self.image,
        )

    def layers(self) -> Int:
        """Return how many layers the stack holds: three.js's `depth`."""
        return self.image.depth

    def texel_fetch(self, x: Int, y: Int, layer: Int) raises -> FloatColor:
        """Return one texel by index: GLSL's `texelFetch` at level zero.

        Args:
            x: Column.
            y: Row, up from the first.
            layer: Layer.

        Returns:
            The color stored there.

        Raises:
            Error: If an index is outside the image.
        """
        return self.image._fetch(x, y, layer, self.color_space)

    def _wrapped(self, x: Int, y: Int, layer: Int) -> FloatColor:
        """Return a texel of one layer by index, wrapped across and up."""
        return self.image._texel(
            wrap_index(x, self.image.width, self.wrap_s),
            wrap_index(y, self.image.height, self.wrap_t),
            layer,
            self.color_space,
        )

    def sample(self, u: Float32, v: Float32, layer: Float32) -> FloatColor:
        """Return the color at a coordinate in one layer: GLSL's `texture`
        on a `sampler2DArray`.

        The layer is `array_layer` of the third coordinate. Within it,
        `NEAREST` takes the texel the coordinate lands in and `BILINEAR`
        blends the four around it. Two layers are never blended.

        Args:
            u: Across, zero at the first column's edge.
            v: Up, zero at the first row's edge.
            layer: Which layer, rounded to the nearest and held inside.

        Returns:
            The color, straight.
        """
        var slice = array_layer(layer, self.image.depth)
        var wide = Float32(self.image.width)
        var tall = Float32(self.image.height)
        if self.filter == NEAREST:
            return self._wrapped(
                Int(floor(u * wide)), Int(floor(v * tall)), slice
            )
        var across = u * wide - 0.5
        var up = v * tall - 0.5
        var x = Int(floor(across))
        var y = Int(floor(up))
        var fx = across - Float32(x)
        return mix_straight_texels(
            mix_straight_texels(
                self._wrapped(x, y, slice), self._wrapped(x + 1, y, slice), fx
            ),
            mix_straight_texels(
                self._wrapped(x, y + 1, slice),
                self._wrapped(x + 1, y + 1, slice),
                fx,
            ),
            up - Float32(y),
        )
