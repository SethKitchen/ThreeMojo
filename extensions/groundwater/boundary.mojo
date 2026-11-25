# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from BoundaryPackage.f90, BoundaryPackageExt.f90, gwf-chd.f90,
# gwf-wel.f90, gwf-drn.f90, gwf-riv.f90, gwf-ghb.f90, gwf-rch.f90 and
# gwf-evt.f90 of MODFLOW 6.9.0.dev0, commit 59d89e9f, which is in the
# public domain (CC0). See THIRD-PARTY-NOTICES.md.

"""The boundary packages: constant heads, wells, drains, rivers, general heads, recharge and evapotranspiration.

Each package has a list of bounds. A bound is a cell and its values,
such as the stage, the conductance and the bottom of a river. Each outer
iteration, a bound adds `hcof` to the diagonal of its cell and `rhs` to
the right side. Its flow into the cell is `hcof * h - rhs`.
"""

from extensions.groundwater.blocks import (
    InputFile,
    read_grid_ints,
    read_grid_reals,
    read_int,
    read_real,
)
from extensions.groundwater.cmath import mul
from extensions.groundwater.constants import DONE, DZERO
from extensions.groundwater.dis import Dis
from extensions.groundwater.kinds import (
    BoundaryKind,
    CHD,
    DRN,
    EVT,
    GHB,
    RCH,
    RIV,
    WEL,
)


def boundary_kind(ftype: String) raises -> BoundaryKind:
    """Return the kind of a package from its file type, such as `WEL6`.

    Args:
        ftype: The file type of the name file.

    Returns:
        The kind.

    Raises:
        Error: The file type is not a boundary package.
    """
    var f = ftype.upper()
    if f == "CHD6":
        return CHD
    if f == "WEL6":
        return WEL
    if f == "DRN6":
        return DRN
    if f == "RIV6":
        return RIV
    if f == "GHB6":
        return GHB
    if f == "RCH6":
        return RCH
    if f == "EVT6":
        return EVT
    raise Error(String("not a boundary package: ", ftype))


struct PeriodData(Copyable, Movable):
    """The input of one PERIOD block."""

    var iper: Int
    """The stress period."""
    var cells: List[Int]
    """The user node of each bound, for list input."""
    var values: List[List[Float64]]
    """The values and then the auxiliary values of each bound."""
    var layers: List[Int]
    """The layer of each cell of a layer, from index 1, for array input. Empty if not read.
    """
    var arrays: List[List[Float64]]
    """The arrays of the block, from index 1, by column. An empty array was not read.
    """

    def __init__(out self, iper: Int):
        """Make an empty block.

        Args:
            iper: The stress period.
        """
        self.iper = iper
        self.cells = List[Int]()
        self.values = List[List[Float64]]()
        self.layers = List[Int]()
        self.arrays = List[List[Float64]]()


