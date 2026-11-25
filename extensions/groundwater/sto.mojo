# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from gwf-sto.f90 of MODFLOW 6.9.0.dev0, commit 59d89e9f, which is
# in the public domain (CC0). See THIRD-PARTY-NOTICES.md.

"""The storage package: the water that a cell gains or loses as its head changes.

A cell stores water by compression, through its specific storage, and,
when it can convert, by draining or filling its pores, through its
specific yield. A steady-state period has no storage.
"""

from extensions.groundwater.blocks import (
    InputFile,
    read_grid_ints,
    read_grid_reals,
    read_int,
)
from extensions.groundwater.cmath import mul
from extensions.groundwater.constants import DEM6, DONE, DZERO
from extensions.groundwater.dis import Dis
from extensions.groundwater.smoothing import (
    squadratic_saturation,
    squadratic_saturation_derivative,
)
from extensions.groundwater.storageutils import (
    ss_capacity,
    ss_terms,
    sy_capacity,
    sy_terms,
)


struct Sto(Movable):
    """The storage properties and the storage flows of STO6."""

    var iconvert: List[Int]
    """1 for a cell that can convert, by reduced node."""
    var ss: List[Float64]
    """The specific storage, or the storage coefficient."""
    var sy: List[Float64]
    """The specific yield."""
    var strgss: List[Float64]
    """The flow from specific storage, by cell."""
    var strgsy: List[Float64]
    """The flow from specific yield, by cell."""
    var istor_coef: Int
    """1 if `ss` holds storage coefficients."""
    var iconf_ss: Int
    """1 if SS_CONFINED_ONLY is on."""
    var iorig_ss: Int
    """1 for the storage formulation of MODFLOW 2005."""
    var inewton: Int
    """1 for the Newton-Raphson formulation."""
    var satomega: Float64
    """The smoothing of the saturation."""
    var periods: List[Int]
    """The stress period of each PERIOD block."""
    var states: List[Int]
    """1 if the PERIOD block of the same index is steady state, else 0."""

    def __init__(out self):
        """Make the package with the defaults of `allocate_scalars`."""
        self.iconvert = List[Int]()
        self.ss = List[Float64]()
        self.sy = List[Float64]()
        self.strgss = List[Float64]()
        self.strgsy = List[Float64]()
        self.istor_coef = 0
        self.iconf_ss = 0
        self.iorig_ss = 0
        self.inewton = 0
        self.satomega = DZERO
        self.periods = List[Int]()
        self.states = List[Int]()

    def read(mut self, file: InputFile, dis: Dis, inewton: Int) raises:
        """Read an STO6 file, as `source_options` and `source_data` do.

        Args:
            file: The file.
            dis: The grid.
            inewton: 1 if the model uses the Newton-Raphson formulation.

        Raises:
            Error: An array is missing or negative.
        """
        self.inewton = inewton
        var b = file.find("OPTIONS")
        if b >= 0:
            for w in file.blocks[b].data_lines():
                var key = w[0].upper()
                if key == "STORAGECOEFFICIENT":
                    self.istor_coef = 1
                elif key == "SS_CONFINED_ONLY":
                    self.iconf_ss = 1
                elif key == "DEV_ORIGINAL_SPECIFIC_STORAGE":
                    self.iorig_ss = 1
                elif key == "DEV_OLDSTORAGEFORMULATION":
                    self.iconf_ss = 1
        if self.iconf_ss != 0:
            self.iorig_ss = 0
        if self.inewton > 0:
            self.satomega = DEM6
        b = file.find("GRIDDATA")
        if b < 0:
            raise Error("STO has no GRIDDATA block")
        ref g = file.blocks[b]
        var ncpl = dis.nrow * dis.ncol
        var ic = read_grid_ints(file, g, "ICONVERT", dis.nlay, ncpl)
        var ss = read_grid_reals(file, g, "SS", dis.nlay, ncpl)
        var sy = read_grid_reals(file, g, "SY", dis.nlay, ncpl)
        if len(ic) == 0:
            raise Error("Error in GRIDDATA block: ICONVERT not found.")
        if len(ss) == 0:
            raise Error("Error in GRIDDATA block: SS not found.")
        var nodes = dis.nodes
        self.iconvert = List[Int](length=nodes + 1, fill=0)
        self.ss = List[Float64](length=nodes + 1, fill=0.0)
        self.sy = List[Float64](length=nodes + 1, fill=0.0)
        self.strgss = List[Float64](length=nodes + 1, fill=0.0)
        self.strgsy = List[Float64](length=nodes + 1, fill=0.0)
        var isconv = False
        for n in range(1, nodes + 1):  # pragma: no branch
            var u = dis.user(n)
            self.iconvert[n] = ic[u]
            if ic[u] != 0:
                isconv = True
            self.ss[n] = ss[u]
            if len(sy) > 0:
                self.sy[n] = sy[u]
        if len(sy) == 0 and isconv:
            raise Error("Error in GRIDDATA block: SY not found.")
        for n in range(1, nodes + 1):  # pragma: no branch
            if self.ss[n] < DZERO:
                raise Error(String("SS of cell ", n, " is less than zero"))
            if isconv and self.sy[n] < DZERO:
                raise Error(String("SY of cell ", n, " is less than zero"))
        for i in file.find_all("PERIOD"):
            ref pb = file.blocks[i]
            if len(pb.args) < 1:
                raise Error("a STO PERIOD block needs a period number")
            var iper = read_int(pb.args[0])
            var state = -1
            for w in pb.data_lines():
                var key = w[0].upper()
                if key == "STEADY-STATE":
                    state = 1
                elif key == "TRANSIENT":
                    state = 0
                else:
                    raise Error(String("Unknown STO PERIOD keyword ", key))
            if state < 0:
                continue
            self.periods.append(iper)
            self.states.append(state)

    def rp(self, kper: Int, mut iss: Int):
        """Set steady state or transient for a period, as `sto_rp` does.

        Args:
            kper: The stress period.
            iss: Receives 1 for steady state, 0 for transient.
        """
        for i in range(len(self.periods)):
            if self.periods[i] == kper:
                iss = self.states[i]

    def _sat(self, dis: Dis, n: Int, h: Float64) -> Float64:
        """Return the smoothed saturation of a cell that can convert.

        Args:
            dis: The grid.
            n: The cell.
            h: The head.

        Returns:
            The saturation.
        """
        return squadratic_saturation(dis.top[n], dis.bot[n], h, self.satomega)

    def fc(
        self,
        dis: Dis,
        ibound: List[Int],
        delt: Float64,
        hold: List[Float64],
        hnew: List[Float64],
        mut amat: List[Float64],
        mut rhs: List[Float64],
    ):
        """Add the storage terms to the matrix, as `fc_default_sto` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            delt: The length of the time step.
            hold: The heads at the start of the step.
            hnew: The heads.
            amat: The matrix, by position.
            rhs: The right side.
        """
        var tled = DONE / delt
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            if ibound[n] < 1:
                continue
            var idiag = dis.con.ia[n]
            var tp = dis.top[n]
            var bt = dis.bot[n]
            var snold = DONE
            var snnew = DONE
            if self.iconvert[n] != 0:
                snold = self._sat(dis, n, hold[n])
                snnew = self._sat(dis, n, hnew[n])
            var sc1 = ss_capacity(
                self.istor_coef, tp, bt, dis.area[n], self.ss[n]
            )
            var rho1 = mul(sc1, tled)
            var t = ss_terms(
                self.iconvert[n],
                self.iorig_ss,
                self.iconf_ss,
                tp,
                bt,
                rho1,
                rho1,
                snnew,
                snold,
                hnew[n],
                hold[n],
            )
            amat[idiag] = amat[idiag] + t.aterm
            rhs[n] = rhs[n] + t.rhsterm
            if self.iconvert[n] != 0:
                var sc2 = sy_capacity(dis.area[n], self.sy[n])
                var rho2 = mul(sc2, tled)
                var y = sy_terms(tp, bt, rho2, rho2, snnew, snold)
                amat[idiag] = amat[idiag] + y.aterm
                rhs[n] = rhs[n] + y.rhsterm

    def fn(
        self,
        dis: Dis,
        ibound: List[Int],
        delt: Float64,
        hnew: List[Float64],
        mut amat: List[Float64],
        mut rhs: List[Float64],
    ):
        """Add the Newton-Raphson terms of storage, as `fn_default_sto` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            delt: The length of the time step.
            hnew: The heads.
            amat: The matrix, by position.
            rhs: The right side.
        """
        var tled = DONE / delt
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            if ibound[n] <= 0:
                continue
            var idiag = dis.con.ia[n]
            var tp = dis.top[n]
            var bt = dis.bot[n]
            var tthk = tp - bt
            var h = hnew[n]
            var snnew = squadratic_saturation(tp, bt, h)
            var sc1 = ss_capacity(
                self.istor_coef, tp, bt, dis.area[n], self.ss[n]
            )
            var sc2 = sy_capacity(dis.area[n], self.sy[n])
            var rho1 = mul(sc1, tled)
            var rho2 = mul(sc2, tled)
            if self.iconvert[n] != 0:
                var derv = squadratic_saturation_derivative(tp, bt, h)
                if self.iconf_ss == 0:
                    var drterm: Float64
                    if self.iorig_ss == 0:
                        drterm = mul(mul(-rho1, derv), h - bt) + mul(
                            mul(mul(rho1, tthk), snnew), derv
                        )
                    else:
                        drterm = -mul(mul(rho1, derv), h)
                    amat[idiag] = amat[idiag] + drterm
                    rhs[n] = rhs[n] + mul(drterm, h)
                if snnew < DONE:
                    if snnew > DZERO:
                        var rterm = mul(mul(-rho2, tthk), snnew)
                        var drterm = mul(mul(-rho2, tthk), derv)
                        amat[idiag] = amat[idiag] + (drterm + rho2)
                        rhs[n] = rhs[n] - rterm + mul(drterm, h) + mul(rho2, bt)

    def cq(
        mut self,
        dis: Dis,
        ibound: List[Int],
        iss: Int,
        delt: Float64,
        hold: List[Float64],
        hnew: List[Float64],
        mut flowja: List[Float64],
    ):
        """Set the storage flows and add them to the diagonal flows, as `cq_default_sto` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            iss: 1 for a steady-state period.
            delt: The length of the time step.
            hold: The heads at the start of the step.
            hnew: The heads.
            flowja: The flows, by position.
        """
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            self.strgss[n] = DZERO
            self.strgsy[n] = DZERO
        if iss == 1:
            return
        var tled = DONE / delt
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            if ibound[n] <= 0:
                continue
            var tp = dis.top[n]
            var bt = dis.bot[n]
            var snold = DONE
            var snnew = DONE
            if self.iconvert[n] != 0:
                snold = self._sat(dis, n, hold[n])
                snnew = self._sat(dis, n, hnew[n])
            var sc1 = ss_capacity(
                self.istor_coef, tp, bt, dis.area[n], self.ss[n]
            )
            var rho1 = mul(sc1, tled)
            var t = ss_terms(
                self.iconvert[n],
                self.iorig_ss,
                self.iconf_ss,
                tp,
                bt,
                rho1,
                rho1,
                snnew,
                snold,
                hnew[n],
                hold[n],
            )
            self.strgss[n] = t.rate
            var idiag = dis.con.ia[n]
            flowja[idiag] = flowja[idiag] + t.rate
            var rate = DZERO
            if self.iconvert[n] != 0:
                var sc2 = sy_capacity(dis.area[n], self.sy[n])
                var rho2 = mul(sc2, tled)
                rate = sy_terms(tp, bt, rho2, rho2, snnew, snold).rate
            self.strgsy[n] = rate
            flowja[idiag] = flowja[idiag] + rate
