# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.vtk`: the files in `assets/vtk/` read as three.js
0.180's `VTKLoader` reads them, from `assets/vtk/three_vtk.mjs`."""

from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from loaders.json import JsonDocument, NULL, parse_json
from loaders.vtk import (
    parse_vtk,
    parse_vtk_ascii,
    parse_vtk_binary,
    parse_vtk_xml,
    read_vtk,
)
from std.memory import bitcast
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _same(geometry: BufferGeometry, name: String) raises:
    """Assert a geometry is what three.js made of a fixture.

    Args:
        geometry: The geometry.
        name: The fixture.
    """
    var doc = parse_json(Path("assets/vtk/vtk.json").read_text())
    var want = doc.get(doc.root(), name)
    var index = doc.get(want, "index")
    if doc.kind(index) == NULL:
        assert_false(geometry.is_indexed(), name)
    else:
        assert_equal(len(geometry.index), doc.length(index), name)
        for k in range(len(geometry.index)):
            assert_equal(geometry.index[k], doc.integer(doc.at(index, k)), name)
    for key in [POSITION, NORMAL, COLOR]:
        var has = geometry.has_attribute(String(key))
        assert_equal(has, doc.has(want, String(key)), name + " " + String(key))
        if not has:
            continue
        var got = geometry.attribute_view(String(key)).packed()
        var values = doc.get(want, String(key))
        assert_equal(len(got), doc.length(values), name)
        for k in range(len(got)):
            # three.js decodes sRGB with `Math.pow`; this with the same
            # constants and `js_pow`, so colors agree to the last bit or
            # two of a float.
            assert_almost_equal(
                Float64(got[k]),
                doc.number(doc.at(values, k)),
                atol=1e-7,
                msg=name + " " + String(key),
            )


def test_legacy_text_is_read_as_three_js_reads_it() raises:
    _same(read_vtk("assets/vtk/ascii.vtk"), "ascii.vtk")


def test_cell_colors_lose_the_index_and_decode_twice() raises:
    _same(read_vtk("assets/vtk/cells.vtk"), "cells.vtk")


def test_legacy_binary_is_read_as_three_js_reads_it() raises:
    _same(read_vtk("assets/vtk/binary.vtk"), "binary.vtk")


def test_each_xml_encoding_is_read_as_three_js_reads_it() raises:
    for name in ["ascii.vtp", "binary.vtp", "zlib.vtp", "appended.vtp"]:
        _same(read_vtk("assets/vtk/" + name), name)


def test_xml_strips_are_cut_as_three_js_cuts_them() raises:
    _same(read_vtk("assets/vtk/strips.vtp"), "strips.vtp")


def test_text_quirks_are_kept() raises:
    # A word line, a line past the shared lastIndex, a short cell, Unicode
    # spaces and a control character, as three.js reads them.
    _same(read_vtk("assets/vtk/quirks.vtk"), "quirks.vtk")


def test_xml_edges_are_read_as_three_js_reads_them() raises:
    # base64url, padding and a bad character; appended offsets that are
    # missing, words or negative; a negative and an empty zlib header.
    for name in ["base64.vtp", "offsets.vtp", "headers.vtp"]:
        var geometry = read_vtk("assets/vtk/" + name)
        _same(geometry, name)
    # An index three.js makes empty draws nothing.
    var empty = read_vtk("assets/vtk/base64.vtp")
    assert_equal(empty.draw_range.count.value(), 0)


def _padded(text: String) -> List[UInt8]:
    """Return a file's bytes, padded past the 250 three.js reads first.

    Args:
        text: The file.

    Returns:
        The bytes, with spaces after.
    """
    var bytes = List[UInt8](text.as_bytes())
    while len(bytes) < 300:
        bytes.append(32)
    return bytes^


