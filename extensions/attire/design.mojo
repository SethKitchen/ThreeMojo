# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Designs woven or embroidered over a garment's dyes, as tiled
textures.

A dye pattern lays whole regions of a garment in one dye, cut on the
skin's triangles. A design is finer than a triangle, so it is a texture
that tiles in the garment's coordinates, which run in meters round its
bones. Each tile is `DESIGN_TEXELS` square:

| Design | Tile | What it shows |
|---|---|---|
| `DAMASK` | 14 cm | rosettes in an ogee lattice, a shade lighter than the dye |
| `BROCADE` | 12 cm | the same, in the trim's dye |
| `TARTAN` | 16 cm | bands of the dye, the secondary and the trim crossing in a twill |
| `PINSTRIPE` | 8 cm | four thin stripes of the trim's dye down each tile |
| `DIAPER` | 7 cm | a lattice of diamonds in the trim's dye, a dot in each |
| `FLORAL` | 12 cm | three flowers of the trim's dye, their hearts the secondary |
| `CHECK` | 8 cm | four checks each way, the trim's dye and a blend where they cross |
| `HERRINGBONE` | 4 cm | a zigzag twill, a shade either side of the dye |
| `HIDE` | 25 cm | the mottle and creases of tanned hide, a shade either side |

A tonal design, damask, herringbone or hide, is a texture of shades
that the dye under it multiplies: it lightens and darkens whatever dye
lies there. Its texels are linear. A design in colors is drawn in the
dyes themselves, as sRGB texels: the primary dye its ground, the trim's
its motif, the secondary its third color. `contrast` shades a motif that
would not show on its ground.

A skinned mesh draws one material, so `design_parts` cuts a garment into
up to three parts: the part the design lies on, a plain part, and the
trim, which takes `braid_texture`, a cable of two strands, when the
design `braids_trim`. `design_dyes` paints the primary region of a
design in colors white, so its wear alone shows in its vertex colors.
`worn_design` says which design a fabric shows: leather wears hide when
it is plain, and mail, plate, scale, fur and straw wear none.

`DesignMaps` makes each texture once for one dressing.

This is not a three.js port. See Extensions.

    var maps = DesignMaps()
    var id = maps.designed(assets, BROCADE, garment.dyes)
"""

from std.math import atan2, cos, floor, pi, sin, sqrt

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from extensions.attire.dye import DYE
from extensions.attire.kinds import (
    FELT,
    LEATHER,
    LINEN,
    PADDING,
    PRIMARY_DYE,
    SECONDARY_DYE,
    SILK,
    TRIM_DYE,
    VELVET,
    WOOL,
    DYE_CHANNEL_COUNT,
    DyeChannel,
    FabricKind,
    require_fabric_kind,
    BROCADE,
    CHECK,
    DAMASK,
    DIAPER,
    FLORAL,
    HERRINGBONE,
    HIDE,
    PINSTRIPE,
    PLAIN,
    TARTAN,
    Design,
    require_design,
)
from math.utils import clamp
from math.vector2 import Vector2
from render.framebuffer import Color
from render.texture import (
    BILINEAR,
    IGNORED,
    LINEAR,
    REPEAT,
    SRGB,
    Texture,
)
from render.texture_store import NO_TEXTURE, TextureId
from extensions.attire.mesh_ops import cut

comptime DESIGN_TEXELS = 128
"""The side of each design's tile, in texels."""
comptime BRAID_TILE = Float32(0.04)
"""The side of one tile of braid, in meters."""
comptime GROUND = Float32(0.6)
"""The shade of a tonal design's ground: the dye times this."""


def design_tile(design: Design) raises -> Float32:
    """Return the side of one tile of a design, in meters.

    Args:
        design: A named design but `PLAIN`.

    Returns:
        The tile's side.

    Raises:
        Error: If the design is not named, or is plain.
    """
    require_design(design)
    if design == DAMASK:
        return 0.14
    if design == BROCADE:
        return 0.12
    if design == TARTAN:
        return 0.16
    if design == PINSTRIPE:
        return 0.08
    if design == DIAPER:
        return 0.07
    if design == FLORAL:
        return 0.12
    if design == CHECK:
        return 0.08
    if design == HERRINGBONE:
        return 0.04
    if design == HIDE:
        return 0.25
    raise Error("A plain garment has no design to tile")


