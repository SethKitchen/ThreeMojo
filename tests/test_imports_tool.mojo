# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The import graph resolves names as the pinned Mojo 1.1.0 does (#714).

Each resolution fixture records what Mojo 1.1.0 (8189361e) did with
`mojo build --num-threads 1 -I . tools/probe.mojo`, where tools/probe.mojo
imports `pkg.one` and pkg/one.mojo imports `helper`:

- root helper.mojo and pkg/helper.mojo: the root one;
- pkg/helper.mojo alone: "unable to locate module 'helper'";
- tools/helper.mojo, helper.mojo and pkg/helper.mojo: the tools one;
- tools/pkg/__init__.mojo without tools/pkg/one.mojo: "unable to locate
  module 'one'" even with a root pkg/one.mojo;
- a plain tools/pkg directory without one.mojo: the root pkg/one.mojo;
- tools/pkg/one.mojo and pkg/one.mojo, neither under a package
  initializer: "ambiguous import 'one'".

The resolver keeps every file each root can reach, so a change to either
side of a hidden or ambiguous name still selects the entry point.
"""

from std.collections import Set
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

from tools._imports import (
    Resolver,
    SourceCache,
    affected_set,
    closure,
    defines_main,
    entry_directories,
    imported_names,
    is_documentation,
    mojo_files,
    quoted_assets,
    resolve,
    sorted_set,
    walk_files,
)
from tests._tree import Tree
from tools._process import run_program
from tools._schedule import weight

comptime PROBE = (
    "from pkg.one import value\n\n\ndef main():\n    print(value())\n"
)
comptime VALUE = "def value() -> Int:\n    return 1\n"


def _set(items: List[String]) -> Set[String]:
    """Return a list's items as a set."""
    var found = Set[String]()
    for item in items:
        found.add(item)
    return found^


def _same(actual: List[String], expected: List[String]) raises:
    """Assert two lists are equal, item by item."""
    assert_equal(len(actual), len(expected), " ".join(actual))
    for index in range(len(expected)):
        assert_equal(actual[index], expected[index])


def _probe_tree() raises -> Tree:
    """Return the native fixture's tree."""
    var tree = Tree()
    tree.write("tools/probe.mojo", PROBE)
    tree.write("tests/test_probe.mojo", PROBE)
    tree.write("pkg/one.mojo", "from helper import value\n")
    tree.write("helper.mojo", VALUE)
    tree.write("pkg/helper.mojo", VALUE)
    return tree^


def _affected(
    tree: Tree, path: String, deleted: Bool = False
) raises -> Set[String]:
    """Return what one changed path affects, which must not be everything."""
    var changed = Dict[String, Bool]()
    changed[path] = deleted
    var reasons = List[String]()
    var selection = affected_set(tree.root, changed, reasons)
    assert_false(selection.all, " ".join(reasons))
    return selection.files.copy()


# --- parsing -------------------------------------------------------------------


def test_imported_names_reads_from_and_plain_imports() raises:
    var source = (
        "from a.b import c, d as e  # f\n"
        "import g.h as i, j\n"
        "from k import (\n"
        "    l,  # m\n"
        "    n as o,\n"
        ")\n"
        "  from p import q\n"
        "# from r import s\n"
        "x = 'from t import u'\n"
        "from\tv  import\tw\tas\tz\n"
        "fromage import x\n"
        "from 9a import b\n"
        "importer = 1\n"
        "from y import\n"
    )
    _same(
        imported_names(source),
        [
            "a.b",
            "a.b.c",
            "a.b.d",
            "g.h",
            "j",
            "k",
            "k.l",
            "k.n",
            "p",
            "p.q",
            "v",
            "v.w",
        ],
    )


def test_imported_names_keeps_an_unclosed_list_to_the_end() raises:
    _same(
        imported_names("from a import (b,\n c\n"),
        ["a", "a.b", "a.c"],
    )
    _same(imported_names("import a as\n"), ["a as"])
    _same(imported_names("from a import b as\n"), ["a", "a.b as"])


def test_quoted_assets_finds_each_asset_path() raises:
    var source = (
        'a = "assets/draco/"\nb = "assets/x.bin" + "other/y"\n'
        '"assets/multi\nline" "assets/open'
    )
    _same(
        quoted_assets(source),
        ["assets/draco/", "assets/x.bin", "assets/multi\nline"],
    )


