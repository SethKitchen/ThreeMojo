# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from types.h of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The kinds and the constants of the EPANET engine.

Each enumeration of `types.h` is a type here. A value keeps the number of
the C enumeration, so a comparison such as "a valve is any link after a
pump" reads as it does in the C code.
"""

from std.math import pi
from core.ordinal import ordinal_valid

# The constants of types.h. Internal units are feet, cubic feet per
# second and seconds.
comptime BIG = 1.0e10
comptime TINY = 1.0e-6
comptime MISSING = -1.0e10
comptime DIFFUS = 1.3e-8
comptime VISCOS = 1.1e-5
comptime MINPDIFF = 0.1
comptime PI = pi
comptime MAXID = 31

# Flow units per cubic foot per second, and other conversion factors.
comptime GPM_PER_CFS = 448.831
comptime AFD_PER_CFS = 1.9837
comptime MGD_PER_CFS = 0.64632
comptime IMGD_PER_CFS = 0.5382
comptime LPS_PER_CFS = 28.317
comptime LPM_PER_CFS = 1699.0
comptime CMS_PER_CFS = 0.028317
comptime CMH_PER_CFS = 101.94
comptime CMD_PER_CFS = 2446.6
comptime MLD_PER_CFS = 2.4466
comptime M3_PER_FT3 = 0.028317
comptime L_PER_FT3 = 28.317
comptime M_PER_FT = 0.3048
comptime PSI_PER_FT = 0.4333
comptime KPA_PER_PSI = 6.895
comptime BAR_PER_PSI = 0.068948
comptime KW_PER_HP = 0.7457
comptime SEC_PER_DAY = 86400


@fieldwise_init
struct NodeType(Equatable, ImplicitlyCopyable, Writable):
    """What a node is: a junction, a reservoir or a tank."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three node types.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 2)


comptime JUNCTION = NodeType(0)
comptime RESERVOIR = NodeType(1)
comptime TANK = NodeType(2)


@fieldwise_init
struct LinkType(Equatable, ImplicitlyCopyable, Writable):
    """What a link is: a pipe, a pump or one of seven valves."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the ten link types.

        Returns:
            Whether the value is 0 to 9.
        """
        return ordinal_valid(self.value, 9)


comptime CVPIPE = LinkType(0)
comptime PIPE = LinkType(1)
comptime PUMP = LinkType(2)
comptime PRV = LinkType(3)
comptime PSV = LinkType(4)
comptime PBV = LinkType(5)
comptime FCV = LinkType(6)
comptime TCV = LinkType(7)
comptime GPV = LinkType(8)
comptime PCV = LinkType(9)


@fieldwise_init
struct StatusType(Equatable, ImplicitlyCopyable, Writable):
    """The status of a link or of a tank during the hydraulics."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the eleven statuses.

        Returns:
            Whether the value is 0 to 10.
        """
        return ordinal_valid(self.value, 10)


comptime XHEAD = StatusType(0)
comptime TEMPCLOSED = StatusType(1)
comptime CLOSED = StatusType(2)
comptime OPEN = StatusType(3)
comptime ACTIVE = StatusType(4)
comptime XFLOW = StatusType(5)
comptime XFCV = StatusType(6)
comptime XPRESSURE = StatusType(7)
comptime FILLING = StatusType(8)
comptime EMPTYING = StatusType(9)
comptime OVERFLOWING = StatusType(10)


@fieldwise_init
struct CurveType(Equatable, ImplicitlyCopyable, Writable):
    """What a data curve gives: a volume, a pump head, and so on."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the six curve types.

        Returns:
            Whether the value is 0 to 5.
        """
        return ordinal_valid(self.value, 5)


comptime VOLUME_CURVE = CurveType(0)
comptime PUMP_CURVE = CurveType(1)
comptime EFFIC_CURVE = CurveType(2)
comptime HLOSS_CURVE = CurveType(3)
comptime GENERIC_CURVE = CurveType(4)
comptime VALVE_CURVE = CurveType(5)


@fieldwise_init
struct PumpType(Equatable, ImplicitlyCopyable, Writable):
    """The law of a pump: constant power, a power function or a curve."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four pump types.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 3)


comptime CONST_HP = PumpType(0)
comptime POWER_FUNC = PumpType(1)
comptime CUSTOM = PumpType(2)
comptime NOCURVE = PumpType(3)


@fieldwise_init
struct SourceType(Equatable, ImplicitlyCopyable, Writable):
    """How a water quality source adds its constituent."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four source types.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 3)


comptime CONCEN = SourceType(0)
comptime MASS = SourceType(1)
comptime SETPOINT = SourceType(2)
comptime FLOWPACED = SourceType(3)


@fieldwise_init
struct ControlType(Equatable, ImplicitlyCopyable, Writable):
    """What starts a simple control: a level, a time or a clock time."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four control types.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 3)


comptime LOWLEVEL = ControlType(0)
comptime HILEVEL = ControlType(1)
comptime TIMER = ControlType(2)
comptime TIMEOFDAY = ControlType(3)


@fieldwise_init
struct MixType(Equatable, ImplicitlyCopyable, Writable):
    """The mixing model of a tank."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four mixing models.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 3)