def _wrap(x: Float32) -> Float32:
    """Return `x` wrapped to minus one half through one half."""
    return x - floor(x + 0.5)


def _edge(distance: Float32, width: Float32) -> Float32:
    """Return one inside a stroke of a half width, falling to nothing
    over one texel past it."""
    return clamp((width - distance) * Float32(DESIGN_TEXELS) + 0.5, 0, 1)


def _rosette(u: Float32, v: Float32, cu: Float32, cv: Float32) -> Float32:
    """Return how much a texel lies on a six-petaled rosette and its
    ring, centered at a point of the tile."""
    var du = _wrap(u - cu)
    var dv = _wrap(v - cv)
    var r = sqrt(du * du + dv * dv)
    var theta = atan2(dv, du)
    var petal = 0.1 * (0.55 + 0.45 * cos(6 * theta))
    var flower = _edge(r - petal, 0.0)
    var ring = _edge(abs(r - 0.15), 0.008)
    # Two leaves up and down the stem.
    var leaf = _edge(
        sqrt(du * du * 9 + (abs(dv) - 0.2) * (abs(dv) - 0.2)) - 0.045, 0.0
    )
    return max(max(flower, ring), leaf)


def _ogee(u: Float32, v: Float32) -> Float32:
    """Return how much a texel lies on an ogee lattice's lines."""
    var bend = 0.25 * sin(2 * Float32(pi) * v)
    var a = abs(_wrap(u - bend))
    var b = abs(_wrap(u + bend))
    return _edge(min(a, b), 0.012)


def _medallions(u: Float32, v: Float32) -> Float32:
    """Return how much a texel lies on damask's motif: the lattice and a
    rosette in each of its two cells."""
    return max(
        _ogee(u, v), max(_rosette(u, v, 0.5, 0.25), _rosette(u, v, 0.0, 0.75))
    )


def _band(x: Float32) -> Int:
    """Return which dye a tartan's sett lays at a share of its tile:
    zero the ground, one the secondary, two the trim's thin line."""
    var t = x - floor(x)
    if t > 0.36 and t < 0.6:
        if t > 0.465 and t < 0.495:
            return 2
        return 1
    if t > 0.82 and t < 0.84:
        return 2
    return 0


def _flower(u: Float32, v: Float32, cu: Float32, cv: Float32) -> Int:
    """Return zero off a small flower, one on its petals, two on its
    heart."""
    var du = _wrap(u - cu)
    var dv = _wrap(v - cv)
    var r = sqrt(du * du + dv * dv)
    if r < 0.045:
        return 2
    if r < 0.15 * (0.55 + 0.45 * cos(5 * atan2(dv, du))):
        return 1
    return 0


def _lattice(i: Int, j: Int, cells: Int, salt: Int) -> Float32:
    """Return the value noise holds at lattice point `(i, j)`, wrapped to
    `cells` points on a side."""
    var a = ((i % cells) + cells) % cells
    var b = ((j % cells) + cells) % cells
    var h = UInt64(a * 7919 + b * 104729 + salt * 1299709)
    h = (h ^ (h >> 13)) * 0x9E3779B97F4A7C15
    h = h ^ (h >> 29)
    return Float32(Int(h >> 40)) / Float32(1 << 24)


def _noise(x: Float32, y: Float32, cells: Int, salt: Int) -> Float32:
    """Return smooth value noise that tiles over `cells` lattice cells."""
    var fx = x * Float32(cells)
    var fy = y * Float32(cells)
    var ix = Int(floor(fx))
    var iy = Int(floor(fy))
    var tx = fx - Float32(ix)
    var ty = fy - Float32(iy)
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    var top = (
        _lattice(ix, iy, cells, salt) * (1 - tx)
        + _lattice(ix + 1, iy, cells, salt) * tx
    )
    var bottom = (
        _lattice(ix, iy + 1, cells, salt) * (1 - tx)
        + _lattice(ix + 1, iy + 1, cells, salt) * tx
    )
    return top * (1 - ty) + bottom * ty


