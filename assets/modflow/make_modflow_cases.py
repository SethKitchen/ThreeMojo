#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Write the MODFLOW 6 reference cases and run the real program on each.

Each case is a folder under cases/ with mfsim.nam and the files that it
names. The script runs mf6 in a temporary copy of the folder and writes
<case>/expected.txt from the binary head and budget files. The tests of
the port compare their results with these files.

Usage: python3 make_modflow_cases.py [path to mf6]
"""

import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CASES = os.path.join(HERE, "cases")


def fmt(v):
    """Return an integer as it is, and a real as the shortest exact text."""
    if isinstance(v, int):
        return str(v)
    return repr(float(v))


def read_heads(path):
    """Read a MODFLOW 6 head file: a list of (kper, kstp, totim, values)."""
    data = open(path, "rb").read()
    out = []
    pos = 0
    while pos < len(data):
        kstp, kper = struct.unpack_from("<ii", data, pos)
        pertim, totim = struct.unpack_from("<dd", data, pos + 8)
        ncol, nrow, ilay = struct.unpack_from("<iii", data, pos + 40)
        pos += 52
        vals = struct.unpack_from("<%dd" % (ncol * nrow), data, pos)
        pos += 8 * ncol * nrow
        if ilay == 1:
            out.append([kper, kstp, totim, list(vals)])
        else:
            out[-1][3].extend(vals)
    return out


def read_budget(path):
    """Read a MODFLOW 6 budget file: a list of records in file order."""
    data = open(path, "rb").read()
    out = []
    pos = 0
    while pos < len(data):
        kstp, kper = struct.unpack_from("<ii", data, pos)
        text = data[pos + 8 : pos + 24].decode().strip()
        n1, n2, n3 = struct.unpack_from("<iii", data, pos + 24)
        pos += 36
        imeth = 1
        if n3 < 0:
            imeth = struct.unpack_from("<i", data, pos)[0]
            pos += 4 + 24
        if imeth == 1:
            n = n1 * n2 * abs(n3)
            vals = list(struct.unpack_from("<%dd" % n, data, pos))
            pos += 8 * n
            out.append((kper, kstp, text, "array", vals))
        elif imeth == 6:
            pname = data[pos + 48 : pos + 64].decode().strip()
            pos += 64
            ndat = struct.unpack_from("<i", data, pos)[0]
            pos += 4 + 16 * (ndat - 1)
            nlist = struct.unpack_from("<i", data, pos)[0]
            pos += 4
            recs = []
            for _ in range(nlist):
                id1, id2 = struct.unpack_from("<ii", data, pos)
                q = struct.unpack_from("<d", data, pos + 8)[0]
                pos += 8 + 8 * ndat
                recs.append((id1, q))
            out.append((kper, kstp, text + " " + pname, "list", recs))
        else:
            raise SystemExit("budget method %d is not read" % imeth)
    return out


def write_expected(folder, work, name):
    """Write expected.txt from the outputs of mf6 in the work folder."""
    heads = read_heads(os.path.join(work, name + ".hds"))
    budget = read_budget(os.path.join(work, name + ".cbc"))
    # The simulation listing names each step that fails to converge. Only a
    # simulation with the CONTINUE option goes on after one.
    failed = set()
    lst = open(os.path.join(work, "mfsim.lst")).read()
    for m in re.finditer(r"Solution 1 did not converge for stress period "
                         r"(\d+) and time step (\d+)", lst):
        failed.add((int(m.group(1)), int(m.group(2))))
    lines = []
    for kper, kstp, totim, vals in heads:
        lines.append("step %d %d %s %d" % (kper, kstp, fmt(totim),
                                           0 if (kper, kstp) in failed else 1))
        lines.append("head " + " ".join(fmt(v) for v in vals))
        for bk, bs, text, kind, vals2 in budget:
            if bk != kper or bs != kstp:
                continue
            if kind == "array":
                lines.append(
                    "%s %s" % (text, " ".join(fmt(v) for v in vals2))
                )
            else:
                body = " ".join("%d %s" % (i, fmt(q)) for i, q in vals2)
                lines.append(("%s %d %s" % (text, len(vals2), body)).rstrip())
    with open(os.path.join(folder, "expected.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")


def write(folder, fname, text):
    with open(os.path.join(folder, fname), "w") as f:
        f.write(text.strip("\n") + "\n")


def array(values, per_line):
    """Return INTERNAL array lines, one grid row on each line.

    MODFLOW 6 reads each row of a grid array with one list-directed READ,
    so a row must start on a new line.
    """
    out = []
    for i in range(0, len(values), per_line):
        out.append("      " + " ".join(fmt(v) for v in values[i : i + per_line]))
    return "\n".join(out)


def factor(values):
    """Return the FACTOR of an INTERNAL array: an integer for integers."""
    return "1" if all(isinstance(v, int) for v in values) else "1.0"


def griddata(name, value, ncol=8):
    """Return the lines of one GRIDDATA array.

    A number is a CONSTANT array and a list is an INTERNAL array. A tuple
    holds one entry of either kind for each layer of a LAYERED array.
    """
    if isinstance(value, tuple):
        out = ["  %s LAYERED" % name]
        for v in value:
            if isinstance(v, list):
                out.append("    INTERNAL FACTOR %s" % factor(v))
                out.append(array(v, ncol))
            else:
                out.append("    CONSTANT %s" % fmt(v))
        return "\n".join(out)
    if isinstance(value, list):
        return "  %s\n    INTERNAL FACTOR %s\n%s" % (
            name, factor(value), array(value, ncol))
    return "  %s\n    CONSTANT %s" % (name, fmt(value))


def model(case, nlay, nrow, ncol, delr, delc, top, botm, strt, k,
          icelltype=0, k33=None, idomain=None, periods=((1.0, 1, 1.0),),
          sto=None, packages=(), ims="", newton="", npf_options="",
          time_units="DAYS", length_units="METERS", sto_periods=None,
          npf_arrays=(), pnames=True, keep_going=False):
    """Write the files of a one-model simulation.

    An array of one layer, given for a grid of more layers, is repeated in
    each layer.
    """

    def g(aname, value):
        if nlay > 1 and isinstance(value, list) and len(value) == nrow * ncol:
            value = tuple([value] * nlay)
        return griddata(aname, value, ncol)

    folder = os.path.join(CASES, case)
    os.makedirs(folder, exist_ok=True)
    name = "model"
    write(folder, "mfsim.nam", """