comptime MIX1 = MixType(0)
comptime MIX2 = MixType(1)
comptime FIFO = MixType(2)
comptime LIFO = MixType(3)


@fieldwise_init
struct HeadLossType(Equatable, ImplicitlyCopyable, Writable):
    """The head loss formula of the pipes."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three formulas.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 2)


comptime HW = HeadLossType(0)
comptime DW = HeadLossType(1)
comptime CM = HeadLossType(2)


@fieldwise_init
struct UnitSystem(Equatable, ImplicitlyCopyable, Writable):
    """US customary units or SI units."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two unit systems.

        Returns:
            Whether the value is 0 or 1.
        """
        return ordinal_valid(self.value, 1)


comptime US = UnitSystem(0)
comptime SI = UnitSystem(1)


@fieldwise_init
struct FlowUnits(Equatable, ImplicitlyCopyable, Writable):
    """The flow units of an input file."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the eleven flow units.

        Returns:
            Whether the value is 0 to 10.
        """
        return ordinal_valid(self.value, 10)


comptime CFS = FlowUnits(0)
comptime GPM = FlowUnits(1)
comptime MGD = FlowUnits(2)
comptime IMGD = FlowUnits(3)
comptime AFD = FlowUnits(4)
comptime LPS = FlowUnits(5)
comptime LPM = FlowUnits(6)
comptime MLD = FlowUnits(7)
comptime CMH = FlowUnits(8)
comptime CMD = FlowUnits(9)
comptime CMS = FlowUnits(10)


@fieldwise_init
struct PressureUnits(Equatable, ImplicitlyCopyable, Writable):
    """The pressure units of an input file."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the six pressure units.

        Returns:
            Whether the value is 0 to 5.
        """
        return ordinal_valid(self.value, 5)


comptime PSI = PressureUnits(0)
comptime KPA = PressureUnits(1)
comptime METERS = PressureUnits(2)
comptime BAR = PressureUnits(3)
comptime FEET = PressureUnits(4)
comptime DEFAULTUNIT = PressureUnits(5)


@fieldwise_init
struct QualityType(Equatable, ImplicitlyCopyable, Writable):
    """The water quality analysis: none, a chemical, age or a trace."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four analyses.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 3)


comptime NONE = QualityType(0)
comptime CHEM = QualityType(1)
comptime AGE = QualityType(2)
comptime TRACE = QualityType(3)


@fieldwise_init
struct DemandModel(Equatable, ImplicitlyCopyable, Writable):
    """Demand driven or pressure driven analysis."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two demand models.

        Returns:
            Whether the value is 0 or 1.
        """
        return ordinal_valid(self.value, 1)


comptime DDA = DemandModel(0)
comptime PDA = DemandModel(1)


@fieldwise_init
struct FlowDirection(Equatable, ImplicitlyCopyable, Writable):
    """The sign of the flow in a link for the water quality routing.

    The value is -1, 0 or +1, as in the C enumeration.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is -1, 0 or +1.

        Returns:
            Whether the value is -1 to 1.
        """
        return ordinal_valid(self.value + 1, 2)


comptime NEGATIVE = FlowDirection(-1)
comptime ZERO_FLOW = FlowDirection(0)
comptime POSITIVE = FlowDirection(1)


@fieldwise_init
struct NodeProperty(Equatable, ImplicitlyCopyable, Writable):
    """A result of a node that `EpanetProject.node_value` gives.

    The values are the codes of `EN_NodeProperty` in the EPANET toolkit.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a result that the port gives.

        Returns:
            Whether the value is `EN_DEMAND` to `EN_QUALITY`.
        """
        return self.value >= 9 and self.value <= 12


comptime EN_DEMAND = NodeProperty(9)
comptime EN_HEAD = NodeProperty(10)
comptime EN_PRESSURE = NodeProperty(11)
comptime EN_QUALITY = NodeProperty(12)


@fieldwise_init
struct LinkProperty(Equatable, ImplicitlyCopyable, Writable):
    """A result of a link that `EpanetProject.link_value` gives.

    The values are the codes of `EN_LinkProperty` in the EPANET toolkit.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a result that the port gives.

        Returns:
            Whether the value is `EN_FLOW`, `EN_STATUS`, `EN_SETTING`,
            `EN_ENERGY` or `EN_LINKQUAL`.
        """
        return (
            self.value == 8
            or self.value == 11
            or self.value == 12
            or self.value == 13
            or self.value == 14
        )


comptime EN_FLOW = LinkProperty(8)
comptime EN_STATUS = LinkProperty(11)
comptime EN_SETTING = LinkProperty(12)
comptime EN_ENERGY = LinkProperty(13)
comptime EN_LINKQUAL = LinkProperty(14)


@fieldwise_init
struct NodeIndex(Equatable, ImplicitlyCopyable, Writable):
    """The index of a node in a project, from 1, as in the EPANET toolkit.

    The junctions come first, then the reservoirs and the tanks.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a node.

        Returns:
            Whether the value is 1 or more.
        """
        return self.value >= 1


@fieldwise_init
struct LinkIndex(Equatable, ImplicitlyCopyable, Writable):
    """The index of a link in a project, from 1, as in the EPANET toolkit."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a link.

        Returns:
            Whether the value is 1 or more.
        """
        return self.value >= 1