def test_the_kind_is_chosen_from_the_first_250_bytes() raises:
    with assert_raises(contains="shorter than 250"):
        _ = parse_vtk(List[UInt8](String("# vtk").as_bytes()))
    with assert_raises(contains="third line"):
        _ = parse_vtk(_padded("# vtk\nno third line"))
    # A byte order mark is dropped before the XML is read.
    var marked: List[UInt8] = [0xEF, 0xBB, 0xBF]
    marked.extend(
        _padded(
            '<?xml version="1.0"?><VTKFile a="1"><PolyData><Piece'
            + ' NumberOfPoints="1" NumberOfPolys="1"><Points><DataArray'
            + ' type="Float32" NumberOfComponents="3" format="ascii">1 2 3'
            + '</DataArray></Points><Polys><DataArray type="Int32"'
            + ' format="ascii">0 0 0</DataArray><DataArray type="Int32"'
            + ' format="ascii">3</DataArray></Polys></Piece></PolyData>'
            + "</VTKFile>"
        )
    )
    var xml = parse_vtk(marked)
    assert_equal(len(xml.index), 3)
    var bad = _padded("# vtk\ntitle\nASCII\n")
    bad[20] = 0xFF
    with assert_raises(contains="not UTF-8"):
        _ = parse_vtk(bad)


def test_what_three_js_throws_on_in_text_is_refused() raises:
    with assert_raises(contains="Unsupported DATASET type: STRUCTURED"):
        _ = parse_vtk_ascii("DATASET STRUCTURED_POINTS\n")
    with assert_raises(contains="type: undefined"):
        _ = parse_vtk_ascii("DATASET\n")
    # A code point past the first plane comes back whole in the message.
    with assert_raises(contains="P" + chr(0x1F600)):
        _ = parse_vtk_ascii("DATASET P" + chr(0x1F600) + "\n")
    var points = "POINTS 3 float\n0 0 0 1 0 0 0 1 0\n"
    with assert_raises(contains="names point 3 of 3"):
        _ = parse_vtk_ascii(points + "POLYGONS 1 4\n3 0 1 3\n")
    with assert_raises(contains="names point 70000"):
        _ = parse_vtk_ascii(points + "POLYGONS 1 4\n3 0 1 70000\n")
    with assert_raises(contains="more points than it gives"):
        _ = parse_vtk_ascii(points + "POLYGONS 1 9\n9 0 1\n")
    # No cells and no colors: one color for each of no index entries, so
    # three.js takes the cell branch and keeps no points.
    var bare = parse_vtk_ascii(points)
    assert_equal(len(bare.attribute_view(String(POSITION)).packed()), 0)
    assert_true(bare.has_attribute(String(COLOR)))


def _binary(
    parts: List[String], ints: List[Int], floats: List[Float32]
) -> List[UInt8]:
    """Return a legacy binary file: each text part, then the big-endian
    ints, then the floats.

    Args:
        parts: The text before the values.
        ints: 32-bit integers.
        floats: 32-bit floats.

    Returns:
        The bytes.
    """
    var out = List[UInt8]()
    for part in parts:
        out.extend(List[UInt8](part.as_bytes()))
    for value in ints:
        var bits = UInt32(value & 0xFFFFFFFF)
        for k in range(4):
            out.append(UInt8((bits >> UInt32(24 - 8 * k)) & 255))
    for value in floats:
        var bits = bitcast[DType.uint32](value)
        for k in range(4):
            out.append(UInt8((bits >> UInt32(24 - 8 * k)) & 255))
    return out^


def test_what_three_js_throws_on_in_binary_is_refused() raises:
    with assert_raises(contains="never ends"):
        _ = parse_vtk_binary(_binary(["DATASET POLYDATA"], [], []))
    with assert_raises(contains="Unsupported DATASET type: X"):
        _ = parse_vtk_binary(_binary(["DATASET X\n"], [], []))
    with assert_raises(contains="POINTS line has no count"):
        _ = parse_vtk_binary(_binary(["POINTS x float\n"], [], []))
    with assert_raises(contains="POINT_DATA line has no count"):
        _ = parse_vtk_binary(_binary(["POINT_DATA\n"], [], []))
    with assert_raises(contains="negative length"):
        _ = parse_vtk_binary(_binary(["POINTS -1 float\n"], [], []))
    with assert_raises(contains="runs past the end"):
        _ = parse_vtk_binary(_binary(["POINTS 2 float\n"], [], [0, 0, 0]))
    with assert_raises(contains="negative length"):
        _ = parse_vtk_binary(_binary(["POLYGONS 1 2\n"], [], []))
    with assert_raises(contains="no cells"):
        _ = parse_vtk_binary(_binary(["POINTS 1 float\n"], [], [0, 0, 0]))
    with assert_raises(contains="no points"):
        _ = parse_vtk_binary(_binary(["POLYGONS 0 0\n"], [], []))
    # No points and an empty normals list are the same length, which
    # three.js makes an attribute of and throws.
    with assert_raises(contains="no normals"):
        _ = parse_vtk_binary(
            _binary(["POINTS 0 float\n\nPOLYGONS 0 0\n"], [], [])
        )
    # A strip of five in a section sized for four keeps two triangles:
    # the typed array drops what is past its end.
    var strip = parse_vtk_binary(
        _binary(
            [
                "POINTS 5 float\n",
            ],
            [],
            [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 2, 2, 0],
        )
        + _binary(["\nTRIANGLE_STRIPS 1 5\n"], [5, 0, 1, 2, 3, 4], [])
        + _binary(["\n"], [], [])
    )
    assert_equal(len(strip.index), 6)
    assert_equal(strip.index[3], 1)
    assert_equal(strip.index[4], 3)


