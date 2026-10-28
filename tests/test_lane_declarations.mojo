# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Lane-control declarations stay in the requested order."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._python_tokens import replace_firsts
from tools._lane_control_labels import lane_control_labels
from tools._lane_declarations import (
    declaration_fallbacks,
    declaration_match_flags,
    declaration_texts_and_flags,
    lane_control_prepare,
    lane_control_prepare_with_labels,
    lane_declarations,
)
from tools._python_json import PyJson


def _payload(name: String, owner_name: String) raises -> String:
    """Return two declaration pins.

    Args:
        name: The first function name.
        owner_name: An owner for the first function. Empty means none.

    Returns:
        A JSON list.

    Raises:
        Error: The payload cannot be written.
    """
    var source = "def f():\n    return 1\n\ndef g():\n    return 2\n"
    var doc = PyJson()
    var rows = doc.new_list()
    var first = doc.new_dict()
    doc.set(first, "source", doc.new_str(source))
    doc.set(first, "name", doc.new_str(name))
    var owners = doc.new_list()
    if owner_name.byte_length() > 0:
        doc.append(owners, doc.new_str(owner_name))
    doc.set(first, "owner", owners)
    doc.append(rows, first)
    var second = doc.new_dict()
    doc.set(second, "source", doc.new_str(source))
    doc.set(second, "name", doc.new_str("g"))
    doc.set(second, "owner", doc.new_list())
    doc.append(rows, second)
    doc.root = rows
    return doc.dumps()


def test_lane_declarations_keep_their_order() raises:
    """`f` comes back before `g`."""
    var doc = PyJson.parse(lane_declarations(_payload("f", "")))
    assert_equal(doc.length(doc.root), 2)
    assert_true(doc.text(doc.item(doc.root, 0)).find("return 1") >= 0)
    assert_true(doc.text(doc.item(doc.root, 1)).find("return 2") >= 0)
    assert_true(doc.text(doc.item(doc.root, 0)).find("return 2") < 0)


def test_a_missing_lane_declaration_is_refused() raises:
    """The first missing name is reported."""
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: absent"
    ):
        _ = lane_declarations(_payload("absent", ""))


def test_a_wrong_lane_owner_is_refused() raises:
    """A top-level function is not inside another struct."""
    with assert_raises(contains="guard caller owner/scope changed: f"):
        _ = lane_declarations(_payload("f", "Nope"))


def test_prepare_renames_before_it_reads_declarations() raises:
    """The renamed texts and the declarations come back in one result."""
    var payload = (
        '{"replacements":[{"source":"def f():\\n    return 1\\n",'
        + '"old":"f","new":"reference_f"}],'
        + '"declarations":[{"source":"def f():\\n    return 1\\n",'
        + '"name":"f","owner":[]}]}'
    )
    var prepared = PyJson.parse(lane_control_prepare(payload))
    var replaced = PyJson.parse(
        replace_firsts(
            '[{"source":"def f():\\n    return'
            ' 1\\n","old":"f","new":"reference_f"}]'
        )
    )
    var declared = PyJson.parse(
        lane_declarations(
            '[{"source":"def f():\\n    return 1\\n","name":"f","owner":[]}]'
        )
    )
    var got_replaced = prepared.at(prepared.root, "replaced")
    var got_declared = prepared.at(prepared.root, "declared")
    assert_equal(
        prepared.text(prepared.item(got_replaced, 0)),
        replaced.text(replaced.item(replaced.root, 0)),
    )
    assert_equal(
        prepared.text(prepared.item(got_declared, 0)),
        declared.text(declared.item(declared.root, 0)),
    )


def test_prepare_reads_the_labels_before_the_declarations() raises:
    """The frozen name uses the reviewed reference prefix."""
    var source = "def f():\\n    return 1\\n"
    var reference = "def _referencef():\\n    return 1\\n"
    var payload = (
        '{"before_source":"'
        + source
        + '","current":"'
        + source
        + '","declarations":[{"name":"f","before":"'
        + source
        + '","test":"'
        + reference
        + '"}],"premises":[]}'
    )
    var prepared = PyJson.parse(lane_control_prepare_with_labels(payload))
    var got_labels = prepared.at(prepared.root, "labels")
    var labels = PyJson.parse(lane_control_labels())
    assert_equal(
        prepared.text(prepared.at(got_labels, "reference")),
        labels.text(labels.at(labels.root, "reference")),
    )
    assert_equal(prepared.text(prepared.at(got_labels, "definition")), "def ")
    var replaced = prepared.at(prepared.root, "replaced")
    assert_equal(
        prepared.text(prepared.item(replaced, 0)),
        "def _referencef():\n    return 1\n",
    )
    var declared = prepared.at(prepared.root, "declared")
    assert_equal(prepared.length(declared), 3)
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: absent"
    ):
        _ = lane_control_prepare_with_labels(
            '{"before_source":"'
            + source
            + '","current":"'
            + source
            + '","declarations":[{"name":"absent","before":"'
            + source
            + '","test":"'
            + source
            + '"}],"premises":[]}'
        )


def test_prepare_reports_a_missing_declaration() raises:
    """A missing function fails after the rename fields are accepted."""
    var payload = (
        '{"replacements":[{"source":"def f():\\n    return 1\\n",'
        + '"old":"f","new":"reference_f"}],'
        + '"declarations":[{"source":"def f():\\n    return 1\\n",'
        + '"name":"absent","owner":[]}]}'
    )
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: absent"
    ):
        _ = lane_control_prepare(payload)


