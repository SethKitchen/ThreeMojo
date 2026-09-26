# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""TrueType fonts, from three.js `examples/jsm/loaders/TTFLoader.js`.

three.js reads a font with opentype.js and converts it to the typeface
JSON that `FontLoader` reads. `ttf_json` does both for a TrueType font,
as opentype.js reads its tables, and `read_ttf` hands the JSON to
`loaders.font.parse_font`.

**What is read.** The `cmap` subtable opentype.js picks: the last one
for Unicode or Windows Unicode, of format 4 or 12. Each glyph's outline
from `glyf`: simple glyphs, and composite glyphs placed by an offset, a
scale, a 2 by 2 matrix or matched points. Each glyph's advance from
`hmtx`, the ascender and descender from `hhea`, the bounding box and the
units from `head`, the underline from `post`, and the English full name
from `name`.

**The outline.** As opentype.js's `getPath` turns contours into a path: a
line to each point on the curve, and a quadratic curve through each
point off it, to the midpoint of two points off the curve in a row. Each
contour closes. `convert` writes each command and its points, scaled by
`100000 / (unitsPerEm * 72)` and rounded.

**Where three.js's quirks are kept.** A format 4 cmap's last segment is
not read. A glyph without an outline has no `x_min` or `x_max`, which
JSON writes as `null`. With `reversed`, three.js reverses a glyph's
commands in place once for each code point that maps to it, so a glyph
of two code points comes back in its first order, without its `z`.

**What is refused.** What opentype.js throws on: a signature that is not
TrueType, a font with no `glyf` and `loca`, no usable `cmap` subtable,
flags that overrun a glyph's points, and matched points past a glyph's
points. And what this port does not read: CFF outlines (`OTTO`), WOFF,
and a composite glyph that names a glyph past the font or nests past
`MAX_TTF_NESTING`, and a code point that is a surrogate, which a string
here cannot hold. `original_font_information`, the `name` table as
opentype.js holds it, is not written: `FontLoader` does not read it.
"""

from loaders.font import Font, parse_font
from loaders.json import quote_json
from loaders.three_mf import js_key_order
from std.math import floor, isnan, nan
from std.pathlib import Path

# How deep a composite glyph may nest components.
comptime MAX_TTF_NESTING = 16


struct _Data:
    """A font's bytes, read big-endian."""

    var bytes: List[UInt8]

    def __init__(out self, var bytes: List[UInt8]):
        """Hold the font.

        Args:
            bytes: The font.
        """
        self.bytes = bytes^

    def u8(self, at: Int) raises -> Int:
        """Return a byte.

        Args:
            at: The byte.

        Returns:
            Its value.

        Raises:
            Error: If it is past the end.
        """
        if at >= len(self.bytes):
            raise Error("TTF: a value runs past the end, at byte " + String(at))
        return Int(self.bytes[at])

    def u16(self, at: Int) raises -> Int:
        """Return an unsigned short.

        Args:
            at: Where it starts.

        Returns:
            Its value.

        Raises:
            Error: If it runs past the end.
        """
        return (self.u8(at) << 8) | self.u8(at + 1)

    def i16(self, at: Int) raises -> Int:
        """Return a signed short.

        Args:
            at: Where it starts.

        Returns:
            Its value.

        Raises:
            Error: If it runs past the end.
        """
        var v = self.u16(at)
        return v - 65536 if v >= 32768 else v

    def u32(self, at: Int) raises -> Int:
        """Return an unsigned long.

        Args:
            at: Where it starts.

        Returns:
            Its value.

        Raises:
            Error: If it runs past the end.
        """
        return (self.u16(at) << 16) | self.u16(at + 2)


@fieldwise_init
struct _Point(Copyable, Movable):
    """A glyph's point, as opentype.js holds it."""

    var x: Float64
    var y: Float64
    var on_curve: Bool
    var last: Bool


