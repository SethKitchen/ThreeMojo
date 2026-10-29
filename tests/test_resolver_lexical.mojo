# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A reviewed import root refuses a competing module, package, or link."""

from std.os import listdir
from std.testing import TestSuite, assert_equal

from tests._carla_tool_files import put, remove_tree, scratch, symlink
from tools._carla_files import lstat_id, stat_id
from tools._process import run_program


def _fold_code(value: Int) -> String:
    if value >= 65 and value <= 90:
        return chr(value + 32)
    if value == 0x00DF:
        return "ss"
    if value == 0x212A:
        return "k"
    if value >= 0x0391 and value <= 0x03A9 and value != 0x03A2:
        return chr(value + 0x20)
    if value == 0x0386:
        return chr(0x03AC)
    if value == 0x0388:
        return chr(0x03AD)
    if value == 0x0389:
        return chr(0x03AE)
    if value == 0x038A:
        return chr(0x03AF)
    if value == 0x038C:
        return chr(0x03CC)
    if value == 0x038E:
        return chr(0x03CD)
    if value == 0x038F:
        return chr(0x03CE)
    return chr(value)


def _codepoint(bytes: Span[UInt8, _], mut index: Int) -> Int:
    var first = Int(bytes[index])
    if first < 128:
        index += 1
        return first
    var need = 2
    var value = first & 0x1F
    if first >= 0xE0:
        need = 3
        value = first & 0x0F
    var step = 1
    while step < need and index + step < len(bytes):
        value = (value << 6) | (Int(bytes[index + step]) & 0x3F)
        step += 1
    index += need
    return value


def _fold(text: String) -> String:
    var bytes = text.as_bytes()
    var index = 0
    var out = String()
    while index < len(bytes):
        out += _fold_code(_codepoint(bytes, index))
    return out


def _has(items: List[String], name: String) -> Bool:
    for item in items:
        if item == name:
            return True
    return False


def _first(path: String) -> String:
    var cut = path.find("/")
    if cut < 0:
        return path
    return String(path[byte=:cut])


def _suffix_index(name: String) -> Int:
    var dot = name.rfind(".")
    if dot > 0 and dot < name.byte_length() - 1:
        return dot
    return -1


def _stem(relative: String) -> String:
    var slash = relative.rfind("/")
    var prefix = String()
    var name = relative
    if slash >= 0:
        prefix = String(relative[byte = : slash + 1])
        name = String(relative[byte = slash + 1 :])
    var cut = _suffix_index(name)
    if cut < 0:
        return relative
    return prefix + String(name[byte=:cut])


def _parents(path: String) -> List[String]:
    var out = List[String]()
    var rest = path
    while True:
        var cut = rest.rfind("/")
        if cut <= 0:
            break
        var parent = String(rest[byte=:cut])
        rest = parent
        out.append(rest)
    return out^


def _skip(name: String) -> Bool:
    return (
        name == ".git"
        or name == ".venv"
        or name == ".cache"
        or name == "out"
        or name == "node_modules"
        or name == "__pycache__"
        or name == ".agents"
        or name == ".claude"
    )


def _allowed() -> List[String]:
    var paths = List[String]()
    paths.append("math/vector.mojo")
    paths.append("units/value.mojo")
    paths.append("extensions/carla/curve.mojo")
    return paths^


def _join(root: String, relative: String) -> String:
    if relative == "":
        return root
    return root + "/" + relative


def _child(directory: String, name: String) -> String:
    if directory == ".":
        return name
    return directory + "/" + name


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


def _directory(path: String) -> Bool:
    try:
        return stat_id(path).is_directory()
    except:
        return False


def _scoped_math(directory: String, entries: List[String]) -> Bool:
    if len(entries) == 0:
        return True
    if _fold(directory) == "docs/wiki":
        return True
    return _has(entries, _fold(directory))


def _relevant(
    name: String,
    relative: String,
    directory: String,
    coordinates: List[String],
    stems: List[String],
    prefixes: List[String],
    top: List[String],
    math_entries: List[String],
) -> Bool:
    var folded = _fold(relative)
    var stem = _fold(_stem(relative))
    var head = name
    var dot = name.find(".")
    if dot >= 0:
        head = String(name[byte=:dot])
    var scoped = _fold(head)
    var prefix = String()
    if directory != ".":
        prefix = directory + "/"
    var suffix = False
    var mark = 0
    while mark < name.byte_length():
        if name.as_bytes()[mark] == 46:
            var cut = String(name[byte=:mark])
            if _has(coordinates, _fold(prefix + cut)):
                suffix = True
        mark += 1
    if (
        suffix
        or _has(stems, folded)
        or _has(prefixes, folded)
        or _has(stems, stem)
        or _has(prefixes, stem)
    ):
        return True
    if name == "__init__.mojo" and _has(prefixes, _fold(directory)):
        return True
    if _has(top, scoped) and _scoped_math(directory, math_entries):
        return True
    return False


