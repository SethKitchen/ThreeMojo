# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.nrrd` and `objects.volume`: the files in
`assets/nrrd/` read as three.js 0.180's `NRRDLoader` reads them, from
`assets/nrrd/three_nrrd.mjs`."""

from loaders.json import JsonDocument, STRING, parse_json
from loaders.nrrd import gunzip, parse_nrrd, parse_nrrd_header, read_nrrd
from objects.volume import Volume, volume_element_size, volume_values
from std.math import inf, isnan
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _number(doc: JsonDocument, node: Int) raises -> Float64:
    """Return a reference number, `NaN` written as a string.

    Args:
        doc: The reference.
        node: The number.

    Returns:
        The number.
    """
    if doc.kind(node) == STRING:
        return Float64(0) / Float64(0)
    return doc.number(node)


def _same_list(
    got: List[Float64], doc: JsonDocument, node: Int, what: String
) raises:
    """Assert numbers are three.js's.

    Args:
        got: The numbers.
        doc: The reference.
        node: Its list.
        what: The name, for a failure.
    """
    assert_equal(len(got), doc.length(node), what)
    for k in range(len(got)):
        var want = _number(doc, doc.at(node, k))
        if isnan(want):
            assert_true(isnan(got[k]), what)
        else:
            assert_almost_equal(got[k], want, atol=1e-6, msg=what)


def test_each_file_is_read_as_three_js_reads_it() raises:
    var doc = parse_json(Path("assets/nrrd/nrrd.json").read_text())
    for name in [
        "raw.nrrd",
        "gzip.nrrd",
        "ascii.nrrd",
        "hex.nrrd",
        "whole.nrrd",
    ]:
        var volume = read_nrrd("assets/nrrd/" + name)
        var want = doc.get(doc.root(), name)
        _same_list(volume.data, doc, doc.get(want, "data"), name + " data")
        _same_list(
            volume.dimensions, doc, doc.get(want, "dimensions"), name + " dims"
        )
        _same_list(volume.spacing, doc, doc.get(want, "spacing"), name)
        _same_list(
            volume.ras_dimensions, doc, doc.get(want, "RASDimensions"), name
        )
        var order = doc.get(want, "axisOrder")
        for k in range(3):
            var axis = (
                volume.axis_order[k] if k < len(volume.axis_order) else ""
            )
            assert_equal(axis, doc.string(doc.at(order, k)), name)
        var matrix = doc.get(want, "matrix")
        var inverse = doc.get(want, "inverseMatrix")
        for k in range(16):
            assert_almost_equal(
                Float64(volume.matrix.elements[k]),
                doc.number(doc.at(matrix, k)),
                atol=1e-6,
                msg=name,
            )
            assert_almost_equal(
                Float64(volume.inverse_matrix.elements[k]),
                doc.number(doc.at(inverse, k)),
                atol=1e-6,
                msg=name,
            )
        assert_equal(volume.min, doc.number(doc.get(want, "min")), name)
        assert_equal(volume.max, doc.number(doc.get(want, "max")), name)
        assert_equal(volume.window_low, volume.min)
        assert_equal(volume.upper_threshold, volume.max)


def test_the_header_is_read_as_three_js_reads_it() raises:
    var doc = parse_json(Path("assets/nrrd/nrrd.json").read_text())
    var raw = read_nrrd("assets/nrrd/raw.nrrd")
    _ = raw^
    var bytes = Path("assets/nrrd/raw.nrrd").read_bytes()
    var text = List[Int]()
    for b in bytes:
        text.append(Int(b))
    var header = parse_nrrd_header(text)
    var want = doc.get(doc.get(doc.root(), "raw.nrrd"), "header")
    assert_equal(header.type.value(), doc.string(doc.get(want, "type")))
    assert_equal(header.space.value(), doc.string(doc.get(want, "space")))
    var origin = doc.get(want, "space_origin")
    for k in range(3):
        assert_equal(
            header.space_origin.value()[k], doc.string(doc.at(origin, k))
        )
    assert_equal(header.field_names[0], "kinds")
    assert_equal(header.field_values[0], doc.string(doc.get(want, "kinds")))


def _file(header: String, data: List[UInt8] = []) -> List[UInt8]:
    """Return an NRRD file of a header and data.

    Args:
        header: The header, with its blank line.
        data: The data.

    Returns:
        The bytes.
    """
    var out = List[UInt8](header.as_bytes())
    out.extend(data.copy())
    return out^


def test_what_three_js_throws_on_is_refused() raises:
    with assert_raises(contains="no blank line"):
        _ = parse_nrrd(_file("NRRD0004\ntype: uchar\n"))
    with assert_raises(contains="Not an NRRD file"):
        _ = parse_nrrd(_file("type: uchar\nx: y\n\n"))
    with assert_raises(contains="Bzip is not supported"):
        _ = parse_nrrd(_file("NRRD1\nencoding: bz2\nx: y\n\n"))
    with assert_raises(contains="Unsupported NRRD data type: long"):
        _ = parse_nrrd(_file("NRRD1\ntype: long\nx: y\n\n"))
    with assert_raises(contains="no encoding"):
        _ = parse_nrrd(_file("NRRD1\ntype: uchar\nx: y\n\n"))
    with assert_raises(contains="no type"):
        _ = parse_nrrd(_file("NRRD1\nencoding: raw\nx: y\n\n"))
    with assert_raises(contains="space origin has no ("):
        _ = parse_nrrd(_file("NRRD1\nspace origin: 1,2\nx: y\n\n"))
    with assert_raises(contains="have no ( )"):
        _ = parse_nrrd(_file("NRRD1\nspace directions: none\nx: y\n\n"))
    with assert_raises(contains="fewer than three"):
        _ = parse_nrrd(
            _file(
                "NRRD1\ntype: uchar\nencoding: raw\nspace directions: (1,0,0)"
                " (0,1\nx: y\n\n"
            )
        )
    with assert_raises(contains="no sizes"):
        _ = parse_nrrd(_file("NRRD1\ntype: uchar\nencoding: text\nx: y\n\n"))
    with assert_raises(contains="no length this port makes"):
        _ = parse_nrrd(
            _file("NRRD1\ntype: uchar\nencoding: text\nsizes: -1 2\nx: y\n\n")
        )
    with assert_raises(contains="not whole values"):
        _ = parse_nrrd(
            _file("NRRD1\ntype: short\nencoding: raw\nx: y\n\n", [1, 2, 3])
        )
    with assert_raises(contains="invalid gzip data"):
        _ = parse_nrrd(
            _file("NRRD1\ntype: uchar\nencoding: gzip\nx: y\n\n", [1, 2, 3])
        )


def test_the_header_s_edges_are_read_as_three_js_reads_them() raises:
    with assert_raises(contains="no blank line"):
        _ = parse_nrrd([])
    # A header of nothing is not NRRD.
    with assert_raises(contains="Not an NRRD file"):
        _ = parse_nrrd(_file("\n\n"))
    with assert_raises(contains="Bzip is not supported"):
        _ = parse_nrrd(_file("NRRD1\nencoding: bzip2\nx: y\n\n"))
    # A carriage return before a line feed goes; one at the end of the
    # last line stays. An empty first line is read as nothing.
    var text = List[Int]()
    for b in String(
        "\nNRRD1\r\ntype: uchar\r\nspace origin: (1,2(3)\r\nend: x\r"
    ).as_bytes():
        text.append(Int(b))
    var header = parse_nrrd_header(text)
    assert_equal(header.type.value(), "uchar")
    assert_equal(header.field_values[0], "x")
    # `split( '(' )[ 1 ]` ends at the second `(`.
    assert_equal(len(header.space_origin.value()), 2)
    assert_equal(header.space_origin.value()[1], "2")
    with assert_raises(contains="no length this port makes"):
        _ = parse_nrrd(
            _file(
                "NRRD1\ntype: uchar\nencoding: text\nsizes: 99999 99999 99\n"
                + "x: y\n\n"
            )
        )
    # Sizes that are not numbers hold no values.
    var none = parse_nrrd(
        _file("NRRD1\ntype: uchar\nencoding: text\nsizes: x\nx: y\n\n")
    )
    assert_equal(len(none.data), 0)
    # Directions that share an axis read the axes in order; one that no
    # direction has leaves a hole.
    var shared = parse_nrrd(
        _file(
            "NRRD1\ntype: uchar\nencoding: raw\nspace directions: (1,1,1)"
            + " (0,0,1) (0,1,0)\nx: y\n\n"
        )
    )
    assert_equal(shared.axis_order[0], "x")
    assert_equal(shared.axis_order[1], "y")
    var holed = parse_nrrd(
        _file(
            "NRRD1\ntype: uchar\nencoding: raw\nspace directions: (1,0,0)"
            + " (0,0,1) (0,0,2)\nx: y\n\n"
        )
    )
    assert_equal(len(holed.axis_order), 2)
    assert_equal(holed.axis_order[1], "z")


def test_words_are_read_as_parseint_and_parsefloat_read_them() raises:
    # The data is Latin-1: 0xA0 is a no-break space, which `parseInt` and
    # `parseFloat` skip.
    var header = "NRRD1\nsizes: 5\nencoding: hex\ntype: uint8\nx: y\n\n"
    var data = List[UInt8](
        String("f: 1/ " + String("9") * 400 + " ").as_bytes()
    )
    data.append(0xA0)
    data.extend(List[UInt8](String(" +").as_bytes()))
    var words = parse_nrrd(_file(header, data))
    # `f:` is 15; `1/` is 1; four hundred nines are Infinity, stored as
    # zero; a no-break space alone, or a sign alone, is NaN, also zero.
    _same(words.data, [15, 1, 0, 0, 0])
    var floats_data: List[UInt8] = [0xA0]
    floats_data.extend(List[UInt8](String("0.1 2 ").as_bytes()))
    floats_data.append(0xA0)
    var floats = parse_nrrd(
        _file(
            "NRRD1\nsizes: 3\nencoding: text\ntype: float\nx: y\n\n",
            floats_data,
        )
    )
    assert_equal(floats.data[0], Float64(Float32(0.1)))
    assert_equal(floats.data[1], 2)
    assert_true(isnan(floats.data[2]))


def test_gunzip_reads_the_header_as_fflate_does() raises:
    # A header with every optional part: extra data, a name, a comment and
    # a header CRC, then a stored block of two bytes and a trailer that
    # says three, so the output is padded with a zero.
    var file: List[UInt8] = [31, 139, 8, 4 | 8 | 16 | 2, 0, 0, 0, 0, 0, 3]
    file.extend([2, 0, 9, 9])
    file.extend([65, 0, 66, 0])
    file.extend([7, 7])
    file.extend([1, 2, 0, 253, 255, 5, 6])
    file.extend([0, 0, 0, 0, 3, 0, 0, 0])
    var out = gunzip(file)
    assert_equal(len(out), 3)
    assert_equal(out[0], 5)
    assert_equal(out[2], 0)
    # A trailer that says one cuts the output.
    file[len(file) - 4] = 1
    assert_equal(len(gunzip(file)), 1)
    with assert_raises(contains="invalid gzip data"):
        _ = gunzip([31, 139, 8, 0, 0])
    with assert_raises(contains="invalid gzip data"):
        _ = gunzip([31, 139])
    # A name that runs past the end reads as ended.
    with assert_raises(contains="invalid gzip data"):
        _ = gunzip([31, 139, 8, 8 | 4, 0, 0, 0, 0, 0, 3, 200])
    # A header and a trailer with no stream between them.
    var empty: List[UInt8] = [31, 139, 8, 0, 0, 0, 0, 0, 0, 3]
    empty.extend(List[UInt8](length=8, fill=0))
    with assert_raises():
        _ = gunzip(empty)
    file[len(file) - 1] = 0x7F
    with assert_raises(contains="longer than this port makes"):
        _ = gunzip(file)


def test_text_is_read_as_three_js_reads_each_type() raises:
    # Each type's wrapping, a word that is not a number, and a float.
    var header = "NRRD1\nsizes: 4\nencoding: text\ntype: "
    var bytes = parse_nrrd(
        _file(
            header + "uchar\nx: y\n\n",
            List[UInt8](String("256 -1 x 7").as_bytes()),
        )
    )
    _same(bytes.data, [0, 255, 0, 7])
    var signed = parse_nrrd(
        _file(
            header + "int8\nx: y\n\n",
            List[UInt8](String("128 -129 +5 -0").as_bytes()),
        )
    )
    _same(signed.data, [-128, 127, 5, 0])
    var wide = parse_nrrd(
        _file(
            header + "int\nx: y\n\n",
            List[UInt8](String("2147483648 4294967297 1 2").as_bytes()),
        )
    )
    _same(wide.data, [-2147483648, 1, 1, 2])
    var doubles = parse_nrrd(
        _file(
            header + "double\nx: y\n\n",
            List[UInt8](String("0.1 1e400 -2 x").as_bytes()),
        )
    )
    assert_equal(doubles.data[0], 0.1)
    assert_equal(doubles.data[1], inf[DType.float64]())
    assert_true(isnan(doubles.data[3]))
    var hex = parse_nrrd(
        _file(
            "NRRD1\nsizes: 4\nencoding: hex\ntype: ushort\nx: y\n\n",
            List[UInt8](String("0XfF -0x1 g 10").as_bytes()),
        )
    )
    _same(hex.data, [255, 65535, 0, 16])


def _same(got: List[Float64], want: List[Float64]) raises:
    """Assert two lists of numbers are equal.

    Args:
        got: The numbers.
        want: What they should be.
    """
    assert_equal(len(got), len(want))
    for k in range(len(got)):
        assert_equal(got[k], want[k])


def test_a_volume_reads_its_voxels_as_three_js_does() raises:
    var bytes: List[UInt8] = [1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0]
    var volume = Volume(3, 2, 0, "uint16_t", bytes)
    assert_equal(volume.z_length, 1)
    assert_equal(volume.get_data(1, 1, 0), 5)
    assert_equal(volume.access(2, 1, 0), 5)
    assert_true(isnan(volume.get_data(3, 1, 0)))
    assert_true(isnan(volume.get_data(0.5, 0, 0)))
    assert_true(isnan(volume.get_data(-1, 0, 0)))
    var back = volume.reverse_access(4)
    assert_equal(back[0], 1)
    assert_equal(back[1], 1)
    assert_equal(back[2], 0)
    var limits = volume.compute_min_max()
    assert_equal(limits[0], 1)
    assert_equal(limits[1], 6)
    var nan_length = Volume(Float64(0) / Float64(0), 1, 12, "unknown", bytes)
    assert_equal(nan_length.x_length, 1)
    assert_equal(nan_length.data[1], 0)
    with assert_raises(contains="lengths are not matching"):
        _ = Volume(2, 2, 2, "Uint8", bytes)
    with assert_raises(contains="not supported in JavaScript"):
        _ = Volume(1, 1, 1, "int64", bytes)
    for name in ["Float64", "Int32", "Int8", "float", "short"]:
        assert_true(volume_element_size(name) > 0)
    var floats = volume_values([0, 0, 0, 0, 0, 0, 0xF0, 0x3F], "double")
    assert_equal(floats[0], 1)
    var negative = volume_values([0xFF, 0xFF, 0xFF, 0xFF], "int")
    assert_equal(negative[0], -1)
    var positive = volume_values([1, 0, 0, 0], "int")
    assert_equal(positive[0], 1)
    var empty = Volume()
    _ = empty.compute_min_max()
    assert_equal(empty.min, inf[DType.float64]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
