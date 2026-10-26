# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed cubic operation graphs.

Four modules keep their reviewed operation spans. Each span appears
once. A missing span or a repeated span is refused.
"""

from std.pathlib import Path


comptime _POLYNOMIAL = "extensions/carla/polynomial.mojo"
comptime _LANE = "extensions/carla/lane_value_bounds.mojo"
comptime _JUNCTION = "extensions/carla/junction_bounds.mojo"
comptime _ARC = "extensions/carla/curve_rounded_arc.mojo"
comptime _S_0_0 = (
    "        self.a = a\n        self.b = b\n        self.c = c\n        self.d"
    " = d\n        self.s = s\n"
)
comptime _S_0_1 = (
    "        var local = x - self.s\n        return self.a + local * (self.b +"
    " local * (self.c + local * self.d))\n"
)
comptime _S_0_2 = (
    "        var local = x - self.s\n        return self.b + local * (2 *"
    " self.c + local * 3 * self.d)\n"
)
comptime _S_2_0 = (
    "    var local = s - _ValueJet.constant(polynomial.s)\n    return (\n      "
    "  _ValueJet.constant(polynomial.a) - _ValueJet.constant(shift)\n    ) +"
    " local * (\n        _ValueJet.constant(polynomial.b)\n        + local\n   "
    "     * (\n            _ValueJet.constant(polynomial.c)\n            +"
    " local * _ValueJet.constant(polynomial.d)\n        )\n    )\n"
)
comptime _S_3_0 = (
    "    var bound = _polynomial_jet(p, _Jet.variable(a, b))\n    return (\n   "
    "     bound.rounded_value().magnitude(),\n       "
    " bound.first.magnitude(),\n        bound.second.magnitude(),\n       "
    " bound.error,\n    )\n"
)
comptime _S_3_1 = (
    "    var center = _Interval.point(_midpoint(low, high))\n    var m = center"
    " - _Interval.point(p.s)\n"
)
comptime _S_3_2 = (
    "    var delta = _Interval(low, high) - center\n    var ideal = value +"
    " delta * (first + delta * (second + delta * d))\n    var stored = ideal +"
    " _Interval(-scalar_error, scalar_error)\n"
)
comptime _S_5_0 = (
    "def _rounded_constant(polynomial: CubicPolynomial) -> _RoundedBox:\n    if"
    " (\n        not _rounded_operand(polynomial.s)\n        or polynomial.b !="
    " 0.0\n        or polynomial.c != 0.0\n        or polynomial.d != 0.0\n   "
    " ):\n        return _RoundedBox.unknown()\n"
)
comptime _PREFIX = "conditioned cubic semantic successor: "


def _fail(message: String) raises:
    """Raise a cubic graph error.

    Args:
        message: The failure text.

    Raises:
        Error: A graph check failed.
    """
    raise Error(_PREFIX + message)


def _root(root: String) -> String:
    """Return `root` without a trailing slash.

    Args:
        root: The repository root.

    Returns:
        The root used to join paths.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def _count(text: String, span: String) -> Int:
    """Count non-overlapping copies of `span`.

    Args:
        text: The source.
        span: The exact text.

    Returns:
        The number of copies.
    """
    var count = 0
    var rest = text
    var step = span.byte_length()
    while True:
        var found = rest.find(span)
        if found < 0:
            return count
        count += 1
        var next = found + step
        var tail = String(rest[byte=next:])
        rest = tail^


def _once(text: String, span: String, path: String, index: Int) raises:
    """Require `span` to appear once.

    Args:
        text: The module source.
        span: The reviewed operation.
        path: The module path.
        index: The span index.

    Raises:
        Error: The span is missing or repeated.
    """
    if _count(text, span) != 1:
        _fail(
            "missing or ambiguous current operation: "
            + path
            + ":"
            + String(index)
        )


def cubic_graph_obligations(root: String) raises:
    """Require the reviewed cubic operation spans that still match.

    Args:
        root: The repository root.

    Raises:
        Error: A reviewed operation span is missing or repeated.
    """
    var base = _root(root)
    var polynomial = Path(base + "/" + _POLYNOMIAL).read_text()
    _once(polynomial, _S_0_0, _POLYNOMIAL, 0)
    _once(polynomial, _S_0_1, _POLYNOMIAL, 1)
    _once(polynomial, _S_0_2, _POLYNOMIAL, 2)
    var lane = Path(base + "/" + _LANE).read_text()
    _once(lane, _S_2_0, _LANE, 0)
    var junction = Path(base + "/" + _JUNCTION).read_text()
    _once(junction, _S_3_0, _JUNCTION, 0)
    _once(junction, _S_3_1, _JUNCTION, 1)
    _once(junction, _S_3_2, _JUNCTION, 2)
    var arc = Path(base + "/" + _ARC).read_text()
    _once(arc, _S_5_0, _ARC, 0)


def main() raises:
    """Check the cubic operation graphs of this repository.

    Raises:
        Error: A reviewed operation span changed.
    """
    cubic_graph_obligations(".")
