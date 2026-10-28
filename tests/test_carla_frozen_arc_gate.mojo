# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed frozen ARC producer record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import declaration_routing
from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools.carla_frozen_arc_gate import (
    frozen_arc_digest,
    frozen_digest_and_token,
    frozen_arc_functions,
    frozen_arc_layout,
    frozen_arc_places,
    frozen_arc_prior,
    frozen_arc_record,
    frozen_arc_token,
    frozen_producer_review,
    frozen_runtime_predecessor,
)


def test_a_function_suite_is_omitted_from_routing() raises:
    """A function body is not part of the declaration routing."""
    assert_equal(
        declaration_routing("def first():\n    return 1\n"),
        '[[[],[[1,"def"],[1,"first"],[55,"("],[55,")"],[55,":"]]]]',
    )


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="frozen ARC producer contract: unreviewed migration record"
    ):
        frozen_arc_record(String("").as_bytes(), String("").as_bytes(), False)


def test_a_changed_guard_pin_is_refused() raises:
    """A different guard-pin digest fails closed."""
    with assert_raises(
        contains="frozen ARC producer contract: guard pin lineage changed"
    ):
        frozen_arc_digest(String("nope").as_bytes(), "00", "guard")


def test_a_changed_successor_token_is_refused() raises:
    """A source that does not have the recorded token digest fails closed."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: complete frozen ARC successor"
            " changed"
        )
    ):
        frozen_arc_token("def changed():\n    pass\n", "00")


def test_a_different_prior_pin_is_refused() raises:
    """A runtime pin predecessor that differs from the cleanup record fails closed.
    """
    with assert_raises(
        contains=(
            "frozen ARC producer contract: runtime pin predecessor differs"
            " from accepted cleanup"
        )
    ):
        frozen_arc_prior("aa", "bb")


def test_a_wrong_runtime_placement_is_refused() raises:
    """A placement outside the reviewed set fails closed."""
    var directory = "/tmp/frozen-places-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text("[]")
    with assert_raises(
        contains=(
            "frozen ARC producer contract: wrong runtime successor placements"
        )
    ):
        frozen_arc_places(directory)


def test_a_changed_producer_function_is_refused() raises:
    """A producer function whose token list changed fails closed."""
    var directory = "/tmp/frozen-functions-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"name":"center","actual":"[]","expected":"[[1,\\"def\\"]]"}]'
    )
    with assert_raises(
        contains=(
            "frozen ARC producer contract: complete producer/Box function"
            " changed: center"
        )
    ):
        frozen_arc_functions(directory)


def test_a_changed_arc_layout_is_refused() raises:
    """A RoundedArc routing text that changed fails closed."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: RoundedArc/Box field layout,"
            " imports, or declaration owners changed"
        )
    ):
        frozen_arc_layout("[]", "[[]]")


def _pin() -> String:
    """Return one active runtime pin."""
    return (
        "{\n"
        '  "groups": {\n'
        '    "eligibility": {\n'
        '      "extensions/carla/curve_frozen_arc.mojo": "new"\n'
        "    },\n"
        '    "optional_runtime": {\n'
        '      "extensions/carla/curve_frozen_arc.mojo": "new"\n'
        "    },\n"
        '    "translation": {\n'
        '      "extensions/carla/curve_frozen_arc.mojo": "new"\n'
        "    }\n"
        "  }\n"
        "}\n"
    )


def _restored() -> String:
    """Return the historical pin for `_pin`."""
    return (
        "{\n"
        '  "groups": {\n'
        '    "eligibility": {\n'
        '      "extensions/carla/curve_frozen_arc.mojo": "old"\n'
        "    },\n"
        '    "optional_runtime": {\n'
        '      "extensions/carla/curve_frozen_arc.mojo": "old"\n'
        "    },\n"
        '    "translation": {\n'
        '      "extensions/carla/curve_frozen_arc.mojo": "old"\n'
        "    }\n"
        "  }\n"
        "}\n"
    )


def _change(group: String, token: String) -> String:
    """Return one runtime successor transition.

    Args:
        group: The pin group.
        token: The active token.

    Returns:
        One JSON object.
    """
    return (
        '{"group":"'
        + group
        + '","path":"extensions/carla/curve_frozen_arc.mojo","after":"'
        + token
        + '","before":"old"}'
    )


def _request(token: String, before: String) -> String:
    """Return one predecessor request.

    Args:
        token: The active token stored in the pin.
        before: The required predecessor digest.

    Returns:
        The request JSON.
    """
    return (
        '{"after":"'
        + sha256_hex(_pin().as_bytes())
        + '","before":"'
        + before
        + '","groups":"groups","transitions":['
        + _change("eligibility", token)
        + ","
        + _change("optional_runtime", token)
        + ","
        + _change("translation", token)
        + "]}"
    )


def test_a_restored_runtime_pin_matches_its_predecessor() raises:
    """The historical tokens replace the active tokens in one check."""
    var restored = _restored()
    assert_equal(
        frozen_runtime_predecessor(
            _pin().as_bytes(),
            _request("new", sha256_hex(restored.as_bytes())),
        ),
        restored,
    )


