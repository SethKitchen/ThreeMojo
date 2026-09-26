"""Writes two small TrueType fonts with fontTools, for `three_ttf.mjs`.

`curves.ttf` has quadratic contours that start off the curve, composite
glyphs placed by an offset, a scale, a 2 by 2 matrix and matched points,
an empty glyph, a glyph under two code points, a digit, and a Windows and
a Macintosh full name. Its cmap is format 4. `astral.ttf` maps a code
point past the first plane through a format 12 cmap.
"""
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphComponent


def contour_glyph():
    pen = TTGlyphPen(None)
    # Off-curve points in a row, and a contour that starts off the curve.
    pen.moveTo((100, 0))
    pen.lineTo((500, 0))
    pen.qCurveTo((700, 100), (700, 400), (500, 600))
    pen.lineTo((100, 600))
    pen.closePath()
    pen.qCurveTo((250, 150), (350, 150), (350, 450), (250, 450), None)
    pen.closePath()
    return pen.glyph()


def box_glyph():
    pen = TTGlyphPen(None)
    pen.moveTo((0, 0))
    pen.lineTo((300, 0))
    pen.lineTo((300, 300))
    pen.lineTo((0, 300))
    pen.closePath()
    return pen.glyph()


def composite(parts):
    glyph = Glyph()
    glyph.numberOfContours = -1
    glyph.components = []
    for name, x, y, transform, matched in parts:
        c = GlyphComponent()
        c.glyphName = name
        c.flags = 0
        if matched is not None:
            c.firstPt, c.secondPt = matched
        else:
            c.x, c.y = x, y
        if transform is not None:
            c.transform = transform
        glyph.components.append(c)
    return glyph


def build(path, cmap, extra_glyphs, full_name):
    order = [".notdef", "space", "curves", "box", "moved", "scaled", "skewed", "matched"] + [g for g, _ in extra_glyphs]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    glyphs = {
        ".notdef": Glyph(),
        "space": Glyph(),
        "curves": contour_glyph(),
        "box": box_glyph(),
        "moved": composite([("box", 120, -40, None, None)]),
        "scaled": composite([("box", 10, 20, [[0.5, 0], [0, 0.75]], None)]),
        "skewed": composite([("box", 0, 0, [[1, 0.25], [-0.5, 1]], None)]),
        "matched": composite([("box", 0, 0, None, None), ("box", 0, 0, None, (2, 0))]),
    }
    for name, glyph in extra_glyphs:
        glyphs[name] = glyph
    fb.setupGlyf(glyphs)
    metrics = {}
    glyf = fb.font["glyf"]
    for name in order:
        g = glyf[name]
        metrics[name] = (700 + 10 * len(metrics), getattr(g, "xMin", 0))
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=820, descent=-230)
    fb.setupNameTable({"familyName": "Curves", "styleName": "Regular", "fullName": full_name})
    fb.setupOS2()
    fb.setupPost(underlinePosition=-120, underlineThickness=55)
    fb.save(path)


build(
    "curves.ttf",
    {0x20: "space", 0x41: "curves", 0x61: "curves", 0x42: "box", 0x43: "moved", 0x44: "scaled",
     0x45: "skewed", 0x46: "matched", 0x35: "box"},
    [],
    "Curves Regular",
)
build(
    "astral.ttf",
    {0x41: "curves", 0x1F600: "moved"},
    [],
    "Astral " + chr(0xE9) + "t" + chr(0xE9),
)


def simple(points, ends):
    """A glyph from points and contour ends, each point (x, y, on)."""
    from fontTools.ttLib.tables._g_l_y_f import GlyphCoordinates
    from fontTools.ttLib.tables import ttProgram

    glyph = Glyph()
    glyph.numberOfContours = len(ends)
    glyph.coordinates = GlyphCoordinates([(x, y) for x, y, _ in points])
    glyph.flags = bytearray(1 if on else 0 for _, _, on in points)
    glyph.endPtsOfContours = ends
    glyph.program = ttProgram.Program()
    glyph.program.fromBytecode(b"")
    return glyph


