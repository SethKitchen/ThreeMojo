# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from mf6core.f90, gwf.f90, gwf-ic.f90 and NumericalSolution.f90 of
# MODFLOW 6.9.0.dev0, commit 59d89e9f, which is in the public domain (CC0).
# See THIRD-PARTY-NOTICES.md.

"""A MODFLOW 6 simulation of one groundwater flow model and its IMS solution.

`Simulation` reads `mfsim.nam` and the files that it names. `step` runs
one time step: it reads the stress period data, solves the outer
iterations and computes the flows. After a step, `heads` holds the head
of each cell and the budget arrays hold the flows.
"""

from std.math import sqrt
from std.os.path import join

from extensions.groundwater.blocks import (
    InputFile,
    read_grid_reals,
    read_int,
    read_real,
)
from extensions.groundwater.boundary import Boundary, boundary_kind
from extensions.groundwater.cmath import cpow, is_close, mul
from extensions.groundwater.constants import (
    DEM1,
    DEM2,
    DEM3,
    DEM15,
    DEM20,
    DHALF,
    DHNOFLO,
    DONE,
    DPREC,
    DTEN,
    DTHREE,
    DZERO,
)
from extensions.groundwater.dis import Dis
from extensions.groundwater.ims import ImsLinear, LinearSettings
from extensions.groundwater.kinds import (
    CG,
    UNDER_RELAXATION_COOLEY,
    UNDER_RELAXATION_DBD,
    UNDER_RELAXATION_NONE,
    UNDER_RELAXATION_SIMPLE,
    UnderRelaxation,
)
from extensions.groundwater.npf import Npf
from extensions.groundwater.smoothing import squadratic_saturation
from extensions.groundwater.sto import Sto
from extensions.groundwater.tdis import Tdis
from units.si import FOOT64, Length64, LengthUnit64, METER

# A centimeter, with the factor exact in double precision.
comptime CENTIMETER64 = LengthUnit64(0.01, "cm")


struct NonlinearSettings(Copyable, Movable):
    """The settings of the OPTIONS and NONLINEAR blocks of IMS."""

    var dvclose: Float64
    """The outer closure criterion of the change."""
    var mxiter: Int
    """The largest number of outer iterations."""
    var nonmeth: UnderRelaxation
    """The under-relaxation."""
    var theta: Float64
    """The reduction of the delta-bar-delta weight."""
    var akappa: Float64
    """The increase of the delta-bar-delta weight."""
    var gamma: Float64
    """The weight of the history."""
    var amomentum: Float64
    """The momentum of the delta-bar-delta change."""
    var numtrack: Int
    """The largest number of backtracking steps, or 0."""
    var btol: Float64
    """The residual growth that starts backtracking."""
    var breduc: Float64
    """The reduction of the change at each backtracking step."""
    var res_lim: Float64
    """The residual under which backtracking stops."""
    var iallowptc: Int
    """1 to allow pseudo-transient continuation, 0 never, -1 not in period 1."""
    var iptcopt: Int
    """1 to start the continuation from the norms of the residual."""
    var ptcexp: Float64
    """The exponent of the continuation update."""
    var ptcdel0: Float64
    """The first continuation step, or 0."""
    var ifdparam: Int
    """The complexity: 1 simple, 2 moderate, 3 complex."""

    def __init__(out self):
        """Make the defaults of `allocate_scalars` and of SIMPLE."""
        self.dvclose = DEM3
        self.mxiter = 25
        self.nonmeth = UNDER_RELAXATION_NONE
        self.theta = DONE
        self.akappa = DZERO
        self.gamma = DONE
        self.amomentum = DZERO
        self.numtrack = 0
        self.btol = DZERO
        self.breduc = DZERO
        self.res_lim = DZERO
        self.iallowptc = 1
        self.iptcopt = 0
        self.ptcexp = DONE
        self.ptcdel0 = DZERO
        self.ifdparam = 1

    def set_outer(mut self, ifdparam: Int):
        """Set the outer defaults of a complexity, as `sln_setouter` does.

        Args:
            ifdparam: 1 simple, 2 moderate, 3 complex.
        """
        self.ifdparam = ifdparam
        self.amomentum = DZERO
        if ifdparam == 1:
            self.dvclose = DEM3
            self.mxiter = 25
            self.nonmeth = UNDER_RELAXATION_NONE
            self.theta = DONE
            self.akappa = DZERO
            self.gamma = DONE
            self.numtrack = 0
            self.btol = DZERO
            self.breduc = DZERO
            self.res_lim = DZERO
        elif ifdparam == 2:
            self.dvclose = DEM2
            self.mxiter = 50
            self.nonmeth = UNDER_RELAXATION_DBD
            self.theta = 0.9
            self.akappa = 0.0001
            self.gamma = DZERO
            self.numtrack = 0
            self.btol = DZERO
            self.breduc = DZERO
            self.res_lim = DZERO
        else:
            self.dvclose = DEM1
            self.mxiter = 100
            self.nonmeth = UNDER_RELAXATION_DBD
            self.theta = 0.8
            self.akappa = 0.0001
            self.gamma = DZERO
            self.numtrack = 20
            self.btol = 1.05
            self.breduc = 0.1
            self.res_lim = 0.002


