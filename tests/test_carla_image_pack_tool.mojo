# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Packaged texture pixels match the resize and byte steps."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._python_json import PyJson
from tools.carla_image_pack import pack_text
from tools.carla_image_resize import resize_text, unit_bytes


def _tile(sample: String) -> String:
    """Return an 8 by 8 RGB picture filled with `sample`."""
    var out = String('{"width":8,"height":8,"bands":3,"pixels":[')
    for index in range(64):
        if index > 0:
            out += ","
        out += sample
    out += "]}"
    return out^


def test_packaged_pixels_match_the_channel_steps() raises:
    assert_equal(
        pack_text(
            '{"mode":"color","image_mode":"RGB","width":1,"height":1,'
            '"pixels":[1,2,3,4],"neutral":false,"resize":false}'
        ),
        '{"width":1,"height":1,"bands":3,"pixels":[1,2,3]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"color","image_mode":"P","width":2,"height":1,'
            '"pixels":[1,2,3,4,5,6,7,8],"neutral":false,"resize":true,'
            '"out_width":4,"out_height":1}'
        ),
        '{"width":4,"height":1,"bands":3,"pixels":[1,2,3,1,2,3,5,6,7,5,6,7]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"color","image_mode":"L","width":1,"height":1,'
            '"pixels":[9,8,7,6],"neutral":false,"resize":true,'
            '"out_width":1,"out_height":1}'
        ),
        '{"width":1,"height":1,"bands":3,"pixels":[9,9,9]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"color","image_mode":"L","width":2,"height":1,'
            '"pixels":[10,1,2,255,30,3,4,255],"neutral":false,"resize":true,'
            '"out_width":1,"out_height":1}'
        ),
        '{"width":1,"height":1,"bands":3,"pixels":[20,20,20]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"color","image_mode":"LA","width":2,"height":1,'
            '"pixels":[255,0,0,128,0,0,255,200],"neutral":false,"resize":true,'
            '"out_width":1,"out_height":1}'
        ),
        '{"width":1,"height":1,"bands":3,"pixels":[99,0,155]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"color","image_mode":"RGBA","width":2,"height":1,'
            '"pixels":[255,0,0,128,0,0,255,64],"neutral":false,"resize":true,'
            '"out_width":1,"out_height":1}'
        ),
        '{"width":1,"height":1,"bands":3,"pixels":[170,0,85]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"color","image_mode":"RGB","width":1,"height":1,'
            '"pixels":[1,2,3,9],"neutral":false,"resize":true,'
            '"out_width":1,"out_height":1}'
        ),
        '{"width":1,"height":1,"bands":3,"pixels":[1,2,3]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"color","image_mode":"RGBA","width":1,"height":1,'
            '"pixels":[255,0,0,10],"neutral":true,"resize":false}'
        ),
        _tile("255,0,0"),
    )
    assert_equal(
        pack_text(
            '{"mode":"color","image_mode":"RGB","width":2,"height":2,'
            '"pixels":[10,0,0,255,30,0,0,255,50,0,0,255,70,0,0,255],'
            '"neutral":true,"resize":false}'
        ),
        _tile("40,0,0"),
    )
    assert_equal(
        pack_text(
            '{"mode":"color","image_mode":"L","width":1,"height":1,'
            '"pixels":[255,0,0,10],"neutral":true,"resize":true,'
            '"out_width":1,"out_height":1}'
        ),
        '{"width":1,"height":1,"bands":3,"pixels":[255,0,0]}',
    )
    var color = String("[1,2,3,255,4,5,6,255,7,8,9,255,10,11,12,255]")
    assert_equal(
        pack_text(
            '{"mode":"masked","width":2,"height":2,"color":'
            + color
            + ',"mask_mode":"L","mask_width":2,"mask_height":2,'
            '"mask":[10,10,10,255,20,20,20,255,30,30,30,255,40,40,40,255],'
            '"resize":false}'
        ),
        '{"width":2,"height":2,"bands":4,"pixels":[1,2,3,10,4,5,6,20,7,8,9,30,10,11,12,40]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"masked","width":2,"height":2,"color":'
            + color
            + ',"mask_mode":"LA","mask_width":2,"mask_height":2,'
            '"mask":[0,0,0,9,0,0,0,8,0,0,0,7,0,0,0,6],"resize":false}'
        ),
        '{"width":2,"height":2,"bands":4,"pixels":[1,2,3,9,4,5,6,8,7,8,9,7,10,11,12,6]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"masked","width":2,"height":2,"color":'
            + color
            + ',"mask_mode":"RGBA","mask_width":2,"mask_height":2,'
            '"mask":[0,0,0,9,0,0,0,8,0,0,0,7,0,0,0,6],"resize":false}'
        ),
        '{"width":2,"height":2,"bands":4,"pixels":[1,2,3,9,4,5,6,8,7,8,9,7,10,11,12,6]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"masked","width":1,"height":1,"color":[1,2,3,255],'
            '"mask_mode":"RGB","mask_width":1,"mask_height":1,'
            '"mask":[128,255,128,255],"resize":false}'
        ),
        '{"width":1,"height":1,"bands":4,"pixels":[1,2,3,255]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"masked","width":2,"height":2,"color":'
            + color
            + ',"mask_mode":"LA","mask_width":1,"mask_height":1,'
            '"mask":[0,0,0,40],"resize":false}'
        ),
        '{"width":2,"height":2,"bands":4,"pixels":[1,2,3,40,4,5,6,40,7,8,9,40,10,11,12,40]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"masked","width":2,"height":2,"color":'
            + color
            + ',"mask_mode":"RGBA","mask_width":2,"mask_height":1,'
            '"mask":[0,0,0,40,0,0,0,80],"resize":false}'
        ),
        '{"width":2,"height":2,"bands":4,"pixels":[1,2,3,40,4,5,6,80,7,8,9,40,10,11,12,80]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"masked","width":2,"height":1,"color":[255,0,0,128,0,0,255,64],'
            '"mask_mode":"LA","mask_width":2,"mask_height":1,'
            '"mask":[0,0,0,128,0,0,0,64],"resize":true,"out_width":1,"out_height":1}'
        ),
        '{"width":1,"height":1,"bands":4,"pixels":[170,0,85,96]}',
    )
    assert_equal(
        pack_text(
            '{"mode":"stitch","width":2,"height":2,'
            '"left":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],'
            '"right":[16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1]}'
        ),
        '{"width":4,"height":2,"bands":4,"pixels":[1,2,3,4,5,6,7,8,16,15,14,13,12,11,10,9,9,10,11,12,13,14,15,16,8,7,6,5,4,3,2,1]}',
    )
    with assert_raises(contains="pack request is not an object"):
        _ = pack_text("[]")
    with assert_raises(
        contains="mode is not color, masked, stitch, atlas or quantize"
    ):
        _ = pack_text('{"mode":1}')
    with assert_raises(
        contains="mode is not color, masked, stitch, atlas or quantize"
    ):
        _ = pack_text('{"mode":"near"}')
    with assert_raises(contains="size is not an integer"):
        _ = pack_text(
            '{"mode":"color","image_mode":"RGB","width":1.5,"height":1,'
            '"pixels":[1,2,3,4],"neutral":false,"resize":false}'
        )
    with assert_raises(contains="size is not positive"):
        _ = pack_text(
            '{"mode":"color","image_mode":"RGB","width":0,"height":1,'
            '"pixels":[],"neutral":false,"resize":false}'
        )
    with assert_raises(contains="pixels do not match the image"):
        _ = pack_text(
            '{"mode":"color","image_mode":"RGB","width":1,"height":1,'
            '"pixels":1,"neutral":false,"resize":false}'
        )
    with assert_raises(contains="pixels do not match the image"):
        _ = pack_text(
            '{"mode":"color","image_mode":"RGB","width":1,"height":1,'
            '"pixels":[1],"neutral":false,"resize":false}'
        )
    with assert_raises(contains="pixel is not an integer"):
        _ = pack_text(
            '{"mode":"color","image_mode":"RGB","width":1,"height":1,'
            '"pixels":[1,2,3,1.5],"neutral":false,"resize":false}'
        )
    with assert_raises(contains="pixel is out of range"):
        _ = pack_text(
            '{"mode":"color","image_mode":"RGB","width":1,"height":1,'
            '"pixels":[1,2,3,-1],"neutral":false,"resize":false}'
        )
    with assert_raises(contains="pixel is out of range"):
        _ = pack_text(
            '{"mode":"color","image_mode":"RGB","width":1,"height":1,'
            '"pixels":[1,2,3,256],"neutral":false,"resize":false}'
        )
    with assert_raises(contains="flag is not a bool"):
        _ = pack_text(
            '{"mode":"color","image_mode":"RGB","width":1,"height":1,'
            '"pixels":[1,2,3,4],"neutral":1,"resize":false}'
        )
    with assert_raises(contains="image mode is not text"):
        _ = pack_text(
            '{"mode":"color","image_mode":1,"width":1,"height":1,'
            '"pixels":[1,2,3,4],"neutral":false,"resize":false}'
        )
    with assert_raises(contains="size is not positive"):
        _ = pack_text(
            '{"mode":"color","image_mode":"RGB","width":1,"height":1,'
            '"pixels":[1,2,3,4],"neutral":false,"resize":true,'
            '"out_width":0,"out_height":1}'
        )
    with assert_raises(contains="pixels do not match the image"):
        _ = pack_text(
            '{"mode":"masked","width":1,"height":1,"color":[1],'
            '"mask_mode":"L","mask_width":1,"mask_height":1,"mask":[0,0,0,1],'
            '"resize":false}'
        )
    with assert_raises(contains="pixels do not match the image"):
        _ = pack_text(
            '{"mode":"stitch","width":1,"height":1,"left":[1],"right":[1,2,3,4]}'
        )


