# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`loaders.ultrahdr` against three.js's `UltraHDRLoader`.

`assets/ultrahdr/` has three UltraHDR files in libultrahdr's layout,
written with PIL: a gain map of the same size in color, one with a gamma
and no SDR offset in gray, and one of half the size. `three.json` holds
what three.js 0.180's `UltraHDRLoader.parse` gives for them with
`FloatType`, run in node. A browser decodes the JPEG files and scales
the gain map, so there an image and a canvas give the pixels that
`render.jpeg` decodes and `scale_gain_map` scales. The segments, the MPF
index, the XMP and the formula are three.js's own.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from loaders.json import parse_json
from loaders.ultrahdr import (
    XMP_NAMESPACE,
    UltraHdrMetadata,
    _read_xmp,
    apply_gain_map,
    parse_ultrahdr,
    read_ultrahdr,
    scale_gain_map,
)
from render.png import DecodedImage
from render.srgb import SRGB
from std.math import isnan
from std.pathlib import Path


def test_images_match_three_js() raises:
    var text = String(
        unsafe_from_utf8=open("assets/ultrahdr/three.json", "r").read_bytes()
    )
    var doc = parse_json(text)
    for name in ["same", "gamma", "half"]:
        var expected = doc.get(doc.root(), name)
        var hdr = read_ultrahdr("assets/ultrahdr/" + name + ".jpg")
        ref image = hdr.image
        assert_equal(image.width, doc.integer(doc.get(expected, "width")))
        assert_equal(image.height, doc.integer(doc.get(expected, "height")))
        var data = doc.get(expected, "data")
        for i in range(len(image.pixels)):
            if i % 4 == 3:
                # three.js writes 255, the value of its half fill.
                assert_equal(image.pixels[i], 1)
            else:
                assert_equal(
                    Float64(image.pixels[i]), doc.number(doc.at(data, i))
                )


def test_metadata() raises:
    var same = read_ultrahdr("assets/ultrahdr/same.jpg").metadata.copy()
    assert_equal(same.version, "1.0")
    assert_false(same.base_rendition_is_hdr)
    assert_equal(same.gain_map_min, -0.5)
    assert_equal(same.gain_map_max, 2.5)
    assert_equal(same.offset_sdr, 1)
    assert_equal(same.offset_hdr, 1)
    assert_equal(same.hdr_capacity_max, 2.5)
    var gamma = read_ultrahdr("assets/ultrahdr/gamma.jpg").metadata.copy()
    assert_equal(gamma.gamma, 2.2)
    # No OffsetSDR is zero: three.js's `null / (1 / 64)`.
    assert_equal(gamma.offset_sdr, 0)


def _image(width: Int, height: Int, value: UInt8) -> DecodedImage:
    """Return an opaque image of one gray."""
    var pixels = List[UInt8](length=width * height * 4, fill=value)
    for i in range(width * height):
        pixels[i * 4 + 3] = 255
    return DecodedImage(width, height, pixels^, SRGB)


def test_scaling() raises:
    # One gray scales to itself, and two columns blend between.
    var tall = scale_gain_map(_image(2, 1, 100), 2, 2)
    assert_equal(Int(tall[4]), 100)
    var flat = scale_gain_map(_image(2, 1, 100), 4, 2)
    for i in range(len(flat)):
        assert_equal(Int(flat[i]), 255 if i % 4 == 3 else 100)
    var pair = _image(2, 1, 0)
    pair.pixels[4] = 200
    var wide = scale_gain_map(pair, 4, 1)
    assert_equal(Int(wide[0]), 0)
    assert_equal(Int(wide[4]), 50)
    assert_equal(Int(wide[8]), 150)
    assert_equal(Int(wide[12]), 200)


