# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An image to look colors up in, from three.js `src/textures/Texture.js`.

The payoff for carrying texture coordinates all the way to the fragment: a `uv`
pair names a place in an image, and this is what reads it.

**Rows run downwards, `v` runs upwards.** An image's first row is its top one —
that is how PNG stores it and how `Framebuffer` addresses it — while texture
space puts its origin at the bottom left, as OpenGL and three.js do. Sampling
is where those two disagree, so sampling is where it is reconciled, once:
`1 - v` turns one into the other. three.js spells the same reconciliation
`flipY`, and has it on by default.

**Two filters.** `NEAREST` takes the color of whichever texel the sample
lands in; `BILINEAR`, the default as in three.js, blends the four around
it, and a chain of mip levels is built by default as three.js builds one. Nearest keeps a checkerboard's
edges hard, which is what makes a mapping error legible — a wrong `uv` shows a
misplaced square rather than a vague blur — and it is exact, so both backends
agree on it to the last bit. Bilinear is what you want once the image is meant
to be looked at rather than debugged: at a glancing angle nearest turns a fine
pattern into noise.

**Texels are decoded before anything is done with them.** An image file holds
sRGB, and filtering or lighting encoded values is arithmetic on the wrong
numbers — see `render.srgb`. A texture therefore carries which space it is in,
and color textures decode by default. Alpha never does: it is not color.

**Alpha is coverage unless a texture says otherwise.** Filtering weights
every texel by its alpha, so a hidden color weighs nothing, and the mip chain
is averaged the same way. That is right for a cut-out and wrong for an image
whose alpha means nothing, such as a map of the light a surface gives off: a
white texel with alpha zero would filter to black. A texture built with
`alpha=IGNORED` reads every alpha byte as 255 instead, at the fetch and in
the chain, and so filters its color as it is. See `Alpha`.

**Out-of-range coordinates wrap.** Nothing constrains `uv` to the unit square:
a geometry can ask for its texture five times across, and clipping can produce
coordinates outside anything the author wrote. `REPEAT` tiles, `CLAMP` holds
the edge color, and `MIRROR` alternates direction each tile — the same three
three.js offers.

**A texture can be read along the long axis of a footprint.** A surface
seen at a glancing angle covers a footprint that is long one way and short
the other, and a mip level is square: the level the long axis wants blurs
the short axis, and the level the short axis wants sparkles along the long
one. `anisotropy`, three.js's `Texture.anisotropy`, is how many samples a
fragment may take along the long axis instead, each read at the level the
short axis wants; see `anisotropic_footprint`. One, the default, is the
plain trilinear read.

**A texture can move, tile and turn on its surface.** three.js's `offset`,
`repeat`, `rotation` and `center` are fields here as there, and
`uv_transform` is the 2D affine matrix they come to, three.js's
`Texture.matrix`. The renderer carries every coordinate of a mesh through
its texture's matrix before the fragment samples with it, as three.js's
vertex shader does, so a `repeat` of two tiles the image twice across and an
`offset` of a half slides it half a tile. The texture itself does not change:
the transform is on the coordinates that reach it, which is why the wrap
mode still decides what a coordinate past the edge reads.