def _joined(pixels: List[Int]) -> String:
    """Return `pixels` as a JSON number list."""
    var out = String()
    for index in range(len(pixels)):
        if index > 0:
            out += ","
        out += String(pixels[index])
    return out


def _picture(width: Int, height: Int, bands: Int, pixels: List[Int]) -> String:
    """Return the packaged JSON for one picture."""
    return (
        '{"width":'
        + String(width)
        + ',"height":'
        + String(height)
        + ',"bands":'
        + String(bands)
        + ',"pixels":['
        + _joined(pixels)
        + "]}"
    )


def _resize_bytes(
    pixels: List[Int],
    width: Int,
    height: Int,
    bands: Int,
    out_width: Int,
    out_height: Int,
) raises -> List[Int]:
    """Return one Lanczos resize as bytes."""
    var request = (
        '{"mode":"lanczos","width":'
        + String(width)
        + ',"height":'
        + String(height)
        + ',"bands":'
        + String(bands)
        + ',"out_width":'
        + String(out_width)
        + ',"out_height":'
        + String(out_height)
        + ',"pixels":['
        + _joined(pixels)
        + "]}"
    )
    var doc = PyJson.parse(resize_text(request))
    var node = doc.at(doc.root, "pixels")
    var out = List[Int]()
    for index in range(doc.length(node)):
        out.append(Int(doc.text(doc.item(node, index))))
    return out^


