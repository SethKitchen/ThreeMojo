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
lands in; `BILINEAR` blends the four around it. Nearest keeps a checkerboard's
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

**A texture can move, tile and turn on its surface.** three.js's `offset`,
`repeat`, `rotation` and `center` are fields here as there, and
`uv_transform` is the 2D affine matrix they come to, three.js's
`Texture.matrix`. The renderer carries every coordinate of a mesh through
its texture's matrix before the fragment samples with it, as three.js's
vertex shader does, so a `repeat` of two tiles the image twice across and an
`offset` of a half slides it half a tile. The texture itself does not change:
the transform is on the coordinates that reach it, which is why the wrap
mode still decides what a coordinate past the edge reads.
"""

from math.matrix3 import Matrix3
from math.vector2 import Vector2
from render.framebuffer import Color, FloatColor
from render.png import DecodedImage
from render.srgb import (
    LINEAR,
    SRGB,
    UNKNOWN_SPACE,
    ColorSpace,
    decode_ramp,
    linear_to_srgb,
)
from std.math import floor
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

    def __init__(out self):
        """Create the blank texture, which samples as opaque white.

        White is the identity for modulation, so a mesh with no texture shades
        exactly as it did before textures existed. That makes "no texture" a
        value rather than a special case the renderer has to branch on.
        """
        self.width = 0
        self.height = 0
        self.pixels = List[UInt8]()
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

    def __init__(
        out self,
        width: Int,
        height: Int,
        var pixels: List[UInt8],
        wrap: Wrap = REPEAT,
        filter: Filter = NEAREST,
        color_space: ColorSpace = SRGB,
        mipmapped: Bool = False,
        alpha: Alpha = COVERAGE,
    ) raises:
        """Create a texture from RGBA bytes.

        Args:
            width: Image width in texels.
            height: Image height in texels.
            pixels: Row-major RGBA bytes from the top, width * height * 4.
            wrap: How coordinates outside the unit square are resolved.
            filter: `NEAREST` or `BILINEAR`.
            color_space: `SRGB` for a color image, the default because that
                is what an image file holds; `LINEAR` for data that is not
                color and must not be decoded. `UNKNOWN_SPACE` is refused:
                it is a decoder's admission, not a way to read texels.
            mipmapped: Build the chain of halved copies. Costs a third more
                memory and is what stops a distant surface from sparkling.
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
        self.wrap = wrap
        self.filter = filter
        self.alpha = alpha
        self.levels = 1
        self.offsets = [0]
        self.offset = Vector2(0, 0)
        self.repeat = Vector2(1, 1)
        self.rotation = Angle(0.0, RADIAN)
        self.center = Vector2(0, 0)
        # After every field is set, so it is the same check the GPU upload
        # makes on a texture that may have been edited since.
        self.validate()
        if mipmapped:
            self._build_mipmaps()

    def validate(self) raises:
        """Refuse a wrap, filter, color space or alpha mode that is none of
        the named values.

        The types stop a bare integer at compile time and nothing else: a
        struct's fields are open, so `Wrap(9)` constructs, and so does
        `image.filter = Filter(5)` after the image was checked. The
        constructor calls this, and `render.gpu.flatten_textures` calls it
        again on the way to the device, because a value that is neither of
        two things was once read one way by the host and the other way by
        the kernel.

        Raises:
            Error: If the wrap mode, the filter, the color space or the
                alpha mode is not one of its named constants.
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

    def __init__(out self, *, copy: Self):
        """Copy another texture, image data included."""
        self.width = copy.width
        self.height = copy.height
        self.pixels = copy.pixels.copy()
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
            Error: If the texture is blank or the coordinates are outside it.
        """
        if self.is_blank():
            raise Error("The blank texture has no texels")
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
            self.offsets.append(len(self.pixels))
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
                            var texel = FloatColor(
                                self.ramp[Int(self.pixels[at])],
                                self.ramp[Int(self.pixels[at + 1])],
                                self.ramp[Int(self.pixels[at + 2])],
                                self._alpha_of(self.pixels[at + 3]),
                            ).premultiplied()
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
                    self.pixels.append(_to_byte(mixed.r, self.color_space))
                    self.pixels.append(_to_byte(mixed.g, self.color_space))
                    self.pixels.append(_to_byte(mixed.b, self.color_space))
                    self.pixels.append(_to_byte(mixed.a, LINEAR))
            level += 1
            self.levels = level + 1

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
        # Color through the ramp; alpha is not color and never decoded, and
        # is not read at all when the texture ignores it.
        return FloatColor(
            self.ramp[Int(self.pixels[offset])],
            self.ramp[Int(self.pixels[offset + 1])],
            self.ramp[Int(self.pixels[offset + 2])],
            self._alpha_of(self.pixels[offset + 3]),
        )

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


def texture_from(
    image: DecodedImage,
    wrap: Wrap = REPEAT,
    filter: Filter = BILINEAR,
    color_space: Optional[ColorSpace] = None,
    mipmapped: Bool = False,
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


def checkerboard(
    size: Int,
    squares: Int,
    light: Color,
    dark: Color,
    wrap: Wrap = REPEAT,
    filter: Filter = NEAREST,
    color_space: ColorSpace = SRGB,
    mipmapped: Bool = False,
    alpha: Alpha = COVERAGE,
) raises -> Texture:
    """Return a square checkerboard, the traditional mapping test image.

    Hard edges on a regular grid are what make a mapping error obvious: a
    wrong `uv` moves a square somewhere visibly wrong, and a wrong
    interpolation bends the grid lines rather than merely shading oddly.

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
