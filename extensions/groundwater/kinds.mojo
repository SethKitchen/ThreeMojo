# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# The numbers follow the integer flags of MODFLOW 6.9.0.dev0, commit
# 59d89e9f, which is in the public domain (CC0). See THIRD-PARTY-NOTICES.md.

"""The kinds of the MODFLOW 6 port: boundaries, solver methods and options.

Each option that MODFLOW 6 stores as an integer flag is a type here. A
value keeps the number of the flag, so that the code compares the same
numbers as the Fortran code.
"""

from core.ordinal import ordinal_valid


@fieldwise_init
struct BoundaryKind(Equatable, ImplicitlyCopyable, Writable):
    """The kind of a boundary package."""

    var value: Int
    """The number of the kind: see the constants below."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the seven kinds.

        Returns:
            Whether the value is 0 to 6.
        """
        return ordinal_valid(self.value, 6)


# A constant head (CHD6).
comptime CHD = BoundaryKind(0)
# A well (WEL6).
comptime WEL = BoundaryKind(1)
# A drain (DRN6).
comptime DRN = BoundaryKind(2)
# A river (RIV6).
comptime RIV = BoundaryKind(3)
# A general head boundary (GHB6).
comptime GHB = BoundaryKind(4)
# Recharge (RCH6), from a list or from arrays.
comptime RCH = BoundaryKind(5)
# Evapotranspiration (EVT6), from a list or from arrays.
comptime EVT = BoundaryKind(6)


@fieldwise_init
struct UnderRelaxation(Equatable, ImplicitlyCopyable, Writable):
    """The under-relaxation of the outer iterations: `nonmeth` of IMS."""

    var value: Int
    """0 none, 1 simple, 2 Cooley, 3 delta-bar-delta."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the four methods.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 3)


comptime UNDER_RELAXATION_NONE = UnderRelaxation(0)
comptime UNDER_RELAXATION_SIMPLE = UnderRelaxation(1)
comptime UNDER_RELAXATION_COOLEY = UnderRelaxation(2)
comptime UNDER_RELAXATION_DBD = UnderRelaxation(3)


@fieldwise_init
struct LinearAcceleration(Equatable, ImplicitlyCopyable, Writable):
    """The Krylov method of the inner iterations: `ilinmeth` of IMS."""

    var value: Int
    """1 conjugate gradient, 2 BiCGSTAB."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the two methods.

        Returns:
            Whether the value is 1 or 2.
        """
        return self.value == 1 or self.value == 2


comptime CG = LinearAcceleration(1)
comptime BICGSTAB = LinearAcceleration(2)


@fieldwise_init
struct Preconditioner(Equatable, ImplicitlyCopyable, Writable):
    """The preconditioner of the inner iterations: `ipc` of IMS."""

    var value: Int
    """1 ILU0, 2 MILU0, 3 ILUT, 4 MILUT."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the four preconditioners.

        Returns:
            Whether the value is 1 to 4.
        """
        return self.value >= 1 and self.value <= 4


comptime IPC_ILU0 = Preconditioner(1)
comptime IPC_MILU0 = Preconditioner(2)
comptime IPC_ILUT = Preconditioner(3)
comptime IPC_MILUT = Preconditioner(4)


@fieldwise_init
struct Scaling(Equatable, ImplicitlyCopyable, Writable):
    """The scaling of the matrix before the inner iterations: `iscl` of IMS."""

    var value: Int
    """0 none, 1 diagonal, 2 L2 norm."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the three scalings.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 2)


comptime SCALING_NONE = Scaling(0)
comptime SCALING_DIAGONAL = Scaling(1)
comptime SCALING_L2NORM = Scaling(2)


@fieldwise_init
struct Reordering(Equatable, ImplicitlyCopyable, Writable):
    """The reordering of the matrix before the inner iterations: `iord` of IMS.
    """

    var value: Int
    """0 none, 1 reverse Cuthill-McKee, 2 minimum degree."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the three orderings.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 2)


comptime REORDERING_NONE = Reordering(0)
comptime REORDERING_RCM = Reordering(1)
comptime REORDERING_MD = Reordering(2)


@fieldwise_init
struct InnerConvergence(Equatable, ImplicitlyCopyable, Writable):
    """How the inner iterations test the residual: `icnvgopt` of IMS."""

    var value: Int
    """0 infinity norm, 1 strict, 2 L2 norm, 3 relative, 4 relative L2 norm."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the five tests.

        Returns:
            Whether the value is 0 to 4.
        """
        return ordinal_valid(self.value, 4)


comptime RCLOSE_INFINITY_NORM = InnerConvergence(0)
comptime RCLOSE_STRICT = InnerConvergence(1)
comptime RCLOSE_L2NORM = InnerConvergence(2)
comptime RCLOSE_RELATIVE = InnerConvergence(3)
comptime RCLOSE_L2NORM_RELATIVE = InnerConvergence(4)


@fieldwise_init
struct CellAveraging(Equatable, ImplicitlyCopyable, Writable):
    """The mean of two conductivities across a face: `icellavg` of NPF."""

    var value: Int
    """0 harmonic, 1 logarithmic, 2 arithmetic thickness and log K, 3 arithmetic thickness and harmonic K.
    """

    def is_valid(self) -> Bool:
        """Return True if this names one of the four means.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 3)


comptime CELLAVG_HARMONIC = CellAveraging(0)
comptime CELLAVG_LOGARITHMIC = CellAveraging(1)
comptime CELLAVG_AMT_LMK = CellAveraging(2)
comptime CELLAVG_AMT_HMK = CellAveraging(3)
