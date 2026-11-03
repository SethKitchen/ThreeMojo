# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the data tools of `extensions.chemistry`: the fitter, the
CHEMKIN writer, the NASA CEA reader and enthalpy uncertainties.

The CEA record is O2 from NASA TP-2002-211556 in the `thermo.inp`
columns. It must read back to the same polynomials, and agree with the
catalog's older TM-4513 O2 to the 0.1 % the two fits differ by. A table
sampled from a NASA fit must refit to that fit. A CHEMKIN file written
from species must read back to them. An equilibrium temperature's
uncertainty must match moving the data by the uncertainty and solving
again.
"""

from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import (
    calcite,
    carbon_dioxide,
    iron,
    lime,
    magnesium_chloride,
    methane,
    oxygen,
)
from extensions.chemistry.cea import read_cea_thermo
from extensions.chemistry.chemkin import (
    chemkin_record,
    read_chemkin_thermo,
    write_chemkin_thermo,
)
from extensions.chemistry.elements import (
    CARBON,
    ElementCount,
    Formula,
    HYDROGEN,
    NITROGEN,
    OXYGEN,
    SILICON,
    SULFUR,
    TITANIUM,
)
from extensions.chemistry.fitting import ThermoPoint, fit_nasa7
from extensions.chemistry.kinds import GAS, LIQUID, SOLID
from extensions.chemistry.quantities import (
    MolarEnergy64,
    MolarEntropy64,
    MolarVolume64,
)
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.thermo import (
    Species,
    Substance,
    ThermoFit,
    nasa7,
    nasa9,
)
from units.si import Pressure64
from units.temperature import Temperature64

comptime NAN = nan[DType.float64]()


def _t(kelvin: Float64) -> Temperature64:
    return Temperature64(kelvin)


# --- fitting ----------------------------------------------------------------


def _co2_table(step: Float64, count: Int) raises -> List[ThermoPoint]:
    var fit = carbon_dioxide().phases[0].thermo.copy()
    var out = List[ThermoPoint]()
    for i in range(count):
        var t = _t(300 + step * Float64(i))
        out.append(
            ThermoPoint(
                t, fit.heat_capacity(t), fit.enthalpy(t), fit.entropy(t)
            )
        )
    return out^


def test_fit_recovers_nasa() raises:
    var fit = fit_nasa7(_co2_table(50, 59), _t(300), _t(1000), _t(3200))
    var nasa = carbon_dioxide().phases[0].thermo.copy()
    for i in range(30):
        var t = _t(300 + 100 * Float64(i))
        assert_almost_equal(
            fit.heat_capacity(t).value, nasa.heat_capacity(t).value, atol=1e-6
        )
        assert_almost_equal(
            fit.enthalpy(t).value, nasa.enthalpy(t).value, atol=0.01
        )
        assert_almost_equal(
            fit.entropy(t).value, nasa.entropy(t).value, atol=1e-5
        )


def test_fit_refuses_bad_tables() raises:
    var table = _co2_table(50, 59)
    with assert_raises(contains="positive and ascend"):
        _ = fit_nasa7(table, _t(1000), _t(1000), _t(3200))
    with assert_raises(contains="positive and ascend"):
        _ = fit_nasa7(table, _t(0), _t(1000), _t(3200))
    with assert_raises(contains="positive and ascend"):
        _ = fit_nasa7(table, _t(-1), _t(1000), _t(3200))
    with assert_raises(contains="outside the fit's range"):
        _ = fit_nasa7(table, _t(300), _t(1000), _t(2000))
    with assert_raises(contains="five points"):
        _ = fit_nasa7(table, _t(300), _t(400), _t(3200))
    with assert_raises(contains="five points"):
        _ = fit_nasa7(List[ThermoPoint](), _t(300), _t(1000), _t(3200))
    with assert_raises(contains="positive and ascend"):
        _ = fit_nasa7(table, _t(300), _t(3200), _t(3200))
    with assert_raises(contains="positive and ascend"):
        _ = fit_nasa7(table, _t(300), _t(1000), _t(inf[DType.float64]()))
    with assert_raises(contains="outside the fit's range"):
        _ = fit_nasa7(table, _t(400), _t(1000), _t(3200))
    with assert_raises(contains="five points"):
        _ = fit_nasa7(_co2_table(50, 18), _t(300), _t(1000), _t(3200))
    with assert_raises(contains="five points"):
        _ = fit_nasa7(_co2_table(10, 60), _t(300), _t(1000), _t(3200))
    var bad = _co2_table(50, 59)
    bad[3].enthalpy = MolarEnergy64(NAN)
    with assert_raises(contains="must be finite"):
        _ = fit_nasa7(bad, _t(300), _t(1000), _t(3200))


# --- CHEMKIN writer ---------------------------------------------------------


def _species(
    name: String, var formula: Formula, var fit: ThermoFit
) raises -> Species:
    return Species(name, formula^, SOLID, fit^, MolarVolume64(0))


def test_chemkin_round_trip() raises:
    var five = _species(
        "CHNOS",
        Formula(
            [
                ElementCount(CARBON, 1),
                ElementCount(HYDROGEN, 2),
                ElementCount(NITROGEN, 3),
                ElementCount(OXYGEN, 4),
                ElementCount(SULFUR, 5),
            ]
        ),
        nasa7(
            [300.0, 1000.0, 3000.0],
            [
                3.0,
                1e-3,
                0,
                0,
                0,
                -1000.0,
                5.0,
                9.999999999,
                -2e-4,
                1e-10,
                0,
                0,
                -1200.0,
                4.0,
            ],
        ),
    )
    var originals: List[Species] = [
        methane().phases[0].copy(),
        magnesium_chloride().phases[1].copy(),
        five^,
    ]
    var text = write_chemkin_thermo(originals)
    assert_true(text.startswith("THERMO\n"))
    assert_true(text.endswith("END\n"))
    for line in text.splitlines():
        var l = String(line)
        if l.byte_length() > 40:
            assert_equal(l.byte_length(), 80)
    var back = read_chemkin_thermo(text)
    assert_equal(len(back), 3)
    assert_equal(back[0].name, "CH4(g)")
    assert_true(back[0].phase == GAS)
    assert_true(back[1].phase == LIQUID)
    assert_equal(back[2].formula.count_of(SULFUR), 5)
    for i in range(3):
        for t in [1000.0, 1200.0, 2500.0]:
            var temperature = _t(t)
            assert_almost_equal(
                back[i].thermo.gibbs(temperature).value,
                originals[i].thermo.gibbs(temperature).value,
                atol=1e-3,
            )
    # A one-segment fit is written as two equal segments.
    assert_almost_equal(
        back[1].thermo.bounds[1], 0.5 * (987.0 + 5000.0), atol=1e-6
    )


def test_chemkin_writer_refuses() raises:
    with assert_raises(contains="at most two segments"):
        _ = chemkin_record(iron().phases[0])
    var nine = _species(
        "X",
        Formula([ElementCount(CARBON, 1)]),
        nasa9([300.0, 1000.0], [1.0, 0, 3.0, 0, 0, 0, 0, 0, 0]),
    )
    with assert_raises(contains="seven-coefficient form"):
        _ = chemkin_record(nine)
    var nine2 = _species(
        "X",
        Formula([ElementCount(CARBON, 1)]),
        nasa9([300.0, 1000.0], [0.0, 1.0, 3.0, 0, 0, 0, 0, 0, 0]),
    )
    with assert_raises(contains="seven-coefficient form"):
        _ = chemkin_record(nine2)
    assert_equal(
        write_chemkin_thermo(List[Species]()),
        "THERMO\n   300.000  1000.000  5000.000\nEND\n",
    )
    var plain = nasa7([300.0, 1000.0], [3.0, 0, 0, 0, 0, 0, 0])
    with assert_raises(contains="no space"):
        _ = chemkin_record(
            _species("A B", Formula([ElementCount(CARBON, 1)]), plain.copy())
        )
    with assert_raises(contains="no space"):
        _ = chemkin_record(
            _species(
                "ABCDEFGHIJKLMNOPQRS",
                Formula([ElementCount(CARBON, 1)]),
                plain.copy(),
            )
        )
    var six = Formula(
        [
            ElementCount(CARBON, 1),
            ElementCount(HYDROGEN, 1),
            ElementCount(NITROGEN, 1),
            ElementCount(OXYGEN, 1),
            ElementCount(SULFUR, 1),
            ElementCount(SILICON, 1),
        ]
    )
    with assert_raises(contains="at most five elements"):
        _ = chemkin_record(_species("X", six^, plain.copy()))
    with assert_raises(contains="does not fit"):
        _ = chemkin_record(
            _species("X", Formula([ElementCount(CARBON, 1000)]), plain.copy())
        )
    with assert_raises(contains="does not fit"):
        _ = chemkin_record(
            _species(
                "X",
                Formula([ElementCount(CARBON, 1)]),
                nasa7([300.0, 1e12], [3.0, 0, 0, 0, 0, 0, 0]),
            )
        )
    with assert_raises(contains="two digits"):
        _ = chemkin_record(
            _species(
                "X",
                Formula([ElementCount(CARBON, 1)]),
                nasa7([300.0, 1000.0], [3.0, 0, 0, 0, 0, 1e100, 0]),
            )
        )


# --- CEA reader -------------------------------------------------------------


comptime O2_LINES: List[StaticString] = [
    "O2                      Oxygen. Gurvich,1989 pt1 p94 pt2 p9.",
    (
        " 3 tpis89 O   2.00    0.00    0.00    0.00    0.00 0   31.9988000     "
        "     0.000"
    ),
    (
        "    200.000   1000.0007 -2.0 -1.0  0.0  1.0  2.0  3.0  4.0  0.0       "
        "  8680.104"
    ),
    (
        "-3.425563420D+04 4.847000970D+02 1.119010961D+00"
        " 4.293889240D-03-6.836300520D-07"
    ),
    (
        "-2.023372700D-09 1.039040018D-12                -3.391454870D+03"
        " 1.849699470D+01"
    ),
    (
        "   1000.000   6000.0007 -2.0 -1.0  0.0  1.0  2.0  3.0  4.0  0.0       "
        "  8680.104"
    ),
    (
        "-1.037939022D+06 2.344830282D+03 1.819732036D+00"
        " 1.267847582D-03-2.188067988D-07"
    ),
    (
        " 2.053719572D-11-8.193467050D-16                -1.689010929D+04"
        " 1.738716506D+01"
    ),
    (
        "   6000.000  20000.0007 -2.0 -1.0  0.0  1.0  2.0  3.0  4.0  0.0       "
        "  8680.104"
    ),
    (
        " 4.975294300D+08-2.866106874D+05 6.690352250D+01-6.169959020D-03"
        " 3.016396027D-07"
    ),
    (
        "-7.421416600D-12 7.278175770D-17                "
        " 2.293554027D+06-5.530621610D+02"
    ),
]


def _o2() -> String:
    var out = String()
    for line in materialize[O2_LINES]():
        out += String(line) + "\n"
    return out^


def _one_interval(name: String, formula: String, phase: String) -> String:
    """A record of one interval with O2's first coefficients."""
    var lines = materialize[O2_LINES]()
    return String(
        name,
        "\n 1 test   ",
        formula,
        phase,
        "   31.9988000          0.000\n",
        lines[2],
        "\n",
        lines[3],
        "\n",
        lines[4],
        "\n",
    )


