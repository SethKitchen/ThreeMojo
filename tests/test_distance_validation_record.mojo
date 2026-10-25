# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The distance proof keeps ordered values, errors, and the original debit."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _MODULE = "extensions/carla/spiral_domain_proof.mojo"
"""The live domain producer."""
comptime _INTERVAL = "extensions/carla/curve_interval.mojo"
"""The ordered widening the producer uses."""
comptime _RECORD = "tools/carla_lane_oracle/distance-validation-contract.json"
"""The reviewed distance validation record."""
comptime _RECORD_SHA256 = (
    "74409c5bb90df7e52e7e91c0bb00ed8466e3c0bf4f458507c84f0f72923548bb"
)
"""The SHA-256 of that record."""
comptime _LIVE_SHA256 = (
    "a641d554b2c2a3fe5d64bbfed9c4d5b10ac71858e13cd3c35c9619a7766720e9"
)
"""The file digest of the live domain producer."""
comptime _MODULE_SHA256 = (
    "89a8760eee14ff17c682ac69657eb62391e5dfd7e6e1e11fa8a931f8595e9252"
)
"""The file digest after the import is restored."""
comptime _MODULE_TOKEN = (
    "7263f3e46da6496d3b3a6054870b4238d9f4767c07e90161065c5c87e6d18813"
)
"""The token digest of the admitted domain producer."""
comptime _INTERVAL_TOKEN = (
    "e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11"
)
"""The token digest of the interval module."""
comptime _LIVE_IMPORT = (
    "from extensions.carla.road_info import _info_index_si as info_index\n"
)
"""The live import the admitted module does not use."""
comptime _ADMITTED_IMPORT = (
    "from extensions.carla.road_info import info_index\n"
)
"""The import the admitted module uses."""


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
        raise Error("missing distance fragment")
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


def _field(doc: PyJson, name: String) raises -> String:
    """Return one string field of the record.

    Args:
        doc: The record.
        name: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent.
    """
    return doc.text(doc.at(doc.root, name))


def _module() raises -> String:
    """Return the admitted domain producer.

    Returns:
        The live module with its earlier import restored.

    Raises:
        Error: The live file or the restored module changed.
    """
    var live = Path(_MODULE).read_text()
    if sha256_hex(live.as_bytes()) != _LIVE_SHA256:
        raise Error(
            "Distance validation, derivative/association checks or"
            " debit/routing changed"
        )
    var restored = _replace_all(live, _LIVE_IMPORT, _ADMITTED_IMPORT)
    if sha256_hex(restored.as_bytes()) != _MODULE_SHA256:
        raise Error(
            "Distance validation, derivative/association checks or"
            " debit/routing changed"
        )
    return restored


def _admit(module: String, interval: String) raises:
    """Require the domain graph and the widening operation.

    Args:
        module: The admitted domain producer.
        interval: The interval module.

    Raises:
        Error: The domain graph or the widening operation changed.
    """
    if token_sha256(module) != _MODULE_TOKEN:
        raise Error(
            "Distance validation, derivative/association checks or"
            " debit/routing changed"
        )
    if token_sha256(interval) != _INTERVAL_TOKEN:
        raise Error("Ordered nonnegative-error widening operation changed")


def _refuse_module(module: String, interval: String, message: String) raises:
    """Require `module` to fail admission with `message`.

    Args:
        module: The edited producer.
        interval: The interval module.
        message: The expected refusal.

    Raises:
        Error: Admission succeeds or the refusal text differs.
    """
    var failed = False
    try:
        _admit(module, interval)
    except error:
        failed = True
        assert_true(String(error).find(message) >= 0)
    assert_true(failed)


def test_the_restored_distance_module_stays_bound() raises:
    """The restored producer, the interval, and the record stay bound."""
    var module = _module()
    var interval = Path(_INTERVAL).read_text()
    _admit(module, interval)
    var commented = module + "\n# comment\n"
    commented = _replace_all(commented, "d.error < 0.0", "d.error  <  0.0")
    _admit(commented, interval + "\n# comment\n")
    var raw = Path(_RECORD).read_bytes()
    assert_equal(sha256_hex(raw), _RECORD_SHA256)
    var doc = PyJson.parse(Path(_RECORD).read_text())
    assert_equal(_field(doc, "path"), _MODULE)
    assert_equal(_field(doc, "after_sha256"), _MODULE_SHA256)
    assert_equal(_field(doc, "after_token_sha256"), _MODULE_TOKEN)
    assert_equal(_field(doc, "interval_token_sha256"), _INTERVAL_TOKEN)


def test_guard_debit_rounding_and_widening_edits_are_refused() raises:
    """A guard, debit, route, or widening edit changes its digest."""
    var module = _module()
    var interval = Path(_INTERVAL).read_text()
    var deletions = List[String]()
    deletions.append("or captured.d.value.low > captured.d.value.high")
    deletions.append("or d.value.low > d.value.high")
    deletions.append("or not isfinite(captured.d.error)")
    deletions.append("or captured.d.error < 0.0")
    deletions.append("or not isfinite(d.error)")
    deletions.append("or d.error < 0.0")
    deletions.append("or not captured.d.first.is_finite()")
    deletions.append("or not d.second.is_finite()")
    for token in deletions:
        var changed = _replace_all(module, token, "")
        _refuse_module(
            changed,
            interval,
            (
                "Distance validation, derivative/association checks or"
                " debit/routing changed"
            ),
        )
    var cases = List[String]()
    cases.append("construction_terms += extra")
    cases.append("construction_terms += 0")
    cases.append("proof_units += extra")
    cases.append("proof_units += 0")
    cases.append("record_at != proof.record_at")
    cases.append("False")
    cases.append("var domain = captured.d.rounded_value()")
    cases.append("var domain = captured.d.value")
    cases.append("var domain = d.rounded_value()")
    cases.append("var domain = d.value")
    var index = 0
    while index < len(cases):
        var changed = _replace_all(module, cases[index], cases[index + 1])
        _refuse_module(
            changed,
            interval,
            (
                "Distance validation, derivative/association checks or"
                " debit/routing changed"
            ),
        )
        index += 2
    var widened = _replace_all(
        interval,
        "return self.value + _Interval(-self.error, self.error)",
        "return self.value + _Interval(self.error, -self.error)",
    )
    _refuse_module(
        module,
        widened,
        "Ordered nonnegative-error widening operation changed",
    )


def main() raises:
    """Run the distance validation record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
