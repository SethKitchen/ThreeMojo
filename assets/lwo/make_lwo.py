# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the LightWave objects the tests read, by hand, from the LWO2
layout and from what three.js's LWO3 parser reads.

Run it in this folder: `python make_lwo.py`.
"""

import struct


def chunk(tag, data, short=False):
    """Return a chunk: a tag, a length, the data, and a pad byte to even."""
    head = tag.encode() + (struct.pack(">H", len(data)) if short else struct.pack(">I", len(data)))
    return head + data + (b"\0" if len(data) % 2 else b"")


def text(s):
    """Return a string, zero-ended and padded to an even length."""
    b = s.encode() + b"\0"
    return b + (b"\0" if len(b) % 2 else b"")


def vx(i):
    """Return a variable-length index."""
    return struct.pack(">H", i) if i < 0xFF00 else struct.pack(">I", 0xFF000000 | i)


def floats(*v):
    return struct.pack(">%df" % len(v), *v)


def form(kind, body):
    return b"FORM" + struct.pack(">I", len(body) + 4) + kind.encode() + body


def polygons(kind, polys):
    data = kind.encode()
    for p in polys:
        data += struct.pack(">H", len(p)) + b"".join(vx(i) for i in p)
    return chunk("POLS", data)


def tags(kind, pairs):
    return chunk("PTAG", kind.encode() + b"".join(vx(p) + struct.pack(">H", t) for p, t in pairs))


def vmap(kind, dim, name, entries, discontinuous=False):
    data = kind.encode() + struct.pack(">H", dim) + text(name)
    for e in entries:
        data += vx(e[0])
        if discontinuous:
            data += vx(e[1])
            data += floats(*e[2:])
        else:
            data += floats(*e[1:])
    return chunk("VMAD" if discontinuous else "VMAP", data)


def surface2(name, parts):
    """An LWO2 surface: a name, an empty source, and short sub-chunks."""
    return chunk("SURF", text(name) + text("") + b"".join(parts))


def sub(tag, data):
    return chunk(tag, data, short=True)


def lwo2_scene():
    body = chunk("TAGS", text("Red") + text("Blue") + text("Green"))
    # A base layer with a pivot: a triangle, a quad and a pentagon.
    body += chunk("LAYR", struct.pack(">HH", 0, 0) + floats(0.5, 0, 0) + text("Base"))
    points = [
        (0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0),
        (2, 0, 0), (3, 0, 1), (3, 1, 1), (2.5, 2, 0.5), (2, 1, 0),
    ]
    body += chunk("PNTS", floats(*[c for p in points for c in p]))
    body += vmap("TXUV", 2, "UVMap", [(0, 0, 0), (1, 1, 0), (2, 1, 1), (3, 0, 1), (5, 0.25, 0.75)])
    body += vmap("TXUV", 2, "Second", [(4, 0.5, 0.5)])
    body += vmap("TXUV", 2, "Seams", [(0, 1, 0.5, 0.5)], discontinuous=True)
    body += vmap("MORF", 3, "Grow", [(1, 0.5, 0, 0), (2, 0.5, 0.5, 0.25)])
    body += vmap("SPOT", 3, "Moved", [(0, -1, -1, -1)])
    body += vmap("WGHT", 1, "Weights", [(0, 1.0)])
    body += polygons("FACE", [[0, 1, 2], [0, 2, 3], [0, 3, 2, 1], [4, 5, 6, 7, 8]])
    body += tags("SURF", [(0, 0), (1, 0), (2, 1), (3, 0)])
    body += tags("PART", [(0, 0)])
    # A child layer of lines with no name, under the base.
    body += chunk("LAYR", struct.pack(">HH", 1, 0) + floats(0, 1, 0) + text("") + struct.pack(">H", 0))
    body += chunk("PNTS", floats(0, 0, 0, 1, 1, 1, 2, 0, 1))
    body += polygons("FACE", [[0, 1], [1, 2]])
    body += tags("SURF", [(0, 2), (1, 2)])
    # A layer of points.
    body += chunk("LAYR", struct.pack(">HH", 2, 1) + floats(0, 0, 0) + text("Dots"))
    body += chunk("PNTS", floats(0, 0, 0, 0, 2, 0))
    body += polygons("FACE", [[0], [1]])
    body += tags("SURF", [(0, 1), (1, 1)])
    body += chunk("CLIP", struct.pack(">I", 1) + sub("STIL", text("images/wood.png")))
    body += surface2("Red", [
        sub("COLR", floats(0.8, 0.2, 0.1) + vx(0)),
        sub("DIFF", floats(0.9) + vx(0)),
        sub("LUMI", floats(0.25) + vx(0)),
        sub("SPEC", floats(0.4) + vx(0)),
        sub("GLOS", floats(0.5) + vx(0)),
        sub("REFL", floats(0.3) + vx(0)),
        sub("SIDE", struct.pack(">H", 3)),
        sub("SMAN", floats(1.2)),
        sub("TRAN", floats(0.5) + vx(0)),
        sub("BUMP", floats(1.0) + vx(0)),
        sub("RIND", floats(1.5) + vx(0)),
    ])
    body += surface2("Blue", [
        sub("COLR", floats(0.1, 0.2, 0.9) + vx(0)),
        sub("SPEC", floats(0.5) + vx(0)),
        sub("SMAN", floats(-1)),
        sub("SIDE", struct.pack(">H", 2)),
    ])
    body += surface2("Green", [
        sub("COLR", floats(0.2, 0.9, 0.3) + vx(0)),
        sub("GLOS", floats(0.5) + vx(0)),
    ])
    return form("LWO2", body)


def big(tag, data):
    """An LWO3 chunk: a tag and a four-byte length."""
    return chunk(tag, data)


def value(kind, *numbers):
    """An LWO3 `VALU` form, as three.js's `parseValueForm` reads it."""
    data = b"\0" * 8 + text(kind)
    if kind in ("vparam", "vparam3"):
        data += b"\0" * 24 + struct.pack(">%dd" % len(numbers), *numbers)
    elif kind == "int":
        data += struct.pack(">I", numbers[0])
    else:
        data += struct.pack(">II", numbers[0], 0)
    return form("VALU", data)


