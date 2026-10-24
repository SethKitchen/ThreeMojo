# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Packaged texture pixels match the Python channel steps."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_image_pack import pack_text


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
    with assert_raises(contains="mode is not color, masked, stitch or atlas"):
        _ = pack_text('{"mode":1}')
    with assert_raises(contains="mode is not color, masked, stitch or atlas"):
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


def test_an_atlas_matches_quantize_resize_and_stitch() raises:
    var views = (
        "[[[1,0,0,1],[0,1,0,1]],[[0,0,1,0.5],[1,1,1,0]]],"
        "[[[0.25,0.5,0.75,1],[1,0,0,0]],[[0,0,0,1],[0.5,0.5,0.5,0.5]]]"
    )
    var request = '{"mode":"atlas","size":2,"views":[' + views + "]}"
    var script = (
        "import json, sys\n"
        + "sys.path.insert(0, 'assets/carla/tools/export')\n"
        + "import carla_gltf_fix as fix\n"
        + "views = json.loads(sys.argv[1])\n"
        + "size = 2\n"
        + "resized = []\n"
        + "for view in views:\n"
        + "    flat = [c for row in view for px in row for c in px]\n"
        + "    raw = fix.quantize_image(flat)\n"
        + "    resized.append(fix.resize_image(raw, len(view[0]), len(view), 4,"
        " size, size, 'lanczos'))\n"
        + "row = size * 4\n"
        + "atlas = []\n"
        + "for y in range(size):\n"
        + "    start = y * row\n"
        + "    atlas.extend(resized[0][start:start + row])\n"
        + "    atlas.extend(resized[1][start:start + row])\n"
        + "print(json.dumps({'width': size * 2, 'height': size, 'bands': 4,"
        " 'pixels': atlas}, separators=(',', ':')), end='')\n"
    )
    var result = run_program(
        ["python3", "-c", script, "[" + views + "]"],
        30,
        merge_errors=False,
    )
    if result.status != 0:
        raise Error(result.errors)
    assert_equal(pack_text(request), result.output)
    with assert_raises(contains="atlas needs two views"):
        _ = pack_text('{"mode":"atlas","size":2,"views":[]}')
    with assert_raises(contains="image is empty"):
        _ = pack_text('{"mode":"atlas","size":2,"views":[[],[[1,0,0,1]]]}')


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
    TestSuite.discover_tests[__functions_in_module()]().run()
