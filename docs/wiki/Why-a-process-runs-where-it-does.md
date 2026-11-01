# Why a process runs where it does

A process temperature is not arbitrary. It is a point inside the overlap of several limits. Each limit comes from one science: thermodynamics, a phase change, a rate, a physical condition or the equipment. [Process chemistry](Process-chemistry) models a step as that list of limits.

## A yield equation hides the limits

A course often writes the Kroll process as one line: `TiCl4 + 2 Mg -> Ti + 2 MgCl2`. The line gives the masses. It does not say why the plant runs the reduction near 850 degC. It does not say why the plant needs three more steps.

The data gives most of the answer. The reaction proceeds strongly at every temperature from 800 K to 1500 K. So the driving force does not choose the temperature. The other requirements choose it:

- MgCl2 must be liquid, so it drains from the retort. It melts at 987 K, 714 degC.
- Magnesium must stay liquid at the retort pressure. It boils at about 1363 K, 1090 degC.
- The steel retort must stay below the iron-titanium eutectic at 1085 degC. Above it, the titanium alloys with the wall.

The window is 714 to 1085 degC. Practice runs near 800 to 900 degC, inside it, with room for the heat that the reaction gives off.

![Each Kroll step's requirements as bars over temperature, with the window where all hold and the planned temperature](out/process-windows.png)

The figure shows each requirement of the four Kroll steps as a bar where it holds. The white bar is the window where all of them hold, and the dot is the planned temperature. `examples/process_windows.mojo` draws it from the steps in `processes.titanium`.

## Each step has its own reason

Rutile does not react with chlorine alone. The Gibbs energy change of `TiO2 + 2 Cl2 -> TiCl4 + O2` is about +100 kJ/mol. With carbon, the change is about -290 kJ/mol, because carbon takes the oxygen. So the chlorinator burns coke with the ore.

TiCl4 is a liquid that boils at 136 degC. Distillation purifies it, because most of its impurities boil at other temperatures. VOCl3 boils at 127 degC, too close to separate, so the plant removes vanadium chemically first.

Titanium takes up oxygen strongly. The change of `Ti + O2 -> TiO2` is about -740 kJ/mol at 850 degC. So the retort runs under argon.

## Some limits come only from experiments

Thermodynamics says what can happen. It does not say how fast. A chlorinator runs near 1000 degC because the rate is too slow far below that, and practice measured that rate. Kroll and later engineers needed years of experiments to find these bounds and to control contamination.

A measured rate constant can replace a stated bound. [Rates and transport](Rates-and-transport) turns an Arrhenius law into a temperature bound with `RateAtLeast`.

The model keeps that difference visible. A computed bound says "computed from NASA TM-4513 data". A stated bound names its source. A kinetic limit that no number captures is an action in the report.

## A product can be metastable

Diamond is not the stable form of carbon at low pressure. Graphite to diamond has a change of about +5.7 kJ/mol at 850 degC and 30 Torr. Diamond becomes stable only above about 1.5 GPa at room temperature, which is why natural diamond forms deep in the earth.

A hot-filament reactor still grows diamond coatings at 30 Torr. Methane at 1 % in hydrogen can deposit either form, because both changes are negative. Atomic hydrogen from the filament etches graphite much faster than diamond. So the diamond survives, and kinetics chooses the product that thermodynamics does not prefer.

## Chemistry keeps the elements

Chemistry can separate and combine elements. It cannot change one element into another. Transmutation, such as mercury into gold, needs nuclear reactions and is outside this model.
