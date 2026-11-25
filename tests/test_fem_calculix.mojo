# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests of the static solver against CalculiX CrunchiX 2.21.

`assets/calculix/make_calculix_reference.py` writes two decks of a steel
cantilever and runs ccx on each. Each test reads the same deck with
`read_deck`, solves it with `solve_static` and compares the displacement
of each node with that of ccx. The `.dat` file of ccx prints seven
significant digits, so a value can differ by half a unit in the
seventh digit.
"""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from extensions.fem.deck import read_deck, si_units
from extensions.fem.static import solve_static
from extensions.numerics.iterative import CONVERGED


def _largest_difference(name: String) raises -> Tuple[Float64, Float64]:
    """Solve a deck and compare it with the displacements of ccx.

    Args:
        name: The deck in `assets/calculix`, without its extension.

    Returns:
        The largest difference of a displacement component, and the
        largest displacement component of ccx, both in meters.

    Raises:
        Error: A file is missing, the solve does not converge, or the
            reference does not hold each node.
    """
    var deck = read_deck(String("assets/calculix/", name, ".inp"), si_units())
    var result = solve_static(deck.problem(), 1e-13, 20000)
    assert_true(result.status == CONVERGED)
    var text = Path(String("assets/calculix/", name, ".expected")).read_text()
    var worst = Float64(0)
    var largest = Float64(0)
    var count = 0
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        var words = line.split()
        var u = result.displacement(deck.node(Int(words[0])))
        var expected = [
            Float64(words[1]),
            Float64(words[2]),
            Float64(words[3]),
        ]
        var got = [u.x, u.y, u.z]
        for a in range(3):
            worst = max(worst, abs(got[a] - expected[a]))
            largest = max(largest, abs(expected[a]))
        count += 1
    assert_equal(count, deck.mesh.node_count())
    return (worst, largest)


def test_four_node_cantilever_matches_calculix() raises:
    """A cantilever of four-node elements with a tip load and gravity.

    Reference: ccx on the same deck. Each displacement is the same to
    one part in a million of the largest one.
    """
    var difference = _largest_difference("cantilever_c3d4")
    assert_true(difference[1] > 1e-5, String(difference[1]))
    assert_true(
        difference[0] < 1e-6 * difference[1],
        String(difference[0], " ", difference[1]),
    )


def test_ten_node_cantilever_matches_calculix() raises:
    """A cantilever of ten-node elements with a face pressure and a side load.

    Reference: ccx on the same deck. Each displacement is the same to
    one part in a million of the largest one.
    """
    var difference = _largest_difference("cantilever_c3d10")
    assert_true(difference[1] > 1e-5, String(difference[1]))
    assert_true(
        difference[0] < 1e-6 * difference[1],
        String(difference[0], " ", difference[1]),
    )


def main() raises:
    """Run the tests.

    Raises:
        Error: A test fails.
    """
    TestSuite.discover_tests[__functions_in_module()]().run()