def read_ims(
    file: InputFile, mut nl: NonlinearSettings
) raises -> LinearSettings:
    """Read an IMS6 file, as `sln_ar` and `read_from_file` do.

    Args:
        file: The file.
        nl: Receives the outer settings.

    Returns:
        The inner settings.

    Raises:
        Error: A keyword or a value is not known.
    """
    var ifdparam = 1
    var b = file.find("OPTIONS")
    if b >= 0:
        for w in file.blocks[b].data_lines():
            var key = w[0].upper()
            if key == "COMPLEXITY" and len(w) > 1:
                var c = w[1].upper()
                if c == "SIMPLE":
                    ifdparam = 1
                elif c == "MODERATE":
                    ifdparam = 2
                elif c == "COMPLEX":
                    ifdparam = 3
                else:
                    raise Error(
                        String("Unknown IMS COMPLEXITY option (", c, ").")
                    )
            elif key == "NO_PTC":
                var ival = 0
                if len(w) > 1 and w[1].upper() == "FIRST":
                    ival = -1
                nl.iallowptc = ival
            elif key == "DEV_PTC":
                nl.iallowptc = 1
            elif key == "DEV_PTC_OPTION":
                nl.iallowptc = 1
                nl.iptcopt = 1
            elif key == "DEV_PTC_EXPONENT" and len(w) > 1:
                var r = read_real(w[1])
                if r > DZERO:
                    nl.iallowptc = 1
                    nl.ptcexp = r
            elif key == "DEV_PTC_DEL0" and len(w) > 1:
                var r = read_real(w[1])
                if r > DZERO:
                    nl.iallowptc = 1
                    nl.ptcdel0 = r
            elif (
                key == "PRINT_OPTION"
                or key == "CSV_OUTER_OUTPUT"
                or key == "CSV_INNER_OUTPUT"
                or key == "ATS_OUTER_MAXIMUM_FRACTION"
            ):
                pass
            else:
                raise Error(String("Unknown IMS option  (", key, ")."))
    var iallowptc = nl.iallowptc
    var iptcopt = nl.iptcopt
    var ptcexp = nl.ptcexp
    var ptcdel0 = nl.ptcdel0
    nl.set_outer(ifdparam)
    nl.iallowptc = iallowptc
    nl.iptcopt = iptcopt
    nl.ptcexp = ptcexp
    nl.ptcdel0 = ptcdel0
    b = file.find("NONLINEAR")
    if b >= 0:
        for w in file.blocks[b].data_lines():
            var key = w[0].upper()
            var has = len(w) > 1
            if key == "OUTER_DVCLOSE" and has:
                nl.dvclose = read_real(w[1])
            elif key == "OUTER_MAXIMUM" and has:
                nl.mxiter = read_int(w[1])
            elif key == "UNDER_RELAXATION" and has:
                var m = w[1].upper()
                if m == "NONE":
                    nl.nonmeth = UNDER_RELAXATION_NONE
                elif m == "SIMPLE":
                    nl.nonmeth = UNDER_RELAXATION_SIMPLE
                elif m == "COOLEY":
                    nl.nonmeth = UNDER_RELAXATION_COOLEY
                elif m == "DBD":
                    nl.nonmeth = UNDER_RELAXATION_DBD
                else:
                    raise Error(
                        String("Unknown UNDER_RELAXATION specified (", m, ").")
                    )
            elif key == "LINEAR_SOLVER" and has:
                var m = w[1].upper()
                if m != "DEFAULT" and m != "LINEAR":
                    raise Error(
                        String("Unknown LINEAR_SOLVER specified (", m, ").")
                    )
            elif key == "UNDER_RELAXATION_THETA" and has:
                nl.theta = read_real(w[1])
            elif key == "UNDER_RELAXATION_KAPPA" and has:
                nl.akappa = read_real(w[1])
            elif key == "UNDER_RELAXATION_GAMMA" and has:
                nl.gamma = read_real(w[1])
            elif key == "UNDER_RELAXATION_MOMENTUM" and has:
                nl.amomentum = read_real(w[1])
            elif key == "BACKTRACKING_NUMBER" and has:
                nl.numtrack = read_int(w[1])
            elif key == "BACKTRACKING_TOLERANCE" and has:
                nl.btol = read_real(w[1])
            elif key == "BACKTRACKING_REDUCTION_FACTOR" and has:
                nl.breduc = read_real(w[1])
            elif key == "BACKTRACKING_RESIDUAL_LIMIT" and has:
                nl.res_lim = read_real(w[1])
            else:
                raise Error(
                    String("Unknown IMS NONLINEAR keyword (", key, ").")
                )
    if nl.theta < DEM3:
        nl.theta = DEM3
    if nl.mxiter <= 0:
        raise Error("Outer iteration number must be > 0.")
    if nl.nonmeth == UNDER_RELAXATION_SIMPLE and nl.gamma == DZERO:
        raise Error(
            "GAMMA must be greater than zero if SIMPLE under-relaxation is"
            " used."
        )
    var ls = LinearSettings(ifdparam)
    ls.read(file)
    return ls^