def tonal_shade(design: Design, u: Float32, v: Float32) raises -> Float32:
    """Return the shade a tonal design lays on its dye at a point of its
    tile.

    Args:
        design: Damask, herringbone or hide.
        u: Across the tile, zero through one.
        v: Down the tile, zero through one.

    Returns:
        The shade, zero through one, that the dye is multiplied by.

    Raises:
        Error: If the design is not tonal.
    """
    if design == DAMASK:
        return GROUND + (1 - GROUND) * _medallions(u, v)
    if design == HERRINGBONE:
        # Eight columns; each one's twill runs the other way.
        var column = Int(floor(u * 8))
        var slope = Float32(1) if column % 2 == 0 else Float32(-1)
        var s = v * 16 + slope * u * 16
        var rib = 0.5 + 0.5 * sin(2 * Float32(pi) * s)
        return 0.7 + 0.3 * rib
    if design == HIDE:
        var mottle = 0.6 * _noise(u, v, 4, 1) + 0.4 * _noise(u, v, 9, 2)
        var crease = _noise(u, v, 6, 3)
        var line = _edge(abs(crease - 0.5), 0.012)
        return clamp(0.8 + 0.22 * mottle - 0.12 * line, 0, 1)
    raise Error("Only damask, herringbone and hide are tonal")


def _mix(a: Color, b: Color, t: Float32) -> Color:
    """Return `a` blended toward `b` by `t`, in sRGB bytes."""
    return Color(
        UInt8(Int(Float32(a.r) + (Float32(b.r) - Float32(a.r)) * t + 0.5)),
        UInt8(Int(Float32(a.g) + (Float32(b.g) - Float32(a.g)) * t + 0.5)),
        UInt8(Int(Float32(a.b) + (Float32(b.b) - Float32(a.b)) * t + 0.5)),
    )


def colored_shade(
    design: Design,
    ground: Color,
    motif: Color,
    third: Color,
    u: Float32,
    v: Float32,
) raises -> Color:
    """Return the color a design in colors lays at a point of its tile.

    Args:
        design: Brocade, tartan, pinstripe, diaper, floral or check.
        ground: The dye of the region it lies on.
        motif: Its motif's dye, the trim's.
        third: A third dye, for tartan's bands and a flower's heart.
        u: Across the tile, zero through one.
        v: Down the tile, zero through one.

    Returns:
        The color, sRGB.

    Raises:
        Error: If the design is not one in colors.
    """
    if design == BROCADE:
        return _mix(ground, motif, _medallions(u, v))
    if design == TARTAN:
        # A two-over-two twill: the warp shows on half the texels, in
        # diagonal steps, and the weft on the rest.
        var step = (Int(u * 64) + Int(v * 64)) // 2
        var band = _band(u) if step % 2 == 0 else _band(v)
        if band == 1:
            return third
        if band == 2:
            return motif
        return ground
    if design == PINSTRIPE:
        return _mix(ground, motif, _edge(abs(_wrap(u * 4)), 0.035))
    if design == DIAPER:
        var a = abs(_wrap(u + v))
        var b = abs(_wrap(u - v))
        var lines = _edge(min(a, b), 0.02)
        var du = _wrap(u)
        var dv = _wrap(v - 0.5)
        var dot = _edge(sqrt(du * du + dv * dv), 0.045)
        return _mix(ground, motif, max(lines, dot))
    if design == FLORAL:
        var on = max(
            _flower(u, v, 0.2, 0.25),
            max(_flower(u, v, 0.7, 0.45), _flower(u, v, 0.35, 0.8)),
        )
        if on == 2:
            return third
        if on == 1:
            return motif
        return ground
    if design == CHECK:
        var across = _wrap(u * 4) < 0
        var down = _wrap(v * 4) < 0
        if across and down:
            return motif
        if across or down:
            return _mix(ground, motif, 0.5)
        return ground
    raise Error(
        "Only brocade, tartan, pinstripe, diaper, floral and check are in"
        " colors"
    )


