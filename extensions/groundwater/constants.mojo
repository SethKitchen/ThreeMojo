# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from Constants.f90 of MODFLOW 6.9.0.dev0, commit 59d89e9f, which
# is in the public domain (CC0). See THIRD-PARTY-NOTICES.md.

"""The real constants of MODFLOW 6 that the groundwater port uses."""

# Each constant is a Float64, not a float literal. Mojo folds literal
# arithmetic exactly, so `DONE - DP9` of two literals would be 0.1, while
# Fortran rounds 1 - 0.9 in double precision to 0.09999999999999998.

comptime DZERO: Float64 = 0.0
comptime DQUARTER: Float64 = 0.25
comptime DHALF: Float64 = 0.5
comptime DP6: Float64 = 0.6
comptime DP7: Float64 = 0.7
comptime DP9: Float64 = 0.9
comptime DP99: Float64 = 0.99
comptime DP999: Float64 = 0.999
comptime DONE: Float64 = 1.0
comptime DTWO: Float64 = 2.0
comptime DTHREE: Float64 = 3.0
comptime DFOUR: Float64 = 4.0
comptime DTEN: Float64 = 10.0
comptime DHUNDRED: Float64 = 100.0
comptime DEP3: Float64 = 1.0e3
comptime DEP20: Float64 = 1.0e20
comptime DHNOFLO: Float64 = 1.0e30
comptime DHDRY: Float64 = -1.0e30
comptime DEM1: Float64 = 1.0e-1
comptime DEM2: Float64 = 1.0e-2
comptime DEM3: Float64 = 1.0e-3
comptime DEM4: Float64 = 1.0e-4
comptime DEM5: Float64 = 1.0e-5
comptime DEM6: Float64 = 1.0e-6
comptime DEM7: Float64 = 1.0e-7
comptime DEM8: Float64 = 1.0e-8
comptime DEM10: Float64 = 1.0e-10
comptime DEM15: Float64 = 1.0e-15
comptime DEM20: Float64 = 1.0e-20
comptime DEM30: Float64 = 1.0e-30
# EPSILON(1.0_DP) of Fortran: 2 to the power -52.
comptime DPREC: Float64 = 2.220446049250313e-16
# DHUNDRED * DPREC.
comptime DSAME: Float64 = 2.220446049250313e-14
comptime DLNLOW: Float64 = 0.995
comptime DLNHIGH: Float64 = 1.005
# DFOUR * ATAN(DONE), rounded as Fortran rounds it.
comptime DPI: Float64 = 3.141592653589793
# The seconds in a minute, an hour, a day and a year, as TDIS uses them.
comptime DSECPERHR: Float64 = 3.6e3
comptime DHRPERDAY: Float64 = 2.4e1
comptime DDYPERYR: Float64 = 3.6525e2
comptime DSECPERDY: Float64 = 8.64e4
comptime DSECPERYR: Float64 = 3.1557600e7
comptime DSIXTY: Float64 = 6.0e1
comptime DONETHIRD: Float64 = 1.0 / 3.0
# The value of atan(1) / 45 that gfortran computes: pi / 180.
comptime DPIO180: Float64 = 0.017453292519943295
