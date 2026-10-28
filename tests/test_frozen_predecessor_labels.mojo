# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The frozen pin labels are read before the runtime predecessor."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._cleanup_declarations import cleanup_declarations
from tools._sha256 import sha256_hex
from tools.carla_frozen_arc_gate import (
    frozen_predecessor_then_declarations,
    frozen_predecessor_with_labels,
    frozen_runtime_predecessor,
)


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


def _request(before: String) -> String:
    """Return a predecessor request that omits the groups key.

    Args:
        before: The required predecessor digest.

    Returns:
        The request JSON.
    """
    return (
        '{"after":"'
        + sha256_hex(_pin().as_bytes())
        + '","before":"'
        + before
        + '","transitions":['
        + _change("eligibility", "new")
        + ","
        + _change("optional_runtime", "new")
        + ","
        + _change("translation", "new")
        + "]}"
    )


def test_the_pin_labels_select_the_runtime_predecessor() raises:
    """A request without `groups` still restores the historical pin."""
    var restored = _restored()
    var request = _request(sha256_hex(restored.as_bytes()))
    var labeled = frozen_predecessor_with_labels(_pin().as_bytes(), request)
    var explicit = frozen_runtime_predecessor(
        _pin().as_bytes(),
        '{"after":"'
        + sha256_hex(_pin().as_bytes())
        + '","before":"'
        + sha256_hex(restored.as_bytes())
        + '","groups":"groups","transitions":['
        + _change("eligibility", "new")
        + ","
        + _change("optional_runtime", "new")
        + ","
        + _change("translation", "new")
        + "]}",
    )
    assert_equal(labeled, restored)
    assert_equal(labeled, explicit)


def test_a_missing_digest_fails_after_the_pin_labels() raises:
    """The labels are read before a missing digest field fails."""
    with assert_raises(contains="KeyError: 'after'"):
        _ = frozen_predecessor_with_labels(_pin().as_bytes(), "{}")


def test_a_changed_digest_fails_before_a_placement() raises:
    """A wrong active digest fails before the placements are read."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: unreviewed runtime pin successor"
        )
    ):
        _ = frozen_predecessor_with_labels(
            "{".as_bytes(),
            '{"after":"00","before":"00","transitions":[]}',
        )


def test_a_missing_placement_fails_after_the_pin_labels() raises:
    """The groups name comes from the labels before the placement check."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: wrong runtime successor placements"
        )
    ):
        _ = frozen_predecessor_with_labels(
            _pin().as_bytes(),
            '{"after":"'
            + sha256_hex(_pin().as_bytes())
            + '","before":"00","transitions":[]}',
        )


def test_a_matching_predecessor_returns_the_declaration_catalog() raises:
    """The catalog follows a predecessor whose digest matches."""
    var restored = _restored()
    var guard = "pin"
    assert_equal(
        frozen_predecessor_then_declarations(
            _pin().as_bytes(),
            _request(sha256_hex(restored.as_bytes())),
            guard.as_bytes(),
            sha256_hex(guard.as_bytes()),
        ),
        cleanup_declarations(),
    )


def test_a_changed_predecessor_fails_before_the_catalog() raises:
    """A wrong active digest fails before the declaration catalog is read."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: unreviewed runtime pin successor"
        )
    ):
        _ = frozen_predecessor_then_declarations(
            "{".as_bytes(),
            '{"after":"00","before":"00","transitions":[]}',
            "nope".as_bytes(),
            "00",
        )


def test_a_changed_guard_fails_after_the_predecessor() raises:
    """A matching predecessor still refuses a changed guard digest."""
    var restored = _restored()
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unreviewed dependency pin"
            " successor"
        )
    ):
        _ = frozen_predecessor_then_declarations(
            _pin().as_bytes(),
            _request(sha256_hex(restored.as_bytes())),
            "nope".as_bytes(),
            "00",
        )


def test_a_missing_placement_fails_before_the_catalog() raises:
    """A placement failure is returned before the guard digest is checked."""
    with assert_raises(
        contains=(
            "frozen ARC producer contract: wrong runtime successor placements"
        )
    ):
        _ = frozen_predecessor_then_declarations(
            _pin().as_bytes(),
            '{"after":"'
            + sha256_hex(_pin().as_bytes())
            + '","before":"00","transitions":[]}',
            "nope".as_bytes(),
            "00",
        )


def main() raises:
    """Run the pin-label and declaration-catalog tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
