# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the anatomy report's source binding without a native probe, and
keep the historical representative example pinned.

The binding tests use small source trees. The committed template report
records the binding of the Python tool it came from, so no test compares it
with the current checkout; regenerating the report brings it back under
`check_binding`.
"""

from std.collections import Set
from std.os import makedirs
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._json_tree import JsonTree
from tools._sha256 import sha256_hex
from tools.anatomy_validity import (
    BINDING_VERSION,
    INVENTORY,
    PINNED_TOOLCHAIN,
    REPORT_LOGIC,
    bound_paths,
    build_flags,
    imports_of,
    source_digest,
    source_snapshot,
)

comptime REPORT = "docs/validation/anatomy-template-report.json"
"""The committed template report, which the binding check reads."""
comptime EXAMPLE = "docs/validation/anatomy-pair-example.json"
"""The historical representative example."""
comptime SOURCE_COMMIT = "2c91d60c660d05cf5e0fa093e6774558ba14332f"
"""The commit the example was produced at."""
comptime SOURCE_SHA256 = (
    "b3dd9ea15888167980fcff72e43e489d52f1106784c01d52ce9484fb7a36bc4d"
)
"""The example's recorded source digest."""
comptime REPORT_SHA256 = (
    "c4b74bfa37670407512eedeac3601ce1d2fd670771143b78276ecac8add31f39"
)
"""The example file's digest."""
comptime PROBE_SHA256 = (
    "752cbe627c526d4e2251d4c933f3eb051281bc5e9be32fd5565b943a56de5d30"
)
"""The example's recorded probe digest."""


def check_binding(root: String) raises:
    """Reject a missing or stale report; this does not validate its
    measurements.

    Args:
        root: The repository root.

    Raises:
        Error: If the report is missing or a binding is stale.
    """
    var tree = JsonTree()
    var report = tree.parse(Path(root + "/" + REPORT).read_text())
    var snapshot = source_snapshot(root)
    var actual = List[Int]()
    actual.append(
        tree.item(tree.item(report, "build_provenance"), "source_sha256")
    )
    actual.append(tree.get(report, "report_logic_sha256"))
    actual.append(tree.get(report, "inventory_sha256"))
    var expected: List[String] = [
        snapshot.digest,
        snapshot.hash(REPORT_LOGIC),
        snapshot.hash(INVENTORY),
    ]
    var keys: List[String] = [
        "source_sha256",
        "report_logic_sha256",
        "inventory_sha256",
    ]
    for index in range(3):
        if not tree.is_text(actual[index], expected[index]):
            raise Error(
                "anatomy report has stale "
                + keys[index]
                + "; regenerate on Linux with mojo run -I ."
                " tools/anatomy_validity.mojo --build --output"
                " docs/validation/anatomy-template-report.json"
            )


def _fixture() raises -> Tree:
    """A probe that imports a package module, a cited input, and an
    unrelated module, with the binding code beside them."""
    var tree = Tree()
    tree.write(
        "tools/anatomy_probe.mojo",
        (
            "from pkg.bound import value\nfrom std.sys import argv\n\n\n"
            'def main():\n    """Mentions import of prose that is not a'
            ' module."""\n    print(value())\n'
        ),
    )
    tree.write(
        "pkg/bound.mojo",
        (
            "from helper import other\n\n\ndef value() -> Int:\n    return"
            " other()\n"
        ),
    )
    tree.write("helper.mojo", "def other() -> Int:\n    return 1\n")
    tree.write("cited.mojo", "def cited():\n    pass\n")
    tree.write("unrelated.mojo", "def unrelated():\n    pass\n")
    tree.write("tools/anatomy_validity.mojo", "report logic")
    tree.write("tools/_imports.mojo", "resolver")
    tree.write(
        "docs/validation/anatomy-provenance.json",
        '{"parameters": [{"source_files": ["cited.mojo"]}]}',
    )
    return tree^


def test_the_binding_is_the_closure_cited_inputs_and_code() raises:
    var root = _fixture()
    var expected: List[String] = [
        "cited.mojo",
        "docs/validation/anatomy-provenance.json",
        "helper.mojo",
        "pkg/bound.mojo",
        "tools/_imports.mojo",
        "tools/anatomy_probe.mojo",
        "tools/anatomy_validity.mojo",
    ]
    assert_true(bound_paths(root.root) == expected)
    root.close()


