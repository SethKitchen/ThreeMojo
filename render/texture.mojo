# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An image to look colours up in, from three.js `src/textures/Texture.js`.

The payoff for carrying texture coordinates all the way to the fragment: a `uv`
pair names a place in an image, and this is what reads it.

**Rows run downwards, `v` runs upwards.** An image's first row is its top one —
that is how PNG stores it and how `Framebuffer` addresses it — while texture
space puts its origin at the bottom left, as OpenGL and three.js do. Sampling
is where those two disagree, so sampling is where it is reconciled, once:
`1 - v` turns one into the other. three.js spells the same reconciliation
`flipY`, and has it on by default.

**Two filters.** `NEAREST` takes the colour of whichever texel the sample
lands in; `BILINEAR` blends the four around it. Nearest keeps a checkerboard's
edges hard, which is what makes a mapping error legible — a wrong `uv` shows a
misplaced square rather than a vague blur — and it is exact, so both backends
agree on it to the last bit. Bilinear is what you want once the image is meant
to be looked at rather than debugged: at a glancing angle nearest turns a fine
pattern into noise.

**Texels are decoded before anything is done with them.** An image file holds
sRGB, and filtering or lighting encoded values is arithmetic on the wrong
numbers — see `render.srgb`. A texture therefore carries which space it is in,
and colour textures decode by default. Alpha never does: it is not colour.

**Out-of-range coordinates wrap.** Nothing constrains `uv` to the unit square:
a geometry can ask for its texture five times across, and clipping can produce
coordinates outside anything the author wrote. `REPEAT` tiles, `CLAMP` holds
the edge colour, and `MIRROR` alternates direction each tile — the same three
three.js offers.
"""

from render.framebuffer import Color, FloatColor, Framebuffer
from render.srgb import LINEAR, SRGB, decode_ramp, linear_to_srgb
from std.math import floor

# How a coordinate outside the unit square is resolved.
# Tile the image; 1.5 reads the same texel as 0.5.
comptime REPEAT = 0
# Hold the edge texel; 1.5 reads the same texel as 1.0.
comptime CLAMP = 1
# Tile, flipping direction every other tile, so tiles meet without a seam.
comptime MIRROR = 2

# How a sample between texel centres is resolved.
# Take whichever texel the sample lands in. Hard edges, visible texels.
comptime NEAREST = 0
# Blend the four texels around the sample by how close it is to each.
comptime BILINEAR = 1


def mix(near: Float32, far: Float32, t: Float32) -> Float32:
    """Return one channel a fraction `t` of the way from `near` to `far`."""
    return near + (far - near) * t


def mix_colour(near: FloatColor, far: FloatColor, t: Float32) -> FloatColor:
    """Return one colour a fraction `t` of the way to another.

    Mixed premultiplied, so a transparent colour contributes no colour — the
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