@fieldwise_init
struct _Command(Copyable, Movable):
    """A path command: `M`, `L`, `Q` or `Z`, its point, and a quadratic
    curve's control point."""

    var type: String
    var x: Float64
    var y: Float64
    var x1: Float64
    var y1: Float64


struct _Glyph(Copyable, Movable):
    """A glyph as opentype.js holds it."""

    var advance: Int
    var has_box: Bool
    var x_min: Int
    var x_max: Int
    var points: List[_Point]
    var commands: List[_Command]
    var unicodes: List[Int]
    var parsed: Bool

    def __init__(out self):
        """Start a glyph with no outline."""
        self.advance = 0
        self.has_box = False
        self.x_min = 0
        self.x_max = 0
        self.points = List[_Point]()
        self.commands = List[_Command]()
        self.unicodes = List[Int]()
        self.parsed = False


def _coordinate(
    data: _Data,
    mut at: Int,
    flag: Int,
    previous: Float64,
    short_bit: Int,
    same_bit: Int,
) raises -> Float64:
    """Return opentype.js's `parseGlyphCoordinate`.

    Args:
        data: The font.
        at: Where the value is; moved past it.
        flag: The point's flag.
        previous: The previous point's coordinate.
        short_bit: The flag bit of a one-byte value.
        same_bit: The flag bit of the same value, or of a positive byte.

    Returns:
        The coordinate.

    Raises:
        Error: If it runs past the end.
    """
    if (flag & short_bit) > 0:
        var v = data.u8(at)
        at += 1
        if (flag & same_bit) == 0:
            return previous - Float64(v)
        return previous + Float64(v)
    if (flag & same_bit) > 0:
        return previous
    var delta = data.i16(at)
    at += 2
    return previous + Float64(delta)


def _f2dot14(data: _Data, mut at: Int) raises -> Float64:
    """Return a 2.14 fixed-point number, and move past it.

    Args:
        data: The font.
        at: Where it is.

    Returns:
        The number.

    Raises:
        Error: If it runs past the end.
    """
    var v = Float64(data.i16(at)) / 16384
    at += 2
    return v


def _transform(
    points: List[_Point],
    xx: Float64,
    xy: Float64,
    yx: Float64,
    yy: Float64,
    dx: Float64,
    dy: Float64,
) -> List[_Point]:
    """Return opentype.js's `transformPoints`.

    Args:
        points: The points.
        xx: `xScale`.
        xy: `scale01`.
        yx: `scale10`.
        yy: `yScale`.
        dx: The offset across.
        dy: The offset up.

    Returns:
        The points, moved.
    """
    var out = List[_Point](capacity=len(points))
    for p in points:  # pragma: no branch
        out.append(
            _Point(
                xx * p.x + xy * p.y + dx,
                yx * p.x + yy * p.y + dy,
                p.on_curve,
                p.last,
            )
        )
    return out^