def test_a_declaration_match_compares_significant_tokens() raises:
    """A comment does not change a match, and the next declaration keeps its result.
    """
    var payload = (
        '[{"source":"def f():\\n    return 1\\n","name":"f","owner":[],'
        + '"expected":"def f():\\n    # note\\n    return 1\\n"},'
        + '{"source":"def f():\\n    return 1\\n","name":"f","owner":[],'
        + '"expected":"def f():\\n    return 2\\n"}]'
    )
    assert_equal(declaration_match_flags(payload), '["true","false"]')


def test_a_declaration_match_reports_a_missing_function_first() raises:
    """A missing function fails before the recorded source is compared."""
    var payload = (
        '[{"source":"def f():\\n    return 1\\n","name":"absent","owner":[],'
        + '"expected":"def f():\\n    return 1\\n"}]'
    )
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: absent"
    ):
        _ = declaration_match_flags(payload)


def test_texts_and_flags_compare_only_the_selected_items() raises:
    """Items without `expected` stay in the declaration list and add no flag."""
    var payload = (
        '[{"source":"def f():\\n    return 1\\n","name":"f","owner":[],'
        + '"expected":"def f():\\n    # note\\n    return 1\\n"},'
        + '{"source":"def g():\\n    return 2\\n","name":"g","owner":[]},'
        + '{"source":"def f():\\n    return 1\\n","name":"f","owner":[],'
        + '"expected":"def f():\\n    return 2\\n"}]'
    )
    var parsed = PyJson.parse(declaration_texts_and_flags(payload))
    var declared = parsed.at(parsed.root, "declared")
    var flags = parsed.at(parsed.root, "flags")
    assert_equal(parsed.length(declared), 3)
    assert_equal(parsed.length(flags), 2)
    assert_equal(parsed.text(parsed.item(flags, 0)), "true")
    assert_equal(parsed.text(parsed.item(flags, 1)), "false")
    assert_true(parsed.text(parsed.item(declared, 1)).find("return 2") >= 0)


def test_empty_declaration_fallbacks_stay_empty() raises:
    """No premises produce no flags and no choices."""
    var parsed = PyJson.parse(declaration_fallbacks("[]"))
    assert_equal(parsed.length(parsed.at(parsed.root, "flags")), 0)
    assert_equal(parsed.length(parsed.at(parsed.root, "fallbacks")), 0)


def test_a_missing_declaration_fails_before_its_fallback() raises:
    """A missing function is reported before the path is required."""
    var payload = (
        '[{"source":"def f():\\n    return 1\\n","name":"absent",'
        + '"owner":[],"expected":"def f():\\n    return 1\\n"}]'
    )
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: absent"
    ):
        _ = declaration_fallbacks(payload)


def test_a_fallback_requires_the_path_after_the_comparison() raises:
    """A readable declaration still requires `path` for its fallback."""
    var payload = (
        '[{"source":"def f():\\n    return 1\\n","name":"f","owner":[],'
        + '"expected":"def f():\\n    return 1\\n"}]'
    )
    with assert_raises(contains="KeyError: 'path'"):
        _ = declaration_fallbacks(payload)


def test_declaration_fallbacks_keep_match_and_choice() raises:
    """A match stays `none`, and a changed seed or lane chooses that predecessor.
    """
    var payload = (
        '[{"source":"def _try_winner_seed():\\n    return 1\\n",'
        + '"name":"_try_winner_seed","owner":[],'
        + '"expected":"def _try_winner_seed():\\n    return 1\\n",'
        + '"path":"extensions/carla/map.mojo"},'
        + '{"source":"struct Map:\\n    def _try_winner_seed(self):\\n       '
        ' return 1\\n",'
        + '"name":"_try_winner_seed","owner":["Map"],'
        + '"expected":"def _try_winner_seed(self):\\n    return 2\\n",'
        + '"path":"extensions/carla/map.mojo"},'
        + '{"source":"def _try_winner_seed():\\n    return 1\\n",'
        + '"name":"_try_winner_seed","owner":[],'
        + '"expected":"def _try_winner_seed():\\n    return 2\\n",'
        + '"path":"extensions/carla/map.mojo"},'
        + '{"source":"def lane():\\n    return 1\\n","name":"lane","owner":[],'
        + '"expected":"def lane():\\n    return 2\\n",'
        + '"path":"extensions/carla/lane_refinement.mojo"}]'
    )
    var parsed = PyJson.parse(declaration_fallbacks(payload))
    var flags = parsed.at(parsed.root, "flags")
    var choices = parsed.at(parsed.root, "fallbacks")
    assert_equal(parsed.text(parsed.item(flags, 0)), "true")
    assert_equal(parsed.text(parsed.item(choices, 0)), "none")
    assert_equal(parsed.text(parsed.item(flags, 1)), "false")
    assert_equal(parsed.text(parsed.item(choices, 1)), "none")
    assert_equal(parsed.text(parsed.item(flags, 2)), "false")
    assert_equal(parsed.text(parsed.item(choices, 2)), "seed")
    assert_equal(parsed.text(parsed.item(flags, 3)), "false")
    assert_equal(parsed.text(parsed.item(choices, 3)), "lane")


def main() raises:
    """Run the lane declaration tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
