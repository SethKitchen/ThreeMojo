# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the LightWave objects the tests read, by hand, from the LWO2
layout and from what three.js's LWO3 parser reads.

Run it from the repository root: `mojo run -I . tools/make_lwo.mojo`.
It writes into `assets/lwo/`.
"""

from std.memory import bitcast
from std.os import makedirs
from std.os.path import dirname
from std.pathlib import Path


# Big-endian packing, as Python's `struct.pack` writes it.


def _be(value: UInt64, size: Int) -> List[UInt8]:
    """Return an unsigned integer as big-endian bytes.

    Args:
        value: The integer.
        size: The number of bytes.

    Returns:
        The low `size` bytes of the integer, high byte first.
    """
    var out = List[UInt8](capacity=size)
    for i in range(size):
        out.append(UInt8((value >> UInt64(8 * (size - 1 - i))) & 0xFF))
    return out^


def _u16(value: Int) -> List[UInt8]:
    """Return `struct.pack(">H", value)`.

    Args:
        value: The integer.

    Returns:
        Two bytes.
    """
    return _be(UInt64(value), 2)


def _u32(value: Int) -> List[UInt8]:
    """Return `struct.pack(">I", value)`, or `">i"` for a negative value.

    Args:
        value: The integer.

    Returns:
        Four bytes.
    """
    return _be(UInt64(UInt32(value & 0xFFFFFFFF)), 4)


def _floats(*v: Float64) -> List[UInt8]:
    """Return `struct.pack(">%df", *v)`: each value rounded to a float32.

    Args:
        v: The values.

    Returns:
        Four bytes for each value.
    """
    var out = List[UInt8]()
    for x in v:
        out += _be(UInt64(bitcast[DType.uint32](Float32(x))), 4)
    return out^


def _doubles(v: List[Float64]) -> List[UInt8]:
    """Return `struct.pack(">%dd", *v)`.

    Args:
        v: The values.

    Returns:
        Eight bytes for each value.
    """
    var out = List[UInt8]()
    for x in v:
        out += _be(bitcast[DType.uint64](x), 8)
    return out^


def _ascii(s: String) -> List[UInt8]:
    """Return the bytes of a string, with no end.

    Args:
        s: The string.

    Returns:
        Its UTF-8 bytes.
    """
    return List[UInt8](s.as_bytes())


def _raw(v: List[Int]) -> List[UInt8]:
    """Return bytes from integers.

    Args:
        v: The integers, each 0 to 255.

    Returns:
        The bytes.
    """
    var out = List[UInt8](capacity=len(v))
    for x in v:
        out.append(UInt8(x))
    return out^


def _zeros(n: Int) -> List[UInt8]:
    """Return zero bytes.

    Args:
        n: The number of bytes.

    Returns:
        `n` zero bytes.
    """
    return List[UInt8](length=n, fill=0)


# The chunks.


def chunk(tag: String, data: List[UInt8], short: Bool = False) -> List[UInt8]:
    """Return a chunk: a tag, a length, the data, and a pad byte to even.

    Args:
        tag: The four-letter tag.
        data: The data.
        short: Whether the length has two bytes, not four.

    Returns:
        The chunk.
    """
    var out = _ascii(tag)
    out += _u16(len(data)) if short else _u32(len(data))
    out += data.copy()
    if len(data) % 2:
        out.append(0)
    return out^


def text(s: String) -> List[UInt8]:
    """Return a string, zero-ended and padded to an even length.

    Args:
        s: The string.

    Returns:
        The bytes.
    """
    var out = _ascii(s)
    out.append(0)
    if len(out) % 2:
        out.append(0)
    return out^


def vx(i: Int) -> List[UInt8]:
    """Return a variable-length index.

    Args:
        i: The index.

    Returns:
        Two bytes below 0xFF00, else four bytes that start with 0xFF.
    """
    return _u16(i) if i < 0xFF00 else _u32(0xFF000000 | i)


def form(kind: String, body: List[UInt8]) -> List[UInt8]:
    """Return a `FORM`: a length, a kind and a body.

    Args:
        kind: The four-letter kind.
        body: The body.

    Returns:
        The form.
    """
    return _ascii("FORM") + _u32(len(body) + 4) + _ascii(kind) + body.copy()


def polygons(kind: String, polys: List[List[Int]]) -> List[UInt8]:
    """Return a `POLS` chunk.

    Args:
        kind: The polygon kind.
        polys: The point indexes of each polygon.

    Returns:
        The chunk.
    """
    var data = _ascii(kind)
    for p in polys:
        data += _u16(len(p))
        for i in p:
            data += vx(i)
    return chunk("POLS", data)


def tags(kind: String, pairs: List[Tuple[Int, Int]]) -> List[UInt8]:
    """Return a `PTAG` chunk.

    Args:
        kind: The tag kind.
        pairs: The polygon and the tag of each pair.

    Returns:
        The chunk.
    """
    var data = _ascii(kind)
    for pair in pairs:
        data += vx(pair[0]) + _u16(pair[1])
    return chunk("PTAG", data)


def vmap(
    kind: String,
    dim: Int,
    name: String,
    entries: List[List[Float64]],
    discontinuous: Bool = False,
) -> List[UInt8]:
    """Return a `VMAP` chunk, or a `VMAD` chunk.

    Args:
        kind: The map kind.
        dim: The number of values for each point.
        name: The map name.
        entries: A point index, a polygon index if discontinuous, and the
            values.
        discontinuous: Whether the map is a `VMAD`.

    Returns:
        The chunk.
    """
    var data = _ascii(kind) + _u16(dim) + text(name)
    for e in entries:
        data += vx(Int(e[0]))
        var first = 1
        if discontinuous:
            data += vx(Int(e[1]))
            first = 2
        for k in range(first, len(e)):
            data += _floats(e[k])
    return chunk("VMAD" if discontinuous else "VMAP", data)


def surface2(name: String, parts: List[List[UInt8]]) -> List[UInt8]:
    """An LWO2 surface: a name, an empty source, and short sub-chunks.

    Args:
        name: The surface name.
        parts: The sub-chunks.

    Returns:
        The `SURF` chunk.
    """
    var data = text(name) + text("")
    for part in parts:
        data += part.copy()
    return chunk("SURF", data)


def sub(tag: String, data: List[UInt8]) -> List[UInt8]:
    """Return a sub-chunk, with a two-byte length.

    Args:
        tag: The four-letter tag.
        data: The data.

    Returns:
        The sub-chunk.
    """
    return chunk(tag, data, short=True)


def lwo2_scene() -> List[UInt8]:
    """Return `scene.lwo`.

    Returns:
        The file.
    """
    var body = chunk("TAGS", text("Red") + text("Blue") + text("Green"))
    # A base layer with a pivot: a triangle, a quad and a pentagon.
    body += chunk("LAYR", _u16(0) + _u16(0) + _floats(0.5, 0, 0) + text("Base"))
    body += chunk(
        "PNTS",
        _floats(
            0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0,
            2, 0, 0, 3, 0, 1, 3, 1, 1, 2.5, 2, 0.5, 2, 1, 0,
        ),
    )  # fmt: skip
    body += vmap(
        "TXUV",
        2,
        "UVMap",
        [[0, 0, 0], [1, 1, 0], [2, 1, 1], [3, 0, 1], [5, 0.25, 0.75]],
    )
    body += vmap("TXUV", 2, "Second", [[4, 0.5, 0.5]])
    body += vmap("TXUV", 2, "Seams", [[0, 1, 0.5, 0.5]], discontinuous=True)
    body += vmap("MORF", 3, "Grow", [[1, 0.5, 0, 0], [2, 0.5, 0.5, 0.25]])
    body += vmap("SPOT", 3, "Moved", [[0, -1, -1, -1]])
    body += vmap("WGHT", 1, "Weights", [[0, 1.0]])
    body += polygons(
        "FACE", [[0, 1, 2], [0, 2, 3], [0, 3, 2, 1], [4, 5, 6, 7, 8]]
    )
    body += tags("SURF", [(0, 0), (1, 0), (2, 1), (3, 0)])
    body += tags("PART", [(0, 0)])
    # A child layer of lines with no name, under the base.
    body += chunk(
        "LAYR", _u16(1) + _u16(0) + _floats(0, 1, 0) + text("") + _u16(0)
    )
    body += chunk("PNTS", _floats(0, 0, 0, 1, 1, 1, 2, 0, 1))
    body += polygons("FACE", [[0, 1], [1, 2]])
    body += tags("SURF", [(0, 2), (1, 2)])
    # A layer of points.
    body += chunk("LAYR", _u16(2) + _u16(1) + _floats(0, 0, 0) + text("Dots"))
    body += chunk("PNTS", _floats(0, 0, 0, 0, 2, 0))
    body += polygons("FACE", [[0], [1]])
    body += tags("SURF", [(0, 1), (1, 1)])
    body += chunk("CLIP", _u32(1) + sub("STIL", text("images/wood.png")))
    body += surface2(
        "Red",
        [
            sub("COLR", _floats(0.8, 0.2, 0.1) + vx(0)),
            sub("DIFF", _floats(0.9) + vx(0)),
            sub("LUMI", _floats(0.25) + vx(0)),
            sub("SPEC", _floats(0.4) + vx(0)),
            sub("GLOS", _floats(0.5) + vx(0)),
            sub("REFL", _floats(0.3) + vx(0)),
            sub("SIDE", _u16(3)),
            sub("SMAN", _floats(1.2)),
            sub("TRAN", _floats(0.5) + vx(0)),
            sub("BUMP", _floats(1.0) + vx(0)),
            sub("RIND", _floats(1.5) + vx(0)),
        ],
    )
    body += surface2(
        "Blue",
        [
            sub("COLR", _floats(0.1, 0.2, 0.9) + vx(0)),
            sub("SPEC", _floats(0.5) + vx(0)),
            sub("SMAN", _floats(-1)),
            sub("SIDE", _u16(2)),
        ],
    )
    body += surface2(
        "Green",
        [
            sub("COLR", _floats(0.2, 0.9, 0.3) + vx(0)),
            sub("GLOS", _floats(0.5) + vx(0)),
        ],
    )
    return form("LWO2", body)


def big(tag: String, data: List[UInt8]) -> List[UInt8]:
    """An LWO3 chunk: a tag and a four-byte length.

    Args:
        tag: The four-letter tag.
        data: The data.

    Returns:
        The chunk.
    """
    return chunk(tag, data)


def value(kind: String, *numbers: Float64) -> List[UInt8]:
    """An LWO3 `VALU` form, as three.js's `parseValueForm` reads it.

    Args:
        kind: The value kind.
        numbers: The values.

    Returns:
        The form.
    """
    var data = _zeros(8) + text(kind)
    if kind == "vparam" or kind == "vparam3":
        var values = List[Float64]()
        for x in numbers:
            values.append(x)
        data += _zeros(24) + _doubles(values)
    elif kind == "int":
        data += _u32(Int(numbers[0]))
    else:
        data += _u32(Int(numbers[0])) + _u32(0)
    return form("VALU", data)


def entry(name: String, body: List[UInt8]) -> List[UInt8]:
    """An `ENTR` form: a node attribute, named, holding a value.

    Args:
        name: The attribute name.
        body: The value and its maps.

    Returns:
        The form.
    """
    return form(
        "ENTR",
        _ascii("NAME") + _u32(len(text(name))) + text(name) + body.copy(),
    )


def node(real: String, reference: String, body: List[UInt8]) -> List[UInt8]:
    """An `NTAG` form: a node with a real name and a reference name.

    Args:
        real: The real name.
        reference: The reference name.
        body: The node's chunks and forms.

    Returns:
        The form.
    """
    var head = _ascii("NRNM") + _u32(len(text(real))) + text(real)
    return form("NTAG", head + big("NNME", text(reference)) + body.copy())


def connection(
    node_name: String, input_name: String, input_node: String
) -> List[UInt8]:
    """Return a node connection: a node, its input, and the input's node.

    Args:
        node_name: The node.
        input_name: The input.
        input_node: The node that feeds the input.

    Returns:
        The `INME`, `IINM` and `IINN` chunks.
    """
    return (
        big("INME", text(node_name))
        + big("IINM", text(input_name))
        + big("IINN", text(input_node))
    )


def lwo3_scene(material: List[UInt8]) -> List[UInt8]:
    """Return an LWO3 quad with one surface.

    Args:
        material: The surface's chunks and forms.

    Returns:
        The file.
    """
    var body = big("TAGS", text("Shiny"))
    body += big("LAYR", _u16(0) + _u16(0) + _floats(0, 0, 0) + text("Only"))
    body += big("PNTS", _floats(0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0))
    body += vmap("TXUV", 2, "UV", [[0, 0, 0], [1, 1, 0], [2, 1, 1], [3, 0, 1]])
    body += polygons("FACE", [[0, 1, 2, 3]])
    body += big("PTAG", _ascii("SURF") + vx(0) + _u16(0))
    # A clip of index 2, three.js's texture for an image map.
    body += form(
        "CLIP",
        _zeros(8) + _u32(2) + form("STIL", _zeros(8) + text("images/clip.png")),
    )
    body += form("SURF", _zeros(8) + text("Shiny") + text("") + material.copy())
    return form("LWO3", body)


def lwo3_standard() -> List[UInt8]:
    """A standard surface: color, roughness, metal and luminous, a color
    and a normal image node, an image map on its specular, and an
    environment file.

    Returns:
        The file.
    """
    var image = node(
        "Image",
        "Image1",
        big("FNAM", text("images/color.png"))
        + big("IUTL", _u32(1))
        + big("IVTL", _u32(2)),
    )
    var bumpy = node(
        "Image",
        "Image2",
        big("FNAM", text("images/normal.png"))
        + form("IBMP", _zeros(48) + _floats(0.5) + _zeros(2)),
    )
    var attributes = (
        entry("Color", value("vparam3", 0.6, 0.4, 0.2))
        + entry("Roughness", value("vparam", 0.35))
        + entry("Metallic", value("vparam", 0.8))
        + entry("Luminous", value("vparam", 0.5))
        + entry("Luminous Color", value("vparam3", 1, 0.5, 0))
        + entry("Transparency", value("vparam", 0.25))
        + entry("Bump Height", value("vparam", 2))
        + entry("Clearcoat", value("vparam", 0))
        + entry("Luminosity", value("vparam", 0.4))
        + entry(
            "Specular",
            value("vparam", 0.5)
            + form(
                "IMAP",
                _zeros(10)
                + big("IMAG", vx(2))
                + big("WRAP", _u16(2) + _u16(3)),
            ),
        )
    )
    var standard = node(
        "Standard",
        "Standard1",
        big("FNAM", text("images/env.hdr")) + form("SATR", attributes),
    )
    var material = big("SIDE", _u16(3)) + big("SMAN", _floats(1))
    material += form(
        "NODS", form("NNDS", image + bumpy.copy() + standard.copy())
    )
    material += form(
        "NCON",
        connection("Surface", "Material", "Standard1")
        + connection("Standard1", "Color", "Image1")
        + connection("Standard1", "Normal", "Image2"),
    )
    return lwo3_scene(material)


def lwo3_phong() -> List[UInt8]:
    """A Phong surface: diffuse, luminosity, reflection, refraction,
    specular with a color highlight and glossiness, an image map on its
    color and one that names no clip, and luminous and alpha nodes.

    Returns:
        The file.
    """
    var glow = node("Image", "Glow", big("FNAM", text("images/glow.png")))
    var alpha = node("Image", "Cut", big("FNAM", text("images/cut.png")))
    var attributes = (
        entry(
            "Color",
            value("vparam3", 0.5, 0.25, 1)
            + form("IMAP", _zeros(10) + big("IMAG", vx(2))),
        )
        + entry("Diffuse", value("vparam", 0.8))
        + entry("Transparency", value("vparam", 0))
        + entry("Luminosity", value("vparam", 0.3))
        + entry("Reflection", value("vparam", 0.2))
        + entry("Refraction Index", value("vparam", 1.4))
        + entry("Specular", value("vparam", 0.6))
        + entry("Color Highlight", value("vparam", 0.5))
        + entry("Glossiness", value("vparam", 0.25))
        + entry("Kept", value("vparam", 1) + big("maps", text("m")))
        + entry(
            "Diffuse Sharpness",
            value("int", 3) + form("IMAP", _zeros(10) + big("IMAG", vx(9))),
        )
    )
    var phong = node("Phong", "Phong1", form("ATTR", attributes))
    var material = big("SIDE", _u16(1))
    material += form("NODS", form("NNDS", glow + alpha.copy() + phong.copy()))
    material += form(
        "NCON",
        connection("Surface", "Material", "Phong1")
        + connection("Phong1", "Luminous", "Glow")
        + connection("Phong1", "Alpha", "Cut"),
    )
    return lwo3_scene(material)


def lwo3_physical() -> List[UInt8]:
    """A physical surface: clearcoat and its gloss, with roughness and
    specular maps, of which three.js keeps the roughness.

    Returns:
        The file.
    """
    var rough = node("Image", "Rough", big("FNAM", text("images/rough.png")))
    var shine = node("Image", "Shine", big("FNAM", text("images/shine.png")))
    var metal = node("Image", "Metal", big("FNAM", text("images/metal.png")))
    var attributes = (
        entry("Clearcoat", value("vparam", 0.7))
        + entry("Clearcoat Gloss", value("vparam", 0.4))
        + entry("Roughness", value("vparam", 0.3))
        + entry("Metallic", value("vparam", 0.1))
        + entry("Reflection", value("vparam", 0.5))
        + entry("Luminous", value("vparam", 1))
    )
    var physical = node(
        "Principled",
        "Principled1",
        big("FNAM", text("images/sky.hdr")) + form("ATTR", attributes),
    )
    var material = form(
        "NODS",
        form("NNDS", rough + shine.copy() + metal.copy() + physical.copy()),
    )
    material += form(
        "NCON",
        connection("Surface", "Material", "Principled1")
        + connection("Principled1", "Roughness", "Rough")
        + connection("Principled1", "Specular", "Shine")
        + connection("Principled1", "Metallic", "Metal")
        + connection("Principled1", "Luminous Color", "Metal"),
    )
    return lwo3_scene(material)


def lwo2_kitchen() -> List[UInt8]:
    """Every LWO2 chunk three.js reads, skips or keeps as text, written where
    three.js reads it without throwing.

    Returns:
        The file.
    """
    var body = chunk(
        "TAGS", text("Red") + _zeros(1) + text("Gone") + _ascii("Blues")
    )
    body += chunk("ICON", _ascii("abcd"))
    body += chunk("AUVO", _zeros(2))
    body += chunk("OTAG", _ascii("LINK") + text("one"))
    body += chunk("OTAG", _ascii("LINK") + text("two"))
    body += chunk("AUVU", _zeros(3))
    body += chunk("DESC", text("A kitchen"))
    for tag in ["TEXT", "CMNT", "NCOM"]:
        body += chunk(tag, text("said"))
    body += chunk("NAME", text("channel"))
    body += chunk("OREF", text("other.lwo"))
    body += chunk("ROID", _u32(7))
    body += chunk("NSTA", _u16(1))
    body += chunk("NRNM", text("real"))
    for tag in ["INME", "IINN", "IINM", "IONM"]:
        body += chunk(tag, text("x"))
    body += chunk("CHAN", _ascii("COLR"))
    body += chunk("CHAN", _ascii("COLR") + _zeros(2))
    body += chunk("IMAG", _raw([0xFF, 0x01, 0x00, 0x02]))
    body += chunk("WRAP", _u16(1) + _u16(2))
    # U+00E9, U+20AC and U+1F600 in UTF-8, then bytes that are not UTF-8.
    body += chunk(
        "ZZZZ",
        _raw([0xC3, 0xA9, 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80])
        + _raw([0x80, 0xC0, 0x80, 0xE2, 0x82, 0xED, 0xA0, 0x80, 0xF5, 0xE2])
        + _ascii("ABc"),
    )
    body += chunk("QQQQ", List[UInt8]())
    # A skipped form, and a clip form that reads the next tag as its kind,
    # four bytes past its end.
    body += form("ISEQ", _zeros(6))
    body += form("CLIP", _ascii("ENVL") + _zeros(4)) + _zeros(4)
    body += chunk("LAYR", _u16(0) + _u16(0) + _floats(0, 0, 0) + text("Main"))
    body += chunk("PNTS", _floats(0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0))
    body += vmap("TXUV", 2, "UV", [[0, 0, 0], [2, 1, 1]])
    body += chunk("VMAP", text("OnlyAName"))
    body += vmap("ABCD", 1, "Unknown", [[0, 1.0]])
    body += vmap("MORF", 3, "Far", [[9, 1, 1, 1], [1, 0, 1, 0]])
    body += polygons(
        "FACE",
        [
            [0, 1, 2],
            List[Int](),
            [0, 2, 3],
            [0, 1, 3],
            [1, 2, 3],
            [0, 1, 2],
            [0, 2, 3],
        ],
    )
    var ptag = (
        _ascii("SURF")
        + vx(0)
        + _u16(0)
        + _raw([0xFF, 0x00, 0x00, 0x01])
        + _u16(0)
    )
    for pair in [(2, 1), (3, 0), (4, 2), (5, 1), (6, 0)]:
        ptag += vx(pair[0]) + _u16(pair[1])
    body += chunk("PTAG", ptag)
    # A layer of points and no polygons, whose mesh is empty.
    body += chunk("LAYR", _u16(1) + _u16(0) + _floats(0, 0, 0) + text("Empty"))
    body += chunk("PNTS", _floats(0, 0, 0))
    body += polygons("FACE", List[List[Int]]())
    body += chunk("CLIP", _u32(1) + _ascii("ISEQ") + _u16(100))
    body += chunk(
        "CLIP",
        _u32(2)
        + _ascii("ISEQ")
        + _u16(2)
        + _ascii("STIL")
        + _u16(6)
        + text("x.png"),
    )
    body += surface2(
        "Red",
        [
            sub("COLR", _floats(1, 0, 0) + vx(0)),
            sub("RIMG", vx(1)),
            sub("TIMG", vx(1)),
            sub("SSHN", text("shader")),
            sub("AOVN", text("aov")),
            sub("IMAP", _raw([0x80, 0x00])),
            sub("BLOK", List[UInt8]()),
        ],
    )
    # Chunks that write nothing, past the surface's end, and then a second
    # surface, which the first surface's end handed back to the materials.
    body += chunk("ICON", _zeros(40))
    body += surface2("Blues", [sub("COLR", _floats(0, 0, 1) + vx(0))])
    return form("LWO2", body)


def _clip(index: Int, name: String) -> List[UInt8]:
    """Return an LWO3 `CLIP` form of a still image.

    Args:
        index: The clip index.
        name: The image file.

    Returns:
        The form.
    """
    return form(
        "CLIP", _zeros(8) + _u32(index) + form("STIL", _zeros(8) + text(name))
    )


def _image_map(index: Int) -> List[UInt8]:
    """Return an `IMAP` form that names a clip.

    Args:
        index: The clip index.

    Returns:
        The form.
    """
    return form("IMAP", _zeros(10) + big("IMAG", vx(index)))


def _image_map(index: Int, wrap: Tuple[Int, Int]) -> List[UInt8]:
    """Return an `IMAP` form that names a clip and its wrap modes.

    Args:
        index: The clip index.
        wrap: The wrap modes in U and V.

    Returns:
        The form.
    """
    return form(
        "IMAP",
        _zeros(10)
        + big("IMAG", vx(index))
        + big("WRAP", _u16(wrap[0]) + _u16(wrap[1])),
    )


def lwo3_kitchen() -> List[UInt8]:
    """Every LWO3 form three.js reads, and a surface of every attribute and
    map name three.js looks for.

    Returns:
        The file.
    """
    var node_extras = (
        big("IPIX", _u32(-3))
        + big("IMIP", _zeros(2))
        + big("IUVI", List[UInt8]())
        + big("IUVI", _ascii("UVMap") + _zeros(1))
        + big("CHAN", _ascii("COLR"))
        + form("ISCL", _zeros(48) + _floats(1, 2, 3) + _zeros(2))
        + form("IPOS", _zeros(48) + _floats(1, 2, 3) + _zeros(2))
        + form("IROT", _zeros(48) + _floats(1, 2, 3) + _zeros(2))
        + form("IFAL", _zeros(48) + _floats(1, 2, 3) + _zeros(2))
        + form("IUTD", _zeros(48) + _floats(2) + _zeros(2))
        + form("IVTD", _zeros(48) + _floats(3) + _zeros(2))
        + form("CLIP", _ascii("FORM") + _zeros(16) + text("images/inner.png"))
        + form("XREF", _zeros(8) + _u32(4) + text("ref"))
        + form("IMST", _zeros(8) + _floats(0.5))
        + form("ISEQ", _zeros(4))
        + form("META", List[UInt8]())
        + form("ENVL", _zeros(4))
        + form("QQQQ", _zeros(4))
    )
    var alpha = node(
        "Image", "Cut", big("FNAM", text("images/cut.png")) + node_extras.copy()
    )
    var bumpy = node("Image", "Bumpy", big("FNAM", text("images/bump.png")))
    var plain_normal = node(
        "Image", "Flat", big("FNAM", text("images/flat.png"))
    )
    var extra = node("Image", "Extra", big("FNAM", text("images/extra.png")))
    var rough = node("Image", "Rough", big("FNAM", text("images/rough.png")))
    # A node with no attributes form: its entry lands on the node itself.
    var bare = node("Bare", "Bare1", entry("Loose", value("double", 5)))
    var attributes = (
        big("ZZZZ", text("kept"))
        + entry("Color", value("vparam3", 0.3, 0.6, 0.9))
        + entry("Color", value("vparam3", 0.4, 0.6, 0.9))
        + entry("Transparency", value("vparam", 0.5) + _image_map(3))
        + entry("Clearcoat", value("vparam", 0.5))
        + entry("Roughness", value("vparam", 0.4) + _image_map(3))
        + entry("Luminous", value("vparam", 2))
        + entry("Luminous Color", value("vparam3", 1, 1, 0))
        + entry("Luminosity", value("vparam", 0.5) + _image_map(6))
        + entry("Diffuse", value("vparam", 0.7) + _image_map(3))
        + entry("Specular", value("vparam", 0.2) + _image_map(3, (0, 1)))
        + entry("Metallic", value("vparam", 0.3) + _image_map(6))
        + entry("Alpha", value("vparam", 1) + _image_map(3))
        + entry("Normal", value("vparam", 1) + _image_map(3))
        + entry("Bump", value("vparam", 1) + _image_map(3))
        + entry("Glossiness", value("vparam", 0.5) + _image_map(3))
        + entry("Flag", value("bool", 1))
        + entry(
            "Diffuse Sharpness", value("vparam", 0.5) + form("IMAP", _zeros(10))
        )
    )
    var standard = node(
        "Standard",
        "Standard1",
        big("FNAM", text("images/env.hdr")) + form("SATR", attributes),
    )
    var material = (
        big("SIDE", _u16(5))
        + big("IMAP", _u32(9))
        + big("SURF", _ascii("odd") + _zeros(1))
    )
    material += form(
        "SSHA", big("SSHN", text("s")) + form("SSHD", List[UInt8]())
    )
    material += form(
        "TMAP",
        form("CNTR", _zeros(8) + _floats(1, 2, 3))
        + form("SIZE", _zeros(8) + _floats(1, 1, 1))
        + form("ROTA", _zeros(8) + _floats(0, 0, 0)),
    )
    material += form(
        "NODS",
        form(
            "NNDS",
            alpha
            + bumpy.copy()
            + plain_normal.copy()
            + extra.copy()
            + rough.copy()
            + bare.copy()
            + standard.copy(),
        ),
    )
    material += form(
        "NCON",
        connection("Surface", "Material", "Standard1")
        + connection("Standard1", "Alpha", "Cut")
        + connection("Standard1", "Transparency", "Cut")
        + connection("Standard1", "Bump", "Bumpy")
        + connection("Standard1", "Normal", "Flat")
        + connection("Standard1", "Sheen", "Extra")
        + connection("Standard1", "Roughness", "Rough")
        + connection("Standard1", "Normal", "Bumpy")
        + connection("Standard1", "Luminous Color", "Extra")
        + connection("Other", "Color", "Extra"),
    )
    var body = big("TAGS", text("Shiny") + text("Missing"))
    body += big("LAYR", _u16(0) + _u16(0) + _floats(0, 0, 0) + text("Only"))
    body += big("PNTS", _floats(0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0))
    body += polygons("FACE", [[0, 1, 2], [0, 2, 3]])
    body += big("PTAG", _ascii("SURF") + vx(0) + _u16(0) + vx(1) + _u16(1))
    body += _clip(3, "images/three.png") + _clip(6, "images/six.png")
    body += form("CLIP", _zeros(8) + _u32(5))
    body += form("SURF", _zeros(8) + text("Shiny") + text("") + material.copy())
    # A last amplitude form whose end is the file's end.
    body += form("TAMP", _zeros(8) + _floats(0.25))
    return form("LWO3", body)


# The files the reader refuses.


def _points() -> List[UInt8]:
    """Return the `PNTS` chunk of a unit square.

    Returns:
        The chunk.
    """
    return chunk("PNTS", _floats(0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0))


def _triangle() -> List[UInt8]:
    """Return the `POLS` chunk of one triangle.

    Returns:
        The chunk.
    """
    return polygons("FACE", [[0, 1, 2]])


def _surface3(material: List[UInt8]) -> List[UInt8]:
    """Return an LWO3 triangle with one surface.

    Args:
        material: The surface's chunks and forms.

    Returns:
        The file.
    """
    return form(
        "LWO3",
        big("TAGS", text("S"))
        + big("LAYR", _u16(0) + _u16(0) + _floats(0, 0, 0) + text("L"))
        + _points()
        + _triangle()
        + big("PTAG", _ascii("SURF") + vx(0) + _u16(0))
        + form("SURF", _zeros(8) + text("S") + text("") + material.copy()),
    )


def _add(
    mut result: List[Tuple[String, List[UInt8]]],
    name: String,
    data: List[UInt8],
):
    """Add a refused file and its bytes."""
    result.append((name, data.copy()))


def broken() -> List[Tuple[String, List[UInt8]]]:
    """Files the reader refuses: most of them three.js throws on, and the
    rest it reads in a way the port does not follow.

    Returns:
        The names and the bytes, in the order they are written.
    """
    var out = List[Tuple[String, List[UInt8]]]()
    var layer = chunk("TAGS", text("S")) + chunk(
        "LAYR", _u16(0) + _u16(0) + _floats(0, 0, 0) + text("L")
    )
    var points = _points()
    var tri = _triangle()
    var tag = chunk("PTAG", _ascii("SURF") + vx(0) + _u16(0))
    var surf = surface2("S", [sub("COLR", _floats(1, 1, 1) + vx(0))])
    var good = layer + points.copy() + tri.copy() + tag.copy() + surf.copy()
    _add(out, "not_form", _ascii("XXXX") + _u32(4) + _ascii("LWO2"))
    _add(out, "not_lwo", form("LWOB", good))
    var short = form("LWO2", good)
    short.resize(60, 0)
    _add(out, "short", short)
    _add(
        out,
        "empty_tags",
        form("LWO2", chunk("TAGS", List[UInt8]()) + good.copy()),
    )
    _add(
        out,
        "no_form",
        form(
            "LWO3",
            form("NTAG", _ascii("NRNM") + _u32(2) + text("n"))
            + big("ICON", _zeros(8))
            + big("DESC", text("d"))
            + good.copy(),
        ),
    )
    _add(
        out, "no_node", form("LWO2", chunk("IUVI", List[UInt8]()) + good.copy())
    )
    _add(
        out, "no_surface", form("LWO2", chunk("SMAN", _floats(1)) + good.copy())
    )
    _add(
        out,
        "open_string",
        form("LWO2", good + chunk("DESC", _ascii("no end"))),
    )
    _add(out, "no_polygons", form("LWO2", layer + points.copy() + surf.copy()))
    _add(
        out,
        "tags_first",
        form(
            "LWO2",
            layer + points.copy() + tag.copy() + tri.copy() + surf.copy(),
        ),
    )
    _add(
        out,
        "no_tags",
        form("LWO2", layer + points.copy() + tri.copy() + surf.copy()),
    )
    _add(
        out,
        "no_parent",
        form(
            "LWO2",
            chunk("TAGS", text("S"))
            + chunk(
                "LAYR",
                _u16(0) + _u16(0) + _floats(0, 0, 0) + text("L") + _u16(5),
            )
            + points.copy()
            + tri.copy()
            + tag.copy()
            + surf.copy(),
        ),
    )
    _add(
        out,
        "lines_no_surface",
        form(
            "LWO2",
            layer
            + points.copy()
            + polygons("FACE", [[0, 1]])
            + chunk("PTAG", _ascii("SURF") + vx(0) + _u16(3))
            + surf.copy(),
        ),
    )
    _add(
        out,
        "not_surface",
        form(
            "LWO2",
            good + chunk("ICON", _zeros(40)) + chunk("DESC", text("d")),
        ),
    )
    # LWO3 surfaces.
    var std = node(
        "Standard",
        "Std",
        form("SATR", entry("Roughness", value("vparam", 0.5))),
    )
    _add(out, "no_connections", _surface3(form("NODS", form("NNDS", std))))
    _add(
        out,
        "no_material_node",
        _surface3(
            form("NODS", form("NNDS", std))
            + form("NCON", connection("Surface", "Material", "Nope"))
        ),
    )
    _add(
        out,
        "no_node_names",
        _surface3(
            form("NODS", form("NNDS", std))
            + form(
                "NCON",
                big("IINM", text("Material")) + big("IINN", text("Std")),
            )
        ),
    )
    _add(
        out,
        "no_material",
        _surface3(
            form("NODS", form("NNDS", std))
            + form("NCON", connection("Surface", "Color", "Std"))
        ),
    )
    _add(
        out,
        "no_texture_node",
        _surface3(
            form("NODS", form("NNDS", std))
            + form(
                "NCON",
                connection("Surface", "Material", "Std")
                + connection("Std", "Color", "Gone"),
            )
        ),
    )
    _add(
        out,
        "no_texture_file",
        _surface3(
            form(
                "NODS", form("NNDS", std + node("Image", "Img", List[UInt8]()))
            )
            + form(
                "NCON",
                connection("Surface", "Material", "Std")
                + connection("Std", "Color", "Img"),
            )
        ),
    )
    var kept = node(
        "Standard",
        "Std",
        form(
            "SATR",
            big("ZZZZ", text("t")) + entry("ZZZZ", value("vparam", 1)),
        ),
    )
    _add(
        out,
        "entry_on_text",
        _surface3(
            form("NODS", form("NNDS", kept))
            + form("NCON", connection("Surface", "Material", "Std"))
        ),
    )
    # What three.js reads, and the port refuses.
    _add(
        out,
        "points_after",
        form(
            "LWO2",
            layer + tri.copy() + points.copy() + tag.copy() + surf.copy(),
        ),
    )
    _add(
        out,
        "few_tags",
        form(
            "LWO2",
            layer
            + points.copy()
            + polygons("FACE", [[0, 1, 2], [0, 2, 3]])
            + tag.copy()
            + surf.copy(),
        ),
    )
    _add(
        out,
        "far_point",
        form(
            "LWO2",
            layer
            + points.copy()
            + polygons("FACE", [[0, 1, 9]])
            + tag.copy()
            + surf.copy(),
        ),
    )
    _add(
        out,
        "far_uv",
        form(
            "LWO2",
            layer
            + points.copy()
            + vmap("TXUV", 2, "UV", [[9, 0, 0]])
            + tri.copy()
            + tag.copy()
            + surf.copy(),
        ),
    )
    var shapes = node(
        "Standard",
        "Std",
        form(
            "SATR",
            entry("Roughness", value("vparam", 0.5))
            + entry("Color", value("vparam", 1)),
        ),
    )
    _add(
        out,
        "color_shape",
        _surface3(
            form("NODS", form("NNDS", shapes))
            + form("NCON", connection("Surface", "Material", "Std"))
        ),
    )
    var empty = node(
        "Standard", "Std", form("SATR", entry("Roughness", List[UInt8]()))
    )
    _add(
        out,
        "no_value",
        _surface3(
            form("NODS", form("NNDS", empty))
            + form("NCON", connection("Surface", "Material", "Std"))
        ),
    )
    var scalars = node(
        "Standard",
        "Std",
        form("SATR", entry("Roughness", value("vparam3", 1, 2, 3))),
    )
    _add(
        out,
        "scalar_shape",
        _surface3(
            form("NODS", form("NNDS", scalars))
            + form("NCON", connection("Surface", "Material", "Std"))
        ),
    )
    var colorless = node(
        "Standard",
        "Std",
        form(
            "SATR",
            entry("Roughness", value("vparam", 0.5))
            + entry("Color", List[UInt8]()),
        ),
    )
    _add(
        out,
        "color_no_value",
        _surface3(
            form("NODS", form("NNDS", colorless))
            + form("NCON", connection("Surface", "Material", "Std"))
        ),
    )
    _add(
        out,
        "short_node_inputs",
        _surface3(
            form("NODS", form("NNDS", std))
            + form(
                "NCON",
                connection("Surface", "Material", "Std")
                + big("INME", text("Std"))
                + big("IINM", text("Color")),
            )
        ),
    )
    _add(
        out,
        "short_inputs",
        _surface3(
            form("NODS", form("NNDS", std))
            + form(
                "NCON",
                big("INME", text("Surface")) + big("IINM", text("Material")),
            )
        ),
    )
    var wraps = node(
        "Image",
        "Img",
        big("FNAM", text("a.png")) + big("IUTL", _u32(7)),
    )
    _add(
        out,
        "wrap7",
        _surface3(
            form("NODS", form("NNDS", std + wraps.copy()))
            + form(
                "NCON",
                connection("Surface", "Material", "Std")
                + connection("Std", "Color", "Img"),
            )
        ),
    )
    return out^


def files() -> List[Tuple[String, List[UInt8]]]:
    """Return every file and its bytes, in the order they are written.

    Returns:
        The relative paths and their bytes.
    """
    var result = List[Tuple[String, List[UInt8]]]()
    result.append(("scene.lwo", lwo2_scene()))
    result.append(("standard.lwo", lwo3_standard()))
    result.append(("phong.lwo", lwo3_phong()))
    result.append(("physical.lwo", lwo3_physical()))
    result.append(("kitchen.lwo", lwo2_kitchen()))
    result.append(("kitchen3.lwo", lwo3_kitchen()))
    for item in broken():
        result.append(("broken/" + item[0] + ".lwo", item[1].copy()))
    return result^


def write_all(root: String) raises:
    """Write every file.

    Args:
        root: The folder to write in.

    Raises:
        Error: If a file cannot be written.
    """
    for item in files():
        var target = root + "/" + item[0]
        makedirs(dirname(target), exist_ok=True)
        Path(target).write_bytes(Span(item[1]))


def main() raises:
    """Write every file into `assets/lwo/`.

    Raises:
        Error: If a file cannot be written.
    """
    write_all("assets/lwo")
