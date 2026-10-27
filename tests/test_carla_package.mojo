# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The CARLA extension package path stays reviewed."""

from std.testing import TestSuite, assert_equal

from tools._carla_package import carla_package


def test_the_carla_package_path_stays_reviewed() raises:
    """The package path is the extensions/carla directory."""
    assert_equal(carla_package(), "extensions/carla")


def main() raises:
    """Run the CARLA package path test."""
    TestSuite.discover_tests[__functions_in_module()]().run()
