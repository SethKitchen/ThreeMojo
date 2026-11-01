# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds of a process model.

A `Phase` says whether a species is a solid, a liquid or a gas. A
`RequirementKind` says which science a requirement comes from. A `Check`
says how a requirement is tested. A `Hazard` names a danger of a step. A
`Setting` names the least equipped place where a step can be done.
"""

from core.ordinal import ordinal_label, ordinal_valid


@fieldwise_init
struct Phase(Equatable, ImplicitlyCopyable, Writable):
    """The state of matter of a species."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three phases.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 2)

    def name(self) -> String:
        """Return the phase's short name.

        Returns:
            "s", "l" or "g", or "?" if not valid.
        """
        var names: List[String] = ["s", "l", "g"]
        return ordinal_label(self.is_valid(), self.value, names, "?")


# A crystalline or amorphous solid.
comptime SOLID = Phase(0)
# A liquid.
comptime LIQUID = Phase(1)
# An ideal gas.
comptime GAS = Phase(2)


@fieldwise_init
struct RequirementKind(Equatable, ImplicitlyCopyable, Writable):
    """The science a requirement comes from."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the five kinds.

        Returns:
            Whether the value is 0 to 4.
        """
        return ordinal_valid(self.value, 4)

    def name(self) -> String:
        """Return the kind's name.

        Returns:
            The name, or "?" if not valid.
        """
        var names: List[String] = [
            "thermodynamic",
            "phase",
            "kinetic",
            "physical",
            "engineering",
        ]
        return ordinal_label(self.is_valid(), self.value, names, "?")


# The reaction must have a driving force: the Gibbs energy must fall.
comptime THERMODYNAMIC = RequirementKind(0)
# A species must be in a given state: melted, boiled or condensed.
comptime PHASE = RequirementKind(1)
# A rate must be fast enough or slow enough. Practice gives these bounds.
comptime KINETIC = RequirementKind(2)
# A physical condition, such as a pressure or a plasma, must hold.
comptime PHYSICAL = RequirementKind(3)
# The equipment or the workpiece must survive and do its job.
comptime ENGINEERING = RequirementKind(4)


@fieldwise_init
struct Check(Equatable, ImplicitlyCopyable, Writable):
    """How a requirement is tested at a temperature and a pressure."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the seven checks.

        Returns:
            Whether the value is 0 to 6.
        """
        return ordinal_valid(self.value, 6)

    def name(self) -> String:
        """Return the check's name.

        Returns:
            The name, or "?" if not valid.
        """
        var names: List[String] = [
            "proceeds",
            "held back",
            "above",
            "below",
            "pressure above",
            "pressure below",
            "action",
        ]
        return ordinal_label(self.is_valid(), self.value, names, "?")


# A reaction must have a negative Gibbs energy change.
comptime PROCEEDS = Check(0)
# A reaction must have a positive Gibbs energy change.
comptime HELD_BACK = Check(1)
# The temperature must be above a bound.
comptime ABOVE = Check(2)
# The temperature must be below a bound.
comptime BELOW = Check(3)
# The pressure must be above a bound.
comptime PRESSURE_ABOVE = Check(4)
# The pressure must be below a bound.
comptime PRESSURE_BELOW = Check(5)
# A stated action that no number tests, such as an etch before a coating.
comptime ACTION = Check(6)


@fieldwise_init
struct Hazard(Equatable, ImplicitlyCopyable, Writable):
    """A danger of a process step."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the seven hazards.

        Returns:
            Whether the value is 0 to 6.
        """
        return ordinal_valid(self.value, 6)

    def name(self) -> String:
        """Return the hazard's name.

        Returns:
            The name, or "?" if not valid.
        """
        var names: List[String] = [
            "burn",
            "toxic gas",
            "corrosive",
            "flammable gas",
            "pyrophoric",
            "electrical",
            "pressure vessel",
        ]
        return ordinal_label(self.is_valid(), self.value, names, "?")


# Hot surfaces and molten material. Water on molten metal explodes as steam.
comptime BURN = Hazard(0)
# A poisonous gas or fume, such as chlorine or carbon monoxide.
comptime TOXIC_GAS = Hazard(1)
# An acid, an alkali or an oxidizer that attacks skin and eyes.
comptime CORROSIVE = Hazard(2)
# A gas that burns or explodes in air, such as hydrogen or methane.
comptime FLAMMABLE_GAS = Hazard(3)
# A material that catches fire in air by itself, such as fine metal powder.
comptime PYROPHORIC = Hazard(4)
# High voltage or high current.
comptime ELECTRICAL = Hazard(5)
# A vessel under vacuum or pressure, which can implode or burst.
comptime PRESSURE_VESSEL = Hazard(6)


@fieldwise_init
struct Setting(Equatable, ImplicitlyCopyable, Writable):
    """The least equipped place where a step can be done safely."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three settings.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 2)

    def name(self) -> String:
        """Return the setting's name.

        Returns:
            The name, or "?" if not valid.
        """
        var names: List[String] = [
            "home workshop",
            "equipped lab",
            "industrial plant",
        ]
        return ordinal_label(self.is_valid(), self.value, names, "?")


# A garage or a kitchen with a kiln, a torch and ordinary protection.
comptime HOME_WORKSHOP = Setting(0)
# A laboratory with fume extraction, gas handling and trained people.
comptime EQUIPPED_LAB = Setting(1)
# A licensed plant with engineered controls. Do not try it elsewhere.
comptime INDUSTRIAL_PLANT = Setting(2)
