# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from ImsLinear.f90, ImsLinearBase.f90 and ImsLinearSettings.f90 of
# MODFLOW 6.9.0.dev0, commit 59d89e9f, which is in the public domain (CC0).
# See THIRD-PARTY-NOTICES.md.
#
# MODFLOW 6 takes the dot product, the Euclidean norm and the sparse
# product from LGPL libraries that it bundles. They are not ported. `ddot`,
# `dnrm2` and `amux` here are original code from the published algorithms:
# the dot product summed in order, the scaled sum of squares of the
# reference BLAS, and the product of a matrix in compressed rows.

"""The linear solver of IMS: preconditioned conjugate gradient and BiCGSTAB.

The solver scales the matrix, builds an incomplete LU preconditioner and
runs the inner iterations until the change and the residual meet the
inner closure criteria.
"""

from std.math import sqrt

from extensions.groundwater.blocks import InputFile, read_int, read_real
from extensions.groundwater.cmath import fsign, is_close, mul
from extensions.groundwater.constants import (
    DEM1,
    DEM2,
    DEM3,
    DEM4,
    DEM6,
    DHALF,
    DONE,
    DPREC,
    DZERO,
)
from extensions.groundwater.kinds import (
    BICGSTAB,
    CG,
    IPC_ILU0,
    IPC_ILUT,
    IPC_MILU0,
    IPC_MILUT,
    InnerConvergence,
    LinearAcceleration,
    Preconditioner,
    Reordering,
    Scaling,
)


def ddot(n: Int, x: List[Float64], y: List[Float64]) -> Float64:
    """Return the dot product of two vectors, summed in order from index 1.

    Args:
        n: The length.
        x: The first vector, from index 1.
        y: The second vector, from index 1.

    Returns:
        The dot product.
    """
    var s = DZERO
    for i in range(1, n + 1):  # pragma: no branch
        s = s + mul(x[i], y[i])
    return s


def dnrm2(n: Int, x: List[Float64]) -> Float64:
    """Return the Euclidean norm of a vector by a scaled sum of squares.

    The scale is the largest magnitude so far. The sum holds the squares
    of the ratios to it, so that no square overflows.

    Args:
        n: The length.
        x: The vector, from index 1.

    Returns:
        The norm.
    """
    if n < 1:
        return DZERO
    if n == 1:
        return abs(x[1])
    var scale = DZERO
    var ssq = DONE
    for i in range(1, n + 1):  # pragma: no branch
        if x[i] != DZERO:
            var absxi = abs(x[i])
            if scale < absxi:
                var r = scale / absxi
                ssq = DONE + mul(ssq, mul(r, r))
                scale = absxi
            else:
                var r = absxi / scale
                ssq = ssq + mul(r, r)
    return mul(scale, sqrt(ssq))


def amux(
    n: Int,
    x: List[Float64],
    mut y: List[Float64],
    a: List[Float64],
    ja: List[Int],
    ia: List[Int],
):
    """Set y to the product of a matrix in compressed rows and x.

    Each row sums its entries in the order of storage.

    Args:
        n: The number of rows.
        x: The vector, from index 1.
        y: Receives the product.
        a: The entries, from index 1.
        ja: The column of each entry.
        ia: The first entry of each row, and `nja + 1` at `ia[n + 1]`.
    """
    for i in range(1, n + 1):  # pragma: no branch
        var t = DZERO
        for k in range(ia[i], ia[i + 1]):  # pragma: no branch
            t = t + mul(a[k], x[ja[k]])
        y[i] = t


def epfact(icnvgopt: Int, kstp: Int) -> Float64:
    """Return the factor of the relative residual test, as `ims_base_epfact` does.

    The Fortran code writes 0.01 and 0.10 as single precision literals, so
    the factors are those values rounded to single precision.

    Args:
        icnvgopt: The inner convergence test.
        kstp: The time step.

    Returns:
        The factor.
    """
    if icnvgopt == 2:
        if kstp == 1:
            return Float64(Float32(0.01))
        return Float64(Float32(0.10))
    elif icnvgopt == 4:
        return DEM4
    return DONE


