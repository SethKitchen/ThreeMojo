# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the village game writes over its frame: the satchel, what the
player can use, what the player just gathered, what a villager said,
and the errands the player has taken.

`draw_hud` draws five things on a frame, in pixels, in the font of
`extensions.village.hud_font`:

1. **The satchel.** A panel in the bottom left lists each kind the player
   holds, with a swatch of its color and its count.
2. **The prompt.** When the player can use a spot or talk to a villager,
   a line in the bottom middle says which button uses it and what it
   does, such as `E  GATHER HERBS`, or `E  TALK TO MAUD`.
3. **The note.** For two seconds after the player gathers something, a
   line over the prompt says what, such as `+3 BERRIES`. It fades over
   its last half second.
4. **The speech.** For `SPEECH_SECONDS` after a villager speaks, a panel
   over the note shows their name and their words.
5. **The errands.** Each errand taken and not yet done is a line in the
   top right, such as `HERBS FOR MAUD 2/5`.

A capital letter stands `TEXT_SIZE` times `hud_scale` pixels tall, in
the middle of a row 7 times it, so the text keeps its size on the screen
at every window's size. The letters' edges
are smooth, and each line has a soft dark shadow, so it reads over the
sky and the grass alike. `draw_styled` draws a line in any `TextStyle`:
any size, with a dark ring, bolder, or leaning.
"""

from extensions.village.gathering import (
    BERRIES,
    BITING,
    CHEST,
    FISH,
    GatherKind,
    HERBS,
    KINDS,
    MUSHROOMS,
    ORE,
    SEAL,
    STRIKES,
    WAITING,
    Satchel,
    TRINKET,
    kind_name,
)
from extensions.village.hud_font import (
    FONT_BASE,
    FONT_CAP,
    FONT_CELL,
    FONT_FIELD,
    FONT_FIRST,
    FONT_LEVELS,
    FONT_METRICS,
    FONT_PAD,
    FONT_SPACE,
    FONT_SPREAD,
)
from extensions.village.talk import SPEECH_SECONDS
from render.framebuffer import Framebuffer
from render.tasks import TaskGroup
from renderers.renderer import available_workers
from std.math import ceil, floor, sqrt

comptime GLYPHS = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/:.,!?'-"
    + "abcdefghijklmnopqrstuvwxyz"
)
"""The characters the font draws, in the order of its rows. Any other
character is a space."""
comptime VIGNETTE_CLEAR = Float32(0.45)
"""The share of the way from a frame's middle to its corner that a
vignette leaves clear."""
comptime NOTE_SECONDS = Float32(2.0)
"""How long a note stays, in seconds."""
comptime NOTE_FADE = Float32(0.5)
"""How long a note takes to fade at its end, in seconds."""


@fieldwise_init
struct Rgb(ImplicitlyCopyable):
    """A color of the overlay, as sRGB bytes."""

    var r: Int
    var g: Int
    var b: Int


comptime WHITE_TEXT = Rgb(245, 238, 220)
comptime GOLD_TEXT = Rgb(255, 205, 90)
comptime SHADOW = Rgb(10, 8, 6)
comptime PANEL_ALPHA = Float32(0.38)
"""How dark a panel behind a group of the display's words and bars is,
from 0 to 1."""


def hud_scale(height: Int) -> Int:
    """Return the pixels a dot of the font takes on a frame.

    Args:
        height: The frame's height, in pixels.

    Returns:
        One dot a pixel up to 359 pixels tall, and one more pixel for each
        270 pixels past that: 4 at 1080.
    """
    return max(1, height // 270)


def text_width(text: String, scale: Int) -> Int:
    """Return how wide a line of text is drawn.

    Args:
        text: The line.
        scale: The size of the text: see `text_size`.

    Returns:
        The sum of its characters' advances, in whole pixels.
    """
    return Int(ceil(styled_width(text, text_size(scale))))


def text_size(scale: Int) -> Float32:
    """Return the height of a capital letter at a scale of the display.

    Args:
        scale: The scale, as `hud_scale` gives it.

    Returns:
        `TEXT_SIZE` times the scale, in pixels.
    """
    return TEXT_SIZE * Float32(scale)


comptime TEXT_SIZE = Float32(5.5)
"""How tall a capital letter of the display's text is, in units of the
scale. A line keeps a row 7 units tall, and stands in its middle."""


def _row_top(y: Int, scale: Int) -> Float32:
    """Return the top of the capitals of a line whose row starts at `y`:
    the line stands in the middle of a row 7 units tall."""
    return Float32(y) + (7 - TEXT_SIZE) / 2 * Float32(scale)


def _glyph(code: Int) -> Int:
    """Return a character's glyph in `GLYPHS`, or -1 for one the font does
    not hold."""
    if code >= 65 and code <= 90:
        return code - 65
    if code >= 48 and code <= 57:
        return code - 48 + 26
    if code >= 97 and code <= 122:
        return code - 97 + 45
    var marks = StaticString("+/:.,!?'-").as_bytes()
    for k in range(len(marks)):  # pragma: no branch
        if Int(marks[k]) == code:
            return 36 + k
    return -1


def _metric(glyph: Int, k: Int) -> Int:
    """Return one of a glyph's six metric levels."""
    return Int(FONT_METRICS.as_bytes()[6 * glyph + k]) - FONT_FIRST