def braid_shade(u: Float32, v: Float32) -> Float32:
    """Return the shade a braid lays on a trim at a point of its tile.

    Two strands cross down the tile, a cable, on a ground a little
    darker.

    Args:
        u: Across the tile, zero through one.
        v: Down the tile, zero through one.

    Returns:
        The shade, zero through one.
    """
    var wave = 0.25 * sin(2 * Float32(pi) * u)
    var a = abs(_wrap(v - 0.5 - wave))
    var b = abs(_wrap(v - 0.5 + wave))
    return 0.72 + 0.28 * _edge(min(a, b), 0.06)


def _bytes(shade: Float32) -> UInt8:
    """Return a shade as a byte."""
    return UInt8(Int(clamp(shade, 0, 1) * 255 + 0.5))


def tonal_texture(design: Design) raises -> Texture:
    """Return a tonal design's tile as a tiling texture of linear shades.

    Args:
        design: Damask, herringbone or hide.

    Returns:
        The texture, its repeat set to its tile's size in meters.

    Raises:
        Error: If the design is not tonal.
    """
    var pixels = List[UInt8](capacity=4 * DESIGN_TEXELS * DESIGN_TEXELS)
    for y in range(DESIGN_TEXELS):  # pragma: no branch
        for x in range(DESIGN_TEXELS):  # pragma: no branch
            var shade = _bytes(
                tonal_shade(
                    design,
                    (Float32(x) + 0.5) / Float32(DESIGN_TEXELS),
                    (Float32(y) + 0.5) / Float32(DESIGN_TEXELS),
                )
            )
            pixels.append(shade)
            pixels.append(shade)
            pixels.append(shade)
            pixels.append(255)
    var texture = Texture(
        DESIGN_TEXELS,
        DESIGN_TEXELS,
        pixels^,
        REPEAT,
        BILINEAR,
        color_space=LINEAR,
        alpha=IGNORED,
    )
    var tiles = 1 / design_tile(design)
    texture.repeat = Vector2(tiles, tiles)
    return texture^


def colored_texture(
    design: Design, ground: Color, motif: Color, third: Color
) raises -> Texture:
    """Return a design in colors as a tiling texture of sRGB colors.

    Args:
        design: Brocade, tartan, pinstripe, diaper, floral or check.
        ground: The dye of the region it lies on.
        motif: Its motif's dye.
        third: A third dye.

    Returns:
        The texture, its repeat set to its tile's size in meters.

    Raises:
        Error: If the design is not one in colors.
    """
    var pixels = List[UInt8](capacity=4 * DESIGN_TEXELS * DESIGN_TEXELS)
    for y in range(DESIGN_TEXELS):  # pragma: no branch
        for x in range(DESIGN_TEXELS):  # pragma: no branch
            var color = colored_shade(
                design,
                ground,
                motif,
                third,
                (Float32(x) + 0.5) / Float32(DESIGN_TEXELS),
                (Float32(y) + 0.5) / Float32(DESIGN_TEXELS),
            )
            pixels.append(color.r)
            pixels.append(color.g)
            pixels.append(color.b)
            pixels.append(255)
    var texture = Texture(
        DESIGN_TEXELS,
        DESIGN_TEXELS,
        pixels^,
        REPEAT,
        BILINEAR,
        color_space=SRGB,
        alpha=IGNORED,
    )
    var tiles = 1 / design_tile(design)
    texture.repeat = Vector2(tiles, tiles)
    return texture^


