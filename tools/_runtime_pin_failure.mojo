# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Decide whether one frozen runtime-pin failure is relabeled."""

from tools._python_json import PY_BOOL, PY_LIST, PY_STR, PyJson


def _is_true(doc: PyJson, key: String) raises -> Bool:
    """Return whether a field is JSON true.

    Args:
        doc: The decision document.
        key: The field name.

    Returns:
        True only for a boolean true. Every other kind is false.
    """
    var node = doc.at(doc.root, key)
    return doc.kind(node) == PY_BOOL and doc.flag(node)


def _matches_one(doc: PyJson, key: String, expected: String) raises -> Bool:
    """Return whether a field is a one-item list holding `expected`.

    Args:
        doc: The decision document.
        key: The field name.
        expected: The one argument text.

    Returns:
        True when the field is exactly `[expected]`.
    """
    var node = doc.at(doc.root, key)
    if doc.kind(node) != PY_LIST or doc.length(node) != 1:
        return False
    var item = doc.item(node, 0)
    if doc.kind(item) != PY_STR:
        return False
    return doc.text(item) == expected


def runtime_pin_relabel(payload: String) raises -> String:
    """Decide whether a frozen runtime-pin failure is relabeled.

    Args:
        payload: JSON with `stage`. Stage `error` also has `operation`,
            `exact_value_error`, `error_args`, and `expected_error`. Stage
            `cause` also has `exact_contract_error`, `cause_args`, and
            `expected_cause`.

    Returns:
        `raise` when the original error stays. `cause` when the cause must
        be checked. `relabel` when the public runtime-pin diagnostic applies.

    Raises:
        Error: `stage` is not `error` or `cause`.
    """
    var doc = PyJson.parse(payload)
    var stage = doc.text(doc.at(doc.root, "stage"))
    if stage == "error":
        var operation = _is_true(doc, "operation")
        var exact_value = _is_true(doc, "exact_value_error")
        var error_match = _matches_one(
            doc, "error_args", doc.text(doc.at(doc.root, "expected_error"))
        )
        if operation or not exact_value or not error_match:
            return "raise"
        return "cause"
    if stage == "cause":
        var exact_contract = _is_true(doc, "exact_contract_error")
        var cause_match = _matches_one(
            doc, "cause_args", doc.text(doc.at(doc.root, "expected_cause"))
        )
        if not exact_contract or not cause_match:
            return "raise"
        return "relabel"
    raise Error("unreviewed runtime pin stage")
