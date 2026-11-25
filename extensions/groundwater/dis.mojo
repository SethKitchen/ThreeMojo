# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from Dis.f90, Connections.f90 and Sparse.f90 of MODFLOW 6.9.0.dev0,
# commit 59d89e9f, which is in the public domain (CC0). See
# THIRD-PARTY-NOTICES.md.

"""The structured grid of a groundwater flow model, and its connections.

A `Dis` has `nlay` layers of `nrow` rows and `ncol` columns. A user node
counts the cells layer by layer, row by row, from 1. A cell with an
`idomain` of 0 or less is not in the model. The other cells are the
reduced nodes, counted in the same order. A cell with an `idomain` of -1
passes vertical flow between the cells above and below it.

`Connections` holds the matrix structure in compressed rows, as MODFLOW
6 stores it. Row n starts with its diagonal, then lists the cells that n
connects to, in the order above, back, left, right, front, below. The
two entries of a connection share a symmetric index, `jas`, into the
arrays of the connection: `ihc`, `cl1`, `cl2` and `hwva`.
"""

from extensions.groundwater.blocks import (
    InputFile,
    read_grid_ints,
    read_grid_reals,
    read_int,
)
from extensions.groundwater.cmath import mul
from extensions.groundwater.constants import DHALF, DPI, DTHREE, DTWO, DZERO

# The kinds of a connection, `ihc`.
comptime C3D_VERTICAL = 0
comptime C3D_HORIZONTAL = 1


struct Connections(Movable):
    """The connections between the reduced nodes of a grid."""

    var nodes: Int
    """The number of reduced nodes."""
    var nja: Int
    """The number of entries of the matrix, diagonals included."""
    var njas: Int
    """The number of connections, each counted once."""
    var ia: List[Int]
    """The start of each row in `ja`, from 1. `ia[nodes + 1]` ends the last row."""
    var ja: List[Int]
    """The node of each entry. Each row starts with its diagonal."""
    var isym: List[Int]
    """The entry of the same connection in the row of the other node."""
    var jas: List[Int]
    """The symmetric index of each entry, or 0 for a diagonal."""
    var ihc: List[Int]
    """The kind of each connection: 0 vertical, 1 horizontal."""
    var cl1: List[Float64]
    """The distance from the center of the lower node to the face."""
    var cl2: List[Float64]
    """The distance from the center of the higher node to the face."""
    var hwva: List[Float64]
    """The width of a horizontal face, or the area of a vertical one."""
    var anglex: List[Float64]
    """The angle of the normal of each face from the x axis."""

    def __init__(out self):
        """Make an empty set of connections."""
        self.nodes = 0
        self.nja = 0
        self.njas = 0
        self.ia = List[Int]()
        self.ja = List[Int]()
        self.isym = List[Int]()
        self.jas = List[Int]()
        self.ihc = List[Int]()
        self.cl1 = List[Float64]()
        self.cl2 = List[Float64]()
        self.hwva = List[Float64]()
        self.anglex = List[Float64]()


