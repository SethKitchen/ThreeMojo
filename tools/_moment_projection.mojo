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
from tools._projection_result import projection_result, require_source_text
from tools._python_json import PyJson
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


def moment_projection(payload: String) raises -> String:
    """Check one ideal half projection.

    Args:
        payload: A JSON object with `legacy`, `current`, and `helper`.
            `legacy` is the pinned spiral. `current` is the live spiral.
            `helper` is the stored-half source.

    Returns:
        The reviewed projection record.

    Raises:
        Error: The legacy source, the helper, the live spiral, or the
            projected graph changed.
    """
    var doc = PyJson.parse(payload)
    var legacy = doc.text(doc.at(doc.root, "legacy"))
    var current = doc.text(doc.at(doc.root, "current"))
    var helper = doc.text(doc.at(doc.root, "helper"))
    ideal_digest(legacy.as_bytes(), "legacy")
    _require_text(helper, "ideal helper declaration or decorator changed")
    check_stored_half(helper)
    var left_dump = ideal_legacy_dump(legacy)
    _require_text(current, "changed ideal generic declaration")
    ideal_current_matches(current, left_dump)
    ideal_digest(left_dump.as_bytes(), "projected")
    var digests = PyJson.parse(ideal_digests())
    return projection_result(
        digests.text(digests.at(digests.root, "projected"))
    )


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