def entry(name, body):
    """An `ENTR` form: a node attribute, named, holding a value."""
    return form("ENTR", b"NAME" + struct.pack(">I", len(text(name))) + text(name) + body)


def node(real, ref, body):
    """An `NTAG` form: a node with a real name and a reference name."""
    head = b"NRNM" + struct.pack(">I", len(text(real))) + text(real)
    return form("NTAG", head + big("NNME", text(ref)) + body)


def connection(node_name, input_name, input_node):
    return big("INME", text(node_name)) + big("IINM", text(input_name)) + big("IINN", text(input_node))


def lwo3_scene(material):
    body = big("TAGS", text("Shiny"))
    body += big("LAYR", struct.pack(">HH", 0, 0) + floats(0, 0, 0) + text("Only"))
    body += big("PNTS", floats(0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0))
    body += vmap("TXUV", 2, "UV", [(0, 0, 0), (1, 1, 0), (2, 1, 1), (3, 0, 1)])
    body += polygons("FACE", [[0, 1, 2, 3]])
    body += big("PTAG", b"SURF" + vx(0) + struct.pack(">H", 0))
    # A clip of index 2, three.js's texture for an image map.
    body += form("CLIP", b"\0" * 8 + struct.pack(">I", 2) + form("STIL", b"\0" * 8 + text("images/clip.png")))
    body += form("SURF", b"\0" * 8 + text("Shiny") + text("") + material)
    return form("LWO3", body)