def testcnvg(
    icnvgopt: Int,
    mut icnvg: Int,
    iiter: Int,
    dvmax: Float64,
    rmax: Float64,
    rmax0: Float64,
    ep: Float64,
    dvclose: Float64,
    rclose: Float64,
):
    """Test the inner convergence, as `ims_base_testcnvg` does.

    Args:
        icnvgopt: The inner convergence test.
        icnvg: Receives 1 if converged, or -1 to stop without convergence.
        iiter: The inner iteration.
        dvmax: The largest change.
        rmax: The residual measure.
        rmax0: The initial residual norm.
        ep: The relative residual factor.
        dvclose: The closure criterion of the change.
        rclose: The closure criterion of the residual.
    """
    if icnvgopt == 0:
        if abs(dvmax) <= dvclose and abs(rmax) <= rclose:
            icnvg = 1
    elif icnvgopt == 1:
        if abs(dvmax) <= dvclose and abs(rmax) <= rclose:
            if iiter == 1:
                icnvg = 1
            else:
                icnvg = -1
    elif icnvgopt == 2:
        if abs(dvmax) <= dvclose or rmax <= rclose:
            icnvg = 1
        elif rmax <= mul(rmax0, ep):
            icnvg = -1
    elif icnvgopt == 3:
        if abs(dvmax) <= dvclose:
            icnvg = 1
        elif rmax <= mul(rmax0, rclose):
            icnvg = -1
    else:
        # RCLOSE_L2NORM_RELATIVE, the last valid kind.
        if abs(dvmax) <= dvclose and rmax <= rclose:
            icnvg = 1
        elif rmax <= mul(rmax0, ep):
            icnvg = -1


def ilu0a(
    neq: Int,
    apc: List[Float64],
    iapc: List[Int],
    japc: List[Int],
    r: List[Float64],
    mut d: List[Float64],
):
    """Apply the preconditioner: solve L U d = r, as `ims_base_ilu0a` does.

    Args:
        neq: The number of equations.
        apc: The factors.
        iapc: The first off-diagonal entry of each row.
        japc: The first upper entry of each row, then the columns.
        r: The right side.
        d: Receives the solution.
    """
    for n in range(1, neq + 1):  # pragma: no branch
        var tv = r[n]
        for j in range(iapc[n], japc[n]):
            tv = tv - mul(apc[j], d[japc[j]])
        d[n] = tv
    for n in range(neq, 0, -1):  # pragma: no branch
        var iu = japc[n]
        var tv = mul(d[n], apc[n])
        var j = iapc[n + 1] - 1
        while j >= iu:
            tv = tv - mul(apc[j], d[japc[j]])
            j -= 1
        d[n] = tv


def residual(
    neq: Int,
    amat: List[Float64],
    ja: List[Int],
    ia: List[Int],
    x: List[Float64],
    b: List[Float64],
    mut d: List[Float64],
):
    """Set d to b - A x, as `ims_base_residual` does.

    Args:
        neq: The number of equations.
        amat: The matrix.
        ja: The column of each entry.
        ia: The first entry of each row.
        x: The heads.
        b: The right side.
        d: Receives the residual.
    """
    amux(neq, x, d, amat, ja, ia)
    for n in range(1, neq + 1):  # pragma: no branch
        d[n] = b[n] - d[n]


