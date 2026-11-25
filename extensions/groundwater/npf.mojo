# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from gwf-npf.f90 and HGeoUtil.f90 of MODFLOW 6.9.0.dev0, commit
# 59d89e9f, which is in the public domain (CC0). See THIRD-PARTY-NOTICES.md.

"""The node property flow package: the conductance between cells.

`Npf` holds the hydraulic conductivity of each cell and the saturated
conductance of each connection. Each outer iteration, it sets the
saturation of the convertible cells and adds the conductance terms to
the matrix. With the Newton-Raphson formulation, it also adds the
derivative terms. After the solve, it computes the flow across each
connection.
"""

from std.math import cos, sin

from extensions.groundwater.blocks import (
    InputFile,
    read_grid_ints,
    read_grid_reals,
    read_int,
    read_real,
)
from extensions.groundwater.cmath import mul
from extensions.groundwater.conductance import CCOND_HMEAN, hcond, vcond
from extensions.groundwater.constants import (
    DEM6,
    DHDRY,
    DHNOFLO,
    DONE,
    DP9,
    DPIO180,
    DZERO,
)
from extensions.groundwater.dis import C3D_VERTICAL, Dis
from extensions.groundwater.kinds import CellAveraging
from extensions.groundwater.smoothing import (
    squadratic_saturation,
    squadratic_saturation_derivative,
)


def hyeff(
    k11: Float64,
    k22: Float64,
    k33: Float64,
    ang1: Float64,
    ang2: Float64,
    ang3: Float64,
    vg1: Float64,
    vg2: Float64,
    vg3: Float64,
    iavgmeth: Int,
) -> Float64:
    """Return the conductivity in a direction, from the principal conductivities.

    Args:
        k11: The conductivity along the first principal axis.
        k22: The conductivity along the second principal axis.
        k33: The conductivity along the third principal axis.
        ang1: The first rotation angle, in radians.
        ang2: The second rotation angle, in radians.
        ang3: The third rotation angle, in radians.
        vg1: The x component of the unit direction.
        vg2: The y component of the unit direction.
        vg3: The z component of the unit direction.
        iavgmeth: 0 for the harmonic form, 1 for the arithmetic form.

    Returns:
        The conductivity in the direction.
    """
    var s1 = sin(ang1)
    var c1 = cos(ang1)
    var s2 = sin(ang2)
    var c2 = cos(ang2)
    var s3 = sin(ang3)
    var c3 = cos(ang3)
    var r11 = mul(c1, c2)
    var r12 = mul(mul(c1, s2), s3) - mul(s1, c3)
    var r13 = mul(mul(-c1, s2), c3) - mul(s1, s3)
    var r21 = mul(s1, c2)
    var r22 = mul(mul(s1, s2), s3) + mul(c1, c3)
    var r23 = mul(mul(-s1, s2), c3) + mul(c1, s3)
    var r31 = s2
    var r32 = mul(-c2, s3)
    var r33 = mul(c2, c3)
    var ve1 = mul(r11, vg1) + mul(r21, vg2) + mul(r31, vg3)
    var ve2 = mul(r12, vg1) + mul(r22, vg2) + mul(r32, vg3)
    var ve3 = mul(r13, vg1) + mul(r23, vg2) + mul(r33, vg3)
    var k = DZERO
    if iavgmeth == 0:
        var dnum = DONE
        var d1 = mul(ve1, ve1)
        var d2 = mul(ve2, ve2)
        var d3 = mul(ve3, ve3)
        if ve1 != DZERO:
            dnum = mul(dnum, k11)
            d2 = mul(d2, k11)
            d3 = mul(d3, k11)
        if ve2 != DZERO:
            dnum = mul(dnum, k22)
            d1 = mul(d1, k22)
            d3 = mul(d3, k22)
        if ve3 != DZERO:
            dnum = mul(dnum, k33)
            d1 = mul(d1, k33)
            d2 = mul(d2, k33)
        var denom = d1 + d2 + d3
        if denom > DZERO:
            k = dnum / denom
    else:
        k = (
            mul(mul(ve1, ve1), k11)
            + mul(mul(ve2, ve2), k22)
            + mul(mul(ve3, ve3), k33)
        )
    return k


