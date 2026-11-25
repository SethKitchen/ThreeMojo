# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from tdis.f90 of MODFLOW 6.9.0.dev0, commit 59d89e9f, which is in
# the public domain (CC0). See THIRD-PARTY-NOTICES.md.

"""The stress periods and the time steps of a simulation.

A stress period has a length, a number of steps and a multiplier. Each
step is the multiplier times the step before it, so that the steps fill
the period. The last step ends the period exactly.
"""

from extensions.groundwater.blocks import InputFile, read_int, read_real
from extensions.groundwater.cmath import mul, powi
from extensions.groundwater.constants import DONE, DZERO


struct Tdis(Movable):
    """The time discretization and the current time step."""

    var nper: Int
    """The number of stress periods."""
    var itmuni: Int
    """The time unit: 0 unknown, 1 seconds, 2 minutes, 3 hours, 4 days, 5 years.
    """
    var perlen: List[Float64]
    """The length of each period, from index 1."""
    var nstp: List[Int]
    """The number of steps of each period."""
    var tsmult: List[Float64]
    """The multiplier of each period."""
    var kper: Int
    """The current period."""
    var kstp: Int
    """The current step of the period."""
    var delt: Float64
    """The length of the current step."""
    var totim: Float64
    """The time at the end of the current step."""
    var pertim: Float64
    """The time in the period at the end of the current step."""
    var topertim: Float64
    """The time at the start of the current period."""
    var totimc: Float64
    """The time at the start of the current step."""
    var endofperiod: Bool
    """Whether the current step ends its period."""
    var endofsimulation: Bool
    """Whether the current step ends the simulation."""

    def __init__(out self):
        """Make an empty time discretization of one period of one step."""
        self.nper = 1
        self.itmuni = 0
        self.perlen = [0.0, 1.0]
        self.nstp = [0, 1]
        self.tsmult = [0.0, 1.0]
        self.kper = 0
        self.kstp = 0
        self.delt = DZERO
        self.totim = DZERO
        self.pertim = DZERO
        self.topertim = DZERO
        self.totimc = DZERO
        self.endofperiod = True
        self.endofsimulation = False

    def read(mut self, file: InputFile) raises:
        """Read the options, the dimensions and the periods of a TDIS file.

        Args:
            file: The file.

        Raises:
            Error: A value is missing or out of range.
        """
        var b = file.find("OPTIONS")
        if b >= 0:
            for w in file.blocks[b].data_lines():
                var key = w[0].upper()
                if key == "TIME_UNITS" and len(w) > 1:
                    var u = w[1].upper()
                    if u == "SECONDS":
                        self.itmuni = 1
                    elif u == "MINUTES":
                        self.itmuni = 2
                    elif u == "HOURS":
                        self.itmuni = 3
                    elif u == "DAYS":
                        self.itmuni = 4
                    elif u == "YEARS":
                        self.itmuni = 5
                    else:
                        self.itmuni = 0
        b = file.find("DIMENSIONS")
        if b >= 0:
            for w in file.blocks[b].data_lines():
                if w[0].upper() == "NPER" and len(w) > 1:
                    self.nper = read_int(w[1])
        if self.nper <= 0:
            raise Error("NPER must be greater than 0")
        self.perlen = [0.0]
        self.nstp = [0]
        self.tsmult = [0.0]
        b = file.find("PERIODDATA")
        if b < 0:
            raise Error("TDIS has no PERIODDATA block")
        var lines = file.blocks[b].data_lines()
        if len(lines) < self.nper:
            raise Error("PERIODDATA has fewer lines than NPER")
        for k in range(self.nper):  # pragma: no branch
            var w = lines[k].copy()
            if len(w) < 3:
                raise Error(
                    "each PERIODDATA line needs PERLEN, NSTP and TSMULT"
                )
            var perlen = read_real(w[0])
            var nstp = read_int(w[1])
            var tsmult = read_real(w[2])
            if nstp <= 0:
                raise Error(String("NSTP of period ", k + 1, " must be > 0"))
            if perlen < DZERO:
                raise Error(String("PERLEN of period ", k + 1, " must be >= 0"))
            if tsmult <= DZERO:
                raise Error(String("TSMULT of period ", k + 1, " must be > 0"))
            self.perlen.append(perlen)
            self.nstp.append(nstp)
            self.tsmult.append(tsmult)

    def set_counters(mut self):
        """Move to the next time step, as `tdis_set_counters` does."""
        if self.endofperiod:
            self.kper += 1
            self.kstp = 1
        else:
            self.kstp += 1

    def set_timestep(mut self):
        """Set the length and the end of the current step, as `tdis_set_timestep` does.
        """
        if self.kstp == 1:
            self.pertim = DZERO
            self.topertim = DZERO
        self._set_delt()
        var totimsav = self.totim
        var pertimsav = self.pertim
        self.totimc = totimsav
        self.totim = totimsav + self.delt
        self.pertim = pertimsav + self.delt
        self.endofperiod = self.kstp == self.nstp[self.kper]
        if self.endofperiod:
            self.pertim = self.perlen[self.kper]
        if self.endofperiod and self.kper == self.nper:
            self.endofsimulation = True

    def _set_delt(mut self):
        """Set the length of the current step, as `tdis_set_delt` does."""
        var kper = self.kper
        if self.kstp == 1:
            self.topertim = self.totim
            if self.tsmult[kper] != DONE:
                self.delt = mul(self.perlen[kper], DONE - self.tsmult[kper]) / (
                    DONE - powi(self.tsmult[kper], self.nstp[kper])
                )
            else:
                self.delt = self.perlen[kper] / Float64(self.nstp[kper])
        elif self.kstp == self.nstp[kper]:
            self.delt = self.topertim + self.perlen[kper] - self.totim
        else:
            self.delt = mul(self.tsmult[kper], self.delt)
