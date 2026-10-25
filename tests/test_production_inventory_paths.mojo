# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The production census keeps nested callers and refuses a bad root."""

from std.os import listdir
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._carla_tool_files import put, remove_tree, scratch, symlink
from tools._carla_files import lstat_id, make_dirs
from tools._process import run_program
from tools._python_json import sorted_order
from tools._sha256 import sha256_hex


def _dot(name: String) -> Bool:
    return name.startswith(".")


def _mojo_name(name: String) -> Bool:
    return name.endswith(".mojo")


def _nonproduction(name: String) -> Bool:
    return (
        name == "tests"
        or name == "examples"
        or name == "bench"
        or name == "tools"
        or name == "docs"
        or name == "assets"
        or name == "out"
        or name == "coverage"
        or name == "cache"
        or name == "build"
        or name == "node_modules"
    )


def _join(root: String, relative: String) -> String:
    if relative == "":
        return root
    return root + "/" + relative


def _child(relative: String, name: String) -> String:
    if relative == "":
        return name
    return relative + "/" + name


def _excluded(relative: String) -> Bool:
    var rest = relative
    var first = True
    while rest != "":
        var cut = rest.find("/")
        var part = rest
        if cut >= 0:
            part = String(rest[byte=:cut])
            var next = String(rest[byte = cut + 1 :])
            rest = next
        else:
            rest = ""
        if _dot(part) or (first and _nonproduction(part)):
            return True
        first = False
    return False


def _production(root: String) raises -> List[String]:
    var found = List[String]()
    var pending = List[String]()
    pending.append("")
    while len(pending) > 0:
        var relative = pending.pop()
        var names = listdir(_join(root, relative))
        for name in names:
            if _dot(name) or (relative == "" and _nonproduction(name)):
                continue
            var child = _child(relative, name)
            var full = _join(root, child)
            var info = lstat_id(full)
            if _mojo_name(name):
                found.append(child)
            if info.is_directory() and not info.is_link():
                pending.append(child)
    return found^


def _reference(root: String) raises -> List[String]:
    var found = List[String]()
    var pending = List[String]()
    pending.append("")
    while len(pending) > 0:
        var relative = pending.pop()
        var directory = _join(root, relative)
        var names = listdir(directory)
        for name in names:
            var child = _child(relative, name)
            var full = directory + "/" + name
            var info = lstat_id(full)
            if info.is_directory() and not info.is_link():
                pending.append(child)
            if _mojo_name(name) and not _excluded(child):
                found.append(child)
    return found^


def _sorted(paths: List[String]) -> List[String]:
    var order = sorted_order(paths)
    var out = List[String]()
    for index in order:
        out.append(paths[index])
    return out^


def _same_paths(left: List[String], right: List[String]) -> Bool:
    var a = _sorted(left)
    var b = _sorted(right)
    if len(a) != len(b):
        return False
    var index = 0
    while index < len(a):
        if a[index] != b[index]:
            return False
        index += 1
    return True


def _has(paths: List[String], name: String) -> Bool:
    for path in paths:
        if path == name:
            return True
    return False