def _apply(root: Tree, change: String) raises:
    """Apply one change to a fixture tree."""
    if change == "closure":
        root.write("helper.mojo", "def other() -> Int:\n    return 2\n")
    elif change == "probe":
        root.write(
            "tools/anatomy_probe.mojo",
            "from pkg.bound import value\n\n\ndef main():\n    pass\n",
        )
    elif change == "shadow":
        # A module beside the entry point shadows the root one.
        root.write("tools/helper.mojo", "def other() -> Int:\n    return 3\n")
    elif change == "cited":
        root.write("cited.mojo", "def cited():\n    return\n")
    elif change == "logic":
        root.write("tools/anatomy_validity.mojo", "changed logic")
    elif change == "resolver":
        root.write("tools/_imports.mojo", "changed resolver")
    elif change == "inventory":
        root.write(
            "docs/validation/anatomy-provenance.json",
            '{"parameters": [{"source_files": ["cited.mojo"]}], "note": 1}',
        )
    elif change == "unrelated":
        root.write("unrelated.mojo", "def changed():\n    pass\n")
    elif change == "added_unrelated":
        root.write("other/new.mojo", "def new():\n    pass\n")


def test_bound_changes_stale_the_report_and_others_do_not() raises:
    for change in [
        "closure",
        "probe",
        "shadow",
        "cited",
        "logic",
        "resolver",
        "inventory",
        "unrelated",
        "added_unrelated",
    ]:
        var root = _fixture()
        var before = source_digest(root.root)
        _apply(root, change)
        var after = source_digest(root.root)
        if change == "unrelated" or change == "added_unrelated":
            assert_equal(before, after, change)
        else:
            assert_true(before != after, change)
        root.close()


def test_the_build_contract_is_bound() raises:
    var root = _fixture()
    var before = source_digest(root.root)
    assert_equal(
        source_snapshot(
            root.root, BINDING_VERSION, PINNED_TOOLCHAIN, build_flags()
        ).digest,
        before,
    )
    assert_true(
        source_snapshot(
            root.root, BINDING_VERSION, "Mojo 1.2.0 (other)", build_flags()
        ).digest
        != before
    )
    assert_true(
        source_snapshot(
            root.root, BINDING_VERSION, PINNED_TOOLCHAIN, ["--Werror"]
        ).digest
        != before
    )
    assert_true(
        source_snapshot(
            root.root, "anatomy-binding-v5", PINNED_TOOLCHAIN, build_flags()
        ).digest
        != before
    )
    root.close()


def _refuse(root: Tree, name: String) raises:
    """Make one fixture tree unbindable."""
    if name == "missing probe":
        root.remove("tools/anatomy_probe.mojo")
    elif name == "missing cited input":
        root.remove("cited.mojo")
    elif name == "missing binding code":
        root.remove("tools/_imports.mojo")
    elif name == "unresolved import":
        root.write("pkg/bound.mojo", "from nowhere import other\n")
    elif name == "relative import":
        root.write("pkg/bound.mojo", "from .helper import other\n")
    elif name == "missing module in a package":
        # An existing ancestor does not stand for a missing module.
        root.write("pkg/__init__.mojo", "")
        root.write("pkg/bound.mojo", "from pkg.missing import other\n")
    elif name == "missing module beside a module":
        root.write("pkg/bound.mojo", "import helper.missing\n")
    elif name == "unreadable import":
        root.write("pkg/bound.mojo", "import 3d\n")
    elif name == "unclosed import list":
        root.write("pkg/bound.mojo", "from helper import (other\n")
    elif name == "unended string":
        root.write(
            "pkg/bound.mojo", 'var text = "open\nfrom helper import other\n'
        )


def test_unbindable_inputs_are_refused() raises:
    for name in [
        "missing probe",
        "missing cited input",
        "missing binding code",
        "unresolved import",
        "relative import",
        "missing module in a package",
        "missing module beside a module",
        "unreadable import",
        "unclosed import list",
        "unended string",
    ]:
        var root = _fixture()
        _refuse(root, name)
        with assert_raises():
            _ = source_digest(root.root)
        root.close()


def _imports(text: String) raises -> String:
    """Return the imports of a source as `module:name,name` lines."""
    var out = String()
    for found in imports_of(text):
        out += found.module
        if not found.plain:
            out += ":" + ",".join(found.names)
        out += "\n"
    return out^