def test_main_is_a_top_level_def_or_fn() raises:
    assert_true(defines_main("def main():\n    pass\n"))
    assert_true(defines_main("x = 1\nfn main ( ) raises:\n"))
    assert_true(defines_main("def\nmain\n(\n"))
    assert_false(defines_main("# def main():\n"))
    assert_false(defines_main("    def main():\n"))
    assert_false(defines_main("def mainly():\n"))
    assert_false(defines_main("defmain():\n"))
    assert_false(defines_main("def main"))


def test_documentation_paths() raises:
    for path in [
        "README.md",
        "docs/wiki/Home.txt",
        "out/a.png",
        ".vscode/settings.json",
        "LICENSE",
        "skills-lock.json",
        ".gitignore",
    ]:
        assert_true(is_documentation(path), path)
    for path in ["Makefile", "tools/a.mojo", "assets/a.md.bin", "docs"]:
        assert_false(is_documentation(path), path)


# --- resolution ----------------------------------------------------------------


def test_entry_directory_then_root_never_the_importer_directory() raises:
    var known = _set(
        ["tools/probe.mojo", "pkg/one.mojo", "helper.mojo", "pkg/helper.mojo"]
    )
    # A transitive import searches the entry point's directory and the root.
    _same(resolve("helper", known, ["tools"]), ["helper.mojo"])
    known.add("tools/helper.mojo")
    _same(
        resolve("helper", known, ["tools"]),
        ["tools/helper.mojo", "helper.mojo"],
    )


def test_importer_sibling_never_substitutes_for_a_missing_module() raises:
    var known = _set(
        [
            "tools/probe.mojo",
            "pkg/__init__.mojo",
            "pkg/one.mojo",
            "pkg/helper.mojo",
        ]
    )
    _same(resolve("helper", known, ["tools"]), [])
    # The sibling counts only when an entry point can sit beside it.
    _same(resolve("helper", known, ["tools", "pkg"]), ["pkg/helper.mojo"])


def test_package_initializers_and_namespace_prefix_overlaps() raises:
    var known = _set(
        ["pkg/__init__.mojo", "pkg/one.mojo", "tools/pkg/__init__.mojo"]
    )
    # A package initializer in the entry directory hides the root package.
    _same(
        resolve("pkg.one", known, ["tools"]),
        ["tools/pkg/__init__.mojo", "pkg/__init__.mojo", "pkg/one.mojo"],
    )
    # A plain directory there does not; with its own module it is ambiguous.
    known = _set(["pkg/one.mojo", "tools/pkg/other.mojo"])
    _same(resolve("pkg.one", known, ["tools"]), ["pkg/one.mojo"])
    known.add("tools/pkg/one.mojo")
    _same(
        resolve("pkg.one", known, ["tools"]),
        ["tools/pkg/one.mojo", "pkg/one.mojo"],
    )
    # A package named by its initializer alone, and a name nothing defines.
    _same(
        resolve("pkg", _set(["pkg/__init__.mojo"]), ["core"]),
        ["pkg/__init__.mojo"],
    )
    _same(resolve("std.sys", known, ["core"]), [])


def test_nested_module_prefixes_keep_both_roots_and_initializers() raises:
    var known = _set(
        [
            "tools/pkg.mojo",
            "tools/pkg/sub.mojo",
            "tools/pkg/__init__.mojo",
            "tools/pkg/sub/__init__.mojo",
            "pkg.mojo",
            "pkg/sub.mojo",
            "pkg/sub/one.mojo",
        ]
    )
    _same(
        resolve("pkg.sub.one", known, ["tools"]),
        [
            "tools/pkg/__init__.mojo",
            "tools/pkg.mojo",
            "tools/pkg/sub/__init__.mojo",
            "tools/pkg/sub.mojo",
            "pkg.mojo",
            "pkg/sub.mojo",
            "pkg/sub/one.mojo",
        ],
    )


def test_entry_directories_are_the_directories_of_main() raises:
    var sources = Dict[String, String]()
    sources["tools/probe.mojo"] = PROBE
    sources["bench/run.mojo"] = "fn main():\n    pass\n"
    sources["pkg/one.mojo"] = "# def main():\nfrom helper import value\n"
    sources["pkg/two.mojo"] = "def mainly():\n    pass\n"
    sources["driver.mojo"] = "def main() raises:\n    pass\n"
    _same(entry_directories(sources), ["", "bench", "tools"])