struct Simulation(Movable):
    """One groundwater flow model, its time discretization and its solution."""

    var folder: String
    """The folder of `mfsim.nam`."""
    var tdis: Tdis
    """The stress periods and the time steps."""
    var dis: Dis
    """The grid."""
    var npf: Npf
    """The conductances."""
    var sto: Sto
    """The storage, if the model has STO6."""
    var insto: Bool
    """True if the model has STO6."""
    var bnds: List[Boundary]
    """The boundary packages, in the order of the name file."""
    var inewton: Int
    """1 for the Newton-Raphson formulation."""
    var inewtonur: Int
    """1 for Newton under-relaxation."""
    var iss: Int
    """1 for a steady-state period."""
    var strt: List[Float64]
    """The starting heads."""
    var x: List[Float64]
    """The heads, by reduced node."""
    var xold: List[Float64]
    """The heads at the start of the step."""
    var xtemp: List[Float64]
    """The heads before the linear solve."""
    var ibound: List[Int]
    """The status of each cell: > 0 active, < 0 constant head, 0 inactive."""
    var amat: List[Float64]
    """The matrix, by position."""
    var rhs: List[Float64]
    """The right side."""
    var flowja: List[Float64]
    """The flows, by position."""
    var nl: NonlinearSettings
    """The outer settings."""
    var ims: ImsLinear
    """The linear solver."""
    var isymmetric: Int
    """1 if the linear solver needs a symmetric matrix."""
    var keep_going: Bool
    """True if the simulation goes on after a step that fails to converge."""
    var icnvg: Int
    """1 if the last time step converged."""
    var kiter_last: Int
    """The outer iterations of the last time step."""
    var itertot_sim: Int
    """The inner iterations of the simulation."""
    var dxold: List[Float64]
    """The change of the last outer iteration."""
    var wsave: List[Float64]
    """The delta-bar-delta weights."""
    var hchold: List[Float64]
    """The delta-bar-delta history."""
    var deold: List[Float64]
    """The delta-bar-delta change before."""
    var bigch: Float64
    """The largest change, for Cooley under-relaxation."""
    var bigchold: Float64
    """The history of the largest change."""
    var relaxold: Float64
    """The Cooley relaxation before."""
    var res_prev: Float64
    """The residual norm before, for backtracking."""
    var res_new: Float64
    """The residual norm now, for backtracking."""
    var l2norm0: Float64
    """The residual norm before, for pseudo-transient continuation."""
    var ptcdel: Float64
    """The continuation step."""

    def __init__(out self, folder: String) raises:
        """Read a simulation, as `sim_df`, `sln_df` and `gwf_ar` do.

        Args:
            folder: The folder that holds `mfsim.nam`.

        Raises:
            Error: A file is missing, or names a package or a value that
                the port does not support.
        """
        self.folder = folder
        var sim = InputFile(folder, "mfsim.nam")
        self.keep_going = False
        var b = sim.find("OPTIONS")
        if b >= 0:
            for w in sim.blocks[b].data_lines():
                if w[0].upper() == "CONTINUE":
                    self.keep_going = True
        var tdisname = String()
        b = sim.find("TIMING")
        if b >= 0:
            for w in sim.blocks[b].data_lines():
                if w[0].upper() == "TDIS6" and len(w) > 1:
                    tdisname = w[1]
        if tdisname.byte_length() == 0:
            raise Error("mfsim.nam has no TDIS6 file")
        var gwfname = String()
        b = sim.find("MODELS")
        if b >= 0:
            var lines = sim.blocks[b].data_lines()
            if len(lines) != 1:
                raise Error("the port runs one model")
            if lines[0][0].upper() != "GWF6" or len(lines[0]) < 2:
                raise Error("the port runs one GWF6 model")
            gwfname = lines[0][1]
        if gwfname.byte_length() == 0:
            raise Error("mfsim.nam has no GWF6 model")
        var imsname = String()
        b = sim.find("SOLUTIONGROUP")
        if b >= 0:
            for w in sim.blocks[b].data_lines():
                var key = w[0].upper()
                if key == "IMS6" and len(w) > 1:
                    imsname = w[1]
                elif key == "MXITER" and len(w) > 1:
                    if read_int(w[1]) != 1:
                        raise Error(
                            "the port runs a solution group MXITER of 1"
                        )
                else:
                    raise Error(String("the port does not support ", key))
        if imsname.byte_length() == 0:
            raise Error("mfsim.nam has no IMS6 file")
        self.tdis = Tdis()
        self.tdis.read(InputFile(folder, tdisname))
        var nam = InputFile(folder, gwfname)
        self.inewton = 0
        self.inewtonur = 0
        b = nam.find("OPTIONS")
        if b >= 0:
            for w in nam.blocks[b].data_lines():
                if w[0].upper() == "NEWTON":
                    self.inewton = 1
                    if len(w) > 1 and w[1].upper() == "UNDER_RELAXATION":
                        self.inewtonur = 1
        self.dis = Dis()
        self.npf = Npf()
        self.sto = Sto()
        self.insto = False
        self.bnds = List[Boundary]()
        self.strt = List[Float64]()
        var icfile = String()
        var npffile = String()
        var stofile = String()
        var bndfiles = List[String]()
        var bndtypes = List[String]()
        var bndnames = List[String]()
        var disfile = String()
        b = nam.find("PACKAGES")
        if b < 0:
            raise Error("the GWF name file has no PACKAGES block")
        var nbnd = 0
        for w in nam.blocks[b].data_lines():
            if len(w) < 2:
                raise Error("a package needs a file type and a file name")
            var ftype = w[0].upper()
            if ftype == "DIS6":
                disfile = w[1]
            elif ftype == "IC6":
                icfile = w[1]
            elif ftype == "NPF6":
                npffile = w[1]
            elif ftype == "STO6":
                stofile = w[1]
            elif ftype == "OC6" or ftype == "OBS6":
                pass
            else:
                _ = boundary_kind(ftype)
                bndtypes.append(ftype)
                bndfiles.append(w[1])
                bndnames.append(w[2].upper() if len(w) > 2 else String())
        # MODFLOW 6 creates the boundary packages in the order of its type
        # list GWF_MULTIPKG, and keeps the order of the name file within a
        # type. The order sets the order of the sums in each cell.
        var order: List[String] = [
            "WEL6",
            "DRN6",
            "RIV6",
            "GHB6",
            "RCH6",
            "EVT6",
            "CHD6",
        ]
        var files = List[String]()
        for t in order:  # pragma: no branch
            var ipaknum = 0
            for i in range(len(bndtypes)):
                if bndtypes[i] != t:
                    continue
                ipaknum += 1
                nbnd += 1
                var pname = bndnames[i]
                if pname.byte_length() == 0:
                    pname = String(t[byte=0:3], "-", ipaknum)
                self.bnds.append(Boundary(boundary_kind(t), pname, nbnd))
                files.append(bndfiles[i])
        bndfiles = files^
        if disfile.byte_length() == 0:
            raise Error("the model has no DIS6 file")
        if icfile.byte_length() == 0:
            raise Error("the model has no IC6 file")
        if npffile.byte_length() == 0:
            raise Error("the model has no NPF6 file")
        self.dis.read(InputFile(folder, disfile))
        var nodes = self.dis.nodes
        var nja = self.dis.con.nja
        var ic = InputFile(folder, icfile)
        b = ic.find("GRIDDATA")
        if b < 0:
            raise Error("IC has no GRIDDATA block")
        var ncpl = self.dis.nrow * self.dis.ncol
        var su = read_grid_reals(ic, ic.blocks[b], "STRT", self.dis.nlay, ncpl)
        self.strt = List[Float64](length=nodes + 1, fill=1.0)
        if len(su) > 0:
            for n in range(1, nodes + 1):  # pragma: no branch
                self.strt[n] = su[self.dis.user(n)]
        self.npf.read(InputFile(folder, npffile), self.dis, self.inewton)
        if stofile.byte_length() > 0:
            self.insto = True
            self.sto.read(InputFile(folder, stofile), self.dis, self.inewton)
        for i in range(len(self.bnds)):
            self.bnds[i].read(InputFile(folder, bndfiles[i]), self.dis)
        self.iss = 1
        self.x = self.strt.copy()
        self.xold = self.strt.copy()
        self.xtemp = self.strt.copy()
        self.ibound = List[Int](length=nodes + 1, fill=1)
        self.amat = List[Float64](length=nja + 1, fill=0.0)
        self.rhs = List[Float64](length=nodes + 1, fill=0.0)
        self.flowja = List[Float64](length=nja + 1, fill=0.0)
        self.npf.preprocess(
            self.dis, self.ibound, self.x, self.strt, self.inewtonur != 0
        )
        for i in range(len(self.bnds)):
            self.bnds[i].default_nodelist(self.dis)
        self.nl = NonlinearSettings()
        var ls = read_ims(InputFile(folder, imsname), self.nl)
        self.isymmetric = 1 if ls.ilinmeth == CG else 0
        if self.isymmetric == 1 and self.inewton != 0:
            raise Error(
                "the Newton-Raphson formulation produces an asymmetric"
                " matrix, but the conjugate gradient method was selected."
                " Use BICGSTAB instead."
            )
        self.ims = ImsLinear(ls^, self.dis.con.ia, self.dis.con.ja)
        self.icnvg = 0
        self.kiter_last = 0
        self.itertot_sim = 0
        self.dxold = List[Float64](length=nodes + 1, fill=0.0)
        self.wsave = List[Float64](length=nodes + 1, fill=0.0)
        self.hchold = List[Float64](length=nodes + 1, fill=0.0)
        self.deold = List[Float64](length=nodes + 1, fill=0.0)
        self.bigch = DZERO
        self.bigchold = DZERO
        self.relaxold = DZERO
        self.res_prev = DZERO
        self.res_new = DZERO
        self.l2norm0 = DZERO
        self.ptcdel = DZERO

    def done(self) -> Bool:
        """Return True after the last time step.

        Returns:
            Whether the simulation has ended.
        """
        return self.tdis.endofsimulation

    def step(mut self) raises:
        """Run one time step, as `Mf6PrepareTimestep` and `Mf6DoTimestep` do.

        Raises:
            Error: A package fails, for example a constant head cell goes
                dry, or the step does not converge and `mfsim.nam` has no
                CONTINUE option. The results of the step are kept.
        """
        self.tdis.set_counters()
        var kper = self.tdis.kper
        if self.tdis.kstp == 1:
            if self.insto:
                self.sto.rp(kper, self.iss)
            for i in range(len(self.bnds)):
                self.bnds[i].rp(kper, self.dis, self.ibound)
        self.tdis.set_timestep()
        # prepareSolve: model_ad.
        for n in range(1, self.dis.nodes + 1):  # pragma: no branch
            self.xold[n] = self.x[n]
        self.npf.ad(self.dis, self.ibound, self.xold, self.x)
        for i in range(len(self.bnds)):
            self.bnds[i].ad(self.dis, self.npf.icelltype, self.x, self.xold)
        self.icnvg = 0
        var kiter = 0
        for k in range(1, self.nl.mxiter + 1):  # pragma: no branch
            kiter = k
            self._solve(k)
            if self.icnvg == 1:
                break
        self.kiter_last = kiter
        self._cq()
        self._bd()
        if self.icnvg == 0 and not self.keep_going:
            self.tdis.endofsimulation = True
            raise Error(
                String(
                    "Solution 1 did not converge for stress period ",
                    kper,
                    " and time step ",
                    self.tdis.kstp,
                    ". The simulation stops, as it has no CONTINUE option.",
                )
            )

    def _buildsystem(mut self, kiter: Int, inewton: Int) raises:
        """Build the matrix and the right side, as `sln_buildsystem` does.

        Args:
            kiter: The outer iteration.
            inewton: 1 to add the Newton-Raphson terms of the model.

        Raises:
            Error: A constant head cell went dry.
        """
        for i in range(len(self.amat)):  # pragma: no branch
            self.amat[i] = DZERO
        for i in range(len(self.rhs)):  # pragma: no branch
            self.rhs[i] = DZERO
        self.npf.cf(self.dis, kiter, self.ibound, self.x)
        for i in range(len(self.bnds)):
            self.bnds[i].cf(self.dis, self.ibound, self.x)
        var inwt = inewton
        if inewton == 1:
            inwt = self.npf.inewton
        var inwtsto = inewton
        if self.insto and inewton == 1:
            inwtsto = self.sto.inewton
        self.npf.fc(self.dis, self.ibound, self.x, self.amat, self.rhs)
        if self.insto and self.iss == 0:
            self.sto.fc(
                self.dis,
                self.ibound,
                self.tdis.delt,
                self.xold,
                self.x,
                self.amat,
                self.rhs,
            )
        for i in range(len(self.bnds)):
            self.bnds[i].fc(self.dis, self.ibound, self.amat, self.rhs)
        if inwt != 0:
            self.npf.fn(self.dis, self.ibound, self.x, self.amat, self.rhs)
        if self.insto and inwtsto != 0 and self.iss == 0:
            self.sto.fn(
                self.dis,
                self.ibound,
                self.tdis.delt,
                self.x,
                self.amat,
                self.rhs,
            )

    def _residual(self) -> List[Float64]:
        """Return A x - b, zero at the inactive cells, as `sln_calc_residual` does.

        Returns:
            The residual, by node.
        """
        var nodes = self.dis.nodes
        var r = List[Float64](length=nodes + 1, fill=0.0)
        ref con = self.dis.con
        for irow in range(1, nodes + 1):  # pragma: no branch
            var y = DZERO
            for ipos in range(
                con.ia[irow], con.ia[irow + 1]
            ):  # pragma: no branch
                y = y + mul(self.amat[ipos], self.x[con.ja[ipos]])
            r[irow] = y
        for i in range(1, nodes + 1):  # pragma: no branch
            r[i] = -self.rhs[i] + r[i]
        for n in range(1, nodes + 1):  # pragma: no branch
            if self.ibound[n] < 1:
                r[n] = DZERO
        return r^

    def _l2norm(self) -> Float64:
        """Return the norm of the residual, as `sln_l2norm` does.

        Returns:
            The norm.
        """
        var r = self._residual()
        var n2 = DZERO
        for i in range(1, self.dis.nodes + 1):  # pragma: no branch
            n2 = n2 + mul(r[i], r[i])
        return sqrt(n2)

    def _calc_ptc(self, mut iptc: Int, mut ptcf: Float64):
        """Set the pseudo-transient continuation factor, as `gwf_ptc` does.

        Args:
            iptc: Receives 1 if the model uses the continuation.
            ptcf: Receives the largest residual per unit volume.
        """
        iptc = 0
        ptcf = DZERO
        var r = self._residual()
        var iptct = 0
        if self.iss > 0:
            iptct = self.npf.inewton
            if self.inewton > 0:
                iptct = self.inewton
        if iptct > 0:
            for n in range(1, self.dis.nodes + 1):  # pragma: no branch
                if self.ibound[n] < 1:
                    continue
                var tp = self.dis.top[n]
                var bt = self.dis.bot[n]
                var sat = squadratic_saturation(tp, bt, tp)
                var v = mul(self.dis.area[n], mul(tp - bt, sat))
                var p = abs(r[n]) / v
                if p > ptcf:
                    ptcf = p
            if ptcf == DZERO:
                ptcf = DONE / mul(self.tdis.delt, DTEN)
            iptc = 1

    def _ls(mut self, kiter: Int, iptc0: Int, ptcf: Float64) -> Int:
        """Prepare and solve the linear system, as `sln_ls` does.

        Args:
            kiter: The outer iteration.
            iptc0: 1 if the model uses pseudo-transient continuation.
            ptcf: The continuation factor.

        Returns:
            The number of inner iterations.
        """
        var nodes = self.dis.nodes
        ref con = self.dis.con
        for ieq in range(1, nodes + 1):  # pragma: no branch
            self.xtemp[ieq] = self.x[ieq]
            var idiag = con.ia[ieq]
            if self.ibound[ieq] > 0:
                var adiag = abs(self.amat[idiag])
                if adiag < DEM15:
                    self.amat[idiag] = -DONE
                    self.rhs[ieq] = self.rhs[ieq] + mul(-DONE, self.x[ieq])
            else:
                self.amat[idiag] = DONE
                for ipos in range(con.ia[ieq] + 1, con.ia[ieq + 1]):
                    self.amat[ipos] = DZERO
                self.rhs[ieq] = self.x[ieq]
        if self.isymmetric == 1:
            for ieq in range(1, nodes + 1):  # pragma: no branch
                if self.ibound[ieq] > 0:
                    for ipos in range(
                        con.ia[ieq], con.ia[ieq + 1]
                    ):  # pragma: no branch
                        var jcol = con.ja[ipos]
                        if jcol == ieq:
                            continue
                        if self.ibound[jcol] < 0:
                            self.rhs[ieq] = self.rhs[ieq] - mul(
                                self.amat[ipos], self.x[jcol]
                            )
                            self.amat[ipos] = DZERO
        var iallowptc = self.nl.iallowptc
        if iallowptc < 0:
            iallowptc = 1 if self.tdis.kper > 1 else 0
        var iptc = iptc0
        var iptct = iptc * iallowptc
        var l2norm = DZERO
        if iptct != 0:
            l2norm = self._l2norm()
            if kiter == 1:
                if self.tdis.kper > 1 or self.tdis.kstp > 1:
                    if l2norm <= self.l2norm0:
                        iptc = 0
            elif is_close(l2norm, self.l2norm0):
                iptc = 0
        iptct = iptc * iallowptc
        if iptct != 0:
            if kiter == 1:
                if self.nl.ptcdel0 > DZERO:
                    self.ptcdel = self.nl.ptcdel0
                elif self.nl.iptcopt == 0:
                    self.ptcdel = DONE / ptcf
                else:
                    var bnorm = DZERO
                    for ieq in range(1, nodes + 1):  # pragma: no branch
                        if self.ibound[ieq] > 0:
                            bnorm = bnorm + mul(self.rhs[ieq], self.rhs[ieq])
                    bnorm = sqrt(bnorm)
                    self.ptcdel = bnorm / l2norm
            elif l2norm > DZERO:
                self.ptcdel = mul(
                    self.ptcdel, cpow(self.l2norm0 / l2norm, self.nl.ptcexp)
                )
            else:
                self.ptcdel = DZERO
            var ptcval = DONE
            if self.ptcdel > DZERO:
                ptcval = DONE / self.ptcdel
            for ieq in range(1, nodes + 1):  # pragma: no branch
                if self.ibound[ieq] > 0:
                    var idiag = con.ia[ieq]
                    self.amat[idiag] = self.amat[idiag] + -ptcval
                    self.rhs[ieq] = self.rhs[ieq] - mul(ptcval, self.x[ieq])
            self.l2norm0 = l2norm
        var res = self.ims.apply(self.amat, self.rhs, self.x, self.tdis.kstp)
        self.icnvg = res[0]
        return res[1]

    def _backtracking(mut self, kiter: Int) raises:
        """Shorten the change while the residual grows, as `sln_backtracking` does.

        Args:
            kiter: The outer iteration.

        Raises:
            Error: A constant head cell went dry.
        """
        self._buildsystem(kiter, 0)
        if kiter == 1:
            self.res_prev = self._l2norm()
            return
        self.res_new = self._l2norm()
        if self.res_new > mul(self.res_prev, self.nl.btol):
            for nb in range(1, self.nl.numtrack + 1):  # pragma: no branch
                var dx_abs_max = DZERO
                for n in range(1, self.dis.nodes + 1):  # pragma: no branch
                    if self.ibound[n] < 1:
                        continue
                    var dx_abs = abs(self.x[n] - self.xtemp[n])
                    if dx_abs > dx_abs_max:
                        dx_abs_max = dx_abs
                if mul(self.nl.breduc, dx_abs_max) < self.nl.dvclose:
                    break
                for n in range(1, self.dis.nodes + 1):  # pragma: no branch
                    if self.ibound[n] < 1:
                        continue
                    var delx = mul(self.nl.breduc, self.x[n] - self.xtemp[n])
                    self.x[n] = self.xtemp[n] + delx
                self._buildsystem(kiter, 0)
                self.res_new = self._l2norm()
                if nb == self.nl.numtrack:
                    break
                if self.res_new < mul(self.res_prev, self.nl.btol):
                    break
                if self.res_new < self.nl.res_lim:
                    break
        self.res_prev = self.res_new

    def _solve(mut self, kiter: Int) raises:
        """Run one outer iteration, as `solve` does.

        Args:
            kiter: The outer iteration.

        Raises:
            Error: A constant head cell went dry.
        """
        if self.nl.numtrack > 0:
            self._backtracking(kiter)
        self._buildsystem(kiter, 1)
        var iptc = 0
        var ptcf = DZERO
        self._calc_ptc(iptc, ptcf)
        var iter = self._ls(kiter, iptc, ptcf)
        self.itertot_sim += iter
        var hncg = self._dxmax()
        if self.icnvg != 0:
            self.icnvg = 0
            if abs(hncg) <= self.nl.dvclose:
                self.icnvg = 1
        if self.icnvg != 1:
            if self.nl.nonmeth.value > 0:
                self._underrelax(kiter, hncg)
            else:
                for n in range(1, self.dis.nodes + 1):  # pragma: no branch
                    if self.ibound[n] < 1:
                        self.dxold[n] = DZERO
                    else:
                        self.dxold[n] = self.x[n] - self.xtemp[n]
            if self.inewton != 0 and self.inewtonur != 0:
                var inewtonur = 0
                var dxmax_nur = DZERO
                var locmax_nur = 0
                self.npf.nur(
                    self.dis,
                    self.ibound,
                    self.x,
                    self.xtemp,
                    self.dxold,
                    inewtonur,
                    dxmax_nur,
                    locmax_nur,
                )
                if inewtonur != 0:
                    var vmax = self._maxval(self.dxold)
                    if (
                        abs(vmax) <= self.nl.dvclose
                        and abs(hncg) <= self.nl.dvclose
                    ):
                        self.icnvg = 1

    def _dxmax(self) -> Float64:
        """Return the largest change of an active head, as `sln_get_dxmax` does.

        Returns:
            The change with its sign.
        """
        var bigch = DZERO
        var abigch = DZERO
        for n in range(1, self.dis.nodes + 1):  # pragma: no branch
            if self.ibound[n] < 1:
                continue
            var hdif = self.x[n] - self.xtemp[n]
            var ahdif = abs(hdif)
            if ahdif > abigch:
                bigch = hdif
                abigch = ahdif
        return bigch

    def _maxval(self, v: List[Float64]) -> Float64:
        """Return the entry of largest magnitude, as `sln_maxval` does.

        Args:
            v: The vector, from index 1.

        Returns:
            The entry.
        """
        var vmax = v[1]
        for n in range(2, self.dis.nodes + 1):
            var d = v[n]
            var denom = abs(vmax)
            if denom == DZERO:
                denom = DPREC
            if abs(d) / denom > DONE:
                vmax = d
        return vmax

    def _underrelax(mut self, kiter: Int, bigch: Float64):
        """Under-relax the change of the heads, as `sln_underrelax` does.

        Args:
            kiter: The outer iteration.
            bigch: The largest change.
        """
        var nodes = self.dis.nodes
        var g = self.nl.gamma
        if self.nl.nonmeth == UNDER_RELAXATION_SIMPLE:
            for n in range(1, nodes + 1):  # pragma: no branch
                if self.ibound[n] < 1:
                    continue
                var delx = self.x[n] - self.xtemp[n]
                self.dxold[n] = delx
                self.x[n] = self.xtemp[n] + mul(g, delx)
        elif self.nl.nonmeth == UNDER_RELAXATION_COOLEY:
            self.bigch = bigch
            var relax: Float64
            if kiter == 1:
                relax = DONE
                self.relaxold = DONE
                self.bigchold = bigch
            else:
                var es = self.bigch / mul(self.bigchold, self.relaxold)
                var aes = abs(es)
                if es < -DONE:
                    relax = DHALF / aes
                else:
                    relax = (DTHREE + es) / (DTHREE + aes)
            self.relaxold = relax
            self.bigchold = mul(DONE - g, self.bigch) + mul(g, self.bigchold)
            if relax < DONE:
                for n in range(1, nodes + 1):  # pragma: no branch
                    if self.ibound[n] < 1:
                        continue
                    var delx = self.x[n] - self.xtemp[n]
                    self.dxold[n] = delx
                    self.x[n] = self.xtemp[n] + mul(relax, delx)
        else:
            # UNDER_RELAXATION_DBD, the last valid kind.
            for n in range(1, nodes + 1):  # pragma: no branch
                if self.ibound[n] < 1:
                    continue
                var delx = self.x[n] - self.xtemp[n]
                if kiter == 1:
                    self.wsave[n] = DONE
                    self.hchold[n] = DEM20
                    self.deold[n] = DZERO
                var ww: Float64
                if mul(self.deold[n], delx) < DZERO:
                    ww = mul(self.nl.theta, self.wsave[n])
                else:
                    ww = self.wsave[n] + self.nl.akappa
                if ww > DONE:
                    ww = DONE
                self.wsave[n] = ww
                if kiter == 1:
                    self.hchold[n] = delx
                else:
                    self.hchold[n] = mul(DONE - g, delx) + mul(
                        g, self.hchold[n]
                    )
                self.deold[n] = delx
                self.dxold[n] = delx
                var amom = DZERO
                if kiter > 4:
                    amom = self.nl.amomentum
                delx = mul(delx, ww) + mul(amom, self.hchold[n])
                self.x[n] = self.xtemp[n] + delx

    def _cq(mut self):
        """Compute the flows of the step, as `gwf_cq` does."""
        for i in range(len(self.flowja)):  # pragma: no branch
            self.flowja[i] = DZERO
        self.npf.cq(self.dis, self.ibound, self.x, self.flowja)
        if self.insto:
            self.sto.cq(
                self.dis,
                self.ibound,
                self.iss,
                self.tdis.delt,
                self.xold,
                self.x,
                self.flowja,
            )
        for i in range(len(self.bnds)):
            self.bnds[i].cf(self.dis, self.ibound, self.x)
            self.bnds[i].cq(self.dis, self.ibound, self.x, self.flowja)

    def _bd(mut self):
        """Sum the flows of each cell and set the constant head flows, as `gwf_bd` does.
        """
        ref con = self.dis.con
        for n in range(1, self.dis.nodes + 1):  # pragma: no branch
            var iposdiag = con.ia[n]
            for ipos in range(con.ia[n] + 1, con.ia[n + 1]):
                self.flowja[iposdiag] = (
                    self.flowja[iposdiag] + self.flowja[ipos]
                )
        for i in range(len(self.bnds)):
            self.bnds[i].chd_rate(self.dis, self.ibound, self.flowja)

    def heads(self) -> List[Float64]:
        """Return the head of each cell, by user node from index 1.

        A cell outside the model has the head 1e30, as the head file of
        MODFLOW 6 has it.

        Returns:
            The heads, in the length unit of the model.
        """
        var out = List[Float64](length=self.dis.nodesuser + 1, fill=DHNOFLO)
        for n in range(1, self.dis.nodes + 1):  # pragma: no branch
            out[self.dis.user(n)] = self.x[n]
        return out^

    def head(self, layer: Int, row: Int, column: Int) raises -> Length64:
        """Return the head of one cell after the last step.

        A model without LENGTH_UNITS is read as meters.

        Args:
            layer: The layer, from 1.
            row: The row, from 1.
            column: The column, from 1.

        Returns:
            The head.

        Raises:
            Error: The cell is outside the grid or the model.
        """
        if (
            layer < 1
            or layer > self.dis.nlay
            or row < 1
            or row > self.dis.nrow
            or column < 1
            or column > self.dis.ncol
        ):
            raise Error("the cell is outside the grid")
        var noder = self.dis.reduced(self.dis.get_node(layer, row, column))
        if noder <= 0:
            raise Error("the cell is not in the model")
        var h = self.x[noder]
        if self.dis.length_units == 1:
            return Length64(h, FOOT64)
        if self.dis.length_units == 3:
            return Length64(h, CENTIMETER64)
        return Length64(h, METER)
