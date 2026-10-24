# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The packaged size and encoding of a CARLA texture.

A neutral file name becomes an 8 pixel square, then the size limit is
applied. Python's round chooses the fitted size. Color is JPEG at
quality 88. A neutral data texture is an optimized JPEG. A mask stays
an optimized PNG.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_texture_plan import plan_text


def _texture(
    path: String, color: Bool, limit: Int, width: Int, height: Int
) -> String:
    """Return one texture request."""
    var flag = "true"
    if not color:
        flag = "false"
    return (
        '{"mode":"texture","path":"'
        + path
        + '","color":'
        + flag
        + ',"max":'
        + String(limit)
        + ',"width":'
        + String(width)
        + ',"height":'
        + String(height)
        + "}"
    )


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test texture plan ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    _ = run_program(["rm", "-rf", root], 10)


def _cli(path: String) raises -> ProcessResult:
    """Run the built program. An empty path omits the file argument."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_texture_plan")
    if path.byte_length() > 0:
        command.append(path)
    return run_program(command, 30, merge_errors=False)


def _python(script: String) raises -> String:
    """Return the standard output of a Python script."""
    var result = run_program(["python3", "-c", script], 20, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    return result.output


def test_a_neutral_name_becomes_a_flat_square() raises:
    assert_equal(
        plan_text(_texture("/cars/BMW_Logo.png", True, 1024, 64, 32)),
        '{"neutral":true,"width":8,"height":8,"resize":false,"format":"JPEG","quality":88,"optimize":false}',
    )
    assert_equal(
        plan_text(_texture("/tex/t_banner_extra.PNG", False, 1024, 64, 32)),
        '{"neutral":true,"width":8,"height":8,"resize":false,"format":"JPEG","quality":-1,"optimize":true}',
    )
    assert_equal(
        plan_text(
            '{"mode":"texture","path":"C:\\\\tex\\\\BMW_Logo.png","color":true,"max":1024,"width":64,"height":32}'
        ),
        '{"neutral":true,"width":8,"height":8,"resize":false,"format":"JPEG","quality":88,"optimize":false}',
    )
    assert_equal(
        plan_text(_texture("/cars/sm_banner.png", False, 1024, 4, 4)),
        '{"neutral":false,"width":4,"height":4,"resize":false,"format":"PNG","quality":-1,"optimize":true}',
    )
    assert_equal(
        plan_text(_texture("/cars/ordinary.tar.png", True, 2, 5, 4)),
        '{"neutral":false,"width":2,"height":2,"resize":true,"format":"JPEG","quality":88,"optimize":false}',
    )


def test_a_mask_keeps_png_and_the_limit_uses_python_round() raises:
    assert_equal(
        plan_text('{"mode":"fit","max":4,"width":8,"height":3}'),
        '{"neutral":false,"width":4,"height":2,"resize":true,"format":"PNG","quality":-1,"optimize":true}',
    )
    assert_equal(
        plan_text(_texture("/cars/bmw_logo.png", True, 4, 64, 32)),
        '{"neutral":true,"width":4,"height":4,"resize":true,"format":"JPEG","quality":88,"optimize":false}',
    )
    var lines = _python(
        "import json, os, random, re\n"
        + "neutral ="
        " re.compile(r'^(bmw_logo|vh_car_mercedesbenzcoupe_mercedestopmat_basecolor|vh_car_minicoopers_minimat|t_carlacola_d|vh_truck_carlacola_bodyworkmat_basecolor|t_billboard_d|sm_banner_|t_banner)',"
        " re.I)\n"
        + "stems = ['bmw_logo', 'BMW_LOGO_x', 'xbmw_logo', 'sm_banner_',"
        " 'sm_banner', 't_banner', 't_billboard_d',"
        " 'vh_car_minicoopers_minimat_extra', 'ordinary', 't_carlacola_d']\n"
        + "rng = random.Random(761)\n"
        + "for _ in range(200):\n"
        + "    stem = rng.choice(stems)\n"
        + "    path = '/Game/' + stem + rng.choice(['.png', '.jpg', '.tar.png',"
        " ''])\n"
        + "    color = rng.choice([True, False])\n"
        + "    masked = rng.choice([True, False])\n"
        + "    width = rng.randrange(1, 4000)\n"
        + "    height = rng.randrange(1, 4000)\n"
        + "    limit = rng.randrange(1, 3000)\n"
        + "    mode = 'fit' if masked else 'texture'\n"
        + "    is_neutral = (not masked) and"
        " bool(neutral.search(os.path.splitext(os.path.basename(path))[0]))\n"
        + "    w, h = (8, 8) if is_neutral else (width, height)\n"
        + "    big = max(w, h)\n"
        + "    resize = False\n"
        + "    if big > limit:\n"
        + "        scale = limit / big\n"
        + "        w2 = max(1, round(w * scale))\n"
        + "        h2 = max(1, round(h * scale))\n"
        + "        resize = (w2, h2) != (w, h)\n"
        + "        w, h = w2, h2\n"
        + "    if masked:\n"
        + "        fmt, quality, optimize, is_neutral = 'PNG', -1, True,"
        " False\n"
        + "    elif color:\n"
        + "        fmt, quality, optimize = 'JPEG', 88, False\n"
        + "    elif is_neutral:\n"
        + "        fmt, quality, optimize = 'JPEG', -1, True\n"
        + "    else:\n"
        + "        fmt, quality, optimize = 'PNG', -1, True\n"
        + "    request = {'mode': mode, 'path': path, 'color': color, 'max':"
        " limit, 'width': width, 'height': height}\n"
        + "    answer = {'neutral': is_neutral, 'width': w, 'height': h,"
        " 'resize': resize, 'format': fmt, 'quality': quality, 'optimize':"
        " optimize}\n"
        + "    print(json.dumps(request, separators=(',', ':')))\n"
        + "    print(json.dumps(answer, separators=(',', ':')))\n"
    )
    var pending = String("")
    var count = 0
    for line in lines.splitlines():
        var text = String(line)
        if text.byte_length() == 0:
            continue
        if pending.byte_length() == 0:
            pending = text
            continue
        assert_equal(plan_text(pending), text)
        pending = ""
        count += 1
    assert_equal(count, 200)


def test_a_bad_plan_is_refused() raises:
    with assert_raises(contains="texture plan is not an object"):
        _ = plan_text("[]")
    with assert_raises(contains="texture mode is not texture or fit"):
        _ = plan_text('{"mode":"other","width":1,"height":1,"max":1}')
    with assert_raises(contains="image size is not positive"):
        _ = plan_text('{"mode":"fit","width":0,"height":0,"max":1}')
    with assert_raises(contains="image size is negative"):
        _ = plan_text('{"mode":"fit","width":-1,"height":1,"max":1}')
    with assert_raises(contains="color is not a bool"):
        _ = plan_text(
            '{"mode":"texture","path":"a.png","color":1,"max":1,"width":1,"height":1}'
        )


def test_the_command_prints_the_plan_and_refuses_bad_use() raises:
    var root = _dir()
    var path = root + "/plan.json"
    Path(path).write_text(_texture("/cars/ordinary.png", False, 8, 4, 4))
    var printed = _cli(path)
    assert_equal(printed.status, 0)
    assert_equal(printed.errors, "")
    assert_equal(
        printed.output,
        '{"neutral":false,"width":4,"height":4,"resize":false,"format":"PNG","quality":-1,"optimize":true}\n',
    )
    var usage = _cli("")
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_texture_plan FILE\n")
    var failed = _cli(root + "/missing.json")
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_texture_plan:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_texture_plan"],
        120,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
