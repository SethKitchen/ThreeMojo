# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The projected ideal spiral matches Python's AST digest."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools.spiral_moment_ast import projected_ideal_digest, projected_ideal_text
from tools.spiral_moment_graph import selected_block


comptime _DIGEST = (
    "f0f94e038fd4a783b3ed400ffd32801ca0c3bdc54980e2c408d44f50211b9e06"
)
"""The projected ideal graph digest."""


def _legacy() raises -> String:
    """Return the pinned legacy ideal spiral.

    Returns:
        The normalized legacy source.

    Raises:
        Error: The pin file is unreadable.
    """
    var text = Path(
        "tools/carla_lane_oracle/spiral-moment-pins.json"
    ).read_text()
    var doc = PyJson.parse(text)
    var projection = doc.at(doc.root, "ideal_projection")
    return doc.text(doc.at(projection, "legacy_normalized_source"))


def _current() raises -> String:
    """Return the live ideal spiral block.

    Returns:
        The normalized block.

    Raises:
        Error: The block is refused.
    """
    var bounds = Path("extensions/carla/curve_bounds.mojo").read_text()
    return selected_block(
        bounds, "def _spiral_expression[", "def _sample_index("
    )


def _helper() raises -> String:
    """Return the live stored-half helper.

    Returns:
        The source from `def _stored_half[`.

    Raises:
        Error: The interval file is unreadable.
    """
    var text = Path("extensions/carla/curve_interval.mojo").read_text()
    var marker = "def _stored_half["
    var at = text.find(marker)
    return String(text[byte=at:])


def _refuse(current: String, message: String) raises:
    """Require `current` to fail with `message`.

    Args:
        current: The live ideal spiral under test.
        message: The expected failure text.

    Raises:
        Error: The inputs cannot be read, or the failure text differs.
    """
    with assert_raises(contains=message):
        _ = projected_ideal_text(_legacy(), current, _helper())


def test_the_projected_graph_matches_the_pin() raises:
    """The legacy and live spirals share the projected digest."""
    var legacy = _legacy()
    var current = _current()
    var helper = _helper()
    assert_equal(projected_ideal_digest(legacy, current, helper), _DIGEST)
    var commented = current.replace(
        "comptime Expression = _JetExpression[derivatives]\n",
        "comptime Expression = _JetExpression[derivatives]\n    # note\n",
    )
    assert_equal(projected_ideal_digest(legacy, commented, helper), _DIGEST)
    var comma = current.replace("translation: Vector3,", "translation: Vector3")
    assert_equal(projected_ideal_digest(legacy, comma, helper), _DIGEST)


def test_a_changed_projection_is_refused() raises:
    """A moved guard, term, call, or auxiliary is refused."""
    var current = _current()
    _refuse(
        current.replace(
            "if not _sum2_supported_environment():", "if not other():"
        ),
        "environment refusal changed",
    )
    _refuse(
        current.replace("    var piece = 0\n", ""),
        "environment refusal changed",
    )
    _refuse(
        current.replace("    while piece < pieces:", "    if piece < pieces:"),
        "ideal statement layout changed",
    )
    _refuse(
        current.replace(
            "    while piece < pieces:\n",
            "    while piece < pieces:\n        var extra = 0\n",
        ),
        "outer-loop layout changed",
    )
    _refuse(
        current.replace("        while i < 5:", "        if i < 5:"),
        "outer-loop layout changed",
    )
    _refuse(
        current.replace(
            "        while i < 5:\n",
            "        while i < 5:\n            var extra = 0\n",
        ),
        "node-loop layout changed",
    )
    _refuse(
        current.replace(
            "var x_magnitude = _Interval.point(0.0)",
            "var x_magnitude = _Interval.point(1.0)",
        ),
        "declarations reordered",
    )
    _refuse(
        current.replace("5 * pieces", "4 * pieces"), "error writes reordered"
    )
    _refuse(
        current.replace("term_x.error", "term_x.value"),
        "auxiliary updates reordered",
    )
    _refuse(current.replace("trig[1]", "trig[2]"), "term definition moved")
    _refuse(
        current.replace("x = x + term_x", "x = x + term_y"),
        "term accumulation moved",
    )
    _refuse(
        current.replace("1.0 + nodes[i]", "nodes[i]"),
        "ideal expression differs",
    )
    _refuse(
        current.replace(
            "var t = start + _stored_half(step)",
            "var t = start + _stored_half(rate)",
        ),
        "five reviewed stored-half calls",
    )
    _refuse(
        current.replace(
            "var t = start + _stored_half(step)", "var t = start + step"
        ),
        "five reviewed stored-half calls",
    )
    _refuse(
        current.replace(
            "var t = start + _stored_half(step)",
            "var t = start + _stored_half(step + d)",
        ),
        "unreviewed stored-half call shape",
    )
    _refuse(
        current.replace(
            "var t = start + _stored_half(step)",
            "var t = start + _stored_half()",
        ),
        "unreviewed stored-half call shape",
    )