def _admit(
    root: String, paths: List[String], math_entries: List[String]
) raises -> Bool:
    try:
        if not stat_id(root).is_directory() or not _unaliased(root):
            return False
    except:
        return False
    var coordinates = List[String]()
    var stems = List[String]()
    var prefixes = List[String]()
    var exact_prefixes = List[String]()
    var top = List[String]()
    top.append("std")
    for path in paths:
        coordinates.append(_fold(path))
        stems.append(_fold(_stem(path)))
        for parent in _parents(path):
            if not _has(exact_prefixes, parent):
                exact_prefixes.append(parent)
            var folded = _fold(parent)
            if not _has(prefixes, folded):
                prefixes.append(folded)
        var head = _fold(_first(path))
        if not _has(top, head):
            top.append(head)
    var pending = List[String]()
    pending.append(".")
    while len(pending) > 0:
        var directory = pending.pop()
        var names: List[String]
        try:
            names = listdir(_join(root, directory if directory != "." else ""))
        except:
            continue
        var order = List[String]()
        for name in names:
            var relative = _child(directory, name)
            var full = _join(root, relative)
            if _directory(full):
                if _skip(name) or relative == "coverage/build":
                    continue
                order.append(name)
                if not lstat_id(full).is_link():
                    pending.append(relative)
            else:
                order.append(name)
        for name in order:
            var relative = _child(directory, name)
            var full = _join(root, relative)
            if not _relevant(
                name,
                relative,
                directory,
                coordinates,
                stems,
                prefixes,
                top,
                math_entries,
            ):
                continue
            try:
                var info = lstat_id(full)
                if (
                    (
                        relative == "docs/wiki/Math.md"
                        or relative == "docs/wiki/Units.md"
                        or relative == "docs/wiki/Extensions.md"
                    )
                    and not info.is_link()
                    and stat_id(full).is_regular()
                ):
                    continue
                if info.is_link():
                    return False
                if info.is_directory():
                    if not _has(exact_prefixes, relative):
                        return False
                    continue
                if not _has(paths, relative) or not stat_id(full).is_regular():
                    return False
            except:
                return False
    return True


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
    _ = run_program(["chmod", "-R", "u+rwx", root], 10.0)
    remove_tree(root)


def _write(root: String, relative: String) raises:
    put(_join(root, relative), "# resolver fixture\n")


def _expect(
    root: String,
    paths: List[String],
    math_entries: List[String],
    expected: Bool,
) raises:
    assert_equal(_admit(root, paths, math_entries), expected)


def test_regular_callers_and_inert_wiki_files_stay() raises:
    """The allowed callers and the three wiki files stay."""
    var root = _tree()
    try:
        var paths = _allowed()
        for path in paths:
            _write(root, path)
        _write(root, "ordinary/nested/noise.txt")
        _expect(root, paths, List[String](), True)
        for name in ["Math", "Units", "Extensions"]:
            _write(root, "docs/wiki/" + name + ".md")
        _expect(root, paths, List[String](), True)
        _write(root, "docs/wiki/Math.txt")
        _expect(root, paths, List[String](), False)
    finally:
        _finish(root)


def test_case_suffix_package_and_namespace_competitors_are_refused() raises:
    """A case, suffix, package, or namespace competitor is refused."""
    var names = List[String]()
    names.append("Math.mojo")
    names.append("std.mojo")
    names.append("unrelated/math.mojo")
    names.append("math/Vector.mojo")
    names.append("MATH/vector.mojo")
    names.append("math/vector.mojopkg")
    names.append("math/vector.so")
    names.append("math/__init__.mojo")
    names.append("extensions/carla.mojo")
    var directories = List[String]()
    directories.append("math/vector")
    directories.append("unrelated/extensions")
    for name in names:
        var root = _tree()
        try:
            _write(root, name)
            _expect(root, _allowed(), List[String](), False)
        finally:
            _finish(root)
    for name in directories:
        var root = _tree()
        try:
            _ = run_program(["mkdir", "-p", _join(root, name)], 10.0)
            _expect(root, _allowed(), List[String](), False)
        finally:
            _finish(root)