struct _Font:
    """The tables `convert` reads, and the glyphs, parsed as needed."""

    var data: _Data
    var glyf: Int
    var loca: List[Int]
    var glyphs: List[_Glyph]

    def __init__(
        out self, var data: _Data, glyf: Int, var loca: List[Int], count: Int
    ):
        """Hold the font's glyph tables.

        Args:
            data: The font.
            glyf: Where `glyf` starts.
            loca: Each glyph's offset into it, and the end.
            count: How many glyphs there are.
        """
        self.data = data^
        self.glyf = glyf
        self.loca = loca^
        self.glyphs = List[_Glyph](length=count, fill=_Glyph())

    def parse(mut self, index: Int, depth: Int) raises:
        """Parse a glyph's outline once, opentype.js's `parseGlyph` and
        `buildPath`.

        Args:
            index: The glyph.
            depth: How deep in composite glyphs it is.

        Raises:
            Error: For a glyph opentype.js cannot read, or one that nests
                past `MAX_TTF_NESTING`.
        """
        if index >= len(self.glyphs):
            raise Error("TTF: a component names glyph " + String(index))
        if self.glyphs[index].parsed:
            return
        if depth > MAX_TTF_NESTING:
            raise Error("TTF: composite glyphs nest too deep")
        var start = self.loca[index]
        if start == self.loca[index + 1]:
            # No outline: an empty path, and no bounding box.
            self.glyphs[index].parsed = True
            return
        var at = self.glyf + start
        var contours = self.data.i16(at)
        self.glyphs[index].has_box = True
        self.glyphs[index].x_min = self.data.i16(at + 2)
        self.glyphs[index].x_max = self.data.i16(at + 6)
        at += 10
        var points = List[_Point]()
        if contours > 0:
            var ends = List[Int]()
            for _ in range(contours):  # pragma: no branch
                ends.append(self.data.u16(at))
                at += 2
            var instructions = self.data.u16(at)
            at += 2 + instructions
            var count = ends[len(ends) - 1] + 1
            var flags = List[Int]()
            var i = 0
            while i < count:
                var flag = self.data.u8(at)
                at += 1
                flags.append(flag)
                if (flag & 8) > 0:
                    var repeat = self.data.u8(at)
                    at += 1
                    for _ in range(repeat):  # pragma: no branch
                        flags.append(flag)
                        i += 1
                i += 1
            if len(flags) != count:
                raise Error("Bad flags.")
            for k in range(count):  # pragma: no branch
                points.append(_Point(0, 0, (flags[k] & 1) != 0, k in ends))
            var px = Float64(0)
            for k in range(count):  # pragma: no branch
                px = _coordinate(self.data, at, flags[k], px, 2, 16)
                points[k].x = px
            var py = Float64(0)
            for k in range(count):  # pragma: no branch
                py = _coordinate(self.data, at, flags[k], py, 4, 32)
                points[k].y = py
        elif contours < 0:
            var more = True
            while more:
                var flags = self.data.u16(at)
                var component = self.data.u16(at + 2)
                at += 4
                var dx = Float64(0)
                var dy = Float64(0)
                var matched = False
                var first = 0
                var second = 0
                if (flags & 1) > 0:
                    if (flags & 2) > 0:
                        dx = Float64(self.data.i16(at))
                        dy = Float64(self.data.i16(at + 2))
                    else:
                        matched = True
                        first = self.data.u16(at)
                        second = self.data.u16(at + 2)
                    at += 4
                else:
                    if (flags & 2) > 0:
                        var a = self.data.u8(at)
                        var b = self.data.u8(at + 1)
                        dx = Float64(a - 256 if a >= 128 else a)
                        dy = Float64(b - 256 if b >= 128 else b)
                    else:
                        matched = True
                        first = self.data.u8(at)
                        second = self.data.u8(at + 1)
                    at += 2
                var xx = Float64(1)
                var xy = Float64(0)
                var yx = Float64(0)
                var yy = Float64(1)
                if (flags & 8) > 0:
                    xx = _f2dot14(self.data, at)
                    yy = xx
                elif (flags & 64) > 0:
                    xx = _f2dot14(self.data, at)
                    yy = _f2dot14(self.data, at)
                elif (flags & 128) > 0:
                    xx = _f2dot14(self.data, at)
                    xy = _f2dot14(self.data, at)
                    yx = _f2dot14(self.data, at)
                    yy = _f2dot14(self.data, at)
                self.parse(component, depth + 1)
                more = (flags & 32) != 0
                # A component with no outline has no points to place.
                if not self.glyphs[component].has_box:
                    continue
                var parts = self.glyphs[component].points.copy()
                if matched:
                    if first > len(points) - 1 or second > len(parts) - 1:
                        raise Error("Matched points out of range")
                    var moved = _transform(
                        [parts[second].copy()], xx, xy, yx, yy, 0, 0
                    )
                    dx = points[first].x - moved[0].x
                    dy = points[first].y - moved[0].y
                points.extend(_transform(parts, xx, xy, yx, yy, dx, dy))
        self.glyphs[index].commands = _path(points)
        self.glyphs[index].points = points^
        self.glyphs[index].parsed = True