def test_imports_are_read_as_the_compiler_reads_them() raises:
    # Prose and strings hold no imports, and an alias can follow a tab.
    var probe = String(
        '"""Prose that is not code.\n\nimport missing\n'
        'from .example import value\n"""\n'
        "from pkg import bound\tas renamed\n"
        "from helper import (\n    other\tas\tanother,  # import nowhere\n)\n"
        "var text = r'from .x import y\\'\n"
        "\n\ndef main():\n    pass\n"
    )
    var root = _fixture()
    root.write("pkg/__init__.mojo", "")
    root.write("tools/anatomy_probe.mojo", probe)
    assert_equal(_imports(probe), "pkg:bound\nhelper:other\n")
    var bound = bound_paths(root.root)
    assert_true("pkg/bound.mojo" in bound)
    assert_true("helper.mojo" in bound)
    var before = source_digest(root.root)
    root.write("pkg/bound.mojo", "def value() -> Int:\n    return 4\n")
    assert_true(source_digest(root.root) != before)
    # A file's CR LF and CR line ends read as Python's universal newlines
    # read them.
    root.write(
        "tools/anatomy_probe.mojo",
        "import cited\r\nimport helper\rdef main():\r    pass\r\n",
    )
    bound = bound_paths(root.root)
    assert_true("cited.mojo" in bound and "helper.mojo" in bound)
    assert_false("pkg/bound.mojo" in bound)
    root.close()


def test_each_alias_spacing_binds_its_module() raises:
    # Pinned Mojo 1.1.0 compiles all six forms. Each one alone must bind the
    # module it imports.
    for form in [
        "import pkg.bound as renamed",
        "import pkg.bound\tas renamed",
        "import pkg.bound as\trenamed",
        "from pkg import bound as renamed",
        "from pkg import bound\tas renamed",
        "from pkg import bound as\trenamed",
    ]:
        var root = _fixture()
        root.write("pkg/__init__.mojo", "")
        root.write(
            "tools/anatomy_probe.mojo", form + "\n\n\ndef main():\n    pass\n"
        )
        assert_true("pkg/bound.mojo" in bound_paths(root.root), form)
        var before = source_digest(root.root)
        root.write("pkg/bound.mojo", "def value() -> Int:\n    return 5\n")
        assert_true(source_digest(root.root) != before, form)
        root.close()


def test_a_local_file_under_a_toolchain_name_is_bound() raises:
    # Pinned Mojo 1.1.0 reads a local max/sentinel.mojo for `max.sentinel`,
    # with or without max/__init__.mojo. A local file under `std` is bound
    # as well, which can only bind more.
    for package in ["max", "std"]:
        for explicit in [False, True]:
            var root = _fixture()
            if explicit:
                root.write(package + "/__init__.mojo", "")
            root.write(
                package + "/sentinel.mojo",
                "def value() -> Int:\n    return 42\n",
            )
            root.write(
                "tools/anatomy_probe.mojo",
                "from "
                + package
                + ".sentinel import value\nfrom "
                + package
                + ".absent import other\n\n\ndef main():\n    pass\n",
            )
            assert_true(package + "/sentinel.mojo" in bound_paths(root.root))
            var before = source_digest(root.root)
            root.write(
                package + "/sentinel.mojo",
                "def value() -> Int:\n    return 7\n",
            )
            assert_true(source_digest(root.root) != before)
            root.close()


def test_plain_imports_and_symbols_are_kept_apart() raises:
    assert_equal(
        _imports(
            "import pkg.bound as bound, helper\nfrom pkg import *\nimport"
            " a.b; import c\n"
        ),
        "pkg.bound\nhelper\npkg:\na.b\nc\n",
    )
    for unreadable in [
        "from pkg import a.b\n",
        "from pkg import\n",
        "import\n",
        "from 3d import x\n",
        "import pkg as\n",
        "from pkg import ()\n",
        "from pkg import ,\n",
    ]:
        with assert_raises(contains="cannot read the import"):
            _ = imports_of(unreadable)
    with assert_raises(contains="relative imports"):
        _ = imports_of("from .pkg import x\n")
    # A name that only starts like an import is not one.
    assert_equal(_imports("from_here = 1\nimported = 2\n"), "")