def ring():
    """Three hundred points on one contour, so the flags repeat."""
    import math

    points = []
    for k in range(300):
        a = 2 * math.pi * k / 300
        points.append((round(500 + 400 * math.cos(a)), round(500 + 400 * math.sin(a)), True))
    return simple(points, [299])


def build_edges(path, full_names, unicode_only, same_advance, far_match=(280, 0), cmap_extra=None, cmap_tables=None):
    """A font of word offsets, a uniform scale, points matched past 255, a
    component with no outline, nested composites, a contour that ends off
    the curve, a single point, shuffled codes for a format 4 range offset,
    and the full names given."""
    order = [".notdef", "space", "box", "ring", "wide", "half", "far", "hollow", "nest", "open", "dot"]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    shuffled = ["half", "box", "open", "wide", "dot", "ring", "far", "hollow", "nest", "box", "half", ".notdef", "open"]
    cmap = {0x20: "space"}
    for k, name in enumerate(shuffled):
        cmap[0x61 + k] = name
    cmap.update(cmap_extra or {})
    fb.setupCharacterMap(cmap)
    glyphs = {
        ".notdef": Glyph(),
        "space": Glyph(),
        "box": box_glyph(),
        "ring": ring(),
        "wide": composite([("box", 300, -200, None, None)]),
        "half": composite([("box", 0, 0, [[0.5, 0], [0, 0.5]], None)]),
        "far": composite([("ring", 0, 0, None, None), ("box", 0, 0, None, far_match)]),
        "hollow": composite([("space", 0, 0, None, None), ("box", 10, 10, None, None)]),
        "nest": composite([("half", 5, 5, None, None), ("wide", 0, 0, None, None)]),
        "open": simple([(0, 0, True), (100, 200, False), (200, 0, True), (100, -100, False)], [3]),
        "dot": simple([(50, 50, True)], [0]),
    }
    fb.setupGlyf(glyphs)
    metrics = {}
    glyf = fb.font["glyf"]
    for name in order:
        g = glyf[name]
        advance = 600 if same_advance and len(metrics) > 4 else 700 + 10 * len(metrics)
        metrics[name] = (advance, getattr(g, "xMin", 0))
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=820, descent=-230)
    fb.setupNameTable({"familyName": "Edges", "styleName": "Regular"})
    names = fb.font["name"]
    for platform, encoding, language, text in full_names:
        from fontTools.ttLib.tables._n_a_m_e import NameRecord

        record = NameRecord()
        record.nameID = 4
        record.platformID = platform
        record.platEncID = encoding
        record.langID = language
        record.string = text
        names.names.append(record)
    fb.setupOS2()
    fb.setupPost()
    if unicode_only:
        fb.font["cmap"].tables = [t for t in fb.font["cmap"].tables if t.platformID == 0]
        from fontTools.ttLib.tables._c_m_a_p import CmapSubtable

        mac = CmapSubtable.newSubtable(0)
        mac.platformID, mac.platEncID, mac.language = 1, 0, 0
        mac.cmap = {0x61: "box"}
        fb.font["cmap"].tables.append(mac)
    if cmap_tables is not None:
        fb.font["cmap"].tables = cmap_tables(fb.font["cmap"].tables)
    fb.save(path)


# A Windows full name with a pair of surrogates, a lone one and a letter;
# one in French and a Macintosh one in another encoding, both skipped.
build_edges(
    "edges.ttf",
    [
        (3, 1, 0x409, b"\xd8\x3d\xde\x00\xd8\x00\x00A\xfb\x01"),
        (3, 1, 0x40C, "Bords".encode("utf_16_be")),
        (1, 1, 0, b"Edges"),
        (1, 0, 1, b"Kanten"),
    ],
    False,
    False,
)
# No full name but an empty one, a Unicode cmap behind a Macintosh one,
# and advances that repeat, so hmtx holds fewer metrics than glyphs.
build_edges("bare.ttf", [(3, 1, 0x409, b"")], True, True)


