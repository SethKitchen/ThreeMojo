# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the ideal half projection in one call.

The caller supplies the legacy spiral, the live spiral, and the
stored-half helper. This check returns the reviewed projection record.
"""

from tests._python_expr import ideal_current_matches, ideal_legacy_dump
from tests._python_tokens import (
    check_stored_half,
    selected_block,
    stored_half_tail,
)
from tools._json_tools import quote_ascii
from tools._moment_pin_shape import (
    require_legacy_digest,
    require_projection_result,
)
from tools._projection_result import projection_result, require_source_text
from tools._python_json import MISSING, PyJson, dumps_canonical
from tools.carla_ideal_gate import ideal_digest, ideal_digests


def _require_text(text: String, message: String) raises:
    """Require one projection input to be text.

    Args:
        text: The source text.
        message: The failure text when the value is not text.

    Raises:
        Error: The value is not text.
    """
    var doc = PyJson()
    var body = doc.new_dict()
    doc.set(body, "text", doc.new_str(text))
    doc.set(body, "message", doc.new_str(message))
    doc.root = body
    require_source_text(doc.dumps())


def _projection_pins(doc: PyJson, pins: Int, result_text: String) raises:
    """Require the pinned projection fields to match the result.

    Args:
        doc: The payload document.
        pins: The ideal-projection object.
        result_text: The reviewed projection record.

    Raises:
        Error: A result pin differs, or a result field is absent.
    """
    var result = PyJson.parse(result_text)
    var subset = String("{")
    var count = result.length(result.root)
    var index = 0
    while index < count:
        var key = result.key(result.root, index)
        if index > 0:
            subset += ","
        subset += quote_ascii(key)
        subset += ":"
        subset += dumps_canonical(doc, doc.at(pins, key))
        index += 1
    subset += "}"
    require_projection_result(
        '{"projection":' + subset + ',"result":' + result_text + "}"
    )


def moment_projection(payload: String) raises -> String:
    """Check one ideal half projection.

    Args:
        payload: A JSON object with `legacy` and `current`. `helper` is
            the stored-half source. `interval` selects that source from
            the interval module instead. `pins` compares the result.

    Returns:
        The reviewed projection record.

    Raises:
        Error: The stored-half tail, the legacy source, the helper, the
            live spiral, the projected graph, or a result pin changed.
    """
    var doc = PyJson.parse(payload)
    var legacy = doc.text(doc.at(doc.root, "legacy"))
    var current = doc.text(doc.at(doc.root, "current"))
    var interval = doc.get(doc.root, "interval")
    var helper: String
    if interval == MISSING:
        helper = doc.text(doc.at(doc.root, "helper"))
    else:
        helper = stored_half_tail(doc.text(interval))
    ideal_digest(legacy.as_bytes(), "legacy")
    _require_text(helper, "ideal helper declaration or decorator changed")
    check_stored_half(helper)
    var left_dump = ideal_legacy_dump(legacy)
    _require_text(current, "changed ideal generic declaration")
    ideal_current_matches(current, left_dump)
    ideal_digest(left_dump.as_bytes(), "projected")
    var digests = PyJson.parse(ideal_digests())
    var record = projection_result(
        digests.text(digests.at(digests.root, "projected"))
    )
    var pins = doc.get(doc.root, "pins")
    if pins != MISSING:
        _projection_pins(doc, pins, record)
    return record


def moment_legacy_projection(payload: String) raises -> String:
    """Check the legacy pin digest, then the ideal half projection.

    Args:
        payload: JSON with `legacy`, `current`, `interval`, `pins`, and
            `legacy_sha256`. `legacy_sha256` is the pinned digest.

    Returns:
        The reviewed projection record.

    Raises:
        Error: The pin digest disagrees, or the projection changed. The
            digest is checked before the interval tail.
    """
    var doc = PyJson.parse(payload)
    var expected = PyJson.parse(ideal_digests())
    var gate = PyJson()
    var body = gate.new_dict()
    gate.set(
        body,
        "actual",
        gate.new_str(doc.text(doc.at(doc.root, "legacy_sha256"))),
    )
    gate.set(
        body,
        "expected",
        gate.new_str(expected.text(expected.at(expected.root, "legacy"))),
    )
    gate.root = body
    require_legacy_digest(gate.dumps())
    return moment_projection(payload)


def moment_sum2_projection(payload: String) raises -> String:
    """Project the Sum2 ideal spiral from its module and interval.

    Args:
        payload: A JSON object with `legacy`, `bounds`, `begin`, `end`,
            and `interval`. `bounds` is the live bounds module. `begin`
            and `end` select the spiral. `interval` is the interval module.

    Returns:
        The reviewed projection record.

    Raises:
        Error: A marker, the stored-half helper, or the projection changed.
    """
    var doc = PyJson.parse(payload)
    var current = selected_block(
        doc.text(doc.at(doc.root, "bounds")),
        doc.text(doc.at(doc.root, "begin")),
        doc.text(doc.at(doc.root, "end")),
    )
    var helper = stored_half_tail(doc.text(doc.at(doc.root, "interval")))
    var inner = PyJson()
    var body = inner.new_dict()
    inner.set(
        body, "legacy", inner.new_str(doc.text(doc.at(doc.root, "legacy")))
    )
    inner.set(body, "current", inner.new_str(current))
    inner.set(body, "helper", inner.new_str(helper))
    inner.root = body
    return moment_projection(inner.dumps())


def checked_helper_projection(payload: String) raises:
    """Require the helper text, then check the stored-half helper.

    Args:
        payload: JSON with `text` and `message`. `text` is the helper
            source when it is a string.

    Raises:
        Error: `text` is not a string, or the helper changed. The text
            check uses `message` and runs before the helper check.
    """
    require_source_text(payload)
    var doc = PyJson.parse(payload)
    check_stored_half(doc.text(doc.at(doc.root, "text")))
