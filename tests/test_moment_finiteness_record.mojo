# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The moment producer keeps a finite stored-coefficient proof."""

from std.pathlib import Path
from std.testing import TestSuite, assert_true

from tests._python_tokens import stored_float_array, token_sha256


comptime _MODULE = "extensions/carla/spiral_moment_proof.mojo"
"""The dynamic moment producer."""
comptime _INTERVAL = "extensions/carla/curve_interval.mojo"
"""The directed interval arithmetic the producer uses."""
comptime _GEOMETRY = "extensions/carla/geometry.mojo"
"""The stored Gauss-Legendre table."""
comptime _TRIG = "extensions/carla/curve_trig.mojo"
"""The stored sine and cosine coefficients."""
comptime _MOMENT = (
    "9001f34d01c28de8dcf85af0bec9d9b9409ef8d56e083bfc25d6342c375f80d1"
)
"""The token digest of the moment producer."""
comptime _INTERVAL_TOKEN = (
    "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"
)
"""The token digest of the interval module."""


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
        raise Error("missing moment fragment")
    var out = String()
    var rest = text
    while True:
        var at = rest.find(before)
        if at < 0:
            out += rest
            break
        var head = String(rest[byte=:at])
        var tail = String(rest[byte = at + before.byte_length() :])
        out += head + after
        rest = tail
    return out


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
        raise Error("missing moment fragment")
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def _bounds(
    source: String,
    name: String,
    size: Int,
    low: Float64,
    high: Float64,
    strict: Bool,
    positive: Bool,
) raises:
    """Require one stored array to stay inside its proof bound.

    Args:
        source: The module that declares the array.
        name: The array name.
        size: The declared length.
        low: The lower bound.
        high: The upper bound.
        strict: True when the bounds are open.
        positive: True when zero is refused.

    Raises:
        Error: The array is missing or a value is outside the bound.
    """
    var values = stored_float_array(source, name, size)
    for value in values:
        var valid = value >= low and value <= high
        if positive:
            valid = valid and value > 0.0
        if strict:
            valid = valid and value > low and value < high
        if not valid:
            raise Error("Constant outside finite proof bound: " + name)


def _admit(
    module: String, interval: String, geometry: String, trig: String
) raises:
    """Require the moment graph and every stored coefficient.

    Args:
        module: The moment producer.
        interval: The interval module.
        geometry: The Gauss-Legendre table.
        trig: The sine and cosine coefficients.

    Raises:
        Error: A graph, the interval arithmetic, or a stored value changed.
    """
    if token_sha256(module) != _MOMENT:
        raise Error("Moment producer count/work/arithmetic graph changed")
    if token_sha256(interval) != _INTERVAL_TOKEN:
        raise Error("Directed interval arithmetic dependency changed")
    _bounds(geometry, "_GL_NODES", 5, -1.0, 1.0, True, False)
    _bounds(geometry, "_GL_WEIGHTS", 5, 0.0, 1.0, False, True)
    _bounds(trig, "_COS_COEFFICIENTS", 11, -1.0, 1.0, False, False)
    _bounds(trig, "_SIN_COEFFICIENTS", 11, -1.0, 1.0, False, False)


def _declaration(text: String, name: String, size: Int) raises -> String:
    """Return one stored-array declaration through its closing bracket.

    Args:
        text: The module source.
        name: The array name.
        size: The declared length.

    Returns:
        The declaration text.

    Raises:
        Error: The declaration is missing.
    """
    var start_mark = (
        "comptime " + name + ": Array[Float64, " + String(size) + "] = ["
    )
    var start = text.find(start_mark)
    if start < 0:
        raise Error("missing moment declaration")
    var end = text.find("]", start)
    if end < start:
        raise Error("missing moment declaration")
    return String(text[byte = start : end + 1])


