# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Packaged texture files match Pillow's encoder and keep cut-out pixels."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_image import image_file
from tools.carla_texture_store import store_text


def _python(script: String) raises -> String:
    """Return the standard output of a Python script."""
    var result = run_program(["python3", "-c", script], 30, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    return result.output


def _ready() raises:
    """Write the fixture images and the Pillow files they must match."""
    var lines = _python(
        "import io, os\n"
        + "from PIL import Image\n"
        + "root = '/tmp/carla-texture-store'\n"
        + "os.makedirs(root + '/out', exist_ok=True)\n"
        + "original = Image.new('RGB', (4, 4), (192, 64, 16))\n"
        + "original.paste((0, 128, 32), (2, 0, 4, 4))\n"
        + "original.save(root + '/ordinary.png')\n"
        + "original.save(root + '/bmw_logo.png')\n"
        + "Image.new('RGB', (4, 4), (255, 0, 0)).save(root + '/red.png')\n"
        + "Image.new('L', (4, 4), 255).save(root + '/mask.png')\n"
        + "Image.new('L', (4, 4), 0).save(root + '/clear.png')\n"
        + "def keep(image, name, kind, **kw):\n"
        + "    buf = io.BytesIO()\n"
        + "    image.save(buf, format=kind, **kw)\n"
        + "    open(root + '/' + name, 'wb').write(buf.getvalue())\n"
        + "keep(original, 'color.jpg', 'JPEG', quality=88)\n"
        + "keep(original, 'data.png', 'PNG', optimize=True)\n"
        + "flat = Image.new('RGB', (8, 8), (96, 96, 24))\n"
        + "keep(flat, 'neutral.jpg', 'JPEG', quality=88)\n"
        + "keep(flat, 'neutral-data.jpg', 'JPEG', optimize=True)\n"
        + "print('ok')\n"
    )
    if not String(lines).startswith("ok"):
        raise Error(lines)


def _color(source: String, color: Bool, folder: String) raises -> String:
    """Package one color texture and return its URI."""
    var flag = String("false")
    if color:
        flag = "true"
    var text = String('{"op":"color","out_dir":"')
    text += folder
    text += '","max_size":512,"source":"'
    text += source
    text += '","color":'
    text += flag
    text += "}"
    var doc = store_text(text)
    return doc


def _uri(doc: String) -> String:
    """Return the URI from a store result."""
    var prefix = String('{"uri":"')
    var start = prefix.byte_length()
    var end = doc.byte_length() - 2
    return String(doc[byte=start:end])


def test_packaged_bytes_match_pillow() raises:
    _ready()
    var root = String("/tmp/carla-texture-store")
    var cases = List[String]()
    cases.append(
        "ordinary.png|true|" + root + "/color-out|" + root + "/color.jpg"
    )
    cases.append(
        "ordinary.png|false|" + root + "/data-out|" + root + "/data.png"
    )
    cases.append(
        "bmw_logo.png|true|" + root + "/neutral-out|" + root + "/neutral.jpg"
    )
    cases.append(
        "bmw_logo.png|false|"
        + root
        + "/neutral-data-out|"
        + root
        + "/neutral-data.jpg"
    )
    for row in cases:
        var parts = row.split("|")
        var source = String(parts[0])
        var color = String(parts[1]) == "true"
        var folder = String(parts[2])
        var expected = String(parts[3])
        var doc = _color(root + "/" + source, color, folder)
        var uri = _uri(doc)
        var stored = Path(folder + "/" + uri).read_bytes()
        assert_equal(stored, Path(expected).read_bytes())
        assert_true(uri.startswith("textures/texture_"))


def test_a_cut_out_keeps_the_color_and_the_mask() raises:
    _ready()
    var root = String("/tmp/carla-texture-store")
    var opaque = store_text(
        '{"op":"masked","out_dir":"'
        + root
        + '/mask-out","max_size":512,"color":"'
        + root
        + '/red.png","mask":"'
        + root
        + '/mask.png"}'
    )
    var clear = store_text(
        '{"op":"masked","out_dir":"'
        + root
        + '/clear-out","max_size":512,"color":"'
        + root
        + '/red.png","mask":"'
        + root
        + '/clear.png"}'
    )
    var opaque_uri = _uri(opaque)
    var clear_uri = _uri(clear)
    assert_true(opaque_uri != clear_uri)
    var kept = image_file(root + "/mask-out/" + opaque_uri)
    assert_true(kept.find('"pixels":[255,0,0,255') >= 0)
    var gone = image_file(root + "/clear-out/" + clear_uri)
    assert_true(gone.find('"pixels":[255,0,0,0') >= 0)
    var again = store_text(
        '{"op":"masked","out_dir":"'
        + root
        + '/mask-out","max_size":512,"color":"'
        + root
        + '/red.png","mask":"'
        + root
        + '/mask.png"}'
    )
    assert_equal(again, opaque)


def test_cli_writes_the_file() raises:
    _ready()
    var root = String("/tmp/carla-texture-store")
    var path = root + "/cli.json"
    Path(path).write_text(
        '{"op":"color","out_dir":"'
        + root
        + '/cli-out","max_size":512,"source":"'
        + root
        + '/ordinary.png","color":true}'
    )
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_texture_store", path],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_equal(ran.output, store_text(Path(path).read_text()) + "\n")
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_texture_store"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_texture_store FILE\n")
    with assert_raises(contains="op is not color or masked"):
        _ = store_text('{"op":"other","out_dir":"/tmp","max_size":8}')
    with assert_raises(contains="store request is not an object"):
        _ = store_text("[]")
    with assert_raises(contains="max_size is negative"):
        _ = store_text(
            '{"op":"color","out_dir":"/tmp","max_size":-1,"source":"a","color":true}'
        )


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_texture_store"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