def _advance(glyph: Int) -> Float32:
    """Return a glyph's advance, in samples."""
    var eighths = _metric(glyph, 0) * FONT_LEVELS + _metric(glyph, 1)
    return Float32(eighths) / 8


def _level(glyph: Int, x: Int, y: Int) -> Float32:
    """Return the field at a sample of a glyph's cell, from 0 outside to 1
    inside; 0 off the cell."""
    if x < 0 or y < 0 or x >= FONT_CELL or y >= FONT_CELL:
        return 0
    var at = (glyph * FONT_CELL + y) * FONT_CELL + x
    var level = Int(FONT_FIELD.unsafe_ptr()[at]) - FONT_FIRST
    return Float32(level) * _PER_LEVEL


comptime _PER_LEVEL = Float32(1) / Float32(FONT_LEVELS - 1)
"""The field's step from one level to the next."""


def _field(glyph: Int, u: Float32, v: Float32) -> Float32:
    """Return the field at a point of a glyph's cell, in samples, from the
    four samples round it."""
    var fx = u - 0.5
    var fy = v - 0.5
    var x = Int(floor(fx))
    var y = Int(floor(fy))
    var tx = fx - Float32(x)
    var ty = fy - Float32(y)
    if x < 0 or y < 0 or x + 1 >= FONT_CELL or y + 1 >= FONT_CELL:
        var top = _level(glyph, x, y) * (1 - tx) + _level(glyph, x + 1, y) * tx
        var low = _level(glyph, x, y + 1) * (1 - tx)
        low += _level(glyph, x + 1, y + 1) * tx
        return top * (1 - ty) + low * ty
    # Inside the cell: the four samples, read straight.
    var field = FONT_FIELD.unsafe_ptr()
    var at = (glyph * FONT_CELL + y) * FONT_CELL + x
    var a = Float32(Int(field[at]) - FONT_FIRST)
    var b = Float32(Int(field[at + 1]) - FONT_FIRST)
    var c = Float32(Int(field[at + FONT_CELL]) - FONT_FIRST)
    var d = Float32(Int(field[at + FONT_CELL + 1]) - FONT_FIRST)
    var top = a + (b - a) * tx
    var low = c + (d - c) * tx
    return (top + (low - top) * ty) * _PER_LEVEL


@fieldwise_init
struct TextStyle(ImplicitlyCopyable):
    """How a line of text is drawn: its size, its color, and the edge,
    shadow, weight and slant it takes."""

    var size: Float32
    """The height of a capital letter, in pixels."""
    var color: Rgb
    """The letters' color."""
    var alpha: Float32
    """How much the letters and their edge and shadow cover the frame,
    from 0 to 1."""
    var outline: Float32
    """How wide the dark ring round each letter is, in pixels; 0 for
    none."""
    var shadow: Float32
    """How far down and right the soft shadow falls, in pixels, and how
    soft it is; 0 for none."""
    var weight: Float32
    """How much bolder than the font the letters are, in pixels."""
    var slant: Float32
    """How far right a letter leans for each pixel of its height: 0 is
    upright, 0.2 italic."""


def plain_style(scale: Int, color: Rgb, alpha: Float32) -> TextStyle:
    """Return the style of `draw_text`: a soft shadow, and no ring.

    Args:
        scale: The scale of the display.
        color: The letters' color.
        alpha: How much the text covers the frame.

    Returns:
        The style.
    """
    var size = text_size(scale)
    return TextStyle(size, color, alpha, 0, size * 0.12, 0, 0)


def ringed_style(scale: Int, color: Rgb, alpha: Float32) -> TextStyle:
    """Return the style of `draw_outlined`: a dark ring and a soft shadow.

    Args:
        scale: The scale of the display.
        color: The letters' color.
        alpha: How much the text covers the frame.

    Returns:
        The style.
    """
    var size = text_size(scale)
    return TextStyle(size, color, alpha, size * 0.11, size * 0.1, 0, 0)


def styled_width(text: String, size: Float32) -> Float32:
    """Return how wide a line of text of a size is drawn.

    Args:
        text: The line.
        size: The height of a capital letter, in pixels.

    Returns:
        The sum of its characters' advances, in pixels. A character that
        the font does not hold takes a space's.
    """
    var r = size / FONT_CAP
    var bytes = text.as_bytes()
    var width = Float32(0)
    for k in range(len(bytes)):
        var g = _glyph(Int(bytes[k]))
        width += (_advance(g) if g >= 0 else FONT_SPACE) * r
    return width


