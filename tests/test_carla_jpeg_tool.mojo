# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""JPEG bytes match Pillow 12.3 `Image.save` for `L` and `RGB`."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_jpeg import jpeg_text


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
            raise Error("jpeg byte " + String(index))


def test_jpeg_bytes_match_pillow() raises:
    var folder = "/tmp/carla-jpeg-match"
    var lines = _python(
        "import io, json, os, random\n"
        + "from PIL import Image\n"
        + "root = '/tmp/carla-jpeg-match'\n"
        + "os.makedirs(root, exist_ok=True)\n"
        + "rng = random.Random(761)\n"
        + "def add(name, mode, w, h, quality, optimize, pixels=None):\n"
        + "    bands = {'L': 1, 'RGB': 3}[mode]\n"
        + "    if pixels is None:\n"
        + "        pixels = [rng.randrange(256) for _ in range(w * h *"
        " bands)]\n"
        + "    req = {'mode': mode, 'width': w, 'height': h, 'quality':"
        " quality,\n"
        + "           'optimize': optimize, 'pixels': pixels}\n"
        + "    im = Image.frombytes(mode, (w, h), bytes(pixels))\n"
        + "    kw = {}\n"
        + "    if quality >= 0:\n"
        + "        kw['quality'] = quality\n"
        + "    if optimize:\n"
        + "        kw['optimize'] = True\n"
        + "    buf = io.BytesIO()\n"
        + "    im.save(buf, format='JPEG', **kw)\n"
        + "    open(os.path.join(root, name + '.json'), 'w').write("
        "json.dumps(req, separators=(',', ':')))\n"
        + "    open(os.path.join(root, name + '.jpg'),"
        " 'wb').write(buf.getvalue())\n"
        + "    print(name)\n"
        + "add('q88', 'RGB', 8, 8, 88, False)\n"
        + "add('q85', 'RGB', 5, 3, 85, False)\n"
        + "add('opt', 'RGB', 8, 8, -1, True, [12, 34, 56] * 64)\n"
        + "add('gray', 'L', 4, 2, 85, False)\n"
        + "add('odd', 'RGB', 3, 1, 75, False, [1, 2, 3, 4, 5, 6, 7, 8, 9])\n"
        + "add('default', 'RGB', 2, 2, -1, False, [1, 2, 3, 4, 5, 6, 9, 8, 7,"
        " 6, 5, 4])\n"
        + "add('wide', 'RGB', 48, 36, 88, False)\n"
    )
    var count = 0
    for line in lines.splitlines():
        var name = String(line)
        if name.byte_length() == 0:
            continue
        var got = jpeg_text(Path(folder + "/" + name + ".json").read_text())
        var expected = Path(folder + "/" + name + ".jpg").read_bytes()
        _same(got, expected)
        count += 1
    assert_equal(count, 7)
    with assert_raises(contains="jpeg mode is not L or RGB"):
        _ = jpeg_text(
            '{"mode":"RGBA","width":1,"height":1,"quality":88,"optimize":false,"pixels":[0,0,0,0]}'
        )
    with assert_raises(contains="jpeg size is not positive"):
        _ = jpeg_text(
            '{"mode":"L","width":0,"height":1,"quality":85,"optimize":false,"pixels":[]}'
        )
    with assert_raises(contains="jpeg quality is out of range"):
        _ = jpeg_text(
            '{"mode":"L","width":1,"height":1,"quality":101,"optimize":false,"pixels":[0]}'
        )
    with assert_raises(contains="optimize is not a bool"):
        _ = jpeg_text(
            '{"mode":"L","width":1,"height":1,"quality":85,"optimize":1,"pixels":[0]}'
        )
    with assert_raises(contains="jpeg request is not an object"):
        _ = jpeg_text("[]")


def test_cli_writes_the_file() raises:
    var folder = "/tmp/carla-jpeg-cli"
    _ = _python(
        "import os\n"
        + "os.makedirs('/tmp/carla-jpeg-cli', exist_ok=True)\n"
        + "open('/tmp/carla-jpeg-cli/in.json','w').write("
        + '\'{"mode":"RGB","width":2,"height":1,"quality":88,"optimize":false,'
        + '"pixels":[9,8,7,6,5,4]}\')\n'
        + "print('ok')\n"
    )
    var wrote = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_jpeg",
            folder + "/in.json",
            folder + "/out.jpg",
        ],
        60,
    )
    if wrote.status != 0:
        raise Error(wrote.output)
    var got = Path(folder + "/out.jpg").read_bytes()
    var expected = jpeg_text(Path(folder + "/in.json").read_text())
    _same(got, expected)
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_jpeg"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_jpeg REQUEST OUT\n")
    Path(folder + "/bad.json").write_text("{")
    var failed = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_jpeg",
            folder + "/bad.json",
            folder + "/out.jpg",
        ],
        30,
        merge_errors=False,
    )
    assert_true(failed.status != 0)
    assert_true(failed.errors.startswith("carla_jpeg:"))


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_jpeg"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