def _path(points: List[_Point]) raises -> List[_Command]:
    """Return opentype.js's `getPath`: each contour as lines and quadratic
    curves, closed.

    Args:
        points: The glyph's points.

    Returns:
        The commands.
    """
    var contours = List[List[_Point]]()
    var current = List[_Point]()
    for p in points:
        current.append(p.copy())
        if p.last:
            contours.append(current^)
            current = List[_Point]()
    # opentype.js throws here if points are left over. The last point of a
    # simple glyph ends its last contour, and a composite glyph's parts end
    # theirs, so none is ever left.
    var out = List[_Command]()
    for contour in contours:
        var n = len(contour)
        var curr = contour[n - 1].copy()
        var next = contour[0].copy()
        if curr.on_curve:
            out.append(_Command("M", curr.x, curr.y, 0, 0))
        elif next.on_curve:
            out.append(_Command("M", next.x, next.y, 0, 0))
        else:
            out.append(
                _Command(
                    "M", (curr.x + next.x) * 0.5, (curr.y + next.y) * 0.5, 0, 0
                )
            )
        for i in range(n):  # pragma: no branch
            var prev = curr.copy()
            curr = next.copy()
            next = contour[(i + 1) % n].copy()
            if curr.on_curve:
                out.append(_Command("L", curr.x, curr.y, 0, 0))
            else:
                var ex = next.x
                var ey = next.y
                if not next.on_curve:
                    ex = (curr.x + next.x) * 0.5
                    ey = (curr.y + next.y) * 0.5
                _ = prev^
                out.append(_Command("Q", ex, ey, curr.x, curr.y))
        out.append(_Command("Z", 0, 0, 0, 0))
    return out^


def _reverse(commands: List[_Command]) -> List[_Command]:
    """Return three.js's `reverseCommands`: each subpath backwards, with
    no `Z`.

    Args:
        commands: The commands.

    Returns:
        The reversed commands.
    """
    var paths = List[List[_Command]]()
    for c in commands:
        if c.type == "M":
            paths.append([c.copy()])
        elif c.type != "Z":
            paths[len(paths) - 1].append(c.copy())
    var out = List[_Command]()
    for p in paths:
        var last = p[len(p) - 1].copy()
        out.append(_Command("M", last.x, last.y, 0, 0))
        for i in range(len(p) - 1, 0, -1):  # pragma: no branch
            var c = p[i].copy()
            out.append(_Command(c.type, p[i - 1].x, p[i - 1].y, c.x1, c.y1))
    return out^


def _round(value: Float64) -> Int:
    """Return JavaScript's `Math.round`: halves up.

    Args:
        value: The value.

    Returns:
        The nearest whole number.
    """
    return Int(floor(value + 0.5))