def test_an_atlas_matches_quantize_resize_and_stitch() raises:
    var left = List[Float64]()
    for value in [
        1.0,
        0.0,
        0.0,
        1.0,
        0.0,
        1.0,
        0.0,
        1.0,
        0.0,
        0.0,
        1.0,
        0.5,
        1.0,
        1.0,
        1.0,
        0.0,
    ]:
        left.append(value)
    var right = List[Float64]()
    for value in [
        0.25,
        0.5,
        0.75,
        1.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.5,
        0.5,
        0.5,
        0.5,
    ]:
        right.append(value)
    var size = 2
    var left_bytes = _resize_bytes(unit_bytes(left), 2, 2, 4, size, size)
    var right_bytes = _resize_bytes(unit_bytes(right), 2, 2, 4, size, size)
    var row = size * 4
    var atlas = List[Int]()
    for y in range(size):
        var start = y * row
        for offset in range(row):
            atlas.append(left_bytes[start + offset])
        for offset in range(row):
            atlas.append(right_bytes[start + offset])
    var views = (
        "[[[1,0,0,1],[0,1,0,1]],[[0,0,1,0.5],[1,1,1,0]]],"
        "[[[0.25,0.5,0.75,1],[1,0,0,0]],[[0,0,0,1],[0.5,0.5,0.5,0.5]]]"
    )
    var request = '{"mode":"atlas","size":2,"views":[' + views + "]}"
    assert_equal(pack_text(request), _picture(size * 2, size, 4, atlas))
    with assert_raises(contains="atlas needs two views"):
        _ = pack_text('{"mode":"atlas","size":2,"views":[]}')
    with assert_raises(contains="image is empty"):
        _ = pack_text('{"mode":"atlas","size":2,"views":[[],[[1,0,0,1]]]}')


def test_a_float_picture_becomes_bytes() raises:
    var image = "[[[1.2,-0.2,0.5],[0,1,0.0]],[[0.5,0.5,0.5],[1,1,1]]]"
    var samples = List[Float64]()
    for value in [
        1.2,
        -0.2,
        0.5,
        0.0,
        1.0,
        0.0,
        0.5,
        0.5,
        0.5,
        1.0,
        1.0,
        1.0,
    ]:
        samples.append(value)
    assert_equal(
        pack_text('{"mode":"quantize","image":' + image + "}"),
        _picture(2, 2, 3, unit_bytes(samples)),
    )
    with assert_raises(contains="pixel is not RGB or RGBA"):
        _ = pack_text('{"mode":"quantize","image":[[[1,2]]]}')
    with assert_raises(contains="image is empty"):
        _ = pack_text('{"mode":"quantize","image":[]}')


def test_the_command_prints_the_pixels_and_refuses_bad_use() raises:
    var root = mkdtemp(prefix="test image pack ")
    var path = root + "/pack.json"
    Path(path).write_text(
        '{"mode":"color","image_mode":"RGB","width":1,"height":1,'
        '"pixels":[1,2,3,4],"neutral":false,"resize":false}'
    )
    var printed = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_image_pack", path],
        30,
        merge_errors=False,
    )
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output, '{"width":1,"height":1,"bands":3,"pixels":[1,2,3]}\n'
    )
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_image_pack"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_image_pack FILE\n")
    var failed = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_image_pack",
            root + "/missing.json",
        ],
        30,
        merge_errors=False,
    )
    assert_true(failed.status != 0)
    assert_true(failed.errors.startswith("carla_image_pack:"))
    Path(path).write_text("{")
    var bad = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_image_pack", path],
        30,
        merge_errors=False,
    )
    assert_true(bad.status != 0)
    assert_true(bad.errors.startswith("carla_image_pack:"))
    _ = run_program(["rm", "-rf", root], 10)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_image_pack"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    var resize = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_image_resize"],
        180,
    )
    if resize.status != 0:
        raise Error(resize.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