def test_a_changed_legacy_or_helper_is_refused() raises:
    """A changed legacy digest or helper is refused."""
    var current = _current()
    var helper = _helper()
    with assert_raises(contains="historical ideal source changed"):
        _ = projected_ideal_text(
            "def changed():\n    return 0\n", current, helper
        )
    with assert_raises(contains="initial expression changed"):
        _ = projected_ideal_text(
            _legacy(),
            current,
            helper.replace("constant(0.5)", "constant(0.25)"),
        )


def test_malformed_ideal_source_is_refused() raises:
    """A declaration, token, or indent outside the subset is refused."""
    _refuse("return 0\n", "unsupported ideal function declaration")
    _refuse(
        "def other[derivatives: Bool]() -> None:\n    return 0\n",
        "unsupported ideal function declaration",
    )
    _refuse(
        "def _spiral_expression() -> None:\n    return 0\n",
        "unsupported ideal function declaration",
    )
    _refuse(
        "def _spiral_expression[derivatives: Int]() -> None:\n    return 0\n",
        "changed ideal generic declaration",
    )
    _refuse(
        (
            "def _spiral_expression[derivatives: List[Bool]]() -> None:\n   "
            " return 0\n"
        ),
        "changed ideal generic declaration",
    )
    _refuse(
        'def _spiral_expression["no"]() -> None:\n    return 0\n',
        "changed ideal generic declaration",
    )
    _refuse(
        _current() + "\ndef other():\n    return 0\n",
        "ambiguous ideal function",
    )
    _refuse(
        "def _spiral_expression[derivatives: Bool] -> None:\n    return 0\n",
        "unsupported ideal source syntax",
    )
    _refuse(
        (
            "def _spiral_expression[derivatives: Bool](1: Int) -> None:\n   "
            " return 0\n"
        ),
        "unsupported ideal source syntax",
    )
    _refuse(
        (
            "def _spiral_expression[derivatives: Bool]() -> None:\n    return"
            " 0\n  return 1\n"
        ),
        "unsupported ideal source syntax",
    )
    _refuse(
        (
            "def _spiral_expression[derivatives: Bool]() -> None:\n    var"
            ' label = "hi"\n'
        ),
        "unsupported ideal source syntax",
    )
    _refuse(
        (
            "def _spiral_expression[derivatives: Bool]() -> None:\n    label[0]"
            " = 1\n"
        ),
        "unsupported ideal source syntax",
    )
    _refuse(
        (
            "def _spiral_expression[derivatives: Bool]() -> None:\n    var"
            " label = 0x10\n"
        ),
        "unsupported ideal source syntax",
    )
    _refuse(
        "def _spiral_expression[derivatives: Bool]() -> None:\n    piece\n",
        "unsupported ideal source syntax",
    )


def main() raises:
    """Run the projected ideal graph tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