def _identifier(text: String, name: String) -> Bool:
    var bytes = text.as_bytes()
    var index = 0
    var size = len(bytes)
    while index < size:
        var byte = bytes[index]
        if byte == 35:
            while index < size and bytes[index] != 10:
                index += 1
            continue
        if byte == 34 or byte == 39:
            var quote = byte
            index += 1
            while index < size and bytes[index] != quote:
                if bytes[index] == 92:
                    index += 2
                    continue
                index += 1
            if index < size:
                index += 1
            continue
        if (
            (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or byte == 95
        ):
            var start = index
            index += 1
            while index < size:
                var next = bytes[index]
                var word = (
                    (next >= 65 and next <= 90)
                    or (next >= 97 and next <= 122)
                    or (next >= 48 and next <= 57)
                    or next == 95
                )
                if not word:
                    break
                index += 1
            var token = String(text[byte=start:index])
            if token == name:
                return True
            continue
        index += 1
    return False


def _watched(kind: Int, text: String) -> Bool:
    if kind == 0:
        return (
            _identifier(text, "_same_cache_key")
            or _identifier(text, "_run_lane_search")
            or _identifier(text, "lane_refinement")
        )
    if kind == 1:
        return _identifier(text, "_run_lane_search") or _identifier(
            text, "lane_refinement"
        )
    return (
        _identifier(text, "_require_sum2_environment")
        or _identifier(text, "curve_sum2")
        or _identifier(text, "_sum2_error")
    )


struct _Rows(Movable):
    var keys: List[String]
    var values: List[String]

    def __init__(out self):
        self.keys = List[String]()
        self.values = List[String]()


def _rows(root: String, paths: List[String], kind: Int) raises -> _Rows:
    var order = sorted_order(paths)
    var rows = _Rows()
    for index in order:
        var relative = paths[index]
        var text = Path(_join(root, relative)).read_text()
        if _watched(kind, text):
            rows.keys.append(relative)
            rows.values.append(sha256_hex(text.as_bytes()))
    return rows^


def _same_rows(left: _Rows, right: _Rows) -> Bool:
    if len(left.keys) != len(right.keys):
        return False
    var index = 0
    while index < len(left.keys):
        if (
            left.keys[index] != right.keys[index]
            or left.values[index] != right.values[index]
        ):
            return False
        index += 1
    return True


def _has_key(rows: _Rows, name: String) -> Bool:
    for key in rows.keys:
        if key == name:
            return True
    return False


def _sorted_keys(rows: _Rows) -> Bool:
    var index = 1
    while index < len(rows.keys):
        if rows.keys[index] < rows.keys[index - 1]:
            return False
        index += 1
    return True


def _caller() -> String:
    return (
        "from extensions.carla.lane_refinement import _run_lane_search\n"
        + "from extensions.carla.curve_sum2 import _require_sum2_environment\n"
    )


def _agree(root: String) raises:
    var produced = _production(root)
    var reference = _reference(root)
    assert_true(_same_paths(produced, reference))
    var kind = 0
    while kind < 3:
        var left = _rows(root, produced, kind)
        var right = _rows(root, reference, kind)
        assert_true(_same_rows(left, right))
        assert_true(_sorted_keys(left))
        kind += 1


def test_nested_callers_stay_and_top_level_trees_stay_out() raises:
    """A nested tests directory stays, and a top-level one stays out."""
    var root = scratch()
    try:
        var kept = List[String]()
        kept.append("root.mojo")
        kept.append("new_namespace/__init__.mojo")
        kept.append("new_namespace/tests/caller.mojo")
        kept.append("new_namespace/tools/caller.mojo")
        kept.append("new_namespace/coverage/caller.mojo")
        for name in kept:
            put(_join(root, name), _caller())
        put(_join(root, "new_namespace/upper.MOJO"), _caller())
        var skipped = List[String]()
        skipped.append("tests")
        skipped.append("examples")
        skipped.append("bench")
        skipped.append("tools")
        skipped.append("docs")
        skipped.append("assets")
        skipped.append("out")
        skipped.append("coverage")
        skipped.append("cache")
        skipped.append("build")
        skipped.append("node_modules")
        for name in skipped:
            put(_join(root, name + "/nested/caller.mojo"), _caller())
        put(_join(root, ".hidden/caller.mojo"), _caller())
        put(_join(root, "new_namespace/.hidden/caller.mojo"), _caller())
        put(_join(root, "new_namespace/.caller.mojo"), _caller())
        var found = _production(root)
        assert_true(_same_paths(found, kept))
        assert_true(not _has(found, "new_namespace/upper.MOJO"))
        _agree(root)
    finally:
        _open_root(root)


def _open_root(root: String) raises:
    _ = run_program(["chmod", "-R", "u+rwx", root], 10)
    remove_tree(root)


def test_a_new_caller_changes_the_inventory_and_an_unrelated_file_does_not() raises:
    """A new caller and a changed caller change each inventory."""
    var root = scratch()
    try:
        put(_join(root, "initial.mojo"), _caller())
        _agree(root)
        var before = List[_Rows]()
        var kind = 0
        while kind < 3:
            before.append(_rows(root, _production(root), kind))
            kind += 1
        var added = "new_namespace/tests/late_caller.mojo"
        put(_join(root, added), _caller())
        _agree(root)
        kind = 0
        while kind < 3:
            var after = _rows(root, _production(root), kind)
            assert_true(not _same_rows(before[kind], after))
            assert_true(_has_key(after, added))
            kind += 1
        put(
            _join(root, added),
            (
                "alias later = _run_lane_search\nalias environment ="
                " _require_sum2_environment\n"
            ),
        )
        _agree(root)
        kind = 0
        while kind < 3:
            var changed = _rows(root, _production(root), kind)
            var previous = _rows(root, _reference(root), kind)
            assert_true(_same_rows(changed, previous))
            assert_true(not _same_rows(before[kind], changed))
            kind += 1
        _ = run_program(["rm", "-f", "--", _join(root, added)], 10)
        _agree(root)
        kind = 0
        while kind < 3:
            assert_true(
                _same_rows(before[kind], _rows(root, _production(root), kind))
            )
            kind += 1
        put(_join(root, added), "alias irrelevant = 1\n")
        _agree(root)
        kind = 0
        while kind < 3:
            assert_true(
                _same_rows(before[kind], _rows(root, _production(root), kind))
            )
            kind += 1
    finally:
        _open_root(root)


def test_a_file_link_stays_and_a_directory_link_is_not_entered() raises:
    """A file link is a caller, and a directory link is not entered."""
    var root = scratch()
    try:
        var target = _join(root, "ordinary/real.mojo")
        put(target, _caller())
        symlink(target, _join(root, "file_link.mojo"))
        symlink(_join(root, "ordinary"), _join(root, "directory_link"))
        var found = _production(root)
        assert_true(_has(found, "file_link.mojo"))
        assert_true(_has(found, "ordinary/real.mojo"))
        assert_true(not _has(found, "directory_link/real.mojo"))
        _agree(root)
    finally:
        _open_root(root)


def test_a_linked_root_keeps_the_same_callers() raises:
    """A symbolic link to the root selects the same callers."""
    var root = scratch()
    var parent = scratch()
    try:
        put(_join(root, "z/first.mojo"), _caller())
        put(_join(root, "a/last.mojo"), _caller())
        put(_join(root, "m.mojo"), _caller())
        var linked = _join(parent, "root")
        symlink(root, linked)
        assert_true(_same_paths(_production(linked), _reference(linked)))
        var kind = 0
        while kind < 3:
            var rows = _rows(linked, _production(linked), kind)
            assert_true(_sorted_keys(rows))
            assert_true(
                _same_rows(rows, _rows(linked, _reference(linked), kind))
            )
            kind += 1
    finally:
        _open_root(parent)
        _open_root(root)


def test_a_matching_directory_or_broken_link_cannot_be_read() raises:
    """A directory or broken link named like a caller cannot be read."""
    var kinds = List[String]()
    kinds.append("directory")
    kinds.append("directory_symlink")
    kinds.append("broken_symlink")
    for kind in kinds:
        var root = scratch()
        try:
            var target = _join(root, "unusual.mojo")
            if kind == "directory":
                make_dirs(target)
            elif kind == "directory_symlink":
                symlink(root, target)
            else:
                symlink(_join(root, "missing"), target)
            assert_true(_same_paths(_production(root), _reference(root)))
            var failed = 0
            var mode = 0
            while mode < 3:
                try:
                    _ = _rows(root, _production(root), mode)
                except:
                    failed += 1
                mode += 1
            assert_equal(failed, 3)
        finally:
            _open_root(root)


def test_a_listed_name_that_cannot_be_classified_is_refused() raises:
    """A name the census can list but cannot classify is refused."""
    var root = scratch()
    try:
        var locked = _join(root, "locked")
        put(_join(locked, "file.mojo"), _caller())
        _ = run_program(["chmod", "400", locked], 10)
        var failed = False
        try:
            _ = _production(root)
        except:
            failed = True
        assert_true(failed)
    finally:
        _open_root(root)


def test_an_unreadable_directory_is_refused() raises:
    """A directory the census cannot list is refused."""
    var root = scratch()
    try:
        put(_join(root, "initial.mojo"), _caller())
        var locked = _join(root, "locked")
        make_dirs(locked)
        _ = run_program(["chmod", "000", locked], 10)
        var failed = False
        try:
            _ = _production(root)
        except:
            failed = True
        assert_true(failed)
    finally:
        _open_root(root)


def test_a_missing_root_or_a_file_root_is_refused() raises:
    """A missing root and a file root are refused."""
    var root = scratch()
    try:
        var ordinary = _join(root, "ordinary.txt")
        put(ordinary, "text\n")
        var failed = 0
        for candidate in [_join(root, "missing"), ordinary]:
            try:
                _ = _production(candidate)
            except:
                failed += 1
        assert_equal(failed, 2)
    finally:
        _open_root(root)


def main() raises:
    """Run the production inventory path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
