# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Historical pin values are written back in stored key order."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import apply_pin_transitions


def _pins() -> String:
    """Return one small pin document.

    Returns:
        JSON with `pins` and no transitions.
    """
    return (
        '{"pins":{"groups":{"g":{"a":"AFTER","b":"keep"}},"ids":[1,2],'
        + '"flag":true,"off":false,"empty":null,"ratio":1.5,"tail":1},'
        + '"transitions":['
    )


def test_pin_transitions_keep_stored_order() raises:
    """Edits replace values and leave the other keys in place."""
    assert_equal(
        apply_pin_transitions(_pins() + "]}"),
        '{"groups":{"g":{"a":"AFTER","b":"keep"}},"ids":[1,2],"flag":true,'
        + '"off":false,"empty":null,"ratio":1.5,"tail":1}',
    )
    assert_equal(
        apply_pin_transitions(
            _pins()
            + '{"pointer":["groups","g","a"],"before":"BEFORE"},'
            + '{"pointer":["tail"],"before":"x"},'
            + '{"pointer":["groups","g","c"],"before":"say \\"hi\\"\\n"}]}'
        ),
        '{"groups":{"g":{"a":"BEFORE","b":"keep","c":"say \\"hi\\"\\n"}},'
        + '"ids":[1,2],"flag":true,"off":false,"empty":null,"ratio":1.5,'
        + '"tail":"x"}',
    )


def test_a_bad_pin_transition_is_refused() raises:
    """An empty pointer or a missing key is refused."""
    with assert_raises(contains="pin transition pointer is empty"):
        _ = apply_pin_transitions(_pins() + '{"pointer":[],"before":"z"}]}')
    with assert_raises(contains="KeyError"):
        _ = apply_pin_transitions(
            _pins() + '{"pointer":["groups","missing","a"],"before":"z"}]}'
        )


def main() raises:
    """Run the pin-transition tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