def test_refusals() raises:
    var metadata = UltraHdrMetadata()
    with assert_raises(contains="one aspect ratio"):
        _ = apply_gain_map(_image(4, 2, 0), _image(2, 2, 0), metadata)
    metadata.hdr_capacity_max = 0
    with assert_raises(contains="must not be zero"):
        _ = apply_gain_map(_image(2, 2, 0), _image(2, 2, 0), metadata)
    metadata.gamma = Float64("nan")
    with assert_raises(contains="not finite"):
        _ = apply_gain_map(_image(2, 2, 0), _image(2, 2, 0), metadata)
    var good = Path("assets/ultrahdr/same.jpg").read_bytes()
    with assert_raises(contains="SOI"):
        _ = parse_ultrahdr(List[UInt8](good[2:]))
    # A plain JPEG file: no version and no MPF index.
    var plain = List[UInt8](good[0:2])
    plain.extend([UInt8(0xFF), 0xD9, 0, 0])
    with assert_raises(contains="no hdrgm:Version"):
        _ = parse_ultrahdr(plain)


def _segment(marker: Int, payload: List[UInt8]) -> List[UInt8]:
    """Return a marker segment."""
    var out: List[UInt8] = [0xFF, UInt8(marker)]
    var length = len(payload) + 2
    out.append(UInt8(length >> 8))
    out.append(UInt8(length & 255))
    out.extend(payload.copy())
    return out^


def _text(text: String) -> List[UInt8]:
    """Return the bytes of a text."""
    return List[UInt8](text.as_bytes())


def _xmp(attributes: String) -> List[UInt8]:
    """Return an APP1 segment of XMP with one `rdf:Description`."""
    var payload = _text(XMP_NAMESPACE)
    payload.append(0)
    payload.extend(
        _text(
            "<x:xmpmeta><rdf:RDF><rdf:Description "
            + attributes
            + "/></rdf:RDF></x:xmpmeta>"
        )
    )
    return _segment(0xE1, payload)


def _mpf(primary_size: Int, gain_size: Int, gain_offset: Int) -> List[UInt8]:
    """Return an APP2 MPF segment, big-endian, with the entries where
    three.js reads them."""
    var payload = List[UInt8](length=82, fill=0)
    var head = _text("MPF\0MM\0*")
    for i in range(len(head)):
        payload[i] = head[i]
    for pair in [(58, primary_size), (74, gain_size), (78, gain_offset)]:
        for k in range(4):
            payload[pair[0] + k] = UInt8((pair[1] >> (24 - 8 * k)) & 255)
    return _segment(0xE2, payload)


def _file(var parts: List[UInt8]) -> List[UInt8]:
    """Return a start of image, the parts, and a start of scan."""
    var out: List[UInt8] = [0xFF, 0xD8]
    out.extend(parts^)
    out.extend([UInt8(0xFF), 0xDA, 0, 0])
    return out^


