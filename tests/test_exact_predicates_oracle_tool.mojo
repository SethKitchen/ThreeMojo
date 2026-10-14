# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The generated exact predicate cases are current.

Importing the generated helper makes it part of this suite's key, so an edit
to it runs this check again.
"""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests.exact_predicates_oracle import _oracle_cases
from tools.generate_exact_predicates_oracle import TARGET, generate, literal


def test_the_generated_helper_matches_the_exact_oracle() raises:
    var made = generate()
    assert_equal(made[1], 123)
    assert_equal(len(_oracle_cases()), made[1])
    assert_true(Path(TARGET).read_text() == made[0])


def test_literals_spell_the_double_s_bits() raises:
    assert_equal(literal(1.0), "_f(0x3FF0000000000000)")
    assert_equal(literal(-0.0), "_f(0x8000000000000000)")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