def test_resolver_remembers_each_answer() raises:
    var lookup = Resolver(_set(["helper.mojo", "tools/helper.mojo"]), ["tools"])
    _same(lookup.lookup("helper"), ["tools/helper.mojo", "helper.mojo"])
    assert_true("helper" in lookup.answers)
    _same(lookup.lookup("helper"), ["tools/helper.mojo", "helper.mojo"])
    assert_equal(len(lookup.answers), 1)


# --- the file tree -------------------------------------------------------------


def test_walk_skips_copies_and_does_not_follow_directory_links() raises:
    var tree = Tree()
    tree.write("a.mojo", "")
    tree.write("deep/b.mojo", "")
    tree.write("deep/c.txt", "")
    tree.write(".git/d.mojo", "")
    tree.write("coverage/build/e.mojo", "")
    tree.write("coverage/f.mojo", "")
    tree.write("tools/out/g.mojo", "")
    _ = run_program(["ln", "-s", tree.root + "/deep", tree.root + "/link"], 10)
    _ = run_program(
        ["ln", "-s", tree.root + "/a.mojo", tree.root + "/h.mojo"], 10
    )
    _same(
        sorted_set(tree.known()),
        [
            "a.mojo",
            "coverage/f.mojo",
            "deep/b.mojo",
            "h.mojo",
            "tools/out/g.mojo",
        ],
    )
    _same(
        sorted_set(_set(walk_files(tree.root, "deep", False))),
        ["deep/b.mojo", "deep/c.txt"],
    )
    _same(walk_files(tree.root, "missing", False), [])
    tree.close()


def test_changed_actual_dependency_selects_every_consumer() raises:
    var tree = _probe_tree()
    _same(
        sorted_set(_affected(tree, "helper.mojo")),
        [
            "helper.mojo",
            "pkg/one.mojo",
            "tests/test_probe.mojo",
            "tools/probe.mojo",
        ],
    )
    # The importer's sibling is not compiled, so it selects nothing else.
    _same(sorted_set(_affected(tree, "pkg/helper.mojo")), ["pkg/helper.mojo"])
    tree.close()


def test_a_module_beside_one_entry_point_selects_its_users() raises:
    var tree = _probe_tree()
    tree.write("tools/helper.mojo", VALUE)
    var selected = _affected(tree, "tools/helper.mojo")
    assert_true("tools/probe.mojo" in selected)
    assert_true("pkg/one.mojo" in selected)
    # The union over entry directories also reaches the tests suite, whose
    # build uses the root helper; selection can only grow.
    assert_true("tests/test_probe.mojo" in selected)
    tree.close()


def test_prefix_module_change_and_removal_select_the_importer() raises:
    var tree = _probe_tree()
    tree.write("tools/pkg.mojo", "def main():\n    pass\n")
    assert_true("tools/probe.mojo" in _affected(tree, "tools/pkg.mojo"))
    tree.remove("tools/pkg.mojo")
    assert_true("tools/probe.mojo" in _affected(tree, "tools/pkg.mojo", True))
    tree.close()


def test_suite_closure_and_weight_use_the_suite_directory() raises:
    var tree = _probe_tree()
    tree.write("tests/helper.mojo", VALUE)
    var known = tree.known()
    var cache = SourceCache()
    _same(
        closure(tree.root, "tests/test_probe.mojo", known, cache),
        [
            "helper.mojo",
            "pkg/one.mojo",
            "tests/helper.mojo",
            "tests/test_probe.mojo",
        ],
    )
    # The same cache serves a suite in another directory correctly.
    _same(
        closure(tree.root, "tools/probe.mojo", known, cache),
        ["helper.mojo", "pkg/one.mojo", "tools/probe.mojo"],
    )
    assert_equal(
        weight(tree.root, "tools/probe.mojo", known, cache),
        VALUE.byte_length()
        + String("from helper import value\n").byte_length()
        + PROBE.byte_length(),
    )
    tree.close()


# --- coverage obligations ------------------------------------------------------