def _mac_roman(byte: Int) -> Int:
    """Return the code point of a Mac Roman byte.

    Args:
        byte: The byte.

    Returns:
        Its code point.
    """
    if byte < 128:
        return byte
    var high: List[Int] = [
        0xC4,
        0xC5,
        0xC7,
        0xC9,
        0xD1,
        0xD6,
        0xDC,
        0xE1,
        0xE0,
        0xE2,
        0xE4,
        0xE3,
        0xE5,
        0xE7,
        0xE9,
        0xE8,
        0xEA,
        0xEB,
        0xED,
        0xEC,
        0xEE,
        0xEF,
        0xF1,
        0xF3,
        0xF2,
        0xF4,
        0xF6,
        0xF5,
        0xFA,
        0xF9,
        0xFB,
        0xFC,
        0x2020,
        0xB0,
        0xA2,
        0xA3,
        0xA7,
        0x2022,
        0xB6,
        0xDF,
        0xAE,
        0xA9,
        0x2122,
        0xB4,
        0xA8,
        0x2260,
        0xC6,
        0xD8,
        0x221E,
        0xB1,
        0x2264,
        0x2265,
        0xA5,
        0xB5,
        0x2202,
        0x2211,
        0x220F,
        0x3C0,
        0x222B,
        0xAA,
        0xBA,
        0x3A9,
        0xE6,
        0xF8,
        0xBF,
        0xA1,
        0xAC,
        0x221A,
        0x192,
        0x2248,
        0x2206,
        0xAB,
        0xBB,
        0x2026,
        0xA0,
        0xC0,
        0xC3,
        0xD5,
        0x152,
        0x153,
        0x2013,
        0x2014,
        0x201C,
        0x201D,
        0x2018,
        0x2019,
        0xF7,
        0x25CA,
        0xFF,
        0x178,
        0x2044,
        0x20AC,
        0x2039,
        0x203A,
        0xFB01,
        0xFB02,
        0x2021,
        0xB7,
        0x201A,
        0x201E,
        0x2030,
        0xC2,
        0xCA,
        0xC1,
        0xCB,
        0xC8,
        0xCD,
        0xCE,
        0xCF,
        0xCC,
        0xD3,
        0xD4,
        0xF8FF,
        0xD2,
        0xDA,
        0xDB,
        0xD9,
        0x131,
        0x2C6,
        0x2DC,
        0xAF,
        0x2D8,
        0x2D9,
        0x2DA,
        0xB8,
        0x2DD,
        0x2DB,
        0x2C7,
    ]
    return high[byte - 128]


def _full_name(data: _Data, start: Int) raises -> Optional[String]:
    """Return the English full name, as opentype.js's `name` table and
    `getEnglishName( 'fullName' )` read it: the last Windows US-English
    or Macintosh English record that is not empty.

    Args:
        data: The font.
        start: Where `name` starts.

    Returns:
        The name, or none.

    Raises:
        Error: If a record runs past the end.
    """
    var count = data.u16(start + 2)
    var strings = start + data.u16(start + 4)
    var found: Optional[String] = None
    for k in range(count):  # pragma: no branch
        var at = start + 6 + k * 12
        var platform = data.u16(at)
        var encoding = data.u16(at + 2)
        var language = data.u16(at + 4)
        var name_id = data.u16(at + 6)
        var length = data.u16(at + 8)
        var offset = strings + data.u16(at + 10)
        if name_id != 4:
            continue
        var text = String()
        if platform == 3 and language == 0x409:
            var units = List[Int]()
            for j in range(0, length - 1, 2):
                units.append(data.u16(offset + j))
            var i = 0
            while i < len(units):
                var v = units[i]
                i += 1
                var pair = (
                    v >= 0xD800
                    and v < 0xDC00
                    and i < len(units)
                    and units[i] >= 0xDC00
                    and units[i] < 0xE000
                )
                if pair:
                    v = 0x10000 + ((v - 0xD800) << 10) + (units[i] - 0xDC00)
                    i += 1
                elif v >= 0xD800 and v < 0xE000:
                    v = 0xFFFD
                text += chr(v)
        elif platform == 1 and language == 0 and encoding == 0:
            for j in range(length):  # pragma: no branch
                text += chr(_mac_roman(data.u8(offset + j)))
        else:
            continue
        if text.byte_length() > 0:
            found = text
    return found^