BEGIN options
%s
END options
BEGIN timing
  TDIS6 model.tdis
END timing
BEGIN models
  gwf6 model.nam model
END models
BEGIN exchanges
END exchanges
BEGIN solutiongroup 1
  ims6 model.ims model
END solutiongroup
""" % ("  CONTINUE" if keep_going else ""))
    pd = "\n".join("  %s %d %s" % (fmt(a), b, fmt(c)) for a, b, c in periods)
    write(folder, "model.tdis", """
BEGIN options
  TIME_UNITS %s
END options
BEGIN dimensions
  NPER %d
END dimensions
BEGIN perioddata
%s
END perioddata
""" % (time_units, len(periods), pd))
    write(folder, "model.ims", ims or """
BEGIN options
END options
BEGIN nonlinear
  OUTER_DVCLOSE 1.0e-9
  OUTER_MAXIMUM 100
END nonlinear
BEGIN linear
  INNER_MAXIMUM 300
  INNER_DVCLOSE 1.0e-10
  INNER_RCLOSE 1.0e-6
  LINEAR_ACCELERATION CG
END linear
""")
    pk = ["  DIS6 model.dis dis", "  IC6 model.ic ic", "  NPF6 model.npf npf",
          "  OC6 model.oc oc"]
    if sto is not None:
        pk.append("  STO6 model.sto sto")
    for i, (ftype, text) in enumerate(packages):
        fname = "model.%s%d" % (ftype.lower(), i + 1)
        if pnames:
            pk.append("  %s6 %s %s_%d" % (ftype, fname, ftype.lower(), i + 1))
        else:
            pk.append("  %s6 %s" % (ftype, fname))
        write(folder, fname, text)
    write(folder, "model.nam", """
BEGIN options
%s
END options
BEGIN packages
%s
END packages
""" % (newton, "\n".join(pk)))
    dis = ["BEGIN options", "  LENGTH_UNITS %s" % length_units,
           "END options", "BEGIN dimensions", "  NLAY %d" % nlay,
           "  NROW %d" % nrow, "  NCOL %d" % ncol, "END dimensions",
           "BEGIN griddata", griddata("DELR", delr), griddata("DELC", delc),
           griddata("TOP", top, ncol),
           g("BOTM", botm)]
    if idomain is not None:
        dis.append(g("IDOMAIN", idomain))
    dis.append("END griddata")
    write(folder, "model.dis", "\n".join(dis))
    write(folder, "model.ic", "BEGIN griddata\n%s\nEND griddata" %
          g("STRT", strt))
    npf = ["BEGIN options", "  SAVE_FLOWS", npf_options, "END options",
           "BEGIN griddata", g("ICELLTYPE", icelltype),
           g("K", k)]
    if k33 is not None:
        npf.append(g("K33", k33))
    for aname, avalue in npf_arrays:
        npf.append(g(aname, avalue))
    npf.append("END griddata")
    write(folder, "model.npf", "\n".join(npf))
    if sto is not None:
        text = ["BEGIN options", "  SAVE_FLOWS", sto.get("options", ""),
                "END options", "BEGIN griddata",
                g("ICONVERT", sto.get("iconvert", 0)),
                g("SS", sto.get("ss", 1.0e-5)),
                g("SY", sto.get("sy", 0.15)), "END griddata"]
        for kper, state in (sto_periods or [(1, "TRANSIENT")]):
            text += ["BEGIN period %d" % kper, "  %s" % state, "END period"]
        write(folder, "model.sto", "\n".join(text))
    write(folder, "model.oc", """
BEGIN options
  BUDGET FILEOUT model.cbc
  HEAD FILEOUT model.hds
END options
BEGIN period 1
  SAVE HEAD ALL
  SAVE BUDGET ALL