def lwo3_standard():
    """A standard surface: color, roughness, metal and luminous, a color
    and a normal image node, an image map on its specular, and an
    environment file."""
    image = node(
        "Image",
        "Image1",
        big("FNAM", text("images/color.png")) + big("IUTL", struct.pack(">I", 1)) + big("IVTL", struct.pack(">I", 2)),
    )
    bumpy = node("Image", "Image2", big("FNAM", text("images/normal.png")) + form("IBMP", b"\0" * 48 + floats(0.5) + b"\0\0"))
    attributes = (
        entry("Color", value("vparam3", 0.6, 0.4, 0.2))
        + entry("Roughness", value("vparam", 0.35))
        + entry("Metallic", value("vparam", 0.8))
        + entry("Luminous", value("vparam", 0.5))
        + entry("Luminous Color", value("vparam3", 1, 0.5, 0))
        + entry("Transparency", value("vparam", 0.25))
        + entry("Bump Height", value("vparam", 2))
        + entry("Clearcoat", value("vparam", 0))
        + entry("Luminosity", value("vparam", 0.4))
        + entry("Specular", value("vparam", 0.5) + form("IMAP", b"\0" * 10 + big("IMAG", vx(2)) + big("WRAP", struct.pack(">HH", 2, 3))))
    )
    standard = node("Standard", "Standard1", big("FNAM", text("images/env.hdr")) + form("SATR", attributes))
    material = big("SIDE", struct.pack(">H", 3)) + big("SMAN", floats(1))
    material += form("NODS", form("NNDS", image + bumpy + standard))
    material += form(
        "NCON",
        connection("Surface", "Material", "Standard1")
        + connection("Standard1", "Color", "Image1")
        + connection("Standard1", "Normal", "Image2"),
    )
    return lwo3_scene(material)


def lwo3_phong():
    """A Phong surface: diffuse, luminosity, reflection, refraction,
    specular with a color highlight and glossiness, an image map on its
    color and one that names no clip, and luminous and alpha nodes."""
    glow = node("Image", "Glow", big("FNAM", text("images/glow.png")))
    alpha = node("Image", "Cut", big("FNAM", text("images/cut.png")))
    attributes = (
        entry("Color", value("vparam3", 0.5, 0.25, 1) + form("IMAP", b"\0" * 10 + big("IMAG", vx(2))))
        + entry("Diffuse", value("vparam", 0.8))
        + entry("Transparency", value("vparam", 0))
        + entry("Luminosity", value("vparam", 0.3))
        + entry("Reflection", value("vparam", 0.2))
        + entry("Refraction Index", value("vparam", 1.4))
        + entry("Specular", value("vparam", 0.6))
        + entry("Color Highlight", value("vparam", 0.5))
        + entry("Glossiness", value("vparam", 0.25))
        + entry("Kept", value("vparam", 1) + big("maps", text("m")))
        + entry("Diffuse Sharpness", value("int", 3) + form("IMAP", b"\0" * 10 + big("IMAG", vx(9))))
    )
    phong = node("Phong", "Phong1", form("ATTR", attributes))
    material = big("SIDE", struct.pack(">H", 1))
    material += form("NODS", form("NNDS", glow + alpha + phong))
    material += form(
        "NCON",
        connection("Surface", "Material", "Phong1")
        + connection("Phong1", "Luminous", "Glow")
        + connection("Phong1", "Alpha", "Cut"),
    )
    return lwo3_scene(material)


def lwo3_physical():
    """A physical surface: clearcoat and its gloss, with roughness and
    specular maps, of which three.js keeps the roughness."""
    rough = node("Image", "Rough", big("FNAM", text("images/rough.png")))
    shine = node("Image", "Shine", big("FNAM", text("images/shine.png")))
    metal = node("Image", "Metal", big("FNAM", text("images/metal.png")))
    attributes = (
        entry("Clearcoat", value("vparam", 0.7))
        + entry("Clearcoat Gloss", value("vparam", 0.4))
        + entry("Roughness", value("vparam", 0.3))
        + entry("Metallic", value("vparam", 0.1))
        + entry("Reflection", value("vparam", 0.5))
        + entry("Luminous", value("vparam", 1))
    )
    physical = node("Principled", "Principled1", big("FNAM", text("images/sky.hdr")) + form("ATTR", attributes))
    material = form("NODS", form("NNDS", rough + shine + metal + physical))
    material += form(
        "NCON",
        connection("Surface", "Material", "Principled1")
        + connection("Principled1", "Roughness", "Rough")
        + connection("Principled1", "Specular", "Shine")
        + connection("Principled1", "Metallic", "Metal")
        + connection("Principled1", "Luminous Color", "Metal"),
    )
    return lwo3_scene(material)