def _cmap(data: _Data, start: Int) raises -> Dict[Int, Int]:
    """Return opentype.js's `cmap.glyphIndexMap`.

    Args:
        data: The font.
        start: Where `cmap` starts.

    Returns:
        Each code point's glyph.

    Raises:
        Error: If no subtable is Unicode or Windows Unicode, or the one
            chosen is not of format 4 or 12, as opentype.js throws.
    """
    var tables = data.u16(start + 2)
    var offset = -1
    for i in range(tables - 1, -1, -1):  # pragma: no branch
        var platform = data.u16(start + 4 + i * 8)
        var encoding = data.u16(start + 4 + i * 8 + 2)
        var windows = platform == 3 and (
            encoding == 0 or encoding == 1 or encoding == 10
        )
        var unicode = platform == 0 and encoding <= 4
        if windows or unicode:
            offset = data.u32(start + 4 + i * 8 + 4)
            break
    if offset < 0:
        raise Error("No valid cmap sub-tables found.")
    var at = start + offset
    var format = data.u16(at)
    var map = Dict[Int, Int]()
    if format == 12:
        var groups = data.u32(at + 12)
        for g in range(groups):  # pragma: no branch
            var first = data.u32(at + 16 + g * 12)
            var last = data.u32(at + 20 + g * 12)
            var glyph = data.u32(at + 24 + g * 12)
            for c in range(first, last + 1):  # pragma: no branch
                map[c] = glyph
                glyph += 1
    elif format == 4:
        var segments = data.u16(at + 6) >> 1
        var ends = at + 14
        var starts = at + 16 + segments * 2
        var deltas = at + 16 + segments * 4
        var ranges = at + 16 + segments * 6
        # opentype.js stops a segment short: the last is not read.
        for i in range(segments - 1):  # pragma: no branch
            var end = data.u16(ends + i * 2)
            var first = data.u16(starts + i * 2)
            var delta = data.i16(deltas + i * 2)
            var range_offset = data.u16(ranges + i * 2)
            for c in range(first, end + 1):  # pragma: no branch
                var glyph: Int
                if range_offset != 0:
                    var place = ranges + i * 2 + range_offset + (c - first) * 2
                    glyph = data.u16(place)
                    if glyph != 0:
                        glyph = (glyph + delta) & 0xFFFF
                else:
                    glyph = (c + delta) & 0xFFFF
                map[c] = glyph
    else:
        raise Error(
            "Only format 4 and 12 cmap tables are supported (found format "
            + String(format)
            + ")."
        )
    return map^


def _commands_text(commands: List[_Command], scale: Float64) -> String:
    """Return `convert`'s `o`: each command and its points, rounded.

    Args:
        commands: The commands.
        scale: The scale.

    Returns:
        The outline.
    """
    var out = String()
    for c in commands:
        out += c.type.lower() + " "
        if c.type != "Z":
            out += (
                String(_round(c.x * scale))
                + " "
                + String(_round(c.y * scale))
                + " "
            )
        if c.type == "Q":
            out += (
                String(_round(c.x1 * scale))
                + " "
                + String(_round(c.y1 * scale))
                + " "
            )
    return out^