def braid_texture() raises -> Texture:
    """Return a braid's tile as a tiling texture of linear shades.

    Returns:
        The texture, `BRAID_TILE` a tile.

    Raises:
        Error: If the texture is refused, which it is not.
    """
    var pixels = List[UInt8](capacity=4 * DESIGN_TEXELS * DESIGN_TEXELS)
    for y in range(DESIGN_TEXELS):  # pragma: no branch
        for x in range(DESIGN_TEXELS):  # pragma: no branch
            var shade = _bytes(
                braid_shade(
                    (Float32(x) + 0.5) / Float32(DESIGN_TEXELS),
                    (Float32(y) + 0.5) / Float32(DESIGN_TEXELS),
                )
            )
            pixels.append(shade)
            pixels.append(shade)
            pixels.append(shade)
            pixels.append(255)
    var texture = Texture(
        DESIGN_TEXELS,
        DESIGN_TEXELS,
        pixels^,
        REPEAT,
        BILINEAR,
        color_space=LINEAR,
        alpha=IGNORED,
    )
    texture.repeat = Vector2(1 / BRAID_TILE, 1 / BRAID_TILE)
    return texture^


struct DesignMaps(Movable):
    """The design textures one dressing has made, each made once."""

    var keys: List[String]
    """What each texture shows."""
    var ids: List[TextureId]
    """Each texture, in the order of `keys`."""

    def __init__(out self):
        """Hold no textures yet."""
        self.keys = List[String]()
        self.ids = List[TextureId]()

    def _find(self, key: String) -> Int:
        """Return where a key's texture is, or minus one."""
        for k in range(len(self.keys)):
            if self.keys[k] == key:
                return k
        return -1

    def tonal(mut self, mut assets: Assets, design: Design) raises -> TextureId:
        """Return a tonal design's texture, making it the first time.

        Args:
            assets: The store the texture goes in.
            design: Damask, herringbone or hide.

        Returns:
            The texture's id.

        Raises:
            Error: If the design is not tonal.
        """
        var key = "tonal " + String(design.value)
        var at = self._find(key)
        if at >= 0:
            return self.ids[at]
        var id = assets.textures.add(tonal_texture(design))
        self.keys.append(key)
        self.ids.append(id)
        return id

    def colored(
        mut self,
        mut assets: Assets,
        design: Design,
        ground: Color,
        motif: Color,
        third: Color,
    ) raises -> TextureId:
        """Return a design in colors' texture for three dyes, making it the
        first time.

        Args:
            assets: The store the texture goes in.
            design: Brocade, tartan, pinstripe, diaper, floral or check.
            ground: The dye of the region it lies on.
            motif: Its motif's dye.
            third: A third dye.

        Returns:
            The texture's id.

        Raises:
            Error: If the design is not one in colors.
        """
        var key = String(design.value)
        for c in [ground, motif, third]:
            key += " " + String(c.r) + "," + String(c.g) + "," + String(c.b)
        var at = self._find(key)
        if at >= 0:
            return self.ids[at]
        var id = assets.textures.add(
            colored_texture(design, ground, motif, third)
        )
        self.keys.append(key)
        self.ids.append(id)
        return id

    def designed(
        mut self, mut assets: Assets, design: Design, dyes: List[Color]
    ) raises -> TextureId:
        """Return the texture a garment's designed part is drawn with.

        A design in colors is drawn with the primary dye for its ground,
        the trim's for its motif and the secondary for its third color.
        A motif or third too near the ground is drawn in a shade of it.
        See `contrast`.

        Args:
            assets: The store the texture goes in.
            design: A named design.
            dyes: The garment's four dyes, sRGB.

        Returns:
            The texture's id, or `NO_TEXTURE` for a plain garment.

        Raises:
            Error: If the design is not named or there are not four dyes.
        """
        require_design(design)
        if len(dyes) != DYE_CHANNEL_COUNT:
            raise Error("A design needs four dyes")
        if design == PLAIN:
            return NO_TEXTURE
        if design.is_tonal():
            return self.tonal(assets, design)
        var ground = dyes[PRIMARY_DYE.value]
        return self.colored(
            assets,
            design,
            ground,
            contrast(ground, dyes[TRIM_DYE.value], 0.45),
            contrast(ground, dyes[SECONDARY_DYE.value], 0.3),
        )

    def braid(mut self, mut assets: Assets) raises -> TextureId:
        """Return the braid's texture, making it the first time.

        Args:
            assets: The store the texture goes in.

        Returns:
            The texture's id.

        Raises:
            Error: If the store refuses the texture, which it does not.
        """
        var at = self._find("braid")
        if at >= 0:
            return self.ids[at]
        var id = assets.textures.add(braid_texture())
        self.keys.append("braid")
        self.ids.append(id)
        return id