struct Boundary(Movable):
    """One boundary package and its current bounds."""

    var kind: BoundaryKind
    """The kind of the package."""
    var name: String
    """The name of the package."""
    var ibcnum: Int
    """The number of the package in the model, from 1."""
    var auxnames: List[String]
    """The names of the auxiliary variables."""
    var iauxmultcol: Int
    """The auxiliary variable that multiplies the main value, from 0, or -1."""
    var readasarrays: Bool
    """True if the periods hold arrays of a layer."""
    var fixed_cell: Bool
    """True if recharge or ET stays in its cell when the cell is dry."""
    var surfratespecified: Bool
    """True if the EVT segments give the rate at the surface."""
    var nseg: Int
    """The number of segments of the EVT curve."""
    var maxbound: Int
    """The largest number of bounds in a period."""
    var periods: List[PeriodData]
    """The PERIOD blocks, in the order of the file."""
    var nbound: Int
    """The number of current bounds."""
    var nodelist: List[Int]
    """The reduced node of each bound, from index 1."""
    var nodesontop: List[Int]
    """The node of each bound in the top layer, for RCH and EVT."""
    var bound: List[List[Float64]]
    """The values of each bound, from index 1."""
    var auxvar: List[List[Float64]]
    """The auxiliary values of each bound, from index 1."""
    var hcof: List[Float64]
    """The term on the diagonal of each bound."""
    var rhs: List[Float64]
    """The term on the right side of each bound."""
    var simvals: List[Float64]
    """The flow into the model of each bound."""

    def __init__(out self, kind: BoundaryKind, name: String, ibcnum: Int):
        """Make an empty package.

        Args:
            kind: The kind.
            name: The name.
            ibcnum: The number of the package in the model, from 1.
        """
        self.kind = kind
        self.name = name
        self.ibcnum = ibcnum
        self.auxnames = List[String]()
        self.iauxmultcol = -1
        self.readasarrays = False
        self.fixed_cell = False
        self.surfratespecified = False
        self.nseg = 1
        self.maxbound = 0
        self.periods = List[PeriodData]()
        self.nbound = 0
        self.nodelist = [0]
        self.nodesontop = [0]
        self.bound = [List[Float64]()]
        self.auxvar = [List[Float64]()]
        self.hcof = [0.0]
        self.rhs = [0.0]
        self.simvals = [0.0]

    def nvalues(self) -> Int:
        """Return the number of values of a bound, before the auxiliary values.

        Returns:
            The count.
        """
        if self.kind == DRN or self.kind == GHB:
            return 2
        if self.kind == RIV:
            return 3
        if self.kind == EVT:
            var n = 3 + 2 * (self.nseg - 1)
            if self.surfratespecified:
                n += 1
            return n
        return 1

    def read(mut self, file: InputFile, dis: Dis) raises:
        """Read the options, the dimensions and the periods of a package file.

        Args:
            file: The file.
            dis: The grid.

        Raises:
            Error: An option is not supported, or a record is wrong.
        """
        var auxmultname = String()
        var b = file.find("OPTIONS")
        if b >= 0:
            for w in file.blocks[b].data_lines():
                var key = w[0].upper()
                if key == "AUXILIARY" or key == "AUX":
                    for i in range(1, len(w)):
                        self.auxnames.append(w[i].upper())
                elif key == "AUXMULTNAME" and len(w) > 1:
                    auxmultname = w[1].upper()
                elif key == "READASARRAYS":
                    self.readasarrays = True
                elif key == "FIXED_CELL":
                    self.fixed_cell = True
                elif key == "SURF_RATE_SPECIFIED":
                    self.surfratespecified = True
                elif (
                    key == "TS6"
                    or key == "TAS6"
                    or key == "MOVER"
                    or key == "AUTO_FLOW_REDUCE"
                    or key == "AUXDEPTHNAME"
                ):
                    raise Error(String("the ", key, " option is not supported"))
        if auxmultname.byte_length() > 0:
            for i in range(len(self.auxnames)):
                if self.auxnames[i] == auxmultname:
                    self.iauxmultcol = i
            if self.iauxmultcol < 0:
                raise Error(
                    String(
                        "AUXMULTNAME ", auxmultname, " is not an auxiliary name"
                    )
                )
        b = file.find("DIMENSIONS")
        if b >= 0:
            for w in file.blocks[b].data_lines():
                var key = w[0].upper()
                if key == "MAXBOUND" and len(w) > 1:
                    self.maxbound = read_int(w[1])
                elif key == "NSEG" and len(w) > 1:
                    self.nseg = read_int(w[1])
        if self.readasarrays:
            self.maxbound = dis.nrow * dis.ncol
        if self.maxbound <= 0:
            raise Error("MAXBOUND must be an integer greater than zero.")
        if self.nseg < 1:
            raise Error("NSEG must be an integer greater than zero.")
        if self.surfratespecified and self.nseg < 2:
            raise Error("SURF_RATE_SPECIFIED requires NSEG of 2 or more.")
        var last = 0
        for i in file.find_all("PERIOD"):
            ref pb = file.blocks[i]
            if len(pb.args) < 1:
                raise Error("a PERIOD block needs a period number")
            var iper = read_int(pb.args[0])
            if iper <= last:
                raise Error("the PERIOD blocks must be in increasing order")
            last = iper
            if self.readasarrays:
                self.periods.append(self._read_arrays(file, i, dis, iper))
            else:
                self.periods.append(self._read_list(file, i, dis, iper))

    def _read_list(
        self, file: InputFile, i: Int, dis: Dis, iper: Int
    ) raises -> PeriodData:
        """Read the records of a PERIOD block of list input.

        Args:
            file: The file.
            i: The index of the block.
            dis: The grid.
            iper: The stress period.

        Returns:
            The records.

        Raises:
            Error: A record is short, or names a cell outside the grid.
        """
        var p = PeriodData(iper)
        var nv = self.nvalues() + len(self.auxnames)
        for w in file.blocks[i].data_lines():
            if len(w) < 3 + nv:
                raise Error(
                    String("a ", self.name, " record has too few values")
                )
            var k = read_int(w[0])
            var r = read_int(w[1])
            var c = read_int(w[2])
            if (
                k < 1
                or k > dis.nlay
                or r < 1
                or r > dis.nrow
                or c < 1
                or c > dis.ncol
            ):
                raise Error(
                    String(
                        "Cell (", k, ",", r, ",", c, ") is outside of the grid."
                    )
                )
            p.cells.append(dis.get_node(k, r, c))
            var vals = List[Float64]()
            for j in range(nv):  # pragma: no branch
                vals.append(read_real(w[3 + j]))
            p.values.append(vals^)
        if len(p.cells) > self.maxbound:
            raise Error(
                String(
                    "The number of ",
                    self.name,
                    " bounds is more than MAXBOUND.",
                )
            )
        return p^

    def _read_arrays(
        self, file: InputFile, i: Int, dis: Dis, iper: Int
    ) raises -> PeriodData:
        """Read the arrays of a PERIOD block of array input.

        Args:
            file: The file.
            i: The index of the block.
            dis: The grid.
            iper: The stress period.

        Returns:
            The arrays.

        Raises:
            Error: An array cannot be read.
        """
        var p = PeriodData(iper)
        ref pb = file.blocks[i]
        var ncpl = dis.nrow * dis.ncol
        var lname = "IRCH" if self.kind == RCH else "IEVT"
        p.layers = read_grid_ints(file, pb, lname, 1, ncpl)
        var names = List[String]()
        if self.kind == RCH:
            names.append("RECHARGE")
        else:
            names.append("SURFACE")
            names.append("RATE")
            names.append("DEPTH")
        for n in self.auxnames:
            names.append(n)
        for n in names:  # pragma: no branch
            p.arrays.append(read_grid_reals(file, pb, n, 1, ncpl))
        return p^

    def _resize(mut self, n: Int):
        """Set the number of current bounds and size the arrays.

        Args:
            n: The number of bounds.
        """
        self.nbound = n
        var nv = self.nvalues()
        var na = len(self.auxnames)
        while len(self.nodelist) < n + 1:
            self.nodelist.append(0)
            self.nodesontop.append(0)
            self.bound.append(List[Float64](length=nv, fill=0.0))
            self.auxvar.append(List[Float64](length=na, fill=0.0))
            self.hcof.append(0.0)
            self.rhs.append(0.0)
            self.simvals.append(0.0)

    def default_nodelist(mut self, dis: Dis):
        """Put the bounds of array input in the top layer, as `default_nodelist` does.

        The values start at zero, as `allocate_dbl1d` sets them. The
        defaults in the input definitions are documentation only.

        Args:
            dis: The grid.
        """
        if not self.readasarrays:
            return
        var ncpl = dis.nrow * dis.ncol
        self._resize(ncpl)
        var ipos = 1
        for r in range(1, dis.nrow + 1):  # pragma: no branch
            for c in range(1, dis.ncol + 1):  # pragma: no branch
                self.nodelist[ipos] = dis.reduced(dis.get_node(1, r, c))
                ipos += 1
        if not self.fixed_cell:
            for n in range(1, self.nbound + 1):  # pragma: no branch
                self.nodesontop[n] = self.nodelist[n]

    def rp(mut self, kper: Int, dis: Dis, mut ibound: List[Int]) raises:
        """Read the bounds of a period, as `bnd_rp` and `chd_rp` do.

        Args:
            kper: The stress period.
            dis: The grid.
            ibound: The status of each cell. A constant head cell is
                negative.

        Raises:
            Error: A cell is outside the active grid, or has two constant
                heads.
        """
        var at = -1
        for i in range(len(self.periods)):
            if self.periods[i].iper == kper:
                at = i
        if at < 0:
            return
        if self.kind == CHD:
            for i in range(1, self.nbound + 1):
                ibound[self.nodelist[i]] = self.ibcnum
        var p = self.periods[at].copy()
        if self.readasarrays:
            var ncpl = dis.nrow * dis.ncol
            if len(p.layers) > 0:
                var ipos = 1
                for r in range(1, dis.nrow + 1):  # pragma: no branch
                    for c in range(1, dis.ncol + 1):  # pragma: no branch
                        var il = p.layers[(r - 1) * dis.ncol + c]
                        if il < 1 or il > dis.nlay:
                            raise Error(String("Invalid layer number: ", il))
                        self.nodelist[ipos] = dis.reduced(
                            dis.get_node(il, r, c)
                        )
                        ipos += 1
            var nv = self.nvalues()
            for j in range(len(p.arrays)):  # pragma: no branch
                if len(p.arrays[j]) == 0:
                    continue
                for n in range(1, ncpl + 1):  # pragma: no branch
                    if j < nv:
                        self.bound[n][j] = p.arrays[j][n]
                    else:
                        self.auxvar[n][j - nv] = p.arrays[j][n]
        else:
            var nlist = len(p.cells)
            self._resize(nlist)
            var nv = self.nvalues()
            for i in range(nlist):
                var noder = dis.reduced(p.cells[i])
                if noder <= 0:
                    raise Error(
                        String(
                            "Cell is outside active grid domain: user node ",
                            p.cells[i],
                        )
                    )
                self.nodelist[i + 1] = noder
                for j in range(nv):  # pragma: no branch
                    self.bound[i + 1][j] = p.values[i][j]
                for j in range(len(self.auxnames)):
                    self.auxvar[i + 1][j] = p.values[i][nv + j]
        if (self.kind == RCH or self.kind == EVT) and not self.fixed_cell:
            for n in range(1, self.nbound + 1):
                self.nodesontop[n] = self.nodelist[n]
        if self.kind == CHD:
            for i in range(1, self.nbound + 1):
                var node = self.nodelist[i]
                if ibound[node] < 0:
                    raise Error(
                        String(
                            "Cell ",
                            node,
                            (
                                " is already a constant head cell of another"
                                " package"
                            ),
                        )
                    )
                ibound[node] = -self.ibcnum

    def _mult(self, i: Int, v: Float64) -> Float64:
        """Return a value times the auxiliary multiplier of its bound.

        Args:
            i: The bound.
            v: The value.

        Returns:
            The product, or the value if the package has no multiplier.
        """
        if self.iauxmultcol >= 0:
            return mul(v, self.auxvar[i][self.iauxmultcol])
        return v

    def ad(
        self,
        dis: Dis,
        icelltype: List[Int],
        mut xnew: List[Float64],
        mut xold: List[Float64],
    ) raises:
        """Set the heads of the constant head cells, as `chd_ad` and `chd_ck` do.

        Args:
            dis: The grid.
            icelltype: The cell types of NPF.
            xnew: The heads.
            xold: The heads at the start of the step.

        Raises:
            Error: A constant head is under the bottom of a convertible cell.
        """
        if self.kind != CHD:
            return
        for i in range(1, self.nbound + 1):
            var node = self.nodelist[i]
            var hb = self._mult(i, self.bound[i][0])
            xnew[node] = hb
            xold[node] = xnew[node]
        for i in range(1, self.nbound + 1):
            var node = self.nodelist[i]
            if (
                self._mult(i, self.bound[i][0]) < dis.bot[node]
                and icelltype[node] != 0
            ):
                raise Error(
                    String(
                        "CHD BOUNDARY ",
                        i,
                        " HEAD IS LESS THAN CELL BOTTOM",
                    )
                )

    def cf(mut self, dis: Dis, ibound: List[Int], xnew: List[Float64]):
        """Set `hcof` and `rhs` of each bound at the current heads.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            xnew: The heads.
        """
        if self.nbound == 0 or self.kind == CHD:
            return
        if self.kind == RCH or self.kind == EVT:
            self._cf_top(dis, ibound, xnew)
            return
        for i in range(1, self.nbound + 1):  # pragma: no branch
            var node = self.nodelist[i]
            if ibound[node] <= 0:
                self.hcof[i] = DZERO
                self.rhs[i] = DZERO
                continue
            if self.kind == WEL:
                self.hcof[i] = DZERO
                self.rhs[i] = -self._mult(i, self.bound[i][0])
            elif self.kind == DRN:
                var cdrn = self._mult(i, self.bound[i][1])
                var drnbot = self.bound[i][0]
                var fact = DONE
                if xnew[node] <= drnbot:
                    fact = DZERO
                self.rhs[i] = mul(mul(-fact, cdrn), drnbot)
                self.hcof[i] = mul(-fact, cdrn)
            elif self.kind == RIV:
                var hriv = self.bound[i][0]
                var criv = self._mult(i, self.bound[i][1])
                var rbot = self.bound[i][2]
                if xnew[node] <= rbot:
                    self.rhs[i] = mul(-criv, hriv - rbot)
                    self.hcof[i] = DZERO
                else:
                    self.rhs[i] = mul(-criv, hriv)
                    self.hcof[i] = -criv
            else:
                var c = self._mult(i, self.bound[i][1])
                self.hcof[i] = -c
                self.rhs[i] = mul(-c, self.bound[i][0])

    def _highest_active(self, dis: Dis, n0: Int, ibound: List[Int]) -> Int:
        """Return the first cell under a cell that is not inactive, as `highest_active` does.

        Args:
            dis: The grid.
            n0: The cell.
            ibound: The status of each cell.

        Returns:
            The cell, or the bottom cell of the column.
        """
        var n = n0
        while True:
            var bottomcell = True
            var done = False
            for ii in range(dis.con.ia[n] + 1, dis.con.ia[n + 1]):
                var m = dis.con.ja[ii]
                var iis = dis.con.jas[ii]
                if dis.con.ihc[iis] == 0 and m > n:
                    bottomcell = False
                    n = m
                    if ibound[m] != 0:
                        done = True
                    break
            if bottomcell or done:
                return n

    def _cf_top(mut self, dis: Dis, ibound: List[Int], xnew: List[Float64]):
        """Set `hcof` and `rhs` of recharge and ET, as `rch_cf` and `evt_cf` do.

        MODFLOW 6 also gives no recharge or ET to a cell under a dry lake.
        The port has no lake package, so it has no such cell.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            xnew: The heads.
        """
        for i in range(1, self.nbound + 1):  # pragma: no branch
            var node: Int
            if self.fixed_cell:
                node = self.nodelist[i]
            else:
                node = self.nodesontop[i]
            if node <= 0:
                self.hcof[i] = DZERO
                self.rhs[i] = DZERO
                continue
            if not self.fixed_cell:
                if ibound[node] == 0:
                    node = self._highest_active(dis, node, ibound)
                self.nodelist[i] = node
            if self.kind == RCH:
                self.hcof[i] = DZERO
                if self.iauxmultcol >= 0:
                    self.rhs[i] = mul(
                        mul(-self.bound[i][0], dis.area[node]),
                        self.auxvar[i][self.iauxmultcol],
                    )
                else:
                    self.rhs[i] = mul(-self.bound[i][0], dis.area[node])
                if ibound[node] <= 0:
                    self.rhs[i] = DZERO
                continue
            self.rhs[i] = DZERO
            self.hcof[i] = DZERO
            if ibound[node] <= 0:
                continue
            var c: Float64
            if self.iauxmultcol >= 0:
                c = mul(
                    mul(self.bound[i][1], dis.area[node]),
                    self.auxvar[i][self.iauxmultcol],
                )
            else:
                c = mul(self.bound[i][1], dis.area[node])
            var s = self.bound[i][0]
            var h = xnew[node]
            var x = self.bound[i][2]
            var npx = self.nseg - 1
            var petm0 = DZERO
            if self.surfratespecified:
                petm0 = self.bound[i][3 + 2 * npx]
            if h >= s:
                if self.surfratespecified:
                    self.rhs[i] = self.rhs[i] + mul(petm0, c)
                else:
                    self.rhs[i] = self.rhs[i] + c
            else:
                var d = s - h
                if d < x:
                    var trhs: Float64
                    var thcof: Float64
                    if self.nseg > 1:
                        var pxdp1 = DZERO
                        var petm1 = DONE
                        if self.surfratespecified:
                            petm1 = petm0
                        var pxdp2 = DZERO
                        var petm2 = DZERO
                        for iseg in range(
                            1, self.nseg + 1
                        ):  # pragma: no branch
                            if iseg < self.nseg:
                                pxdp2 = self.bound[i][3 + iseg - 1]
                                petm2 = self.bound[i][3 + npx + iseg - 1]
                            else:
                                pxdp2 = DONE
                                petm2 = DZERO
                            if d <= mul(pxdp2, x):
                                break
                            pxdp1 = pxdp2
                            petm1 = petm2
                        thcof = -mul(petm1 - petm2, c) / mul(pxdp2 - pxdp1, x)
                        trhs = mul(thcof, s - mul(pxdp1, x)) + mul(petm1, c)
                    else:
                        trhs = c - mul(c, s) / x
                        thcof = -c / x
                    self.rhs[i] = self.rhs[i] + trhs
                    self.hcof[i] = self.hcof[i] + thcof

    def fc(
        mut self,
        dis: Dis,
        ibound: List[Int],
        mut amat: List[Float64],
        mut rhs: List[Float64],
    ):
        """Add the terms of each bound to the matrix, as `bnd_fc` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            amat: The matrix, by position.
            rhs: The right side.
        """
        if self.kind == CHD:
            return
        for i in range(1, self.nbound + 1):
            var n = self.nodelist[i]
            if n <= 0:
                continue
            rhs[n] = rhs[n] + self.rhs[i]
            var ipos = dis.con.ia[n]
            amat[ipos] = amat[ipos] + self.hcof[i]

    def cq(
        mut self,
        dis: Dis,
        ibound: List[Int],
        hnew: List[Float64],
        mut flowja: List[Float64],
    ):
        """Set the flow of each bound and add it to the diagonal flows, as `bnd_cq_simrate` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            hnew: The heads.
            flowja: The flows, by position.
        """
        if self.kind == CHD:
            return
        for i in range(1, self.nbound + 1):
            var node = self.nodelist[i]
            var rrate = DZERO
            if node > 0:
                var idiag = dis.con.ia[node]
                if ibound[node] > 0:
                    rrate = mul(self.hcof[i], hnew[node]) - self.rhs[i]
                flowja[idiag] = flowja[idiag] + rrate
            self.simvals[i] = rrate

    def chd_rate(
        mut self, dis: Dis, ibound: List[Int], mut flowja: List[Float64]
    ):
        """Set the flow of each constant head from the flows of its faces, as `calc_chd_rate` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            flowja: The flows, by position.
        """
        if self.kind != CHD:
            return
        for i in range(1, self.nbound + 1):
            var node = self.nodelist[i]
            var idiag = dis.con.ia[node]
            var rate = DZERO
            for ipos in range(dis.con.ia[node] + 1, dis.con.ia[node + 1]):
                rate = rate - flowja[ipos]
            self.rhs[i] = -rate
            self.hcof[i] = DZERO
            self.simvals[i] = rate
            flowja[idiag] = flowja[idiag] + rate