def ttf_json(bytes: List[UInt8], reversed: Bool = False) raises -> String:
    """Read a TrueType font into three.js's typeface JSON, three.js's
    `TTFLoader.parse`.

    Args:
        bytes: The font.
        reversed: Whether to reverse each glyph's commands, three.js's
            `reversed`.

    Returns:
        The JSON text `FontLoader` reads.

    Raises:
        Error: For anything the module docstring lists.
    """
    var data = _Data(bytes.copy())
    var signature = data.u32(0)
    if signature != 0x00010000 and signature != 0x74727565:
        raise Error("TTF: only TrueType outlines are read")
    var tables = data.u16(4)
    var offsets = Dict[String, Int]()
    for k in range(tables):  # pragma: no branch
        var at = 12 + k * 16
        var tag = String()
        for j in range(4):  # pragma: no branch
            tag += chr(data.u8(at + j))
        offsets[tag] = data.u32(at + 8)
    for needed in [
        "head",
        "hhea",
        "maxp",
        "hmtx",
        "cmap",
        "post",
        "name",
    ]:  # pragma: no branch
        if needed not in offsets:
            raise Error("TTF: the font has no " + needed + " table")
    if "glyf" not in offsets or "loca" not in offsets:
        raise Error("Font doesn't contain TrueType or CFF outlines.")
    var head = offsets["head"]
    var units = data.u16(head + 18)
    var long_loca = data.i16(head + 50) != 0
    var hhea = offsets["hhea"]
    var metrics = data.u16(hhea + 34)
    var count = data.u16(offsets["maxp"] + 4)
    var loca = List[Int]()
    var loca_at = offsets["loca"]
    for i in range(count + 1):  # pragma: no branch
        loca.append(
            data.u32(loca_at + 4 * i) if long_loca else data.u16(
                loca_at + 2 * i
            )
            * 2
        )
    var font = _Font(data^, offsets["glyf"], loca^, count)
    var hmtx = offsets["hmtx"]
    var advance = 0
    for i in range(count):  # pragma: no branch
        if i < metrics:
            advance = font.data.u16(hmtx + 4 * i)
        font.glyphs[i].advance = advance
    var map = _cmap(font.data, offsets["cmap"])
    var codes = List[Int]()
    for entry in map.items():  # pragma: no branch
        codes.append(entry.key)
    sort(codes)
    for c in codes:  # pragma: no branch
        var glyph = map[c]
        if glyph >= count:
            raise Error("TTF: code point " + String(c) + " names no glyph")
        font.glyphs[glyph].unicodes.append(c)
    var scale = 100000.0 / (Float64(units if units != 0 else 2048) * 72)
    var keys = List[String]()
    var tokens = Dict[String, String]()
    for c in codes:  # pragma: no branch
        var index = map[c]
        font.parse(index, 0)
        ref glyph = font.glyphs[index]
        var token = '{"ha":' + String(_round(Float64(glyph.advance) * scale))
        if glyph.has_box:
            token += ',"x_min":' + String(_round(Float64(glyph.x_min) * scale))
            token += ',"x_max":' + String(_round(Float64(glyph.x_max) * scale))
        else:
            token += ',"x_min":null,"x_max":null'
        if reversed:
            glyph.commands = _reverse(glyph.commands)
        token += (
            ',"o":' + quote_json(_commands_text(glyph.commands, scale)) + "}"
        )
        for u in glyph.unicodes:  # pragma: no branch
            if u >= 0xD800 and u < 0xE000:
                raise Error("TTF: code point " + String(u) + " is a surrogate")
            var key = chr(u)
            if key not in tokens:
                keys.append(key)
            tokens[key] = token
    var out = String('{"glyphs":{')
    var first = True
    for key in js_key_order(keys):  # pragma: no branch
        if not first:
            out += ","
        first = False
        out += quote_json(key) + ":" + tokens[key]
    out += "}"
    var name = _full_name(font.data, offsets["name"])
    if Bool(name):
        out += ',"familyName":' + quote_json(name.value())
    var post = offsets["post"]
    out += ',"ascender":' + String(
        _round(Float64(font.data.i16(hhea + 4)) * scale)
    )
    out += ',"descender":' + String(
        _round(Float64(font.data.i16(hhea + 6)) * scale)
    )
    out += ',"underlinePosition":' + String(font.data.i16(post + 8))
    out += ',"underlineThickness":' + String(font.data.i16(post + 10))
    out += ',"boundingBox":{"xMin":' + String(font.data.i16(head + 36))
    out += ',"xMax":' + String(font.data.i16(head + 40))
    out += ',"yMin":' + String(font.data.i16(head + 38))
    out += ',"yMax":' + String(font.data.i16(head + 42))
    out += '},"resolution":1000}'
    return out^


def read_ttf(path: String, reversed: Bool = False) raises -> Font:
    """Read a TrueType font file into a `Font`, three.js's `TTFLoader`
    and `FontLoader` together.

    Args:
        path: The file.
        reversed: Whether to reverse each glyph's commands.

    Returns:
        The font.

    Raises:
        Error: If the file cannot be read, and for anything `ttf_json` or
            `parse_font` refuses.
    """
    return parse_font(ttf_json(Path(path).read_bytes(), reversed))