comptime CONTRAST = 60
"""The least difference, summed over a color's three bytes, a motif keeps
from its ground. A motif closer than this is drawn in a shade of the
ground."""
comptime CREAM = Color(236, 222, 184)
"""The color a dark ground's motif is lightened toward."""


def worn_design(design: Design, kind: FabricKind) raises -> Design:
    """Return the design a garment of a fabric wears.

    Woven and stitched cloth wears its design: linen, wool, silk,
    velvet, padding and felt. Leather wears hide when it is plain. Mail,
    plate, scale, fur and straw wear none.

    Args:
        design: A named design.
        kind: A named fabric kind.

    Returns:
        The design to draw.

    Raises:
        Error: If the design or the fabric kind is not named.
    """
    require_design(design)
    require_fabric_kind(kind)
    if kind == LEATHER:
        return HIDE if design == PLAIN else design
    if (
        kind == LINEN
        or kind == WOOL
        or kind == SILK
        or kind == VELVET
        or kind == PADDING
        or kind == FELT
    ):
        return design
    return PLAIN


def contrast(ground: Color, motif: Color, lift: Float32) -> Color:
    """Return a motif that shows on its ground.

    A motif that differs from its ground by `CONTRAST` or more is kept.
    A closer one is drawn in a shade of the ground: a dark ground's
    motif lightened toward cream, a light ground's darkened.

    Args:
        ground: The ground's dye, sRGB.
        motif: The motif's dye, sRGB.
        lift: How far a shade moves from the ground, zero through one.

    Returns:
        The motif's color, sRGB.
    """
    var apart = (
        abs(Int(ground.r) - Int(motif.r))
        + abs(Int(ground.g) - Int(motif.g))
        + abs(Int(ground.b) - Int(motif.b))
    )
    if apart >= CONTRAST:
        return motif
    var light = (
        0.299 * Float32(ground.r)
        + 0.587 * Float32(ground.g)
        + 0.114 * Float32(ground.b)
    )
    if light < 128:
        return _mix(ground, CREAM, lift)
    return _mix(ground, Color(0, 0, 0), lift)


def design_dyes(design: Design, dyes: List[Color]) raises -> List[Color]:
    """Return the dyes a garment's vertex colors are painted in.

    A design in colors draws the primary region's dyes in its texture,
    so that region is painted white, and its wear alone shows there.
    Other designs keep the dyes.

    Args:
        design: A named design.
        dyes: Four dyes, sRGB.

    Returns:
        Four dyes, sRGB.

    Raises:
        Error: If the design is not named or there are not four dyes.
    """
    require_design(design)
    if len(dyes) != DYE_CHANNEL_COUNT:
        raise Error("A design needs four dyes")
    var painted = dyes.copy()
    if design.is_colored():
        painted[PRIMARY_DYE.value] = Color(255, 255, 255)
    return painted^


struct DrawnParts(Movable):
    """The parts of a garment that are drawn, each with its color map."""

    var pieces: List[BufferGeometry]
    """The parts, designed first, then plain, then braided."""
    var maps: List[TextureId]
    """The color map of each part, or `NO_TEXTURE`."""

    def __init__(
        out self, var pieces: List[BufferGeometry], var maps: List[TextureId]
    ):
        """Hold the parts and their maps.

        Args:
            pieces: The parts.
            maps: One color map a part.
        """
        self.pieces = pieces^
        self.maps = maps^


