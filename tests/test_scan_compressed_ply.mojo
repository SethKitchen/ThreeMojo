# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.compressed_ply`, the compressed PLY reader.

`assets/compressed_ply/make_compressed_ply.mjs` wrote every compressed file
in `assets/compressed_ply/` with PlayCanvas splat-transform 3.10.1, and
read each one back with the same tool into a `_restored.ply` file. The
reader must make, from each compressed file, the splats that
`loaders.gaussian_splat_ply` makes from its PLY file. Every way a header
can be wrong is made from a real file and refused.
"""

from extensions.scan.compressed_ply import (
    is_compressed_ply,
    parse_compressed_ply,
    read_compressed_ply,
)
from extensions.scan.scene import SPLAT_ANTIALIASED, SPLAT_DEFAULT
from loaders.gaussian_splat_ply import read_gaussian_splat_ply
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._splat_same import same_splats

comptime DIR = "assets/compressed_ply/"


def _file(name: String) raises -> List[UInt8]:
    """Return a test file's bytes."""
    return Path(DIR + name).read_bytes()


def _edit(bytes: List[UInt8], old: String, new: String) raises -> List[UInt8]:
    """Return the bytes with the first `old` replaced by `new`."""
    var from_bytes = old.as_bytes()
    for at in range(len(bytes) - len(from_bytes) + 1):
        var found = True
        for k in range(len(from_bytes)):
            if bytes[at + k] != from_bytes[k]:
                found = False
                break
        if found:
            var out = List[UInt8](capacity=len(bytes))
            for k in range(at):
                out.append(bytes[k])
            for byte in new.as_bytes():
                out.append(byte)
            for k in range(at + len(from_bytes), len(bytes)):
                out.append(bytes[k])
            return out^
    raise Error("the test file has no '" + old + "'")


def _bytes(text: String) -> List[UInt8]:
    """Return a text's bytes."""
    var out = List[UInt8]()
    for byte in text.as_bytes():
        out.append(byte)
    return out^


def _refused(bytes: List[UInt8], message: String) raises:
    """Assert that a file is refused with a message."""
    with assert_raises(contains=message):
        _ = parse_compressed_ply(bytes)


def test_every_file_makes_the_splats_of_its_restored_ply() raises:
    """Each file, read here, holds what splat-transform read from it."""
    for name in ["sh3", "sh2", "sh1", "sh0", "untinted"]:
        var scene = read_compressed_ply(DIR + name + ".compressed.ply")
        same_splats(
            scene.geometry,
            read_gaussian_splat_ply(DIR + name + "_restored.ply"),
        )
        assert_true(scene.model == SPLAT_DEFAULT)


def test_the_files_cover_every_band() raises:
    """The files reach every band, and every chunk of a long file."""
    var sh3 = read_compressed_ply(DIR + "sh3.compressed.ply")
    assert_equal(sh3.geometry.count(), 600)
    assert_equal(sh3.geometry.spherical_harmonics_degree(), 3)
    var sh0 = read_compressed_ply(DIR + "sh0.compressed.ply")
    assert_equal(sh0.geometry.spherical_harmonics_degree(), 0)


def test_the_ends_of_the_alpha_byte_are_clear_and_solid() raises:
    """An alpha byte of 0 is an infinite negative logit, so no opacity, and
    255 an infinite one, so full opacity."""
    var bytes = _file("sh1.compressed.ply")
    var marker = _bytes("end_header\n")
    var start = 0
    for at in range(len(bytes)):
        var found = True
        for k in range(len(marker)):
            if bytes[at + k] != marker[k]:
                found = False
                break
        if found:
            start = at + len(marker)
            break
    # One chunk row of 18 floats, then 16 bytes a splat; the alpha is the
    # low byte of the fourth word.
    var vertex = start + 72
    bytes[vertex + 12] = 0
    bytes[vertex + 16 + 12] = 255
    var colors = parse_compressed_ply(bytes).geometry.colors.copy()
    assert_equal(colors[3], 0)
    assert_equal(colors[7], 255)


def test_a_comment_names_the_model() raises:
    """A `SplatRenderMode` comment is kept with the splats."""
    var bytes = _edit(
        _file("sh1.compressed.ply"),
        "comment Generated",
        "comment SplatRenderMode: mip\ncomment Generated",
    )
    var scene = parse_compressed_ply(bytes)
    assert_true(scene.model == SPLAT_ANTIALIASED)
    same_splats(
        scene.geometry, read_gaussian_splat_ply(DIR + "sh1_restored.ply")
    )


def test_header_lines_that_are_skipped() raises:
    """A `ply` line, an empty line, an empty `sh` element, doubled spaces, a
    signed count and no comment are read past."""
    var bytes = _edit(
        _edit(
            _edit(
                _file("sh0.compressed.ply"),
                "end_header",
                "ply\n\nelement  sh +9\nend_header",
            ),
            "comment Generated by splat-transform 3.10.1\n",
            "",
        ),
        "element vertex 9",
        "element vertex +9",
    )
    var scene = parse_compressed_ply(bytes)
    assert_true(scene.model == SPLAT_DEFAULT)
    same_splats(
        scene.geometry, read_gaussian_splat_ply(DIR + "sh0_restored.ply")
    )