def draw_styled(
    mut frame: Framebuffer,
    x: Float32,
    y: Float32,
    text: String,
    style: TextStyle,
):
    """Draw a line of text in a style, the top of its capitals at a point.

    The letters' edges are smooth: each pixel takes the share of it that
    a letter covers. The shadow is drawn first, then every ring, then the
    letters, so a ring never covers a letter beside it.

    Args:
        frame: The frame.
        x: The left of the first letter, in pixels.
        y: The top of a capital letter, in pixels.
        text: The line. A character that the font does not hold is left
            as a space.
        style: How it is drawn.
    """
    if style.alpha <= 0 or style.size <= 0:
        return
    var r = style.size / FONT_CAP
    var bytes = text.as_bytes()
    var spread = FONT_SPREAD * 2 * r
    # The cell's top, in pixels.
    var top = y - (FONT_BASE - FONT_CAP) * r
    # The field holds distances out to `FONT_SPREAD` samples from the
    # letters' edges: a ring and a shadow keep within that.
    var room = FONT_SPREAD * r - 1
    var ring = min(style.outline, room / 2)
    var soft = max(min(style.shadow, room - ring), Float32(0.5))
    for layer in range(3):
        if layer == 0 and style.shadow <= 0:
            continue
        if layer == 1 and ring <= 0:
            continue
        var off = style.shadow if layer == 0 else Float32(0)
        # How far past a letter's ink this layer reaches, in pixels.
        var reach = ring + style.weight + 1 + (soft if layer == 0 else 0)
        var paint = SHADOW if layer < 2 else style.color
        var strength = style.alpha * (Float32(0.6) if layer == 0 else 1)
        var pen = x
        for k in range(len(bytes)):
            var g = _glyph(Int(bytes[k]))
            if g < 0:
                pen += FONT_SPACE * r
                continue
            var left = pen + (Float32(_metric(g, 2)) - FONT_PAD) * r
            var right = pen + (Float32(_metric(g, 3)) - FONT_PAD) * r
            var high = top + Float32(_metric(g, 4)) * r
            var low = top + Float32(_metric(g, 5)) * r
            # A leaning letter's top leans right of its foot.
            var lean = style.slant * (FONT_BASE * r)
            var x0 = Int(floor(left - reach + off - style.slant * (low - top)))
            var x1 = Int(ceil(right + reach + lean + off))
            var y0 = Int(floor(high - reach + off))
            var y1 = Int(ceil(low + reach + off))
            for py in range(max(0, y0), min(frame.height, y1)):
                var v = (Float32(py) + 0.5 - off - top) / r
                var shear = style.slant * (FONT_BASE - v)
                for px in range(max(0, x0), min(frame.width, x1)):
                    var u = (Float32(px) + 0.5 - off - pen) / r + FONT_PAD
                    var d = (_field(g, u - shear, v) - 0.5) * spread
                    d += style.weight
                    var cover: Float32
                    if layer == 0:
                        cover = (d + ring + soft) / (2 * soft)
                    elif layer == 1:
                        cover = d + ring + 0.5
                    else:
                        cover = d + 0.5
                    cover = min(Float32(1), max(Float32(0), cover))
                    if cover > 0:
                        _blend(frame, px, py, paint, strength * cover)
            pen += _advance(g) * r


def _blend(mut frame: Framebuffer, x: Int, y: Int, color: Rgb, alpha: Float32):
    """Blend a color over one pixel of the frame. The caller keeps the
    pixel on the frame."""
    var p = frame.pixels.unsafe_ptr() + (y * frame.width + x) * 4
    var keep = 1 - alpha
    p[0] = UInt8(Int(Float32(p[0]) * keep + Float32(color.r) * alpha))
    p[1] = UInt8(Int(Float32(p[1]) * keep + Float32(color.g) * alpha))
    p[2] = UInt8(Int(Float32(p[2]) * keep + Float32(color.b) * alpha))


def _mix(a: Rgb, b: Rgb, t: Float32) -> Rgb:
    """Return the color a share `t` of the way from `a` to `b`."""
    return Rgb(
        Int(Float32(a.r) + Float32(b.r - a.r) * t + 0.5),
        Int(Float32(a.g) + Float32(b.g - a.g) * t + 0.5),
        Int(Float32(a.b) + Float32(b.b - a.b) * t + 0.5),
    )


def _slant(
    mut frame: Framebuffer,
    x: Float32,
    y: Int,
    width: Float32,
    height: Int,
    lean: Float32,
    start: Float32,
    stop: Float32,
    top: Rgb,
    bottom: Rgb,
    alpha: Float32,
):
    """Blend a share of a leaning bar over the frame, its colors shaded
    from its top row to its bottom row.

    The bar's top row stands `lean` pixels right of its bottom row. The
    part drawn runs from the share `start` of its width to `stop`. Its
    left and right edges are smooth. The caller gives a strength over 0."""
    if stop <= start:
        return
    for row in range(height):  # pragma: no branch
        var py = y + row
        if py < 0 or py >= frame.height:
            continue
        var t = (Float32(row) + 0.5) / Float32(height)
        var shift = lean * (1 - t)
        var left = x + shift + width * start
        var right = x + shift + width * stop
        var paint = _mix(top, bottom, t)
        var x0 = max(0, Int(floor(left)))
        var x1 = min(frame.width, Int(ceil(right)))
        for px in range(x0, x1):
            var a = Float32(px + 1) - left
            var b = right - Float32(px)
            # A pixel of the span is covered in part at the least.
            var cover = min(Float32(1), min(a, b))
            _blend(frame, px, py, paint, alpha * cover)


comptime _WHITE = Rgb(255, 255, 255)
comptime BAR_LEAN = Float32(0.8)
"""How far right a gauge's top leans past its foot, for each pixel of its
height."""
comptime TICK_HEIGHT = 5
"""The least height, in pixels, of a gauge that is marked at each tenth."""
comptime TICK_WIDTH = 160
"""The least width, in pixels, of a gauge that is marked at each tenth."""


