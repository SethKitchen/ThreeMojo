# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed rounded LINE singleton record fails the gate."""

from std.testing import TestSuite, assert_raises, assert_true

from std.os import makedirs
from std.pathlib import Path
from tests._python_tokens import declaration_text
from tools._python_json import PyJson
from tools.carla_singleton_gate import (
    checked_import_scopes,
    singleton_graphs,
    singleton_path,
    singleton_record,
    singleton_restored_graphs,
    singleton_source_graphs,
    singleton_views,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="rounded LINE singleton contract: unreviewed migration record"
    ):
        singleton_record(String("").as_bytes())


def test_disagreeing_lane_views_are_refused() raises:
    """Text and decoded views with different tokens fail closed."""
    with assert_raises(
        contains=(
            "rounded LINE singleton contract: consumer lane source text/bytes"
            " disagree"
        )
    ):
        singleton_views(
            "def changed():\n    pass\n", "def other():\n    pass\n"
        )


def test_a_changed_selector_path_is_refused() raises:
    """A selector path that is not the requested path fails closed."""
    with assert_raises(
        contains=(
            "rounded LINE singleton contract: wrong selector predecessor path"
        )
    ):
        singleton_path(
            "extensions/carla/other.mojo",
            "extensions/carla/curve_rounded_line.mojo",
        )


def test_a_changed_consumer_graph_is_refused() raises:
    """A consumer token list that changed fails closed."""
    var directory = "/tmp/singleton-graphs-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"label":"consumer import scope changed: lane.mojo",'
        + '"actual":"[]","expected":"[[1,\\"def\\"]]"}]'
    )
    with assert_raises(
        contains=(
            "rounded LINE singleton contract: consumer import scope changed:"
            " lane.mojo"
        )
    ):
        singleton_graphs(directory)


def test_a_changed_consumer_source_is_refused() raises:
    """A changed consumer source fails after both texts are tokenized."""
    var payload = (
        '[{"label":"consumer import scope changed: lane.mojo",'
        + '"actual":"def center():\\n    return 1\\n",'
        + '"source":"def center():\\n    return 2\\n"},'
        + '{"label":"later","actual":"def later():\\n    return 1\\n",'
        + '"source":"def later():\\n    return 1\\n"}]'
    )
    with assert_raises(
        contains=(
            "rounded LINE singleton contract: consumer import scope changed:"
            " lane.mojo"
        )
    ):
        singleton_source_graphs(payload)


def test_matching_consumer_sources_are_accepted() raises:
    """Identical consumer sources pass in one check."""
    var payload = (
        '[{"label":"consumer import scope changed: lane.mojo",'
        + '"actual":"def center():\\n    return 1\\n",'
        + '"source":"def center():\\n    return 1\\n"}]'
    )
    singleton_source_graphs(payload)


def _add_restore(
    mut doc: PyJson,
    rows: Int,
    index: Int,
    source: String,
    name: String,
    owner_name: String,
):
    """Append one restore pin.

    Args:
        doc: The payload document.
        rows: The restore list.
        index: The graph position this declaration replaces.
        source: The module that owns the function.
        name: The function name.
        owner_name: The enclosing struct. Empty means none.
    """
    var row = doc.new_dict()
    doc.set(row, "index", doc.new_int(index))
    doc.set(row, "source", doc.new_str(source))
    doc.set(row, "name", doc.new_str(name))
    var owners = doc.new_list()
    if owner_name.byte_length() > 0:
        doc.append(owners, doc.new_str(owner_name))
    doc.set(row, "owner", owners)
    doc.append(rows, row)


def _add_graph(
    mut doc: PyJson, rows: Int, label: String, actual: String, source: String
):
    """Append one source graph.

    Args:
        doc: The payload document.
        rows: The graph list.
        label: The failure text, without the contract prefix.
        actual: The declaration text before a restore replaces it.
        source: The recorded declaration text.
    """
    var row = doc.new_dict()
    doc.set(row, "label", doc.new_str(label))
    doc.set(row, "actual", doc.new_str(actual))
    doc.set(row, "source", doc.new_str(source))
    doc.append(rows, row)


def test_a_missing_restored_declaration_fails_before_the_graph() raises:
    """A missing function is reported before a changed graph."""
    var doc = PyJson()
    var root = doc.new_dict()
    var restores = doc.new_list()
    _add_restore(doc, restores, 0, "def f():\n    return 1\n", "absent", "")
    var graphs = doc.new_list()
    _add_graph(
        doc,
        graphs,
        "later",
        "def a():\n    return 1\n",
        "def a():\n    return 2\n",
    )
    doc.set(root, "restores", restores)
    doc.set(root, "graphs", graphs)
    doc.root = root
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: absent"
    ):
        singleton_restored_graphs(doc.dumps())