def test_compressed_files_are_told_apart() raises:
    """Only a readable header with `packed_position` is compressed."""
    assert_true(is_compressed_ply(_file("sh2.compressed.ply")))
    assert_false(is_compressed_ply(Path(DIR + "sh2_restored.ply").read_bytes()))
    assert_false(is_compressed_ply(_bytes("ply")))
    assert_false(
        is_compressed_ply(
            _bytes("ply\nformat binary_little_endian 1.0\nend_header\n")
        )
    )
    assert_false(
        is_compressed_ply(
            _bytes(
                "ply\nformat binary_little_endian 1.0\nelement vertex 0\n"
                "end_header\n"
            )
        )
    )
    var renamed = _edit(_file("sh0.compressed.ply"), "vertex", "points")
    assert_false(is_compressed_ply(renamed))
    _refused(renamed, "no packed_position")
    _refused(
        Path(DIR + "sh0_restored.ply").read_bytes(),
        "loaders.gaussian_splat_ply",
    )


def test_a_header_must_end_early() raises:
    """The end of the header is looked for in the first 128 KiB."""
    var text = String("ply\ncomment ")
    for _ in range(140000):
        text += "a"
    _refused(_bytes(text + "\nend_header\n"), "end_header is not in")
    _refused(_bytes("pl"), "end_header is not in")


def test_malformed_header_lines_are_refused() raises:
    """Each malformed header line is refused, naming what is wrong."""
    var sh1 = _file("sh1.compressed.ply")
    _refused(_edit(sh1, "ply\n", "plx\n"), "does not start with ply")
    _refused(_edit(sh1, " 1.0\n", "\n   \n"), "unrecognized header line ''")
    _refused(_edit(sh1, "comment", "obj_info"), "line 'obj_info'")
    _refused(_edit(sh1, "element chunk 1", "element chunk"), "element line")
    _refused(_edit(sh1, "element chunk 1", "element chunk one"), "not a count")
    _refused(_edit(sh1, "element chunk 1", "element chunk -1"), "negative")
    _refused(_edit(sh1, "element chunk 1", "element chunk -"), "not a count")
    _refused(_edit(sh1, "element chunk 1", "element chunk 1."), "not a count")
    _refused(_edit(sh1, "element chunk 1", "element chunk 1a"), "not a count")
    _refused(
        _edit(sh1, "element chunk 1", "element chunk -0"),
        "30 splats need 1 chunks, and the file has 0",
    )
    _refused(
        _edit(sh1, "element chunk 1", "element chunk 4294967296"),
        "too large a count",
    )
    _refused(
        _edit(sh1, "element chunk 1", "element chunk 99999999999999999999999"),
        "too large a count",
    )
    _refused(
        _edit(sh1, "comment", "property float early\ncomment"),
        "invalid property line",
    )
    _refused(
        _edit(sh1, "property float min_x", "property list uchar float min_x"),
        "invalid property line",
    )
    _refused(
        _edit(sh1, "property float min_x", "property half min_x"),
        "type 'half'",
    )


def test_a_short_file_is_refused() raises:
    """A file that ends before its rows do is refused."""
    var sh1 = _file("sh1.compressed.ply")
    var short = List[UInt8]()
    for index in range(len(sh1) - 1):
        short.append(sh1[index])
    _refused(short, "its header needs")


def test_the_format_must_be_little_endian() raises:
    """An ASCII, a big-endian or a missing format is refused."""
    var sh1 = _file("sh1.compressed.ply")
    _refused(_edit(sh1, "binary_little_endian", "ascii"), "not 'ascii'")
    _refused(
        _edit(sh1, "binary_little_endian", "binary_big_endian"),
        "not 'binary_big_endian'",
    )
    _refused(_edit(sh1, "format binary_little_endian 1.0", "format"), "not ''")


def test_the_elements_must_agree() raises:
    """A missing chunk element, no splats or a wrong count of chunks is
    refused."""
    var sh1 = _file("sh1.compressed.ply")
    _refused(
        _edit(sh1, "element chunk", "element block"), "has no chunk element"
    )
    _refused(
        _edit(
            _edit(sh1, "element vertex 30", "element vertex 0"),
            "element sh 30",
            "element sh 0",
        ),
        "at least one splat",
    )
    _refused(
        _edit(
            _file("sh3.compressed.ply"), "element chunk 3", "element chunk 2"
        ),
        "600 splats need 3 chunks, and the file has 2",
    )


def test_each_word_and_bound_must_be_there() raises:
    """A missing or mistyped packed word, or a missing bound, is refused."""
    var sh1 = _file("sh1.compressed.ply")
    _refused(_edit(sh1, "packed_scale", "packed_sizes"), "has no packed_scale")
    _refused(
        _edit(sh1, "property uint packed_color", "property int packed_color"),
        "packed_color must be a uint",
    )
    _refused(_edit(sh1, "min_scale_y", "min_scale_q"), "has no min_scale_y")
    _refused(_edit(sh1, "max_g", "max_q"), "has no max_g")


def test_the_harmonics_must_fit() raises:
    """A wrong count of bytes or rows, or a byte that is not a `uchar`, is
    refused."""
    var sh1 = _file("sh1.compressed.ply")
    _refused(
        _edit(sh1, "property uchar f_rest_8\n", ""),
        "8 sh bytes a splat, not 0, 9, 24 or 45",
    )
    _refused(
        _edit(sh1, "element sh 30", "element sh 29"),
        "the sh element has 29 rows for 30 splats",
    )
    _refused(
        _edit(sh1, "property uchar f_rest_3", "property char f_rest_3"),
        "f_rest_3 must be a uchar",
    )
    _refused(
        _edit(sh1, "property uchar f_rest_3\n", "property uchar f_rest_03\n"),
        "the sh element has no f_rest_3",
    )
    _refused(
        _edit(sh1, "property uchar f_rest_3\n", "property uchar f_rest_\n"),
        "the sh element has no f_rest_3",
    )
    _refused(
        _edit(sh1, "property uchar f_rest_3\n", "property uchar f_rest\n"),
        "the sh element has no f_rest_3",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
