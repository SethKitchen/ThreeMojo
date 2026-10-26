# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The density successor inputs keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.density_successor_inputs import density_successor_inputs


def _copy(root: String) raises:
    """Copy the reviewed density successor inputs.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        [
            "mkdir",
            "-p",
            root + "/core",
            root + "/extensions/humanoid/skeleton/head",
            root + "/geometries",
            root + "/loaders",
            root + "/math",
            root + "/objects",
            root + "/render",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("core/extent.mojo")
    files.append("extensions/humanoid/skeleton/head/assembly.mojo")
    files.append("extensions/humanoid/skeleton/look.mojo")
    files.append("geometries/attribute_utils.mojo")
    files.append("loaders/bytes.mojo")
    files.append("math/matrix4.mojo")
    files.append("math/square_matrix.mojo")
    files.append("math/vector4.mojo")
    files.append("objects/gaussian_splat.mojo")
    files.append("render/tasks.mojo")

    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_density_successor_inputs_hold() raises:
    """The 10 density successor inputs keep their reviewed digests."""
    density_successor_inputs(".")
    density_successor_inputs("./")
    density_successor_inputs("core/..")


def test_a_changed_extent_is_refused() raises:
    """A changed extent is refused."""
    var root = "/tmp/density-successor-extent"
    _copy(root)
    var path = root + "/core/extent.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains="density successor input changed: core/extent.mojo"
    ):
        density_successor_inputs(root)


def test_a_changed_task_runtime_is_refused() raises:
    """A changed task runtime is refused."""
    var root = "/tmp/density-successor-tasks"
    _copy(root)
    var path = root + "/render/tasks.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=("density successor input changed: " + "render/tasks.mojo")
    ):
        density_successor_inputs(root)


def main() raises:
    """Run the density successor input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
