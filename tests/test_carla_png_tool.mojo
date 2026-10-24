# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""PNG bytes match Pillow 12.3 `Image.save` for `L`, `RGB` and `RGBA`."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_png import png_text


def _python(script: String) raises -> String:
    """Return the standard output of a Python script."""
    var result = run_program(["python3", "-c", script], 30, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    return result.output


def _same(left: List[UInt8], right: List[UInt8]) raises:
    """Require two byte strings to be identical."""
    assert_equal(len(left), len(right))
    for index in range(len(left)):
        if left[index] != right[index]:
            raise Error("png byte " + String(index))


def test_png_bytes_match_pillow() raises:
    var folder = "/tmp/carla-png-match"
    var lines = _python(
        "import io, json, os, random\n"
        + "from PIL import Image\n"
        + "root = '/tmp/carla-png-match'\n"
        + "os.makedirs(root, exist_ok=True)\n"
        + "rng = random.Random(761)\n"
        + "def add(name, mode, w, h, optimize, pixels=None):\n"
        + "    bands = {'L': 1, 'RGB': 3, 'RGBA': 4}[mode]\n"
        + "    if pixels is None:\n"
        + "        pixels = [rng.randrange(256) for _ in range(w * h *"
        " bands)]\n"
        + "    req = {'mode': mode, 'width': w, 'height': h, 'optimize':"
        " optimize, 'pixels': pixels}\n"
        + "    im = Image.frombytes(mode, (w, h), bytes(pixels))\n"
        + "    buf = io.BytesIO()\n"
        + "    im.save(buf, format='PNG', optimize=optimize)\n"
        + "    open(os.path.join(root, name + '.json'), 'w').write("
        "json.dumps(req, separators=(',', ':')))\n"
        + "    open(os.path.join(root, name + '.png'),"
        " 'wb').write(buf.getvalue())\n"
        + "    print(name)\n"
        + "add('l1', 'L', 1, 1, True, [0])\n"
        + "add('l0', 'L', 1, 1, False, [200])\n"
        + "add('rgb1', 'RGB', 1, 1, True, [1, 2, 3])\n"
        + "add('grid', 'RGB', 8, 8, True)\n"
        + "add('plain', 'RGB', 8, 8, False)\n"
        + "add('rgba', 'RGBA', 5, 3, True)\n"
        + "add('flat', 'RGBA', 5, 3, False)\n"
        + "add('row', 'L', 64, 2, True)\n"
        + "add('solid', 'RGB', 8, 8, True, [12, 34, 56] * 64)\n"
        + "add('wide', 'RGB', 200, 160, True)\n"
    )
    var count = 0
    for line in lines.splitlines():
        var name = String(line)
        if name.byte_length() == 0:
            continue
        var got = png_text(Path(folder + "/" + name + ".json").read_text())
        var expected = Path(folder + "/" + name + ".png").read_bytes()
        _same(got, expected)
        count += 1
    assert_equal(count, 10)
    with assert_raises(contains="png mode is not L, RGB or RGBA"):
        _ = png_text(
            '{"mode":"CMYK","width":1,"height":1,"optimize":true,"pixels":[0]}'
        )
    with assert_raises(contains="png size is not positive"):
        _ = png_text(
            '{"mode":"L","width":0,"height":1,"optimize":true,"pixels":[]}'
        )
    with assert_raises(contains="png pixels do not match the image"):
        _ = png_text(
            '{"mode":"L","width":1,"height":1,"optimize":false,"pixels":[1,2]}'
        )
    with assert_raises(contains="optimize is not a bool"):
        _ = png_text(
            '{"mode":"L","width":1,"height":1,"optimize":1,"pixels":[0]}'
        )
    with assert_raises(contains="png request is not an object"):
        _ = png_text("[]")


def test_cli_writes_the_file() raises:
    var folder = "/tmp/carla-png-cli"
    _ = _python(
        "import os\n"
        + "os.makedirs('/tmp/carla-png-cli', exist_ok=True)\n"
        + "open('/tmp/carla-png-cli/in.json','w').write("
        + '\'{"mode":"RGB","width":2,"height":1,"optimize":true,"pixels":'
        + "[9,8,7,6,5,4]}')\n"
        + "print('ok')\n"
    )
    var wrote = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_png",
            folder + "/in.json",
            folder + "/out.png",
        ],
        60,
    )
    if wrote.status != 0:
        raise Error(wrote.output)
    var got = Path(folder + "/out.png").read_bytes()
    var expected = png_text(Path(folder + "/in.json").read_text())
    _same(got, expected)
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_png"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_png REQUEST OUT\n")
    Path(folder + "/bad.json").write_text("{")
    var failed = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_png",
            folder + "/bad.json",
            folder + "/out.png",
        ],
        30,
        merge_errors=False,
    )
    assert_true(failed.status != 0)
    assert_true(failed.errors.startswith("carla_png:"))


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_png"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