def test_a_scoped_math_lookup_keeps_only_the_exact_wiki_file() raises:
    """Scoped math keeps only the exact regular wiki files."""
    var entries = List[String]()
    entries.append(".")
    entries.append("tests")
    entries.append("examples")
    var inert = List[String]()
    inert.append("docs/wiki/Math.md")
    inert.append("docs/wiki/Units.md")
    inert.append("docs/wiki/Extensions.md")
    var alternatives = List[String]()
    alternatives.append("docs/wiki/Math.txt")
    alternatives.append("docs/wiki/math.md")
    alternatives.append("docs/wiki/MATH.md")
    alternatives.append("docs/wiki/Math.md.mojopkg")
    alternatives.append("docs/wiki/Math.mojo")
    alternatives.append("docs/wiki/Math.mojoc")
    alternatives.append("docs/wiki/Math.mojopkg")
    alternatives.append("docs/wiki/Math")
    alternatives.append("docs/Wiki/Math.md")
    alternatives.append("Docs/wiki/Math.md")
    var target_root = _tree()
    try:
        _write(target_root, "ordinary/target.txt")
        var target = _join(target_root, "ordinary/target.txt")
        for relative in inert:
            var root = _tree()
            try:
                _write(root, relative)
                _expect(root, _allowed(), entries, True)
            finally:
                _finish(root)
            root = _tree()
            try:
                _ = run_program(["mkdir", "-p", _join(root, relative)], 10.0)
                _expect(root, _allowed(), entries, False)
            finally:
                _finish(root)
            root = _tree()
            try:
                var slash = relative.rfind("/")
                var parent = String(relative[byte=:slash])
                _ = run_program(["mkdir", "-p", _join(root, parent)], 10.0)
                symlink(target, _join(root, relative))
                _expect(root, _allowed(), entries, False)
            finally:
                _finish(root)
        for relative in alternatives:
            var root = _tree()
            try:
                _write(root, relative)
                _expect(root, _allowed(), entries, False)
            finally:
                _finish(root)
    finally:
        _finish(target_root)


def test_scoped_coordinates_keep_ordinary_files_and_refuse_competitors() raises:
    """Scoped math keeps an ordinary file and refuses a coordinate competitor.
    """
    var entries = List[String]()
    entries.append(".")
    entries.append("tests")
    entries.append("examples")
    var accepted = List[String]()
    accepted.append("ordinary/Math.txt")
    accepted.append("ordinary/Math.md")
    accepted.append("math/vector.mojo")
    var refused = List[String]()
    refused.append("math.mojo")
    refused.append("tests/Math.txt")
    refused.append("examples/Math.md")
    refused.append("math/vector.mojopkg")
    refused.append("math/vector.mojo.cov-origin")
    refused.append("math/vector/__init__.mojo")
    for relative in accepted:
        var root = _tree()
        try:
            _write(root, relative)
            _expect(root, _allowed(), entries, True)
            var slash = relative.rfind("/")
            var parent = "."
            if slash >= 0:
                parent = String(relative[byte=:slash])
            if parent != "ordinary":
                var linked = _tree()
                try:
                    if parent != ".":
                        _ = run_program(
                            ["mkdir", "-p", _join(linked, parent)], 10.0
                        )
                    symlink(_join(root, relative), _join(linked, relative))
                    _expect(linked, _allowed(), entries, False)
                finally:
                    _finish(linked)
        finally:
            _finish(root)
    for relative in refused:
        var root = _tree()
        try:
            _write(root, relative)
            _expect(root, _allowed(), entries, False)
        finally:
            _finish(root)


def test_relevant_links_and_a_linked_root_are_refused() raises:
    """A relevant link and a linked root are refused."""
    var source = _tree()
    try:
        _write(source, "ordinary/target.txt")
        var target = _join(source, "ordinary/target.txt")
        var cases = List[String]()
        cases.append("math/vector.mojo")
        cases.append("math")
        cases.append("docs/wiki/Math.md")
        for relative in cases:
            var root = _tree()
            try:
                var slash = relative.rfind("/")
                if slash >= 0:
                    _ = run_program(
                        [
                            "mkdir",
                            "-p",
                            _join(root, String(relative[byte=:slash])),
                        ],
                        10.0,
                    )
                var destination = target
                if relative == "math":
                    destination = _join(source, "ordinary")
                symlink(destination, _join(root, relative))
                _expect(root, _allowed(), List[String](), False)
            finally:
                _finish(root)
        var alias = _tree()
        try:
            var link = _join(alias, "root")
            symlink(source, link)
            _expect(link, _allowed(), List[String](), False)
        finally:
            _finish(alias)
    finally:
        _finish(source)


def test_an_irrelevant_link_stays_and_skipped_trees_stay_out() raises:
    """An irrelevant link stays, and a skipped tree stays out."""
    var root = _tree()
    try:
        var paths = _allowed()
        for path in paths:
            _write(root, path)
        _write(root, "ordinary/target.txt")
        symlink(
            _join(root, "ordinary/target.txt"),
            _join(root, "irrelevant-link.txt"),
        )
        symlink(_join(root, "ordinary"), _join(root, "unrelated-link"))
        _expect(root, paths, List[String](), True)
        for name in [
            ".git",
            ".venv",
            ".cache",
            "out",
            "node_modules",
            "__pycache__",
            ".agents",
            ".claude",
        ]:
            _write(root, name + "/math.mojo")
        _write(root, "coverage/build/math.mojo")
        _write(root, "coverage/kept/noise.txt")
        _expect(root, paths, List[String](), True)
    finally:
        _finish(root)


