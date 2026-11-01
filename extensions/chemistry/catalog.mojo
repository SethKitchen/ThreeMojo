# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The substances of the process recipes, with their NASA data.

The coefficients are copied unchanged from McBride, Gordon and Reno,
"Coefficients for Calculating Thermodynamic and Transport Properties of
Individual Species", NASA TM-4513, 1993. That report is a work of the US
government. The copy came from the conversion that Cantera 3.2 ships in
`nasa_gas.yaml` and `nasa_condensed.yaml`. The comment above each species
gives the source code that TM-4513 assigns to its data.

`diamond` is not in TM-4513. It is graphite's data, moved by the enthalpy
and entropy of the graphite-to-diamond change at 298.15 K: 1.895 kJ/mol
and -3.363 J/(mol K), from the CODATA and NBS tables. That assumes the two
have the same heat capacity. Diamond's is lower, so the change in Gibbs
energy is low, by roughly one kJ/mol at 1000 K. The sign does not change,
so diamond stays metastable at low pressure in this model too.

A molar volume is given only where the pressure term matters: graphite
and diamond, for the pressure that makes diamond stable.
"""

from extensions.chemistry.elements import (
    CALCIUM,
    CARBON,
    CHLORINE,
    ElementCount,
    Formula,
    HYDROGEN,
    MAGNESIUM,
    OXYGEN,
    TITANIUM,
)
from extensions.chemistry.kinds import GAS, LIQUID, SOLID
from extensions.chemistry.quantities import (
    CUBIC_CENTIMETER_PER_MOLE,
    MolarEnergy64,
    MolarEntropy64,
    MolarVolume64,
)
from extensions.chemistry.thermo import Nasa7, Species, Substance

# The graphite-to-diamond change at 298.15 K and one bar.
comptime DIAMOND_ENTHALPY = MolarEnergy64(1895.0)
comptime DIAMOND_ENTROPY = MolarEntropy64(-3.363)
# Diamond's molar volume: 12.011 g/mol over 3.515 g/cm^3.
comptime DIAMOND_VOLUME = 3.4171


def graphite() raises -> Substance:
    """Return graphite, the stable form of carbon at low pressure.

    Its molar volume is 12.011 g/mol over 2.267 g/cm^3.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # C(gr), TM-4513 source X 4/83.
    phases.append(
        Species(
            "graphite",
            Formula([ElementCount(CARBON, 1)]),
            SOLID,
            Nasa7(
                [200.0, 1000.0, 5000.0],
                [
                    -0.310872072,
                    4.40353686e-03,
                    1.90394118e-06,
                    -6.38546966e-09,
                    2.98964248e-12,
                    -108.650794,
                    1.11382953,
                    1.45571829,
                    1.71702216e-03,
                    -6.97562786e-07,
                    1.35277032e-10,
                    -9.67590652e-15,
                    -695.138814,
                    -8.52583033,
                ],
            ),
            MolarVolume64(5.2982, CUBIC_CENTIMETER_PER_MOLE),
        )
    )
    return Substance("graphite", phases^)