def test_missing_and_stale_reports_are_rejected() raises:
    for mutation in [
        "none",
        "source",
        "logic",
        "inventory",
        "missing_report",
        "missing_key",
        "report_logic_hash",
    ]:
        var root = _fixture()
        var snapshot = source_snapshot(root.root)
        var tree = JsonTree()
        var report = tree.object()
        var provenance = tree.object()
        tree.set_text(provenance, "source_sha256", snapshot.digest)
        tree.set(report, "build_provenance", provenance)
        tree.set_text(
            report, "report_logic_sha256", snapshot.hash(REPORT_LOGIC)
        )
        tree.set_text(report, "inventory_sha256", snapshot.hash(INVENTORY))
        if mutation == "source":
            root.write("helper.mojo", "def other() -> Int:\n    return 9\n")
        elif mutation == "logic":
            root.write("tools/anatomy_validity.mojo", "changed logic")
            # Keep the digest current to check the separate hash.
            tree.set_text(provenance, "source_sha256", source_digest(root.root))
        elif mutation == "inventory":
            root.write(
                "docs/validation/anatomy-provenance.json",
                '{"parameters": [{"source_files": ["cited.mojo"]}], "v": 2}',
            )
            tree.set_text(provenance, "source_sha256", source_digest(root.root))
        elif mutation == "missing_key":
            _ = tree.pop(provenance, "source_sha256")
        elif mutation == "report_logic_hash":
            tree.set_text(report, "report_logic_sha256", "wrong")
        if mutation != "missing_report":
            root.write(REPORT, tree.dumps(report, False))
        if mutation == "none":
            check_binding(root.root)
        else:
            with assert_raises():
                check_binding(root.root)
        root.close()


def check_metadata(tree: JsonTree, report: Int) raises:
    """Refuse an example whose binding, scope or counts changed.

    Args:
        tree: The tree.
        report: The example report.

    Raises:
        Error: If the binding, the probe fingerprint, the scope or the
            counts differ from the recorded ones.
    """
    var provenance = tree.item(report, "build_provenance")
    if not tree.is_text(tree.item(provenance, "source_sha256"), SOURCE_SHA256):
        raise Error("historical example source binding changed")
    if not tree.is_text(tree.item(provenance, "binary_sha256"), PROBE_SHA256):
        raise Error("historical example probe fingerprint changed")
    var inventory = tree.item(report, "pair_inventory")
    var checked = 0
    var omitted = 0
    var other = 0
    var pairs = tree.item(inventory, "pairs")
    for pair in tree.items(pairs):
        var status = tree.item(pair, "status")
        if tree.is_text(status, "checked"):
            checked += 1
        elif tree.is_text(status, "intentionally_omitted"):
            omitted += 1
        else:
            other += 1
    if (
        not tree.is_text(tree.item(inventory, "run_scope"), "representative")
        or not tree.is_number(tree.item(inventory, "total_pairs"), 8911)
        or tree.length(pairs) != 8911
        or checked != 528
        or omitted != 8383
        or other != 0
    ):
        raise Error("historical representative scope or counts changed")


def check_pinned_example(path: String) raises:
    """Refuse an example whose bytes or metadata changed.

    Args:
        path: The example file.

    Raises:
        Error: If the checksum or the metadata changed.
    """
    var data = Path(path).read_bytes()
    if sha256_hex(data) != REPORT_SHA256:
        raise Error("historical example checksum changed")
    var tree = JsonTree()
    check_metadata(tree, tree.parse(String(from_utf8=Span(data))))


def test_example_is_pinned_to_its_recorded_source_not_current_head() raises:
    check_pinned_example(EXAMPLE)
    var text = Path("docs/validation/anatomy-pairs-596.md").read_text()
    assert_true(text.find(SOURCE_COMMIT) >= 0)
    assert_true(text.find("not a report of the current checkout") >= 0)


def test_changed_example_bytes_are_rejected() raises:
    var root = Tree()
    root.write("example.json", Path(EXAMPLE).read_text() + " ")
    with assert_raises(contains="checksum"):
        check_pinned_example(root.root + "/example.json")
    root.close()


def test_changed_example_binding_or_scope_is_rejected() raises:
    var tree = JsonTree()
    var original = tree.parse(Path(EXAMPLE).read_text())
    check_metadata(tree, original)
    for mutation in range(5):
        var report = tree.clone(original)
        var provenance = tree.item(report, "build_provenance")
        var inventory = tree.item(report, "pair_inventory")
        if mutation == 0:
            tree.set_text(provenance, "source_sha256", "0" * 64)
        elif mutation == 1:
            tree.set_text(provenance, "binary_sha256", "0" * 64)
        elif mutation == 2:
            tree.set_text(inventory, "run_scope", "full")
        elif mutation == 3:
            tree.set(inventory, "total_pairs", tree.integer(8910))
        else:
            var first = tree.at(tree.item(inventory, "pairs"), 0)
            tree.set_text(first, "status", "unsupported")
        with assert_raises():
            check_metadata(tree, report)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