def lwo2_kitchen():
    """Every LWO2 chunk three.js reads, skips or keeps as text, written where
    three.js reads it without throwing."""
    body = chunk("TAGS", text("Red") + b"\0" + text("Gone") + b"Blues")
    body += chunk("ICON", b"abcd")
    body += chunk("AUVO", b"\0\0")
    body += chunk("OTAG", b"LINK" + text("one"))
    body += chunk("OTAG", b"LINK" + text("two"))
    body += chunk("AUVU", b"\0\0\0")
    body += chunk("DESC", text("A kitchen"))
    for tag in ["TEXT", "CMNT", "NCOM"]:
        body += chunk(tag, text("said"))
    body += chunk("NAME", text("channel"))
    body += chunk("OREF", text("other.lwo"))
    body += chunk("ROID", struct.pack(">I", 7))
    body += chunk("NSTA", struct.pack(">H", 1))
    body += chunk("NRNM", text("real"))
    for tag in ["INME", "IINN", "IINM", "IONM"]:
        body += chunk(tag, text("x"))
    body += chunk("CHAN", b"COLR")
    body += chunk("CHAN", b"COLR\0\0")
    body += chunk("IMAG", b"\xff\x01\x00\x02")
    body += chunk("WRAP", struct.pack(">HH", 1, 2))
    body += chunk("ZZZZ", "\u00e9\u20ac\U0001F600".encode() + b"\x80\xc0\x80\xe2\x82\xed\xa0\x80\xf5\xe2ABc")
    body += chunk("QQQQ", b"")
    # A skipped form, and a clip form that reads the next tag as its kind,
    # four bytes past its end.
    body += form("ISEQ", b"\0" * 6)
    body += form("CLIP", b"ENVL" + b"\0" * 4) + b"\0" * 4
    body += chunk("LAYR", struct.pack(">HH", 0, 0) + floats(0, 0, 0) + text("Main"))
    body += chunk("PNTS", floats(0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0))
    body += vmap("TXUV", 2, "UV", [(0, 0, 0), (2, 1, 1)])
    body += chunk("VMAP", text("OnlyAName"))
    body += vmap("ABCD", 1, "Unknown", [(0, 1.0)])
    body += vmap("MORF", 3, "Far", [(9, 1, 1, 1), (1, 0, 1, 0)])
    body += polygons("FACE", [[0, 1, 2], [], [0, 2, 3], [0, 1, 3], [1, 2, 3], [0, 1, 2], [0, 2, 3]])
    body += chunk(
        "PTAG",
        b"SURF" + vx(0) + struct.pack(">H", 0) + b"\xff\x00\x00\x01" + struct.pack(">H", 0)
        + b"".join(vx(i) + struct.pack(">H", s) for i, s in [(2, 1), (3, 0), (4, 2), (5, 1), (6, 0)]),
    )
    # A layer of points and no polygons, whose mesh is empty.
    body += chunk("LAYR", struct.pack(">HH", 1, 0) + floats(0, 0, 0) + text("Empty"))
    body += chunk("PNTS", floats(0, 0, 0))
    body += polygons("FACE", [])
    body += chunk("CLIP", struct.pack(">I", 1) + b"ISEQ" + struct.pack(">H", 100))
    body += chunk("CLIP", struct.pack(">I", 2) + b"ISEQ" + struct.pack(">H", 2) + b"STIL" + struct.pack(">H", 6) + text("x.png"))
    body += surface2("Red", [
        sub("COLR", floats(1, 0, 0) + vx(0)),
        sub("RIMG", vx(1)),
        sub("TIMG", vx(1)),
        sub("SSHN", text("shader")),
        sub("AOVN", text("aov")),
        sub("IMAP", b"\x80\0"),
        sub("BLOK", b""),
    ])
    # Chunks that write nothing, past the surface's end, and then a second
    # surface, which the first surface's end handed back to the materials.
    body += chunk("ICON", b"\0" * 40)
    body += surface2("Blues", [sub("COLR", floats(0, 0, 1) + vx(0))])
    return form("LWO2", body)


