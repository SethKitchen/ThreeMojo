# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The fresh heading consumers stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._heading_consumers import heading_consumers, heading_plan
from tools._python_json import PyJson


def test_three_heading_consumers_stay_in_order() raises:
    """The domain proof comes before the two moment expansions."""
    var doc = PyJson.parse(heading_consumers())
    assert_equal(doc.length(doc.root), 3)
    assert_equal(doc.key(doc.root, 0), "spiral_domain_proof.mojo")
    assert_equal(doc.text(doc.value(doc.root, 0)), "_spiral_proof_branch")
    assert_equal(doc.key(doc.root, 1), "spiral_moment_proof.mojo")
    assert_equal(doc.key(doc.root, 2), "spiral_moment_table.mojo")
    assert_equal(
        doc.text(doc.value(doc.root, 2)), "_try_spiral_moment_expansion"
    )


def test_the_package_comes_before_the_consumers() raises:
    """The package path is read before the three consumer names."""
    var doc = PyJson.parse(heading_plan())
    assert_equal(doc.key(doc.root, 0), "package")
    assert_equal(doc.text(doc.at(doc.root, "package")), "extensions/carla")
    var consumers = doc.at(doc.root, "consumers")
    assert_equal(doc.key(consumers, 0), "spiral_domain_proof.mojo")
    assert_equal(doc.key(consumers, 1), "spiral_moment_proof.mojo")
    assert_equal(doc.key(consumers, 2), "spiral_moment_table.mojo")
    assert_equal(doc.text(doc.value(consumers, 0)), "_spiral_proof_branch")


def main() raises:
    """Run the heading consumer tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