struct DesignParts(Movable):
    """A garment cut by its dyes into the parts drawn with one texture
    each."""

    var designed: Optional[BufferGeometry]
    """The part the design lies on, or None when there is none."""
    var plain: Optional[BufferGeometry]
    """The part drawn in its dyes alone, or None."""
    var braided: Optional[BufferGeometry]
    """The trim drawn with a braid, or None."""

    def __init__(out self):
        """Hold no parts."""
        self.designed = None
        self.plain = None
        self.braided = None

    def drawn(
        mut self,
        mut maps: DesignMaps,
        mut assets: Assets,
        design: Design,
        dyes: List[Color],
    ) raises -> DrawnParts:
        """Take the parts that are present, each with its color map.

        Args:
            maps: The design textures made so far.
            assets: The store new textures go in.
            design: The design the parts were cut for.
            dyes: The garment's four dyes, sRGB.

        Returns:
            The parts, designed first, then plain, then braided, and the
            color map of each: the design's, `NO_TEXTURE`, the braid's.

        Raises:
            Error: If the design is not named or there are not four dyes.
        """
        var pieces = List[BufferGeometry]()
        var looks = List[TextureId]()
        if self.designed:
            pieces.append(self.designed.take())
            looks.append(maps.designed(assets, design, dyes))
        if self.plain:
            pieces.append(self.plain.take())
            looks.append(NO_TEXTURE)
        if self.braided:
            pieces.append(self.braided.take())
            looks.append(maps.braid(assets))
        return DrawnParts(pieces^, looks^)


def _channel_of(weights: List[Float32], v: Int) -> Int:
    """Return the dye channel that weighs most on a vertex."""
    var best = 0
    for c in range(1, DYE_CHANNEL_COUNT):  # pragma: no branch
        if (
            weights[DYE_CHANNEL_COUNT * v + c]
            > weights[DYE_CHANNEL_COUNT * v + best]
        ):
            best = c
    return best


def _part(
    piece: BufferGeometry, channels: List[Int], wanted: List[Bool]
) raises -> Optional[BufferGeometry]:
    """Return the triangles of a piece in the wanted channels, or None
    when it has none."""
    var values = List[Float32](capacity=len(channels))
    for channel in channels:  # pragma: no branch
        values.append(Float32(1) if wanted[channel] else Float32(-1))
    var kept = cut(piece, values, 0)
    if kept.triangle_count() == 0:
        return None
    return kept^


def design_parts(piece: BufferGeometry, design: Design) raises -> DesignParts:
    """Cut a painted garment into the parts its design draws apart.

    A plain garment, and one in a tonal design that keeps no braid, is
    one part: the design multiplies all of it. A tonal design that
    braids its trim lies on all but the trim. A design in colors lies on
    the primary region alone. The trim takes the braid when the design
    braids it. What is left is drawn plain.

    Args:
        piece: A garment with a `dye` attribute, each triangle in one
            channel.
        design: A named design.

    Returns:
        The parts. At least one is present for a garment with triangles.

    Raises:
        Error: If the design is not named or the garment has no dye
            weights.
    """
    require_design(design)
    var parts = DesignParts()
    if design == PLAIN or (design.is_tonal() and not design.braids_trim()):
        parts.designed = piece.clone()
        return parts^
    var weights = piece.attribute_view(String(DYE)).packed()
    var channels = List[Int](capacity=piece.vertex_count())
    for v in range(piece.vertex_count()):  # pragma: no branch
        channels.append(_channel_of(weights, v))
    var designed = List[Bool](length=DYE_CHANNEL_COUNT, fill=False)
    var braided = List[Bool](length=DYE_CHANNEL_COUNT, fill=False)
    for c in range(DYE_CHANNEL_COUNT):  # pragma: no branch
        if design.is_colored():
            designed[c] = c == PRIMARY_DYE.value
        else:
            designed[c] = c != TRIM_DYE.value
        braided[c] = design.braids_trim() and c == TRIM_DYE.value
    var plain = List[Bool](capacity=DYE_CHANNEL_COUNT)
    for c in range(DYE_CHANNEL_COUNT):  # pragma: no branch
        plain.append(not designed[c] and not braided[c])
    parts.designed = _part(piece, channels, designed)
    parts.plain = _part(piece, channels, plain)
    parts.braided = _part(piece, channels, braided)
    return parts^