struct LinearSettings(Copyable, Movable):
    """The settings of the LINEAR block of IMS."""

    var dvclose: Float64
    """The inner closure criterion of the change."""
    var rclose: Float64
    """The inner closure criterion of the residual."""
    var icnvgopt: InnerConvergence
    """The inner convergence test."""
    var iter1: Int
    """The largest number of inner iterations."""
    var ilinmeth: LinearAcceleration
    """The Krylov method."""
    var iscl: Scaling
    """The scaling."""
    var iord: Reordering
    """The reordering."""
    var north: Int
    """The inner iterations between recomputations of the residual, or 0."""
    var relax: Float64
    """The relaxation factor of the modified incomplete LU factorization."""
    var level: Int
    """The fill level of ILUT, or 0 for ILU0."""
    var droptol: Float64
    """The drop tolerance of ILUT."""

    def __init__(out self, ifdparam: Int):
        """Make the settings of a complexity, as `preset_config` does.

        Args:
            ifdparam: 1 simple, 2 moderate, 3 complex.
        """
        self.dvclose = DEM3
        self.rclose = DEM1
        self.icnvgopt = InnerConvergence(0)
        self.iter1 = 50
        self.ilinmeth = CG
        self.iscl = Scaling(0)
        self.iord = Reordering(0)
        self.north = 0
        self.relax = DZERO
        self.level = 0
        self.droptol = DZERO
        if ifdparam == 2:
            self.iter1 = 100
            self.ilinmeth = BICGSTAB
            self.dvclose = DEM2
            self.relax = 0.97
        elif ifdparam == 3:
            self.iter1 = 500
            self.ilinmeth = BICGSTAB
            self.dvclose = DEM1
            self.level = 5
            self.droptol = DEM4
            self.north = 2

    def read(mut self, file: InputFile) raises:
        """Read the LINEAR block, as `read_from_file` does.

        Args:
            file: The IMS file.

        Raises:
            Error: A keyword or a value is not known.
        """
        var b = file.find("LINEAR")
        if b < 0:
            return
        for w in file.blocks[b].data_lines():
            var key = w[0].upper()
            var has = len(w) > 1
            if key == "INNER_DVCLOSE" and has:
                self.dvclose = read_real(w[1])
            elif key == "INNER_RCLOSE" and has:
                self.rclose = read_real(w[1])
                if len(w) > 2:
                    var opt = w[2].upper()
                    if opt == "STRICT":
                        self.icnvgopt = InnerConvergence(1)
                    elif opt == "L2NORM_RCLOSE":
                        self.icnvgopt = InnerConvergence(2)
                    elif opt == "RELATIVE_RCLOSE":
                        self.icnvgopt = InnerConvergence(3)
                    elif opt == "L2NORM_RELATIVE_RCLOSE":
                        self.icnvgopt = InnerConvergence(4)
            elif key == "INNER_MAXIMUM" and has:
                self.iter1 = read_int(w[1])
            elif key == "LINEAR_ACCELERATION" and has:
                var m = w[1].upper()
                if m == "CG":
                    self.ilinmeth = CG
                elif m == "BICGSTAB":
                    self.ilinmeth = BICGSTAB
                else:
                    raise Error(
                        String(
                            "Unknown IMSLINEAR LINEAR_ACCELERATION method (",
                            m,
                            ").",
                        )
                    )
            elif key == "SCALING_METHOD" and has:
                var m = w[1].upper()
                if m == "NONE":
                    self.iscl = Scaling(0)
                elif m == "DIAGONAL":
                    self.iscl = Scaling(1)
                elif m == "L2NORM":
                    self.iscl = Scaling(2)
                else:
                    raise Error(
                        String("Unknown IMSLINEAR SCALING_METHOD (", m, ").")
                    )
            elif key == "RED_BLACK_ORDERING":
                self.iord = Reordering(0)
            elif key == "REORDERING_METHOD" and has:
                var m = w[1].upper()
                if m == "NONE":
                    self.iord = Reordering(0)
                elif m == "RCM":
                    self.iord = Reordering(1)
                elif m == "MD":
                    self.iord = Reordering(2)
                else:
                    raise Error(
                        String("Unknown IMSLINEAR REORDERING_METHOD (", m, ").")
                    )
            elif key == "NUMBER_ORTHOGONALIZATIONS" and has:
                self.north = read_int(w[1])
            elif key == "RELAXATION_FACTOR" and has:
                self.relax = read_real(w[1])
            elif key == "PRECONDITIONER_LEVELS" and has:
                self.level = read_int(w[1])
                if self.level < 0:
                    raise Error(
                        "IMSLINEAR PRECONDITIONER_LEVELS must be greater than"
                        " or equal to zero"
                    )
            elif key == "PRECONDITIONER_DROP_TOLERANCE" and has:
                self.droptol = read_real(w[1])
                if self.droptol < DZERO:
                    raise Error(
                        "IMSLINEAR PRECONDITIONER_DROP_TOLERANCE must be"
                        " greater than or equal to zero"
                    )
            else:
                raise Error(String("Unknown IMSLINEAR keyword (", key, ")."))

    def ipc(self) -> Preconditioner:
        """Return the preconditioner of the settings, as `resolve_ipc` does.

        Returns:
            ILUT or MILUT with fill levels, else ILU0 or MILU0.
        """
        if self.level > 0:
            if self.relax > DZERO:
                return IPC_MILUT
            return IPC_ILUT
        if self.relax > DZERO:
            return IPC_MILU0
        return IPC_ILU0