END period
""")
    return folder


def listpkg(records, options="  SAVE_FLOWS", period=1, extra=None):
    """Return the text of a list package with one or more PERIOD blocks."""
    blocks = [(period, records)] + list(extra or [])
    nmax = max(len(r) for _, r in blocks) or 1
    text = ["BEGIN options", options, "END options", "BEGIN dimensions",
            "  MAXBOUND %d" % nmax, "END dimensions"]
    for kper, recs in blocks:
        text.append("BEGIN period %d" % kper)
        for r in recs:
            text.append("  " + " ".join(str(v) if isinstance(v, int)
                                        else fmt(v) for v in r))
        text.append("END period")
    return "\n".join(text)


def cases():
    """Write every case."""
    shutil.rmtree(CASES, ignore_errors=True)
    os.makedirs(CASES)
    # Confined, steady, one layer: two constant heads and a well.
    model("confined_steady", 1, 5, 7, 100.0, 100.0, 10.0, 0.0, 10.0, 5.0,
          packages=[
              ("CHD", listpkg([(1, r, 1, 10.0) for r in range(1, 6)]
                              + [(1, r, 7, 5.0) for r in range(1, 6)])),
              ("WEL", listpkg([(1, 3, 4, -150.0)])),
          ])
    # Two layers, convertible top layer, transient, with a river and a drain.
    model("unconfined_transient", 2, 6, 6, 50.0, 50.0, 20.0, (10.0, 0.0),
          18.0, 2.0, icelltype=(1, 0), k33=0.5,
          periods=((1.0, 1, 1.0), (30.0, 5, 1.2)),
          sto={"iconvert": (1, 0), "ss": 1e-5, "sy": 0.2},
          sto_periods=[(1, "STEADY-STATE"), (2, "TRANSIENT")],
          packages=[
              ("GHB", listpkg([(1, r, 1, 17.0, 40.0) for r in range(1, 7)])),
              ("RIV", listpkg([(1, r, 6, 15.0, 80.0, 13.0)
                               for r in range(1, 7)])),
              ("DRN", listpkg([(1, 2, 3, 16.5, 25.0)])),
              ("WEL", listpkg([(2, 4, 4, -300.0)], period=2)),
              ("RCH", listpkg([(1, r, c, 0.002) for r in range(1, 7)
                               for c in range(1, 7)])),
          ])
    more_cases()
    branch_cases()
    edge_cases()
    solver_cases()


def ims(options="", nonlinear="", linear=""):
    """Return an IMS file of the three blocks."""
    return "\n".join(["BEGIN options", options, "END options",
                      "BEGIN nonlinear", nonlinear, "END nonlinear",
                      "BEGIN linear", linear, "END linear"])


def field(nrow, ncol, base, amp, phase=0.0):
    """Return a smooth, varied field of one layer, row by row."""
    import math
    return [base + amp * math.sin(0.7 * r + 1.3 * c + phase)
            for r in range(nrow) for c in range(ncol)]


def arrays_pkg(options, layer_name, layer, arrays, period=1):
    """Return the text of an array package (READASARRAYS)."""
    text = ["BEGIN options", "  READASARRAYS", options, "END options",
            "BEGIN period %d" % period]
    if layer is not None:
        text.append(griddata(layer_name, layer))
    for name, value in arrays:
        text.append(griddata(name, value))
    text.append("END period")
    return "\n".join(text)


NEWTON_IMS = ims(
    nonlinear="  OUTER_DVCLOSE 1.0e-8\n  OUTER_MAXIMUM 200",
    linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
           "  INNER_RCLOSE 1.0e-6\n  LINEAR_ACCELERATION BICGSTAB")


def more_cases():
    """Write the cases of the solver options and the packages."""
    k = field(8, 8, 5.0, 3.0)
    top = field(8, 8, 30.0, 2.0, 0.4)
    chd = [(1, r, 1, 24.0) for r in range(1, 9)]
    wel = [(1, 4, 6, -400.0), (1, 6, 3, -250.0)]
    rch = [(1, r, c, 0.004) for r in range(1, 9) for c in range(1, 9)]
    # Newton-Raphson, steady state: pseudo-transient continuation.
    model("newton_steady", 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k,
          icelltype=1, newton="  NEWTON", ims=NEWTON_IMS,
          packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel)),
                    ("RCH", listpkg(rch))])
    # Newton under-relaxation, transient, delta-bar-delta and backtracking.
    model("newton_dbd_backtracking", 2, 8, 8, 40.0, 40.0, top, (18.0, 0.0),
          22.0, k, icelltype=(1, 1), k33=(1.0, 0.5),
          newton="  NEWTON UNDER_RELAXATION",
          periods=((10.0, 3, 1.5), (20.0, 2, 1.0)),
          sto={"iconvert": 1, "ss": 1e-5, "sy": 0.1},
          ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-8\n  OUTER_MAXIMUM 200\n"
                  "  UNDER_RELAXATION DBD\n  UNDER_RELAXATION_THETA 0.7\n"
                  "  UNDER_RELAXATION_KAPPA 0.1\n"
                  "  UNDER_RELAXATION_GAMMA 0.2\n"
                  "  UNDER_RELAXATION_MOMENTUM 0.001\n"
                  "  BACKTRACKING_NUMBER 5\n  BACKTRACKING_TOLERANCE 1.0\n"
                  "  BACKTRACKING_REDUCTION_FACTOR 0.3\n"
                  "  BACKTRACKING_RESIDUAL_LIMIT 1.0e-4",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
                  "  INNER_RCLOSE 1.0e-6 L2NORM_RCLOSE\n"
                  "  LINEAR_ACCELERATION BICGSTAB\n"
                  "  RELAXATION_FACTOR 0.97\n  SCALING_METHOD DIAGONAL"),
          packages=[("CHD", listpkg([(1, r, 1, 20.0) for r in range(1, 9)])),
                    ("WEL", listpkg([(2, 4, 6, -900.0), (1, 6, 3, -300.0)])),
                    ("RCH", listpkg(rch))])
    # Cooley under-relaxation, BiCGSTAB with MILU0 and L2 norm scaling.
    model("cooley_bicgstab", 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k,
          icelltype=1,
          periods=((1.0, 1, 1.0), (5.0, 2, 1.0)),
          sto={"iconvert": 1, "ss": 1e-5, "sy": 0.1},
          sto_periods=[(1, "STEADY-STATE"), (2, "TRANSIENT")],
          ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-8\n  OUTER_MAXIMUM 200\n"
                  "  UNDER_RELAXATION COOLEY\n  UNDER_RELAXATION_GAMMA 0.3",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
                  "  INNER_RCLOSE 1.0e-3 RELATIVE_RCLOSE\n"
                  "  LINEAR_ACCELERATION BICGSTAB\n"
                  "  RELAXATION_FACTOR 0.9\n  SCALING_METHOD L2NORM\n"
                  "  NUMBER_ORTHOGONALIZATIONS 3"),
          packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel)),
                    ("RCH", listpkg(rch))])
    # Simple under-relaxation, CG, the strict and the relative L2 tests.
    model("simple_strict", 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k,
          icelltype=1,
          ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-8\n  OUTER_MAXIMUM 300\n"
                  "  UNDER_RELAXATION SIMPLE\n  UNDER_RELAXATION_GAMMA 0.8",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
                  "  INNER_RCLOSE 1.0e-6 STRICT\n  LINEAR_ACCELERATION CG\n"
                  "  NUMBER_ORTHOGONALIZATIONS 2"),
          packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel)),
                    ("RCH", listpkg(rch))])
    model("l2norm_relative", 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k,
          icelltype=1,
          ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-8\n  OUTER_MAXIMUM 300",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
                  "  INNER_RCLOSE 1.0e-6 L2NORM_RELATIVE_RCLOSE\n"
                  "  LINEAR_ACCELERATION BICGSTAB"),
          packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel)),
                    ("RCH", listpkg(rch))])
    # The defaults of the MODERATE and SIMPLE complexities.
    for name, cx in (("complexity_moderate", "MODERATE"),
                     ("complexity_simple", "SIMPLE")):
        model(name, 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k, icelltype=1,
              ims="BEGIN options\n  COMPLEXITY %s\nEND options" % cx,
              packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel)),
                        ("RCH", listpkg(rch))])
    # EVT from lists: three segments, and a rate at the surface.
    evt = [(1, r, c, 26.0, 0.003, 6.0, 0.3, 0.7, 0.6, 0.2)
           for r in range(1, 9) for c in range(1, 9)]
    evt2 = [(1, r, c, 26.0, 0.002, 4.0, 0.5, 0.5, 0.9)
            for r in range(1, 5) for c in range(1, 9)]
    model("evt_list", 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k, icelltype=1,
          packages=[
              ("CHD", listpkg(chd)), ("RCH", listpkg(rch)),
              ("EVT", listpkg(evt, options="  SAVE_FLOWS")
               .replace("END dimensions", "  NSEG 3\nEND dimensions")),
              ("EVT", listpkg(evt2, options="  SURF_RATE_SPECIFIED")
               .replace("END dimensions", "  NSEG 2\nEND dimensions")),
              ("EVT", listpkg([(1, 2, 2, 26.0, 0.002, 4.0)])),
          ])
    # RCH and EVT from arrays, with layers and FIXED_CELL.
    irch = [1 if c < 5 else 2 for r in range(8) for c in range(8)]
    model("arrays_two_layers", 2, 8, 8, 40.0, 40.0, top, (18.0, 0.0), 25.0,
          k, icelltype=(1, 0),
          packages=[
              ("CHD", listpkg(chd)),
              ("RCH", arrays_pkg("  SAVE_FLOWS", "IRCH", irch,
                                 [("RECHARGE", field(8, 8, 0.004, 0.002))])),
              ("RCH", arrays_pkg("  FIXED_CELL", None, None, [])),
              ("EVT", arrays_pkg("", "IEVT", 1,
                                 [("SURFACE", top), ("RATE", 0.002),
                                  ("DEPTH", 8.0)])),
          ])
    # Cells that dry and rewet, with a perched water table and
    # VARIABLECV DEWATERED.
    model("rewet_perched", 3, 8, 8, 40.0, 40.0, 30.0, (20.0, 12.0, 0.0),
          26.0, k, icelltype=(1, 1, 0), k33=0.2,
          npf_options="  REWET WETFCT 1.0 IWETIT 1 IHDWET 0\n  PERCHED\n"
                      "  VARIABLECV DEWATERED",
          npf_arrays=[("WETDRY", (-1.0, 1.0, 0.0))],
          periods=((1.0, 1, 1.0), (10.0, 4, 1.0)),
          sto={"iconvert": (1, 1, 0), "ss": 1e-5, "sy": 0.1},
          sto_periods=[(1, "STEADY-STATE"), (2, "TRANSIENT")],
          ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-7\n  OUTER_MAXIMUM 300",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-8\n"
                  "  INNER_RCLOSE 1.0e-6\n  LINEAR_ACCELERATION BICGSTAB"),
          packages=[("CHD", listpkg([(3, r, 1, 24.0) for r in range(1, 9)])),
                    ("WEL", listpkg([(3, 4, 6, -1500.0)], period=2)),
                    ("RCH", listpkg([(1, 2, 2, 0.05), (1, 7, 7, 0.08)]))])
    # The averaging options, THICKSTRT, anisotropy and IDOMAIN.
    k2 = field(8, 8, 4.0, 3.5, 1.1)
    for name, opt in (("average_logarithmic", "LOGARITHMIC"),
                      ("average_amt_lmk", "AMT-LMK"),
                      ("average_amt_hmk", "AMT-HMK")):
        model(name, 2, 8, 8, 40.0, 40.0, top, (18.0, 0.0), 26.0, (k2, k),
              icelltype=(1, 0), k33=(0.3, 0.6),
              npf_options="  ALTERNATIVE_CELL_AVERAGING %s" % opt,
              packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel)),
                        ("RCH", listpkg(rch))])
    idom = [0 if (r, c) in ((2, 2), (5, 7)) else 1
            for r in range(8) for c in range(8)]
    idom2 = [-1 if (r, c) in ((3, 3), (4, 5)) else 1
             for r in range(8) for c in range(8)]
    model("thickstrt_anisotropy_idomain", 3, 8, 8, 40.0, 40.0, top,
          (18.0, 10.0, 0.0), 26.0, k, icelltype=(-1, 1, 0),
          k33=(0.5, 0.5, 2.0), idomain=(idom, idom2, 1),
          npf_options="  THICKSTRT\n  K22OVERK\n  K33OVERK",
          npf_arrays=[("K22", 0.4), ("ANGLE1", 30.0)],
          packages=[("CHD", listpkg([(1, r, 1, 24.0) for r in range(1, 9)])),
                    ("WEL", listpkg([(3, 4, 6, -400.0)]))])
    # Newton with HIGHEST_CELL_SATURATION over a stepped bottom.
    bot = [10.0 if c < 4 else 14.0 for r in range(8) for c in range(8)]
    model("newton_highest_cell", 1, 8, 8, 40.0, 40.0, top, bot, 25.0, k,
          icelltype=1, newton="  NEWTON", ims=NEWTON_IMS,
          npf_options="  HIGHEST_CELL_SATURATION",
          packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel)),
                    ("RCH", listpkg(rch))])
    # The storage options, a time step multiplier and feet.
    for name, opt in (("storage_coefficient", "  STORAGECOEFFICIENT"),
                      ("ss_confined_only", "  SS_CONFINED_ONLY"),
                      ("original_ss", "  DEV_ORIGINAL_SPECIFIC_STORAGE")):
        model(name, 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k, icelltype=1,
              length_units="FEET", time_units="SECONDS",
              periods=((86400.0, 4, 1.5),),
              sto={"iconvert": 1, "ss": 1e-4, "sy": 0.1, "options": opt},
              packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel))])
    # Auxiliary multipliers, and bounds that change between periods.
    aux = "  AUXILIARY mult other\n  AUXMULTNAME mult\n  SAVE_FLOWS"
    model("auxmult_periods", 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k,
          icelltype=1, periods=((1.0, 1, 1.0), (1.0, 1, 1.0), (1.0, 1, 1.0)),
          packages=[
              ("CHD", listpkg([(1, r, 1, 24.0, 1.0, 0.0) for r in range(1, 9)],
                              options=aux,
                              extra=[(3, [(1, r, 8, 23.0, 1.02, 0.0)
                                          for r in range(1, 9)])])),
              ("WEL", listpkg([(1, 4, 6, -400.0, 0.5, 7.0)], options=aux,
                              extra=[(2, [])])),
              ("GHB", listpkg([(1, 1, 8, 22.0, 30.0, 2.0, 0.0)], options=aux)),
              ("RIV", listpkg([(1, 8, 8, 22.0, 30.0, 21.0, 0.5, 0.0)],
                              options=aux)),
              ("DRN", listpkg([(1, 5, 5, 23.0, 50.0, 0.7, 0.0)], options=aux)),
              ("RCH", listpkg([(1, r, 4, 0.01, 1.5, 0.0) for r in range(1, 9)],
                              options=aux)),
          ])


def branch_cases():
    """Write the cases that reach the rarer branches of the solver."""
    k = field(8, 8, 5.0, 3.0)
    top = field(8, 8, 30.0, 2.0, 0.4)
    chd = [(1, r, 1, 24.0) for r in range(1, 9)]
    wel = [(1, 4, 6, -400.0), (1, 6, 3, -250.0)]
    rch = [(1, r, c, 0.004) for r in range(1, 9) for c in range(1, 9)]
    two_steady = ((1.0, 1, 1.0), (1.0, 1, 1.0))
    wel2 = [(2, [(1, 4, 6, -700.0), (1, 6, 3, -250.0)])]
    # Pseudo-transient continuation: its development options, and NO_PTC.
    for name, opts in (
            ("ptc_option_exponent",
             "  DEV_PTC_OPTION\n  DEV_PTC_EXPONENT 0.5"),
            ("ptc_del0", "  DEV_PTC_DEL0 0.5"),
            ("ptc_no_first", "  NO_PTC FIRST"),
            ("ptc_none", "  NO_PTC")):
        model(name, 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k, icelltype=1,
              newton="  NEWTON", periods=two_steady,
              ims=NEWTON_IMS.replace("BEGIN options\n",
                                     "BEGIN options\n" + opts + "\n"),
              packages=[("CHD", listpkg(chd)),
                        ("WEL", listpkg(wel, extra=wel2)),
                        ("RCH", listpkg(rch))])
    # Cells that go dry under a well and wet again when it stops. Two cells
    # of the top layer start below their bottom.
    strt = [(9.0 if (r, c) in ((0, 7), (7, 7)) else 14.0)
            for r in range(8) for c in range(8)]
    for name, rewet, wetdry, q, go in (
            ("rewet_wetfct", "  REWET WETFCT 1.0 IWETIT 1 IHDWET 0",
             (1.0, 0.0), -900.0, True),
            ("rewet_ihdwet", "  REWET WETFCT 0.5 IWETIT 2 IHDWET 1",
             (-0.5, 0.0), -2500.0, False)):
        model(name, 2, 8, 8, 40.0, 40.0, 20.0, (10.0, 0.0), (strt, 14.0),
              5.0, icelltype=(1, 1), npf_options=rewet,
              npf_arrays=[("WETDRY", wetdry)], keep_going=go,
              periods=((1.0, 1, 1.0), (5.0, 3, 1.0), (20.0, 4, 1.0)),
              sto={"iconvert": 1, "ss": 1e-5, "sy": 0.2},
              sto_periods=[(1, "STEADY-STATE"), (2, "TRANSIENT")],
              ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-6\n"
                      "  OUTER_MAXIMUM 500",
                      linear="  INNER_MAXIMUM 300\n"
                      "  INNER_DVCLOSE 1.0e-7\n  INNER_RCLOSE 1.0e-4\n"
                      "  LINEAR_ACCELERATION BICGSTAB"),
              packages=[
                  ("CHD", listpkg([(2, r, 1, 14.0) for r in range(1, 9)])),
                  ("WEL", listpkg([(2, 4, 5, q)], period=2,
                                  extra=[(3, [])])),
                  ("RCH", listpkg([(1, r, c, 0.0005) for r in range(1, 9)
                                   for c in range(1, 9)], period=3)),
              ])
    # A perched water table, VARIABLECV without DEWATERED, and two confined
    # layers under it.
    model("perched_varcv", 4, 8, 8, 40.0, 40.0, 40.0,
          (30.0, 20.0, 10.0, 0.0), 32.0, k, icelltype=(1, 1, 0, 0),
          k33=(0.002, 1.0, 1.0, 1.0),
          npf_options="  PERCHED\n  VARIABLECV",
          ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-8\n  OUTER_MAXIMUM 500",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
                  "  INNER_RCLOSE 1.0e-6\n  LINEAR_ACCELERATION BICGSTAB"),
          packages=[
              ("CHD", listpkg([(4, r, 1, 24.0) for r in range(1, 9)])),
              ("DRN", listpkg([(2, r, 8, 21.0, 50.0) for r in range(1, 9)])),
              ("RCH", listpkg(rch)),
          ])
    # Anisotropy in three angles.
    model("angles3d", 2, 8, 8, 40.0, 40.0, 30.0, (15.0, 0.0), 26.0, k,
          k33=0.3, npf_options="  K22OVERK",
          npf_arrays=[("K22", 0.4), ("ANGLE1", 30.0), ("ANGLE2", 10.0),
                      ("ANGLE3", 20.0)],
          packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel)),
                    ("RCH", listpkg(rch))])
    # Newton under-relaxation with heads pulled toward the bottom.
    model("newton_nur_dry", 2, 8, 8, 40.0, 40.0, 30.0, (20.0, 10.0), 26.0,
          2.0, icelltype=(1, 1), newton="  NEWTON UNDER_RELAXATION",
          periods=((1.0, 1, 1.0), (2.0, 4, 1.0)),
          sto={"iconvert": 1, "ss": 1e-5, "sy": 0.05},
          sto_periods=[(1, "STEADY-STATE"), (2, "TRANSIENT")],
          ims=NEWTON_IMS,
          packages=[("CHD", listpkg([(1, r, 1, 26.0) for r in range(1, 9)])),
                    ("WEL", listpkg([(2, 5, 6, -1600.0)], period=2))])
    # One cell of constant head: the residual is zero at the start.
    model("single_cell", 1, 1, 1, 10.0, 10.0, 10.0, 0.0, 5.0, 1.0,
          packages=[("CHD", listpkg([(1, 1, 1, 5.0)]))])
    # Drains and rivers above the head, ET above its surface and in its last
    # segment, auxiliary multipliers of RCH and EVT, array input over a
    # removed cell, and packages without names.
    idom = [0 if (r, c) == (3, 3) else 1 for r in range(8) for c in range(8)]
    auxm = "  AUXILIARY mult\n  AUXMULTNAME mult"
    evt_hi = [(1, r, c, 23.0, 0.002, 5.0, 2.0) for r in range(1, 9)
              for c in range(1, 4)]
    evt_seg = [(1, r, c, 30.0, 0.003, 9.0, 0.2, 0.5, 0.8, 0.3, 0.1, 1.0)
               for r in range(1, 9) for c in range(4, 9) if (r, c) != (4, 4)]
    evt_srs = [(1, r, 1, 23.0, 0.002, 4.0, 0.5, 0.5, 0.9)
               for r in range(1, 9)]
    model("bounds_edge", 2, 8, 8, 40.0, 40.0, top, (18.0, 0.0), 25.0, k,
          icelltype=(1, 0), idomain=(idom, 1), pnames=False,
          packages=[
              ("CHD", listpkg(chd)),
              ("DRN", listpkg([(1, 2, 5, 29.0, 20.0), (1, 7, 7, 23.5, 20.0)])),
              ("RIV", listpkg([(1, 5, 2, 27.0, 30.0, 26.0),
                               (1, 3, 6, 24.0, 30.0, 23.0)])),
              ("EVT", listpkg(evt_hi, options="  " + auxm.strip())),
              ("EVT", listpkg(evt_seg).replace("END dimensions",
                                               "  NSEG 3\nEND dimensions")),
              ("EVT", listpkg(evt_srs, options="  SURF_RATE_SPECIFIED")
               .replace("END dimensions", "  NSEG 2\nEND dimensions")),
              ("RCH", arrays_pkg(auxm, None, None,
                                 [("RECHARGE", 0.004),
                                  ("mult", field(8, 8, 1.0, 0.5))])),
          ])
    # The IMS keywords that set a default again, a theta under its floor,
    # and Cooley under-relaxation that changes direction.
    model("ims_keywords", 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k,
          icelltype=1,
          ims=ims(options="  COMPLEXITY MODERATE\n  PRINT_OPTION SUMMARY",
                  nonlinear="  OUTER_DVCLOSE 1.0e-8\n  OUTER_MAXIMUM 300\n"
                  "  UNDER_RELAXATION NONE\n  LINEAR_SOLVER DEFAULT",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
                  "  INNER_RCLOSE 1.0e-6\n  LINEAR_ACCELERATION BICGSTAB\n"
                  "  SCALING_METHOD NONE\n  RED_BLACK_ORDERING\n"
                  "  REORDERING_METHOD NONE"),
          packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel)),
                    ("RCH", listpkg(rch))])
    model("dbd_theta_floor", 1, 8, 8, 40.0, 40.0, top, 10.0, 25.0, k,
          icelltype=1,
          ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-8\n  OUTER_MAXIMUM 300\n"
                  "  UNDER_RELAXATION DBD\n  UNDER_RELAXATION_THETA 0.0\n"
                  "  UNDER_RELAXATION_KAPPA 0.05",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
                  "  INNER_RCLOSE 1.0e-6\n  LINEAR_ACCELERATION BICGSTAB"),
          packages=[("CHD", listpkg(chd)), ("WEL", listpkg(wel)),
                    ("RCH", listpkg(rch))])
    model("cooley_oscillate", 1, 8, 8, 40.0, 40.0, 30.0, 10.0, 29.0, 20.0,
          icelltype=1,
          ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-8\n  OUTER_MAXIMUM 500\n"
                  "  UNDER_RELAXATION COOLEY\n  UNDER_RELAXATION_GAMMA 0.0",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
                  "  INNER_RCLOSE 1.0e-6\n  LINEAR_ACCELERATION CG"),
          packages=[("CHD", listpkg([(1, r, 1, 12.0) for r in range(1, 9)])),
                    ("WEL", listpkg([(1, 4, 8, -900.0)]))])


def edge_cases():
    """Write the cases of cells, storage and solver steps at their edges."""
    # A cell with no neighbors has no conductance on its diagonal.
    model("isolated_cell", 1, 1, 3, 10.0, 10.0, 10.0, 0.0, [8.0, 8.0, 9.0],
          1.0, idomain=[1, 0, 1],
          packages=[("CHD", listpkg([(1, 1, 1, 8.0)]))])
    # Newton under-relaxation that converges at a reset: the well takes a
    # little more than the constant head can give at the bottom, and one
    # inner iteration leaves each solve unconverged.
    model("nur_converges", 1, 1, 2, 10.0, 10.0, 10.0, 0.0, 5.0, 1.0,
          icelltype=1, newton="  NEWTON UNDER_RELAXATION", keep_going=True,
          ims=NEWTON_IMS.replace("INNER_MAXIMUM 300", "INNER_MAXIMUM 1")
          .replace("INNER_DVCLOSE 1.0e-9", "INNER_DVCLOSE 1.0e-30")
          .replace("INNER_RCLOSE 1.0e-6", "INNER_RCLOSE 1.0e-30"),
          packages=[("CHD", listpkg([(1, 1, 1, 1.0)])),
                    ("WEL", listpkg([(1, 1, 2, -0.999996005)]))])
    # A linear Newton problem of two steady steps: the second step starts
    # balanced.
    model("newton_exact", 1, 1, 2, 10.0, 10.0, 10.0, 0.0, 10.0, 1.0,
          newton="  NEWTON", periods=((1.0, 2, 1.0),), ims=NEWTON_IMS,
          packages=[("CHD", listpkg([(1, 1, 1, 8.0)]))])
    # ET with a specified rate at the surface: a head above the surface, one
    # under the extinction depth, and two between.
    evt = []
    for c in range(2, 5):
        evt += [(1, 1, c, 20.0, 0.002, 4.0, 0.5, 0.6, 0.9),
                (1, 2, c, 40.0, 0.002, 2.0, 0.5, 0.6, 0.9),
                (1, 3, c, 26.0, 0.002, 5.0, 0.5, 0.6, 0.9),
                (1, 4, c, 25.5, 0.002, 10.0, 0.3, 0.4, 0.8)]
    model("evt_depths", 1, 4, 4, 40.0, 40.0, 30.0, 0.0, 25.0, 5.0,
          packages=[
              ("CHD", listpkg([(1, r, 1, 24.0) for r in range(1, 5)])),
              ("EVT", listpkg(evt, options="  SURF_RATE_SPECIFIED")
               .replace("END dimensions", "  NSEG 2\nEND dimensions")),
          ])
    # VARIABLECV DEWATERED over a lower layer that is partly full.
    k = field(6, 6, 5.0, 2.0)
    rch = [(1, r, c, 0.002) for r in range(1, 7) for c in range(1, 7)]
    model("varcv_lower_partial", 3, 6, 6, 40.0, 40.0, 30.0,
          (20.0, 10.0, 0.0), (25.0, 15.0, 15.0), k, icelltype=(1, 1, 0),
          k33=(0.001, 1.0, 1.0), npf_options="  VARIABLECV DEWATERED",
          ims=NEWTON_IMS.replace("BICGSTAB", "CG"),
          packages=[("CHD", listpkg([(3, r, 1, 15.0) for r in range(1, 7)])),
                    ("RCH", listpkg(rch))])
    # A confined layer over a convertible layer that starts dry.
    model("dry_lower_layer", 2, 5, 5, 40.0, 40.0, 20.0, (10.0, 0.0),
          (15.0, -1.0), 3.0, icelltype=(0, 1),
          packages=[("CHD", listpkg([(1, r, 1, 15.0) for r in range(1, 6)])),
                    ("WEL", listpkg([(1, 3, 4, -10.0)]))])
    # Confined and convertible cells side by side, and a negative cell type
    # without THICKSTRT, with VARIABLECV.
    ict = [(r + c) % 2 for r in range(6) for c in range(6)]
    model("mixed_celltype", 2, 6, 6, 40.0, 40.0, 30.0, (15.0, 0.0), 26.0, k,
          icelltype=(ict, -1), npf_options="  VARIABLECV",
          packages=[("CHD", listpkg([(1, r, 1, 25.0) for r in range(1, 7)])),
                    ("WEL", listpkg([(2, 4, 4, -200.0)]))])
    # Newton flow toward a constant head in the last column.
    model("newton_chd_downstream", 1, 1, 6, 10.0, 10.0, 10.0, 0.0, 8.0, 1.0,
          icelltype=1, newton="  NEWTON", ims=NEWTON_IMS,
          packages=[("CHD", listpkg([(1, 1, 6, 5.0)])),
                    ("RCH", listpkg([(1, 1, c, 0.01) for c in range(1, 7)]))])
    # Newton storage of convertible and confined layers, by each formulation.
    for name, opt in (("newton_sto_original",
                       "  DEV_ORIGINAL_SPECIFIC_STORAGE"),
                      ("newton_sto_confined_only", "  SS_CONFINED_ONLY")):
        model(name, 2, 6, 6, 40.0, 40.0, 30.0, (15.0, 0.0), 26.0, k,
              icelltype=(1, 0), newton="  NEWTON", ims=NEWTON_IMS,
              periods=((1.0, 1, 1.0), (10.0, 3, 1.2)),
              sto={"iconvert": (1, 0), "ss": 1e-4, "sy": 0.1,
                   "options": opt},
              sto_periods=[(1, "STEADY-STATE"), (2, "TRANSIENT")],
              packages=[
                  ("CHD", listpkg([(1, r, 1, 25.0) for r in range(1, 7)])),
                  ("WEL", listpkg([(1, 3, 5, -300.0)], period=2))])
    # Newton under-relaxation: the first solve draws a head under the bottom.
    model("nur_overshoot", 1, 1, 5, 10.0, 10.0, 10.0, 0.0, 9.0, 1.0,
          icelltype=1, newton="  NEWTON UNDER_RELAXATION", keep_going=True,
          ims=NEWTON_IMS,
          packages=[("CHD", listpkg([(1, 1, 1, 2.0)])),
                    ("WEL", listpkg([(1, 1, 5, -1.5)]))])
    # Backtracking that stops at its count, and at its residual limit.
    k8 = field(8, 8, 5.0, 3.0)
    top8 = field(8, 8, 30.0, 2.0, 0.4)
    for name, bt in (("backtrack_once",
                      "  BACKTRACKING_NUMBER 1\n"
                      "  BACKTRACKING_TOLERANCE 1.0\n"
                      "  BACKTRACKING_REDUCTION_FACTOR 0.5\n"
                      "  BACKTRACKING_RESIDUAL_LIMIT 1.0e-12"),
                     ("backtrack_res_limit",
                      "  BACKTRACKING_NUMBER 5\n"
                      "  BACKTRACKING_TOLERANCE 1.0\n"
                      "  BACKTRACKING_REDUCTION_FACTOR 0.5\n"
                      "  BACKTRACKING_RESIDUAL_LIMIT 1.0e6")):
        model(name, 1, 8, 8, 40.0, 40.0, top8, 10.0, 29.0, k8, icelltype=1,
              newton="  NEWTON", keep_going=True,
              ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-8\n"
                      "  OUTER_MAXIMUM 200\n" + bt,
                      linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
                      "  INNER_RCLOSE 1.0e-6\n"
                      "  LINEAR_ACCELERATION BICGSTAB"),
              packages=[
                  ("CHD", listpkg([(1, r, 1, 24.0) for r in range(1, 9)])),
                  ("WEL", listpkg([(1, 4, 6, -1500.0), (1, 6, 3, -900.0)]))])
    # Cooley under-relaxation of a change that reverses and grows.
    model("cooley_reverse", 1, 1, 5, 10.0, 10.0, 10.0, 0.0, 9.5, 1.0,
          icelltype=1, keep_going=True,
          ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-8\n  OUTER_MAXIMUM 200\n"
                  "  UNDER_RELAXATION COOLEY\n  UNDER_RELAXATION_GAMMA 0.0",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-9\n"
                  "  INNER_RCLOSE 1.0e-6\n  LINEAR_ACCELERATION CG"),
          packages=[("CHD", listpkg([(1, 1, 1, 1.0)])),
                    ("WEL", listpkg([(1, 1, 5, -0.6)]))])

    # One cell that a well drains: Newton under-relaxation holds its head
    # near the bottom until the change is small.
    model("nur_single_cell", 1, 1, 1, 10.0, 10.0, 10.0, 0.0, 5.0, 1.0,
          icelltype=1, newton="  NEWTON UNDER_RELAXATION", keep_going=True,
          periods=((1.0, 1, 1.0), (1.0, 2, 1.0)),
          sto={"iconvert": 1, "ss": 1e-5, "sy": 0.1},
          sto_periods=[(1, "TRANSIENT")],
          ims=NEWTON_IMS.replace("OUTER_MAXIMUM 200", "OUTER_MAXIMUM 400"),
          packages=[("WEL", listpkg([(1, 1, 1, -80.0)]))])
    # Dry cells that wet only from below, and a dry cell over a dry cell.
    model("rewet_vertical", 2, 1, 4, 10.0, 10.0, 10.0, (5.0, 0.0),
          ([8.0, 4.0, 4.0, 8.0], [8.0, 8.0, -1.0, 8.0]), 1.0,
          icelltype=(1, 1), npf_options="  REWET WETFCT 1.0 IWETIT 1 IHDWET 0",
          npf_arrays=[("WETDRY", (-1.0, -1.0))], keep_going=True,
          ims=ims(nonlinear="  OUTER_DVCLOSE 1.0e-6\n  OUTER_MAXIMUM 100",
                  linear="  INNER_MAXIMUM 300\n  INNER_DVCLOSE 1.0e-7\n"
                  "  INNER_RCLOSE 1.0e-4\n  LINEAR_ACCELERATION BICGSTAB"),
          packages=[("CHD", listpkg([(2, 1, 1, 8.0), (2, 1, 4, 7.0)]))])


def solver_case(name, nlay, nrow, ncol, newton, lin, ur, gamma, scal, rcl,
                relax, north, inner, outer, dvclose, rclose, ict, k, strt, chd,
                q, rch):
    """Write a small model with every solver setting given.

    A search over small models found each of these settings. Each one
    reaches a rare branch of the solver: a breakdown test of an inner
    method, a residual of zero, or a reversed change under Cooley.
    """
    nl = "  OUTER_DVCLOSE %g\n  OUTER_MAXIMUM %d" % (dvclose, outer)
    if ur != "NONE":
        nl += "\n  UNDER_RELAXATION %s\n  UNDER_RELAXATION_GAMMA %g" % (ur,
                                                                     gamma)
        if ur == "DBD":
            nl += "\n  UNDER_RELAXATION_THETA 0.7\n  UNDER_RELAXATION_KAPPA 0.1"
    li = ("  INNER_MAXIMUM %d\n  INNER_DVCLOSE %g\n  INNER_RCLOSE %g%s\n"
          "  LINEAR_ACCELERATION %s\n  SCALING_METHOD %s\n"
          "  RELAXATION_FACTOR %g\n  NUMBER_ORTHOGONALIZATIONS %d" % (
              inner, dvclose, rclose, rcl, lin, scal, relax, north))
    pk = []
    if chd is not None:
        pk.append(("CHD", listpkg([(1, 1, 1, chd)])))
    if q != 0.0:
        pk.append(("WEL", listpkg([(nlay, nrow, ncol, q)])))
    if rch != 0.0:
        pk.append(("RCH", listpkg([(1, r, c, rch) for r in range(1, nrow + 1)
                                   for c in range(1, ncol + 1)])))
    botm = 0.0 if nlay == 1 else (5.0, 0.0)
    model(name, nlay, nrow, ncol, 10.0, 10.0, 10.0, botm, strt, k,
          icelltype=ict, newton="  NEWTON UNDER_RELAXATION" if newton else "",
          ims=ims(nonlinear=nl, linear=li), packages=pk, keep_going=True)


def solver_cases():
    """Write the cases of the rare branches of the solver."""
    # BiCGSTAB with a residual of zero, the same rho and the same omega, and
    # Cooley under-relaxation of a change that reverses, under Newton with
    # pseudo-transient continuation at the same residual.
    solver_case("solver_bicgstab_breakdown", 1, 1, 2, True, "BICGSTAB",
                "COOLEY", 0.0, "NONE", "", 0.0, 1, 300, 50, 1e-12, 1e-3, 1,
                1.0, 5.0, None, -5.0, 0.01)
    # BiCGSTAB where rho times omega is zero.
    solver_case("solver_bicgstab_rho_omega", 1, 1, 3, False, "BICGSTAB", "DBD",
                0.0, "NONE", " RELATIVE_RCLOSE", 0.0, 2, 300, 50, 1e-30, 0.0,
                1, 0.01, 5.0, 8.0, -5.0, 0.2)
    # BiCGSTAB where alpha does not change.
    solver_case("solver_bicgstab_alpha", 2, 1, 2, True, "BICGSTAB", "NONE",
                0.2, "NONE", "", 0.0, 0, 300, 3, 1e-30, 1e-12, 1, 1.0, 9.9,
                5.0, 0.0, 0.01)
    # CG with L2 norm scaling, the strict test, and the same rho.
    solver_case("solver_cg_same_rho", 2, 2, 1, False, "CG", "COOLEY", 0.8,
                "L2NORM", " STRICT", 0.97, 2, 300, 50, 1e-30, 1e-12, 0, 1.0,
                9.9, 5.0, -50.0, 0.0)
    # CG with a residual of zero.
    solver_case("solver_cg_zero_residual", 1, 2, 2, False, "CG", "COOLEY",
                0.2, "NONE", "", 0.0, 1, 1, 10, 1e-30, 1e-3, 1, 0.01, 5.0,
                1.0, 0.0, 0.01)
    # CG where rho becomes zero after a step.
    solver_case("solver_cg_zero_rho", 1, 1, 5, False, "CG", "NONE", 0.8,
                "L2NORM", " STRICT", 0.97, 0, 5, 10, 1e-12, 1e-3, 0, 0.01,
                1.0, None, -50.0, 0.2)
    # Pseudo-transient continuation at a residual of zero.
    solver_case("solver_ptc_zero_residual", 2, 1, 2, True, "BICGSTAB", "NONE",
                0.0, "L2NORM", "", 0.0, 1, 1, 50, 1e-6, 1e-3, 1, 1.0, 1.0,
                None, -0.5, 0.0)


def main():
    mf6 = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        "~/mf6build/src/mf6")
    cases()
    for case in sorted(os.listdir(CASES)):
        folder = os.path.join(CASES, case)
        work = tempfile.mkdtemp()
        try:
            for f in os.listdir(folder):
                shutil.copy(os.path.join(folder, f), work)
            r = subprocess.run([mf6], cwd=work, capture_output=True, text=True)
            if r.returncode != 0 or "Normal termination" not in r.stdout:
                print(case, "failed:", "\n".join(r.stdout.splitlines()[-5:]))
                lst = os.path.join(work, "model.lst")
                if os.path.exists(lst):
                    print("\n".join(open(lst).read().splitlines()[-15:]))
                raise SystemExit(1)
            write_expected(folder, work, "model")
            print(case, "ok")
        finally:
            shutil.rmtree(work)


if __name__ == "__main__":
    main()
