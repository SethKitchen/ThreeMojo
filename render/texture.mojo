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

**Nearest-neighbour only, for now.** A sample takes the colour of whichever
texel it lands in, with no blending between neighbours. That is the honest
starting point: it makes the mapping itself visible — a checkerboard's edges
stay hard, so a wrong `uv` shows up as a misplaced square rather than a vague
blur — and bilinear filtering is a separate, testable change on top of it.

**Out-of-range coordinates wrap.** Nothing constrains `uv` to the unit square:
a geometry can ask for its texture five times across, and clipping can produce
coordinates outside anything the author wrote. `REPEAT` tiles, `CLAMP` holds
the edge colour, and `MIRROR` alternates direction each tile — the same three
three.js offers.
"""

from render.framebuffer import Color, FloatColor
from std.math import floor

# How a coordinate outside the unit square is resolved.
# Tile the image; 1.5 reads the same texel as 0.5.
comptime REPEAT = 0
# Hold the edge texel; 1.5 reads the same texel as 1.0.
comptime CLAMP = 1
# Tile, flipping direction every other tile, so tiles meet without a seam.
comptime MIRROR = 2


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

    def __init__(
        out self,
        width: Int,
        height: Int,
        var pixels: List[UInt8],
        wrap: Int = REPEAT,
    ) raises:
        """Create a texture from RGBA bytes.

        Args:
            width: Image width in texels.
            height: Image height in texels.
            pixels: Row-major RGBA bytes from the top, width * height * 4.
            wrap: How coordinates outside the unit square are resolved.

        Raises:
            Error: If the dimensions are not positive, the buffer length
                disagrees with them, or the wrap mode is not one of the three.
        """
        if width <= 0 or height <= 0:
            raise Error("Texture dimensions must be positive")
        if len(pixels) != width * height * Self.CHANNELS:
            raise Error("Texture buffer length does not match the dimensions")
        if wrap != REPEAT and wrap != CLAMP and wrap != MIRROR:
            raise Error("Unknown texture wrap mode")
        self.width = width
        self.height = height
        self.pixels = pixels^
        self.wrap = wrap

    def __init__(out self, *, copy: Self):
        """Copy another texture, image data included."""
        self.width = copy.width
        self.height = copy.height
        self.pixels = copy.pixels.copy()
        self.wrap = copy.wrap

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

    def sample(self, u: Float32, v: Float32) -> FloatColor:
        """Return the colour at a texture coordinate.

        Nearest neighbour: the sample takes whichever texel it lands in. `v`
        is flipped because rows run down from the top while texture space
        counts up from the bottom.

        A coordinate of exactly zero or one sits on a tile boundary, and the
        wrap mode decides which side it belongs to. Under `REPEAT` both ends
        of the range name the same texel, which is what makes a tiled texture
        seamless; under `CLAMP` they name opposite edges, which is what makes
        a clamped one hold still.

        Does not raise: a fragment shader is not a place to handle errors, and
        every coordinate has an answer once a wrap mode is chosen.

        Args:
            u: Horizontal coordinate, 0 at the left edge.
            v: Vertical coordinate, 0 at the *bottom* edge.

        Returns:
            The colour found there, or opaque white if the texture is blank.
        """
        if self.is_blank():
            return FloatColor(1.0, 1.0, 1.0, 1.0)
        var column = Int(floor(u * Float32(self.width)))
        var row = Int(floor((1 - v) * Float32(self.height)))
        var offset = (
            wrap_index(row, self.height, self.wrap) * self.width
            + wrap_index(column, self.width, self.wrap)
        ) * Self.CHANNELS
        return FloatColor(
            of=Color(
                self.pixels[offset],
                self.pixels[offset + 1],
                self.pixels[offset + 2],
                self.pixels[offset + 3],
            )
        )


def checkerboard(
    size: Int, squares: Int, light: Color, dark: Color, wrap: Int = REPEAT
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
    return Texture(size, size, pixels^, wrap)