**A texture holds bytes or floats.** Bytes are what image files hold and
what every texture held first: a fraction from zero to one, decoded through
the color space's ramp. An HDR image holds light with no top, which no byte
can, so a texture of `FLOAT_TYPE`, three.js's `FloatType`, keeps four floats
a texel in `data` and reads them as they are. Everything past the fetch --
the wrap, the filter, the chain's weighted average, the footprint -- is the
same arithmetic on the same `FloatColor`, which is why one `_texel_at` is
the only place the two differ. See `float_texture`.
"""

from math.matrix3 import Matrix3
from math.vector2 import Vector2
from render.framebuffer import Color, FloatColor, Framebuffer
from render.png import DecodedImage
from render.srgb import (
    LINEAR,
    SRGB,
    UNKNOWN_SPACE,
    ColorSpace,
    decode_ramp,
    linear_to_srgb,
)
from render.float_image import FloatImage
from std.math import ceil, floor, inf, isfinite, log2, sqrt
from std.memory import bitcast
from units.si import Angle, RADIAN


@fieldwise_init
struct Wrap(Equatable, ImplicitlyCopyable, Writable):
    """How a coordinate outside the unit square is resolved, as a type.

    See `core.object3d.NodeId` for why these are wrapped rather than bare
    integers. `value` is what the GPU's descriptor table stores. The type
    does not stop `Wrap(9)`, so `Texture.validate` asks `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `REPEAT`, `CLAMP` or `MIRROR`."""
        return self == REPEAT or self == CLAMP or self == MIRROR


# Tile the image; 1.5 reads the same texel as 0.5.
comptime REPEAT = Wrap(0)
# Hold the edge texel; 1.5 reads the same texel as 1.0.
comptime CLAMP = Wrap(1)
# Tile, flipping direction every other tile, so tiles meet without a seam.
comptime MIRROR = Wrap(2)


@fieldwise_init
struct Filter(Equatable, ImplicitlyCopyable, Writable):
    """How a sample between texel centers is resolved, as a type."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `NEAREST` or `BILINEAR`."""
        return self == NEAREST or self == BILINEAR


# Take whichever texel the sample lands in. Hard edges, visible texels.
comptime NEAREST = Filter(0)
# Blend the four texels around the sample by how close it is to each.
comptime BILINEAR = Filter(1)


@fieldwise_init
struct Alpha(Equatable, ImplicitlyCopyable, Writable):
    """What a texture's alpha bytes mean, as a type.

    Filtering is a weighted sum, and whether alpha weights it is a property
    of what the image *is*, not of how it is decoded: `ColorSpace` says how
    the color bytes turn into light, and this says whether the alpha bytes
    are coverage that hides color, or nothing at all. An image of light a
    surface gives off has no coverage, and reading its alpha as coverage
    turns a white texel with alpha zero into black under a bilinear filter,
    and down the whole mip chain. `value` is what the GPU's descriptor table
    stores. The type does not stop `Alpha(9)`, so `Texture.validate` asks
    `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `COVERAGE` or `IGNORED`."""
        return self == COVERAGE or self == IGNORED


# Alpha is coverage: it weights every filter and every mip average, so a
# hidden color weighs nothing, and a sample carries it. The default, and what
# a cut-out sprite or a translucent image is.
comptime COVERAGE = Alpha(0)
# Alpha is not read: every alpha byte counts as 255, so color is filtered as
# it is and every sample is opaque. What an emissive map is, and any other
# image whose alpha channel means nothing.
comptime IGNORED = Alpha(1)


@fieldwise_init
struct TexelType(Equatable, ImplicitlyCopyable, Writable):
    """What one channel of a texel is stored as, three.js's `Texture.type`,
    as a type rather than a bare int.

    A byte holds a fraction from zero to one, decoded through the color
    space's ramp. A float holds linear light as it is, and light has no
    top: a sun in an HDR image is thousands of times brighter than the
    sky beside it, and a byte would clip both to one. `value` is what the
    GPU's descriptor table stores. The type does not stop `TexelType(9)`,
    so `Texture.validate` asks `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `UNSIGNED_BYTE_TYPE` or `FLOAT_TYPE`."""
        return self == UNSIGNED_BYTE_TYPE or self == FLOAT_TYPE


# Eight bits a channel, in `Texture.pixels`: three.js's `UnsignedByteType`.
# What every image file but an HDR one holds, and the default.
comptime UNSIGNED_BYTE_TYPE = TexelType(0)
# Thirty-two bits a channel, linear, in `Texture.data`: three.js's
# `FloatType`. What `render.rgbe` and `render.exr` produce. three.js's
# loaders default to `HalfFloatType`; a half here is widened to a float,
# which holds every half exactly.
comptime FLOAT_TYPE = TexelType(1)


@fieldwise_init
struct UvChannel(Equatable, ImplicitlyCopyable, Writable):
    """Which set of texture coordinates a texture is sampled with, as a
    type: three.js's `Texture.channel`.

    `UV_CHANNEL_0` reads the geometry's `uv` and `UV_CHANNEL_1` its `uv1`.
    Only an ambient occlusion map or a light map can read the second set;
    the renderer refuses it on any other map. The type does not stop
    `UvChannel(9)`, so `Texture.validate` asks `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `UV_CHANNEL_0` or `UV_CHANNEL_1`."""
        return self == UV_CHANNEL_0 or self == UV_CHANNEL_1


# The geometry's `uv`: three.js's default channel, and every map's here.
comptime UV_CHANNEL_0 = UvChannel(0)
# The geometry's `uv1`, or its `uv` when it has no `uv1`. What a baked
# ambient occlusion map or light map usually reads.
comptime UV_CHANNEL_1 = UvChannel(1)


def float_from_bytes(b0: UInt8, b1: UInt8, b2: UInt8, b3: UInt8) -> Float32:
    """Return the float four little-endian bytes hold.

    How a float texel crosses to the device: the GPU's texel buffer is
    bytes, and a float texture's numbers ride in it four bytes each.
    Shared, so the host test that reads the flattened buffer back and the
    kernel that samples it read the same bits the same way.

    Args:
        b0: The lowest byte.
        b1: The next.
        b2: The next.
        b3: The highest byte, holding the sign.

    Returns:
        The IEEE 754 single those bits spell.
    """
    return bitcast[DType.float32](
        UInt32(b0) | (UInt32(b1) << 8) | (UInt32(b2) << 16) | (UInt32(b3) << 24)
    )


def float_texel(
    r: Float32, g: Float32, b: Float32, a: Float32, alpha: Alpha
) -> FloatColor:
    """Return a float texel as the color it samples as.

    The float counterpart of the byte decode: no ramp, because a float
    already holds linear light, and an alpha of one when the texture
    ignores its alpha. Shared by both rasterizers.

    Args:
        r: The stored red.
        g: The stored green.
        b: The stored blue.
        a: The stored alpha.
        alpha: The texture's alpha mode.

    Returns:
        The color.
    """
    if alpha == IGNORED:
        return FloatColor(r, g, b, 1.0)
    return FloatColor(r, g, b, a)


def mix(near: Float32, far: Float32, t: Float32) -> Float32:
    """Return one channel a fraction `t` of the way from `near` to `far`."""
    return near + (far - near) * t


def mix_color(near: FloatColor, far: FloatColor, t: Float32) -> FloatColor:
    """Return one color a fraction `t` of the way to another.

    Mixed premultiplied, so a transparent color contributes no color — the
    same reason `blend_texels` does. Shared with the GPU kernel, which blends
    between mip levels with it.
    """
    var one = near.premultiplied()
    var two = far.premultiplied()
    return FloatColor(
        mix(one.r, two.r, t),
        mix(one.g, two.g, t),
        mix(one.b, two.b, t),
        mix(one.a, two.a, t),
    ).unpremultiplied()


def mix_straight(near: FloatColor, far: FloatColor, t: Float32) -> FloatColor:
    """Return one vertex color a fraction `t` of the way to another.

    For a varying, which is what a color on a corner is: a number the
    author put there, interpolated component by component, exactly as the
    triangle rasterizer interpolates the same field across three corners.
    The GPU line pass calls this too, so the one convention for a line's
    color lives in one place.

    Not `mix_color`. That one premultiplies first, which is right for
    filtering the texels of an image -- an invisible texel must not lend
    its color to a neighbor -- and wrong for a varying, where a corner's
    color and its alpha are two numbers the author gave separately. Mixing
    a transparent red toward an opaque blue premultiplied drops the red
    outright. The triangle path keeps it, and so does this.

    Args:
        near: The color at one end.
        far: The color at the other.
        t: How far along, from zero at `near` to one at `far`.

    Returns:
        The interpolated color, straight rather than premultiplied.
    """
    return FloatColor(
        mix(near.r, far.r, t),
        mix(near.g, far.g, t),
        mix(near.b, far.b, t),
        mix(near.a, far.a, t),
    )


def blend_texels(
    lower_left: FloatColor,
    lower_right: FloatColor,
    upper_left: FloatColor,
    upper_right: FloatColor,
    across: Float32,
    down: Float32,
) -> FloatColor:
    """Bilinear blend of four texels, done where hidden color weighs nothing.

    Filtering is a weighted sum, and a weighted sum of *straight* colors lets
    an invisible texel contribute its color anyway. An opaque red beside a
    fully transparent green averages to half red and half green, so a fringe
    of a color nobody put there appears along every transparent edge — the
    classic halo around a cut-out sprite.

    Premultiplied, the transparent texel contributes nothing but its alpha,
    and the answer is half-covered red. The result is unpremultiplied again so
    that callers keep a single straight-alpha convention and alpha is applied
    exactly once.

    Args:
        lower_left: The texel at the smaller column and row.
        lower_right: One column further on.
        upper_left: One row further on.
        upper_right: One of each.
        across: How far between the two columns, 0 to 1.
        down: How far between the two rows, 0 to 1.

    Returns:
        The blended color, with straight alpha.
    """
    return blend(
        lower_left.premultiplied(),
        lower_right.premultiplied(),
        upper_left.premultiplied(),
        upper_right.premultiplied(),
        across,
        down,
    ).unpremultiplied()


def blend(
    lower_left: FloatColor,
    lower_right: FloatColor,
    upper_left: FloatColor,
    upper_right: FloatColor,
    across: Float32,
    down: Float32,
) -> FloatColor:
    """Blend the four texels around a sample point.

    Two mixes along one axis and one along the other, which is what bilinear
    means. Public and pure because the GPU kernel calls it too: each backend
    fetches its own four texels, and then both do the arithmetic here. Sharing
    the *blend* rather than the lookup is the part that matters — memory
    access differs between host and device by nature, and interpolation does
    not.

    Args:
        lower_left: The texel at the smaller column and row.
        lower_right: One column further on.
        upper_left: One row further on.
        upper_right: One of each.
        across: How far between the two columns, 0 to 1.
        down: How far between the two rows, 0 to 1.

    Returns:
        The blended color.
    """
    var top = FloatColor(
        mix(lower_left.r, lower_right.r, across),
        mix(lower_left.g, lower_right.g, across),
        mix(lower_left.b, lower_right.b, across),
        mix(lower_left.a, lower_right.a, across),
    )
    var bottom = FloatColor(
        mix(upper_left.r, upper_right.r, across),
        mix(upper_left.g, upper_right.g, across),
        mix(upper_left.b, upper_right.b, across),
        mix(upper_left.a, upper_right.a, across),
    )
    return FloatColor(
        mix(top.r, bottom.r, down),
        mix(top.g, bottom.g, down),
        mix(top.b, bottom.b, down),
        mix(top.a, bottom.a, down),
    )


def _to_byte(value: Float32, space: ColorSpace) -> UInt8:
    """Return a linear channel as the byte that stores it in `space`.

    Only the top is clamped. The one caller averages values that came from
    bytes, so `value` cannot be negative, and a guard against that would be a
    branch no test could ever take -- coverage says so, and dead code that
    looks like a safety check is worse than none.

    Args:
        value: A linear channel, 0 to 1.
        space: `SRGB` to encode through the curve, `LINEAR` to store as is.

    Returns:
        The byte.
    """
    var shown = value
    if space == SRGB:
        shown = linear_to_srgb(value)
    var scaled = shown * 255 + 0.5
    if scaled >= 255:
        return 255
    return UInt8(scaled)


def _ceiling(value: Int, divisor: Int) -> Int:
    """Return `value` divided by `divisor`, rounded up. Both are positive."""
    return (value + divisor - 1) // divisor


def _overlap(low: Int, high: Int, start: Int, extent: Int) -> Int:
    """Return how much of `[start, start + extent)` lies in `[low, high)`.

    The weight one source texel carries into one destination texel, in the
    scaled units `_build_mipmaps` works in. Never negative: the caller only
    visits texels the range actually reaches.

    Args:
        low: Start of the destination's range.
        high: One past its end.
        start: Start of the source texel's range.
        extent: Its length.

    Returns:
        The length they share.
    """
    var near = low
    if start > near:
        near = start
    var far = high
    if start + extent < far:
        far = start + extent
    return far - near


def _identity_ramp() -> List[Float32]:
    """Return the 256 values a byte stands for when nothing is encoded."""
    var ramp = List[Float32]()
    for step in range(256):  # pragma: no branch
        ramp.append(Float32(step) / 255)
    return ramp^


def wrap_index(coordinate: Int, extent: Int, mode: Wrap) -> Int:
    """Return `coordinate` brought inside [0, extent) under a wrap mode.

    Public, and pure, because the GPU kernel calls it too. Sampling has to
    agree between the two backends texel for texel, and the way to make two
    implementations agree is to have one — the same argument `render.fillrule`
    makes about coverage. Nothing here allocates, raises or prints, so it
    compiles for a device as readily as for the host.

    Args:
        coordinate: The texel index, possibly outside the image.
        extent: The image's size on this axis; always positive here.
        mode: `REPEAT`, `CLAMP` or `MIRROR`.

    Returns:
        An index inside the image.
    """
    if mode == CLAMP:
        if coordinate < 0:
            return 0
        if coordinate >= extent:
            return extent - 1
        return coordinate

    # Mojo's `%` is floored, as Python's is, so a negative coordinate already
    # comes back inside [0, extent) and needs no correcting afterwards: -1 % 4
    # is 3, not -1. Guards for a negative result were written here out of C
    # habit and were unreachable; the coverage report is what found them.
    # `test_negative_coordinates_rely_on_floored_modulo` pins the assumption,
    # since the whole of wrapping quietly depends on it.
    if mode == MIRROR:
        # A full period is out and back again, so twice the extent.
        var folded = coordinate % (extent * 2)
        if folded >= extent:
            return extent * 2 - 1 - folded
        return folded

    return coordinate % extent


struct Texture(Movable):
    """An RGBA image, sampled by texture coordinate."""

    comptime CHANNELS = 4

    var width: Int
    var height: Int
    # Row-major RGBA from the top, the same layout `Framebuffer` uses, so an
    # image rendered by this project can be fed straight back in as a texture.
    var pixels: List[UInt8]
    # Whether the texels are bytes in `pixels` or floats in `data`; see
    # `TexelType`. The other list is empty.
    var texel_type: TexelType
    # Row-major RGBA floats from the top, the mip chain after the image, in
    # the same layout `pixels` has: filled for a `FLOAT_TYPE` texture only.
    var data: List[Float32]
    var wrap: Wrap
    var filter: Filter
    var color_space: ColorSpace
    # Whether the alpha bytes are coverage or nothing at all; see `Alpha`.
    # Read wherever an alpha byte becomes a number -- the mip build and the
    # texel fetch, here and on the device -- which is the one place a mode
    # about reading bytes belongs.
    var alpha: Alpha
    # How many images the chain holds: the full-size one, then each halving
    # down to a single texel. One means no chain.
    var levels: Int
    # Where each level starts in the texel buffer, one entry per level.
    # `level_offset` can work it out from the sizes, and does when the chain
    # is being built; a fetch happens per texel per fragment and reads the
    # table instead of walking the chain each time.
    var offsets: List[Int]
    # The 256 linear values this texture's bytes stand for. Built once here
    # rather than per fragment, because `pow` has only 256 possible inputs
    # and sampling happens per pixel.
    var ramp: List[Float32]
    # How the coordinates that sample this texture are moved, tiled and
    # turned first: three.js's fields of the same names, and `uv_transform`
    # is the matrix they make. Set after construction, as in three.js.
    # None of them is checked, because every value is a transform: a repeat
    # of zero collapses the image to one texel, which is what was asked.
    var offset: Vector2
    var repeat: Vector2
    var rotation: Angle
    var center: Vector2
    # How many samples a fragment may take along the long axis of its
    # footprint, three.js's `anisotropy`. One, the default, reads one
    # trilinear sample; sixteen is what a GPU usually caps it at. Set
    # after construction, as in three.js, and refused below one by
    # `validate`. Read by both rasterizers where they pick a level.
    var anisotropy: Int
    # Which set of the geometry's texture coordinates this texture is
    # sampled with, three.js's `channel`. `UV_CHANNEL_0`, the default, is
    # three.js's. Set after construction, as in three.js, and refused by
    # `validate` when it is neither channel.
    var channel: UvChannel

    def __init__(out self):
        """Create the blank texture, which samples as opaque white.

        White is the identity for modulation, so a mesh with no texture shades
        exactly as it did before textures existed. That makes "no texture" a
        value rather than a special case the renderer has to branch on.
        """
        self.width = 0
        self.height = 0
        self.pixels = List[UInt8]()
        self.texel_type = UNSIGNED_BYTE_TYPE
        self.data = List[Float32]()
        self.wrap = REPEAT
        self.filter = NEAREST
        self.color_space = LINEAR
        self.alpha = COVERAGE
        self.ramp = _identity_ramp()
        self.levels = 1
        self.offsets = [0]
        self.offset = Vector2(0, 0)
        self.repeat = Vector2(1, 1)
        self.rotation = Angle(0.0, RADIAN)
        self.center = Vector2(0, 0)
        self.anisotropy = 1
        self.channel = UV_CHANNEL_0

    def __init__(
        out self,
        width: Int,
        height: Int,
        var pixels: List[UInt8],
        wrap: Wrap = REPEAT,
        filter: Filter = BILINEAR,
        color_space: ColorSpace = SRGB,
        mipmapped: Bool = True,
        alpha: Alpha = COVERAGE,
    ) raises:
        """Create a texture from RGBA bytes.

        Args:
            width: Image width in texels.
            height: Image height in texels.
            pixels: Row-major RGBA bytes from the top, width * height * 4.
            wrap: How coordinates outside the unit square are resolved.
            filter: `NEAREST` or `BILINEAR`. Bilinear by default, as
                three.js's `LinearFilter` is.
            color_space: `SRGB` for a color image, the default because that
                is what an image file holds; `LINEAR` for data that is not
                color and must not be decoded. `UNKNOWN_SPACE` is refused:
                it is a decoder's admission, not a way to read texels.
            mipmapped: Build the chain of halved copies. Costs a third more
                memory and is what stops a distant surface from sparkling.
                On by default, as three.js's `generateMipmaps` and
                `LinearMipmapLinearFilter` are.
            alpha: `COVERAGE`, the default, if the alpha bytes hide color,
                as a cut-out's or a translucent image's do; `IGNORED` if they
                mean nothing, as an emissive map's do. Decided here rather
                than at the sample, because a mip chain is averaged as it is
                built and cannot be unaveraged.

        Raises:
            Error: If the dimensions are not positive, the buffer length
                disagrees with them, or the wrap, filter, color space or
                alpha mode is none of the named values -- see `validate`.
        """
        if width <= 0 or height <= 0:
            raise Error("Texture dimensions must be positive")
        if len(pixels) != width * height * Self.CHANNELS:
            raise Error("Texture buffer length does not match the dimensions")
        self.color_space = color_space
        if color_space == SRGB:
            self.ramp = decode_ramp()
        else:
            self.ramp = _identity_ramp()
        self.width = width
        self.height = height
        self.pixels = pixels^
        self.texel_type = UNSIGNED_BYTE_TYPE
        self.data = List[Float32]()
        self.wrap = wrap
        self.filter = filter
        self.alpha = alpha
        self.levels = 1
        self.offsets = [0]
        self.offset = Vector2(0, 0)
        self.repeat = Vector2(1, 1)
        self.rotation = Angle(0.0, RADIAN)
        self.center = Vector2(0, 0)
        self.anisotropy = 1
        self.channel = UV_CHANNEL_0
        # After every field is set, so it is the same check the GPU upload
        # makes on a texture that may have been edited since.
        self.validate()
        if mipmapped:
            self._build_mipmaps()

    def validate(self) raises:
        """Refuse a wrap, filter, color space, alpha mode, texel type or
        channel that is none of the named values.

        The types stop a bare integer at compile time and nothing else: a
        struct's fields are open, so `Wrap(9)` constructs, and so does
        `image.filter = Filter(5)` after the image was checked. The
        constructor calls this, and `render.gpu.flatten_textures` calls it
        again on the way to the device, because a value that is neither of
        two things was once read one way by the host and the other way by
        the kernel.

        Raises:
            Error: If the wrap mode, the filter, the color space, the
                alpha mode, the texel type or the channel is not one of
                its named constants, or a float texture is not `LINEAR`.
                `UNKNOWN_SPACE` counts: it is a decoder's admission, not a
                way to read texels.
        """
        if not self.wrap.is_valid():
            raise Error("A texture's wrap mode must be REPEAT, CLAMP or MIRROR")
        if not self.filter.is_valid():
            raise Error("A texture's filter must be NEAREST or BILINEAR")
        if not self.color_space.is_decodable():
            raise Error(
                "A texture needs a color space it can decode: SRGB or LINEAR"
            )
        if not self.alpha.is_valid():
            raise Error("A texture's alpha mode must be COVERAGE or IGNORED")
        if not self.texel_type.is_valid():
            raise Error(
                "A texture's texel type must be UNSIGNED_BYTE_TYPE or"
                " FLOAT_TYPE"
            )
        # A float holds linear light as it is. The sRGB curve is a way to
        # spend 256 steps where the eye sees them, and a float has no steps
        # to spend: three.js's HDR loaders mark their textures linear.
        if self.texel_type == FLOAT_TYPE and self.color_space != LINEAR:
            raise Error("A float texture holds linear light: it must be LINEAR")
        if self.anisotropy < 1:
            raise Error("A texture's anisotropy is at least one")
        if self.anisotropy > MAX_ANISOTROPY:
            raise Error(
                "A texture's anisotropy is at most MAX_ANISOTROPY: every"
                " tap is work a fragment pays for"
            )
        if not self.channel.is_valid():
            raise Error(
                "A texture's channel must be UV_CHANNEL_0 or UV_CHANNEL_1"
            )

    def __init__(out self, *, copy: Self):
        """Copy another texture, image data included."""
        self.width = copy.width
        self.height = copy.height
        self.pixels = copy.pixels.copy()
        self.texel_type = copy.texel_type
        self.data = copy.data.copy()
        self.wrap = copy.wrap
        self.filter = copy.filter
        self.color_space = copy.color_space
        self.alpha = copy.alpha
        self.ramp = copy.ramp.copy()
        self.levels = copy.levels
        self.offsets = copy.offsets.copy()
        self.offset = copy.offset
        self.repeat = copy.repeat
        self.rotation = copy.rotation
        self.center = copy.center
        self.anisotropy = copy.anisotropy
        self.channel = copy.channel

    def ignoring_alpha(self) raises -> Texture:
        """Return a copy of this texture that ignores its alpha.

        For one image used both as a base map, where its alpha is coverage,
        and as an emissive map, where alpha means nothing: two textures in
        the store, one per role, each built once. The copy's mip chain is
        rebuilt from the full-size image, because the chain this one holds
        was averaged with alpha as coverage and cannot be unaveraged. The
        blank texture is its own copy: it has no alpha to ignore.

        Returns:
            The copy, with `alpha` set to `IGNORED` and the same wrap,
            filter, color space, chain length and transform.

        Raises:
            Error: If this texture's fields were edited into nonsense since
                it was built; see `validate`.
        """
        var copy: Texture
        if self.is_blank():
            # Blank, and marked as promised: a renderer that asks whether an
            # emissive map ignores its alpha gets the same answer here as
            # for any other copy, and samples opaque white as it would.
            copy = Texture()
            copy.alpha = IGNORED
        elif self.texel_type == FLOAT_TYPE:
            var base = List[Float32]()
            # The full-size image is the first level: the loop always runs.
            for index in range(
                self.width * self.height * Self.CHANNELS
            ):  # pragma: no branch
                base.append(self.data[index])
            copy = float_texture(
                self.width,
                self.height,
                base^,
                self.wrap,
                self.filter,
                self.levels > 1,
                IGNORED,
            )
        else:
            var base = List[UInt8]()
            # The full-size image is the first level: the loop always runs.
            for index in range(
                self.width * self.height * Self.CHANNELS
            ):  # pragma: no branch
                base.append(self.pixels[index])
            copy = Texture(
                self.width,
                self.height,
                base^,
                self.wrap,
                self.filter,
                self.color_space,
                self.levels > 1,
                IGNORED,
            )
        # The same image the same way round, the blank one included: a base
        # map and an emissive map made from one image are sampled at one
        # coordinate, and the renderer refuses the pair if their transforms
        # differ.
        copy.offset = self.offset
        copy.repeat = self.repeat
        copy.rotation = self.rotation
        copy.center = self.center
        copy.anisotropy = self.anisotropy
        copy.channel = self.channel
        return copy^

    def is_blank(self) -> Bool:
        """Return True if this is the blank texture."""
        return self.width == 0

    def uv_transform(self) -> Matrix3:
        """Return the transform the renderer applies to a mesh's texture
        coordinates before this texture is sampled with them: three.js's
        `Texture.matrix` after `updateMatrix`, built from `offset`,
        `repeat`, `rotation` and `center`.

        The identity until a field is set, so a texture that says nothing
        about it is sampled where the geometry says. Built each time it is
        asked for rather than cached, because the fields are open and a
        cached matrix could not know when it had gone stale; the renderer
        asks once per mesh.

        Returns:
            The matrix. See `Matrix3.uv_transform` for its order.
        """
        return Matrix3.uv_transform(
            self.offset, self.repeat, self.rotation, self.center
        )

    def _alpha_of(self, byte: UInt8) -> Float32:
        """Return what an alpha byte means: its fraction, or one if alpha is
        ignored. Never decoded through the ramp -- alpha is not color."""
        if self.alpha == IGNORED:
            return 1
        return Float32(byte) / 255

    def texel(self, x: Int, y: Int) raises -> Color:
        """Return the color at a texel, by row and column from the top.

        Args:
            x: Column, from the left.
            y: Row, from the top.

        Returns:
            The color stored there.

        Raises:
            Error: If the texture is blank, holds floats rather than bytes,
                or the coordinates are outside it.
        """
        if self.is_blank():
            raise Error("The blank texture has no texels")
        if self.texel_type == FLOAT_TYPE:
            raise Error(
                "A float texture's texels are not bytes; read them with"
                " wrapped_texel"
            )
        if x < 0 or x >= self.width or y < 0 or y >= self.height:
            raise Error("Texel coordinate out of bounds")
        var offset = (y * self.width + x) * Self.CHANNELS
        return Color(
            self.pixels[offset],
            self.pixels[offset + 1],
            self.pixels[offset + 2],
            self.pixels[offset + 3],
        )

    def level_width(self, level: Int) -> Int:
        """Return how wide the image is at `level`, never below one."""
        var extent = self.width >> level
        if extent < 1:
            return 1
        return extent

    def level_height(self, level: Int) -> Int:
        """Return how tall the image is at `level`, never below one."""
        var extent = self.height >> level
        if extent < 1:
            return 1
        return extent

    def level_offset(self, level: Int) -> Int:
        """Return where `level` starts in the concatenated texel buffer.

        The chain is stored end to end, largest first, so a level's position
        is the sum of the sizes before it. Computed rather than stored: it is
        a handful of shifts, and the GPU has to be able to work it out the
        same way from the same numbers.
        """
        var offset = 0
        for step in range(level):
            offset += (
                self.level_width(step) * self.level_height(step) * Self.CHANNELS
            )
        return offset

    def _build_mipmaps(mut self) raises:
        """Append each halved copy of the image to the texel buffer.

        Box filter: each texel of a level is the average of the region of the
        level above that it stands for. Averaged in premultiplied linear
        light, for the two reasons everything else in this file is — a hidden
        color must weigh nothing, and light is what averages — and encoded
        back to bytes at each level, which is what a GPU stores too.

        A chain exists to answer a question the full-size image cannot: when
        one pixel covers many texels, which one is the color? Any single
        answer sparkles as the surface moves. The average of all of them does
        not, and each level is the average already taken.

        **Odd extents.** "The four beneath it" is only true when the extent
        halves evenly. An extent of three halves to one, and a destination
        texel that reads a fixed 2x2 block drops the third column entirely —
        silently, because the block is in bounds and there is nothing to
        report. That was a live bug: a 3x1 image of black, black, white
        reduced to black rather than to a third of the light, and a 6x1 image
        lost its last third one level down, at the 3 to 1 step. An even base
        size is no protection, because an even level can halve to an odd one.

        So a destination texel covers its *proportionate* rectangle of the
        whole source — columns `x * W / W'` up to `(x + 1) * W / W'` — and
        each source texel is weighted by how much of that rectangle it
        occupies. A 5 to 2 reduction gives the middle column to both halves,
        half each. Nothing is dropped, and the weights sum to the whole image.

        The arithmetic is integers scaled by the destination extent, so the
        weights are exact rather than nearly-exact: every destination texel
        accumulates a total weight of exactly `wide * tall`. Where the extent
        does halve evenly the weights come out equal and this is the plain
        average of four, which is why there is no separate fast path.

        The two innermost loops are `while` rather than `for ... in range`.
        That is not a style choice: with `range` over computed bounds at this
        nesting depth the Mojo compiler stops making progress, and building
        this file goes from three seconds to not finishing. The loops are
        otherwise identical.
        """
        var level = 0
        while self.level_width(level) > 1 or self.level_height(level) > 1:
            var wide = self.level_width(level)
            var tall = self.level_height(level)
            var next_wide = self.level_width(level + 1)
            var next_tall = self.level_height(level + 1)
            var base = self.level_offset(level)
            # The next level begins where this buffer currently ends.
            self.offsets.append(self._stored())
            for y in range(next_tall):  # pragma: no branch
                # The rows this destination stands for, in source rows scaled
                # by the destination extent so the bounds stay exact.
                var top = y * tall
                var bottom = top + tall
                for x in range(next_wide):  # pragma: no branch
                    var left = x * wide
                    var right = left + wide
                    var total = FloatColor(0.0, 0.0, 0.0, 0.0)
                    var first_row = top // next_tall
                    var past_row = _ceiling(bottom, next_tall)
                    var first_col = left // next_wide
                    var past_col = _ceiling(right, next_wide)
                    var sy = first_row
                    while sy < past_row:
                        var weight_y = _overlap(
                            top, bottom, sy * next_tall, next_tall
                        )
                        var sx = first_col
                        while sx < past_col:
                            var weight = Float32(
                                weight_y
                                * _overlap(
                                    left, right, sx * next_wide, next_wide
                                )
                            )
                            var at = base + (sy * wide + sx) * Self.CHANNELS
                            # An ignored alpha reads as one, so premultiplying
                            # changes nothing and the color averages as it
                            # is; the level then stores an opaque alpha.
                            var texel = self._texel_at(at).premultiplied()
                            total = FloatColor(
                                total.r + texel.r * weight,
                                total.g + texel.g * weight,
                                total.b + texel.b * weight,
                                total.a + texel.a * weight,
                            )
                            sx += 1
                        sy += 1
                    var share = 1 / Float32(wide * tall)
                    var mixed = FloatColor(
                        total.r * share,
                        total.g * share,
                        total.b * share,
                        total.a * share,
                    ).unpremultiplied()
                    self._store(mixed)
            level += 1
            self.levels = level + 1

    def _stored(self) -> Int:
        """Return how many channels the texel buffer holds, the chain
        included: the length of `data` for a float texture, of `pixels`
        for a byte one."""
        if self.texel_type == FLOAT_TYPE:
            return len(self.data)
        return len(self.pixels)

    def _store(mut self, color: FloatColor):
        """Append one averaged texel to the chain being built.

        A float texture keeps the average as it is, light above one
        included. A byte texture encodes it back to bytes in its own color
        space, which is what a GPU stores too; alpha is never encoded.
        """
        if self.texel_type == FLOAT_TYPE:
            self.data.append(color.r)
            self.data.append(color.g)
            self.data.append(color.b)
            self.data.append(color.a)
            return
        self.pixels.append(_to_byte(color.r, self.color_space))
        self.pixels.append(_to_byte(color.g, self.color_space))
        self.pixels.append(_to_byte(color.b, self.color_space))
        self.pixels.append(_to_byte(color.a, LINEAR))

    def _texel_at(self, offset: Int) -> FloatColor:
        """Return the texel that starts at `offset` in the texel buffer, as
        light: floats as they are, bytes through the ramp.

        Color through the ramp; alpha is not color and never decoded, and
        is not read at all when the texture ignores it.
        """
        if self.texel_type == FLOAT_TYPE:
            return float_texel(
                self.data[offset],
                self.data[offset + 1],
                self.data[offset + 2],
                self.data[offset + 3],
                self.alpha,
            )
        return FloatColor(
            self.ramp[Int(self.pixels[offset])],
            self.ramp[Int(self.pixels[offset + 1])],
            self.ramp[Int(self.pixels[offset + 2])],
            self._alpha_of(self.pixels[offset + 3]),
        )

    def _has_level(self, level: Int) -> Bool:
        """Return True if `level` names an image this texture actually holds."""
        return level >= 0 and level < self.levels

    def wrapped_texel(
        self, x: Int, y: Int, level: Int = 0
    ) raises -> FloatColor:
        """Return a texel by index, with the wrap mode applied first.

        No index is out of range: every column and row has an answer once a
        wrap mode is chosen, which is what a sampler needs. A *level* is a
        different matter — it names an image rather than a position in one,
        and a level the chain does not hold is a mistake with no sensible
        answer. Asking an 8x8 chain for level 4 used to compute an offset one
        past the end of the texel buffer and read it.

        The blank texture is the deliberate exception: it holds no images at
        all and answers white for any request, the identity that lets "no
        texture" be a value rather than a branch.

        Args:
            x: Column, possibly outside the image.
            y: Row from the top, possibly outside the image.
            level: Which image of the mip chain to read, zero being full size.

        Returns:
            The color found there, or opaque white if the texture is blank.

        Raises:
            Error: If the texture is not blank and has no such level.
        """
        if self.is_blank():
            return FloatColor(1.0, 1.0, 1.0, 1.0)
        if not self._has_level(level):
            raise Error("No such mip level")
        return self._wrapped_texel(x, y, level)

    def _wrapped_texel(self, x: Int, y: Int, level: Int) -> FloatColor:
        """Return a texel by index without checking that `level` exists.

        The innermost read, and the reason the checks are not here: sampling
        calls this once per texel per fragment. Its two preconditions — the
        texture is not blank, and `level` is one the chain holds — are
        established by every caller. `wrapped_texel` validates both for
        callers from outside; `_sample_at` and `sample` answer white for a
        blank texture before they get this far, and `sample_level` clamps the
        level into range. Coverage confirms a blank one never arrives here.
        """
        var wide = self.level_width(level)
        var tall = self.level_height(level)
        var offset = (
            self.offsets[level]
            + (
                wrap_index(y, tall, self.wrap) * wide
                + wrap_index(x, wide, self.wrap)
            )
            * Self.CHANNELS
        )
        return self._texel_at(offset)

    def sample_at(
        self, u: Float32, v: Float32, level: Int
    ) raises -> FloatColor:
        """Return the color at a coordinate, read from one mip level.

        An explicit level lookup, so a level the chain does not hold is
        rejected rather than clamped. `sample_level` is the other interface:
        it takes a fractional level of the kind a footprint produces, where
        landing outside the chain is ordinary and clamping is the answer.

        Args:
            u: Horizontal coordinate, 0 at the left edge.
            v: Vertical coordinate, 0 at the *bottom* edge.
            level: Which image of the chain, zero being full size.

        Returns:
            The color found there, or opaque white if the texture is blank.

        Raises:
            Error: If the texture is not blank and has no such level.
        """
        if self.is_blank():
            return FloatColor(1.0, 1.0, 1.0, 1.0)
        if not self._has_level(level):
            raise Error("No such mip level")
        return self._sample_at(u, v, level)

    def _sample_at(self, u: Float32, v: Float32, level: Int) -> FloatColor:
        """Return the color at a coordinate without checking `level` exists.

        The hot path, called up to twice per fragment by `sample_level` with
        a level it has already clamped.
        """
        if self.is_blank():
            return FloatColor(1.0, 1.0, 1.0, 1.0)
        var wide = self.level_width(level)
        var tall = self.level_height(level)

        if self.filter == NEAREST:
            return self._wrapped_texel(
                Int(floor(u * Float32(wide))),
                Int(floor((1 - v) * Float32(tall))),
                level,
            )

        # Texel centers are at half-integers, so shift the sample into a space
        # where they are at integers, and blend between the two either side.
        var across = u * Float32(wide) - 0.5
        var down = (1 - v) * Float32(tall) - 0.5
        var column = Int(floor(across))
        var row = Int(floor(down))
        return blend_texels(
            self._wrapped_texel(column, row, level),
            self._wrapped_texel(column + 1, row, level),
            self._wrapped_texel(column, row + 1, level),
            self._wrapped_texel(column + 1, row + 1, level),
            across - Float32(column),
            down - Float32(row),
        )

    def sample_level(
        self, u: Float32, v: Float32, level: Float32
    ) -> FloatColor:
        """Return the color at a coordinate, blended between two mip levels.

        Trilinear: bilinear within each of the two levels either side of
        `level`, then linearly between them. The blend between levels is what
        stops the change from one to the next being a visible seam across a
        receding surface.

        A texture with no chain ignores the level entirely and reads the only
        image it has.

        Args:
            u: Horizontal coordinate, 0 at the left edge.
            v: Vertical coordinate, 0 at the *bottom* edge.
            level: How far down the chain to read, fractional. Below zero
                means the surface is magnified, where the full-size image is
                already the right answer.

        Returns:
            The color found there, or opaque white if the texture is blank.
        """
        if self.is_blank() or self.levels == 1 or level <= 0:
            return self._sample_at(u, v, 0)
        if level >= Float32(self.levels - 1):
            return self._sample_at(u, v, self.levels - 1)
        var lower = Int(floor(level))
        return mix_color(
            self._sample_at(u, v, lower),
            self._sample_at(u, v, lower + 1),
            level - Float32(lower),
        )

    def sample_footprint(
        self, u: Float32, v: Float32, footprint: Footprint
    ) raises -> FloatColor:
        """Return the color over a pixel's footprint: one trilinear sample,
        or several along the footprint's long axis averaged.

        The checked entry point. A `Footprint` is fieldwise-constructible,
        so a caller can hand this one no taps at all, and the average
        below would divide by it. Anything a caller builds by hand comes
        through here; the rasterizers take `_sample_footprint`, because
        `anisotropic_footprint` made what they hand it.

        Args:
            u: Horizontal coordinate, 0 at the left edge.
            v: Vertical coordinate, 0 at the *bottom* edge.
            footprint: The level, the tap count and the step between taps,
                from `anisotropic_footprint` or built by hand.

        Returns:
            The color found there, or opaque white if the texture is blank.

        Raises:
            Error: Everything `Footprint.validate` raises.
        """
        footprint.validate()
        return self._sample_footprint(u, v, footprint)

    def _sample_footprint(
        self, u: Float32, v: Float32, footprint: Footprint
    ) -> FloatColor:
        """Return the color over a footprint `validate` has already passed.

        The taps are spread evenly along the long axis, centered on the
        coordinate, each read by `sample_level` at the footprint's level.
        Averaged premultiplied, as `mix_color` mixes, so a transparent tap
        lends no color. The GPU kernel takes the same taps in the same
        order; see `render.gpu._sample_slot`.

        Args:
            u: Horizontal coordinate, 0 at the left edge.
            v: Vertical coordinate, 0 at the *bottom* edge.
            footprint: The level, the tap count and the step between taps,
                from `anisotropic_footprint`. At least one tap.

        Returns:
            The color found there, or opaque white if the texture is blank.
        """
        if footprint.taps == 1:
            return self.sample_level(u, v, footprint.level)
        var total = FloatColor(0.0, 0.0, 0.0, 0.0)
        for tap in range(footprint.taps):  # pragma: no branch
            var along = Float32(tap) - Float32(footprint.taps - 1) / 2
            var sampled = self.sample_level(
                u + footprint.step.x * along,
                v + footprint.step.y * along,
                footprint.level,
            ).premultiplied()
            total = FloatColor(
                total.r + sampled.r,
                total.g + sampled.g,
                total.b + sampled.b,
                total.a + sampled.a,
            )
        var share = 1 / Float32(footprint.taps)
        return FloatColor(
            total.r * share, total.g * share, total.b * share, total.a * share
        ).unpremultiplied()

    def sample(self, u: Float32, v: Float32) -> FloatColor:
        """Return the color at a texture coordinate.

        `v` is flipped because rows run down from the top while texture space
        counts up from the bottom.

        Under `NEAREST` the sample takes whichever texel it lands in. A
        coordinate of exactly zero or one sits on a tile boundary, and the
        wrap mode decides which side it belongs to: under `REPEAT` both ends
        of the range name the same texel, which is what makes a tiled texture
        seamless; under `CLAMP` they name opposite edges.

        Under `BILINEAR` it blends the four texels around it. Texel *centers*
        sit at half-integers, which is the whole reason for the half subtracted
        below: without it the blend is offset by half a texel and every image
        drifts diagonally. The four neighbors are fetched through the wrap
        mode, so a bilinear `REPEAT` texture blends across its own seam and a
        `CLAMP` one holds its edge instead of fading out of it.

        Does not raise: a fragment shader is not a place to handle errors, and
        every coordinate has an answer once the modes are chosen. This is
        `sample_at` for level zero without the level check, and used to be a
        second copy of it.

        Args:
            u: Horizontal coordinate, 0 at the left edge.
            v: Vertical coordinate, 0 at the *bottom* edge.

        Returns:
            The color found there, or opaque white if the texture is blank.
        """
        if self.is_blank():
            return FloatColor(1.0, 1.0, 1.0, 1.0)

        return self._sample_at(u, v, 0)


# The most taps a fragment may take along a footprint's long axis, and so
# the largest `anisotropy` a texture may ask for. Sixteen is what the
# desktop GL implementations report and what three.js caps a texture at
# through `getMaxAnisotropy`. The cap belongs here and not only in the
# estimator: a tap is per-fragment work, and an asset that asked for a
# thousand would cost a thousand reads a pixel on both backends.
comptime MAX_ANISOTROPY = 16
# Below this fraction of the footprint's diagonal terms, an off-diagonal
# term is rounding noise and the footprint is axis-aligned; see
# `_major_direction`. Ten times a Float32's relative precision.
comptime DIAGONAL_TOLERANCE = Float32(1e-6)


@fieldwise_init
struct Footprint(ImplicitlyCopyable):
    """How a pixel's footprint is read: which level, how many taps along
    its long axis, and how far apart in texture coordinates they are.

    What `anisotropic_footprint` returns and `Texture.sample_footprint`
    reads. One tap with a step of zero is the plain trilinear read.

    Fieldwise-constructible, because building one by hand is a real thing
    to want -- a test pinning one tap arrangement, a tool asking what a
    level looks like -- and a struct is not a proof. `Footprint(0, 0,
    Vector2(0, 0))` builds, and sampling it would divide by a tap count of
    nothing. So `validate` states the contract and `Texture.sample_footprint`
    asks it, while the renderer's own footprints come from
    `anisotropic_footprint` and go to `Texture._sample_footprint`, which
    does not ask: a fragment loop is not a place to handle an error.
    """

    var level: Float32
    var taps: Int
    var step: Vector2

    def validate(self) raises:
        """Raise unless this footprint can be sampled.

        Raises:
            Error: If the tap count is below one or above `MAX_ANISOTROPY`,
                or the level or either component of the step is not finite.
        """
        if self.taps < 1:
            raise Error("A footprint takes at least one tap")
        if self.taps > MAX_ANISOTROPY:
            raise Error(
                "A footprint takes at most MAX_ANISOTROPY taps: a fragment"
                " pays for every one of them"
            )
        if not isfinite(self.level):
            raise Error("A footprint's level must be finite")
        if not isfinite(self.step.x) or not isfinite(self.step.y):
            raise Error("A footprint's step must be finite")


def _principal_axes(u: Vector2, v: Vector2) -> Vector2:
    """Return the footprint ellipse's two principal lengths, longer first.

    `u` and `v` are the columns of the derivative matrix in texels: how far
    the coordinates move for one pixel right and for one pixel down. The
    footprint is the image of the unit disc under that matrix, an ellipse
    whose semi-axes are its singular values. Those are the square roots of
    the eigenvalues of `J` transpose times `J`, the symmetric two by two

        [ u.u  u.v ]
        [ u.v  v.v ]

    whose eigenvalues are the roots of a quadratic. No decomposition
    library, and nothing that can fail: the discriminant of a symmetric
    matrix is a sum of squares and cannot go negative, bar a rounding,
    which the clamps below take.

    Args:
        u: The first column, in texels.
        v: The second column, in texels.

    Returns:
        The major length in `x` and the minor in `y`, neither below zero.
    """
    var a = u.x * u.x + u.y * u.y
    var b = u.x * v.x + u.y * v.y
    var c = v.x * v.x + v.y * v.y
    var half_sum = (a + c) / 2
    var half_difference = (a - c) / 2
    var spread = sqrt(half_difference * half_difference + b * b)
    # Clamped with `max` rather than with an `if`. Neither can go below
    # zero in exact arithmetic -- `spread` is at most `half_sum`, because
    # the Gram matrix of two real vectors is positive semidefinite -- so a
    # rounding is the only thing either guard is for, and an `if` would be
    # a branch no test could take.
    var larger = max(Float32(0), half_sum + spread)
    var smaller = max(Float32(0), half_sum - spread)
    return Vector2(sqrt(larger), sqrt(smaller))


def _major_direction(u: Vector2, v: Vector2, major: Float32) -> Vector2:
    """Return the unit direction of the footprint's long axis, in texels.

    The long axis lives in the derivative matrix's *output* space, so it is
    an eigenvector of `J` times `J` transpose -- not of the `J` transpose
    times `J` whose eigenvalues `_principal_axes` took. The two share their
    eigenvalues and not their eigenvectors. That matrix is

        [ p  q ]    p = u.x * u.x + v.x * v.x
        [ q  r ]    q = u.x * u.y + v.x * v.y
                    r = u.y * u.y + v.y * v.y

    and either row of it less the eigenvalue on the diagonal gives the
    eigenvector. Either row can be the zero row, so the longer answer of
    the two is taken.

    Args:
        u: The first column of the derivative matrix, in texels.
        v: The second column, in texels.
        major: The major length, `_principal_axes`'s `x`.

    Returns:
        A unit vector along the long axis, in texel space. Its sign is
        arbitrary: the taps are centered, so both ends span one line.
    """
    var q = u.x * u.y + v.x * v.y
    var p = u.x * u.x + v.x * v.x
    var r = u.y * u.y + v.y * v.y
    # Diagonal, which is the axis-aligned footprint: the long axis is
    # whichever texel axis carries more of the two derivatives. Asked
    # with a tolerance rather than of zero, because a derivative that
    # should be zero along one axis arrives as the rounding residue of
    # two interpolations that differ in their last bit, and a `q` made
    # of that residue would turn the long axis by a hair. A tap then
    # landed a hair past a texel's edge, and which texel it read changed
    # with how the compiler fused the interpolation's multiplies and adds.
    var noise = q
    if noise < 0:
        noise = -noise
    if noise <= (p + r) * DIAGONAL_TOLERANCE:
        if p >= r:
            return Vector2(1, 0)
        return Vector2(0, 1)
    var eigenvalue = major * major
    var first = Vector2(q, eigenvalue - p)
    var second = Vector2(eigenvalue - r, q)
    var chosen = first
    if (
        second.x * second.x + second.y * second.y
        > first.x * first.x + first.y * first.y
    ):
        chosen = second
    # No guard on the length, where `q` above guards the diagonal case.
    # `first` is `(q, ...)` and `q` is not zero on this path, so `first` is
    # at least `|q|` long, and `chosen` is the longer of the two. The
    # caller reaches this only when it took more than one tap, which needs
    # a major axis above one texel, so nothing here is near the range
    # where a square could underflow to zero.
    var length = sqrt(chosen.x * chosen.x + chosen.y * chosen.y)
    return Vector2(chosen.x / length, chosen.y / length)


def anisotropic_footprint(
    along_x: Vector2,
    along_y: Vector2,
    width: Int,
    height: Int,
    anisotropy: Int,
) -> Footprint:
    """Return how to read a pixel's footprint, given how far the texture
    coordinates move one pixel over and one pixel down.

    The two derivatives are measured in texels, as
    `render.rasterizer.mip_level` measures them.

    **With an anisotropy of one** the level is the log of the longer
    derivative, the number `mip_level` gives and the number OpenGL's
    isotropic rho gives, so a texture that asks for nothing reads exactly
    as it did.

    **With more**, the footprint is treated as what it is: the ellipse the
    derivative matrix maps the unit disc onto. Its principal lengths are
    that matrix's singular values, which are *not* the lengths of the two
    derivatives. Two derivatives of equal length describe a circle only
    when they are perpendicular. Turn the screen's basis forty-five degrees
    under a surface seen edge-on and the two lengths become equal while the
    footprint stays as long and as thin as it was; measuring the
    derivatives would call that footprint round and blur it by several
    levels. `_principal_axes` takes the real lengths and `_major_direction`
    the real long axis, each from one quadratic.

    **The level follows the minor axis, not the major one divided by the
    taps.** Taps along the long axis filter along the long axis and do
    nothing across the short one, so rounding the tap count up must not
    shrink the level below what the short axis needs. The rule is

        effective minor = max(1, minor, major / taps allowed)
        taps            = clamp(ceil(major / effective minor), 1, allowed)
        level           = log2(effective minor)

    which is continuous where measuring along the major axis jumped: a
    footprint going from sixteen by sixteen to sixteen and a thousandth by
    sixteen gains a tap, and keeps its level instead of losing most of one
    with it. The floor of one is what stops a tap per texel from reading
    any texel twice.

    Pure and shared by both rasterizers, as `wrap_index` is.

    Args:
        along_x: How the coordinates change one pixel to the right.
        along_y: How they change one pixel down.
        width: The texture's width in texels.
        height: Its height.
        anisotropy: How many taps the texture allows, at least one and
            clamped to `MAX_ANISOTROPY`.

    Returns:
        The footprint. A level at or below zero means magnification.
    """
    var u = Vector2(along_x.x * Float32(width), along_x.y * Float32(height))
    var v = Vector2(along_y.x * Float32(width), along_y.y * Float32(height))
    var in_x = sqrt(u.x * u.x + u.y * u.y)
    var in_y = sqrt(v.x * v.x + v.y * v.y)
    var longest = in_x
    if in_y > in_x:
        longest = in_y
    if longest <= 0:
        return Footprint(0, 1, Vector2(0, 0))
    # The isotropic read, unchanged: the longer derivative's own level,
    # negative where the texture is magnified.
    if anisotropy <= 1:
        return Footprint(log2(longest), 1, Vector2(0, 0))
    var allowed = anisotropy
    if allowed > MAX_ANISOTROPY:
        allowed = MAX_ANISOTROPY
    var axes = _principal_axes(u, v)
    var major = axes.x
    var minor = axes.y
    # A degenerate footprint -- a surface collapsed to a line -- has no
    # minor axis at all, and this floor is what keeps its level finite.
    var effective_minor = minor
    if effective_minor < 1:
        effective_minor = 1
    var reach_of_one = major / Float32(allowed)
    if reach_of_one > effective_minor:
        effective_minor = reach_of_one
    # Both ends clamped with `min` and `max` rather than with an `if`.
    # `effective_minor` is at least one and at least `major / allowed`, so
    # the quotient already lies between one and `allowed` and neither
    # guard has a reachable second side. They are here against a rounding
    # that could put `ceil` one over the cap, which must not happen:
    # `Footprint.validate` refuses more taps than the cap allows.
    var taps = max(1, min(Int(ceil(major / effective_minor)), allowed))
    if taps == 1:
        # One tap is the trilinear read, and the trilinear read of a round
        # footprint is the level the longer derivative wants: the same
        # number the isotropic path above returns, so a texture whose
        # footprint happens to be round reads the same whether or not it
        # asked for taps it cannot use.
        return Footprint(log2(longest), 1, Vector2(0, 0))
    var direction = _major_direction(u, v, major)
    # The taps span the long axis once: `taps` steps of the axis divided by
    # the count, in texels, taken back into texture coordinates by the size
    # they were measured against.
    var step = major / Float32(taps)
    return Footprint(
        log2(effective_minor),
        taps,
        Vector2(
            direction.x * step / Float32(width),
            direction.y * step / Float32(height),
        ),
    )


def texture_from(
    image: DecodedImage,
    wrap: Wrap = REPEAT,
    filter: Filter = BILINEAR,
    color_space: Optional[ColorSpace] = None,
    mipmapped: Bool = True,
    alpha: Alpha = COVERAGE,
) raises -> Texture:
    """Return a texture holding a decoded image's pixels.

    The join between `render.png`'s decoder and this module. Both hold
    eight-bit RGBA in row-major order from the top, so there is nothing to
    convert — which is the point of widening every color type while decoding
    rather than carrying five shapes through the renderer.

    **The color space comes from the file unless you say otherwise.** A PNG
    does not imply sRGB: it can declare a gamma of one, which is linear, and
    decoding that through the sRGB curve turns a mid gray of 128 into a fifth
    of the light instead of half of it. Passing `color_space` overrides what
    the file said, which is what a normal map stored without any tag needs.

    A file that declared something this decoder could not interpret — an ICC
    profile, or a gamma that is neither sRGB's nor one — arrives as
    `UNKNOWN_SPACE` and must be settled here. Refusing beats guessing: the
    caller knows what the image is for and the decoder does not.

    Args:
        image: The decoded image.
        wrap: How coordinates outside the unit square are resolved.
        filter: `NEAREST` or `BILINEAR`.
        color_space: `SRGB` or `LINEAR` to override, or nothing to use
            whatever the file declared.
        mipmapped: Build the chain of halved copies.
        alpha: `COVERAGE` if the file's alpha hides color, `IGNORED` if it
            means nothing; see `Alpha`.

    Returns:
        The texture.

    Raises:
        Error: If the file's declared color space could not be interpreted
            and none was given.
    """
    var space = color_space.or_else(image.color_space)
    if space == UNKNOWN_SPACE:
        raise Error(
            "This image declares a color space that cannot be interpreted;"
            " pass SRGB or LINEAR to say how to read it"
        )
    return Texture(
        image.width,
        image.height,
        image.pixels.copy(),
        wrap,
        filter,
        space,
        mipmapped,
        alpha,
    )


def data_texture(
    width: Int,
    height: Int,
    data: List[Float32],
    channels: Int = 4,
    wrap: Wrap = CLAMP,
    filter: Filter = NEAREST,
    mipmapped: Bool = False,
    alpha: Alpha = COVERAGE,
) raises -> Texture:
    """Return a texture built from raw numbers, three.js's `DataTexture`.

    For data that was never an image file: a ramp a toon material steps
    through, a mask, a lookup table, a height field. Each number is a
    fraction from zero to one and becomes one byte, quantized without any
    transfer function, and the texture is `LINEAR`, so the byte comes
    back as the fraction it was. A number outside zero to one is clamped:
    a byte cannot hold it, and this project's textures are bytes.

    The numbers fill the channels in order, red first, and a channel the
    data does not reach is zero for a color and one for alpha, exactly as
    a `RedFormat` or `RGFormat` texture samples in WebGL. A one-channel
    texture is a red one, not a gray one: green and blue read zero. A
    toon ramp reads red alone, so one channel is all it needs; a gray
    image wants three equal numbers a texel.

    The defaults are three.js's own for a `DataTexture`: nearest, no mip
    chain, and the edges clamped, because data is read where it was
    written and not filtered, tiled or averaged.

    Args:
        width: Image width in texels.
        height: Image height in texels.
        data: `channels` numbers per texel, row-major from the top.
        channels: How many numbers each texel holds, filling red, green,
            blue and alpha in that order. The colors not given are zero
            and an alpha not given is one: three.js's `RedFormat`,
            `RGFormat`, `RGBFormat` and `RGBAFormat`, as WebGL samples
            them.
        wrap: How coordinates outside the unit square are resolved.
        filter: `NEAREST` or `BILINEAR`.
        mipmapped: Build the chain of halved copies.
        alpha: `COVERAGE` if the alpha channel hides color, `IGNORED` if
            it means nothing, as it does for an alpha map or a ramp.

    Returns:
        The texture, stored `LINEAR`.

    Raises:
        Error: If the dimensions are not positive, `channels` is not one
            through four, the data holds any number that is not finite,
            or its length is not `width * height * channels`.
    """
    if width <= 0 or height <= 0:
        raise Error("Texture dimensions must be positive")
    if channels < 1 or channels > 4:
        raise Error("A data texture holds one through four numbers a texel")
    if len(data) != width * height * channels:
        raise Error("Data texture length does not match the dimensions")
    var pixels = List[UInt8]()
    pixels.reserve(width * height * Texture.CHANNELS)
    # Both dimensions are positive, so the loop cannot run zero times.
    for texel in range(width * height):  # pragma: no branch
        var base = texel * channels
        for channel in range(Texture.CHANNELS):  # pragma: no branch
            # Red, green and blue not given are zero; an alpha not given
            # is one, so the texel is opaque.
            var byte = UInt8(0)
            if channel == 3:
                byte = 255
            if channel < channels:
                byte = _fraction_byte(data[base + channel])
            pixels.append(byte)
    return Texture(
        width, height, pixels^, wrap, filter, LINEAR, mipmapped, alpha
    )


def float_texture(
    width: Int,
    height: Int,
    var data: List[Float32],
    wrap: Wrap = CLAMP,
    filter: Filter = BILINEAR,
    mipmapped: Bool = False,
    alpha: Alpha = COVERAGE,
) raises -> Texture:
    """Return a texture that holds linear light as floats: three.js's
    `DataTexture` with a `type` of `FloatType`.

    What an HDR image is. Every number is kept as it is, light above one
    included, and sampled as it is: no ramp, no clamp, no transfer
    function. Filtering and the mip chain average the floats premultiplied,
    as they average a byte texture's decoded light.

    The defaults are three.js's `RGBELoader` and `EXRLoader` settings:
    clamped, bilinear, and no mip chain. Ask for a chain to sample a
    minified image, or to give a rough surface a blurred environment.

    Args:
        width: Image width in texels.
        height: Image height in texels.
        data: Row-major RGBA floats from the top, width * height * 4.
        wrap: How coordinates outside the unit square are resolved.
        filter: `NEAREST` or `BILINEAR`.
        mipmapped: Build the chain of halved copies, in floats.
        alpha: `COVERAGE` if the alpha channel hides color, `IGNORED` if
            it means nothing.

    Returns:
        The texture: `FLOAT_TYPE`, `LINEAR`.

    Raises:
        Error: If the dimensions are not positive, the data's length is
            not `width * height * 4`, a number is not finite, or the
            wrap, filter or alpha mode is none of the named values.
    """
    if width <= 0 or height <= 0:
        raise Error("Texture dimensions must be positive")
    if len(data) != width * height * Texture.CHANNELS:
        raise Error("Float texture length does not match the dimensions")
    # Both dimensions are positive, so the loop cannot run zero times.
    for index in range(len(data)):  # pragma: no branch
        # An infinity or a NaN poisons every filter that reaches it, and
        # every level of the chain above it: refused, not sampled.
        if not isfinite(data[index]):
            raise Error("A float texture holds finite numbers")
    var image = Texture()
    image.width = width
    image.height = height
    image.texel_type = FLOAT_TYPE
    image.data = data^
    image.wrap = wrap
    image.filter = filter
    image.color_space = LINEAR
    image.alpha = alpha
    image.validate()
    if mipmapped:
        image._build_mipmaps()
    return image^


def float_texture_from(
    image: FloatImage,
    wrap: Wrap = CLAMP,
    filter: Filter = BILINEAR,
    mipmapped: Bool = False,
    alpha: Alpha = COVERAGE,
) raises -> Texture:
    """Return a float texture holding an HDR image's pixels.

    The join between `render.rgbe` or `render.exr` and this module, as
    `texture_from` is the join to the PNG reader. The defaults are the
    loaders' own in three.js: clamped, bilinear, no chain.

    Args:
        image: The decoded HDR image.
        wrap: How coordinates outside the unit square are resolved.
        filter: `NEAREST` or `BILINEAR`.
        mipmapped: Build the chain of halved copies.
        alpha: `COVERAGE` or `IGNORED`; see `Alpha`.

    Returns:
        The texture: `FLOAT_TYPE`, `LINEAR`.

    Raises:
        Error: Everything `float_texture` raises.
    """
    return float_texture(
        image.width,
        image.height,
        image.pixels.copy(),
        wrap,
        filter,
        mipmapped,
        alpha,
    )


def _fraction_byte(value: Float32) raises -> UInt8:
    """Return a fraction from zero to one as the byte that stands for it,
    without any transfer function, clamped at either end.

    Raises:
        Error: If the number is not finite.
    """
    if not isfinite(value):
        raise Error("A data texture holds finite numbers")
    var held = value
    if held < 0:
        held = 0
    if held > 1:
        held = 1
    return UInt8(Int(held * 255 + 0.5))


def texture_of(
    image: Framebuffer,
    wrap: Wrap = CLAMP,
    filter: Filter = BILINEAR,
    mipmapped: Bool = True,
    alpha: Alpha = COVERAGE,
) raises -> Texture:
    """Return a texture holding a rendered image, so a later draw can
    sample what an earlier one drew: three.js's `WebGLRenderTarget.texture`.

    A `Framebuffer` holds eight-bit sRGB with unassociated alpha, which is
    exactly what a color texture holds, so nothing is converted: the
    bytes are copied and read back as the light they encode. Resolve a
    `RenderTarget` first, or ask it for `texture` directly.

    **It is a snapshot, in bytes.** The copy does not follow the target
    it came from, and light above one was clamped or tone mapped away
    when the image was resolved: two pixels of linear one and four are
    both byte 255 here, and no later exposure can tell them apart. That
    is what a picture on a screen in the scene wants. A linear texture
    that keeps a render's range for a later pass is another thing, and
    this is not it.

    The edges are clamped by default, as three.js clamps a render
    target's texture: a rendered image has no reason to tile.

    Args:
        image: The rendered image.
        wrap: How coordinates outside the unit square are resolved.
        filter: `NEAREST` or `BILINEAR`.
        mipmapped: Build the chain of halved copies.
        alpha: `COVERAGE`, the default, so a transparent clear color
            reads as nothing; `IGNORED` to read the color under it.

    Returns:
        The texture, stored `SRGB`.

    Raises:
        Error: If the wrap, filter or alpha mode is none of the named
            values.
    """
    return Texture(
        image.width,
        image.height,
        image.pixels.copy(),
        wrap,
        filter,
        SRGB,
        mipmapped,
        alpha,
    )


def depth_texture_of(image: Framebuffer, wrap: Wrap = CLAMP) raises -> Texture:
    """Return a rendered image's depth buffer as a texture: a preview of
    three.js's `DepthTexture`, at eight bits.

    Each texel is the window-space depth a GPU stores, zero at the near
    plane and one at the far plane, as one gray byte in every color
    channel: the NDC depth the framebuffer keeps, halved and moved up by
    a half, quantized without any transfer function. A pixel nothing was
    drawn into is at the far plane. The texture is `LINEAR` and ignores
    its alpha, because a depth is data, and it is read nearest with no
    chain: two depths averaged are the depth of nothing.

    **It is a picture of the depth, not the depth.** A byte holds 256
    steps, and a perspective projection spends most of its range near
    the near plane: with planes at a tenth of a meter and a hundred, a
    surface one meter away is byte 230, ten meters is 253, and forty
    meters is 255, the same byte as the far plane and the background.
    three.js's `DepthTexture` holds a real depth format. Use this to
    look at a depth, and nothing that compares or reconstructs one.

    Args:
        image: The rendered image, with the depth `Framebuffer` carries.
        wrap: How coordinates outside the unit square are resolved.

    Returns:
        The texture.

    Raises:
        Error: If the wrap mode is none of the named values.
    """
    return depth_texture_of_buffer(image.width, image.height, image.depth, wrap)


def depth_texture_of_buffer(
    width: Int, height: Int, depth: List[Float32], wrap: Wrap = CLAMP
) raises -> Texture:
    """Return a depth buffer as a texture, as `depth_texture_of` returns a
    framebuffer's, without a framebuffer around it.

    What `RenderTarget.depth_texture` calls, so a target's depth is read
    as it stands without a color image being built to carry it.

    Args:
        width: The buffer's width in pixels.
        height: Its height.
        depth: One NDC depth per pixel, row-major from the top, infinity
            where nothing was drawn.
        wrap: How coordinates outside the unit square are resolved.

    Returns:
        The texture; see `depth_texture_of`.

    Raises:
        Error: If the dimensions are not positive, the buffer's length
            does not match them, or the wrap mode is none of the named
            values.
    """
    if width <= 0 or height <= 0:
        raise Error("Texture dimensions must be positive")
    if len(depth) != width * height:
        raise Error("Depth buffer length does not match the dimensions")
    var pixels = List[UInt8]()
    pixels.reserve(width * height * Texture.CHANNELS)
    # Both dimensions are positive, so the loop always runs.
    for slot in range(width * height):  # pragma: no branch
        var z = depth[slot]
        var gray = UInt8(255)
        if z != inf[DType.float32]():
            gray = _fraction_byte(z * 0.5 + 0.5)
        pixels.append(gray)
        pixels.append(gray)
        pixels.append(gray)
        pixels.append(255)
    return Texture(
        width, height, pixels^, wrap, NEAREST, LINEAR, False, IGNORED
    )


def checkerboard(
    size: Int,
    squares: Int,
    light: Color,
    dark: Color,
    wrap: Wrap = REPEAT,
    filter: Filter = BILINEAR,
    color_space: ColorSpace = SRGB,
    mipmapped: Bool = True,
    alpha: Alpha = COVERAGE,
) raises -> Texture:
    """Return a square checkerboard, the traditional mapping test image.

    Hard edges on a regular grid are what make a mapping error obvious: a
    wrong `uv` moves a square somewhere visibly wrong, and a wrong
    interpolation bends the grid lines rather than merely shading oddly.
    Ask for `NEAREST` to keep the edges hard; the default filters as
    three.js's defaults filter.

    Args:
        size: The image's width and height in texels.
        squares: How many squares fit across it; must divide `size`.
        light: Color of the square at the top left.
        dark: Color of its neighbors.
        wrap: How coordinates outside the unit square are resolved.
        filter: `NEAREST` or `BILINEAR`.
        color_space: `SRGB` or `LINEAR`.
        mipmapped: Build the chain of halved copies.
        alpha: `COVERAGE` or `IGNORED`; see `Alpha`.

    Returns:
        The texture.

    Raises:
        Error: If the size or square count is not positive, or the squares do
            not divide the image evenly — which would put a half square at
            one edge and make a tiled image visibly discontinuous.
    """
    if size <= 0:
        raise Error("A checkerboard needs a positive size")
    if squares <= 0:
        raise Error("A checkerboard needs at least one square")
    if size % squares != 0:
        raise Error("A checkerboard's squares must divide its size evenly")

    var step = size // squares
    var pixels = List[UInt8]()
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var shade = light
            if (x // step + y // step) % 2 == 1:
                shade = dark
            pixels.append(shade.r)
            pixels.append(shade.g)
            pixels.append(shade.b)
            pixels.append(shade.a)
    return Texture(
        size, size, pixels^, wrap, filter, color_space, mipmapped, alpha
    )
