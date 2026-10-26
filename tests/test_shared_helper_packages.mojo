# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shared-helper package files keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.shared_helper_packages import shared_helper_packages


def _copy(root: String) raises:
    """Copy the four package files.

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
            root + "/extensions/carla",
            root + "/loaders",
            root + "/render",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("extensions/__init__.mojo")
    files.append("extensions/carla/__init__.mojo")
    files.append("loaders/__init__.mojo")
    files.append("render/__init__.mojo")
    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_package_files_hold() raises:
    """The four package files keep their reviewed digests."""
    shared_helper_packages(".")
    shared_helper_packages("./")
    shared_helper_packages("extensions/..")


def test_a_changed_package_file_is_refused() raises:
    """A changed CARLA package file is refused."""
    var root = "/tmp/shared-helper-packages-carla"
    _copy(root)
    var path = root + "/extensions/carla/__init__.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains="package input changed: extensions/carla/__init__.mojo"
    ):
        shared_helper_packages(root)


def test_a_changed_loader_package_is_refused() raises:
    """A changed loader package file is refused."""
    var root = "/tmp/shared-helper-packages-loaders"
    _copy(root)
    var path = root + "/loaders/__init__.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(contains="package input changed: loaders/__init__.mojo"):
        shared_helper_packages(root)


def main() raises:
    """Run the shared-helper package tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