def draw_gauge(
    mut frame: Framebuffer,
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    share: Float32,
    color: Rgb,
    chip: Float32 = -1,
):
    """Draw a gauge: a leaning bar on a dark plate, filled from the left by
    a share.

    The fill is shaded from light at its top to dark at its foot, and its
    leading edge is bright. Past the share, up to `chip`, the bar is pale:
    what a blow just took, which then drains. A gauge `TICK_HEIGHT` pixels
    tall and `TICK_WIDTH` wide or more is marked at each tenth.

    Args:
        frame: The frame.
        x: The left of the bar's foot, in pixels.
        y: Its top, in pixels.
        width: Its width, in pixels.
        height: Its height, in pixels.
        share: How full it is, from 0 to 1.
        color: The fill's color.
        chip: How full it was a moment ago, from 0 to 1; less than
            `share` for none.
    """
    if width <= 0 or height <= 0:
        return
    var full = max(Float32(0), min(Float32(1), share))
    var was = max(Float32(0), min(Float32(1), chip))
    var lean = BAR_LEAN * Float32(height)
    var w = Float32(width)
    # The plate: a pixel round the bar, dark.
    var edge = Float32(1) / Float32(height + 2)
    _slant(
        frame,
        Float32(x) - 1 - lean * edge,
        y - 1,
        w + 2,
        height + 2,
        lean * (1 + 2 * edge),
        0,
        1,
        SHADOW,
        SHADOW,
        0.62,
    )
    if was > full:
        _slant(
            frame,
            Float32(x),
            y,
            w,
            height,
            lean,
            full,
            was,
            CHIP,
            CHIP,
            0.85,
        )
    var light = _mix(color, _WHITE, 0.4)
    var deep = _mix(color, SHADOW, 0.35)
    _slant(frame, Float32(x), y, w, height, lean, 0, full, light, deep, 1)
    if height >= TICK_HEIGHT and width >= TICK_WIDTH:
        var tick = Float32(1) / w
        for k in range(1, 10):
            var at = Float32(k) / 10
            _slant(
                frame,
                Float32(x),
                y,
                w,
                height,
                lean,
                at - tick / 2,
                at + tick / 2,
                SHADOW,
                SHADOW,
                Float32(0.22) if at < full else Float32(0.1),
            )
    # The leading edge, bright.
    if full > 0 and full < 1:
        var glow = min(Float32(2), w * full) / w
        _slant(
            frame,
            Float32(x),
            y,
            w,
            height,
            lean,
            full - glow,
            full,
            _WHITE,
            _mix(color, _WHITE, 0.6),
            0.7,
        )


comptime CHIP = Rgb(255, 236, 196)
"""The pale part of a gauge: what a blow just took."""


