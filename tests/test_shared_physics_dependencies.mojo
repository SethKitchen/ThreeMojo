# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shared mechanics import graph stays independent of simulation domains."""

from std.collections import Set
from std.testing import TestSuite, assert_false, assert_true

from tools._imports import (
    dirname,
    imported_names,
    mojo_files,
    read_source,
    resolve,
)


def test_core_imports_no_carla_or_humanoid_module() raises:
    var files = mojo_files(".")
    var known = Set[String]()
    var pending = List[String]()
    for path in files:
        known.add(path)
        if path.startswith("extensions/physics/"):
            pending.append(path)
    assert_true(len(pending) > 0)
    var visited = Set[String]()
    while len(pending) > 0:
        var path = pending.pop()
        if path in visited:
            continue
        visited.add(path)
        assert_false(
            path.startswith("extensions/carla/")
            or path.startswith("extensions/humanoid/"),
            path,
        )
        var entries = List[String]()
        entries.append(dirname(path))
        for name in imported_names(read_source(".", path)):
            for target in resolve(name, known, entries):
                pending.append(target)
    assert_true("extensions/physics/world.mojo" in visited)
    assert_true("math/vector3.mojo" in visited)
    assert_true("units/si.mojo" in visited)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
