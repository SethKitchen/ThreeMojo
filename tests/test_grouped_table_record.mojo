# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The grouped table record binds the consumer graph and the stored GL table."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._python_tokens import stored_float_array, token_sha256
from tools._python_json import PyJson


comptime _Y_RECORD = "tools/carla_lane_oracle/grouped-y-successor-record.json"
"""The later grouped module, used to recover the table-era module."""
comptime _SELECTION = (
    "tools/carla_lane_oracle/selection-finiteness-contract.json"
)
"""The selection edit that sits between the table module and the Y module."""
comptime _GEOMETRY = "extensions/carla/geometry.mojo"
"""The live geometry file that still stores the GL table."""
comptime _MODULE = "extensions/carla/spiral_grouped_roundoff_proof.mojo"
"""The consumer module."""
comptime _TOKEN = (
    "3fcfc637a40c4e322b5747f27f8d77163c3f47a49d1092b37c20744cafecba40"
)
"""The token digest of the table-era consumer."""


def _field(doc: PyJson, node: Int, name: String) raises -> String:
    """Return one string field.

    Args:
        doc: The document.
        node: The object.
        name: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent.
    """
    return doc.text(doc.at(node, name))


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
        raise Error("missing grouped table fragment")
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
        raise Error("missing grouped table fragment")
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


def _table_module() raises -> String:
    """Return the table-era grouped module.

    Returns:
        The module whose token digest is the table contract.

    Raises:
        Error: The recorded functions do not rebuild that module.
    """
    var later = PyJson.parse(Path(_Y_RECORD).read_text())
    var selection = PyJson.parse(Path(_SELECTION).read_text())
    var full = _field(later, later.root, "before_complete_module")
    var modules = doc_modules(selection)
    var after = _field(selection, modules, "after_complete_function")
    var before = _field(selection, modules, "before_complete_function")
    return _replace_first(full, after, before)


def doc_modules(selection: PyJson) raises -> Int:
    """Return the grouped module object in the selection record.

    Args:
        selection: The selection record.

    Returns:
        The module object.

    Raises:
        Error: The module is absent.
    """
    return selection.at(selection.at(selection.root, "modules"), _MODULE)


def _table_ok(geometry: String) raises -> Bool:
    """Return whether the stored GL nodes and weights satisfy the contract.

    Args:
        geometry: The geometry source.

    Returns:
        True when both arrays are finite, symmetric, and inside their bounds.

    Raises:
        Error: An array declaration cannot be read.
    """
    var weights = stored_float_array(geometry, "_GL_WEIGHTS", 5)
    var nodes = stored_float_array(geometry, "_GL_NODES", 5)
    if weights[0] != weights[4] or weights[1] != weights[3]:
        return False
    for weight in weights:
        if not (weight > 0.0 and weight <= 1.0):
            return False
    for node in nodes:
        if not (node > -1.0 and node < 1.0):
            return False
    return True


def _consumer(module: String) raises:
    """Require the table-era consumer token digest.

    Args:
        module: The grouped module.

    Raises:
        Error: The consumer graph changed.
    """
    if token_sha256(module) != _TOKEN:
        raise Error("Reviewed grouped consumer graph changed")


def test_the_table_module_and_the_live_geometry_stay_bound() raises:
    """The recovered module keeps its digest, and the live table stays valid."""
    var module = _table_module()
    _consumer(module)
    var geometry = Path(_GEOMETRY).read_text()
    assert_true(_table_ok(geometry))
    var commented = "# harmless comment\n" + module
    var spaced = _replace_first(module, "var node_low =", "var  node_low =")
    _consumer(commented)
    _consumer(spaced)
    assert_true(_table_ok(geometry))
    var symmetric = _replace_all(geometry, "0.2369268850561891", "0.25")
    assert_true(_table_ok(symmetric))


def test_consumer_edits_change_the_grouped_graph() raises:
    """Each consumer edit changes the table-era token digest."""
    var module = _table_module()
    var cases = List[String]()
    cases.append("materialize[_GL_WEIGHTS]()")
    cases.append("materialize[_GL_NODES]()")
    cases.append("materialize[_GL_NODES]()")
    cases.append("materialize[_GL_WEIGHTS]()")
    cases.append("var node_low =")
    cases.append("weights[0] = 0.0\n    var node_low =")
    cases.append("d.error")
    cases.append("0.0")
    cases.append("5 * pieces")
    cases.append("pieces")
    cases.append("if not _sum2_supported_environment():")
    cases.append("if _sum2_supported_environment():")
    cases.append("_GL_WEIGHTS[0] <= 1.0")
    cases.append("_GL_WEIGHTS[0] < 1.0")
    var index = 0
    while index < len(cases):
        var changed = _replace_all(module, cases[index], cases[index + 1])
        var failed = False
        try:
            _consumer(changed)
        except error:
            failed = True
            assert_true(
                String(error).find("Reviewed grouped consumer graph changed")
                >= 0
            )
        assert_true(failed)
        index += 2


def test_producer_edits_and_decoys_are_refused() raises:
    """A broken declaration, a bad value, or a decoy cannot supply the table."""
    var geometry = Path(_GEOMETRY).read_text()
    var broken = List[String]()
    broken.append(
        _replace_first(geometry, "comptime _GL_WEIGHTS:", "var _GL_WEIGHTS:")
    )
    broken.append(_replace_all(geometry, "0.5688888888888889", "0.0"))
    broken.append(_replace_all(geometry, "0.9061798459386640", "1.0"))
    var start = geometry.find("comptime _GL_WEIGHTS: Array[Float64, 5] = [")
    var end = geometry.find("]", start)
    if start < 0 or end < start:
        raise Error("missing weight declaration")
    var declaration = String(geometry[byte = start : end + 1])
    broken.append(
        _replace_first(geometry, declaration, '"""' + declaration + '"""')
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
    broken.append(
        _replace_first(geometry, declaration, "if True:\n" + indented)
    )
    broken.append(
        _replace_first(geometry, declaration, declaration + " + [0.0]")
    )
    for text in broken:
        var failed = False
        try:
            _ = _table_ok(text)
        except error:
            failed = True
        if not failed:
            assert_false(_table_ok(text))
        else:
            assert_true(failed)


def main() raises:
    """Run the grouped table record tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
