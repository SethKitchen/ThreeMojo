# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The moment dependency record and the check messages stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._moment_check_plan import moment_check_plan
from tools._python_json import PyJson


def test_moment_check_plan_keeps_the_array_order() raises:
    """The four array names stay ahead of the check messages."""
    var doc = PyJson.parse(moment_check_plan())
    assert_equal(doc.text(doc.at(doc.root, "group")), "stored_arithmetic")
    assert_equal(
        doc.text(doc.at(doc.root, "pin_file")),
        "tools/carla_lane_oracle/runtime-source-pins.json",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "interval")),
        "extensions/carla/curve_interval.mojo",
    )
    var groups = doc.at(doc.root, "additional_groups")
    assert_equal(doc.length(groups), 1)
    assert_equal(doc.text(doc.item(groups, 0)), "canonical_accumulation")
    var arrays = doc.at(doc.root, "arrays")
    assert_equal(doc.length(arrays), 4)
    assert_equal(doc.text(doc.item(arrays, 0)), "_GL_NODES")
    assert_equal(doc.text(doc.item(arrays, 1)), "_GL_WEIGHTS")
    assert_equal(doc.text(doc.item(arrays, 2)), "_COS_COEFFICIENTS")
    assert_equal(doc.text(doc.item(arrays, 3)), "_SIN_COEFFICIENTS")
    assert_equal(doc.text(doc.at(doc.root, "nodes")), "_GL_NODES")
    assert_equal(doc.text(doc.at(doc.root, "weights")), "_GL_WEIGHTS")
    assert_equal(doc.text(doc.at(doc.root, "ideal_caller")), "ideal_caller")
    var messages = doc.at(doc.root, "messages")
    assert_equal(
        doc.text(doc.at(messages, "stored_words")),
        "stored constant words changed: ",
    )
    assert_equal(
        doc.text(doc.at(messages, "invalid_word")), "invalid UInt64 word"
    )
    assert_equal(
        doc.text(doc.at(messages, "array_set")), "wrong constant-array set"
    )
    assert_equal(doc.text(doc.at(messages, "overflow")), "binary64 overflow")
    assert_equal(
        doc.text(doc.at(messages, "scalar_word")),
        "stored scalar word changed: ",
    )
    assert_equal(
        doc.text(doc.at(messages, "routing_pin")), "inconsistent routing pin: "
    )
    assert_equal(
        doc.text(doc.at(messages, "routing")), "source routing changed: "
    )
    assert_equal(
        doc.text(doc.at(messages, "closure")),
        "stored-half dependency closure: ",
    )
    assert_equal(
        doc.text(doc.at(messages, "projection")), "ideal half projection: "
    )
    assert_equal(
        doc.text(doc.at(messages, "node_sums")),
        "rounded 1 + node words changed",
    )
    assert_equal(doc.text(doc.at(messages, "utf8")), "table is not UTF-8")
    var pin_groups = doc.at(doc.root, "pin_groups")
    assert_equal(doc.text(doc.item(pin_groups, 0)), "arrays")
    assert_equal(doc.text(doc.item(pin_groups, 1)), "scalars")
    assert_equal(doc.text(doc.item(pin_groups, 2)), "blocks")
    assert_equal(doc.text(doc.item(pin_groups, 3)), "routing")
    assert_equal(
        doc.text(doc.at(doc.root, "report_name")), "spiral-moment-report.json"
    )
    assert_equal(
        doc.text(doc.at(doc.root, "words_name")), "spiral_moment_words.be64"
    )
    assert_equal(
        doc.text(doc.at(doc.root, "coefficients_name")),
        "spiral_moment_exact_coefficients.json",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "output_env")), "CARLA_LANE_ORACLE_OUTPUT"
    )
    assert_equal(
        doc.text(doc.at(doc.root, "output_dir")), "out/carla-lane-oracle"
    )
    assert_equal(
        doc.text(doc.at(doc.root, "pass_line")),
        (
            "PASS: 64 counts, 1408 exact coefficients, 2816 tight endpoints,"
            " 22528 payload bytes"
        ),
    )
    assert_equal(
        doc.text(doc.at(doc.root, "sha_prefix")), "canonical source SHA-256: "
    )


def main() raises:
    """Run the moment check plan tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