def _vtp(root: String, piece: String, tail: String = "") -> String:
    """Return a VTK XML file of one piece.

    Args:
        root: The `VTKFile`'s attributes.
        piece: What the `PolyData` holds.
        tail: What follows the `PolyData`.

    Returns:
        The text.
    """
    return (
        "<VTKFile"
        + root
        + "><PolyData>"
        + piece
        + "</PolyData>"
        + tail
        + "</VTKFile>"
    )


comptime _POINTS = (
    '<Points><DataArray type="Float32" NumberOfComponents="3"'
    ' format="ascii">1 2 3</DataArray></Points>'
)
comptime _POLYS = (
    '<Polys><DataArray type="Int32" format="ascii">0 0 0</DataArray>'
    '<DataArray type="Int32" format="ascii">3</DataArray></Polys>'
)
comptime _PIECE = '<Piece NumberOfPoints="1" NumberOfPolys="1">'


def test_what_three_js_throws_on_in_xml_is_refused() raises:
    var root = ' a="1"'
    var whole = _PIECE + _POINTS + _POLYS + "</Piece>"
    _ = parse_vtk_xml(_vtp(root, whole))
    with assert_raises(contains="Unsupported DATASET type"):
        _ = parse_vtk_xml("<VTKFile/>")
    with assert_raises(contains="more than one PolyData"):
        _ = parse_vtk_xml("<VTKFile a='1'><PolyData/><PolyData/></VTKFile>")
    with assert_raises(contains="has no Piece"):
        _ = parse_vtk_xml(_vtp(root, ""))
    with assert_raises(contains="VTKFile has no attributes"):
        _ = parse_vtk_xml(_vtp("", whole))
    with assert_raises(contains="no cells"):
        _ = parse_vtk_xml(_vtp(root, String(whole) + whole))
    with assert_raises(contains="no cells"):
        _ = parse_vtk_xml(_vtp(root, _PIECE + _POINTS + "</Piece>"))
    with assert_raises(contains="no points"):
        _ = parse_vtk_xml(_vtp(root, _PIECE + _POLYS + "</Piece>"))
    with assert_raises(contains="Piece has no attributes"):
        _ = parse_vtk_xml(_vtp(root, "<Piece>" + _POINTS + "</Piece>"))
    with assert_raises(contains="PointData has no attributes"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + "<PointData><DataArray a='1'/></PointData>"
                + "</Piece>",
            )
        )
    with assert_raises(contains="DataArray has no attributes"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + "<Points><DataArray>1</DataArray></Points>"
                + "</Piece>",
            )
        )
    with assert_raises(contains="more than one DataArray"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + "<Points><DataArray a='1'/><DataArray a='1'/>"
                + "</Points></Piece>",
            )
        )
    with assert_raises(contains="need a connectivity and offsets"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + _POINTS
                + "<Polys><DataArray a='1'/></Polys>"
                + "</Piece>",
            )
        )
    with assert_raises(contains="points array has no values"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + '<Points><DataArray type="Float64"'
                + ' NumberOfComponents="3" format="ascii">1 2 3</DataArray>'
                + "</Points></Piece>",
            )
        )
    with assert_raises(contains="more values than their count"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + '<Points><DataArray type="Float32"'
                + ' NumberOfComponents="3" format="ascii">1 2 3 4</DataArray>'
                + "</Points></Piece>",
            )
        )
    with assert_raises(contains="negative length"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + '<Points><DataArray type="Float32"'
                + ' NumberOfComponents="-3" format="ascii">1</DataArray>'
                + "</Points></Piece>",
            )
        )
    with assert_raises(contains="Length must be a multiple of 4"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + '<Points><DataArray type="Float32"'
                + ' NumberOfComponents="3" format="binary">AAA</DataArray>'
                + "</Points></Piece>",
            )
        )
    with assert_raises(contains="whole number of values"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + '<Points><DataArray type="Float32"'
                + ' NumberOfComponents="3" format="binary">AAAA</DataArray>'
                + "</Points></Piece>",
            )
        )
    # A type three.js does not read, in each encoding, has no values.
    for encoded in ["binary", "zlib"]:
        var attributes = root + (' compressor="z"' if encoded == "zlib" else "")
        with assert_raises(contains="points array has no values"):
            _ = parse_vtk_xml(
                _vtp(
                    attributes,
                    _PIECE
                    + '<Points><DataArray type="UInt8"'
                    + ' NumberOfComponents="3" format="binary">AAAA</DataArray>'
                    + "</Points></Piece>",
                )
            )
    # zlib: a header that is not zlib's, and one that names a dictionary
    # (0x78 0x20).
    for block in ["AQAAAA==", "AQAAAAAAAAAAAAAAAgAAAAAAeCA="]:
        with assert_raises(contains="invalid zlib data"):
            _ = parse_vtk_xml(
                _vtp(
                    ' compressor="z"'
                    + (
                        ' header_type="UInt32"' if block.byte_length()
                        > 8 else ""
                    ),
                    _PIECE
                    + '<Points><DataArray type="Float32"'
                    + ' NumberOfComponents="3" format="binary">'
                    + block
                    + "</DataArray></Points></Piece>",
                )
            )
    # Appended data: two, none, with no PolyData, and with no Piece.
    var data = '<AppendedData encoding="base64">_AAAA</AppendedData>'
    with assert_raises(contains="appended data has no text"):
        _ = parse_vtk_xml(_vtp(root, whole, String(data) + data))
    with assert_raises(contains="appended data has no text"):
        _ = parse_vtk_xml(_vtp(root, whole, "<AppendedData/>"))
    with assert_raises(contains="no one PolyData"):
        _ = parse_vtk_xml("<VTKFile a='1'>" + data + "</VTKFile>")
    with assert_raises(contains="has no Piece"):
        _ = parse_vtk_xml(_vtp(root, "", data))
    with assert_raises(contains="DataArray has no attributes"):
        _ = parse_vtk_xml(
            _vtp(root, _PIECE + "<Points><DataArray/></Points></Piece>", data)
        )
    # Two pieces with appended data: three.js assigns nothing, then has
    # no cells.
    with assert_raises(contains="no cells"):
        _ = parse_vtk_xml(_vtp(root, String(whole) + whole, data))