struct Npf(Movable):
    """The conductivities, the options and the conductances of NPF6."""

    var icelltype: List[Int]
    """0 for a confined cell, > 0 for a convertible cell, by reduced node."""
    var k11: List[Float64]
    """The horizontal conductivity."""
    var k22: List[Float64]
    """The conductivity along the second axis."""
    var k33: List[Float64]
    """The vertical conductivity."""
    var angle1: List[Float64]
    """The first rotation angle, in radians."""
    var angle2: List[Float64]
    """The second rotation angle, in radians."""
    var angle3: List[Float64]
    """The third rotation angle, in radians."""
    var wetdry: List[Float64]
    """The rewetting threshold and its direction."""
    var sat: List[Float64]
    """The saturation of each cell."""
    var condsat: List[Float64]
    """The saturated conductance of each connection, by `jas`."""
    var ithickstartflag: List[Int]
    """1 for a cell whose thickness is set by the starting head."""
    var ibotnode: List[Int]
    """The lowest cell under each cell, for Newton under-relaxation."""
    var icellavg: CellAveraging
    """The mean of the conductivities across a horizontal face."""
    var ithickstrt: Int
    """1 if THICKSTRT is on."""
    var ivarcv: Int
    """1 if VARIABLECV is on."""
    var idewatcv: Int
    """1 if VARIABLECV DEWATERED is on."""
    var iperched: Int
    """1 if PERCHED is on."""
    var irewet: Int
    """1 if REWET is on."""
    var wetfct: Float64
    """The factor of the head of a rewet cell."""
    var iwetit: Int
    """The outer iterations between rewetting checks."""
    var ihdwet: Int
    """0 to rewet from the neighbor head, 1 from the threshold."""
    var ihighcellsat: Int
    """1 if HIGHEST_CELL_SATURATION is on."""
    var ik22overk: Int
    """1 if K22 is a ratio to K."""
    var ik33overk: Int
    """1 if K33 is a ratio to K."""
    var ik22: Int
    """1 if K22 was read."""
    var ik33: Int
    """1 if K33 was read."""
    var iangle1: Int
    """1 if ANGLE1 was read."""
    var iangle2: Int
    """1 if ANGLE2 was read."""
    var iangle3: Int
    """1 if ANGLE3 was read."""
    var iwetdry: Int
    """1 if WETDRY was read."""
    var inewton: Int
    """1 for the Newton-Raphson formulation."""
    var satomega: Float64
    """The smoothing of the saturation: 1e-6 with Newton, else 0."""
    var hnoflo: Float64
    """The head of a cell with no flow."""
    var hdry: Float64
    """The head of a dry cell."""
    var iavgkeff: Int
    """0 for the harmonic conductivity in a direction."""

    def __init__(out self):
        """Make the package with the defaults of `allocate_scalars`."""
        self.icelltype = List[Int]()
        self.k11 = List[Float64]()
        self.k22 = List[Float64]()
        self.k33 = List[Float64]()
        self.angle1 = List[Float64]()
        self.angle2 = List[Float64]()
        self.angle3 = List[Float64]()
        self.wetdry = List[Float64]()
        self.sat = List[Float64]()
        self.condsat = List[Float64]()
        self.ithickstartflag = List[Int]()
        self.ibotnode = List[Int]()
        self.icellavg = CellAveraging(CCOND_HMEAN)
        self.ithickstrt = 0
        self.ivarcv = 0
        self.idewatcv = 0
        self.iperched = 0
        self.irewet = 0
        self.wetfct = DONE
        self.iwetit = 1
        self.ihdwet = 0
        self.ihighcellsat = 0
        self.ik22overk = 0
        self.ik33overk = 0
        self.ik22 = 0
        self.ik33 = 0
        self.iangle1 = 0
        self.iangle2 = 0
        self.iangle3 = 0
        self.iwetdry = 0
        self.inewton = 0
        self.satomega = DZERO
        self.hnoflo = DHNOFLO
        self.hdry = DHDRY
        self.iavgkeff = 0

    def read(mut self, file: InputFile, dis: Dis, inewton: Int) raises:
        """Read an NPF6 file, as `source_options` and `source_griddata` do.

        Args:
            file: The file.
            dis: The grid.
            inewton: 1 if the model uses the Newton-Raphson formulation.

        Raises:
            Error: An option or an array is missing or wrong.
        """
        self.inewton = inewton
        var b = file.find("OPTIONS")
        if b >= 0:
            for w in file.blocks[b].data_lines():
                var key = w[0].upper()
                if key == "ALTERNATIVE_CELL_AVERAGING":
                    if len(w) < 2:
                        raise Error(
                            "Unrecognized input value for"
                            " ALTERNATIVE_CELL_AVERAGING option."
                        )
                    var v = w[1].upper()
                    if v == "LOGARITHMIC":
                        self.icellavg = CellAveraging(1)
                    elif v == "AMT-LMK":
                        self.icellavg = CellAveraging(2)
                    elif v == "AMT-HMK":
                        self.icellavg = CellAveraging(3)
                    else:
                        raise Error(
                            "Unrecognized input value for"
                            " ALTERNATIVE_CELL_AVERAGING option."
                        )
                elif key == "THICKSTRT":
                    self.ithickstrt = 1
                elif key == "VARIABLECV":
                    self.ivarcv = 1
                    if len(w) > 1 and w[1].upper() == "DEWATERED":
                        self.idewatcv = 1
                elif key == "PERCHED":
                    self.iperched = 1
                elif key == "REWET":
                    self.irewet = 1
                    var i = 1
                    while i + 1 < len(w):
                        var k = w[i].upper()
                        if k == "WETFCT":
                            self.wetfct = read_real(w[i + 1])
                        elif k == "IWETIT":
                            self.iwetit = read_int(w[i + 1])
                        elif k == "IHDWET":
                            self.ihdwet = read_int(w[i + 1])
                        i += 2
                elif key == "XT3D":
                    raise Error("the XT3D option is not supported")
                elif key == "HIGHEST_CELL_SATURATION":
                    self.ihighcellsat = 1
                elif key == "K22OVERK":
                    self.ik22overk = 1
                elif key == "K33OVERK":
                    self.ik33overk = 1
                elif key == "DEV_NO_NEWTON":
                    self.inewton = 0
                elif key == "DEV_OMEGA" and len(w) > 1:
                    self.satomega = read_real(w[1])
        if self.iwetit <= 0:
            self.iwetit = 1
        if self.inewton > 0:
            self.satomega = DEM6
            if self.iperched > 0:
                raise Error(
                    "PERCHED option cannot be used with the Newton-Raphson"
                    " formulation."
                )
            if self.ivarcv > 0:
                raise Error(
                    "VARIABLECV option cannot be used with the Newton-Raphson"
                    " formulation."
                )
            if self.irewet > 0:
                raise Error(
                    "REWET option cannot be used with the Newton-Raphson"
                    " formulation."
                )
        else:
            self.ihighcellsat = 0
        b = file.find("GRIDDATA")
        if b < 0:
            raise Error("NPF has no GRIDDATA block")
        ref g = file.blocks[b]
        var ncpl = dis.nrow * dis.ncol
        var ict = read_grid_ints(file, g, "ICELLTYPE", dis.nlay, ncpl)
        var k = read_grid_reals(file, g, "K", dis.nlay, ncpl)
        var k22 = read_grid_reals(file, g, "K22", dis.nlay, ncpl)
        var k33 = read_grid_reals(file, g, "K33", dis.nlay, ncpl)
        var wd = read_grid_reals(file, g, "WETDRY", dis.nlay, ncpl)
        var a1 = read_grid_reals(file, g, "ANGLE1", dis.nlay, ncpl)
        var a2 = read_grid_reals(file, g, "ANGLE2", dis.nlay, ncpl)
        var a3 = read_grid_reals(file, g, "ANGLE3", dis.nlay, ncpl)
        if len(ict) == 0:
            raise Error("Error in GRIDDATA block: ICELLTYPE not found.")
        if len(k) == 0:
            raise Error("Error in GRIDDATA block: K not found.")
        if len(k33) == 0 and self.ik33overk != 0:
            raise Error("K33OVERK option specified but K33 not specified.")
        if len(k22) == 0 and self.ik22overk != 0:
            raise Error("K22OVERK option specified but K22 not specified.")
        if len(k33) > 0:
            self.ik33 = 1
        if len(k22) > 0:
            self.ik22 = 1
        if len(wd) > 0:
            self.iwetdry = 1
        if len(a1) > 0:
            self.iangle1 = 1
        if len(a2) > 0:
            self.iangle2 = 1
        if len(a3) > 0:
            self.iangle3 = 1
        var nodes = dis.nodes
        self.icelltype = List[Int](length=nodes + 1, fill=0)
        self.k11 = List[Float64](length=nodes + 1, fill=0.0)
        self.k22 = List[Float64](length=nodes + 1, fill=0.0)
        self.k33 = List[Float64](length=nodes + 1, fill=0.0)
        self.wetdry = List[Float64](length=nodes + 1, fill=0.0)
        self.angle1 = List[Float64](length=nodes + 1, fill=0.0)
        self.angle2 = List[Float64](length=nodes + 1, fill=0.0)
        self.angle3 = List[Float64](length=nodes + 1, fill=0.0)
        for n in range(1, nodes + 1):  # pragma: no branch
            var u = dis.user(n)
            self.icelltype[n] = ict[u]
            self.k11[n] = k[u]
            self.k22[n] = k22[u] if self.ik22 != 0 else k[u]
            self.k33[n] = k33[u] if self.ik33 != 0 else k[u]
            if self.iwetdry != 0:
                self.wetdry[n] = wd[u]
            if self.iangle1 != 0:
                self.angle1[n] = a1[u]
            if self.iangle2 != 0:
                self.angle2[n] = a2[u]
            if self.iangle3 != 0:
                self.angle3[n] = a3[u]
        self._prepcheck(nodes)

    def _prepcheck(mut self, nodes: Int) raises:
        """Check the conductivities and convert the angles, as `prepcheck` does.

        Args:
            nodes: The number of cells.

        Raises:
            Error: A conductivity is not positive, or WETDRY is missing.
        """
        for n in range(1, nodes + 1):  # pragma: no branch
            if self.k11[n] <= DZERO:
                raise Error(
                    String(
                        "K value of ", self.k11[n], " for cell ", n, " is <= 0"
                    )
                )
        if self.ik33 != 0:
            for n in range(1, nodes + 1):  # pragma: no branch
                if self.ik33overk != 0:
                    self.k33[n] = mul(self.k33[n], self.k11[n])
                if self.k33[n] <= DZERO:
                    raise Error(String("K33 of cell ", n, " is <= 0"))
        if self.ik22 != 0:
            for n in range(1, nodes + 1):  # pragma: no branch
                if self.ik22overk != 0:
                    self.k22[n] = mul(self.k22[n], self.k11[n])
                if self.k22[n] <= DZERO:
                    raise Error(String("K22 of cell ", n, " is <= 0"))
        if self.irewet == 1 and self.iwetdry == 0:
            raise Error(
                "REWET was specified in the options block but WETDRY was"
                " not found."
            )
        if self.iangle1 != 0:
            for n in range(1, nodes + 1):  # pragma: no branch
                self.angle1[n] = mul(self.angle1[n], DPIO180)
        if self.iangle2 != 0:
            if self.iangle1 == 0:
                raise Error("ANGLE2 requires ANGLE1.")
            if self.iangle3 == 0:
                raise Error("ANGLE2 requires ANGLE3.")
            for n in range(1, nodes + 1):  # pragma: no branch
                self.angle2[n] = mul(self.angle2[n], DPIO180)
        if self.iangle3 != 0:
            if self.iangle1 == 0:
                raise Error("ANGLE3 requires ANGLE1.")
            if self.iangle2 == 0:
                raise Error("ANGLE3 requires ANGLE2.")
            for n in range(1, nodes + 1):  # pragma: no branch
                self.angle3[n] = mul(self.angle3[n], DPIO180)

    def thksat(self, dis: Dis, n: Int, hn: Float64) -> Float64:
        """Return the saturation of a cell at a head, as `sgwf_npf_thksat` does.

        Args:
            dis: The grid.
            n: The cell.
            hn: The head.

        Returns:
            The saturation, 0 to 1.
        """
        var s: Float64
        if hn >= dis.top[n]:
            s = DONE
        else:
            s = (hn - dis.bot[n]) / (dis.top[n] - dis.bot[n])
        if self.inewton != 0:
            s = squadratic_saturation(dis.top[n], dis.bot[n], hn, self.satomega)
        return s

    def _initial_sat(
        self, dis: Dis, ibound: List[Int], strt: List[Float64], n: Int
    ) -> Float64:
        """Return the saturation of a cell for its saturated conductance.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            strt: The starting heads.
            n: The cell.

        Returns:
            1, or the saturation at the starting head for a THICKSTRT cell.
        """
        var satn = DONE
        if ibound[n] != 0 and self.ithickstartflag[n] != 0:
            satn = self.thksat(dis, n, strt[n])
        return satn

    def _connection_normal(
        self, dis: Dis, noden: Int, nodem: Int, ihc: Int
    ) -> Tuple[Float64, Float64, Float64]:
        """Return the unit normal of a face, as `connection_normal` of DIS does.

        Args:
            dis: The grid.
            noden: The cell on this side.
            nodem: The cell on the other side.
            ihc: The kind of the connection.

        Returns:
            The x, y and z components.
        """
        if ihc == 0:
            if nodem < noden:
                return (DZERO, DZERO, DONE)
            return (DZERO, DZERO, -DONE)
        var u1 = dis.user(noden) - 1
        var u2 = dis.user(nodem) - 1
        var ncpl = dis.nrow * dis.ncol
        var i1 = (u1 % ncpl) // dis.ncol
        var j1 = (u1 % ncpl) % dis.ncol
        var i2 = (u2 % ncpl) // dis.ncol
        var j2 = (u2 % ncpl) % dis.ncol
        if i2 < i1:
            return (DZERO, DONE, DZERO)
        elif j2 < j1:
            return (-DONE, DZERO, DZERO)
        elif j2 > j1:
            return (DONE, DZERO, DZERO)
        return (DZERO, -DONE, DZERO)

    def hy_eff(self, dis: Dis, n: Int, m: Int, ihc: Int) -> Float64:
        """Return the conductivity of cell n toward cell m, as `hy_eff` does.

        Args:
            dis: The grid.
            n: The cell.
            m: The cell on the other side.
            ihc: The kind of the connection.

        Returns:
            The conductivity.
        """
        var hy11 = self.k11[n]
        var hy22 = self.k22[n]
        var hy33 = self.k33[n]
        var hy: Float64
        if ihc == C3D_VERTICAL:
            hy = hy33
            if self.iangle2 > 0:
                var vg = self._connection_normal(dis, n, m, ihc)
                # `read` requires ANGLE3 with ANGLE2.
                var ang3 = self.angle3[n]
                hy = hyeff(
                    hy11,
                    hy22,
                    hy33,
                    self.angle1[n],
                    self.angle2[n],
                    ang3,
                    vg[0],
                    vg[1],
                    vg[2],
                    self.iavgkeff,
                )
        else:
            hy = hy11
            if self.ik22 > 0:
                var vg = self._connection_normal(dis, n, m, ihc)
                var ang1 = DZERO
                var ang2 = DZERO
                var ang3 = DZERO
                if self.iangle1 > 0:
                    ang1 = self.angle1[n]
                    if self.iangle2 > 0:
                        # `read` requires ANGLE3 with ANGLE2.
                        ang2 = self.angle2[n]
                        ang3 = self.angle3[n]
                hy = hyeff(
                    hy11,
                    hy22,
                    hy33,
                    ang1,
                    ang2,
                    ang3,
                    vg[0],
                    vg[1],
                    vg[2],
                    self.iavgkeff,
                )
        return hy

    def preprocess(
        mut self,
        dis: Dis,
        mut ibound: List[Int],
        mut hnew: List[Float64],
        strt: List[Float64],
        newtonur: Bool,
    ) raises:
        """Set the saturations and the saturated conductances, as `preprocess_input` does.

        Args:
            dis: The grid.
            ibound: The status of each cell. A cell that is dry at the
                start becomes inactive.
            hnew: The heads.
            strt: The starting heads.
            newtonur: True if the model uses Newton under-relaxation.

        Raises:
            Error: A cell of THICKSTRT is dry at the start, or a constant
                head cell is dry.
        """
        var nodes = dis.nodes
        self.ithickstartflag = List[Int](length=nodes + 1, fill=0)
        self.sat = List[Float64](length=nodes + 1, fill=0.0)
        # MODFLOW 6 makes a cell inactive here when it has no conductivity
        # to a neighbor. Each cell of the model starts active and each K is
        # positive, so this changes no cell.
        # MODFLOW 6 also lifts each head under its bottom when Newton and
        # VARIABLECV are both on. `read` rejects that pair.
        if self.inewton == 0:
            self.wetdry_check(dis, 0, ibound, hnew)
        if self.ithickstrt == 0:
            for n in range(1, nodes + 1):  # pragma: no branch
                if self.icelltype[n] < 0:
                    self.icelltype[n] = 1
        for n in range(1, nodes + 1):  # pragma: no branch
            if ibound[n] == 0:
                self.sat[n] = DONE
                # A negative cell type is left only with THICKSTRT.
                if self.icelltype[n] < 0:
                    self.ithickstartflag[n] = 1
                    self.icelltype[n] = 0
            else:
                var satn: Float64
                if self.icelltype[n] < 0:
                    satn = self.thksat(dis, n, strt[n])
                    if dis.bot[n] > strt[n]:
                        raise Error(
                            String(
                                "Cell ",
                                n,
                                " is dry at the start and THICKSTRT is on",
                            )
                        )
                    self.ithickstartflag[n] = 1
                    self.icelltype[n] = 0
                else:
                    satn = DONE
                self.sat[n] = satn
        self.condsat = List[Float64](length=dis.con.njas + 1, fill=0.0)
        for n in range(1, nodes + 1):  # pragma: no branch
            self._calc_condsat(dis, ibound, strt, n)
        if newtonur:
            self.ibotnode = List[Int](length=nodes + 1, fill=0)
            for n in range(1, nodes + 1):  # pragma: no branch
                # MODFLOW 6 also keeps the lowest bottom so far. The cell
                # under nn always has the lower bottom, as DIS rejects a cell
                # with no thickness, so the port follows the column down.
                var nn = n
                while True:
                    var nextn = 0
                    for ii in range(dis.con.ia[nn] + 1, dis.con.ia[nn + 1]):
                        var m = dis.con.ja[ii]
                        if dis.con.ihc[dis.con.jas[ii]] == 0 and m > nn:
                            nextn = m
                    if nextn > 0:
                        nn = nextn
                    else:
                        break
                self.ibotnode[n] = nn

    def _calc_condsat(
        mut self, dis: Dis, ibound: List[Int], strt: List[Float64], node: Int
    ):
        """Set the saturated conductance of the connections of a cell to the cells after it.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            strt: The starting heads.
            node: The cell.
        """
        var satnode = self._initial_sat(dis, ibound, strt, node)
        for ii in range(dis.con.ia[node] + 1, dis.con.ia[node + 1]):
            var m = dis.con.ja[ii]
            var jj = dis.con.jas[ii]
            if m < node:
                continue
            var n = node
            var topn = dis.top[n]
            var botn = dis.bot[n]
            var satn = satnode
            var topm = dis.top[m]
            var botm = dis.bot[m]
            var satm = self._initial_sat(dis, ibound, strt, m)
            var ihc = dis.con.ihc[jj]
            var hyn = self.hy_eff(dis, n, m, ihc)
            var hym = self.hy_eff(dis, m, n, ihc)
            var hn = topn
            if self.ithickstartflag[n] != 0:
                hn = strt[n]
            var hm = topm
            if self.ithickstartflag[m] != 0:
                hm = strt[m]
            var csat: Float64
            if ihc == C3D_VERTICAL:
                csat = vcond(
                    1,
                    1,
                    1,
                    1,
                    0,
                    1,
                    1,
                    DONE,
                    botn,
                    botm,
                    hyn,
                    hym,
                    satn,
                    satm,
                    topn,
                    topm,
                    botn,
                    botm,
                    dis.con.hwva[jj],
                )
            else:
                csat = hcond(
                    1,
                    1,
                    1,
                    1,
                    0,
                    self.icellavg.value,
                    DONE,
                    hn,
                    hm,
                    satn,
                    satm,
                    hyn,
                    hym,
                    topn,
                    topm,
                    botn,
                    botm,
                    dis.con.cl1[jj],
                    dis.con.cl2[jj],
                    dis.con.hwva[jj],
                )
            self.condsat[jj] = csat

    def ad(
        self,
        dis: Dis,
        ibound: List[Int],
        mut hold: List[Float64],
        mut hnew: List[Float64],
    ):
        """Set the heads of the dry cells that can rewet, as `npf_ad` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            hold: The heads at the start of the step.
            hnew: The heads.
        """
        if self.irewet > 0:
            for n in range(1, dis.nodes + 1):  # pragma: no branch
                if self.wetdry[n] == DZERO:
                    continue
                if ibound[n] != 0:
                    continue
                hold[n] = dis.bot[n]
            for n in range(1, dis.nodes + 1):  # pragma: no branch
                if self.wetdry[n] == DZERO:
                    continue
                if ibound[n] != 0:
                    continue
                hnew[n] = DHDRY

    def cf(
        mut self,
        dis: Dis,
        kiter: Int,
        mut ibound: List[Int],
        mut hnew: List[Float64],
    ) raises:
        """Rewet and dry the cells, then set the saturations, as `npf_cf` does.

        Args:
            dis: The grid.
            kiter: The outer iteration.
            ibound: The status of each cell.
            hnew: The heads.

        Raises:
            Error: A constant head cell went dry.
        """
        if self.inewton != 1:
            self.wetdry_check(dis, kiter, ibound, hnew)
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            if self.icelltype[n] != 0:
                if ibound[n] == 0:
                    self.sat[n] = DZERO
                else:
                    self.sat[n] = self.thksat(dis, n, hnew[n])

    def wetdry_check(
        mut self,
        dis: Dis,
        kiter: Int,
        mut ibound: List[Int],
        mut hnew: List[Float64],
    ) raises:
        """Rewet the dry cells and dry the cells under their bottoms, as `sgwf_npf_wetdry` does.

        Args:
            dis: The grid.
            kiter: The outer iteration.
            ibound: The status of each cell.
            hnew: The heads.

        Raises:
            Error: A constant head cell went dry.
        """
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            for ii in range(dis.con.ia[n] + 1, dis.con.ia[n + 1]):
                var m = dis.con.ja[ii]
                var ihc = dis.con.ihc[dis.con.jas[ii]]
                self._rewet_check(
                    dis, kiter, n, hnew[m], ibound[m], ihc, ibound, hnew
                )
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            if ibound[n] == 0:
                continue
            if self.icelltype[n] == 0:
                continue
            # DIS rejects a cell whose thickness is not positive.
            var bbot = dis.bot[n]
            var ttop = dis.top[n]
            if hnew[n] < ttop:
                ttop = hnew[n]
            var thick = ttop - bbot
            if thick <= DZERO:
                hnew[n] = self.hdry
                if ibound[n] < 0:
                    raise Error(
                        "CONSTANT-HEAD CELL WENT DRY -- SIMULATION ABORTED"
                    )
                ibound[n] = 0
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            if ibound[n] == 30000:
                ibound[n] = 1

    def _rewet_check(
        self,
        dis: Dis,
        kiter: Int,
        node: Int,
        hm: Float64,
        ibdm: Int,
        ihc: Int,
        mut ibound: List[Int],
        mut hnew: List[Float64],
    ):
        """Rewet a dry cell from a neighbor, as `rewet_check` does.

        Args:
            dis: The grid.
            kiter: The outer iteration.
            node: The dry cell.
            hm: The head of the neighbor.
            ibdm: The status of the neighbor.
            ihc: The kind of the connection.
            ibound: The status of each cell.
            hnew: The heads.
        """
        if self.irewet <= 0:
            return
        if kiter % self.iwetit != 0:
            return
        if ibound[node] != 0 or self.wetdry[node] == DZERO:
            return
        var bbot = dis.bot[node]
        var wd = self.wetdry[node]
        var awd = wd
        if wd < 0:
            awd = -wd
        var turnon = bbot + awd
        var irewet = 0
        if ihc == C3D_VERTICAL:
            if ibdm > 0 and hm >= turnon:
                irewet = 1
        elif wd > DZERO:
            if ibdm > 0 and hm >= turnon:
                irewet = 1
        if irewet == 1:
            if self.ihdwet == 0:
                hnew[node] = bbot + mul(self.wetfct, hm - bbot)
            else:
                hnew[node] = bbot + mul(self.wetfct, awd)
            ibound[node] = 30000

    def _cond(
        self,
        dis: Dis,
        ibound: List[Int],
        n: Int,
        m: Int,
        ipos: Int,
        hn: Float64,
        hm: Float64,
    ) -> Float64:
        """Return the conductance of a connection at two heads.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            n: The first cell.
            m: The second cell.
            ipos: The position of the connection in row n.
            hn: The head of n.
            hm: The head of m.

        Returns:
            The conductance.
        """
        var jas = dis.con.jas[ipos]
        var ihc = dis.con.ihc[jas]
        var hyn = self.hy_eff(dis, n, m, ihc)
        var hym = self.hy_eff(dis, m, n, ihc)
        if ihc == C3D_VERTICAL:
            return vcond(
                ibound[n],
                ibound[m],
                self.icelltype[n],
                self.icelltype[m],
                self.inewton,
                self.ivarcv,
                self.idewatcv,
                self.condsat[jas],
                hn,
                hm,
                hyn,
                hym,
                self.sat[n],
                self.sat[m],
                dis.top[n],
                dis.top[m],
                dis.bot[n],
                dis.bot[m],
                dis.con.hwva[jas],
            )
        var satn = self.sat[n]
        var satm = self.sat[m]
        if self.ihighcellsat != 0:
            var botn = dis.bot[n]
            var botm = dis.bot[m]
            var ihdbot = n
            if botm > botn:
                ihdbot = m
            if abs(botm - botn) >= 1.0e-2:
                var top = dis.top[ihdbot]
                var bot = dis.bot[ihdbot]
                satn = squadratic_saturation(top, bot, hn, self.satomega)
                satm = squadratic_saturation(top, bot, hm, self.satomega)
        return hcond(
            ibound[n],
            ibound[m],
            self.icelltype[n],
            self.icelltype[m],
            self.inewton,
            self.icellavg.value,
            self.condsat[jas],
            hn,
            hm,
            satn,
            satm,
            hyn,
            hym,
            dis.top[n],
            dis.top[m],
            dis.bot[n],
            dis.bot[m],
            dis.con.cl1[jas],
            dis.con.cl2[jas],
            dis.con.hwva[jas],
        )

    def fc(
        self,
        dis: Dis,
        ibound: List[Int],
        hnew: List[Float64],
        mut amat: List[Float64],
        mut rhs: List[Float64],
    ):
        """Add the conductance terms to the matrix, as `fc_default_flow` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            hnew: The heads.
            amat: The matrix, by position.
            rhs: The right side.
        """
        ref con = dis.con
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            for ipos in range(con.ia[n] + 1, con.ia[n + 1]):
                var m = con.ja[ipos]
                if m < n:
                    continue
                var cond = self._cond(dis, ibound, n, m, ipos, hnew[n], hnew[m])
                var ihc = con.ihc[con.jas[ipos]]
                if ihc == C3D_VERTICAL and self.iperched != 0:
                    if self.icelltype[m] != 0 and hnew[m] < dis.top[m]:
                        var idiag = con.ia[n]
                        rhs[n] = rhs[n] - mul(cond, dis.bot[n])
                        amat[idiag] = amat[idiag] + -cond
                        var isymcon = con.isym[ipos]
                        amat[isymcon] = amat[isymcon] + cond
                        rhs[m] = rhs[m] + mul(cond, dis.bot[n])
                        continue
                var idiag = con.ia[n]
                amat[ipos] = amat[ipos] + cond
                amat[idiag] = amat[idiag] + -cond
                var isymcon = con.isym[ipos]
                var idiagm = con.ia[m]
                amat[isymcon] = amat[isymcon] + cond
                amat[idiagm] = amat[idiagm] + -cond

    def fn(
        self,
        dis: Dis,
        ibound: List[Int],
        hnew: List[Float64],
        mut amat: List[Float64],
        mut rhs: List[Float64],
    ):
        """Add the Newton-Raphson terms of the flows, as `fn_default_flow` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            hnew: The heads.
            amat: The matrix, by position.
            rhs: The right side.
        """
        ref con = dis.con
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            for ipos in range(con.ia[n] + 1, con.ia[n + 1]):
                var m = con.ja[ipos]
                if m < n:
                    continue
                var idiag = con.ia[n]
                var isymcon = con.isym[ipos]
                var ihc = con.ihc[con.jas[ipos]]
                # `read` rejects VARIABLECV with Newton, so a vertical
                # connection has no Newton term.
                if ihc == 0:
                    continue
                var iups = m
                if hnew[m] < hnew[n]:
                    iups = n
                var idn = n
                if iups == n:
                    idn = m
                # A confined cell upstream has no Newton term.
                if self.icelltype[iups] == 0:
                    continue
                var topup = dis.top[iups]
                var botup = dis.bot[iups]
                var cond = self.condsat[con.jas[ipos]]
                var consterm = mul(-cond, hnew[iups] - hnew[idn])
                var derv = squadratic_saturation_derivative(
                    topup, botup, hnew[iups], self.satomega
                )
                var idiagm = con.ia[m]
                if iups == n:
                    var term = mul(consterm, derv)
                    rhs[n] = rhs[n] + mul(term, hnew[n])
                    rhs[m] = rhs[m] - mul(term, hnew[n])
                    amat[idiag] = amat[idiag] + term
                    if ibound[m] > 0:
                        amat[isymcon] = amat[isymcon] + -term
                else:
                    var term = mul(-consterm, derv)
                    rhs[n] = rhs[n] + mul(term, hnew[m])
                    rhs[m] = rhs[m] - mul(term, hnew[m])
                    if ibound[n] > 0:
                        amat[ipos] = amat[ipos] + term
                    amat[idiagm] = amat[idiagm] + -term

    def cq(
        self,
        dis: Dis,
        ibound: List[Int],
        hnew: List[Float64],
        mut flowja: List[Float64],
    ):
        """Set the flow across each connection, as `cq_default_flow` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            hnew: The heads.
            flowja: The flows, by position.
        """
        ref con = dis.con
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            for ipos in range(con.ia[n] + 1, con.ia[n + 1]):
                var m = con.ja[ipos]
                if m < n:
                    continue
                var hn = hnew[n]
                var hm = hnew[m]
                var condnm = self._cond(dis, ibound, n, m, ipos, hn, hm)
                var hntemp = hn
                var hmtemp = hm
                if self.iperched != 0 and con.ihc[con.jas[ipos]] == 0:
                    if self.icelltype[m] != 0:
                        if hm < dis.top[m]:
                            hmtemp = dis.bot[n]
                var qnm = mul(condnm, hmtemp - hntemp)
                flowja[ipos] = qnm
                flowja[con.isym[ipos]] = -qnm

    def nur(
        self,
        dis: Dis,
        ibound: List[Int],
        mut x: List[Float64],
        xtemp: List[Float64],
        mut dx: List[Float64],
        mut inewtonur: Int,
        mut dxmax: Float64,
        mut locmax: Int,
    ):
        """Keep the heads above the bottom of the model, as `npf_nur` does.

        Args:
            dis: The grid.
            ibound: The status of each cell.
            x: The heads.
            xtemp: The heads before the solve.
            dx: The changes.
            inewtonur: Receives 1 if a head was reset.
            dxmax: The largest reset.
            locmax: The cell of the largest reset.
        """
        for n in range(1, dis.nodes + 1):  # pragma: no branch
            if ibound[n] < 1:
                continue
            var ibot = self.ibotnode[n]
            if self.icelltype[n] > 0 and self.icelltype[ibot] > 0:
                var botm = dis.bot[ibot]
                if x[n] < botm:
                    inewtonur = 1
                    var xx = mul(xtemp[n], DONE - DP9) + mul(botm, DP9)
                    var dxx = xx - xtemp[n]
                    if abs(dxx) > abs(dxmax):
                        locmax = n
                        dxmax = dxx
                    x[n] = xx
                    dx[n] = xtemp[n] - x[n]