def test_a_late_competitor_is_seen_and_a_removed_one_is_not() raises:
    """A late package competitor is refused until it is removed."""
    var root = _tree()
    try:
        var paths = _allowed()
        _write(root, "math/vector.mojo")
        _expect(root, paths, List[String](), True)
        _write(root, "math/vector.mojopkg")
        _expect(root, paths, List[String](), False)
        _ = run_program(
            ["rm", "-f", "--", _join(root, "math/vector.mojopkg")], 10.0
        )
        _expect(root, paths, List[String](), True)
    finally:
        _finish(root)


def test_a_coordinate_suffix_is_refused_unless_it_is_allowed() raises:
    """An appended suffix of a consumed coordinate is refused."""
    var names = List[String]()
    names.append("math/vector.mojo.py")
    names.append("math/vector.mojo.origin.json")
    names.append("math/VECTOR.MOJO.py")
    names.append("math/vector.mojo..py")
    names.append("units/value.mojo.origin")
    names.append("extensions/carla/curve.mojo.py")
    for relative in names:
        var root = _tree()
        try:
            _write(root, relative)
            _expect(root, _allowed(), List[String](), False)
        finally:
            _finish(root)
        root = _tree()
        try:
            _ = run_program(["mkdir", "-p", _join(root, relative)], 10.0)
            _expect(root, _allowed(), List[String](), False)
        finally:
            _finish(root)
        root = _tree()
        try:
            var slash = relative.rfind("/")
            _ = run_program(
                ["mkdir", "-p", _join(root, String(relative[byte=:slash]))],
                10.0,
            )
            symlink(_join(root, "missing"), _join(root, relative))
            _expect(root, _allowed(), List[String](), False)
        finally:
            _finish(root)
    var root = _tree()
    try:
        var relative = "math/vector.mojo.origin.json"
        _write(root, relative)
        var paths = _allowed()
        paths.append(relative)
        _expect(root, paths, List[String](), True)
        _expect(root, _allowed(), List[String](), False)
    finally:
        _finish(root)
    root = _tree()
    try:
        _write(root, "ordinary/vector.mojo.origin.json")
        _write(root, "math/vectors.mojo.origin.json")
        _expect(root, _allowed(), List[String](), True)
    finally:
        _finish(root)


def test_unicode_case_and_dotted_names_follow_the_coordinate_rule() raises:
    """Unicode case and dotted names follow the consumed coordinate."""
    var root = _tree()
    try:
        _write(root, "Straße/σχήμα.mojo")
        var paths = List[String]()
        paths.append("Straße/σχήμα.mojo")
        _expect(root, paths, List[String](), True)
    finally:
        _finish(root)
    root = _tree()
    try:
        _write(root, "STRASSE/σχήμα.mojo")
        var paths = List[String]()
        paths.append("Straße/σχήμα.mojo")
        _expect(root, paths, List[String](), False)
    finally:
        _finish(root)
    var names = List[String]()
    names.append("VECTOR.MOJO")
    names.append("vector.mojo.py")
    names.append("Straße.mojo")
    names.append(".mojo")
    names.append("foo.")
    for name in names:
        root = _tree()
        try:
            _write(root, "math/" + name)
            var expected = (
                name == "Straße.mojo" or name == ".mojo" or name == "foo."
            )
            _expect(root, _allowed(), List[String](), expected)
        finally:
            _finish(root)


def test_a_missing_root_or_a_file_root_is_refused() raises:
    """A missing root and a file root are refused."""
    var root = _tree()
    try:
        _write(root, "plain-file")
        _expect(_join(root, "plain-file"), _allowed(), List[String](), False)
        _expect(_join(root, "missing-root"), _allowed(), List[String](), False)
    finally:
        _finish(root)


def test_an_unreadable_directory_does_not_hide_a_caller() raises:
    """A directory the walk cannot list does not hide another caller."""
    var root = _tree()
    try:
        _write(root, "math/vector.mojo")
        var locked = _join(root, "locked")
        _ = run_program(["mkdir", "-p", locked], 10.0)
        _ = run_program(["chmod", "000", locked], 10.0)
        _expect(root, _allowed(), List[String](), True)
        _write(root, "math/vector.mojopkg")
        _expect(root, _allowed(), List[String](), False)
    finally:
        _finish(root)


def main() raises:
    """Run the resolver lexical tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