def test_text_edges_are_read_as_three_js_reads_them() raises:
    var points = "POINTS 3 float\n0 0 0 1 0 0 0 1 0\n"
    # An index of four hundred nines is Infinity, which a typed array
    # stores as zero.
    var huge = parse_vtk_ascii(
        points + "POLYGONS 1 4\n3 0 1 " + String("9") * 400 + "\n"
    )
    assert_equal(huge.index[2], 0)
    # A number cut by a letter is not a number of the run; a count with
    # no words, or cut by a letter, is no cell; a section word with no
    # count opens nothing.
    var cut = parse_vtk_ascii(
        "POINTS 3 float\n1x 0 0 0 1 0 0\n0 1 0\nPOLYGONS 3 6\n3\n3x\n"
        + "3 0 1 2\nPOINT_DATA x\nCELL_DATA\n"
    )
    assert_equal(len(cut.attribute_view(String(POSITION)).packed()), 9)
    assert_equal(len(cut.index), 3)
    # Colors and normals lines that start with a word keep no run, and
    # the shared lastIndex after them skips the short line that follows.
    # Two colors for three points are no color.
    var worded = parse_vtk_ascii(
        points
        + "POLYGONS 1 4\n3 0 1 2\nPOINT_DATA 3\nNORMALS n float\n"
        + "x 0 0 1\n0\n0 0 1 0 0 1 0 0 1\nCOLOR_SCALARS c 3\nx 1 0 0\n0\n"
        + "0 1 0 0 0 1\n"
    )
    assert_true(worded.has_attribute(String(NORMAL)))
    assert_false(worded.has_attribute(String(COLOR)))
    # Cell colors keep the normals, spread over the triangles' corners.
    var cells = parse_vtk_ascii(
        points
        + "POLYGONS 1 4\n3 0 1 2\nPOINT_DATA 3\nNORMALS n float\n"
        + "0 0 1 0 0 1 0 0 1\nCELL_DATA 1\nCOLOR_SCALARS c 3\n1 0 0\n"
    )
    assert_false(cells.is_indexed())
    assert_equal(len(cells.attribute_view(String(NORMAL)).packed()), 9)


