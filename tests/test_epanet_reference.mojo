# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The EPANET port against the results of OWA EPANET 2.3.6.

Each network in `assets/epanet/` has a `.expected` file from the real
EPANET library, made by `assets/epanet/make_epanet.py`. The file holds
the hydraulics of each hydraulic step and the water quality of each
report time, with ten significant digits. The port must give the same
time steps and agree with each value to the last printed digit.
"""

from std.testing import TestSuite, assert_equal

from extensions.epanet.project import EpanetProject
from tests._epanet_expected import Expected, check_simulation


def _check_network(name: String) raises:
    var base = String("assets/epanet/", name)
    var p = EpanetProject(open(base + ".inp", "r").read())
    var ex = Expected(open(base + ".expected", "r").read())
    check_simulation(p, ex)
    assert_equal(ex.peek(), String())


def test_net1_chlorine_decay() raises:
    """Net1: a pump, a tank, simple controls and chlorine decay."""
    _check_network("Net1")


def test_net2_fluoride_tracer() raises:
    """Net2: a tank fed by a pattern of demands and a fluoride source."""
    _check_network("Net2")


def test_net3_river_trace() raises:
    """Net3: two sources, three tanks, pumps and a source trace."""
    _check_network("Net3")


def test_valves() raises:
    """All seven valve types, a check valve and time and level controls."""
    _check_network("Valves")


def test_pumps_and_energy() raises:
    """Four pump curves, speed patterns, energy and water age."""
    _check_network("Pumps")


def test_pressure_driven_demand() raises:
    """PDA, leakage, emitters, demand categories, rules and a trace."""
    _check_network("Pressure")


def test_tank_mixing_and_sources() raises:
    """Four tank mixing models, four source types and reaction orders."""
    _check_network("Mixing")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
