# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Energy balances of streams.

A `StreamItem` is an amount of a substance at a temperature. The enthalpy
of a stream is the sum of amount times molar enthalpy, on the formation
scale, so it includes the heat of every reaction between two streams. A
step's heat duty is the enthalpy that leaves minus the enthalpy that
enters. A positive duty is heat the step needs. A negative duty is heat
the step gives off, which the equipment must remove.

    var feed = List[StreamItem]()
    feed.append(StreamItem(calcite(), Amount64(1, MOLE), Temperature64(298.15)))
    var out = List[StreamItem]()
    out.append(StreamItem(lime(), Amount64(1, MOLE), Temperature64(1173.15)))
    out.append(StreamItem(carbon_dioxide(), Amount64(1, MOLE),
                          Temperature64(1173.15)))
    heat_duty(feed, out)   # about 260 kJ
"""

from std.math import isfinite
from extensions.chemistry.quantities import Amount64
from extensions.chemistry.thermo import Substance
from units.si import Energy64
from units.temperature import Temperature64


struct StreamItem(Copyable, Movable):
    """An amount of a substance at a temperature."""

    var substance: Substance
    var amount: Amount64
    var temperature: Temperature64

    def __init__(
        out self,
        var substance: Substance,
        amount: Amount64,
        temperature: Temperature64,
    ):
        """Make a stream item. `stream_enthalpy` checks it.

        Args:
            substance: The substance.
            amount: How many moles.
            temperature: Its temperature.
        """
        self.substance = substance^
        self.amount = amount
        self.temperature = temperature


def stream_enthalpy(items: List[StreamItem]) raises -> Energy64:
    """Return the enthalpy of a stream, on the formation scale.

    Args:
        items: The substances in the stream.

    Returns:
        The sum of amount times molar enthalpy. An empty stream is zero.

    Raises:
        Error: If an amount is negative or not finite, or a substance's
            data does not reach its temperature.
    """
    var total = Float64(0)
    for item in items:
        if not (isfinite(item.amount.value) and item.amount.value >= 0):
            raise Error("An amount must be finite and not negative")
        var h = item.substance.enthalpy(item.temperature)
        total += h.times(item.amount).value
    return Energy64(total)


def heat_duty(
    entering: List[StreamItem], leaving: List[StreamItem]
) raises -> Energy64:
    """Return the heat a step needs: what leaves minus what enters.

    Args:
        entering: The feed, at its temperatures.
        leaving: The products, at theirs.

    Returns:
        The duty. Below zero, the step gives off heat.

    Raises:
        Error: If a stream is not valid.
    """
    return stream_enthalpy(leaving) - stream_enthalpy(entering)