def test_cea_reader() raises:
    var text = String(
        "! a comment\n",
        "thermo\n",
        "    200.00   1000.00   6000.00  20000.   9/09/04\n",
        _o2(),
        "\n",
        # A zero count is left out of a formula.
        _one_interval("O2z", "O   2.00XX  0.00    0.00    0.00    0.00", " 0"),
        # An ion, an assigned enthalpy, a fractional formula and a negative
        # count are left out.
        _one_interval("O2n", "O  -2.00    0.00    0.00    0.00    0.00", " 0"),
        _one_interval("O2+", "O   2.00E  -1.00    0.00    0.00    0.00", " 0"),
        "Xx        reactant\n",
        (
            " 0 test   O   2.00    0.00    0.00    0.00    0.00 0   31.9988000 "
            "         0.000\n"
        ),
        _one_interval("FeO", "FE  0.95O   1.00    0.00    0.00    0.00", " 1"),
        _one_interval(
            "TIO2(L)", "TI  1.00O   2.00    0.00    0.00    0.00", " 1"
        ),
        "END PRODUCTS\n",
        _one_interval(
            "TIO2(cr)", "TI  1.00O   2.00    0.00    0.00    0.00", " 1"
        ),
        "END REACTANTS\n",
        "This is not read.\n",
    )
    var species = read_cea_thermo(text)
    assert_equal(len(species), 4)
    assert_equal(species[1].name, "O2z")
    _ = species.pop(1)
    assert_equal(species[0].name, "O2")
    assert_true(species[0].phase == GAS)
    assert_equal(len(species[0].thermo.bounds), 4)
    assert_true(species[1].phase == LIQUID)
    assert_equal(species[1].formula.count_of(TITANIUM), 1)
    assert_true(species[2].phase == SOLID)
    var old = oxygen()
    for t in [300.0, 900.0, 1500.0, 5000.0]:
        var temperature = _t(t)
        assert_almost_equal(
            species[0].thermo.entropy(temperature).value,
            old.phases[0].thermo.entropy(temperature).value,
            atol=0.1,
        )
    assert_equal(len(read_cea_thermo("")), 0)


