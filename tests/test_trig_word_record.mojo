# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The trig dependency keeps its token digest and its stored words."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import stored_word_sha256, token_sha256


comptime _PATH = "extensions/carla/curve_trig.mojo"
"""The trig module whose stored words are bound."""
comptime _TOKEN = (
    "523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f"
)
"""The token digest of that module."""
comptime _WORD = (
    "f2337e89e88234a7a275e1be6398d672abd05210e5b37098e2e3bd39212c3807"
)
"""The stored-word digest of that module."""


def _replace_first(
    text: String, before: String, after: String
) raises -> String:
    """Replace the first occurrence of `before`.

    Args:
        text: The source.
        before: The original fragment.
        after: The replacement.

    Returns:
        The changed source.

    Raises:
        Error: `before` is missing.
    """
    var at = text.find(before)
    if at < 0:
        raise Error("missing trig fragment")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _words(source: String) raises -> String:
    """Return the stored-word digest of the trig module.

    Args:
        source: The trig source.

    Returns:
        The hex digest.

    Raises:
        Error: A stored declaration cannot be read.
    """
    var arrays = List[String]()
    arrays.append("_COS_COEFFICIENTS")
    arrays.append("_SIN_COEFFICIENTS")
    var sizes = List[Int]()
    sizes.append(11)
    sizes.append(11)
    var scalars = List[String]()
    scalars.append("_PHASE_LIMIT")
    scalars.append("_INV_HALF_PI")
    scalars.append("_HALF_PI_HIGH")
    scalars.append("_HALF_PI_LOW")
    return stored_word_sha256(source, arrays, sizes, scalars)


def _admit(path: String, source: String, expected: String) raises:
    """Admit an exact token digest or the same stored words.

    Args:
        path: The module path being checked.
        source: The module source.
        expected: The recorded token digest.

    Raises:
        Error: The path, the token digest, or the stored words changed.
    """
    if path == _PATH and expected == _TOKEN:
        if token_sha256(source) == expected:
            return
        if _words(source) == _WORD:
            return
    raise Error(
        "reviewed cleanup source contract: unchanged premise dependency"
        " changed: "
        + path
    )


def _refuse(path: String, source: String, expected: String) raises:
    """Require admission of `source` to fail.

    Args:
        path: The module path being checked.
        source: The module source.
        expected: The recorded token digest.

    Raises:
        Error: Admission succeeds.
    """
    var failed = False
    try:
        _admit(path, source, expected)
    except error:
        failed = True
        _ = String(error)
    assert_true(failed)


def test_the_trig_fingerprint_and_equivalent_words_stay_bound() raises:
    """The live module keeps its digests, and equal words stay admitted."""
    var source = Path(_PATH).read_text()
    assert_equal(token_sha256(source), _TOKEN)
    assert_equal(_words(source), _WORD)
    _admit(_PATH, source + "\n# comment\n", _TOKEN)
    var widened = _replace_first(source, "    -0.5,", "    -0.5000000000000,")
    var integer = _replace_first(
        source, "Float64(1048576.0)", "Float64(1048576)"
    )
    assert_equal(_words(widened), _WORD)
    assert_equal(_words(integer), _WORD)
    _admit(_PATH, widened, _TOKEN)
    _admit(_PATH, integer, _TOKEN)


def test_changed_trig_words_and_other_paths_are_refused() raises:
    """A different word, graph, declaration, path, or pin is refused."""
    var source = Path(_PATH).read_text()
    var cases = List[String]()
    cases.append("    -0.5,")
    cases.append("    -0.5000000000000001,")
    cases.append("Float64(1048576.0)")
    cases.append("Float64(1048577.0)")
    cases.append("Float64(1048576.0)")
    cases.append("Float64(1048576.0) + 1.0")
    cases.append("Float64(1048576.0)")
    cases.append("Float64(1048576.0 if True else 2.0)")
    cases.append("comptime _PHASE_LIMIT =")
    cases.append("comptime _UNBOUND_LIMIT =")
    cases.append("from std.memory import bitcast")
    cases.append("from other.memory import bitcast")
    cases.append("def _curve_sincos(")
    cases.append("def _changed_sincos(")
    cases.append("    -0.5,")
    cases.append("    -0.5 + 0.0,")
    cases.append("    -0.5,")
    cases.append("    -0.5, -0.5,")
    cases.append("    -0.5,")
    cases.append("    0.5,")
    var index = 0
    while index < len(cases):
        var changed = _replace_first(source, cases[index], cases[index + 1])
        _refuse(_PATH, changed, _TOKEN)
        index += 2
    _refuse(
        _PATH,
        source + "\ncomptime _PHASE_LIMIT = Float64(1048576.0)\n",
        _TOKEN,
    )
    var hidden = _replace_first(
        source,
        "comptime _PHASE_LIMIT = Float64(1048576.0)",
        "if True:\n    comptime _PHASE_LIMIT = Float64(1048576.0)",
    )
    _refuse(_PATH, hidden, _TOKEN)
    var equivalent = _replace_first(
        source, "    -0.5,", "    -0.5000000000000,"
    )
    _refuse("extensions/carla/road_info.mojo", equivalent, _TOKEN)
    _refuse(
        _PATH,
        equivalent,
        "0000000000000000000000000000000000000000000000000000000000000000",
    )


def main() raises:
    """Run the trig stored-word tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
