# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A maintained input must be one regular file under an unaliased root."""

from std.testing import TestSuite, assert_equal, assert_true

from tests._carla_tool_files import put, remove_tree, scratch, symlink
from tools._carla_files import lstat_id, stat_id
from tools._process import run_program


def _parts(text: String) -> List[String]:
    var out = List[String]()
    if text == "":
        return out^
    var rest = text
    if rest.startswith("//"):
        out.append("//")
        var tail = String(rest[byte=2:])
        rest = tail
    elif rest.startswith("/"):
        out.append("/")
        var tail = String(rest[byte=1:])
        rest = tail
    while rest != "":
        var cut = rest.find("/")
        var part = rest
        if cut >= 0:
            part = String(rest[byte=:cut])
            var next = String(rest[byte = cut + 1 :])
            rest = next
        else:
            rest = ""
        if part != "" and part != ".":
            out.append(part)
    return out^


def _join(root: String, relative: String) -> String:
    if relative == "":
        return root
    return root + "/" + relative


def _unaliased(root: String) -> Bool:
    var path = root
    while True:
        try:
            if lstat_id(path).is_link():
                return False
        except:
            return False
        var cut = path.rfind("/")
        if cut <= 0:
            return True
        var parent = String(path[byte=:cut])
        path = parent


def _regular(root: String, relative: String) raises -> String:
    if relative.find("\0") >= 0:
        raise Error("ValueError: embedded null byte")
    var parts = _parts(relative)
    var absolute = False
    var dotdot = False
    if len(parts) > 0 and (parts[0] == "/" or parts[0] == "//"):
        absolute = True
    for part in parts:
        if part == "..":
            dotdot = True
    if len(parts) == 0 or absolute or dotdot:
        raise Error("full-audit cleanup successor: unsafe input path")
    if not _unaliased(root):
        raise Error("full-audit cleanup successor: symbolic root or ancestor")
    var path = root
    var built = String()
    for part in parts:
        path = path + "/" + part
        if built == "":
            built = part
        else:
            built = built + "/" + part
        var info = lstat_id(path)
        if info.is_link():
            raise Error(
                "full-audit cleanup successor: symlink input: " + relative
            )
    if not stat_id(path).is_regular():
        raise Error(
            "full-audit cleanup successor: input is not a regular file: "
            + relative
        )
    return built


def _resolve(path: String) raises -> String:
    var result = run_program(["readlink", "-f", path], 10.0, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    var text = result.output
    if text.endswith("\n"):
        var end = text.byte_length() - 1
        var trimmed = String(text[byte=:end])
        text = trimmed
    return text


def _tree() raises -> String:
    return _resolve(scratch())


def _finish(root: String) raises:
    remove_tree(root)


def _message(root: String, relative: String) raises -> String:
    try:
        _ = _regular(root, relative)
    except error:
        return String(error)
    return ""


def test_a_regular_file_keeps_its_path() raises:
    """A regular file under the root keeps its relative path."""
    var root = _tree()
    try:
        for relative in [
            "file",
            "nested/file",
            "back\\slash",
            ".hidden/file",
            "a/.../file",
        ]:
            put(_join(root, relative), "fixture\n")
        assert_equal(_regular(root, "file"), "file")
        assert_equal(_regular(root, "nested/file"), "nested/file")
        assert_equal(_regular(root, "back\\slash"), "back\\slash")
        assert_equal(_regular(root, ".hidden/file"), ".hidden/file")
        assert_equal(_regular(root, "a/.../file"), "a/.../file")
        assert_equal(_regular(root, "./file"), "file")
        assert_equal(_regular(root, "nested//file"), "nested/file")
        assert_equal(_regular(root, "nested/./file"), "nested/file")
        assert_equal(_regular(root, "nested/file/"), "nested/file")
    finally:
        _finish(root)


def test_an_unsafe_path_is_refused() raises:
    """An absolute path, an empty path, or a parent step is refused."""
    var root = _tree()
    try:
        put(_join(root, "file"), "fixture\n")
        put(_join(root, "nested/file"), "fixture\n")
        for relative in [
            "",
            ".",
            "..",
            "../file",
            "nested/../file",
            "/file",
            "//file",
        ]:
            var message = _message(root, relative)
            assert_true(message.find("unsafe input path") >= 0, relative)
    finally:
        _finish(root)


def test_a_missing_directory_or_null_path_is_refused() raises:
    """A missing file, a directory, a child of a file, and a null are refused.
    """
    var root = _tree()
    try:
        put(_join(root, "file"), "fixture\n")
        put(_join(root, "nested/file"), "fixture\n")
        var missing = _message(root, "missing")
        assert_true(missing.find("No such file") >= 0)
        var directory = _message(root, "nested")
        assert_true(directory.find("not a regular file") >= 0)
        var child = _message(root, "file/child")
        assert_true(child.find("Not a directory") >= 0)
        var null_name = _message(root, "\0")
        assert_true(null_name.find("embedded null byte") >= 0)
        var null_inside = _message(root, "nul\0name")
        assert_true(null_inside.find("embedded null byte") >= 0)
    finally:
        _finish(root)


def test_a_symlink_input_or_a_linked_root_is_refused() raises:
    """A symlink in the path, or a linked root, is refused."""
    var root = _tree()
    try:
        put(_join(root, "nested/file"), "fixture\n")
        put(_join(root, "file"), "fixture\n")
        symlink(_join(root, "nested"), _join(root, "alias"))
        var linked = _message(root, "alias/file")
        assert_true(linked.find("symlink input: alias/file") >= 0)
        var parent = _tree()
        try:
            var alias = _join(parent, "root")
            symlink(root, alias)
            var rooted = _message(alias, "file")
            assert_true(rooted.find("symbolic root or ancestor") >= 0)
        finally:
            _finish(parent)
    finally:
        _finish(root)


def main() raises:
    """Run the regular-path tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
