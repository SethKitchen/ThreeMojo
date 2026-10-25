# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The grouped Y premises keep their token digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_true

from tests._geometry_predecessor import restored_geometry
from tests._python_tokens import token_sha256


comptime _GROUPED = "extensions/carla/spiral_grouped_roundoff_proof.mojo"
"""The grouped producer."""
comptime _INTERVAL = "extensions/carla/curve_interval.mojo"
"""The interval module."""
comptime _TRIG = "extensions/carla/curve_trig.mojo"
"""The trig module."""
comptime _GEOMETRY = "extensions/carla/geometry.mojo"
"""The live geometry file."""
comptime _SUM2 = "extensions/carla/curve_sum2.mojo"
"""The Sum2 module."""
comptime _GROUPED_TOKEN = (
    "cd92ac2f02c75fc420920fe3a73b4ddd28a4e5cf0d97785b4ae4eb0f54f2cbd7"
)
"""The token digest of the grouped producer."""
comptime _INTERVAL_TOKEN = (
    "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"
)
"""The token digest of the interval module."""
comptime _TRIG_TOKEN = (
    "523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f"
)
"""The token digest of the trig module."""
comptime _GEOMETRY_TOKEN = (
    "a1979bd37d0ea725f452e0a0a269c7aaef3cda485b291e8fe79b49b35850adcb"
)
"""The token digest of the restored geometry module."""
comptime _SUM2_TOKEN = (
    "3fbcbb7f6ba0b9120500698665f0419acf6618d8bd34b7e18b9d10896282383d"
)
"""The token digest of the Sum2 module."""
comptime _LIVE_SHA256 = (
    "374fd1621142ec8354a29b24357503db7f45ce419cb39089b913b5c39b4e983e"
)
"""The file digest of the live geometry module."""
comptime _RESTORED_SHA256 = (
    "eb55cc639bb840e2cef06cdb6ad5b76a5b2af880c74813590585ec180092a45c"
)
"""The file digest after the reviewed line edits are removed."""


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
        raise Error("missing grouped premise")
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
        raise Error("missing grouped premise")
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


def _admit(
    grouped: String,
    interval: String,
    trig: String,
    geometry: String,
    sum2: String,
) raises:
    """Require the five Y-premise token digests.

    Args:
        grouped: The grouped producer.
        interval: The interval module.
        trig: The trig module.
        geometry: The restored geometry module.
        sum2: The Sum2 module.

    Raises:
        Error: A premise, the graph, a write, or the order changed.
    """
    if token_sha256(grouped) != _GROUPED_TOKEN:
        raise Error(
            "Y-finiteness premise, graph, writes or ordering changed: "
            + _GROUPED
        )
    if token_sha256(interval) != _INTERVAL_TOKEN:
        raise Error(
            "Y-finiteness premise, graph, writes or ordering changed: "
            + _INTERVAL
        )
    if token_sha256(trig) != _TRIG_TOKEN:
        raise Error(
            "Y-finiteness premise, graph, writes or ordering changed: " + _TRIG
        )
    if token_sha256(geometry) != _GEOMETRY_TOKEN:
        raise Error(
            "Y-finiteness premise, graph, writes or ordering changed: "
            + _GEOMETRY
        )
    if token_sha256(sum2) != _SUM2_TOKEN:
        raise Error(
            "Y-finiteness premise, graph, writes or ordering changed: " + _SUM2
        )


def _spaced(text: String) raises -> String:
    """Append a comment and widen one assignment when it is present.

    Args:
        text: The source.

    Returns:
        The commented source.
    """
    var commented = text + "\n# comment\n"
    if commented.find("copies =") >= 0:
        return _replace_all(commented, "copies =", "copies  =")
    return commented


def _refuse(
    grouped: String,
    interval: String,
    trig: String,
    geometry: String,
    sum2: String,
    path: String,
) raises:
    """Require admission to fail for `path`.

    Args:
        grouped: The grouped producer.
        interval: The interval module.
        trig: The trig module.
        geometry: The geometry module.
        sum2: The Sum2 module.
        path: The module whose digest must change.

    Raises:
        Error: Admission succeeds or the refusal text differs.
    """
    var failed = False
    try:
        _admit(grouped, interval, trig, geometry, sum2)
    except error:
        failed = True
        assert_true(
            String(error).find(
                "Y-finiteness premise, graph, writes or ordering changed: "
                + path
            )
            >= 0
        )
    assert_true(failed)


def test_the_grouped_premises_stay_bound() raises:
    """The five live or restored modules satisfy the Y premises."""
    var grouped = Path(_GROUPED).read_text()
    var interval = Path(_INTERVAL).read_text()
    var trig = Path(_TRIG).read_text()
    var geometry = restored_geometry()
    var sum2 = Path(_SUM2).read_text()
    _admit(grouped, interval, trig, geometry, sum2)
    _admit(
        _spaced(grouped),
        _spaced(interval),
        _spaced(trig),
        _spaced(geometry),
        _spaced(sum2),
    )


def test_phase_table_and_interval_edits_are_refused() raises:
    """A phase, table, or interval edit changes its premise digest."""
    var grouped = Path(_GROUPED).read_text()
    var interval = Path(_INTERVAL).read_text()
    var trig = Path(_TRIG).read_text()
    var geometry = restored_geometry()
    var sum2 = Path(_SUM2).read_text()
    var trig_cases = List[String]()
    trig_cases.append("Float64(0.6366197723675814)")
    trig_cases.append("Float64(0.4)")
    trig_cases.append("Float64(1048576.0)")
    trig_cases.append("Float64(1e100)")
    trig_cases.append("_SIN_COEFFICIENTS: Array[Float64, 11]")
    trig_cases.append("_SIN_COEFFICIENTS: Array[Float64, 12]")
    trig_cases.append("-0.16666666666666666")
    trig_cases.append("-2.0")
    var index = 0
    while index < len(trig_cases):
        var changed = _replace_first(
            trig, trig_cases[index], trig_cases[index + 1]
        )
        _refuse(grouped, interval, changed, geometry, sum2, _TRIG)
        index += 2
    var geometry_cases = List[String]()
    geometry_cases.append("-0.9061798459386640")
    geometry_cases.append("-1.0")
    geometry_cases.append("0.2369268850561891")
    geometry_cases.append("2.0")
    index = 0
    while index < len(geometry_cases):
        var changed = _replace_first(
            geometry, geometry_cases[index], geometry_cases[index + 1]
        )
        _refuse(grouped, interval, trig, changed, sum2, _GEOMETRY)
        index += 2
    var interval_cases = List[String]()
    interval_cases.append(
        "return self.value + _Interval(-self.error, self.error)"
    )
    interval_cases.append("return self.value")
    interval_cases.append("if other.rounded_value().is_finite():")
    interval_cases.append("if True:")
    interval_cases.append("error = other.error")
    interval_cases.append("error = 0.0")
    interval_cases.append("var inherited = _next_up(self.error + other.error)")
    interval_cases.append("var inherited = 0.0")
    interval_cases.append("var residual = fma(one, two, -value)")
    interval_cases.append("var residual = 0.0")
    interval_cases.append("var residual = fma(-value, two, one)")
    interval_cases.append("var residual = 0.0")
    index = 0
    while index < len(interval_cases):
        var changed = _replace_first(
            interval, interval_cases[index], interval_cases[index + 1]
        )
        _refuse(grouped, changed, trig, geometry, sum2, _INTERVAL)
        index += 2


def main() raises:
    """Run the grouped Y premise tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
