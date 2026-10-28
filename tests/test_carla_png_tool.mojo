# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""PNG bytes match Pillow 12.3 `Image.save` for `L`, `RGB` and `RGBA`.

The digests are those of Pillow 12.3.0's output for the same requests. The
random pixels come from Python's `random.Random(761)`, as Pillow saw them.
"""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._golden import digest, int_list, random_bytes
from tests._tree import tool_mojo
from tests.test_scratch import TestScratch, temporary_path
from tools._process import run_program
from tools._python_random import PythonRandom
from tools.carla_png import png_text


def _same(left: List[UInt8], right: List[UInt8]) raises:
    """Require two byte strings to be identical."""
    assert_equal(len(left), len(right))
    for index in range(len(left)):
        if left[index] != right[index]:
            raise Error("png byte " + String(index))


def _bands(mode: String) -> Int:
    """Return the samples per pixel of a Pillow mode."""
    if mode == "L":
        return 1
    return 3 if mode == "RGB" else 4


def _check(
    mut rng: PythonRandom,
    mode: String,
    width: Int,
    height: Int,
    optimize: Bool,
    var pixels: List[Int],
    expected: String,
) raises:
    """Require one request to produce Pillow's PNG digest.

    An empty `pixels` draws `width * height` random pixels from `rng`.
    """
    if len(pixels) == 0:
        pixels = random_bytes(rng, width * height * _bands(mode))
    var request = (
        '{"mode":"'
        + mode
        + '","width":'
        + String(width)
        + ',"height":'
        + String(height)
        + ',"optimize":'
        + ("true" if optimize else "false")
        + ',"pixels":'
        + int_list(pixels)
        + "}"
    )
    assert_equal(digest(png_text(request)), expected, mode)


def test_png_bytes_match_pillow() raises:
    var rng = PythonRandom(761)
    var none = List[Int]()
    _check(
        rng,
        "L",
        1,
        1,
        True,
        [0],
        "a4d4c009619311d9b83904acfd62fe3b7f918c312522bbcc6ad51cdec4fd1edf",
    )
    _check(
        rng,
        "L",
        1,
        1,
        False,
        [200],
        "676bb1db990ed1d1bdd2e98d4e0180d14fb614b5db9b3079497f1c3e6b6b94ad",
    )
    _check(
        rng,
        "RGB",
        1,
        1,
        True,
        [1, 2, 3],
        "9951d20c987aac93c538973ddc3978c0b88c6b1b47b6f80fe4b8dda6200a6a43",
    )
    _check(
        rng,
        "RGB",
        8,
        8,
        True,
        none.copy(),
        "53eece67e035dcf9d65329c428e73accd8a96d83d50c314eb4208a14a1612020",
    )
    _check(
        rng,
        "RGB",
        8,
        8,
        False,
        none.copy(),
        "89210305c500ca063f023b4743212c0bef91386e1bf2cd7a8c3aa5f0a5f35d3b",
    )
    _check(
        rng,
        "RGBA",
        5,
        3,
        True,
        none.copy(),
        "eff35e12421053d48c000e45a6bb303ab244f65bb42f9cd341a9aa6da1fe421e",
    )
    _check(
        rng,
        "RGBA",
        5,
        3,
        False,
        none.copy(),
        "d34b223cce22f41f311bcfd5fa6aca75e846de5f4c4d05f5f953e72da6ef7457",
    )
    _check(
        rng,
        "L",
        64,
        2,
        True,
        none.copy(),
        "35616c86a77b5299690798f868c799d9dea57431fec2b4a5ee9cee3657ffa69a",
    )
    var solid = List[Int]()
    for _ in range(64):
        solid.extend([12, 34, 56])
    _check(
        rng,
        "RGB",
        8,
        8,
        True,
        solid^,
        "f66aa919493eb97d66af48f9d442ce82cdcb9571ee4b6e83857ed58443a55842",
    )
    _check(
        rng,
        "RGB",
        200,
        160,
        True,
        none.copy(),
        "47c6eb4cbac0f46a16121990af31300423d32d33cec83f16780aa00dd8424e54",
    )
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
    var folder = temporary_path("carla-png-cli")
    _ = run_program(["mkdir", "-p", folder], 10)
    Path(folder + "/in.json").write_text(
        '{"mode":"RGB","width":2,"height":1,"optimize":true,"pixels":'
        + "[9,8,7,6,5,4]}"
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
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