def test_binary_edges_are_read_as_three_js_reads_them() raises:
    # A blank line, a cell of no points before a fan of five in a section
    # sized for one triangle, and normals for no points.
    var file = _binary(
        ["\nPOINTS 5 float\n"],
        [],
        [0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0, 2, 2, 0],
    )
    file.extend(_binary(["\nPOLYGONS 2 7\n"], [0, 5, 0, 1, 2, 3, 4], []))
    file.extend(_binary(["\nPOINT_DATA 0\nNORMALS n float\n"], [], []))
    var fan = parse_vtk_binary(file)
    assert_equal(len(fan.index), 3)
    assert_equal(fan.index[2], 2)


def _points(attributes: String, values: String) -> String:
    """Return a `Points` section of one text array.

    Args:
        attributes: The array's attributes.
        values: Its text.

    Returns:
        The section.
    """
    return (
        '<Points><DataArray type="Float32" format="ascii"'
        + attributes
        + ">"
        + values
        + "</DataArray></Points>"
    )


def _cells(
    section: String, count: String, conn: String, offsets: String
) -> String:
    """Return a piece of one point and a cell section.

    Args:
        section: `Strips` or `Polys`.
        count: The piece's count of cells.
        conn: The connectivity's text.
        offsets: The offsets' text.

    Returns:
        The piece.
    """
    var key = "NumberOfStrips" if section == "Strips" else "NumberOfPolys"
    return (
        '<Piece NumberOfPoints="4" '
        + key
        + '="'
        + count
        + '">'
        + _points(' NumberOfComponents="3"', "0 0 0 1 0 0 0 1 0 1 1 0")
        + "<"
        + section
        + '><DataArray type="Int32" format="ascii">'
        + conn
        + '</DataArray><DataArray type="Int32" format="ascii">'
        + offsets
        + "</DataArray></"
        + section
        + "></Piece>"
    )


def test_xml_edges_the_fixtures_miss_are_read_as_three_js_reads_them() raises:
    var root = ' a="1"'
    # No offsets: no cell is read, and the index is zeros. A binary array
    # of only its byte count is empty.
    var empty = '<DataArray type="Int32" format="binary">AAAAAA==</DataArray>'
    var no_offsets = parse_vtk_xml(
        _vtp(
            ' header_type="UInt32"',
            _PIECE
            + _POINTS
            + "<Polys>"
            + '<DataArray type="Int32" format="ascii">0 1 2</DataArray>'
            + empty
            + "</Polys></Piece>",
        )
    )
    _same_index(no_offsets.index, [0, 0, 0])
    # Strips that end at zero and at two make no triangles; one that ends
    # past the index's room stops when it is full.
    var ends = parse_vtk_xml(
        _vtp(root, _cells("Strips", "3", "0 1 2 3 0 1 2", "0 2 9"))
    )
    assert_equal(len(ends.index), 3 * (3 + 7) - 27)
    var full = parse_vtk_xml(_vtp(root, _cells("Strips", "1", "0 1 2", "5")))
    _same_index(full.index, [0, 1, 2])
    # Infinity is stored as zero.
    var infinite = parse_vtk_xml(
        _vtp(root, _cells("Strips", "1", "0 Infinity 2", "3"))
    )
    _same_index(infinite.index, [0, 0, 2])
    # A polygon of two points makes no triangle.
    var short = parse_vtk_xml(
        _vtp(root, _cells("Polys", "2", "0 1 0 1 2 3", "2 6"))
    )
    _same_index(short.index, [0, 1, 2, 0, 2, 3])
    with assert_raises(contains="negative length"):
        _ = parse_vtk_xml(
            _vtp(
                ' header_type="UInt32"',
                _PIECE
                + _POINTS
                + "<Polys>"
                + empty
                + empty
                + "</Polys></Piece>",
            )
        )
    # Counts of zero read nothing.
    with assert_raises(contains="no cells"):
        _ = parse_vtk_xml(_vtp(root, _cells("Polys", "0", "0 1 2", "3")))
    with assert_raises(contains="no points"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                '<Piece NumberOfPoints="0" NumberOfPolys="1">'
                + _points(' NumberOfComponents="3"', "0 0 0")
                + _POLYS
                + "</Piece>",
            )
        )
    # Components that are not a number, or none, hold nothing; too many
    # hold more than the points can; two a point are not points.
    for attributes in [' NumberOfComponents="x"', ""]:
        with assert_raises(contains="more values than their count"):
            _ = parse_vtk_xml(
                _vtp(
                    root,
                    _PIECE + _points(attributes, "1") + _POLYS + "</Piece>",
                )
            )
    with assert_raises(contains="longer than this port makes"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                '<Piece NumberOfPoints="99999999" NumberOfPolys="1">'
                + _points(' NumberOfComponents="3"', "1")
                + _POLYS
                + "</Piece>",
            )
        )
    with assert_raises(contains="not three numbers each"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + _points(' NumberOfComponents="2"', "1 2")
                + _POLYS
                + "</Piece>",
            )
        )
    # Point data of no points, of an array that is not the normals, and
    # of normals with no components.
    var data = (
        '<PointData Normals="N"><DataArray type="Float32"'
        ' Name="Other">1</DataArray></PointData>'
    )
    with assert_raises(contains="no points"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                '<Piece NumberOfPoints="0" NumberOfPolys="1">'
                + data
                + _POLYS
                + "</Piece>",
            )
        )
    _ = parse_vtk_xml(_vtp(root, _PIECE + data + _POINTS + _POLYS + "</Piece>"))
    with assert_raises(contains="more values than their count"):
        _ = parse_vtk_xml(
            _vtp(
                root,
                _PIECE
                + '<PointData Normals="N"><DataArray type="Float32"'
                + ' Name="N" format="ascii">1</DataArray></PointData>'
                + _POINTS
                + _POLYS
                + "</Piece>",
            )
        )