def draw_panel(
    mut frame: Framebuffer, x0: Int, y0: Int, x1: Int, y1: Int, scale: Int
):
    """Draw a panel of frosted glass behind a group of words and bars, so
    they read over a bright sky.

    What is behind the panel is blurred and darkened, more toward its
    foot. Its corners are round, its edges smooth, and its top edge
    catches the light. The blur is made on a grid of cells `scale`
    pixels on a side, and the panel's rows are drawn in parallel.

    Args:
        frame: The frame.
        x0: The panel's left pixel.
        y0: Its top pixel.
        x1: One past its right pixel.
        y1: One past its bottom pixel.
        scale: The scale of the display: the corners' radius is 3 times
            it, in pixels.
    """
    var left = max(0, x0)
    var top = max(0, y0)
    var right = min(frame.width, x1)
    var low = min(frame.height, y1)
    if right <= left or low <= top:
        return
    var cell = max(1, scale)
    var grid = _shrink(frame, left, top, right, low, cell)
    var gw = (right - left + cell - 1) // cell
    var gh = (low - top + cell - 1) // cell
    var line = List[Int32](length=max(gw, gh) * 3, fill=0)
    for _ in range(2):
        _box_pass(grid, line, gw, gh, 3, gw * 3, 1, 3)
        _box_pass(grid, line, gh, gw, gw * 3, 3, 1, 3)
    var rows = low - top
    var tasks = max(1, min(available_workers(), rows // 8))
    var group = TaskGroup()
    for t in range(tasks):  # pragma: no branch
        group.create_task(
            _glass_task(
                frame.pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                frame.width,
                grid.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                gw,
                gh,
                cell,
                _Glass(x0, y0, x1, y1, left, top, right, Float32(3 * scale)),
                top + t * rows // tasks,
                top + (t + 1) * rows // tasks,
            )
        )
    group.wait()
    _ = grid^


@fieldwise_init
struct _Glass(ImplicitlyCopyable):
    """Where a panel of frosted glass stands, and the part of it on the
    frame."""

    var x0: Int
    var y0: Int
    var x1: Int
    var y1: Int
    var left: Int
    var top: Int
    var right: Int
    var radius: Float32


def _shrink(
    frame: Framebuffer, x0: Int, y0: Int, x1: Int, y1: Int, cell: Int
) -> List[Int32]:
    """Return a box of the frame averaged down to cells `cell` pixels on a
    side: three channels a cell, row by row."""
    var w = x1 - x0
    var h = y1 - y0
    var gw = (w + cell - 1) // cell
    var gh = (h + cell - 1) // cell
    var grid = List[Int32](length=gw * gh * 3, fill=0)
    var pixels = frame.pixels.unsafe_ptr()
    var g = grid.unsafe_ptr()
    for y in range(h):  # pragma: no branch
        var row = pixels + ((y0 + y) * frame.width + x0) * 4
        var gy = g + (y // cell) * gw * 3
        for x in range(w):  # pragma: no branch
            var at = gy + (x // cell) * 3
            var from_ = row + 4 * x
            at[0] += Int32(from_[0])
            at[1] += Int32(from_[1])
            at[2] += Int32(from_[2])
    for cy in range(gh):  # pragma: no branch
        var tall = min(cell, h - cy * cell)
        for cx in range(gw):  # pragma: no branch
            var n = Int32(tall * min(cell, w - cx * cell))
            var at = g + (cy * gw + cx) * 3
            at[0] //= n
            at[1] //= n
            at[2] //= n
    return grid^


__async def _glass_task(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    width: Int,
    grid: MutPointer[Int32, MutAnyOrigin],
    gw: Int,
    gh: Int,
    cell: Int,
    glass: _Glass,
    first: Int,
    past: Int,
):
    """Draw rows `first` to `past` of a panel: the blurred grid, between
    the four cells round each pixel, darkened, inside the panel's round
    corners."""
    var per = Float32(1) / Float32(cell)
    var w = Float32(glass.x1 - glass.x0)
    var h = Float32(glass.y1 - glass.y0)
    var r = glass.radius
    for y in range(first, past):  # pragma: no branch
        var row = pixels + (y * width + glass.left) * 4
        var fy = (Float32(y - glass.top) + 0.5) * per - 0.5
        var cy = min(gh - 1, max(0, Int(floor(fy))))
        var upper = grid + cy * gw * 3
        var lower = grid + min(gh - 1, cy + 1) * gw * 3
        var ty = min(Float32(1), max(Float32(0), fy - Float32(cy)))
        var t = (Float32(y - glass.y0) + 0.5) / h
        var dark = PANEL_ALPHA * (0.7 + 0.6 * t)
        var dy = abs(Float32(y - glass.y0) + 0.5 - h / 2) - (h / 2 - r)
        var lit = y == glass.y0
        for x in range(glass.right - glass.left):  # pragma: no branch
            var px = Float32(x + glass.left - glass.x0) + 0.5
            var dx = abs(px - w / 2) - (w / 2 - r)
            # How far outside the round box the pixel's middle is.
            var ox = max(dx, Float32(0))
            var oy = max(dy, Float32(0))
            var out = sqrt(ox * ox + oy * oy) + min(max(dx, dy), Float32(0))
            var cover = min(Float32(1), max(Float32(0), 0.5 - (out - r)))
            if cover <= 0:
                continue
            var fx = (Float32(x) + 0.5) * per - 0.5
            var cx = min(gw - 1, max(0, Int(floor(fx))))
            var a = 3 * cx
            var b = 3 * min(gw - 1, cx + 1)
            var tx = min(Float32(1), max(Float32(0), fx - Float32(cx)))
            var keep = 1 - dark
            for k in range(3):
                var ua = Float32(upper[a + k])
                var la = Float32(lower[a + k])
                var top = ua + (Float32(upper[b + k]) - ua) * tx
                var low = la + (Float32(lower[b + k]) - la) * tx
                var blurred = top + (low - top) * ty
                var shade = Float32(
                    SHADOW.r if k == 0 else (SHADOW.g if k == 1 else SHADOW.b)
                )
                var tinted = blurred * keep + shade * dark
                if lit:
                    tinted += (255 - tinted) * 0.14
                var under = Float32(row[4 * x + k])
                row[4 * x + k] = UInt8(
                    Int(under + (tinted - under) * cover + 0.5)
                )


def draw_pill(
    mut frame: Framebuffer, x0: Int, y0: Int, x1: Int, y1: Int, alpha: Float32
):
    """Darken a box with fully round ends behind a line of words, so that
    it reads over a bright sky.

    Args:
        frame: The frame.
        x0: The box's left pixel.
        y0: Its top pixel.
        x1: One past its right pixel.
        y1: One past its bottom pixel.
        alpha: How dark it is, from 0 to 1.
    """
    _round_box(
        frame,
        x0,
        y0,
        x1,
        y1,
        Float32(y1 - y0) / 2,
        SHADOW,
        alpha,
        alpha,
        0,
    )


def draw_chip(
    mut frame: Framebuffer,
    x0: Int,
    y0: Int,
    x1: Int,
    y1: Int,
    rim: Rgb,
    alpha: Float32,
):
    """Draw a small dark box with round corners and a colored rim, such as
    a key of a combo.

    Args:
        frame: The frame.
        x0: The box's left pixel.
        y0: Its top pixel.
        x1: One past its right pixel.
        y1: One past its bottom pixel.
        rim: The color of its edge.
        alpha: How much it covers the frame, from 0 to 1.
    """
    var radius = Float32(min(x1 - x0, y1 - y0)) / 4
    _round_box(frame, x0, y0, x1, y1, radius, rim, alpha, alpha, 0)
    _round_box(
        frame,
        x0 + 1,
        y0 + 1,
        x1 - 1,
        y1 - 1,
        radius - 1,
        SHADOW,
        0.75 * alpha,
        0.9 * alpha,
        0,
    )


def _round_box(
    mut frame: Framebuffer,
    x0: Int,
    y0: Int,
    x1: Int,
    y1: Int,
    radius: Float32,
    color: Rgb,
    top_alpha: Float32,
    foot_alpha: Float32,
    shine: Float32,
):
    """Blend a color over a box with round corners and smooth edges, from
    one strength at its top to another at its foot; its top row lit by
    `shine`."""
    var w = Float32(x1 - x0)
    var h = Float32(y1 - y0)
    if w <= 0 or h <= 0:
        return
    for py in range(max(0, y0), min(frame.height, y1)):  # pragma: no branch
        var t = (Float32(py - y0) + 0.5) / h
        var strength = top_alpha + (foot_alpha - top_alpha) * t
        var dy = abs(Float32(py - y0) + 0.5 - h / 2) - (h / 2 - radius)
        for px in range(max(0, x0), min(frame.width, x1)):
            var dx = abs(Float32(px - x0) + 0.5 - w / 2) - (w / 2 - radius)
            # How far outside the box the pixel's middle is.
            var ox = max(dx, Float32(0))
            var oy = max(dy, Float32(0))
            var out = sqrt(ox * ox + oy * oy) + min(max(dx, dy), Float32(0))
            out -= radius
            var cover = min(Float32(1), max(Float32(0), 0.5 - out))
            if cover <= 0:
                continue
            _blend(frame, px, py, color, strength * cover)
            if shine > 0 and py == y0:
                _blend(frame, px, py, _WHITE, shine * cover)


def _box_pass(
    mut plane: List[Int32],
    mut line: List[Int32],
    long: Int,
    lines: Int,
    step: Int,
    next: Int,
    radius: Int,
    span: Int32,
):
    """Average each pixel of each line of a plane of three channels with
    the `radius` pixels each side of it, by a running sum.

    A line is `long` pixels, `step` apart in the plane; the lines start
    `next` apart."""
    var last = long - 1
    for l in range(lines):  # pragma: no branch
        var start = l * next
        for c in range(3):
            var base = start + c
            var sum = Int32(0)
            for k in range(-radius, radius + 1):  # pragma: no branch
                sum += plane[base + min(last, max(0, k)) * step]
            for i in range(long):  # pragma: no branch
                line[i] = sum // span
                var leave = base + max(0, i - radius) * step
                var enter = base + min(last, i + radius + 1) * step
                sum += plane[enter] - plane[leave]
            for i in range(long):  # pragma: no branch
                plane[base + i * step] = line[i]


def fill_box(
    mut frame: Framebuffer,
    x0: Int,
    y0: Int,
    x1: Int,
    y1: Int,
    color: Rgb,
    alpha: Float32,
):
    """Blend a color over a box of pixels, clipped to the frame.

    Args:
        frame: The frame.
        x0: The box's left pixel.
        y0: Its top pixel.
        x1: One past its right pixel.
        y1: One past its bottom pixel.
        color: The color.
        alpha: How much of the color covers the frame, from 0 to 1.
    """
    for y in range(max(0, y0), min(frame.height, y1)):
        for x in range(max(0, x0), min(frame.width, x1)):
            _blend(frame, x, y, color, alpha)


def draw_text(
    mut frame: Framebuffer,
    x: Int,
    y: Int,
    text: String,
    scale: Int,
    color: Rgb,
    alpha: Float32,
):
    """Draw a line of text with a soft shadow, its top left at a pixel.

    A character that the font does not hold is left as a space.

    Args:
        frame: The frame.
        x: The left of the first character, in pixels.
        y: The top of the line's row, 7 times `scale` tall, in pixels.
        text: The line.
        scale: The size of the text: see `text_size`.
        color: The text's color.
        alpha: How much the text and its shadow cover the frame, from 0
            to 1.
    """
    draw_styled(
        frame,
        Float32(x),
        _row_top(y, scale),
        text,
        plain_style(scale, color, alpha),
    )


def draw_outlined(
    mut frame: Framebuffer,
    x: Int,
    y: Int,
    text: String,
    scale: Int,
    color: Rgb,
    alpha: Float32,
):
    """Draw a line of text ringed by a dark outline, its top left at a
    pixel, so it reads over a bright sky as over dark grass.

    A character that the font does not hold is left as a space.

    Args:
        frame: The frame.
        x: The left of the first character, in pixels.
        y: The top of the line's row, 7 times `scale` tall, in pixels.
        text: The line.
        scale: The size of the text: see `text_size`.
        color: The text's color.
        alpha: How much the text and its outline cover the frame, from 0
            to 1.
    """
    draw_styled(
        frame,
        Float32(x),
        _row_top(y, scale),
        text,
        ringed_style(scale, color, alpha),
    )


def kind_color(kind: GatherKind) -> Rgb:
    """Return the swatch color of a kind in the satchel.

    Args:
        kind: The kind.

    Returns:
        Green herbs, red mushrooms, purple berries, copper ore, gold
        coins, blue trinkets, silver fish and black seals.
    """
    if kind == HERBS:
        return Rgb(90, 160, 60)
    if kind == MUSHROOMS:
        return Rgb(200, 50, 40)
    if kind == BERRIES:
        return Rgb(140, 40, 110)
    if kind == ORE:
        return Rgb(200, 110, 50)
    if kind == CHEST:
        return Rgb(250, 200, 70)
    if kind == FISH:
        return Rgb(150, 190, 210)
    if kind == SEAL:
        return Rgb(60, 50, 60)
    return Rgb(80, 140, 240)


def use_prompt(
    kind: GatherKind, strikes: Int, phase: Int = 0, needed: Int = STRIKES
) -> String:
    """Return what the prompt says the use button does at a spot.

    Args:
        kind: The spot's kind.
        strikes: How many times a boulder has been struck.
        phase: A fishing spot's phase: `IDLE`, `WAITING` or `BITING`.
        needed: How many strikes a boulder takes to give its ore.

    Returns:
        The button and the deed, such as "E  GATHER HERBS", or for a
        boulder "E  MINE ORE 1/3". At a fishing spot, it casts the line,
        reels it in, or hooks the fish that bites.
    """
    if kind == HERBS:
        return "E  GATHER HERBS"
    if kind == MUSHROOMS:
        return "E  PICK MUSHROOMS"
    if kind == BERRIES:
        return "E  PICK BERRIES"
    if kind == ORE:
        return String("E  MINE ORE ", strikes, "/", needed)
    if kind == CHEST:
        return "E  OPEN CHEST"
    if kind == FISH and phase == BITING:
        return "E  HOOK IT!"
    if kind == FISH and phase == WAITING:
        return "E  REEL IN"
    if kind == FISH:
        return "E  CAST LINE"
    return "E  TAKE TRINKET"


def note_text(kind: GatherKind, gives: Int) raises -> String:
    """Return the note that says what was gathered.

    Args:
        kind: The kind of spot.
        gives: How many things it gave.

    Returns:
        A plus, the count and the things' name, such as "+3 BERRIES".

    Raises:
        Error: If the kind is not one.
    """
    return String("+", gives, " ", kind_name(kind))


def note_alpha(age: Float32, seconds: Float32 = NOTE_SECONDS) -> Float32:
    """Return how strongly a note shows, by how long it has shown.

    Args:
        age: How long the note has shown, in seconds.
        seconds: How long the note shows.

    Returns:
        One until the fade begins, `NOTE_FADE` before the end, then less,
        to zero at `seconds` and after.
    """
    var left = seconds - age
    if left <= 0:
        return 0
    return min(Float32(1), left / NOTE_FADE)


def draw_vignette(mut frame: Framebuffer, strength: Float32) raises:
    """Redden a frame's edges, as a player who is hurt or near falling
    sees it.

    The red is strongest in the corners, and fades to nothing a
    `VIGNETTE_CLEAR` share of the way out from the middle.

    Args:
        frame: The frame. Its pixels are changed.
        strength: How strong the red is, from 0, none, to 1.

    Raises:
        Error: If the strength is not from 0 to 1.
    """
    if not (strength >= 0 and strength <= 1):
        raise Error("A vignette's strength must be from 0 to 1")
    if strength == 0:
        return
    var tasks = max(1, min(available_workers() * 2, frame.height))
    var group = TaskGroup()
    for t in range(tasks):  # pragma: no branch
        group.create_task(
            _vignette_task(
                frame.pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                frame.width,
                frame.height,
                strength,
                t * frame.height // tasks,
                (t + 1) * frame.height // tasks,
            )
        )
    group.wait()


def clear_span(
    y: Int, width: Int, height: Int, radius: Float32
) -> Tuple[Int, Int]:
    """Return the pixels of a row that lie, for certain, within a radius
    of the frame's middle, as an edge's tint measures it.

    A pixel's place is `((x + 0.5) / width * 2 - 1, (y + 0.5) / height *
    2 - 1)`. The span keeps a little inside the circle, and a pixel of
    margin at each end, so a pixel near the circle's edge is left to the
    tint's own test.

    Args:
        y: The row.
        width: The frame's width, in pixels.
        height: The frame's height, in pixels.
        radius: The radius, in those units.

    Returns:
        The first pixel of the span and the one past its last; the two
        are equal for a row with no such pixel.
    """
    var dy = (Float32(y) + 0.5) / Float32(height) * 2 - 1
    # A row near the top or the bottom of the circle meets it at a slant,
    # where a rounding of its height moves the ends far: the span keeps
    # a little inside the circle.
    var inside = radius * 0.999
    var room = inside * inside - dy * dy
    if room <= 0:
        return (0, 0)
    var half = sqrt(room)
    var w = Float32(width)
    var first = max(0, Int(ceil((1 - half) * w / 2 - 0.5)) + 1)
    var past = min(width, Int(floor((1 + half) * w / 2 - 0.5)))
    if past <= first:
        return (0, 0)
    return (first, past)


__async def _vignette_task(
    pixels: MutPointer[UInt8, MutAnyOrigin],
    width: Int,
    height: Int,
    strength: Float32,
    first: Int,
    past: Int,
):
    """Redden rows `first` to `past`, past the clear middle."""
    var w = Float32(width)
    var h = Float32(height)
    for y in range(first, past):  # pragma: no branch
        var dy = (Float32(y) + 0.5) / h * 2 - 1
        var clear = clear_span(y, width, height, VIGNETTE_CLEAR * 1.4142)
        var x = 0
        while x < width:
            if x == clear[0] and clear[1] > clear[0]:
                x = clear[1]
                continue
            var dx = (Float32(x) + 0.5) / w * 2 - 1
            var reach = sqrt(dx * dx + dy * dy) / 1.4142
            if reach > VIGNETTE_CLEAR:
                var t = (reach - VIGNETTE_CLEAR) / (1 - VIGNETTE_CLEAR)
                var alpha = min(Float32(0.85), t * t * strength)
                var at = (y * width + x) * 4
                var keep = 1 - alpha
                pixels[unsafe_offset=at] = UInt8(
                    Int(Float32(pixels[unsafe_offset=at]) * keep + 150 * alpha)
                )
                pixels[unsafe_offset=at + 1] = UInt8(
                    Int(Float32(pixels[unsafe_offset=at + 1]) * keep)
                )
                pixels[unsafe_offset=at + 2] = UInt8(
                    Int(Float32(pixels[unsafe_offset=at + 2]) * keep)
                )
            x += 1


def _prompt(mut frame: Framebuffer, prompt: String, top: Int, scale: Int):
    """Draw what the use button does, in the bottom middle, on a dark pill:
    the key, before the first two spaces, on a key's chip, and what it
    does after them."""
    var at = prompt.find("  ")
    var key = String(prompt[byte=:at]) if at > 0 else String()
    var rest = String(prompt[byte = at + 2 :]) if at > 0 else prompt
    var cap = 9 * scale
    var gap = 3 * scale
    var lead = cap + gap if at > 0 else 0
    var width = lead + text_width(rest, scale)
    var x = (frame.width - width) // 2
    var y = top - scale
    draw_pill(
        frame,
        x - 4 * scale,
        y - 2 * scale,
        x + width + 5 * scale,
        y + cap + 2 * scale,
        0.55,
    )
    if at > 0:
        draw_chip(frame, x, y, x + cap, y + cap, WHITE_TEXT, 1)
        var small = Float32(5 * scale)
        draw_styled(
            frame,
            Float32(x) + (Float32(cap) - styled_width(key, small)) / 2,
            Float32(y) + (Float32(cap) - small) / 2,
            key,
            TextStyle(small, WHITE_TEXT, 1, 0, 0, 0, 0),
        )
    draw_text(frame, x + lead, top, rest, scale, WHITE_TEXT, 1)


def draw_hud(
    mut frame: Framebuffer,
    satchel: Satchel,
    prompt: String,
    note: String,
    note_age: Float32,
    speech: String = String(),
    speech_age: Float32 = SPEECH_SECONDS,
    errands: List[String] = List[String](),
    skills: List[String] = List[String](),
) raises:
    """Draw the satchel, the prompt, the note, what a villager said, the
    errands taken and the player's skills over a frame.

    Args:
        frame: The frame, the window's size.
        satchel: What the player holds. A kind the player holds none of
            is left out, and an empty satchel draws no panel.
        prompt: What the use button does, or empty for no prompt.
        note: What was just gathered, or empty for no note.
        note_age: How long the note has shown, in seconds.
        speech: What a villager last said, or empty for nothing. It shows
            in a panel over the note for `SPEECH_SECONDS`.
        speech_age: How long it has shown, in seconds.
        errands: A line for each errand taken, listed in the top right.
        skills: A line for each skill, listed in the top left.

    Raises:
        Error: Never: each kind's name is known.
    """
    var scale = hud_scale(frame.height)
    var line = 10 * scale
    var margin = 6 * scale
    var shown = List[Int]()
    for k in range(KINDS):  # pragma: no branch
        if satchel.counts[k] > 0:
            shown.append(k)
    if len(shown) > 0:
        var widest = 0
        for k in shown:  # pragma: no branch
            var label = String(kind_name(GatherKind(k)), " ", satchel.counts[k])
            widest = max(widest, text_width(label, scale))
        var top = frame.height - margin - line * len(shown) - 2 * scale
        draw_panel(
            frame,
            margin - 4 * scale,
            top - 4 * scale,
            margin + widest + 13 * scale,
            frame.height - margin + 2 * scale,
            scale,
        )
        for row in range(len(shown)):  # pragma: no branch
            var k = shown[row]
            var y = top + row * line
            var swatch = kind_color(GatherKind(k))
            _round_box(
                frame,
                margin,
                y,
                margin + 6 * scale,
                y + 7 * scale,
                Float32(2 * scale),
                swatch,
                1,
                1,
                0.3,
            )
            draw_text(
                frame,
                margin + 9 * scale,
                y,
                String(kind_name(GatherKind(k)), " ", satchel.counts[k]),
                scale,
                WHITE_TEXT,
                1,
            )
    var bottom = frame.height - margin - 7 * scale
    if prompt.byte_length() > 0:
        _prompt(frame, prompt, bottom, scale)
    var alpha = note_alpha(note_age)
    if note.byte_length() > 0 and alpha > 0:
        var width = text_width(note, scale)
        draw_text(
            frame,
            (frame.width - width) // 2,
            bottom - 2 * line,
            note,
            scale,
            GOLD_TEXT,
            alpha,
        )
    var said = note_alpha(speech_age, SPEECH_SECONDS)
    if speech.byte_length() > 0 and said > 0:
        var width = text_width(speech, scale)
        var x = (frame.width - width) // 2
        var y = bottom - 4 * line
        draw_panel(
            frame,
            x - 6 * scale,
            y - 5 * scale,
            x + width + 6 * scale,
            y + 12 * scale,
            scale,
        )
        draw_text(frame, x, y, speech, scale, WHITE_TEXT, said)
    for row in range(len(errands)):
        var width = text_width(errands[row], scale)
        draw_text(
            frame,
            frame.width - margin - width,
            margin + row * line,
            errands[row],
            scale,
            GOLD_TEXT,
            1,
        )
    for row in range(len(skills)):
        draw_text(
            frame,
            margin,
            margin + row * line,
            skills[row],
            scale,
            WHITE_TEXT,
            1,
        )