def test_a_changed_runtime_pin_digest_is_refused_before_parse() raises:
    """A wrong active digest fails before the pin text is read."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: unreviewed runtime pin successor"
        )
    ):
        _ = frozen_runtime_predecessor("{".as_bytes(), _request("new", "00"))


def test_a_runtime_pin_with_the_wrong_placement_is_refused() raises:
    """A transition outside the reviewed set fails closed."""
    var request = (
        '{"after":"'
        + sha256_hex(_pin().as_bytes())
        + '","before":"00","groups":"groups","transitions":[]}'
    )
    with assert_raises(
        contains=(
            "frozen ARC producer contract: wrong runtime successor placements"
        )
    ):
        _ = frozen_runtime_predecessor(_pin().as_bytes(), request)


def test_a_changed_runtime_successor_token_is_refused() raises:
    """A placement whose token changed fails closed."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: runtime successor token mismatch"
        )
    ):
        _ = frozen_runtime_predecessor(
            _pin().as_bytes(), _request("other", "00")
        )


def test_a_changed_runtime_predecessor_digest_is_refused() raises:
    """A restored pin whose digest changed fails closed."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: runtime predecessor"
            " reconstruction failed"
        )
    ):
        _ = frozen_runtime_predecessor(_pin().as_bytes(), _request("new", "00"))


def _review(
    actual: String, source: String, name: String, arc: String, stored: String
) raises -> String:
    """Return one producer-review payload.

    Args:
        actual: The live declaration.
        source: The recorded declaration.
        name: The function name.
        arc: The rounded-arc source.
        stored: The recorded routing.

    Returns:
        The review JSON.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var functions = doc.new_list()
    var row = doc.new_dict()
    doc.set(row, "name", doc.new_str(name))
    doc.set(row, "actual", doc.new_str(actual))
    doc.set(row, "source", doc.new_str(source))
    doc.append(functions, row)
    doc.set(root, "functions", functions)
    var layout = doc.new_dict()
    doc.set(layout, "source", doc.new_str(arc))
    doc.set(layout, "stored", doc.new_str(stored))
    doc.set(root, "layout", layout)
    doc.root = root
    return doc.dumps()


def test_a_producer_review_accepts_the_recorded_function_and_layout() raises:
    """Matching tokens and routing pass in one check."""
    var arc = "def center():\n    return 1\n"
    frozen_producer_review(
        _review(arc, arc, "center", arc, declaration_routing(arc))
    )


def test_a_changed_producer_review_names_the_function() raises:
    """A changed function fails before the layout is considered."""
    var arc = "def center():\n    return 1\n"
    var changed = "def center():\n    return 2\n"
    with assert_raises(
        contains=(
            "frozen ARC producer contract: complete producer/Box function"
            " changed: center"
        )
    ):
        frozen_producer_review(
            _review(changed, arc, "center", arc, "not-the-routing")
        )


def test_a_changed_producer_layout_is_refused_after_the_functions() raises:
    """A changed arc routing fails after the functions match."""
    var arc = "def center():\n    return 1\n"
    with assert_raises(
        contains=(
            "frozen ARC producer contract: RoundedArc/Box field layout,"
            " imports, or declaration owners changed"
        )
    ):
        frozen_producer_review(_review(arc, arc, "center", arc, "[]"))


def test_a_producer_review_reads_the_declaration_from_the_module() raises:
    """The review extracts the function before it checks the arc layout."""
    var arc = "def center():\n    return 1\n"
    var payload = (
        '{"functions":[{"name":"center","module":"def other():\\n    return'
        " 0\\n\\n"
        + 'def center():\\n    return 1\\n","owner":[],'
        + '"source":"def center():\\n    return 1\\n"}],'
        + '"layout":{"source":"def center():\\n    return 1\\n","stored":"'
    )
    frozen_producer_review(
        payload + declaration_routing(arc).replace('"', '\\"') + '"}}'
    )


def test_a_missing_producer_declaration_is_refused_before_the_layout() raises:
    """A missing function fails before a bad arc layout is reported."""
    var payload = (
        '{"functions":[{"name":"absent","module":"def center():\\n    return'
        ' 1\\n",'
        + '"owner":[],"source":"def center():\\n    return 1\\n"}],'
        + '"layout":{"source":"def center():\\n    return 1\\n","stored":"[]"}}'
    )
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: absent"
    ):
        frozen_producer_review(payload)


def test_a_guard_digest_fails_before_the_successor_token() raises:
    """A changed guard pin is reported before the successor token."""
    with assert_raises(contains="guard pin lineage changed"):
        frozen_digest_and_token(
            '{"bytes":"nope","sha":"00","kind":"guard","text":"def f():\\n   '
            ' pass\\n","token":"00"}'
        )


def test_a_matching_guard_digest_checks_the_successor_token() raises:
    """The successor token is checked after the guard pin digest matches."""
    var payload = String("nope")
    var body = (
        '{"bytes":"nope","sha":"'
        + sha256_hex(payload.as_bytes())
        + '","kind":"guard","text":"def f():\\n    pass\\n","token":"00"}'
    )
    with assert_raises(contains="complete frozen ARC successor changed"):
        frozen_digest_and_token(body)


def main() raises:
    """Run the frozen ARC gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