def lwo3_kitchen():
    """Every LWO3 form three.js reads, and a surface of every attribute and
    map name three.js looks for."""
    def clip(index, name):
        return form("CLIP", b"\0" * 8 + struct.pack(">I", index) + form("STIL", b"\0" * 8 + text(name)))

    def image_map(index, wrap=None):
        body = b"\0" * 10 + big("IMAG", vx(index))
        if wrap:
            body += big("WRAP", struct.pack(">HH", *wrap))
        return form("IMAP", body)

    xval = lambda kind, *v: form(kind, b"\0" * 8 + floats(*v))
    node_extras = (
        big("IPIX", struct.pack(">i", -3)) + big("IMIP", b"\0\0")
        + big("IUVI", b"") + big("IUVI", b"UVMap\0")
        + big("CHAN", b"COLR")
        + form("ISCL", b"\0" * 48 + floats(1, 2, 3) + b"\0\0")
        + form("IPOS", b"\0" * 48 + floats(1, 2, 3) + b"\0\0")
        + form("IROT", b"\0" * 48 + floats(1, 2, 3) + b"\0\0")
        + form("IFAL", b"\0" * 48 + floats(1, 2, 3) + b"\0\0")
        + form("IUTD", b"\0" * 48 + floats(2) + b"\0\0")
        + form("IVTD", b"\0" * 48 + floats(3) + b"\0\0")
        + form("CLIP", b"FORM" + b"\0" * 16 + text("images/inner.png"))
        + form("XREF", b"\0" * 8 + struct.pack(">I", 4) + text("ref"))
        + form("IMST", b"\0" * 8 + floats(0.5))
        + form("ISEQ", b"\0" * 4) + form("META", b"") + form("ENVL", b"\0" * 4)
        + form("QQQQ", b"\0" * 4)
    )
    alpha = node("Image", "Cut", big("FNAM", text("images/cut.png")) + node_extras)
    bumpy = node("Image", "Bumpy", big("FNAM", text("images/bump.png")))
    plain_normal = node("Image", "Flat", big("FNAM", text("images/flat.png")))
    extra = node("Image", "Extra", big("FNAM", text("images/extra.png")))
    rough = node("Image", "Rough", big("FNAM", text("images/rough.png")))
    # A node with no attributes form: its entry lands on the node itself.
    bare = node("Bare", "Bare1", entry("Loose", value("double", 5)))
    attributes = (
        big("ZZZZ", text("kept"))
        + entry("Color", value("vparam3", 0.3, 0.6, 0.9))
        + entry("Color", value("vparam3", 0.4, 0.6, 0.9))
        + entry("Transparency", value("vparam", 0.5) + image_map(3))
        + entry("Clearcoat", value("vparam", 0.5))
        + entry("Roughness", value("vparam", 0.4) + image_map(3))
        + entry("Luminous", value("vparam", 2))
        + entry("Luminous Color", value("vparam3", 1, 1, 0))
        + entry("Luminosity", value("vparam", 0.5) + image_map(6))
        + entry("Diffuse", value("vparam", 0.7) + image_map(3))
        + entry("Specular", value("vparam", 0.2) + image_map(3, (0, 1)))
        + entry("Metallic", value("vparam", 0.3) + image_map(6))
        + entry("Alpha", value("vparam", 1) + image_map(3))
        + entry("Normal", value("vparam", 1) + image_map(3))
        + entry("Bump", value("vparam", 1) + image_map(3))
        + entry("Glossiness", value("vparam", 0.5) + image_map(3))
        + entry("Flag", value("bool", 1))
        + entry("Diffuse Sharpness", value("vparam", 0.5) + form("IMAP", bytes(10)))
    )
    standard = node("Standard", "Standard1", big("FNAM", text("images/env.hdr")) + form("SATR", attributes))
    material = big("SIDE", struct.pack(">H", 5)) + big("IMAP", struct.pack(">I", 9)) + big("SURF", b"odd\0")
    material += form("SSHA", big("SSHN", text("s")) + form("SSHD", b""))
    material += form("TMAP", form("CNTR", b"\0" * 8 + floats(1, 2, 3)) + form("SIZE", b"\0" * 8 + floats(1, 1, 1)) + form("ROTA", b"\0" * 8 + floats(0, 0, 0)))
    material += form("NODS", form("NNDS", alpha + bumpy + plain_normal + extra + rough + bare + standard))
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
    body = big("TAGS", text("Shiny") + text("Missing"))
    body += big("LAYR", struct.pack(">HH", 0, 0) + floats(0, 0, 0) + text("Only"))
    body += big("PNTS", floats(0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0))
    body += polygons("FACE", [[0, 1, 2], [0, 2, 3]])
    body += big("PTAG", b"SURF" + vx(0) + struct.pack(">H", 0) + vx(1) + struct.pack(">H", 1))
    body += clip(3, "images/three.png") + clip(6, "images/six.png")
    body += form("CLIP", b"\0" * 8 + struct.pack(">I", 5))
    body += form("SURF", b"\0" * 8 + text("Shiny") + text("") + material)
    # A last amplitude form whose end is the file's end.
    body += form("TAMP", b"\0" * 8 + floats(0.25))
    return form("LWO3", body)