def methane() raises -> Substance:
    """Return methane gas.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # CH4, TM-4513 source L 8/88.
    phases.append(
        Species(
            "CH4(g)",
            Formula([ElementCount(CARBON, 1), ElementCount(HYDROGEN, 4)]),
            GAS,
            Nasa7(
                [200.0, 1000.0, 6000.0],
                [
                    5.14987613,
                    -0.0136709788,
                    4.91800599e-05,
                    -4.84743026e-08,
                    1.66693956e-11,
                    -1.02466476e04,
                    -4.64130376,
                    1.63552643,
                    0.0100842795,
                    -3.36916254e-06,
                    5.34958667e-10,
                    -3.15518833e-14,
                    -1.00056455e04,
                    9.99313326,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("CH4(g)", phases^)


def hydrogen() raises -> Substance:
    """Return hydrogen gas.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # H2, TM-4513 source TPIS78.
    phases.append(
        Species(
            "H2(g)",
            Formula([ElementCount(HYDROGEN, 2)]),
            GAS,
            Nasa7(
                [200.0, 1000.0, 6000.0],
                [
                    2.34433112,
                    7.98052075e-03,
                    -1.9478151e-05,
                    2.01572094e-08,
                    -7.37611761e-12,
                    -917.935173,
                    0.683010238,
                    2.93286579,
                    8.26607967e-04,
                    -1.46402335e-07,
                    1.54100359e-11,
                    -6.88804432e-16,
                    -813.065597,
                    -1.02432887,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("H2(g)", phases^)


def atomic_hydrogen() raises -> Substance:
    """Return atomic hydrogen, the gas a hot filament or a plasma makes.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # H, TM-4513 source L 5/93.
    phases.append(
        Species(
            "H(g)",
            Formula([ElementCount(HYDROGEN, 1)]),
            GAS,
            Nasa7(
                [200.0, 1000.0, 6000.0],
                [
                    2.5,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    2.54736599e04,
                    -0.446682853,
                    2.50000286,
                    -5.65334214e-09,
                    3.63251723e-12,
                    -9.1994972e-16,
                    7.95260746e-20,
                    2.54736589e04,
                    -0.446698494,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("H(g)", phases^)


def oxygen() raises -> Substance:
    """Return oxygen gas.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # O2, TM-4513 source TPIS89.
    phases.append(
        Species(
            "O2(g)",
            Formula([ElementCount(OXYGEN, 2)]),
            GAS,
            Nasa7(
                [200.0, 1000.0, 6000.0],
                [
                    3.78245636,
                    -2.99673415e-03,
                    9.847302e-06,
                    -9.68129508e-09,
                    3.24372836e-12,
                    -1063.94356,
                    3.65767573,
                    3.66096083,
                    6.56365523e-04,
                    -1.41149485e-07,
                    2.05797658e-11,
                    -1.29913248e-15,
                    -1215.97725,
                    3.41536184,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("O2(g)", phases^)


def carbon_monoxide() raises -> Substance:
    """Return carbon monoxide gas.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # CO, TM-4513 source TPIS79.
    phases.append(
        Species(
            "CO(g)",
            Formula([ElementCount(CARBON, 1), ElementCount(OXYGEN, 1)]),
            GAS,
            Nasa7(
                [200.0, 1000.0, 6000.0],
                [
                    3.57953347,
                    -6.1035368e-04,
                    1.01681433e-06,
                    9.07005884e-10,
                    -9.04424499e-13,
                    -1.4344086e04,
                    3.50840928,
                    3.04848583,
                    1.35172818e-03,
                    -4.85794075e-07,
                    7.88536486e-11,
                    -4.69807489e-15,
                    -1.42661171e04,
                    6.0170979,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("CO(g)", phases^)


def carbon_dioxide() raises -> Substance:
    """Return carbon dioxide gas.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # CO2, TM-4513 source L 7/88.
    phases.append(
        Species(
            "CO2(g)",
            Formula([ElementCount(CARBON, 1), ElementCount(OXYGEN, 2)]),
            GAS,
            Nasa7(
                [200.0, 1000.0, 6000.0],
                [
                    2.35677352,
                    8.98459677e-03,
                    -7.12356269e-06,
                    2.45919022e-09,
                    -1.43699548e-13,
                    -4.83719697e04,
                    9.90105222,
                    4.63659493,
                    2.74131991e-03,
                    -9.95828531e-07,
                    1.60373011e-10,
                    -9.16103468e-15,
                    -4.90249341e04,
                    -1.93534855,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("CO2(g)", phases^)


def chlorine() raises -> Substance:
    """Return chlorine gas.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # CL2, TM-4513 source TPIS89.
    phases.append(
        Species(
            "Cl2(g)",
            Formula([ElementCount(CHLORINE, 2)]),
            GAS,
            Nasa7(
                [200.0, 1000.0, 6000.0],
                [
                    2.73638114,
                    7.835257e-03,
                    -1.45104963e-05,
                    1.25730834e-08,
                    -4.13247145e-12,
                    -1058.80114,
                    9.44555879,
                    4.74727508,
                    -4.8858171e-04,
                    2.68444871e-07,
                    -2.43476083e-11,
                    -1.03683148e-15,
                    -1511.01862,
                    -0.344551305,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("Cl2(g)", phases^)


def titanium_tetrachloride() raises -> Substance:
    """Return liquid titanium tetrachloride.

    The NASA data runs from 300 K, so the solid below 249 K is left out.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # TiCL4(L), TM-4513 source J12/67.
    phases.append(
        Species(
            "TiCl4(l)",
            Formula([ElementCount(TITANIUM, 1), ElementCount(CHLORINE, 4)]),
            LIQUID,
            Nasa7(
                [300.0, 1000.0, 5000.0],
                [
                    17.066042,
                    1.5777168e-03,
                    -1.0870376e-06,
                    1.0390303e-09,
                    -3.602253e-13,
                    -1.0187134e05,
                    -67.308228,
                    17.142643,
                    1.0937087e-03,
                    -1.0690311e-09,
                    2.6616757e-13,
                    -2.279448e-17,
                    -1.0188027e05,
                    -67.640142,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("TiCl4", phases^)


def titanium_tetrachloride_gas() raises -> Substance:
    """Return titanium tetrachloride gas.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # TiCL4, TM-4513 source J12/67.
    phases.append(
        Species(
            "TiCl4(g)",
            Formula([ElementCount(TITANIUM, 1), ElementCount(CHLORINE, 4)]),
            GAS,
            Nasa7(
                [300.0, 1000.0, 5000.0],
                [
                    6.9496757,
                    0.026049659,
                    -4.6520302e-05,
                    3.8384834e-08,
                    -1.2027915e-11,
                    -9.4677831e04,
                    -2.92575094,
                    12.38603,
                    7.0931316e-04,
                    -3.1746078e-07,
                    6.2603958e-11,
                    -4.5337038e-15,
                    -9.5669078e04,
                    -28.4715956,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("TiCl4(g)", phases^)


def rutile() raises -> Substance:
    """Return rutile, the titanium dioxide of mineral sands and pigments.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # TiO2(ru), TM-4513 source J12/73.
    phases.append(
        Species(
            "TiO2(rutile)",
            Formula([ElementCount(TITANIUM, 1), ElementCount(OXYGEN, 2)]),
            SOLID,
            Nasa7(
                [300.0, 1000.0, 2130.0],
                [
                    -0.16117517,
                    0.03796666,
                    -6.515475e-05,
                    5.2552136e-08,
                    -1.6200051e-11,
                    -1.1478897e05,
                    -1.8874035,
                    6.8489151,
                    4.2463461e-03,
                    -3.0088984e-06,
                    1.0602519e-09,
                    -1.4379597e-13,
                    -1.1599246e05,
                    -34.514106,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("TiO2", phases^)


def titanium() raises -> Substance:
    """Return titanium metal: alpha, then beta from 1156 K, then the liquid from 1944 K.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # Ti(a), TM-4513 source CODA89.
    phases.append(
        Species(
            "Ti(alpha)",
            Formula([ElementCount(TITANIUM, 1)]),
            SOLID,
            Nasa7(
                [200.0, 1000.0, 1156.0],
                [
                    1.3282964,
                    0.0104776117,
                    -2.19816539e-05,
                    2.17468998e-08,
                    -7.66060428e-12,
                    -706.881044,
                    -6.19722912,
                    29.7987171,
                    -0.0567369024,
                    3.0848735e-05,
                    0.0,
                    0.0,
                    -9275.57025,
                    -156.730793,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # Ti(b), TM-4513 source CODA89.
    phases.append(
        Species(
            "Ti(beta)",
            Formula([ElementCount(TITANIUM, 1)]),
            SOLID,
            Nasa7(
                [1156.0, 1944.0],
                [
                    4.55050938,
                    -5.78446834e-03,
                    6.58428776e-06,
                    -2.60523484e-09,
                    4.06930218e-13,
                    -186.695724,
                    -19.795304,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # Ti(L), TM-4513 source CODA89.
    phases.append(
        Species(
            "Ti(l)",
            Formula([ElementCount(TITANIUM, 1)]),
            LIQUID,
            Nasa7(
                [1944.0, 6000.0],
                [
                    5.62871414,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    -2375.09598,
                    -30.7872691,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("Ti", phases^)


def magnesium() raises -> Substance:
    """Return magnesium metal: the solid, then the liquid from 923 K.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # Mg(cr), TM-4513 source SRD 93.
    phases.append(
        Species(
            "Mg(s)",
            Formula([ElementCount(MAGNESIUM, 1)]),
            SOLID,
            Nasa7(
                [298.15, 923.0],
                [
                    1.47884944,
                    9.27430526e-03,
                    -1.95050788e-05,
                    1.98215527e-08,
                    -7.04927374e-12,
                    -716.649299,
                    -6.57222695,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # Mg(L), TM-4513 source SRD 93.
    phases.append(
        Species(
            "Mg(l)",
            Formula([ElementCount(MAGNESIUM, 1)]),
            LIQUID,
            Nasa7(
                [923.0, 6000.0],
                [
                    4.12531827,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    -658.934341,
                    -19.3786894,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("Mg", phases^)


def magnesium_gas() raises -> Substance:
    """Return magnesium vapor.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # Mg, TM-4513 source J 9/83.
    phases.append(
        Species(
            "Mg(g)",
            Formula([ElementCount(MAGNESIUM, 1)]),
            GAS,
            Nasa7(
                [200.0, 1000.0, 6000.0],
                [
                    2.5,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    1.69465876e04,
                    3.63433014,
                    2.31664484,
                    3.65866339e-04,
                    -2.33227803e-07,
                    5.3711757e-11,
                    -2.99513065e-15,
                    1.70119233e04,
                    4.63449516,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("Mg(g)", phases^)


def magnesium_chloride() raises -> Substance:
    """Return magnesium chloride: the solid, then the liquid from 987 K.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # MgCL2(s), TM-4513 source J12/65.
    phases.append(
        Species(
            "MgCl2(s)",
            Formula([ElementCount(MAGNESIUM, 1), ElementCount(CHLORINE, 2)]),
            SOLID,
            Nasa7(
                [300.0, 987.0],
                [
                    5.4491296,
                    0.016745224,
                    -2.5956907e-05,
                    1.9111573e-08,
                    -5.1059014e-12,
                    -7.9343894e04,
                    -24.261084,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # MgCL2(L), TM-4513 source J12/65.
    phases.append(
        Species(
            "MgCl2(l)",
            Formula([ElementCount(MAGNESIUM, 1), ElementCount(CHLORINE, 2)]),
            LIQUID,
            Nasa7(
                [987.0, 5000.0],
                [
                    11.071048,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    -7.6294618e04,
                    -48.972588,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("MgCl2", phases^)


def magnesium_chloride_gas() raises -> Substance:
    """Return magnesium chloride vapor, as the monomer.

    With this data MgCl2 boils at 1631 K at one atmosphere. The measured
    normal boiling point is about 1685 K, so treat it as an estimate.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # MgCL2, TM-4513 source J12/69.
    phases.append(
        Species(
            "MgCl2(g)",
            Formula([ElementCount(MAGNESIUM, 1), ElementCount(CHLORINE, 2)]),
            GAS,
            Nasa7(
                [300.0, 1000.0, 5000.0],
                [
                    5.4095529,
                    7.7206281e-03,
                    -1.1620094e-05,
                    7.9417889e-09,
                    -2.0252502e-12,
                    -4.9070537e04,
                    0.647158084,
                    7.2401913,
                    2.8856239e-04,
                    -1.2401187e-07,
                    2.3527101e-11,
                    -1.6443205e-15,
                    -4.9442326e04,
                    -8.18090146,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("MgCl2(g)", phases^)


def calcite() raises -> Substance:
    """Return calcite: limestone, chalk and seashells.

    The NASA data stops at 1200 K.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # CaCO3(caL), TM-4513 source BAR 89.
    phases.append(
        Species(
            "CaCO3(calcite)",
            Formula(
                [
                    ElementCount(CALCIUM, 1),
                    ElementCount(CARBON, 1),
                    ElementCount(OXYGEN, 3),
                ]
            ),
            SOLID,
            Nasa7(
                [298.15, 1000.0, 1200.0],
                [
                    -1.76968953,
                    0.0618884685,
                    -8.82380139e-05,
                    4.61909015e-08,
                    -2.9872974e-12,
                    -1.46691812e05,
                    6.32412532,
                    14.4388162,
                    -1.39777807e-03,
                    2.04333103e-06,
                    0.0,
                    0.0,
                    -1.5040071e05,
                    -72.8445489,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("CaCO3", phases^)


def lime() raises -> Substance:
    """Return lime: calcium oxide, also called quicklime.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # CaO(s), TM-4513 source J 6/73.
    phases.append(
        Species(
            "CaO(s)",
            Formula([ElementCount(CALCIUM, 1), ElementCount(OXYGEN, 1)]),
            SOLID,
            Nasa7(
                [300.0, 1000.0, 3200.0],
                [
                    1.6937688,
                    0.018149663,
                    -2.8372609e-05,
                    2.0513539e-08,
                    -5.5175768e-12,
                    -7.7482769e04,
                    -9.3710081,
                    5.6557517,
                    1.0165439e-03,
                    -2.5576899e-07,
                    5.4514395e-11,
                    -4.257995e-15,
                    -7.8238381e04,
                    -28.223372,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("CaO", phases^)


def diamond() raises -> Substance:
    """Return diamond, metastable at low pressure.

    Its data is graphite's, moved by the change at 298.15 K. See the
    module notes.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var carbon = graphite()
    var phases = List[Species]()
    phases.append(
        Species(
            "diamond",
            Formula([ElementCount(CARBON, 1)]),
            SOLID,
            carbon.phases[0].thermo.shifted(DIAMOND_ENTHALPY, DIAMOND_ENTROPY),
            MolarVolume64(DIAMOND_VOLUME, CUBIC_CENTIMETER_PER_MOLE),
        )
    )
    return Substance("diamond", phases^)