def test_cea_reader_refuses() raises:
    with assert_raises(contains="needs two lines"):
        _ = read_cea_thermo("O2\n")
    var lines = materialize[O2_LINES]()
    with assert_raises(contains="run past the file"):
        _ = read_cea_thermo(String(lines[0], "\n", lines[1], "\n"))
    with assert_raises(contains="run past the file"):
        _ = read_cea_thermo(
            String("X\n-1 test   O   2.00    0.00    0.00    0.00    0.00 0\n")
        )
    var bad_exponent = _o2().replace(" -2.0 -1.0", " -3.0 -1.0")
    with assert_raises(contains="exponents of T"):
        _ = read_cea_thermo(bad_exponent)
    var bad_number = _o2().replace("-3.425563420D+04", "-3.42556342xD+4")
    with assert_raises(contains="is not a number"):
        _ = read_cea_thermo(bad_number)
    var short = String(
        lines[0],
        "\n",
        lines[1].replace(" 3 tpis", " 1 tpis"),
        "\n",
        lines[2],
        "\n",
        lines[3],
        "\n",
        "-2.023372700D-09\n",
    )
    with assert_raises(contains="is not a number"):
        _ = read_cea_thermo(short)
    with assert_raises(contains="symbol 'QQ'"):
        _ = read_cea_thermo(
            _one_interval("Q", "QQ  1.00    0.00    0.00    0.00    0.00", " 0")
        )