def main():
    open("scene.lwo", "wb").write(lwo2_scene())
    open("standard.lwo", "wb").write(lwo3_standard())
    open("phong.lwo", "wb").write(lwo3_phong())
    open("physical.lwo", "wb").write(lwo3_physical())
    open("kitchen.lwo", "wb").write(lwo2_kitchen())
    open("kitchen3.lwo", "wb").write(lwo3_kitchen())
    import os

    os.makedirs("broken", exist_ok=True)
    for name, data in broken().items():
        open("broken/" + name + ".lwo", "wb").write(data)


def broken():
    """Files the reader refuses: most of them three.js throws on, and the
    rest it reads in a way the port does not follow."""
    out = {}
    layer = chunk("TAGS", text("S")) + chunk("LAYR", struct.pack(">HH", 0, 0) + floats(0, 0, 0) + text("L"))
    points = chunk("PNTS", floats(0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0))
    tri = polygons("FACE", [[0, 1, 2]])
    tag = chunk("PTAG", b"SURF" + vx(0) + struct.pack(">H", 0))
    surf = surface2("S", [sub("COLR", floats(1, 1, 1) + vx(0))])
    good = layer + points + tri + tag + surf
    out["not_form"] = b"XXXX" + struct.pack(">I", 4) + b"LWO2"
    out["not_lwo"] = form("LWOB", good)
    out["short"] = form("LWO2", good)[:60]
    out["empty_tags"] = form("LWO2", chunk("TAGS", b"") + good)
    out["no_form"] = form("LWO3", form("NTAG", b"NRNM" + struct.pack(">I", 2) + text("n")) + big("ICON", bytes(8)) + big("DESC", text("d")) + good)
    out["no_node"] = form("LWO2", chunk("IUVI", b"") + good)
    out["no_surface"] = form("LWO2", chunk("SMAN", floats(1)) + good)
    out["open_string"] = form("LWO2", good + chunk("DESC", b"no end"))
    out["no_polygons"] = form("LWO2", layer + points + surf)
    out["tags_first"] = form("LWO2", layer + points + tag + tri + surf)
    out["no_tags"] = form("LWO2", layer + points + tri + surf)
    out["no_parent"] = form("LWO2", chunk("TAGS", text("S")) + chunk("LAYR", struct.pack(">HH", 0, 0) + floats(0, 0, 0) + text("L") + struct.pack(">H", 5)) + points + tri + tag + surf)
    out["lines_no_surface"] = form("LWO2", layer + points + polygons("FACE", [[0, 1]]) + chunk("PTAG", b"SURF" + vx(0) + struct.pack(">H", 3)) + surf)
    out["not_surface"] = form("LWO2", good + chunk("ICON", b"\0" * 40) + chunk("DESC", text("d")))
    # LWO3 surfaces.
    def surface3(material):
        return form("LWO3", big("TAGS", text("S")) + big("LAYR", struct.pack(">HH", 0, 0) + floats(0, 0, 0) + text("L")) + points + tri + big("PTAG", b"SURF" + vx(0) + struct.pack(">H", 0)) + form("SURF", b"\0" * 8 + text("S") + text("") + material))
    std = node("Standard", "Std", form("SATR", entry("Roughness", value("vparam", 0.5))))
    out["no_connections"] = surface3(form("NODS", form("NNDS", std)))
    out["no_material_node"] = surface3(form("NODS", form("NNDS", std)) + form("NCON", connection("Surface", "Material", "Nope")))
    out["no_node_names"] = surface3(form("NODS", form("NNDS", std)) + form("NCON", big("IINM", text("Material")) + big("IINN", text("Std"))))
    out["no_material"] = surface3(form("NODS", form("NNDS", std)) + form("NCON", connection("Surface", "Color", "Std")))
    out["no_texture_node"] = surface3(form("NODS", form("NNDS", std)) + form("NCON", connection("Surface", "Material", "Std") + connection("Std", "Color", "Gone")))
    out["no_texture_file"] = surface3(form("NODS", form("NNDS", std + node("Image", "Img", b""))) + form("NCON", connection("Surface", "Material", "Std") + connection("Std", "Color", "Img")))
    kept = node("Standard", "Std", form("SATR", big("ZZZZ", text("t")) + entry("ZZZZ", value("vparam", 1))))
    out["entry_on_text"] = surface3(form("NODS", form("NNDS", kept)) + form("NCON", connection("Surface", "Material", "Std")))
    # What three.js reads, and the port refuses.
    out["points_after"] = form("LWO2", layer + tri + points + tag + surf)
    out["few_tags"] = form("LWO2", layer + points + polygons("FACE", [[0, 1, 2], [0, 2, 3]]) + tag + surf)
    out["far_point"] = form("LWO2", layer + points + polygons("FACE", [[0, 1, 9]]) + tag + surf)
    out["far_uv"] = form("LWO2", layer + points + vmap("TXUV", 2, "UV", [(9, 0, 0)]) + tri + tag + surf)
    shapes = node("Standard", "Std", form("SATR", entry("Roughness", value("vparam", 0.5)) + entry("Color", value("vparam", 1))))
    out["color_shape"] = surface3(form("NODS", form("NNDS", shapes)) + form("NCON", connection("Surface", "Material", "Std")))
    empty = node("Standard", "Std", form("SATR", entry("Roughness", b"")))
    out["no_value"] = surface3(form("NODS", form("NNDS", empty)) + form("NCON", connection("Surface", "Material", "Std")))
    scalars = node("Standard", "Std", form("SATR", entry("Roughness", value("vparam3", 1, 2, 3))))
    out["scalar_shape"] = surface3(form("NODS", form("NNDS", scalars)) + form("NCON", connection("Surface", "Material", "Std")))
    colorless = node("Standard", "Std", form("SATR", entry("Roughness", value("vparam", 0.5)) + entry("Color", b"")))
    out["color_no_value"] = surface3(form("NODS", form("NNDS", colorless)) + form("NCON", connection("Surface", "Material", "Std")))
    out["short_node_inputs"] = surface3(form("NODS", form("NNDS", std)) + form("NCON", connection("Surface", "Material", "Std") + big("INME", text("Std")) + big("IINM", text("Color"))))
    out["short_inputs"] = surface3(form("NODS", form("NNDS", std)) + form("NCON", big("INME", text("Surface")) + big("IINM", text("Material"))))
    wraps = node("Image", "Img", big("FNAM", text("a.png")) + big("IUTL", struct.pack(">I", 7)))
    out["wrap7"] = surface3(form("NODS", form("NNDS", std + wraps)) + form("NCON", connection("Surface", "Material", "Std") + connection("Std", "Color", "Img")))
    return out


main()