def test_xml_encodings_the_fixtures_miss_are_read_as_three_js_reads_them() raises:
    # base64 with `+`, `-` and `~`, the last read as zero; no header type
    # cuts nothing.
    var odd = parse_vtk_xml(
        _vtp(
            ' a="1"',
            _PIECE
            + '<Points><DataArray type="Int32"'
            + ' NumberOfComponents="3"'
            ' format="binary">+-~AAA==</DataArray></Points>'
            + _POLYS
            + "</Piece>",
        )
    )
    _ = odd^
    # A header of nothing but its byte count: no values, of either type.
    for type in ["Float32", "Int64"]:
        with assert_raises(contains="no points"):
            _ = parse_vtk_xml(
                _vtp(
                    ' header_type="UInt32"',
                    '<Piece NumberOfPoints="0" NumberOfPolys="1">'
                    + '<Points><DataArray type="'
                    + type
                    + '" NumberOfComponents="3"'
                    + ' format="binary">AAAAAA==</DataArray></Points>'
                    + _POLYS
                    + "</Piece>",
                )
            )
    # A UInt64 zlib header cut short reads zeros past its end.
    var cut = parse_vtk_xml(
        _vtp(
            ' header_type="UInt64" compressor="z"',
            _PIECE
            + '<Points><DataArray type="Float32" NumberOfComponents="3"'
            + ' format="binary">AAAA</DataArray></Points>'
            + _POLYS
            + "</Piece>",
        )
    )
    _ = cut^
    # Appended data with a section of no arrays, and an array whose slice
    # is empty.
    var appended = '<AppendedData encoding="base64">_AAAA</AppendedData>'
    with assert_raises(contains="points array has no values"):
        _ = parse_vtk_xml(
            _vtp(
                ' a="1"',
                '<Piece NumberOfPoints="1" NumberOfPolys="0"><Verts/>'
                + '<Points><DataArray type="Float32" NumberOfComponents="3"'
                ' offset="4"/>'
                + "</Points></Piece>",
                appended,
            )
        )
    with assert_raises(contains="no cells"):
        _ = parse_vtk_xml(
            _vtp(' a="1"', '<Piece NumberOfPoints="0"/>', appended)
        )


def _same_index(got: List[Int], want: List[Int]) raises:
    """Assert an index is the one given.

    Args:
        got: The index.
        want: What it should be.
    """
    assert_equal(len(got), len(want))
    for k in range(len(got)):
        assert_equal(got[k], want[k])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
