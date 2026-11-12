# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare the equilibrium solver with Cantera's, where Cantera is installed.

    uv pip install --python .venv/bin/python cantera
    PYTHONPATH=$(ls -d .venv/lib/python3*/site-packages) \\
        .venv/bin/mojo run -I . tools/check_chemistry_cantera.mojo

This is a developer check. It is not part of `make check`, because CI
does not install Cantera. Both solvers read the same NASA TM-4513 data,
so they must agree to the solvers' tolerances. Cantera reads its NASA
files at a reference pressure of one atmosphere, but TM-4513 data is at
one bar. The tool rebuilds each Cantera species at one bar first. The tool equilibrates four
gas mixtures at a fixed temperature and pressure with each solver. It
prints the largest difference in mole fraction for each, and exits with 1
when one is above 1e-6.
"""

from std.python import Python, PythonObject
from std.sys import exit

from extensions.chemistry.catalog import (
    atomic_hydrogen,
    carbon_dioxide,
    carbon_monoxide,
    hydrogen,
    methane,
    nitrogen,
    oxygen,
    steam,
)
from extensions.chemistry.equilibrium import Charge, equilibrate
from extensions.chemistry.quantities import Amount64, MOLE
from extensions.chemistry.thermo import Substance
from units.si import Pressure64
from units.temperature import Temperature64

# The largest difference in mole fraction the two solvers may show.
comptime _LIMIT = 1e-6


def _candidates() raises -> List[Substance]:
    """Return the gases both solvers consider."""
    return [
        methane(),
        oxygen(),
        nitrogen(),
        carbon_monoxide(),
        carbon_dioxide(),
        steam(),
        hydrogen(),
        atomic_hydrogen(),
    ]


def _cantera_names() -> List[String]:
    """Return Cantera's names of the candidates, in the same order."""
    return ["CH4", "O2", "N2", "CO", "CO2", "H2O", "H2", "H"]


def _case(
    gas: PythonObject,
    label: String,
    charge: String,
    var feed: List[Charge],
    kelvin: Float64,
    pascal: Float64,
) raises -> Bool:
    """Equilibrate one mixture with both solvers and print the difference."""
    gas.TPX = Python.tuple(kelvin, pascal, charge)
    gas.equilibrate("TP")
    var ours = equilibrate(
        _candidates(), feed, Temperature64(kelvin), Pressure64(pascal)
    )
    var names = _cantera_names()
    var candidates = _candidates()
    var worst = Float64(0)
    for i in range(len(names)):
        var theirs = Float64(py=gas[names[i]].X[0])
        # A candidate with an element the charge lacks takes no part.
        var mine = Float64(0)
        try:
            mine = ours.mole_fraction(candidates[i].name)
        except:
            pass
        worst = max(worst, abs(theirs - mine))
    var ok = worst <= _LIMIT
    var verdict = String("ok")
    if not ok:
        verdict = "DIFFERS"
    print(label, "largest difference in mole fraction:", worst, verdict)
    return ok


def _charge(var pairs: List[Tuple[Float64, Int]]) raises -> List[Charge]:
    """Return a charge of the candidates by index and moles."""
    var candidates = _candidates()
    var out = List[Charge]()
    for p in pairs:
        out.append(Charge(candidates[p[1]].copy(), Amount64(p[0], MOLE)))
    return out^


def main() raises:
    var ct = Python.import_module("cantera")
    var keep = Python.list()
    var names = _cantera_names()
    for s in ct.Species.list_from_file("nasa_gas.yaml"):
        var name = String(py=s.name)
        for w in names:
            if name == w:
                var t = s.thermo
                s.thermo = ct.NasaPoly2(t.min_temp, t.max_temp, 1e5, t.coeffs)
                keep.append(s)
    var gas = ct.Solution(thermo="ideal-gas", species=keep)
    var ok = True
    ok = (
        _case(
            gas,
            "methane in air, 2000 K, 1 atm:",
            "CH4:1, O2:2, N2:7.52",
            _charge([(1.0, 0), (2.0, 1), (7.52, 2)]),
            2000,
            101325,
        )
        and ok
    )
    ok = (
        _case(
            gas,
            "methane in air, 3000 K, 10 atm:",
            "CH4:1, O2:2, N2:7.52",
            _charge([(1.0, 0), (2.0, 1), (7.52, 2)]),
            3000,
            1013250,
        )
        and ok
    )
    ok = (
        _case(
            gas,
            "hydrogen and oxygen, 3500 K, 1 bar:",
            "H2:2, O2:1",
            _charge([(2.0, 6), (1.0, 1)]),
            3500,
            1e5,
        )
        and ok
    )
    ok = (
        _case(
            gas,
            "water-gas shift, 1100 K, 1 atm:",
            "CO2:1, H2:1",
            _charge([(1.0, 4), (1.0, 6)]),
            1100,
            101325,
        )
        and ok
    )
    if not ok:
        exit(1)
