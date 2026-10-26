# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The town builder refuses a missing layout and prints the Python summary."""

from std.os import getenv, makedirs, setenv
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._python_json import PyJson
from tools.carla_town_build import (
    build_town,
    directory_byte_count,
    grouped_digits,
    package_megabytes,
    ranked_mesh_lines,
    town_summary_line,
)


def test_a_missing_layout_is_refused() raises:
    """A town with no layout file is refused."""
    with assert_raises():
        _ = build_town(
            "Fixture",
            512,
            32.0,
            "/tmp/town-build-missing-raw",
            "/tmp/town-build-missing-layout",
            "/tmp/town-build-missing-maps",
            "/tmp/town-build-missing-out",
        )


def _bytes(text: String) raises -> Int:
    """Return a size the compiler cannot fold into an exact fraction."""
    _ = setenv("TOWN_SUMMARY_BYTES", text)
    return Int(getenv("TOWN_SUMMARY_BYTES", ""))


def test_the_summary_matches_the_python_command() raises:
    """The summary line uses Python grouping and one decimal megabyte."""
    assert_equal(grouped_digits(0), "0")
    assert_equal(grouped_digits(999), "999")
    assert_equal(grouped_digits(1000), "1,000")
    assert_equal(grouped_digits(1234567), "1,234,567")
    assert_equal(grouped_digits(-12000), "-12,000")
    assert_equal(package_megabytes(_bytes("0")), "0.0")
    assert_equal(package_megabytes(_bytes("50000")), "0.1")
    assert_equal(package_megabytes(_bytes("949999")), "0.9")
    assert_equal(package_megabytes(_bytes("950000")), "0.9")
    assert_equal(package_megabytes(_bytes("999999")), "1.0")
    assert_equal(package_megabytes(_bytes("1234567")), "1.2")
    assert_equal(package_megabytes(_bytes("1250000")), "1.2")
    assert_equal(package_megabytes(_bytes("1350000")), "1.4")
    assert_equal(
        town_summary_line("Town01", 1234567, 89, 3, 1234567),
        "Town01: 1,234,567 triangles near, 89 far, 3 meshes, 1.2 MB",
    )


def test_ranked_meshes_keep_the_earlier_tie() raises:
    """An equal triangle count keeps the mesh that was listed first."""
    var doc = PyJson.parse(
        '{"meshes":[{"path":"/Game/Carla/Static/Building/A","triangles":10},{"path":"/Game/Carla/Static/Building/B","triangles":2},{"path":"plain","triangles":10}]}'
    )
    assert_equal(
        ranked_mesh_lines(doc, 3),
        (
            "          10  Building/A\n          10  plain\n           2 "
            " Building/B"
        ),
    )
    assert_equal(ranked_mesh_lines(doc, 1), "          10  Building/A")
    assert_equal(ranked_mesh_lines(doc, 0), "")


def test_directory_byte_count_sums_nested_files() raises:
    """The package size is the sum of the files under the directory."""
    var root = mkdtemp(prefix="town bytes ")
    try:
        Path(root + "/a.txt").write_bytes("abc".as_bytes())
        var nested = root + "/inner"
        _ = makedirs(nested)
        Path(nested + "/b.txt").write_bytes("de".as_bytes())
        assert_equal(directory_byte_count(root), 5)
    finally:
        _ = run_program(["rm", "-rf", root], 10.0)


def test_the_command_requires_a_value_after_max_size() raises:
    """`--max-size` without a number is refused."""
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_town_build",
            "--max-size",
        ],
        30.0,
        merge_errors=False,
    )
    assert_equal(result.status, 2)
    assert_true(result.errors.startswith("usage: carla_town_build "))


def main() raises:
    """Run the town builder tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_town_build"],
        180.0,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
