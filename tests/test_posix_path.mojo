# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Component names follow Python's POSIX path parent rule."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._posix_path import (
    component_confined,
    path_basename,
    require_component_names,
)


def test_a_component_name_stays_inside_its_directory() raises:
    """The parent comparison matches `PurePosixPath` for both anchors."""
    var directory = "/tmp/components"
    assert_equal(component_confined(directory, "a.json"), True)
    assert_equal(component_confined(directory, ".."), True)
    assert_equal(component_confined(directory, "."), False)
    assert_equal(component_confined(directory, ""), False)
    assert_equal(component_confined(directory, "a/b"), False)
    assert_equal(component_confined(directory, "/abs"), False)
    assert_equal(component_confined(directory, "//abs"), False)
    assert_equal(component_confined(directory, "///a"), False)
    assert_equal(component_confined(directory, "foo/."), True)
    assert_equal(component_confined(directory, "./a"), True)
    assert_equal(component_confined(directory, "a/"), True)
    assert_equal(component_confined(directory, "a\\b"), True)
    assert_equal(component_confined(directory, "/tmp/components/a"), True)
    assert_equal(component_confined(directory, "/tmp/components/a/b"), False)
    assert_equal(component_confined("components", "a.json"), True)
    assert_equal(component_confined("components", "."), False)
    assert_equal(component_confined("/", "/"), True)
    assert_equal(component_confined("/tmp", "/"), False)
    assert_equal(component_confined("//host", "a"), True)
    assert_equal(component_confined("", ""), True)
    assert_equal(component_confined("//", ""), True)
    assert_equal(component_confined("components", "."), False)
    assert_equal(component_confined("/b/x", "/a/y/z"), False)


def test_a_basename_keeps_the_text_after_the_last_slash() raises:
    """Only `/` separates, and a trailing slash leaves an empty part."""
    assert_equal(path_basename(""), "")
    assert_equal(path_basename("c.json"), "c.json")
    assert_equal(path_basename("a/b/c.json"), "c.json")
    assert_equal(path_basename("a/"), "")
    assert_equal(path_basename("//a"), "a")
    assert_equal(path_basename("/"), "")
    assert_equal(path_basename("a\\b"), "a\\b")
    assert_equal(path_basename("a//b"), "b")


def test_an_escaping_component_name_is_refused() raises:
    """The first escaping name is reported, and safe names pass."""
    require_component_names('{"directory":"/tmp/components","names":[]}')
    require_component_names(
        '{"directory":"/tmp/components","names":["a.json","b.json"]}'
    )
    with assert_raises(
        contains="coverage invariant successor: component record changed: a/b"
    ):
        require_component_names(
            '{"directory":"/tmp/components","names":["a.json","a/b"]}'
        )


def main() raises:
    """Run the POSIX path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
