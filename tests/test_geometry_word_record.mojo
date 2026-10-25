# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The geometry dependency keeps its stored Gauss-Legendre words."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._geometry_predecessor import restored_geometry
from tests._python_tokens import stored_word_sha256, token_sha256


comptime _PATH = "extensions/carla/geometry.mojo"
"""The geometry module whose stored words are bound."""
comptime _TRIG = "extensions/carla/curve_trig.mojo"
"""The trig module whose stored words are bound."""
comptime _TOKEN = (
    "a1979bd37d0ea725f452e0a0a269c7aaef3cda485b291e8fe79b49b35850adcb"
)
"""The token digest of the restored geometry module."""
comptime _WORD = (
    "fb42552072a0166ca3ca94016b39ba98a6645e4091751e4b5b67e199139e96f0"
)
"""The stored-word digest of that module."""
comptime _TRIG_WORD = (
    "f2337e89e88234a7a275e1be6398d672abd05210e5b37098e2e3bd39212c3807"
)
"""The stored-word digest of the live trig module."""


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
        raise Error("missing geometry fragment")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _replace_all(text: String, before: String, after: String) raises -> String:
    """Replace every occurrence of `before`.

    Args:
        text: The source.
        before: The original fragment.
        after: The replacement.

    Returns:
        The changed source.

    Raises:
        Error: `before` is missing.
    """
    if text.find(before) < 0:
        raise Error("missing geometry fragment")
    var out = String()
    var rest = text
    while True:
        var at = rest.find(before)
        if at < 0:
            out += rest
            return out
        var head = String(rest[byte=:at])
        var tail = String(rest[byte = at + before.byte_length() :])
        out += head + after
        rest = tail


def _words(source: String) raises -> String:
    """Return the stored-word digest of a geometry module.

    Args:
        source: The geometry source.

    Returns:
        The hex digest.

    Raises:
        Error: A stored declaration cannot be read.
    """
    var arrays = List[String]()
    arrays.append("_GL_NODES")
    arrays.append("_GL_WEIGHTS")
    var sizes = List[Int]()
    sizes.append(5)
    sizes.append(5)
    var scalars = List[String]()
    return stored_word_sha256(source, arrays, sizes, scalars)


def _trig_words(source: String) raises -> String:
    """Return the stored-word digest of a trig module.

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
    """Admit an exact geometry token or the same stored words.

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


def _nodes(text: String) raises -> String:
    """Return the `_GL_NODES` declaration through its closing bracket.

    Args:
        text: The geometry source.

    Returns:
        The declaration text.

    Raises:
        Error: The declaration is missing.
    """
    var mark = "comptime _GL_NODES: Array[Float64, 5] = ["
    var start = text.find(mark)
    if start < 0:
        raise Error("missing geometry declaration")
    var end = text.find("]", start + mark.byte_length())
    if end < start:
        raise Error("missing geometry declaration")
    return String(text[byte = start : end + 1])


def test_the_geometry_words_and_equivalent_spellings_stay_bound() raises:
    """The restored table and the live trig words stay bound."""
    var geometry = restored_geometry()
    assert_equal(token_sha256(geometry), _TOKEN)
    assert_equal(_words(geometry), _WORD)
    assert_equal(_trig_words(Path(_TRIG).read_text()), _TRIG_WORD)
    var changed = _replace_all(
        geometry, "0.2369268850561891,", "0.23692688505618910000,"
    )
    changed = _replace_all(
        changed, "-0.9061798459386640,", "-0.90617984593866400,"
    )
    changed += "\n# harmless comment\n"
    assert_true(token_sha256(changed) != _TOKEN)
    assert_equal(_words(changed), _WORD)
    _admit(_PATH, changed, _TOKEN)
    _refuse("unlisted/geometry.mojo", changed, _TOKEN)
    _refuse(
        _PATH,
        changed,
        "0000000000000000000000000000000000000000000000000000000000000000",
    )


def test_changed_geometry_words_and_hidden_declarations_are_refused() raises:
    """A different word, type, hiding, or extra statement is refused."""
    var geometry = restored_geometry()
    var cases = List[String]()
    cases.append("0.2369268850561891,")
    cases.append("0.2469268850561891,")
    cases.append("comptime _GL_NODES:")
    cases.append("comptime _OTHER_NODES:")
    cases.append("Array[Float64, 5]")
    cases.append("Array[Float32, 5]")
    var index = 0
    while index < len(cases):
        var changed = _replace_first(geometry, cases[index], cases[index + 1])
        _refuse(_PATH, changed, _TOKEN)
        index += 2
    var declaration = _nodes(geometry)
    var start = geometry.find(declaration)
    var removed = String(geometry[byte=:start]) + String(
        geometry[byte = start + declaration.byte_length() :]
    )
    var indented = String()
    var rest = declaration
    while True:
        var at = rest.find("\n")
        if at < 0:
            indented += "    " + rest
            break
        var line = String(rest[byte = : at + 1])
        indented += "    " + line
        var tail = String(rest[byte = at + 1 :])
        rest = tail
    var moved = declaration + "\n" + removed
    var nested = removed + "\ndef _hidden_constants():\n" + indented + "\n"
    var suffix = (
        String(geometry[byte=:start])
        + declaration
        + " + [0.0]"
        + String(geometry[byte = start + declaration.byte_length() :])
    )
    var extras = List[String]()
    extras.append(moved)
    extras.append(nested)
    extras.append(suffix)
    extras.append(
        geometry + '\n"""comptime _GL_NODES: Array[Float64, 5] = [0.0]"""\n'
    )
    extras.append(
        geometry + "\ndef _unreviewed_control() -> Int:\n    return 1\n"
    )
    extras.append(geometry + "\nfrom unreviewed import Float64\n")
    for extra in extras:
        _refuse(_PATH, extra, _TOKEN)


def main() raises:
    """Run the geometry stored-word tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
