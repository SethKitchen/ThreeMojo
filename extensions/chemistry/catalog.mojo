# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Built-in substances, with their NASA data.

Most records are in the seven-coefficient form. Alpha iron is in the
nine-coefficient form, as Cantera stores it. The coefficients are copied unchanged from McBride, Gordon and Reno,
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
    ALUMINUM,
    ARGON,
    CALCIUM,
    CARBON,
    CHLORINE,
    ElementCount,
    Formula,
    HYDROGEN,
    IRON,
    MAGNESIUM,
    NITROGEN,
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
from extensions.chemistry.thermo import Species, Substance, nasa7, nasa9

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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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
            nasa7(
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


def water() raises -> Substance:
    """Return liquid water.

    The NASA data runs from 273.15 K to 600 K.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # H2O(L), TM-4513 source L 8/89.
    phases.append(
        Species(
            "H2O(l)",
            Formula([ElementCount(HYDROGEN, 2), ElementCount(OXYGEN, 1)]),
            LIQUID,
            nasa7(
                [273.15, 600.0],
                [
                    72.5575005,
                    -0.662445402,
                    2.56198746e-03,
                    -4.36591923e-06,
                    2.78178981e-09,
                    -4.18865499e04,
                    -288.280137,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("H2O", phases^)


def steam() raises -> Substance:
    """Return water vapor.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # H2O, TM-4513 source L 8/89.
    phases.append(
        Species(
            "H2O(g)",
            Formula([ElementCount(HYDROGEN, 2), ElementCount(OXYGEN, 1)]),
            GAS,
            nasa7(
                [200.0, 1000.0, 6000.0],
                [
                    4.19864056,
                    -2.0364341e-03,
                    6.52040211e-06,
                    -5.48797062e-09,
                    1.77197817e-12,
                    -3.02937267e04,
                    -0.849032208,
                    2.67703787,
                    2.97318329e-03,
                    -7.7376969e-07,
                    9.44336689e-11,
                    -4.26900959e-15,
                    -2.98858938e04,
                    6.88255571,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("H2O(g)", phases^)


def aluminum() raises -> Substance:
    """Return aluminum metal: the solid, then the liquid from 933.61 K.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # AL(cr), TM-4513 source CODA89.
    phases.append(
        Species(
            "Al(s)",
            Formula([ElementCount(ALUMINUM, 1)]),
            SOLID,
            nasa7(
                [200.0, 933.61],
                [
                    1.01040191,
                    0.0120769743,
                    -2.62083556e-05,
                    2.64282413e-08,
                    -9.01916513e-12,
                    -654.454196,
                    -5.00471254,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # AL(L), TM-4513 source CODA89.
    phases.append(
        Species(
            "Al(l)",
            Formula([ElementCount(ALUMINUM, 1)]),
            LIQUID,
            nasa7(
                [933.61, 6000.0],
                [
                    3.81862551,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    -94.9651808,
                    -17.5229704,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("Al", phases^)


def alumina() raises -> Substance:
    """Return alumina: alpha aluminum oxide, corundum, then the liquid from 2327 K.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # AL2O3(a), TM-4513 source J12/79.
    phases.append(
        Species(
            "Al2O3(alpha)",
            Formula([ElementCount(ALUMINUM, 2), ElementCount(OXYGEN, 3)]),
            SOLID,
            nasa7(
                [300.0, 1000.0, 2327.0],
                [
                    -4.9138309,
                    0.079398443,
                    -1.3237918e-04,
                    1.044675e-07,
                    -3.156633e-11,
                    -2.0262622e05,
                    15.478073,
                    11.833666,
                    3.7708878e-03,
                    -1.7863191e-07,
                    -5.6008807e-10,
                    1.4076825e-13,
                    -2.0571131e05,
                    -63.599835,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # AL2O3(L), TM-4513 source J12/79.
    phases.append(
        Species(
            "Al2O3(l)",
            Formula([ElementCount(ALUMINUM, 2), ElementCount(OXYGEN, 3)]),
            LIQUID,
            nasa7(
                [2327.0, 6000.0],
                [
                    23.148241,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    -2.114052e05,
                    -138.60205,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("Al2O3", phases^)


def magnesia() raises -> Substance:
    """Return magnesia: magnesium oxide, then the liquid from 3105 K.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # MgO(s), TM-4513 source J12/74.
    phases.append(
        Species(
            "MgO(s)",
            Formula([ElementCount(MAGNESIUM, 1), ElementCount(OXYGEN, 1)]),
            SOLID,
            nasa7(
                [300.0, 1000.0, 3105.0],
                [
                    -0.45403953,
                    0.027873269,
                    -4.9062247e-05,
                    4.0474151e-08,
                    -1.2670344e-11,
                    -7.3057948e04,
                    -0.6355202,
                    5.0448681,
                    1.6898201e-03,
                    -7.5617695e-07,
                    2.0286893e-10,
                    -2.0591271e-14,
                    -7.4029285e04,
                    -26.328892,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # MgO(L), TM-4513 source J12/74.
    phases.append(
        Species(
            "MgO(l)",
            Formula([ElementCount(MAGNESIUM, 1), ElementCount(OXYGEN, 1)]),
            LIQUID,
            nasa7(
                [3105.0, 5000.0],
                [
                    8.0516715,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    -6.9879451e04,
                    -44.343825,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("MgO", phases^)


def iron() raises -> Substance:
    """Return iron: alpha, then gamma from 1184 K, delta from 1665 K and the liquid from 1809 K.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # Fe(a), TM-4513 source J 3/78.
    phases.append(
        Species(
            "Fe(alpha)",
            Formula([ElementCount(IRON, 1)]),
            SOLID,
            nasa9(
                [200.0, 1000.0, 1042.0, 1184.0],
                [
                    0.0,
                    0.0,
                    2.41337476,
                    -1.57780744e-03,
                    2.14701339e-05,
                    -3.80171438e-08,
                    2.20426984e-11,
                    -774.380998,
                    -10.6560296,
                    0.0,
                    0.0,
                    4690.80173,
                    -9.90659991,
                    2.69427446e-03,
                    5.54445321e-06,
                    -3.01659823e-09,
                    -1.41547586e06,
                    -2.49294387e04,
                    0.0,
                    0.0,
                    659.678809,
                    -1.14058217,
                    4.96306997e-04,
                    0.0,
                    0.0,
                    -2.52106802e05,
                    -3656.65236,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # Fe(c), TM-4513 source J 3/78.
    phases.append(
        Species(
            "Fe(gamma)",
            Formula([ElementCount(IRON, 1)]),
            SOLID,
            nasa7(
                [1184.0, 1665.0],
                [
                    61.010999,
                    -0.160945061,
                    1.68369493e-04,
                    -7.74563702e-08,
                    1.3309129e-11,
                    -1.65335454e04,
                    -313.710668,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # Fe(d), TM-4513 source J 3/78.
    phases.append(
        Species(
            "Fe(delta)",
            Formula([ElementCount(IRON, 1)]),
            SOLID,
            nasa7(
                [1665.0, 1809.0],
                [
                    -435.904698,
                    0.768489448,
                    -4.46898892e-04,
                    8.67070913e-08,
                    0.0,
                    1.87925534e05,
                    2450.57619,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # Fe(L), TM-4513 source J 3/78.
    phases.append(
        Species(
            "Fe(l)",
            Formula([ElementCount(IRON, 1)]),
            LIQUID,
            nasa7(
                [1809.0, 6000.0],
                [
                    5.53538332,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    -1274.28941,
                    -29.4772271,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("Fe", phases^)


def wustite() raises -> Substance:
    """Return wustite, iron(II) oxide, then the liquid from 1650 K.

    The data is for FeO as written. Real wustite holds a little less iron.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # FeO(s), TM-4513 source J 6/65.
    phases.append(
        Species(
            "FeO(s)",
            Formula([ElementCount(IRON, 1), ElementCount(OXYGEN, 1)]),
            SOLID,
            nasa7(
                [300.0, 1000.0, 1650.0],
                [
                    5.3195475,
                    2.2096591e-03,
                    1.0721775e-06,
                    -2.7929729e-09,
                    1.3320733e-12,
                    -3.4407165e04,
                    -23.686034,
                    5.8316489,
                    1.4275156e-03,
                    -9.3208143e-08,
                    -6.5997763e-12,
                    -2.2512143e-14,
                    -3.4566902e04,
                    -26.44699,
                ],
            ),
            MolarVolume64(0),
        )
    )
    # FeO(L), TM-4513 source J 6/65.
    phases.append(
        Species(
            "FeO(l)",
            Formula([ElementCount(IRON, 1), ElementCount(OXYGEN, 1)]),
            LIQUID,
            nasa7(
                [1650.0, 5000.0],
                [
                    8.2022482,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    -3.3848615e04,
                    -40.079129,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("FeO", phases^)


def magnetite() raises -> Substance:
    """Return magnetite, Fe3O4.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # Fe3O4(s), TM-4513 source J 6/65.
    phases.append(
        Species(
            "Fe3O4(s)",
            Formula([ElementCount(IRON, 3), ElementCount(OXYGEN, 4)]),
            SOLID,
            nasa7(
                [300.0, 1000.0, 5000.0],
                [
                    36.198148,
                    -0.17437976,
                    5.2475673e-04,
                    -5.4238219e-07,
                    1.7996202e-10,
                    -1.413873e05,
                    -155.56683,
                    24.13372,
                    4.1592226e-05,
                    -2.6331492e-08,
                    6.6035094e-12,
                    -5.692468e-16,
                    -1.4121052e05,
                    -120.06412,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("Fe3O4", phases^)


def hematite() raises -> Substance:
    """Return hematite, Fe2O3.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # Fe2O3(s), TM-4513 source J 6/65.
    phases.append(
        Species(
            "Fe2O3(s)",
            Formula([ElementCount(IRON, 2), ElementCount(OXYGEN, 3)]),
            SOLID,
            nasa7(
                [300.0, 1000.0, 2500.0],
                [
                    -7.7037843,
                    0.13647471,
                    -3.2905655e-04,
                    3.8150478e-07,
                    -1.6310285e-10,
                    -1.0080076e05,
                    25.292085,
                    40.49753,
                    -0.046131596,
                    3.1826406e-05,
                    -8.9226331e-09,
                    8.4655417e-13,
                    -1.1317627e05,
                    -216.35088,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("Fe2O3", phases^)


def argon() raises -> Substance:
    """Return argon gas.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # Ar, TM-4513 source L 6/88.
    phases.append(
        Species(
            "Ar(g)",
            Formula([ElementCount(ARGON, 1)]),
            GAS,
            nasa7(
                [200.0, 6000.0],
                [
                    2.5,
                    0.0,
                    0.0,
                    0.0,
                    0.0,
                    -745.375,
                    4.37967491,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("Ar(g)", phases^)


def nitrogen() raises -> Substance:
    """Return nitrogen gas.

    Returns:
        The substance.

    Raises:
        Error: Never. The data is checked as it is built.
    """
    var phases = List[Species]()
    # N2, TM-4513 source TPIS78.
    phases.append(
        Species(
            "N2(g)",
            Formula([ElementCount(NITROGEN, 2)]),
            GAS,
            nasa7(
                [200.0, 1000.0, 6000.0],
                [
                    3.53100528,
                    -1.23660987e-04,
                    -5.02999437e-07,
                    2.43530612e-09,
                    -1.40881235e-12,
                    -1046.97628,
                    2.96747468,
                    2.95257626,
                    1.39690057e-03,
                    -4.92631691e-07,
                    7.86010367e-11,
                    -4.60755321e-15,
                    -923.948645,
                    5.87189252,
                ],
            ),
            MolarVolume64(0),
        )
    )
    return Substance("N2(g)", phases^)


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