def test_segments_are_checked() raises:
    with assert_raises(contains="SOI"):
        _ = parse_ultrahdr([UInt8(0xFF)])
    with assert_raises(contains="SOI"):
        _ = parse_ultrahdr([UInt8(0), 0xD8, 0, 0])
    with assert_raises(contains="must start with 0xFF"):
        _ = parse_ultrahdr([UInt8(0xFF), 0xD8, 0, 0, 0, 0])
    with assert_raises(contains="runs past the file"):
        _ = parse_ultrahdr([UInt8(0xFF), 0xD8, 0xFF, 0xE0, 0, 1])
    with assert_raises(contains="runs past the file"):
        _ = parse_ultrahdr([UInt8(0xFF), 0xD8, 0xFF, 0xE0, 0, 9])
    with assert_raises(contains="ends before its scan"):
        _ = parse_ultrahdr([UInt8(0xFF), 0xD8, 0xFF, 0xE0, 0, 2])
    with assert_raises(contains="cut short"):
        _ = parse_ultrahdr(_file(_segment(0xE2, _text("MPF\0MM\0*"))))
    # EXIF data is read past, and a version without an MPF index is not
    # enough.
    var exif = _segment(0xE1, _text("Exif\0\0"))
    exif.extend(_segment(0xE2, _text("ICC_PROFILE\0")))
    exif.extend(_xmp('hdrgm:Version="1.0"'))
    with assert_raises(contains="no MPF index"):
        _ = parse_ultrahdr(_file(exif^))
    # A gain map past the end of the file, and an SDR image of no bytes.
    var parts = _xmp('hdrgm:Version="1.0"')
    parts.extend(_mpf(0, 8, 5000))
    with assert_raises(contains="SOI"):
        _ = parse_ultrahdr(_file(parts^))
    # The gain map is a start of image and of scan after the file's own
    # scan: past the TIFF header by the MPF segment's length less four.
    var mpf_length = len(_mpf(0, 0, 0))
    var empty = _xmp('hdrgm:Version="1.0"')
    empty.extend(_mpf(0, 6, mpf_length - 4))
    var bytes = _file(empty^)
    bytes.extend([UInt8(0xFF), 0xD8, 0xFF, 0xDA, 0, 0])
    with assert_raises(contains="an image of the MPF index runs past"):
        _ = parse_ultrahdr(bytes)
    var long = _xmp('hdrgm:Version="1.0"')
    long.extend(_mpf(99999, 6, mpf_length - 4))
    var past = _file(long^)
    past.extend([UInt8(0xFF), 0xD8, 0xFF, 0xDA, 0, 0])
    with assert_raises(contains="an image of the MPF index runs past"):
        _ = parse_ultrahdr(past)


def test_little_endian_index() raises:
    # The MPF index of `same.jpg`, written little-endian, reads the same.
    var bytes = Path("assets/ultrahdr/same.jpg").read_bytes()
    var at = 2
    while not (bytes[at] == 0xFF and bytes[at + 1] == 0xE2):
        at += 2 + ((Int(bytes[at + 2]) << 8) | Int(bytes[at + 3]))
    var base = at + 2
    for i, byte in enumerate("II*\0".as_bytes()):
        bytes[base + 6 + i] = byte
    for entry in [60, 64, 76, 80]:
        var a = bytes[base + entry]
        var b = bytes[base + entry + 1]
        bytes[base + entry] = bytes[base + entry + 3]
        bytes[base + entry + 1] = bytes[base + entry + 2]
        bytes[base + entry + 2] = b
        bytes[base + entry + 3] = a
    var little = parse_ultrahdr(bytes)
    var big = read_ultrahdr("assets/ultrahdr/same.jpg")
    assert_true(little.image.pixels == big.image.pixels)


def test_xmp_variants() raises:
    var metadata = UltraHdrMetadata()
    # No tags, and a tag closed before it opens: nothing is read.
    _read_xmp("no tags", metadata)
    _read_xmp("a > b <", metadata)
    _read_xmp("<x:xmpmeta></x:xmpmeta>", metadata)
    assert_equal(metadata.version, "")
    # The first description is read; a blank or missing number is its
    # default; an offset that is not a number is NaN.
    _read_xmp(
        (
            '<r><rdf:Description hdrgm:Version="2" hdrgm:GainMapMin=""'
            ' hdrgm:OffsetSDR="" hdrgm:OffsetHDR="inf"'
            ' hdrgm:BaseRenditionIsHDR="True"/><rdf:Description'
            ' hdrgm:Version="3"/></r>'
        ),
        metadata,
    )
    assert_equal(metadata.version, "2")
    assert_true(metadata.base_rendition_is_hdr)
    assert_equal(metadata.gain_map_min, 0)
    assert_equal(metadata.gain_map_max, 1)
    assert_equal(metadata.offset_sdr, 0)
    assert_true(isnan(metadata.offset_hdr))
    _read_xmp('<rdf:Description hdrgm:OffsetSDR="1.5x"/>', metadata)
    assert_true(isnan(metadata.offset_sdr))
    assert_equal(metadata.version, "")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