struct Dis(Movable):
    """A structured grid of layers, rows and columns."""

    var nlay: Int
    """The number of layers."""
    var nrow: Int
    """The number of rows."""
    var ncol: Int
    """The number of columns."""
    var nodesuser: Int
    """The number of cells: nlay * nrow * ncol."""
    var nodes: Int
    """The number of reduced nodes: the cells in the model."""
    var length_units: Int
    """The length unit of the input: 0 unknown, 1 feet, 2 meters, 3 centimeters."""
    var delr: List[Float64]
    """The width of each column, from index 1."""
    var delc: List[Float64]
    """The width of each row, from index 1."""
    var top2d: List[Float64]
    """The top of the model at each cell of a layer, by user node of layer 1."""
    var bot3d: List[Float64]
    """The bottom of each cell, by user node."""
    var idomain: List[Int]
    """The domain of each cell, by user node."""
    var nodereduced: List[Int]
    """The reduced node of each user node, or 0 or -1. Empty when no cell is out."""
    var nodeuser: List[Int]
    """The user node of each reduced node. Empty when no cell is out."""
    var top: List[Float64]
    """The top of each reduced node."""
    var bot: List[Float64]
    """The bottom of each reduced node."""
    var area: List[Float64]
    """The area of each reduced node."""
    var con: Connections
    """The connections."""

    def __init__(out self):
        """Make an empty grid."""
        self.nlay = 0
        self.nrow = 0
        self.ncol = 0
        self.nodesuser = 0
        self.nodes = 0
        self.length_units = 0
        self.delr = List[Float64]()
        self.delc = List[Float64]()
        self.top2d = List[Float64]()
        self.bot3d = List[Float64]()
        self.idomain = List[Int]()
        self.nodereduced = List[Int]()
        self.nodeuser = List[Int]()
        self.top = List[Float64]()
        self.bot = List[Float64]()
        self.area = List[Float64]()
        self.con = Connections()

    def read(mut self, file: InputFile) raises:
        """Read a DIS6 file and build the grid, as `dis_df` does.

        Args:
            file: The file.

        Raises:
            Error: A dimension or an array is missing or wrong.
        """
        var b = file.find("OPTIONS")
        if b >= 0:
            for w in file.blocks[b].data_lines():
                if w[0].upper() == "LENGTH_UNITS" and len(w) > 1:
                    var u = w[1].upper()
                    if u == "FEET":
                        self.length_units = 1
                    elif u == "METERS":
                        self.length_units = 2
                    elif u == "CENTIMETERS":
                        self.length_units = 3
                    else:
                        self.length_units = 0
        b = file.find("DIMENSIONS")
        if b < 0:
            raise Error("DIS has no DIMENSIONS block")
        self.nlay = 1
        self.nrow = 1
        self.ncol = 1
        for w in file.blocks[b].data_lines():
            var key = w[0].upper()
            if len(w) < 2:
                continue
            if key == "NLAY":
                self.nlay = read_int(w[1])
            elif key == "NROW":
                self.nrow = read_int(w[1])
            elif key == "NCOL":
                self.ncol = read_int(w[1])
        if self.nlay < 1:
            raise Error("NLAY was not specified or was specified incorrectly.")
        if self.nrow < 1:
            raise Error("NROW was not specified or was specified incorrectly.")
        if self.ncol < 1:
            raise Error("NCOL was not specified or was specified incorrectly.")
        self.nodesuser = self.nlay * self.nrow * self.ncol
        b = file.find("GRIDDATA")
        if b < 0:
            raise Error("DIS has no GRIDDATA block")
        ref g = file.blocks[b]
        self.delr = read_grid_reals(file, g, "DELR", 1, self.ncol)
        self.delc = read_grid_reals(file, g, "DELC", 1, self.nrow)
        self.top2d = read_grid_reals(file, g, "TOP", 1, self.nrow * self.ncol)
        self.bot3d = read_grid_reals(
            file, g, "BOTM", self.nlay, self.nrow * self.ncol
        )
        self.idomain = read_grid_ints(
            file, g, "IDOMAIN", self.nlay, self.nrow * self.ncol
        )
        if len(self.delr) == 0:
            raise Error("DELR not found.")
        if len(self.delc) == 0:
            raise Error("DELC not found.")
        if len(self.top2d) == 0:
            raise Error("TOP not found.")
        if len(self.bot3d) == 0:
            raise Error("BOTM not found.")
        if len(self.idomain) == 0:
            self.idomain = List[Int](length=self.nodesuser + 1, fill=1)
        for j in range(1, self.ncol + 1):  # pragma: no branch
            if self.delr[j] <= DZERO:
                raise Error(String("DELR(", j, ") must be greater than zero."))
        for i in range(1, self.nrow + 1):  # pragma: no branch
            if self.delc[i] <= DZERO:
                raise Error(String("DELC(", i, ") must be greater than zero."))
        var err = self.finalize()
        if err.byte_length() > 0:
            raise Error(err)

    def get_node(self, k: Int, i: Int, j: Int) -> Int:
        """Return the user node of a layer, a row and a column.

        Args:
            k: The layer, from 1.
            i: The row, from 1.
            j: The column, from 1.

        Returns:
            The user node, from 1.
        """
        return (k - 1) * self.nrow * self.ncol + (i - 1) * self.ncol + j

    def reduced(self, nodeu: Int) -> Int:
        """Return the reduced node of a user node.

        Args:
            nodeu: The user node.

        Returns:
            The reduced node, or 0 or less if the cell is not in the model.
        """
        if self.nodes < self.nodesuser:
            return self.nodereduced[nodeu]
        return nodeu

    def user(self, noder: Int) -> Int:
        """Return the user node of a reduced node.

        Args:
            noder: The reduced node.

        Returns:
            The user node.
        """
        if self.nodes < self.nodesuser:
            return self.nodeuser[noder]
        return noder

    def finalize(mut self) -> String:
        """Count the reduced nodes and build the connections.

        `delr`, `delc`, `top2d`, `bot3d` and `idomain` must be set.

        Returns:
            An empty text, or the text of an error.
        """
        var n = 0
        for nodeu in range(1, self.nodesuser + 1):  # pragma: no branch
            if self.idomain[nodeu] > 0:
                n += 1
        self.nodes = n
        if self.nodes == 0:
            return (
                "Model does not have any active nodes. Ensure IDOMAIN array"
                " has some values greater than zero."
            )
        var ncpl = self.nrow * self.ncol
        for k in range(1, self.nlay + 1):  # pragma: no branch
            for c in range(1, ncpl + 1):  # pragma: no branch
                var nodeu = (k - 1) * ncpl + c
                if self.idomain[nodeu] < 1:
                    continue
                var tp = self.top2d[c]
                if k > 1:
                    tp = self.bot3d[nodeu - ncpl]
                if tp - self.bot3d[nodeu] <= DZERO:
                    var i = (c - 1) // self.ncol + 1
                    var j = (c - 1) % self.ncol + 1
                    return String(
                        "CELL (",
                        k,
                        ",",
                        i,
                        ",",
                        j,
                        ") THICKNESS <= 0.",
                    )
        self.nodereduced = List[Int]()
        self.nodeuser = List[Int]()
        if self.nodes < self.nodesuser:
            self.nodereduced = List[Int](length=self.nodesuser + 1, fill=0)
            self.nodeuser = List[Int](length=self.nodes + 1, fill=0)
            var noder = 1
            for nodeu in range(1, self.nodesuser + 1):  # pragma: no branch
                if self.idomain[nodeu] > 0:
                    self.nodereduced[nodeu] = noder
                    self.nodeuser[noder] = nodeu
                    noder += 1
                elif self.idomain[nodeu] < 0:
                    self.nodereduced[nodeu] = -1
        self.top = List[Float64](length=self.nodes + 1, fill=0.0)
        self.bot = List[Float64](length=self.nodes + 1, fill=0.0)
        self.area = List[Float64](length=self.nodes + 1, fill=0.0)
        for k in range(1, self.nlay + 1):  # pragma: no branch
            for i in range(1, self.nrow + 1):  # pragma: no branch
                for j in range(1, self.ncol + 1):  # pragma: no branch
                    var nodeu = self.get_node(k, i, j)
                    var noder = self.reduced(nodeu)
                    if noder <= 0:
                        continue
                    var c = (i - 1) * self.ncol + j
                    var tp = self.top2d[c]
                    if k > 1:
                        tp = self.bot3d[nodeu - ncpl]
                    self.top[noder] = tp
                    self.bot[noder] = self.bot3d[nodeu]
                    self.area[noder] = mul(self.delr[j], self.delc[i])
        self._connect()
        return String()

    def _mr(self, k: Int, i: Int, j: Int) -> Int:
        """Return the reduced node of a cell, as `nrdcd_ptr` or `get_node` gives it.
        """
        return self.reduced(self.get_node(k, i, j))

    def _above(self, k: Int, i: Int, j: Int) -> Int:
        """Return the cell above that a vertical connection reaches, or 0 or less.
        """
        var mr = 0
        var kk = k - 1
        while kk >= 1:  # pragma: no branch
            mr = self._mr(kk, i, j)
            if mr >= 0:
                break
            kk -= 1
        return mr

    def _below(self, k: Int, i: Int, j: Int) -> Int:
        """Return the cell below that a vertical connection reaches, or 0 or less.
        """
        var mr = 0
        var kk = k + 1
        while kk <= self.nlay:  # pragma: no branch
            mr = self._mr(kk, i, j)
            if mr >= 0:
                break
            kk += 1
        return mr

    def _connect(mut self):
        """Build the connections, as `disconnections` does."""
        var rows = List[List[Int]]()
        for _ in range(self.nodes + 1):  # pragma: no branch
            rows.append(List[Int]())
        for k in range(1, self.nlay + 1):  # pragma: no branch
            for i in range(1, self.nrow + 1):  # pragma: no branch
                for j in range(1, self.ncol + 1):  # pragma: no branch
                    var nr = self._mr(k, i, j)
                    if nr <= 0:
                        continue
                    rows[nr].append(nr)
                    if k > 1:
                        var mr = self._above(k, i, j)
                        if mr > 0:
                            rows[nr].append(mr)
                    if i > 1:
                        var mr = self._mr(k, i - 1, j)
                        if mr > 0:
                            rows[nr].append(mr)
                    if j > 1:
                        var mr = self._mr(k, i, j - 1)
                        if mr > 0:
                            rows[nr].append(mr)
                    if j < self.ncol:
                        var mr = self._mr(k, i, j + 1)
                        if mr > 0:
                            rows[nr].append(mr)
                    if i < self.nrow:
                        var mr = self._mr(k, i + 1, j)
                        if mr > 0:
                            rows[nr].append(mr)
                    if k < self.nlay:
                        var mr = self._below(k, i, j)
                        if mr > 0:
                            rows[nr].append(mr)
        var con = Connections()
        con.nodes = self.nodes
        con.ia = List[Int](length=self.nodes + 2, fill=0)
        con.ja = List[Int]()
        con.ja.append(0)
        var ipos = 1
        con.ia[1] = 1
        for n in range(1, self.nodes + 1):  # pragma: no branch
            for m in rows[n]:  # pragma: no branch
                con.ja.append(m)
                ipos += 1
            con.ia[n + 1] = ipos
        con.nja = ipos - 1
        con.njas = (con.nja - self.nodes) // 2
        con.isym = List[Int](length=con.nja + 1, fill=0)
        con.jas = List[Int](length=con.nja + 1, fill=0)
        for n in range(1, self.nodes + 1):  # pragma: no branch
            for ii in range(con.ia[n], con.ia[n + 1]):  # pragma: no branch
                var m = con.ja[ii]
                if m != n:
                    for jj in range(
                        con.ia[m], con.ia[m + 1]
                    ):  # pragma: no branch
                        if con.ja[jj] == n:
                            con.isym[ii] = jj
                            break
                else:
                    con.isym[ii] = ii
        var isympos = 1
        for n in range(1, self.nodes + 1):  # pragma: no branch
            for ii in range(con.ia[n] + 1, con.ia[n + 1]):
                if con.ja[ii] > n:
                    con.jas[ii] = isympos
                    isympos += 1
        for n in range(1, self.nodes + 1):  # pragma: no branch
            for ii in range(con.ia[n], con.ia[n + 1]):  # pragma: no branch
                if con.ja[ii] < n:
                    con.jas[ii] = con.jas[con.isym[ii]]
        con.ihc = List[Int](length=con.njas + 1, fill=0)
        con.cl1 = List[Float64](length=con.njas + 1, fill=0.0)
        con.cl2 = List[Float64](length=con.njas + 1, fill=0.0)
        con.hwva = List[Float64](length=con.njas + 1, fill=0.0)
        con.anglex = List[Float64](length=con.njas + 1, fill=0.0)
        isympos = 1
        for k in range(1, self.nlay + 1):  # pragma: no branch
            for i in range(1, self.nrow + 1):  # pragma: no branch
                for j in range(1, self.ncol + 1):  # pragma: no branch
                    var nr = self._mr(k, i, j)
                    if nr <= 0:
                        continue
                    if j < self.ncol:
                        if self._mr(k, i, j + 1) > 0:
                            con.ihc[isympos] = 1
                            con.cl1[isympos] = mul(DHALF, self.delr[j])
                            con.cl2[isympos] = mul(DHALF, self.delr[j + 1])
                            con.hwva[isympos] = self.delc[i]
                            con.anglex[isympos] = DZERO
                            isympos += 1
                    if i < self.nrow:
                        if self._mr(k, i + 1, j) > 0:
                            con.ihc[isympos] = 1
                            con.cl1[isympos] = mul(DHALF, self.delc[i])
                            con.cl2[isympos] = mul(DHALF, self.delc[i + 1])
                            con.hwva[isympos] = self.delr[j]
                            con.anglex[isympos] = mul(DTHREE / DTWO, DPI)
                            isympos += 1
                    if k < self.nlay:
                        var mr = self._below(k, i, j)
                        if mr > 0:
                            con.ihc[isympos] = 0
                            con.cl1[isympos] = mul(
                                DHALF, self.top[nr] - self.bot[nr]
                            )
                            con.cl2[isympos] = mul(
                                DHALF, self.top[mr] - self.bot[mr]
                            )
                            con.hwva[isympos] = mul(self.delr[j], self.delc[i])
                            con.anglex[isympos] = DZERO
                            isympos += 1
        self.con = con^
