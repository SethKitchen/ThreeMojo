# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Town-bake primitive digests match Python SHA-256 over JSON shapes."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_not_equal,
    assert_raises,
    assert_true,
)

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_geometry_digest import digest_bytes


comptime _PIN_A = (
    "792d71a85b1c7a471a135c9a3be611b3bf5ae0329eed6f401cc018f734728c7d"
)
"""SHA-256 of the sample primitive whose first position byte is 0."""
comptime _PIN_B = (
    "b28054bd6407331050c9cc433b94fc0ee17d0effbe7af80ed501c90ad193d769"
)
"""SHA-256 of the sample primitive whose first position byte is 1."""
comptime _PIN_FLAT = (
    "e3473036962e5772a04235f087e8076042ed323dff74db7a5f6213ce9d18b7b8"
)
"""SHA-256 of the same bytes with a flat position shape."""


def _u32(mut out: List[UInt8], value: Int):
    """Append one little-endian u32."""
    var rest = value
    for _ in range(4):
        out.append(UInt8(rest & 255))
        rest >>= 8


def _u64(mut out: List[UInt8], value: Int):
    """Append one little-endian u64."""
    var rest = value
    for _ in range(8):
        out.append(UInt8(rest & 255))
        rest >>= 8


def _name(mut out: List[UInt8], text: String):
    """Append one field name."""
    var raw = text.as_bytes()
    _u32(out, len(raw))
    for index in range(len(raw)):
        out.append(raw[index])


def _zeros(count: Int) -> List[UInt8]:
    """Return `count` zero bytes."""
    var out = List[UInt8]()
    for _ in range(count):
        out.append(0)
    return out^


def _positions(first: Int) -> List[UInt8]:
    """Return 2 by 3 little-endian float64 positions, first value near 1."""
    var out = _zeros(0)
    out.append(UInt8(first))
    out.append(0)
    out.append(0)
    out.append(0)
    out.append(0)
    out.append(0)
    out.append(0xF0)
    out.append(0x3F)
    for _ in range(40):
        out.append(0)
    return out^


def _triangles() -> List[UInt8]:
    """Return the int64 triangle 0, 1, 2."""
    var out = List[UInt8]()
    for value in range(3):
        out.append(UInt8(value))
        for _ in range(7):
            out.append(0)
    return out^


def _field(
    mut out: List[UInt8], name: String, dims: List[Int], data: List[UInt8]
):
    """Append one field."""
    _name(out, name)
    _u32(out, len(dims))
    for index in range(len(dims)):
        _u32(out, dims[index])
    _u64(out, len(data))
    for index in range(len(data)):
        out.append(data[index])


def _shape2() -> List[Int]:
    """Return the rank-2 sample shape."""
    var dims = List[Int]()
    dims.append(2)
    dims.append(3)
    return dims^


def _shape_uv() -> List[Int]:
    """Return the UV sample shape."""
    var dims = List[Int]()
    dims.append(2)
    dims.append(2)
    return dims^


def _shape_tri() -> List[Int]:
    """Return the triangle sample shape."""
    var dims = List[Int]()
    dims.append(1)
    dims.append(3)
    return dims^


def _primitive(mut out: List[UInt8], first: Int, flat: Bool):
    """Append one sample primitive."""
    _u32(out, 4)
    var positions = _positions(first)
    if flat:
        var dims = List[Int]()
        dims.append(6)
        _field(out, "positions", dims, positions)
    else:
        _field(out, "positions", _shape2(), positions)
    _field(out, "normals", _shape2(), _zeros(48))
    _field(out, "uvs", _shape_uv(), _zeros(32))
    _field(out, "triangles", _shape_tri(), _triangles())


def _header(count: Int) -> List[UInt8]:
    """Return a CGD1 header with `count` primitives."""
    var out = List[UInt8]()
    out.append(67)
    out.append(71)
    out.append(68)
    out.append(49)
    _u32(out, count)
    return out^


def _pair() -> List[UInt8]:
    """Return the two sample primitives."""
    var out = _header(2)
    _primitive(out, 0, False)
    _primitive(out, 1, False)
    return out^


def _flat() -> List[UInt8]:
    """Return the sample primitive with a flat position shape."""
    var out = _header(1)
    _primitive(out, 0, True)
    return out^


def _python(script: String) raises -> String:
    """Return the standard output of a Python expression."""
    var result = run_program(["python3", "-c", script], 10, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    return result.output


def test_sample_digests_match_python_sha256() raises:
    var lines = digest_bytes(_pair())
    assert_equal(len(lines), 2)
    assert_equal(lines[0], _PIN_A)
    assert_equal(lines[1], _PIN_B)
    var expected = _python(
        "import hashlib, json\ndef digest(first):\n    h = hashlib.sha256()\n  "
        "  pos = bytearray(48)\n    pos[0:8] ="
        " bytes.fromhex('000000000000f03f')\n    pos[0] = first\n    fields ="
        " [\n        ('positions', [2, 3], bytes(pos)),\n        ('normals',"
        " [2, 3], bytes(48)),\n        ('uvs', [2, 2], bytes(32)),\n       "
        " ('triangles', [1, 3],"
        " bytes.fromhex('000000000000000001000000000000000200000000000000')),\n"
        "    ]\n    for name, shape, raw in fields:\n       "
        " h.update(json.dumps([name, shape], separators=(',', ':')).encode())\n"
        "        h.update(raw)\n    return"
        " h.hexdigest()\nprint(digest(0))\nprint(digest(1))\n"
    )
    assert_equal(expected, _PIN_A + "\n" + _PIN_B + "\n")
    var flat = digest_bytes(_flat())
    assert_equal(flat[0], _PIN_FLAT)
    assert_not_equal(flat[0], lines[0])


def test_an_empty_request_has_no_digests() raises:
    var lines = digest_bytes(_header(0))
    assert_equal(len(lines), 0)


def test_a_bad_request_is_refused() raises:
    var bad = _header(0)
    bad[0] = UInt8(0)
    with assert_raises():
        _ = digest_bytes(bad)
    var short = List[UInt8]()
    short.append(67)
    with assert_raises():
        _ = digest_bytes(short)
    var trailing = _header(0)
    trailing.append(0)
    with assert_raises():
        _ = digest_bytes(trailing)
    var count = _header(1)
    _u32(count, 3)
    with assert_raises():
        _ = digest_bytes(count)
    var renamed = _pair()
    renamed[16] = UInt8(88)
    with assert_raises():
        _ = digest_bytes(renamed)


def test_the_tool_prints_one_line_per_primitive() raises:
    var directory = mkdtemp(prefix="geometry digest ")
    var path = directory + "/request.cgd"
    var data = _pair()
    Path(path).write_bytes(data)
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_geometry_digest",
            path,
        ],
        60,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    assert_equal(result.output, _PIN_A + "\n" + _PIN_B + "\n")
    assert_true(result.errors.find("Crashpad") < 0)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "--build",
            "carla_geometry_digest",
        ],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