def test_the_live_moment_graph_and_stored_tables_stay_bound() raises:
    """The live producer, interval, and stored tables satisfy the proof."""
    var module = Path(_MODULE).read_text()
    var interval = Path(_INTERVAL).read_text()
    var geometry = Path(_GEOMETRY).read_text()
    var trig = Path(_TRIG).read_text()
    _admit(module, interval, geometry, trig)
    var commented_module = module + "\n# Benign source commentary\n"
    commented_module = _replace_all(
        commented_module, "pieces > 64", "pieces  >  64"
    )
    _admit(
        commented_module,
        interval + "\n# Benign source commentary\n",
        geometry + "\n# Benign source commentary\n",
        trig + "\n# Benign source commentary\n",
    )
    var softened = _replace_all(trig, "-0.16666666666666666", "-0.125")
    _admit(module, interval, geometry, softened)


def test_count_work_and_interval_edits_are_refused() raises:
    """A count, work, or interval edit changes its recorded digest."""
    var module = Path(_MODULE).read_text()
    var interval = Path(_INTERVAL).read_text()
    var geometry = Path(_GEOMETRY).read_text()
    var trig = Path(_TRIG).read_text()
    var cases = List[String]()
    cases.append("pieces > 64")
    cases.append("pieces > 1024")
    cases.append("proof_terms += work")
    cases.append("proof_terms += 0")
    cases.append("range(1, 22)")
    cases.append("range(1, 222)")
    cases.append("materialize[_GL_WEIGHTS]()")
    cases.append("materialize[_GL_NODES]()")
    cases.append("var alpha2 =")
    cases.append("weights[0] = 1e300\n            var alpha2 =")
    var index = 0
    while index < len(cases):
        var changed = _replace_all(module, cases[index], cases[index + 1])
        var failed = False
        try:
            _admit(changed, interval, geometry, trig)
        except error:
            failed = True
            assert_true(
                String(error).find(
                    "Moment producer count/work/arithmetic graph changed"
                )
                >= 0
            )
        assert_true(failed)
        index += 2
    var widened = _replace_all(
        interval,
        "return Self(_next_down(low), _next_up(high))",
        "return Self(low, high)",
    )
    var interval_failed = False
    try:
        _admit(module, widened, geometry, trig)
    except error:
        interval_failed = True
        assert_true(
            String(error).find(
                "Directed interval arithmetic dependency changed"
            )
            >= 0
        )
    assert_true(interval_failed)


def test_stored_coefficient_edits_and_decoys_are_refused() raises:
    """A value outside the proof bound, or a hidden declaration, is refused."""
    var module = Path(_MODULE).read_text()
    var interval = Path(_INTERVAL).read_text()
    var geometry = Path(_GEOMETRY).read_text()
    var trig = Path(_TRIG).read_text()
    var heavy = _replace_all(geometry, "0.5688888888888889", "1e300")
    var nodes = _replace_first(
        geometry, "comptime _GL_NODES:", "var _GL_NODES:"
    )
    var sine = _replace_all(trig, "-0.16666666666666666", "-2.0")
    for changed_geometry in [heavy, nodes]:
        var failed = False
        try:
            _admit(module, interval, changed_geometry, trig)
        except error:
            failed = True
        assert_true(failed)
    var sine_failed = False
    try:
        _admit(module, interval, geometry, sine)
    except error:
        sine_failed = True
        assert_true(
            String(error).find(
                "Constant outside finite proof bound: _SIN_COEFFICIENTS"
            )
            >= 0
        )
    assert_true(sine_failed)
    var names = List[String]()
    names.append("_GL_NODES")
    names.append("_GL_WEIGHTS")
    names.append("_COS_COEFFICIENTS")
    names.append("_SIN_COEFFICIENTS")
    var sizes = List[Int]()
    sizes.append(5)
    sizes.append(5)
    sizes.append(11)
    sizes.append(11)
    var sources = List[String]()
    sources.append(geometry)
    sources.append(geometry)
    sources.append(trig)
    sources.append(trig)
    for index in range(len(names)):
        var declaration = _declaration(
            sources[index], names[index], sizes[index]
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
        var decoys = List[String]()
        decoys.append('"""' + declaration + '"""')
        decoys.append("if True:\n" + indented)
        decoys.append(declaration + " + [0.0]")
        for decoy in decoys:
            var text = _replace_first(sources[index], declaration, decoy)
            var failed = False
            try:
                if index < 2:
                    _admit(module, interval, text, trig)
                else:
                    _admit(module, interval, geometry, text)
            except error:
                failed = True
            assert_true(failed)


def main() raises:
    """Run the moment finiteness record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