def _coverage_tree() raises -> Tree:
    """Return a tree where tests reach library modules in several ways."""
    var tree = Tree()
    tree.write("core/common.mojo", "def common():\n    pass\n")
    tree.write("core/used.mojo", "from core.common import common\n")
    tree.write("core/other.mojo", "def other():\n    pass\n")
    tree.write("tests/helper.mojo", "def helper():\n    pass\n")
    # A suite defines main, so its directory is an entry directory and the
    # bare helper import resolves beside it.
    tree.write(
        "tests/test_a.mojo",
        (
            "from core.used import common\nfrom helper import helper\n\n\ndef"
            " main():\n    pass\n"
        ),
    )
    tree.write("tests/test_b.mojo", "from core.common import common\n")
    tree.write("tests/test_other.mojo", "from core.other import other\n")
    tree.write(
        "tests/test_asset.mojo",
        'from core.used import common\n# "assets/fixture/"\n',
    )
    return tree^


def _relevant() -> List[String]:
    """Return what an edit of test_a or its helper must measure."""
    return [
        "core/common.mojo",
        "core/used.mojo",
        "tests/helper.mojo",
        "tests/test_a.mojo",
        "tests/test_asset.mojo",
        "tests/test_b.mojo",
    ]


def test_test_edit_measures_imports_and_all_relevant_suites() raises:
    var tree = _coverage_tree()
    _same(sorted_set(_affected(tree, "tests/test_a.mojo")), _relevant())
    _same(sorted_set(_affected(tree, "tests/helper.mojo")), _relevant())
    tree.close()


def test_test_fixture_edit_also_measures_exercised_library() raises:
    var tree = _coverage_tree()
    # test_a is reached as an importer of core.used; its helper is not
    # measured because the edited fixture belongs to test_asset only.
    var expected = _relevant()
    _ = expected.pop(2)
    _same(sorted_set(_affected(tree, "assets/fixture/data.bin")), expected)
    tree.close()


def test_library_only_change_keeps_the_reverse_import_scope() raises:
    var tree = _coverage_tree()
    _same(
        sorted_set(_affected(tree, "core/used.mojo")),
        ["core/used.mojo", "tests/test_a.mojo", "tests/test_asset.mojo"],
    )
    tree.close()


def test_documentation_and_empty_changes_select_nothing() raises:
    var tree = _coverage_tree()
    var reasons = List[String]()
    assert_equal(
        len(affected_set(tree.root, Dict[String, Bool](), reasons).files), 0
    )
    assert_equal(len(_affected(tree, "README.md")), 0)
    tree.close()


def test_conservative_changes_select_everything_with_a_reason() raises:
    var tree = _coverage_tree()
    tree.write("tests/test_bad.mojo", "")
    Path(tree.root + "/tests/test_bad.mojo").write_bytes([UInt8(0xFF)])
    var cases = [
        (
            "tests/test_a.mojo",
            True,
            "a test suite was deleted: tests/test_a.mojo",
        ),
        (
            "Makefile",
            False,
            "a build input has no narrower dependency rule: Makefile",
        ),
        (
            "coverage/a.mojo",
            False,
            "a build input has no narrower dependency rule: coverage/a.mojo",
        ),
        (
            "tests/test_bad.mojo",
            False,
            "a source file could not be read: tests/test_bad.mojo",
        ),
    ]
    for entry in cases:
        var changed = Dict[String, Bool]()
        changed[entry[0]] = entry[1]
        var reasons = List[String]()
        assert_true(affected_set(tree.root, changed, reasons).all, entry[0])
        _same(reasons, [entry[2]])
    tree.close()


def test_nested_helpers_remain_dependencies() raises:
    var tree = Tree()
    tree.write("math/measured.mojo", "def value() -> Int:\n    return 1\n")
    tree.write("tests/_nested.mojo", "from math.measured import value\n")
    tree.write("tests/_shared.mojo", "from tests._nested import value\n")
    tree.write("tests/test_driver.mojo", "from tests._shared import value\n")
    tree.write("tests/test_other.mojo", "from math.measured import value\n")
    var cache = SourceCache()
    _same(
        closure(tree.root, "tests/test_driver.mojo", tree.known(), cache),
        [
            "math/measured.mojo",
            "tests/_nested.mojo",
            "tests/_shared.mojo",
            "tests/test_driver.mojo",
        ],
    )
    var selected = _affected(tree, "tests/_nested.mojo")
    for path in [
        "math/measured.mojo",
        "tests/_nested.mojo",
        "tests/_shared.mojo",
        "tests/test_driver.mojo",
        "tests/test_other.mojo",
    ]:
        assert_true(path in selected, path)
    tree.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