struct ImsLinear(Movable):
    """The linear solver and its work arrays."""

    var s: LinearSettings
    """The settings."""
    var ipc: Preconditioner
    """The preconditioner."""
    var neq: Int
    """The number of equations."""
    var nja: Int
    """The number of entries of the matrix."""
    var ia: List[Int]
    """The first entry of each row."""
    var ja: List[Int]
    """The column of each entry."""
    var apc: List[Float64]
    """The preconditioner: the inverse diagonal, then the off-diagonal entries."""
    var iapc: List[Int]
    """The first off-diagonal entry of each row of the preconditioner."""
    var japc: List[Int]
    """The first upper entry of each row, then the column of each entry."""
    var iw: List[Int]
    """Work flags of the factorization."""
    var w: List[Float64]
    """Work values of the factorization."""
    var dscale: List[Float64]
    """The row scale."""
    var dscale2: List[Float64]
    """The column scale."""
    var rscale: List[Float64]
    """The scale of the residual."""
    var hscale: List[Float64]
    """The scale of the change."""
    var l2norm0: Float64
    """The norm of the residual at the start of the solve."""

    def __init__(
        out self, var s: LinearSettings, ia: List[Int], ja: List[Int]
    ) raises:
        """Set up the solver for a matrix structure, as `imslinear_ar` does.

        Args:
            s: The settings.
            ia: The first entry of each row, from index 1.
            ja: The column of each entry, from index 1.

        Raises:
            Error: A setting is not supported or out of range.
        """
        self.ipc = s.ipc()
        if self.ipc == IPC_ILUT or self.ipc == IPC_MILUT:
            raise Error("ILUT preconditioning is not supported")
        if s.iord.value != 0:
            raise Error("matrix reordering is not supported")
        if s.relax < DZERO or s.relax > DONE:
            raise Error("IMSLINEAR RELAXATION_FACTOR must be from 0 to 1")
        if s.north < 0:
            raise Error("IMSLINEAR NUMBER_ORTHOGONALIZATIONS must be >= 0")
        self.s = s^
        self.neq = len(ia) - 2
        self.nja = ia[self.neq + 1] - 1
        self.ia = ia.copy()
        self.ja = ja.copy()
        var neq = self.neq
        var nja = self.nja
        self.apc = List[Float64](length=nja + 1, fill=0.0)
        self.iapc = List[Int](length=neq + 2, fill=0)
        self.japc = List[Int](length=nja + 1, fill=0)
        self.iw = List[Int](length=neq + 1, fill=0)
        self.w = List[Float64](length=neq + 1, fill=0.0)
        self.dscale = List[Float64](length=neq + 1, fill=1.0)
        self.dscale2 = List[Float64](length=neq + 1, fill=1.0)
        self.rscale = List[Float64](length=neq + 1, fill=1.0)
        self.hscale = List[Float64](length=neq + 1, fill=1.0)
        self.l2norm0 = DZERO
        self._pccrs()

    def _pccrs(mut self):
        """Build the structure of the preconditioner, as `ims_base_pccrs` does.
        """
        # MODFLOW 6 sorts the columns of each row. The columns of a DIS grid
        # after the diagonal are in increasing order already, so the port
        # keeps their order.
        var neq = self.neq
        var ip = neq + 1
        for n in range(1, neq + 1):  # pragma: no branch
            self.iapc[n] = ip
            for j in range(self.ia[n] + 1, self.ia[n + 1]):
                self.japc[ip] = self.ja[j]
                ip += 1
        self.iapc[neq + 1] = self.nja + 1
        for n in range(1, neq + 1):  # pragma: no branch
            var i0 = self.iapc[n]
            var i1 = self.iapc[n + 1]
            self.japc[n] = i1
            for j in range(i0, i1):
                if self.japc[j] > n:
                    self.japc[n] = j
                    break

    def _scale(
        mut self,
        iopt: Int,
        mut amat: List[Float64],
        mut x: List[Float64],
        mut b: List[Float64],
    ):
        """Scale the system, or undo the scaling, as `ims_base_scale` does.

        Args:
            iopt: 0 to scale, 1 to undo.
            amat: The matrix.
            x: The heads.
            b: The right side.
        """
        var neq = self.neq
        if iopt == 0:
            if self.s.iscl.value == 1:
                for n in range(1, neq + 1):  # pragma: no branch
                    var c1 = DONE / sqrt(abs(amat[self.ia[n]]))
                    self.dscale[n] = c1
                    self.dscale2[n] = c1
                for n in range(1, neq + 1):  # pragma: no branch
                    var c1 = self.dscale[n]
                    for i in range(
                        self.ia[n], self.ia[n + 1]
                    ):  # pragma: no branch
                        var c2 = self.dscale2[self.ja[i]]
                        amat[i] = mul(mul(c1, amat[i]), c2)
            else:
                for n in range(1, neq + 1):  # pragma: no branch
                    var c1 = DZERO
                    for i in range(
                        self.ia[n], self.ia[n + 1]
                    ):  # pragma: no branch
                        c1 = c1 + mul(amat[i], amat[i])
                    c1 = sqrt(c1)
                    if c1 == DZERO:
                        c1 = DONE
                    else:
                        c1 = DONE / c1
                    self.dscale[n] = c1
                    for i in range(
                        self.ia[n], self.ia[n + 1]
                    ):  # pragma: no branch
                        amat[i] = mul(c1, amat[i])
                for n in range(1, neq + 1):  # pragma: no branch
                    self.dscale2[n] = DZERO
                for n in range(1, neq + 1):  # pragma: no branch
                    for i in range(
                        self.ia[n], self.ia[n + 1]
                    ):  # pragma: no branch
                        var jc = self.ja[i]
                        var c2 = amat[i]
                        self.dscale2[jc] = self.dscale2[jc] + mul(c2, c2)
                for n in range(1, neq + 1):  # pragma: no branch
                    var c2 = self.dscale2[n]
                    if c2 == DZERO:
                        c2 = DONE
                    else:
                        c2 = DONE / sqrt(c2)
                    self.dscale2[n] = c2
                for n in range(1, neq + 1):  # pragma: no branch
                    for i in range(
                        self.ia[n], self.ia[n + 1]
                    ):  # pragma: no branch
                        amat[i] = mul(self.dscale2[self.ja[i]], amat[i])
            for n in range(1, neq + 1):  # pragma: no branch
                x[n] = x[n] / self.dscale2[n]
                b[n] = mul(b[n], self.dscale[n])
        else:
            for n in range(1, neq + 1):  # pragma: no branch
                var c1 = self.dscale[n]
                for i in range(self.ia[n], self.ia[n + 1]):  # pragma: no branch
                    var c2 = self.dscale2[self.ja[i]]
                    amat[i] = mul(mul(DONE / c1, amat[i]), DONE / c2)
                x[n] = mul(x[n], self.dscale2[n])
                b[n] = b[n] / c1

    def _pcilu0(
        mut self, amat: List[Float64], mut ipcflag: Int, delta: Float64
    ):
        """Factor the incomplete LU preconditioner, as `ims_base_pcilu0` does.

        Args:
            amat: The matrix.
            ipcflag: Receives 1 if a pivot has the wrong sign or is zero.
                With 2 or more, such a pivot becomes 1e-6 with the sign of
                the diagonal.
            delta: The factor added to the diagonal.
        """
        var neq = self.neq
        var drelax = self.s.relax
        for n in range(1, neq + 1):  # pragma: no branch
            self.iw[n] = 0
            self.w[n] = DZERO
        var finished = True
        for n in range(1, neq + 1):  # pragma: no branch
            for j in range(self.ia[n], self.ia[n + 1]):  # pragma: no branch
                var jcol = self.ja[j]
                self.iw[jcol] = 1
                self.w[jcol] = self.w[jcol] + amat[j]
            var ic0 = self.iapc[n]
            var ic1 = self.iapc[n + 1]
            var iu = self.japc[n]
            var rs = DZERO
            for j in range(ic0, iu):
                var jcol = self.japc[j]
                var iic1 = self.iapc[jcol + 1]
                var iiu = self.japc[jcol]
                var tl = mul(self.w[jcol], self.apc[jcol])
                self.w[jcol] = tl
                # The pattern is symmetric, so row jcol < n holds n after
                # its diagonal.
                for jj in range(iiu, iic1):  # pragma: no branch
                    var jjcol = self.japc[jj]
                    if self.iw[jjcol] != 0:
                        self.w[jjcol] = self.w[jjcol] - mul(tl, self.apc[jj])
                    else:
                        rs = rs + mul(tl, self.apc[jj])
            var d = self.w[n]
            var tl = mul(DONE + delta, d) - mul(drelax, rs)
            var sd1 = fsign(d, tl)
            if sd1 != d:
                if ipcflag > 1:
                    tl = fsign(DEM6, d)
                else:
                    ipcflag = 1
                    finished = False
                    break
            if abs(tl) == DZERO:
                if ipcflag > 1:
                    tl = fsign(DEM6, d)
                else:
                    ipcflag = 1
                    finished = False
                    break
            self.apc[n] = DONE / tl
            self.iw[n] = 0
            self.w[n] = DZERO
            for j in range(ic0, ic1):
                var jcol = self.japc[j]
                self.apc[j] = self.w[jcol]
                self.iw[jcol] = 0
                self.w[jcol] = DZERO
        if finished:
            for n in range(1, neq + 1):  # pragma: no branch
                for j in range(self.japc[n], self.iapc[n + 1]):
                    self.apc[j] = mul(self.apc[j], self.apc[n])
            ipcflag = 0

    def _pcu(mut self, amat: List[Float64]):
        """Factor the preconditioner, adding to the diagonal until it works, as `ims_base_pcu` does.

        Args:
            amat: The matrix.
        """
        # MODFLOW 6 also caps delta at 0.5 and stops after 11 tries. Delta is
        # about 0.11 at the tenth try, and that try sets every bad pivot to
        # 1e-6, so neither limit is reached.
        var ipcflag = 0
        var icount = 0
        var delta = DZERO
        while True:
            self._pcilu0(amat, ipcflag, delta)
            if ipcflag < 1:
                break
            delta = mul(1.5, delta) + DEM3
            ipcflag = 0
            icount += 1
            if icount == 10:
                ipcflag = 2

    def apply(
        mut self,
        mut amat: List[Float64],
        mut rhs: List[Float64],
        mut x: List[Float64],
        kstp: Int,
    ) -> Tuple[Int, Int]:
        """Solve the linear system, as `imslinear_ap` does.

        Args:
            amat: The matrix. It is scaled and then restored.
            rhs: The right side.
            x: The heads. Receives the solution.
            kstp: The time step.

        Returns:
            The convergence flag and the number of inner iterations.
        """
        var neq = self.neq
        var ep = epfact(self.s.icnvgopt.value, kstp)
        if self.s.iscl.value != 0:
            self._scale(0, amat, x, rhs)
            for n in range(1, neq + 1):  # pragma: no branch
                self.rscale[n] = DONE / self.dscale[n]
                self.hscale[n] = self.dscale2[n]
        self._pcu(amat)
        var icnvg = 0
        var d = List[Float64](length=neq + 1, fill=0.0)
        residual(neq, amat, self.ja, self.ia, x, rhs, d)
        if self.s.iscl.value != 0:
            var s = DZERO
            for n in range(1, neq + 1):  # pragma: no branch
                var r = mul(d[n], self.rscale[n])
                s = s + mul(r, r)
            self.l2norm0 = sqrt(s)
        else:
            self.l2norm0 = dnrm2(neq, d)
        var itmax = self.s.iter1
        if self.l2norm0 == DZERO:
            itmax = 0
            icnvg = 1
        var innerit: Int
        if self.s.ilinmeth == CG:
            innerit = self._cg(amat, x, rhs, d, itmax, ep, icnvg)
        else:
            innerit = self._bcgs(amat, x, rhs, d, itmax, ep, icnvg)
        if self.s.iscl.value != 0:
            self._scale(1, amat, x, rhs)
        return (icnvg, innerit)

    def _cg(
        self,
        amat: List[Float64],
        mut x: List[Float64],
        b: List[Float64],
        mut d: List[Float64],
        itmax: Int,
        ep: Float64,
        mut icnvg: Int,
    ) -> Int:
        """Run the preconditioned conjugate gradient iterations, as `ims_base_cg` does.

        Args:
            amat: The matrix.
            x: The heads.
            b: The right side.
            d: The residual. Receives the final residual.
            itmax: The largest number of iterations.
            ep: The relative residual factor.
            icnvg: Receives 1 if converged.

        Returns:
            The number of inner iterations.
        """
        var neq = self.neq
        var iscl = self.s.iscl.value
        var rho0 = DZERO
        var innerit = 0
        var p = List[Float64](length=neq + 1, fill=0.0)
        var q = List[Float64](length=neq + 1, fill=0.0)
        var z = List[Float64](length=neq + 1, fill=0.0)
        for iiter in range(1, itmax + 1):
            innerit += 1
            ilu0a(neq, self.apc, self.iapc, self.japc, d, z)
            var rho = ddot(neq, d, z)
            if iiter == 1:
                for n in range(1, neq + 1):  # pragma: no branch
                    p[n] = z[n]
            else:
                var beta = rho / rho0
                for n in range(1, neq + 1):  # pragma: no branch
                    p[n] = z[n] + mul(beta, p[n])
            amux(neq, p, q, amat, self.ja, self.ia)
            var denominator = ddot(neq, p, q)
            denominator = denominator + fsign(DPREC, denominator)
            var alpha = rho / denominator
            var deltax = DZERO
            var rmax = DZERO
            var l2norm = DZERO
            for n in range(1, neq + 1):  # pragma: no branch
                var tv = mul(alpha, p[n])
                x[n] = x[n] + tv
                if iscl != 0:
                    tv = mul(tv, self.hscale[n])
                if abs(tv) > abs(deltax):
                    deltax = tv
                tv = d[n]
                tv = tv - mul(alpha, q[n])
                d[n] = tv
                if iscl != 0:
                    tv = mul(tv, self.rscale[n])
                if abs(tv) > abs(rmax):
                    rmax = tv
                l2norm = l2norm + mul(tv, tv)
            l2norm = sqrt(l2norm)
            var opt = self.s.icnvgopt.value
            var rcnvg = rmax
            if opt == 2 or opt == 3 or opt == 4:
                rcnvg = l2norm
            testcnvg(
                opt,
                icnvg,
                innerit,
                deltax,
                rcnvg,
                self.l2norm0,
                ep,
                self.s.dvclose,
                self.s.rclose,
            )
            if rcnvg == DZERO:
                icnvg = 1
            if icnvg != 0:
                break
            if is_close(rho, rho0):
                break
            if self.s.north > 0:
                if (iiter + 1) % self.s.north == 0:
                    residual(neq, amat, self.ja, self.ia, x, b, d)
            if rho == DZERO:
                break
            rho0 = rho
        if icnvg < 0:
            icnvg = 0
        return innerit

    def _bcgs(
        self,
        amat: List[Float64],
        mut x: List[Float64],
        b: List[Float64],
        mut d: List[Float64],
        itmax: Int,
        ep: Float64,
        mut icnvg: Int,
    ) -> Int:
        """Run the preconditioned BiCGSTAB iterations, as `ims_base_bcgs` does.

        Args:
            amat: The matrix.
            x: The heads.
            b: The right side.
            d: The residual. Receives the final residual.
            itmax: The largest number of iterations.
            ep: The relative residual factor.
            icnvg: Receives 1 if converged.

        Returns:
            The number of inner iterations.
        """
        var neq = self.neq
        var iscl = self.s.iscl.value
        var innerit = 0
        var alpha0 = DZERO
        var rho0 = DZERO
        var omega0 = DZERO
        var p = List[Float64](length=neq + 1, fill=0.0)
        var q = List[Float64](length=neq + 1, fill=0.0)
        var t = List[Float64](length=neq + 1, fill=0.0)
        var v = List[Float64](length=neq + 1, fill=0.0)
        var phat = List[Float64](length=neq + 1, fill=0.0)
        var qhat = List[Float64](length=neq + 1, fill=0.0)
        var dhat = d.copy()
        for iiter in range(1, itmax + 1):
            innerit += 1
            var rho = ddot(neq, dhat, d)
            if iiter == 1:
                for n in range(1, neq + 1):  # pragma: no branch
                    p[n] = d[n]
            else:
                var beta = mul(rho / rho0, alpha0 / omega0)
                for n in range(1, neq + 1):  # pragma: no branch
                    p[n] = d[n] + mul(beta, p[n] - mul(omega0, v[n]))
            ilu0a(neq, self.apc, self.iapc, self.japc, p, phat)
            amux(neq, phat, v, amat, self.ja, self.ia)
            var denominator = ddot(neq, dhat, v)
            denominator = denominator + fsign(DPREC, denominator)
            var alpha = rho / denominator
            for n in range(1, neq + 1):  # pragma: no branch
                q[n] = d[n] - mul(alpha, v[n])
            ilu0a(neq, self.apc, self.iapc, self.japc, q, qhat)
            amux(neq, qhat, t, amat, self.ja, self.ia)
            var numerator = ddot(neq, t, q)
            denominator = ddot(neq, t, t)
            denominator = denominator + fsign(DPREC, denominator)
            var omega = numerator / denominator
            var deltax = DZERO
            var rmax = DZERO
            var l2norm = DZERO
            for n in range(1, neq + 1):  # pragma: no branch
                var tv = mul(alpha, phat[n]) + mul(omega, qhat[n])
                x[n] = x[n] + tv
                if iscl != 0:
                    tv = mul(tv, self.hscale[n])
                if abs(tv) > abs(deltax):
                    deltax = tv
                tv = q[n] - mul(omega, t[n])
                d[n] = tv
                if iscl != 0:
                    tv = mul(tv, self.rscale[n])
                if abs(tv) > abs(rmax):
                    rmax = tv
                l2norm = l2norm + mul(tv, tv)
            l2norm = sqrt(l2norm)
            var opt = self.s.icnvgopt.value
            var rcnvg = rmax
            if opt == 2 or opt == 3 or opt == 4:
                rcnvg = l2norm
            testcnvg(
                opt,
                icnvg,
                innerit,
                deltax,
                rcnvg,
                self.l2norm0,
                ep,
                self.s.dvclose,
                self.s.rclose,
            )
            if rcnvg == DZERO:
                icnvg = 1
            if icnvg != 0:
                break
            if is_close(rho, rho0):
                break
            if is_close(alpha, alpha0):
                break
            if is_close(omega, omega0):
                break
            if self.s.north > 0:
                if (iiter + 1) % self.s.north == 0:
                    residual(neq, amat, self.ja, self.ia, x, b, d)
            if mul(rho, omega) == DZERO:
                break
            rho0 = rho
            alpha0 = alpha
            omega0 = omega
        if icnvg < 0:
            icnvg = 0
        return innerit