def test_a_restored_declaration_graph_is_refused() raises:
    """The restored declaration replaces the graph before the compare."""
    var source = "struct Box:\n    def changed(self):\n        return 9\n"
    var owners = List[String]()
    owners.append("Box")
    var restored = declaration_text(source, "changed", owners)
    assert_true(restored.find("return 9") >= 0)
    var doc = PyJson()
    var root = doc.new_dict()
    var restores = doc.new_list()
    _add_restore(doc, restores, 1, source, "changed", "Box")
    var graphs = doc.new_list()
    _add_graph(
        doc,
        graphs,
        "consumer/reference declaration changed: keep",
        "def keep():\n    return 1\n",
        "def keep():\n    return 1\n",
    )
    _add_graph(
        doc,
        graphs,
        "consumer/reference declaration changed: changed",
        "def changed(self):\n    return 1\n",
        "def changed(self):\n    return 1\n",
    )
    doc.set(root, "restores", restores)
    doc.set(root, "graphs", graphs)
    doc.root = root
    with assert_raises(
        contains=(
            "rounded LINE singleton contract: consumer/reference declaration"
            " changed: changed"
        )
    ):
        singleton_restored_graphs(doc.dumps())


def test_restored_declaration_graphs_are_accepted() raises:
    """A restored declaration that matches its record passes."""
    var source = "def keep():\n    return 1\n\ndef changed():\n    return 2\n"
    var owners = List[String]()
    var keep = declaration_text(source, "keep", owners)
    var changed = declaration_text(source, "changed", owners)
    var doc = PyJson()
    var root = doc.new_dict()
    var restores = doc.new_list()
    _add_restore(doc, restores, 0, source, "keep", "")
    _add_restore(doc, restores, 1, source, "changed", "")
    var graphs = doc.new_list()
    _add_graph(
        doc,
        graphs,
        "consumer/reference declaration changed: keep",
        "def keep():\n    return 9\n",
        keep,
    )
    _add_graph(
        doc,
        graphs,
        "consumer/reference declaration changed: changed",
        "def changed():\n    return 9\n",
        changed,
    )
    _add_graph(
        doc,
        graphs,
        "other",
        "def other():\n    return 3\n",
        "def other():\n    return 3\n",
    )
    doc.set(root, "restores", restores)
    doc.set(root, "graphs", graphs)
    doc.root = root
    singleton_restored_graphs(doc.dumps())


def test_an_unrestored_graph_is_still_refused() raises:
    """Empty restores still compare every graph."""
    var doc = PyJson()
    var root = doc.new_dict()
    var graphs = doc.new_list()
    _add_graph(
        doc,
        graphs,
        "consumer/reference declaration changed: f",
        "def f():\n    return 1\n",
        "def f():\n    return 2\n",
    )
    doc.set(root, "restores", doc.new_list())
    doc.set(root, "graphs", graphs)
    doc.root = root
    with assert_raises(
        contains=(
            "rounded LINE singleton contract: consumer/reference declaration"
            " changed: f"
        )
    ):
        singleton_restored_graphs(doc.dumps())


def test_restores_are_read_before_a_bad_graph_list() raises:
    """A readable restore still refuses a graph payload that is not a list."""
    var doc = PyJson()
    var root = doc.new_dict()
    var restores = doc.new_list()
    _add_restore(doc, restores, 0, "def f():\n    return 1\n", "f", "")
    doc.set(root, "restores", restores)
    doc.set(root, "graphs", doc.new_dict())
    doc.root = root
    with assert_raises(
        contains=(
            "rounded LINE singleton contract: consumer import scope changed"
        )
    ):
        singleton_restored_graphs(doc.dumps())


def test_a_changed_lane_scope_requests_a_restore() raises:
    """A different lane prefix is returned before the other graphs are checked.
    """
    var payload = (
        '{"texts":["import a\\ndef f():\\n    pass\\n","import b\\n'
        + 'def g():\\n    pass\\n"],"expected":["import b","import b"],'
        + '"labels":["lane","other"],"lane":0}'
    )
    var parsed = PyJson.parse(checked_import_scopes(payload))
    assert_true(parsed.flag(parsed.at(parsed.root, "restore")))


def test_a_matching_lane_scope_checks_the_other_graph() raises:
    """The other graph fails after the lane scope matches."""
    var payload = (
        '{"texts":["import a\\ndef f():\\n    pass\\n","import b\\n'
        + 'def g():\\n    pass\\n"],"expected":["import a","import c"],'
        + '"labels":["lane","other"],"lane":0}'
    )
    with assert_raises(contains="rounded LINE singleton contract: other"):
        _ = checked_import_scopes(payload)


def test_matching_import_scopes_need_no_restore() raises:
    """Matching scopes pass in one check."""
    var payload = (
        '{"texts":["import a\\ndef f():\\n    pass\\n"],'
        + '"expected":["import a"],"labels":["lane"],"lane":0}'
    )
    var parsed = PyJson.parse(checked_import_scopes(payload))
    assert_true(not parsed.flag(parsed.at(parsed.root, "restore")))


def main() raises:
    """Run the singleton gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