# --- uncertainty ------------------------------------------------------------


def test_equilibrium_temperature_uncertainty() raises:
    var p = Pressure64(101325)
    var stone = calcite()
    stone.phases[0].set_uncertainty(MolarEnergy64(1000))
    var calc = Reaction(
        [reactant(stone.copy()), product(lime()), product(carbon_dioxide())]
    )
    assert_almost_equal(
        calc.delta_g_uncertainty(_t(1100)).value, 1000.0, atol=1e-9
    )
    var t_eq = calc.equilibrium_temperature(_t(900), _t(1199), p)
    var u = calc.equilibrium_temperature_uncertainty(t_eq, p)
    # Move calcite's enthalpy by the uncertainty and solve again.
    var moved = stone.phases[0].copy()
    moved.thermo = moved.thermo.shifted(MolarEnergy64(1000), MolarEntropy64(0))
    var shifted = Reaction(
        [
            reactant(Substance("CaCO3", [moved^])),
            product(lime()),
            product(carbon_dioxide()),
        ]
    )
    var t_moved = shifted.equilibrium_temperature(_t(900), _t(1199), p)
    assert_almost_equal(u.value, abs(t_moved.kelvin - t_eq.kelvin), atol=0.05)
    with assert_raises(contains="finite and not negative"):
        stone.phases[0].set_uncertainty(MolarEnergy64(-1))
    with assert_raises(contains="finite and not negative"):
        stone.phases[0].set_uncertainty(MolarEnergy64(NAN))
    # Two forms with one fit: the change never varies.
    var a = Substance("A", [stone.phases[0].copy()])
    var same = Reaction(
        [reactant(a.copy()), product(Substance("B", [stone.phases[0].copy()]))]
    )
    with assert_raises(contains="does not vary"):
        _ = same.equilibrium_temperature_uncertainty(_t(1000), p)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