def patched(source, path, edit):
    """Write a copy of a font with its bytes changed by `edit`."""
    from fontTools.ttLib import TTFont

    data = bytearray(open(source, "rb").read())
    font = TTFont(source)
    edit(data, font)
    open(path, "wb").write(bytes(data))


def glyph_at(font, name):
    """Return where a glyph's data starts in the file."""
    order = font.getGlyphOrder()
    return font.reader.tables["glyf"].offset + font["loca"][order.index(name)]


def component_index(glyph, value):
    """Point the first component of a composite glyph at another glyph."""

    def edit(data, font):
        at = glyph_at(font, glyph) + 10 + 2
        data[at : at + 2] = value.to_bytes(2, "big")

    return edit


def rename_table(old, new):
    def edit(data, font):
        at = data.index(old.encode(), 12)
        data[at : at + 4] = new.encode()

    return edit


def bad_flags(data, font):
    # The box's first flag repeats five times, past its four points.
    at = glyph_at(font, "box") + 10 + 2 + 2
    data[at] |= 8
    data[at + 1] = 5


def far_match(data, font):
    # The second part of `far` matches point 400, past the ring's 300.
    at = glyph_at(font, "far") + 10
    first = 8 if data[at + 1] & 1 else 6
    at += first + 4
    data[at : at + 2] = (400).to_bytes(2, "big")


def far_second(data, font):
    # The second part of `far` matches its own point 9, past the box's 4.
    at = glyph_at(font, "far") + 10
    first = 8 if data[at + 1] & 1 else 6
    at += first + 4 + 2
    data[at : at + 2] = (9).to_bytes(2, "big")


def zero_contours(data, font):
    # The dot keeps its box but says it has no contours.
    at = glyph_at(font, "dot")
    data[at : at + 2] = (0).to_bytes(2, "big")


def true_signature(data, font):
    data[0:4] = b"true"


def few_glyphs(data, font):
    at = font.reader.tables["maxp"].offset + 4
    data[at : at + 2] = (3).to_bytes(2, "big")


def otto(data, font):
    data[0:4] = b"OTTO"


def short(data, font):
    del data[200:]


def mac_only(tables):
    from fontTools.ttLib.tables._c_m_a_p import CmapSubtable

    mac = CmapSubtable.newSubtable(0)
    mac.platformID, mac.platEncID, mac.language = 1, 0, 0
    mac.cmap = {0x61: "box"}
    return [mac]


def format_6(tables):
    from fontTools.ttLib.tables._c_m_a_p import CmapSubtable

    six = CmapSubtable.newSubtable(6)
    six.platformID, six.platEncID, six.language = 3, 1, 0
    six.cmap = {0x61: "box", 0x62: "ring"}
    return [six]


# Fonts three.js refuses, for the tests of what the reader refuses.
patched("edges.ttf", "broken/matched.ttf", far_match)
build_edges("broken/surrogate.ttf", [], False, False, cmap_extra={0xD800: "box"})
build_edges("broken/mac_cmap.ttf", [], False, False, cmap_tables=mac_only)
build_edges("broken/format_6.ttf", [], False, False, cmap_tables=format_6)
patched("edges.ttf", "broken/far_component.ttf", component_index("wide", 999))
patched("edges.ttf", "broken/loop.ttf", component_index("wide", 4))
patched("edges.ttf", "broken/flags.ttf", bad_flags)
patched("edges.ttf", "broken/few_glyphs.ttf", few_glyphs)
patched("edges.ttf", "broken/otto.ttf", otto)
patched("edges.ttf", "broken/short.ttf", short)
patched("edges.ttf", "broken/no_post.ttf", rename_table("post", "posx"))
patched("edges.ttf", "broken/no_glyf.ttf", rename_table("glyf", "glyx"))
patched("edges.ttf", "broken/no_loca.ttf", rename_table("loca", "locx"))
patched("edges.ttf", "broken/matched_second.ttf", far_second)
# Valid, and read against three.js: a glyph with a box but no contours,
# and Apple's `true` signature.
patched("edges.ttf", "zero.ttf", zero_contours)
patched("edges.ttf", "true.ttf", true_signature)
print("ok")