def blend_texels(
    lower_left: FloatColor,
    lower_right: FloatColor,
    upper_left: FloatColor,
    upper_right: FloatColor,
    across: Float32,
    down: Float32,
) -> FloatColor:
    """Bilinear blend of four texels, done where hidden colour weighs nothing.

    Filtering is a weighted sum, and a weighted sum of *straight* colours lets
    an invisible texel contribute its colour anyway. An opaque red beside a
    fully transparent green averages to half red and half green, so a fringe
    of a colour nobody put there appears along every transparent edge — the
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
        The blended colour, with straight alpha.
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
        The blended colour.
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


def _to_byte(value: Float32, space: Int) -> UInt8:
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


def wrap_index(coordinate: Int, extent: Int, mode: Int) -> Int:
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
    var wrap: Int
    var filter: Int
    var color_space: Int
    # How many images the chain holds: the full-size one, then each halving
    # down to a single texel. One means no chain.
    var levels: Int
    # The 256 linear values this texture's bytes stand for. Built once here
    # rather than per fragment, because `pow` has only 256 possible inputs
    # and sampling happens per pixel.
    var ramp: List[Float32]

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
        self.ramp = _identity_ramp()
        self.levels = 1

    def __init__(
        out self,
        width: Int,
        height: Int,
        var pixels: List[UInt8],
        wrap: Int = REPEAT,
        filter: Int = NEAREST,
        color_space: Int = SRGB,
        mipmapped: Bool = False,
    ) raises:
        """Create a texture from RGBA bytes.

        Args:
            width: Image width in texels.
            height: Image height in texels.
            pixels: Row-major RGBA bytes from the top, width * height * 4.
            wrap: How coordinates outside the unit square are resolved.
            filter: `NEAREST` or `BILINEAR`.
            color_space: `SRGB` for a colour image, the default because that
                is what an image file holds; `LINEAR` for data that is not
                colour and must not be decoded.
            mipmapped: Build the chain of halved copies. Costs a third more
                memory and is what stops a distant surface from sparkling.

        Raises:
            Error: If the dimensions are not positive, the buffer length
                disagrees with them, or either mode is not one this knows.
        """
        if width <= 0 or height <= 0:
            raise Error("Texture dimensions must be positive")
        if len(pixels) != width * height * Self.CHANNELS:
            raise Error("Texture buffer length does not match the dimensions")
        if wrap != REPEAT and wrap != CLAMP and wrap != MIRROR:
            raise Error("Unknown texture wrap mode")
        if filter != NEAREST and filter != BILINEAR:
            raise Error("Unknown texture filter mode")
        if color_space != SRGB and color_space != LINEAR:
            raise Error("Unknown texture colour space")
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
        self.levels = 1
        if mipmapped:
            self._build_mipmaps()

    def __init__(out self, *, copy: Self):
        """Copy another texture, image data included."""
        self.width = copy.width
        self.height = copy.height
        self.pixels = copy.pixels.copy()
        self.wrap = copy.wrap
        self.filter = copy.filter
        self.color_space = copy.color_space
        self.ramp = copy.ramp.copy()
        self.levels = copy.levels

    def is_blank(self) -> Bool:
        """Return True if this is the blank texture."""
        return self.width == 0

    def texel(self, x: Int, y: Int) raises -> Color:
        """Return the colour at a texel, by row and column from the top.

        Args:
            x: Column, from the left.
            y: Row, from the top.

        Returns:
            The colour stored there.

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
        colour must weigh nothing, and light is what averages — and encoded
        back to bytes at each level, which is what a GPU stores too.

        A chain exists to answer a question the full-size image cannot: when
        one pixel covers many texels, which one is the colour? Any single
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
                            var texel = FloatColor(
                                self.ramp[Int(self.pixels[at])],
                                self.ramp[Int(self.pixels[at + 1])],
                                self.ramp[Int(self.pixels[at + 2])],
                                Float32(self.pixels[at + 3]) / 255,
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
            The colour found there, or opaque white if the texture is blank.

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
            self.level_offset(level)
            + (
                wrap_index(y, tall, self.wrap) * wide
                + wrap_index(x, wide, self.wrap)
            )
            * Self.CHANNELS
        )
        # Colour through the ramp; alpha is not colour and never decoded.
        return FloatColor(
            self.ramp[Int(self.pixels[offset])],
            self.ramp[Int(self.pixels[offset + 1])],
            self.ramp[Int(self.pixels[offset + 2])],
            Float32(self.pixels[offset + 3]) / 255,
        )

    def sample_at(
        self, u: Float32, v: Float32, level: Int
    ) raises -> FloatColor:
        """Return the colour at a coordinate, read from one mip level.

        An explicit level lookup, so a level the chain does not hold is
        rejected rather than clamped. `sample_level` is the other interface:
        it takes a fractional level of the kind a footprint produces, where
        landing outside the chain is ordinary and clamping is the answer.

        Args:
            u: Horizontal coordinate, 0 at the left edge.
            v: Vertical coordinate, 0 at the *bottom* edge.
            level: Which image of the chain, zero being full size.

        Returns:
            The colour found there, or opaque white if the texture is blank.

        Raises:
            Error: If the texture is not blank and has no such level.
        """
        if self.is_blank():
            return FloatColor(1.0, 1.0, 1.0, 1.0)
        if not self._has_level(level):
            raise Error("No such mip level")
        return self._sample_at(u, v, level)

    def _sample_at(self, u: Float32, v: Float32, level: Int) -> FloatColor:
        """Return the colour at a coordinate without checking `level` exists.

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

        # Texel centres are at half-integers, so shift the sample into a space
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
        """Return the colour at a coordinate, blended between two mip levels.

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
            The colour found there, or opaque white if the texture is blank.
        """
        if self.is_blank() or self.levels == 1 or level <= 0:
            return self._sample_at(u, v, 0)
        if level >= Float32(self.levels - 1):
            return self._sample_at(u, v, self.levels - 1)
        var lower = Int(floor(level))
        return mix_colour(
            self._sample_at(u, v, lower),
            self._sample_at(u, v, lower + 1),
            level - Float32(lower),
        )

    def sample(self, u: Float32, v: Float32) -> FloatColor:
        """Return the colour at a texture coordinate.

        `v` is flipped because rows run down from the top while texture space
        counts up from the bottom.

        Under `NEAREST` the sample takes whichever texel it lands in. A
        coordinate of exactly zero or one sits on a tile boundary, and the
        wrap mode decides which side it belongs to: under `REPEAT` both ends
        of the range name the same texel, which is what makes a tiled texture
        seamless; under `CLAMP` they name opposite edges.

        Under `BILINEAR` it blends the four texels around it. Texel *centres*
        sit at half-integers, which is the whole reason for the half subtracted
        below: without it the blend is offset by half a texel and every image
        drifts diagonally. The four neighbours are fetched through the wrap
        mode, so a bilinear `REPEAT` texture blends across its own seam and a
        `CLAMP` one holds its edge instead of fading out of it.

        Does not raise: a fragment shader is not a place to handle errors, and
        every coordinate has an answer once the modes are chosen.

        Args:
            u: Horizontal coordinate, 0 at the left edge.
            v: Vertical coordinate, 0 at the *bottom* edge.

        Returns:
            The colour found there, or opaque white if the texture is blank.
        """
        if self.is_blank():
            return FloatColor(1.0, 1.0, 1.0, 1.0)

        if self.filter == NEAREST:
            return self._wrapped_texel(
                Int(floor(u * Float32(self.width))),
                Int(floor((1 - v) * Float32(self.height))),
                0,
            )

        # Texel centres are at half-integers, so shift the sample into a space
        # where they are at integers, and blend between the two either side.
        var across = u * Float32(self.width) - 0.5
        var down = (1 - v) * Float32(self.height) - 0.5
        var column = Int(floor(across))
        var row = Int(floor(down))
        return blend_texels(
            self._wrapped_texel(column, row, 0),
            self._wrapped_texel(column + 1, row, 0),
            self._wrapped_texel(column, row + 1, 0),
            self._wrapped_texel(column + 1, row + 1, 0),
            across - Float32(column),
            down - Float32(row),
        )


def texture_from(
    image: Framebuffer,
    wrap: Int = REPEAT,
    filter: Int = BILINEAR,
    color_space: Int = SRGB,
    mipmapped: Bool = False,
) raises -> Texture:
    """Return a texture holding a decoded image's pixels.

    The join between `render.png`'s decoder and this module. Both already hold
    eight-bit RGBA in row-major order from the top, so there is nothing to
    convert -- which is the point of widening every colour type to RGBA while
    decoding rather than carrying five shapes through the renderer.

    Args:
        image: The decoded image.
        wrap: How coordinates outside the unit square are resolved.
        filter: `NEAREST` or `BILINEAR`.
        color_space: `SRGB` for a colour image, `LINEAR` for data that merely
            happens to be stored in one.
        mipmapped: Build the chain of halved copies.

    Returns:
        The texture.

    Raises:
        Error: If any argument is not one this module knows.
    """
    return Texture(
        image.width,
        image.height,
        image.pixels.copy(),
        wrap,
        filter,
        color_space,
        mipmapped,
    )


def checkerboard(
    size: Int,
    squares: Int,
    light: Color,
    dark: Color,
    wrap: Int = REPEAT,
    filter: Int = NEAREST,
    color_space: Int = SRGB,
    mipmapped: Bool = False,
) raises -> Texture:
    """Return a square checkerboard, the traditional mapping test image.

    Hard edges on a regular grid are what make a mapping error obvious: a
    wrong `uv` moves a square somewhere visibly wrong, and a wrong
    interpolation bends the grid lines rather than merely shading oddly.

    Args:
        size: The image's width and height in texels.
        squares: How many squares fit across it; must divide `size`.
        light: Colour of the square at the top left.
        dark: Colour of its neighbours.
        wrap: How coordinates outside the unit square are resolved.
        filter: `NEAREST` or `BILINEAR`.
        color_space: `SRGB` or `LINEAR`.
        mipmapped: Build the chain of halved copies.

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
    return Texture(size, size, pixels^, wrap, filter, color_space, mipmapped)
