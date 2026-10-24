# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Opened images match Pillow's `convert("RGBA")` pixels and mode."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_image import image_file


def _python(script: String) raises -> String:
    """Return the standard output of a Python script."""
    var result = run_program(["python3", "-c", script], 30, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    return result.output


def test_opened_pixels_match_pillow() raises:
    var lines = _python(
        "import io, json, os\n"
        + "from PIL import Image\n"
        + "root = '/tmp/carla-image-match'\n"
        + "os.makedirs(root, exist_ok=True)\n"
        + "def add(name, image, kind, **kw):\n"
        + "    path = os.path.join(root, name)\n"
        + "    image.save(path, format=kind, **kw)\n"
        + "    opened = Image.open(path)\n"
        + "    doc = {'mode': opened.mode, 'width': opened.width, 'height':"
        " opened.height,\n"
        + "           'pixels': list(opened.convert('RGBA').tobytes())}\n"
        + "    open(path + '.json', 'w').write(json.dumps(doc, separators=(',',"
        " ':')))\n"
        + "    print(path)\n"
        + "add('rgb.png', Image.new('RGB', (4, 3), (10, 20, 30)), 'PNG')\n"
        + "add('gray.png', Image.new('L', (3, 2), 12), 'PNG')\n"
        + "la = Image.new('LA', (3, 2))\n"
        + "la.putpixel((0, 0), (10, 255)); la.putpixel((2, 1), (200, 4))\n"
        + "add('la.png', la, 'PNG')\n"
        + "rgba = Image.new('RGBA', (2, 2), (5, 6, 7, 8))\n"
        + "rgba.putpixel((1, 1), (1, 2, 3, 0))\n"
        + "add('rgba.png', rgba, 'PNG')\n"
        + "pal = Image.new('P', (4, 2))\n"
        + "colors = []\n"
        + "for i in range(256):\n"
        + "    colors += [i, 255 - i, i // 2]\n"
        + "pal.putpalette(colors)\n"
        + "for x in range(4):\n"
        + "    for y in range(2):\n"
        + "        pal.putpixel((x, y), x + 4 * y)\n"
        + "add('pal.png', pal, 'PNG')\n"
        + "keyed = Image.new('L', (2, 2), 10)\n"
        + "keyed.putpixel((0, 0), 0)\n"
        + "add('key.png', keyed, 'PNG', transparency=0)\n"
        + "add('color.jpg', Image.new('RGB', (6, 4), (4, 5, 6)), 'JPEG',"
        " quality=88)\n"
        + "gray = Image.new('L', (5, 3), 40)\n"
        + "gray.putpixel((1, 1), 200)\n"
        + "add('gray.jpg', gray, 'JPEG', quality=85)\n"
    )
    var count = 0
    for line in lines.splitlines():
        var path = String(line)
        if path.byte_length() == 0:
            continue
        assert_equal(image_file(path), Path(path + ".json").read_text())
        count += 1
    assert_equal(count, 8)
    with assert_raises(contains="image file is not png or jpeg"):
        _ = image_file("/tmp/carla-image-match/rgb.png.json")


def test_cli_prints_the_image() raises:
    var folder = "/tmp/carla-image-cli"
    var lines = _python(
        "import os\n"
        + "from PIL import Image\n"
        + "os.makedirs('/tmp/carla-image-cli', exist_ok=True)\n"
        + "Image.new('RGB', (2, 1), (9, 8, 7)).save("
        "'/tmp/carla-image-cli/in.png')\n"
        + "print('ok')\n"
    )
    if not String(lines).startswith("ok"):
        raise Error(lines)
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_image", folder + "/in.png"],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output)
    assert_equal(ran.output, image_file(folder + "/in.png") + "\n")
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_image"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_image FILE\n")
    var failed = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_image",
            folder + "/missing.png",
        ],
        30,
        merge_errors=False,
    )
    assert_true(failed.status != 0)
    assert_true(failed.errors.startswith("carla_image:"))


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_image"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
