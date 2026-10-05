# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Direct fingerprint controls for incomplete owned model lists."""

from std.testing import TestSuite, assert_equal, assert_true
from extensions.building.fingerprint import fingerprint
from tests.test_building_render import _building


def test_fingerprint_hashes_empty_owned_lists() raises:
    # Hashing reads owned lists, not referenced objects. It must also
    # distinguish incomplete content without calling Building.validate.
    var b = _building()
    var before = fingerprint(b)
    b.spaces[0].outline.clear()
    var empty_outline = fingerprint(b)
    assert_true(empty_outline != before)
    assert_equal(fingerprint(b), empty_outline)
    b.constructions[0].layers.clear()
    var empty_layers = fingerprint(b)
    assert_true(empty_layers != empty_outline)
    assert_equal(fingerprint(b), empty_layers)
    b.topology.complex.faces[0].loop.clear()
    var empty_face = fingerprint(b)
    assert_true(empty_face != empty_layers)
    assert_equal(fingerprint(b), empty_face)
    b.topology.complex.cell_faces[0].clear()
    var empty_cell = fingerprint(b)
    assert_true(empty_cell != empty_face)
    assert_equal(fingerprint(b), empty_cell)
    b.topology.complex.edge_faces[0].clear()
    var empty_edge = fingerprint(b)
    assert_true(empty_edge != empty_cell)
    assert_equal(fingerprint(b), empty_edge)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
