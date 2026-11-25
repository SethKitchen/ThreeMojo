# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read MODFLOW 6 input files: each option, and each error of each reader.

Each test writes a small simulation to a temporary folder. It changes one
text of the base simulation, then runs it. The base has two layers of
three cells, a constant head and a well.
"""

from std.os import remove, rmdir
from std.os.path import join
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from extensions.groundwater.simulation import Simulation
from units.si import METER


comptime Files = Dict[String, String]


def _base() -> Files:
    """Return the files of the base simulation.

    Returns:
        The text of each file, by name.
    """
    var f = Files()
    f["mfsim.nam"] = (
        "BEGIN options\nEND options\nBEGIN timing\n  TDIS6 model.tdis\n"
        "END timing\nBEGIN models\n  GWF6 model.nam model\nEND models\n"
        "BEGIN solutiongroup 1\n  IMS6 model.ims model\nEND solutiongroup\n"
    )
    f["model.tdis"] = (
        "BEGIN options\n  TIME_UNITS DAYS\nEND options\nBEGIN dimensions\n"
        "  NPER 1\nEND dimensions\nBEGIN perioddata\n  1.0 1 1.0\n"
        "END perioddata\n"
    )
    f["model.nam"] = (
        "BEGIN options\nEND options\nBEGIN packages\n  DIS6 model.dis dis\n"
        "  IC6 model.ic ic\n  NPF6 model.npf npf\n  OC6 model.oc oc\n"
        "  CHD6 model.chd chd\n  WEL6 model.wel wel\nEND packages\n"
    )
    f["model.dis"] = (
        "BEGIN options\n  LENGTH_UNITS METERS\nEND options\n"
        "BEGIN dimensions\n  NLAY 2\n  NROW 1\n  NCOL 3\nEND dimensions\n"
        "BEGIN griddata\n  DELR\n    CONSTANT 10.0\n  DELC\n"
        "    CONSTANT 10.0\n  TOP\n    CONSTANT 10.0\n  BOTM LAYERED\n"
        "    CONSTANT 5.0\n    CONSTANT 0.0\nEND griddata\n"
    )
    f["model.ic"] = "BEGIN griddata\n  STRT\n    CONSTANT 8.0\nEND griddata\n"
    f["model.npf"] = (
        "BEGIN options\nEND options\nBEGIN griddata\n  ICELLTYPE\n"
        "    CONSTANT 0\n  K\n    CONSTANT 1.0\nEND griddata\n"
    )
    f["model.ims"] = (
        "BEGIN options\nEND options\nBEGIN nonlinear\nEND nonlinear\n"
        "BEGIN linear\nEND linear\n"
    )
    f["model.oc"] = "BEGIN options\nEND options\n"
    f["model.chd"] = (
        "BEGIN options\nEND options\nBEGIN dimensions\n  MAXBOUND 1\n"
        "END dimensions\nBEGIN period 1\n  1 1 1 8.0\nEND period\n"
    )
    f["model.wel"] = (
        "BEGIN options\nEND options\nBEGIN dimensions\n  MAXBOUND 1\n"
        "END dimensions\nBEGIN period 1\n  2 1 3 -1.0\nEND period\n"
    )
    return f^


def _with(var f: Files, name: String, old: String, new: String) raises -> Files:
    """Return the files with one text of one file replaced.

    Args:
        f: The files.
        name: The file.
        old: The text to replace. It must be in the file.
        new: The new text.

    Returns:
        The changed files.

    Raises:
        Error: The file does not hold the text.
    """
    var t = f[name]
    if t.find(old) < 0:
        raise Error(String(name, " has no '", old, "'"))
    f[name] = t.replace(old, new)
    return f^


def _load(f: Files) raises -> Simulation:
    """Write the files to a new folder, read the simulation and remove the folder.

    Args:
        f: The files.

    Returns:
        The simulation, before its first step.

    Raises:
        Error: The simulation cannot be read.
    """
    var folder = mkdtemp(prefix="modflow-input-")
    for e in f.items():
        Path(join(folder, e.key)).write_text(e.value)
    var msg = String()
    var sim = Optional[Simulation]()
    try:
        sim = Simulation(folder)
    except e:
        msg = String(e)
    for e in f.items():
        remove(join(folder, e.key))
    rmdir(folder)
    if not sim:
        raise Error(msg)
    return sim.take()


def _run(f: Files) raises -> Simulation:
    """Read a simulation and run each step.

    Args:
        f: The files.

    Returns:
        The simulation after its last step.

    Raises:
        Error: The simulation cannot be read or run.
    """
    var sim = _load(f)
    while not sim.done():
        sim.step()
    return sim^


def _fails(f: Files, want: String) raises:
    """Check that a simulation fails with a message.

    Args:
        f: The files.
        want: A part of the message.

    Raises:
        Error: The simulation runs, or fails with another message.
    """
    var msg = String()
    try:
        _ = _run(f)
    except e:
        msg = String(e)
    if msg.byte_length() == 0 or msg.find(want) < 0:
        raise Error(String("want an error with '", want, "', got '", msg, "'"))


def _fails_with(name: String, old: String, new: String, want: String) raises:
    """Change the base simulation and check that it fails with a message.

    Args:
        name: The file to change.
        old: The text to replace.
        new: The new text.
        want: A part of the message.

    Raises:
        Error: The simulation runs, or fails with another message.
    """
    _fails(_with(_base(), name, old, new), want)


def test_the_base_runs() raises:
    """The base simulation converges, and its well cell is below the constant head.
    """
    var sim = _run(_base())
    assert_equal(sim.icnvg, 1)
    assert_true(sim.head(2, 1, 3) < sim.head(1, 1, 1))
    assert_true(sim.head(1, 1, 1).to(METER) == 8.0)


def test_simulation_name_file_errors() raises:
    """Each error of `mfsim.nam`."""
    _fails_with("mfsim.nam", "  TDIS6 model.tdis\n", "", "no TDIS6 file")
    _fails_with(
        "mfsim.nam",
        "  GWF6 model.nam model\n",
        "  GWF6 model.nam model\n  GWF6 b.nam b\n",
        "one model",
    )
    _fails_with(
        "mfsim.nam", "GWF6 model.nam model", "GWT6 model.nam model", "one GWF6"
    )
    _fails_with(
        "mfsim.nam",
        "BEGIN models\n  GWF6 model.nam model\nEND models\n",
        "",
        "no GWF6",
    )
    _fails_with(
        "mfsim.nam",
        "  IMS6 model.ims model\n",
        "  IMS6 model.ims model\n  MXITER 2\n",
        "MXITER of 1",
    )
    _fails_with(
        "mfsim.nam",
        "  IMS6 model.ims model\n",
        "  IMS6 model.ims model\n  EMS6 a b\n",
        "does not support EMS6",
    )
    _fails_with("mfsim.nam", "  IMS6 model.ims model\n", "", "no IMS6 file")
    _fails_with(
        "mfsim.nam",
        "BEGIN timing\n  TDIS6 model.tdis\nEND timing\n",
        "",
        "no TDIS6",
    )
    _fails_with(
        "mfsim.nam",
        "BEGIN solutiongroup 1\n  IMS6 model.ims model\nEND solutiongroup\n",
        "",
        "no IMS6",
    )
    _fails_with("mfsim.nam", "TDIS6 model.tdis", "TDIS6 missing.tdis", "")


def test_simulation_name_file_options() raises:
    """MXITER 1 is allowed, and words of other options are skipped."""
    var f = _with(
        _base(),
        "mfsim.nam",
        "  IMS6 model.ims model\n",
        "  IMS6 model.ims model\n  MXITER 1\n",
    )
    f = _with(
        f^,
        "mfsim.nam",
        "BEGIN options\n",
        "BEGIN options\n  MEMORY_PRINT_OPTION SUMMARY\n",
    )
    f = _with(
        f^, "mfsim.nam", "  TDIS6 model.tdis\n", "  TDIS6 model.tdis\n  TDIS\n"
    )
    _ = _run(f)


def test_model_name_file_errors() raises:
    """Each error of the GWF name file."""
    var pk = String(
        "BEGIN packages\n  DIS6 model.dis dis\n  IC6 model.ic ic\n  NPF6"
        " model.npf npf\n  OC6 model.oc oc\n  CHD6 model.chd chd\n  WEL6"
        " model.wel wel\nEND packages\n"
    )
    _fails_with("model.nam", pk, "", "no PACKAGES block")
    _fails_with(
        "model.nam",
        "  WEL6 model.wel wel\n",
        "  WEL6 model.wel wel\n  RIV6\n",
        "a file type and a file name",
    )
    _fails_with(
        "model.nam",
        "  WEL6 model.wel wel\n",
        "  WEL6 model.wel wel\n  MAW6 a.maw\n",
        "not a boundary package",
    )
    _fails_with("model.nam", "  DIS6 model.dis dis\n", "", "no DIS6 file")
    _fails_with("model.nam", "  IC6 model.ic ic\n", "", "no IC6 file")
    _fails_with("model.nam", "  NPF6 model.npf npf\n", "", "no NPF6 file")
    _fails_with(
        "model.nam", "BEGIN options\n", "BEGIN options\n  NEWTON\n", "BICGSTAB"
    )
    _fails_with(
        "model.ic",
        "BEGIN griddata\n  STRT\n    CONSTANT 8.0\nEND griddata\n",
        "BEGIN options\nEND options\n",
        "IC has no GRIDDATA",
    )


def test_model_name_file_options() raises:
    """Packages without names, OBS6, other model options and IC without STRT."""
    var f = _with(
        _base(),
        "model.nam",
        "  CHD6 model.chd chd\n  WEL6 model.wel wel\n",
        "  CHD6 model.chd\n  WEL6 model.wel\n  OBS6 model.obs\n",
    )
    f = _with(
        f^, "model.nam", "BEGIN options\n", "BEGIN options\n  PRINT_INPUT\n"
    )
    f = _with(f^, "model.ic", "  STRT\n    CONSTANT 8.0\n", "")
    var sim = _run(f)
    assert_equal(sim.bnds[0].name, "WEL-1")
    assert_equal(sim.bnds[1].name, "CHD-1")
    assert_true(sim.head(1, 1, 1).to(METER) == 8.0)


def test_block_and_word_errors() raises:
    """A line outside a block, a block that does not end, and bad numbers."""
    _fails_with(
        "model.dis",
        "BEGIN options\n",
        "junk\nBEGIN options\n",
        "outside a block",
    )
    _fails_with(
        "model.dis",
        "BEGIN options\n",
        "BEGIN\nBEGIN options\n",
        "outside a block",
    )
    _fails_with("model.ic", "END griddata\n", "", "does not end")
    _fails_with(
        "model.ic", "CONSTANT 8.0", "CONSTANT abc", "cannot read a real number"
    )
    _fails_with(
        "model.ic", "CONSTANT 8.0", "CONSTANT 8.0x", "cannot read a real number"
    )
    _fails_with("model.dis", "NLAY 2", "NLAY x", "cannot read an integer")
    _fails_with("model.dis", "NLAY 2", "NLAY -", "cannot read an integer")
    _fails_with("model.dis", "NLAY 2", "NLAY 2x", "cannot read an integer")


def test_words_comments_and_signs() raises:
    """Comments of each kind, quoted words, commas, tabs and signs."""
    var f = _with(
        _base(),
        "model.dis",
        "  NLAY 2\n",
        "# a comment\n! another\n// a third\n\n  NLAY +2\n",
    )
    f = _with(f^, "model.dis", "  NCOL 3\n", "  NCOL,\t3\r\n")
    f = _with(
        f^,
        "model.dis",
        "  DELR\n",
        "  DELR\n  # between the name and the control\n",
    )
    f = _with(
        f^,
        "model.nam",
        "  WEL6 model.wel wel\n",
        "  WEL6 'model.wel' \"wel\"\n",
    )
    f = _with(f^, "model.wel", "  2 1 3 -1.0\n", "  2 1 3 -1.0E0\n")
    var sim = _run(f)
    assert_equal(sim.dis.nlay, 2)
    assert_equal(sim.dis.ncol, 3)
    assert_equal(sim.bnds[0].name, "WEL")


def test_array_controls() raises:
    """INTERNAL with repeats, IPRN and FACTOR, OPEN/CLOSE, and integer arrays.
    """
    var f = _with(
        _base(),
        "model.ic",
        "  STRT\n    CONSTANT 8.0\n",
        (
            "  STRT LAYERED\n    INTERNAL IPRN 3 FACTOR 2.0\n      3*4.0\n   "
            " OPEN/CLOSE strt2.txt FACTOR 1.0\n"
        ),
    )
    f["strt2.txt"] = "8.0 8.0\n8.0\n"
    f = _with(
        f^,
        "model.npf",
        "  ICELLTYPE\n    CONSTANT 0\n",
        (
            "  ICELLTYPE LAYERED\n    INTERNAL FACTOR 1\n      0 0 0\n   "
            " OPEN/CLOSE ict.txt FACTOR 0\n"
        ),
    )
    f["ict.txt"] = "5 5 5\n"
    f = _with(
        f^,
        "model.npf",
        "  K\n    CONSTANT 1.0\n",
        "  K\n    INTERNAL FACTOR 0.0\n      6*1.0\n",
    )
    var sim = _run(f)
    assert_equal(sim.npf.icelltype[4], 5)
    assert_equal(sim.strt[2], 8.0)


def test_array_control_errors() raises:
    """Each error of an array control line."""
    _fails_with(
        "model.ic",
        "  STRT\n    CONSTANT 8.0\n",
        "  STRT\n",
        "control record for STRT",
    )
    _fails_with(
        "model.ic", "CONSTANT 8.0", "CONSTANT", "control record for STRT"
    )
    _fails_with(
        "model.ic", "CONSTANT 8.0", "OPEN/CLOSE", "control record for STRT"
    )
    _fails_with(
        "model.ic", "CONSTANT 8.0", "EXTERNAL x", "Use CONSTANT, INTERNAL"
    )
    _fails_with(
        "model.ic", "CONSTANT 8.0", "INTERNAL (BINARY)\n 6*8.0", "binary arrays"
    )
    _fails_with("model.ic", "CONSTANT 8.0", "INTERNAL\n 5*8.0", "the data ends")
    _fails_with(
        "model.npf",
        "  ICELLTYPE\n    CONSTANT 0\n",
        "  ICELLTYPE\n",
        "control record for ICELLTYPE",
    )


def test_time_units() raises:
    """Each TIME_UNITS, and a TDIS with no OPTIONS or DIMENSIONS block."""
    var names: List[String] = [
        "SECONDS",
        "MINUTES",
        "HOURS",
        "DAYS",
        "YEARS",
        "UNKNOWN",
    ]
    var codes: List[Int] = [1, 2, 3, 4, 5, 0]
    for i in range(len(names)):
        var sim = _load(_with(_base(), "model.tdis", "DAYS", names[i]))
        assert_equal(sim.tdis.itmuni, codes[i])
    var f = _with(
        _base(),
        "model.tdis",
        "BEGIN options\n  TIME_UNITS DAYS\nEND options\n",
        "",
    )
    f = _with(
        f^, "model.tdis", "BEGIN dimensions\n  NPER 1\nEND dimensions\n", ""
    )
    var sim = _load(f)
    assert_equal(sim.tdis.nper, 1)
    sim = _load(
        _with(_base(), "model.tdis", "  TIME_UNITS DAYS\n", "  TIME_UNITS\n")
    )
    sim = _load(_with(_base(), "model.tdis", "  NPER 1\n", "  NPER\n"))


def test_time_discretization_errors() raises:
    """Each error of TDIS6."""
    _fails_with("model.tdis", "NPER 1", "NPER 0", "NPER must be")
    _fails_with(
        "model.tdis",
        "BEGIN perioddata\n  1.0 1 1.0\nEND perioddata\n",
        "",
        "no PERIODDATA",
    )
    _fails_with("model.tdis", "NPER 1", "NPER 2", "fewer lines than NPER")
    _fails_with(
        "model.tdis", "  1.0 1 1.0\n", "  1.0 1\n", "PERLEN, NSTP and TSMULT"
    )
    _fails_with(
        "model.tdis", "  1.0 1 1.0\n", "  1.0 0 1.0\n", "NSTP of period 1"
    )
    _fails_with(
        "model.tdis", "  1.0 1 1.0\n", "  -1.0 1 1.0\n", "PERLEN of period 1"
    )
    _fails_with(
        "model.tdis", "  1.0 1 1.0\n", "  1.0 1 0.0\n", "TSMULT of period 1"
    )


def test_length_units_and_heads() raises:
    """Each LENGTH_UNITS gives the head in its unit, and `head` checks its cell.
    """
    var names: List[String] = ["FEET", "METERS", "CENTIMETERS", "UNKNOWN"]
    var codes: List[Int] = [1, 2, 3, 0]
    var meters: List[Float64] = [8.0 * 0.3048, 8.0, 0.08, 8.0]
    for i in range(len(names)):
        var sim = _run(_with(_base(), "model.dis", "METERS", names[i]))
        assert_equal(sim.dis.length_units, codes[i])
        var got = Float64(sim.head(1, 1, 1).to(METER))
        assert_true(abs(got - meters[i]) < 1e-12, String(names[i], " ", got))
    var f = _with(
        _base(),
        "model.dis",
        "BEGIN options\n  LENGTH_UNITS METERS\nEND options\n",
        "",
    )
    f = _with(
        f^,
        "model.dis",
        "  BOTM LAYERED\n    CONSTANT 5.0\n    CONSTANT 0.0\n",
        (
            "  BOTM LAYERED\n    CONSTANT 5.0\n    CONSTANT 0.0\n  IDOMAIN"
            " LAYERED\n    INTERNAL\n      1 1 1\n    INTERNAL\n      1 1 0\n"
        ),
    )
    f = _with(f^, "model.wel", "  2 1 3 -1.0\n", "  2 1 2 -1.0\n")
    var sim = _run(f)
    assert_equal(sim.dis.length_units, 0)
    var h = sim.heads()
    assert_equal(h[6], 1.0e30)
    var cells: List[Int] = [
        0,
        1,
        1,
        3,
        1,
        1,
        1,
        0,
        1,
        1,
        2,
        1,
        1,
        1,
        0,
        1,
        1,
        4,
    ]
    for i in range(0, len(cells), 3):
        var msg = String()
        try:
            _ = sim.head(cells[i], cells[i + 1], cells[i + 2])
        except e:
            msg = String(e)
        assert_true(msg.find("outside the grid") >= 0)
    var msg = String()
    try:
        _ = sim.head(2, 1, 3)
    except e:
        msg = String(e)
    assert_true(msg.find("not in the model") >= 0)


def test_grid_errors() raises:
    """Each error of DIS6."""
    _fails_with(
        "model.dis",
        "BEGIN dimensions\n  NLAY 2\n  NROW 1\n  NCOL 3\nEND dimensions\n",
        "",
        "no DIMENSIONS block",
    )
    _fails_with("model.dis", "NLAY 2", "NLAY 0", "NLAY was not specified")
    _fails_with("model.dis", "NROW 1", "NROW 0", "NROW was not specified")
    _fails_with("model.dis", "NCOL 3", "NCOL 0", "NCOL was not specified")
    _ = _load(_with(_base(), "model.dis", "  NROW 1\n", "  NROW\n  NROW 1\n"))
    _fails_with(
        "model.dis", "BEGIN griddata", "BEGIN other", "no GRIDDATA block"
    )
    _fails_with(
        "model.dis", "  DELR\n    CONSTANT 10.0\n", "", "DELR not found"
    )
    _fails_with(
        "model.dis", "  DELC\n    CONSTANT 10.0\n", "", "DELC not found"
    )
    _fails_with("model.dis", "  TOP\n    CONSTANT 10.0\n", "", "TOP not found")
    _fails_with(
        "model.dis",
        "  BOTM LAYERED\n    CONSTANT 5.0\n    CONSTANT 0.0\n",
        "",
        "BOTM not found",
    )
    _fails_with(
        "model.dis",
        "  DELR\n    CONSTANT 10.0\n",
        "  DELR\n    CONSTANT 0.0\n",
        "DELR(1) must be",
    )
    _fails_with(
        "model.dis",
        "  DELC\n    CONSTANT 10.0\n",
        "  DELC\n    CONSTANT 0.0\n",
        "DELC(1) must be",
    )
    _fails_with(
        "model.dis",
        "    CONSTANT 5.0\n",
        "    CONSTANT 12.0\n",
        "THICKNESS <= 0",
    )
    _fails_with(
        "model.dis",
        "    CONSTANT 0.0\nEND griddata",
        "    CONSTANT 0.0\n  IDOMAIN\n    CONSTANT 0\nEND griddata",
        "does not have any active nodes",
    )


def test_node_property_flow_options() raises:
    """The NPF options that the reference cases do not use."""
    var f = _with(
        _base(),
        "model.npf",
        "BEGIN options\n",
        (
            "BEGIN options\n  ALTERNATIVE_CELL_AVERAGING AMT-HMK\n  REWET"
            " WETFCT 0.5 IWETIT 0 IHDWET 1\n  DEV_NO_NEWTON\n  SAVE_FLOWS\n"
        ),
    )
    f = _with(
        f^,
        "model.npf",
        "END griddata",
        "  WETDRY\n    CONSTANT 0.5\nEND griddata",
    )
    var sim = _run(f)
    assert_equal(sim.npf.iwetit, 1)
    assert_equal(sim.npf.ihdwet, 1)
    sim = _run(
        _with(
            _base(),
            "model.npf",
            "BEGIN options\n",
            "BEGIN options\n  DEV_OMEGA 0.001\n",
        )
    )
    assert_equal(sim.npf.satomega, 0.001)
    # Newton sets omega again, as `check_options` does.
    f = _with(
        _base(),
        "model.npf",
        "BEGIN options\n",
        "BEGIN options\n  DEV_OMEGA 0.001\n",
    )
    f = _with(f^, "model.nam", "BEGIN options\n", "BEGIN options\n  NEWTON\n")
    f = _with(
        f^,
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  LINEAR_ACCELERATION BICGSTAB\n",
    )
    sim = _run(f)
    assert_equal(sim.npf.satomega, 1.0e-6)
    f = _with(
        _base(),
        "model.npf",
        "BEGIN options\n",
        "BEGIN options\n  DEV_NO_NEWTON\n",
    )
    f = _with(f^, "model.nam", "BEGIN options\n", "BEGIN options\n  NEWTON\n")
    f = _with(
        f^,
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  LINEAR_ACCELERATION BICGSTAB\n",
    )
    sim = _run(f)
    assert_equal(sim.npf.inewton, 0)


def test_node_property_flow_errors() raises:
    """Each error of NPF6."""
    var newton = _with(
        _base(), "model.nam", "BEGIN options\n", "BEGIN options\n  NEWTON\n"
    )
    newton = _with(
        newton^,
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  LINEAR_ACCELERATION BICGSTAB\n",
    )
    _fails(
        _with(
            newton.copy(),
            "model.npf",
            "BEGIN options\n",
            "BEGIN options\n  PERCHED\n",
        ),
        "PERCHED",
    )
    _fails(
        _with(
            newton.copy(),
            "model.npf",
            "BEGIN options\n",
            "BEGIN options\n  VARIABLECV\n",
        ),
        "VARIABLECV",
    )
    _fails(
        _with(
            newton.copy(),
            "model.npf",
            "BEGIN options\n",
            "BEGIN options\n  REWET\n",
        ),
        "REWET",
    )
    _fails_with(
        "model.npf",
        "BEGIN options\n",
        "BEGIN options\n  ALTERNATIVE_CELL_AVERAGING\n",
        "ALTERNATIVE_CELL_AVERAGING",
    )
    _fails_with(
        "model.npf",
        "BEGIN options\n",
        "BEGIN options\n  ALTERNATIVE_CELL_AVERAGING MEDIAN\n",
        "Unrecognized input value",
    )
    _fails_with(
        "model.npf", "BEGIN options\n", "BEGIN options\n  XT3D\n", "XT3D"
    )
    _fails_with("model.npf", "BEGIN griddata", "BEGIN other", "no GRIDDATA")
    _fails_with(
        "model.npf", "  ICELLTYPE\n    CONSTANT 0\n", "", "ICELLTYPE not found"
    )
    _fails_with("model.npf", "  K\n    CONSTANT 1.0\n", "", "K not found")
    _fails_with(
        "model.npf",
        "BEGIN options\n",
        "BEGIN options\n  K33OVERK\n",
        "K33 not specified",
    )
    _fails_with(
        "model.npf",
        "BEGIN options\n",
        "BEGIN options\n  K22OVERK\n",
        "K22 not specified",
    )
    _fails_with("model.npf", "CONSTANT 1.0", "CONSTANT 0.0", "K value of")
    _fails_with(
        "model.npf",
        "END griddata",
        "  K33\n    CONSTANT -1.0\nEND griddata",
        "K33 of cell 1",
    )
    _fails_with(
        "model.npf",
        "END griddata",
        "  K22\n    CONSTANT 0.0\nEND griddata",
        "K22 of cell 1",
    )
    _fails_with(
        "model.npf", "BEGIN options\n", "BEGIN options\n  REWET\n", "WETDRY was"
    )
    _fails_with(
        "model.npf",
        "END griddata",
        "  ANGLE2\n    CONSTANT 1.0\nEND griddata",
        "ANGLE2 requires ANGLE1",
    )
    _fails_with(
        "model.npf",
        "END griddata",
        "  ANGLE1\n    CONSTANT 1.0\n  ANGLE2\n    CONSTANT 1.0\nEND griddata",
        "ANGLE2 requires ANGLE3",
    )
    _fails_with(
        "model.npf",
        "END griddata",
        "  ANGLE3\n    CONSTANT 1.0\nEND griddata",
        "ANGLE3 requires ANGLE1",
    )
    _fails_with(
        "model.npf",
        "END griddata",
        "  ANGLE1\n    CONSTANT 1.0\n  ANGLE3\n    CONSTANT 1.0\nEND griddata",
        "ANGLE3 requires ANGLE2",
    )
    # Without Newton the cell goes dry first, so only Newton reaches the error.
    var thick = _with(
        newton.copy(),
        "model.npf",
        "BEGIN options\n",
        "BEGIN options\n  THICKSTRT\n",
    )
    thick = _with(thick^, "model.npf", "    CONSTANT 0\n", "    CONSTANT -1\n")
    thick = _with(thick^, "model.ic", "CONSTANT 8.0", "CONSTANT 4.0")
    _fails(thick, "dry at the start")
    var dry = _with(
        _base(), "model.npf", "    CONSTANT 0\n", "    CONSTANT 1\n"
    )
    dry = _with(dry^, "model.chd", "  1 1 1 8.0\n", "  1 1 1 4.0\n")
    _fails(dry, "")


def test_storage_options_and_errors() raises:
    """The STO options, and each error of STO6."""
    var sto = String(
        "BEGIN options\n  DEV_OLDSTORAGEFORMULATION\nEND options\nBEGIN"
        " griddata\n  ICONVERT\n    CONSTANT 1\n  SS\n    CONSTANT 1.0E-5\n "
        " SY\n    CONSTANT 0.1\nEND griddata\nBEGIN period 1\nEND period\nBEGIN"
        " period 2\n  TRANSIENT\nEND period\n"
    )
    var f = _with(
        _base(),
        "model.nam",
        "  OC6 model.oc oc\n",
        "  OC6 model.oc oc\n  STO6 model.sto sto\n",
    )
    f = _with(f^, "model.tdis", "NPER 1", "NPER 2")
    f = _with(f^, "model.tdis", "  1.0 1 1.0\n", "  1.0 1 1.0\n  1.0 1 1.0\n")
    var g = f.copy()
    g["model.sto"] = sto
    var sim = _run(g)
    assert_equal(sim.sto.iconf_ss, 1)
    assert_equal(sim.iss, 0)
    var cases: List[String] = [
        "BEGIN griddata",
        "BEGIN other",
        "STO has no GRIDDATA",
        "  ICONVERT\n    CONSTANT 1\n",
        "",
        "ICONVERT not found",
        "  SS\n    CONSTANT 1.0E-5\n",
        "",
        "SS not found",
        "  SY\n    CONSTANT 0.1\n",
        "",
        "SY not found",
        "CONSTANT 1.0E-5",
        "CONSTANT -1.0",
        "SS of cell 1",
        "CONSTANT 0.1",
        "CONSTANT -0.1",
        "SY of cell 1",
        "BEGIN period 1\n",
        "BEGIN period\n",
        "needs a period number",
        "  TRANSIENT\n",
        "  STEADY\n",
        "Unknown STO PERIOD keyword",
    ]
    for i in range(0, len(cases), 3):
        var h = f.copy()
        h["model.sto"] = sto.replace(cases[i], cases[i + 1])
        _fails(h, cases[i + 2])
    var h = f.copy()
    h["model.sto"] = (
        sto.replace(
            "BEGIN options\n  DEV_OLDSTORAGEFORMULATION\nEND options\n", ""
        )
        .replace("CONSTANT 1\n", "CONSTANT 0\n")
        .replace("  SY\n    CONSTANT 0.1\n", "")
    )
    _ = _run(h)


def test_boundary_options_and_errors() raises:
    """The boundary options, and each error of a boundary package."""
    _fails_with(
        "model.wel",
        "BEGIN options\n",
        "BEGIN options\n  MOVER\n",
        "MOVER option is not supported",
    )
    _fails_with(
        "model.wel",
        "BEGIN options\n",
        "BEGIN options\n  TS6 FILEIN a.ts\n",
        "TS6 option",
    )
    _fails_with(
        "model.wel",
        "BEGIN options\n",
        "BEGIN options\n  TAS6 FILEIN a.tas\n",
        "TAS6 option",
    )
    _fails_with(
        "model.wel",
        "BEGIN options\n",
        "BEGIN options\n  AUTO_FLOW_REDUCE 0.1\n",
        "AUTO_FLOW_REDUCE",
    )
    _fails_with(
        "model.wel",
        "BEGIN options\n",
        "BEGIN options\n  AUXDEPTHNAME d\n",
        "AUXDEPTHNAME",
    )
    _fails_with(
        "model.wel",
        "BEGIN options\n",
        "BEGIN options\n  AUX a\n  AUXMULTNAME b\n",
        "AUXMULTNAME",
    )
    _fails_with("model.wel", "MAXBOUND 1", "MAXBOUND 0", "MAXBOUND must be")
    _fails_with(
        "model.wel", "BEGIN period 1", "BEGIN period", "needs a period number"
    )
    _fails_with(
        "model.wel",
        "END period\n",
        "END period\nBEGIN period 1\nEND period\n",
        "increasing order",
    )
    _fails_with("model.wel", "  2 1 3 -1.0\n", "  2 1 3\n", "")
    _fails_with("model.wel", "  2 1 3 -1.0\n", "  3 1 3 -1.0\n", "")
    _fails_with("model.wel", "  2 1 3 -1.0\n", "  2 2 3 -1.0\n", "")
    _fails_with("model.wel", "  2 1 3 -1.0\n", "  2 1 4 -1.0\n", "")
    _fails_with("model.wel", "  2 1 3 -1.0\n", "  0 1 3 -1.0\n", "")
    _fails_with("model.wel", "  2 1 3 -1.0\n", "  2 0 3 -1.0\n", "")
    _fails_with("model.wel", "  2 1 3 -1.0\n", "  2 1 0 -1.0\n", "")
    _fails_with(
        "model.wel",
        "  2 1 3 -1.0\n",
        "  2 1 3 -1.0\n  2 1 2 -1.0\n",
        "MAXBOUND",
    )
    var two = _with(
        _base(),
        "model.nam",
        "  WEL6 model.wel wel\n",
        "  WEL6 model.wel wel\n  CHD6 model.chd2 chd2\n",
    )
    two["model.chd2"] = two["model.chd"]
    _fails(two, "already a constant head cell")
    var off = _with(
        _base(),
        "model.dis",
        "    CONSTANT 0.0\nEND griddata",
        (
            "    CONSTANT 0.0\n  IDOMAIN\n    INTERNAL\n      1 1 1 1 1 0\nEND"
            " griddata"
        ),
    )
    _fails(off, "outside active grid")
    var evt = String(
        "BEGIN options\nEND options\nBEGIN dimensions\n  MAXBOUND 1\n  NSEG 1\n"
        "END dimensions\nBEGIN period 1\n  1 1 2 9.0 0.001 2.0\nEND period\n"
    )
    var f = _with(
        _base(),
        "model.nam",
        "  WEL6 model.wel wel\n",
        "  WEL6 model.wel wel\n  EVT6 model.evt evt\n",
    )
    var g = f.copy()
    g["model.evt"] = evt
    _ = _run(g)
    g = f.copy()
    g["model.evt"] = evt.replace("NSEG 1", "NSEG 0")
    _fails(g, "NSEG must be")
    g = f.copy()
    g["model.evt"] = evt.replace(
        "BEGIN options\n", "BEGIN options\n  SURF_RATE_SPECIFIED\n"
    )
    _fails(g, "SURF_RATE_SPECIFIED requires")
    var rch = String(
        "BEGIN options\n  READASARRAYS\nEND options\nBEGIN period 1\n  IRCH\n"
        "    CONSTANT 3\nEND period\n"
    )
    f = _with(
        _base(),
        "model.nam",
        "  WEL6 model.wel wel\n",
        "  WEL6 model.wel wel\n  RCH6 model.rch rch\n",
    )
    g = f.copy()
    g["model.rch"] = rch
    _fails(g, "Invalid layer number: 3")
    g = f.copy()
    g["model.rch"] = rch.replace("CONSTANT 3", "CONSTANT 0")
    _fails(g, "Invalid layer number: 0")
    g = f.copy()
    g["model.rch"] = rch.replace(
        "BEGIN options\n", "BEGIN options\n  AUXILIARY m\n  AUXMULTNAME m\n"
    ).replace(
        "    CONSTANT 3\n",
        (
            "    CONSTANT 2\n  RECHARGE\n    CONSTANT 0.01\n  m\n    CONSTANT"
            " 2.0\n"
        ),
    )
    var sim = _run(g)
    assert_equal(sim.bnds[1].auxvar[1][0], 2.0)
    var empty = _with(
        _base(),
        "model.wel",
        (
            "BEGIN options\nEND options\nBEGIN dimensions\n  MAXBOUND 1\nEND"
            " dimensions\n"
        ),
        "BEGIN dimensions\n  MAXBOUND\nEND dimensions\n",
    )
    _fails(empty, "MAXBOUND must be")


def test_constant_head_cell_that_goes_dry() raises:
    """A constant head below the bottom of a convertible cell is an error."""
    var f = _with(_base(), "model.npf", "    CONSTANT 0\n", "    CONSTANT 1\n")
    f = _with(f^, "model.chd", "  1 1 1 8.0\n", "  1 1 1 4.0\n")
    f = _with(f^, "model.ic", "CONSTANT 8.0", "CONSTANT 9.0")
    _fails(f, "")


def test_solver_options() raises:
    """The IMS options and settings that the reference cases do not use."""
    var f = _with(
        _base(),
        "model.ims",
        "BEGIN options\n",
        (
            "BEGIN options\n  NO_PTC ALL\n  DEV_PTC\n  CSV_OUTER_OUTPUT FILEOUT"
            " o.csv\n  CSV_INNER_OUTPUT FILEOUT i.csv\n "
            " ATS_OUTER_MAXIMUM_FRACTION 0.5\n  DEV_PTC_EXPONENT -1.0\n "
            " DEV_PTC_DEL0 -1.0\n"
        ),
    )
    f = _with(
        f^,
        "model.ims",
        "BEGIN linear\n",
        (
            "BEGIN linear\n  INNER_RCLOSE 0.1 OTHER\n  PRECONDITIONER_LEVELS"
            " 0\n  PRECONDITIONER_DROP_TOLERANCE 0.0\n"
        ),
    )
    var sim = _run(f)
    assert_equal(sim.nl.iallowptc, 1)
    assert_equal(sim.nl.ptcexp, 1.0)
    f = _with(_base(), "model.ims", "BEGIN options\nEND options\n", "")
    f = _with(f^, "model.ims", "BEGIN nonlinear\nEND nonlinear\n", "")
    f = _with(f^, "model.ims", "BEGIN linear\nEND linear\n", "")
    sim = _run(f)
    assert_equal(sim.nl.mxiter, 25)


def test_solver_errors() raises:
    """Each error of IMS6."""
    _fails_with(
        "model.ims",
        "BEGIN options\n",
        "BEGIN options\n  COMPLEXITY COMPLEX\n",
        "ILUT",
    )
    _fails_with(
        "model.ims",
        "BEGIN options\n",
        "BEGIN options\n  COMPLEXITY HARD\n",
        "COMPLEXITY option (HARD)",
    )
    _fails_with(
        "model.ims",
        "BEGIN options\n",
        "BEGIN options\n  COMPLEXITY\n",
        "IMS option",
    )
    _fails_with(
        "model.ims", "BEGIN options\n", "BEGIN options\n  FAST\n", "IMS option"
    )
    _fails_with(
        "model.ims",
        "BEGIN nonlinear\n",
        "BEGIN nonlinear\n  UNDER_RELAXATION FAST\n",
        "UNDER_RELAXATION specified (FAST)",
    )
    _fails_with(
        "model.ims",
        "BEGIN nonlinear\n",
        "BEGIN nonlinear\n  LINEAR_SOLVER PETSC\n",
        "LINEAR_SOLVER specified (PETSC)",
    )
    _fails_with(
        "model.ims",
        "BEGIN nonlinear\n",
        "BEGIN nonlinear\n  OUTER_MAXIMUM 0\n",
        "Outer iteration number",
    )
    _fails_with(
        "model.ims",
        "BEGIN nonlinear\n",
        (
            "BEGIN nonlinear\n  UNDER_RELAXATION SIMPLE\n "
            " UNDER_RELAXATION_GAMMA 0.0\n"
        ),
        "GAMMA must be",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  LINEAR_ACCELERATION GMRES\n",
        "GMRES",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  SCALING_METHOD CUBE\n",
        "CUBE",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  REORDERING_METHOD RCM\n",
        "reordering",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  REORDERING_METHOD MD\n",
        "reordering",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  REORDERING_METHOD AMD\n",
        "AMD",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  PRECONDITIONER_LEVELS -1\n",
        "LEVELS",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  PRECONDITIONER_DROP_TOLERANCE -1.0\n",
        "DROP_TOLERANCE",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  PRECONDITIONER_LEVELS 2\n",
        "ILUT",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  PRECONDITIONER_LEVELS 2\n  RELAXATION_FACTOR 0.5\n",
        "ILUT",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  RELAXATION_FACTOR 1.5\n",
        "RELAXATION_FACTOR must be",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  RELAXATION_FACTOR -0.5\n",
        "RELAXATION_FACTOR must be",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  NUMBER_ORTHOGONALIZATIONS -1\n",
        "ORTHOGONALIZATIONS",
    )
    _fails_with(
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  FAST\n",
        "IMSLINEAR keyword (FAST)",
    )


def test_solver_keywords_need_values() raises:
    """A keyword of IMS that needs a value is unknown without it."""
    var nonlinear: List[String] = [
        "OUTER_DVCLOSE",
        "OUTER_MAXIMUM",
        "UNDER_RELAXATION",
        "LINEAR_SOLVER",
        "UNDER_RELAXATION_THETA",
        "UNDER_RELAXATION_KAPPA",
        "UNDER_RELAXATION_GAMMA",
        "UNDER_RELAXATION_MOMENTUM",
        "BACKTRACKING_NUMBER",
        "BACKTRACKING_TOLERANCE",
        "BACKTRACKING_REDUCTION_FACTOR",
        "BACKTRACKING_RESIDUAL_LIMIT",
    ]
    for k in nonlinear:
        _fails_with(
            "model.ims",
            "BEGIN nonlinear\n",
            String("BEGIN nonlinear\n  ", k, "\n"),
            "NONLINEAR keyword",
        )
    var linear: List[String] = [
        "INNER_DVCLOSE",
        "INNER_RCLOSE",
        "INNER_MAXIMUM",
        "LINEAR_ACCELERATION",
        "SCALING_METHOD",
        "REORDERING_METHOD",
        "NUMBER_ORTHOGONALIZATIONS",
        "RELAXATION_FACTOR",
        "PRECONDITIONER_LEVELS",
        "PRECONDITIONER_DROP_TOLERANCE",
    ]
    for k in linear:
        _fails_with(
            "model.ims",
            "BEGIN linear\n",
            String("BEGIN linear\n  ", k, "\n"),
            "IMSLINEAR keyword",
        )
    var options: List[String] = ["DEV_PTC_EXPONENT", "DEV_PTC_DEL0"]
    for k in options:
        _fails_with(
            "model.ims",
            "BEGIN options\n",
            String("BEGIN options\n  ", k, "\n"),
            "IMS option",
        )


def test_a_step_that_does_not_converge() raises:
    """A step that does not converge stops a simulation without CONTINUE."""
    var f = _with(
        _base(),
        "model.ims",
        "BEGIN nonlinear\n",
        "BEGIN nonlinear\n  OUTER_MAXIMUM 1\n",
    )
    f = _with(
        f^,
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  INNER_MAXIMUM 1\n  INNER_DVCLOSE 1.0E-30\n",
    )
    f = _with(f^, "model.npf", "    CONSTANT 0\n", "    CONSTANT 1\n")
    _fails(f, "did not converge for stress period 1")
    f = _with(f^, "mfsim.nam", "BEGIN options\n", "BEGIN options\n  CONTINUE\n")
    var sim = _run(f)
    assert_equal(sim.icnvg, 0)


def test_name_file_words_that_are_missing_or_extra() raises:
    """Name files with no OPTIONS block, short lines and unknown words."""
    var f = _with(_base(), "mfsim.nam", "BEGIN options\nEND options\n", "")
    f = _with(f^, "model.nam", "BEGIN options\nEND options\n", "")
    _ = _run(f)
    _fails_with("mfsim.nam", "TDIS6 model.tdis", "TDIS6", "no TDIS6 file")
    _fails_with("mfsim.nam", "GWF6 model.nam model", "GWF6", "one GWF6")
    _fails_with(
        "mfsim.nam", "IMS6 model.ims model", "IMS6", "does not support IMS6"
    )
    _fails_with(
        "mfsim.nam",
        "  IMS6 model.ims model\n",
        "  IMS6 model.ims model\n  MXITER\n",
        "does not support MXITER",
    )
    _fails_with(
        "model.nam",
        (
            "BEGIN packages\n  DIS6 model.dis dis\n  IC6 model.ic ic\n  NPF6"
            " model.npf npf\n  OC6 model.oc oc\n  CHD6 model.chd chd\n  WEL6"
            " model.wel wel\nEND packages\n"
        ),
        "BEGIN packages\nEND packages\n",
        "no DIS6 file",
    )
    f = _with(
        _base(), "model.nam", "BEGIN options\n", "BEGIN options\n  NEWTON NOW\n"
    )
    f = _with(
        f^,
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  LINEAR_ACCELERATION BICGSTAB\n",
    )
    var sim = _run(f)
    assert_equal(sim.inewton, 1)
    assert_equal(sim.inewtonur, 0)
    _ = _run(
        _with(
            _base(),
            "model.ims",
            "BEGIN nonlinear\n",
            "BEGIN nonlinear\n  LINEAR_SOLVER LINEAR\n",
        )
    )


def test_other_options_and_dimensions() raises:
    """TDIS and DIS skip the options and dimensions that they do not use."""
    var f = _with(
        _base(),
        "model.tdis",
        "  TIME_UNITS DAYS\n",
        "  START_DATE_TIME 2000-01-01\n  TIME_UNITS DAYS\n",
    )
    f = _with(f^, "model.tdis", "  NPER 1\n", "  NOTHING 2\n  NPER 1\n")
    f = _with(
        f^,
        "model.dis",
        "  LENGTH_UNITS METERS\n",
        "  XORIGIN 0.0\n  LENGTH_UNITS\n  LENGTH_UNITS METERS\n",
    )
    f = _with(f^, "model.dis", "  NCOL 3\n", "  NCOL 3\n  NCPL 9\n")
    var sim = _run(f)
    assert_equal(sim.dis.length_units, 2)
    f = _with(_base(), "model.dis", "  LENGTH_UNITS METERS\n", "")
    _ = _run(f)
    _fails_with(
        "model.dis", "  NLAY 2\n  NROW 1\n  NCOL 3\n", "", "outside of the grid"
    )


def test_words_at_the_edges() raises:
    """Quotes that do not close, tabs, leading separators and slashes."""
    var f = _with(
        _base(),
        "model.nam",
        "  WEL6 model.wel wel\n",
        "  WEL6 model.wel 'wel\n",
    )
    f = _with(
        f^,
        "model.dis",
        "  NROW 1\n",
        "  NROW\t1\n,\t# a comment after separators\n\r\n\t\n",
    )
    f = _with(
        f^, "model.npf", "BEGIN options\n", "BEGIN options\n  /not-a-comment\n"
    )
    var sim = _run(f)
    assert_equal(sim.bnds[0].name, "WEL")
    _fails_with("model.dis", "NLAY 2", "NLAY ''", "cannot read an integer")
    _fails_with("model.dis", "NLAY 2", "NLAY 2.", "cannot read an integer")
    _fails_with(
        "model.ic", "CONSTANT 8.0", "CONSTANT ''", "cannot read a real number"
    )


def test_more_array_controls() raises:
    """Controls with a word missing or unknown, no factor, and no data value."""
    var f = _with(
        _base(),
        "model.ic",
        "  STRT\n    CONSTANT 8.0\n",
        (
            "  STRT LAYERED\n    INTERNAL IPRN\n      3*8.0\n    INTERNAL"
            " FACTOR\n      3*8.0\n"
        ),
    )
    _ = _run(f)
    f = _with(
        _base(),
        "model.ic",
        "    CONSTANT 8.0\n",
        "    INTERNAL JUNK\n\n      6*8.0\n",
    )
    _ = _run(f)
    f = _with(
        _base(),
        "model.ic",
        "    CONSTANT 8.0\n",
        "    INTERNAL FACTOR 1.0\n      8.0 8.0 3.0E30 8.0 8.0 8.0\n",
    )
    f = _with(
        f^, "model.npf", "    CONSTANT 0\n", "    INTERNAL\n      0 0 0 0 0 0\n"
    )
    var sim = _load(f)
    assert_equal(sim.strt[3], 3.0e30)
    f = _with(
        _base(),
        "model.npf",
        "  ICELLTYPE\n    CONSTANT 0\n  K\n    CONSTANT 1.0\n",
        "  K\n    CONSTANT 1.0\n  ICELLTYPE\n",
    )
    _fails(f, "control record for ICELLTYPE")


def test_more_boundary_options() raises:
    """Auxiliary words with no names, empty blocks and packages with no bounds.
    """
    _ = _run(
        _with(
            _base(),
            "model.wel",
            "BEGIN options\n",
            "BEGIN options\n  AUX\n  AUXMULTNAME\n",
        )
    )
    _fails_with(
        "model.wel",
        "BEGIN options\n",
        "BEGIN options\n  AUXMULTNAME m\n",
        "not an auxiliary name",
    )
    _fails_with("model.wel", "  MAXBOUND 1\n", "", "MAXBOUND must be")
    _ = _run(
        _with(_base(), "model.wel", "  MAXBOUND 1\n", "  MAXBOUND 1\n  NSEG\n")
    )
    _ = _run(
        _with(
            _base(),
            "model.wel",
            "BEGIN period 1\n  2 1 3 -1.0\nEND period\n",
            "",
        )
    )
    # A confined cell can hold a constant head under its bottom.
    _ = _run(_with(_base(), "model.chd", "  1 1 1 8.0\n", "  1 1 1 4.0\n"))


def test_packages_with_empty_periods() raises:
    """Each kind of package with a period of no bounds, and a model of no bounds.
    """
    var f = _base()
    var kinds: List[String] = ["WEL", "DRN", "RIV", "GHB", "RCH", "EVT", "CHD"]
    var pk = String()
    for k in kinds:
        var name = String("model.", k.lower(), "0")
        pk += String("  ", k, "6 ", name, " ", k.lower(), "0\n")
        f[name] = (
            "BEGIN dimensions\n  MAXBOUND 1\nEND dimensions\nBEGIN period"
            " 1\nEND period\n"
        )
    f = _with(
        f^, "model.nam", "  CHD6 model.chd chd\n  WEL6 model.wel wel\n", pk
    )
    var sim = _run(f)
    assert_equal(len(sim.bnds), 7)
    sim = _run(
        _with(
            _base(),
            "model.nam",
            "  CHD6 model.chd chd\n  WEL6 model.wel wel\n",
            "",
        )
    )
    assert_equal(len(sim.bnds), 0)
    assert_true(sim.head(2, 1, 3).to(METER) == 8.0)


def test_more_flow_options() raises:
    """NPF words with no value, a negative cell type, and THICKSTRT over a dry cell.
    """
    var f = _with(
        _base(),
        "model.npf",
        "BEGIN options\n",
        "BEGIN options\n  VARIABLECV NOW\n  DEV_OMEGA\n  REWET FOO 1\n",
    )
    f = _with(
        f^,
        "model.npf",
        "END griddata",
        "  WETDRY\n    CONSTANT 0.5\nEND griddata",
    )
    var sim = _run(f)
    assert_equal(sim.npf.idewatcv, 0)
    f = _with(_base(), "model.npf", "BEGIN options\nEND options\n", "")
    f = _with(f^, "model.npf", "    CONSTANT 0\n", "    CONSTANT -1\n")
    sim = _run(f)
    assert_equal(sim.npf.icelltype[1], 1)
    f = _with(
        _base(), "model.npf", "BEGIN options\n", "BEGIN options\n  THICKSTRT\n"
    )
    f = _with(
        f^,
        "model.npf",
        "    CONSTANT 0\n",
        "    INTERNAL\n      -1 -1 0 0 0 0\n",
    )
    f = _with(
        f^,
        "model.ic",
        "    CONSTANT 8.0\n",
        "    INTERNAL\n      8.0 4.0 8.0 8.0 8.0 8.0\n",
    )
    sim = _load(f)
    assert_equal(sim.npf.ithickstartflag[2], 1)
    assert_equal(sim.npf.icelltype[2], 0)


def test_a_constant_head_at_the_bottom_goes_dry() raises:
    """A constant head at the bottom of a convertible cell leaves it no thickness.
    """
    var f = _with(_base(), "model.npf", "    CONSTANT 0\n", "    CONSTANT 1\n")
    f = _with(f^, "model.chd", "  1 1 1 8.0\n", "  1 1 1 5.0\n")
    _fails(f, "CONSTANT-HEAD CELL WENT DRY")


def test_storage_with_empty_options() raises:
    """STO with an empty OPTIONS block."""
    var f = _with(
        _base(),
        "model.nam",
        "  OC6 model.oc oc\n",
        "  OC6 model.oc oc\n  STO6 model.sto sto\n",
    )
    f["model.sto"] = (
        "BEGIN options\nEND options\nBEGIN griddata\n  ICONVERT\n    CONSTANT"
        " 0\n  SS\n    CONSTANT 1.0E-5\n  SY\n    CONSTANT 0.1\nEND"
        " griddata\nBEGIN period 1\n  TRANSIENT\nEND period\n"
    )
    var sim = _run(f)
    assert_equal(sim.iss, 0)


def test_newton_with_no_residual() raises:
    """Newton with heads that already balance: the continuation factor has no residual.
    """
    var f = _with(
        _base(), "model.nam", "BEGIN options\n", "BEGIN options\n  NEWTON\n"
    )
    f = _with(
        f^,
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  LINEAR_ACCELERATION BICGSTAB\n",
    )
    f = _with(f^, "model.wel", "  2 1 3 -1.0\n", "  2 1 3 0.0\n")
    var sim = _run(f)
    assert_equal(sim.icnvg, 1)
    assert_true(sim.head(2, 1, 3).to(METER) == 8.0)


def test_the_highest_active_cell_of_a_lone_cell() raises:
    """A cell with no neighbors is the bottom of its own column."""
    var f = _with(
        _base(),
        "model.dis",
        "    CONSTANT 0.0\nEND griddata",
        (
            "    CONSTANT 0.0\n  IDOMAIN\n    INTERNAL\n      1 0 1 0 0 0\nEND"
            " griddata"
        ),
    )
    f = _with(f^, "model.wel", "  2 1 3 -1.0\n", "  1 1 3 0.0\n")
    var sim = _run(f)
    var ib = sim.ibound.copy()
    ib[2] = 0
    assert_equal(sim.bnds[0]._highest_active(sim.dis, 2, ib), 2)


def test_empty_blocks_and_no_periods() raises:
    """TDIS with empty blocks, and STO with no PERIOD block."""
    var f = _with(_base(), "model.tdis", "  TIME_UNITS DAYS\n", "")
    f = _with(f^, "model.tdis", "  NPER 1\n", "")
    var sim = _run(f)
    assert_equal(sim.tdis.nper, 1)
    f = _with(
        _base(),
        "model.nam",
        "  OC6 model.oc oc\n",
        "  OC6 model.oc oc\n  STO6 model.sto sto\n",
    )
    f["model.sto"] = (
        "BEGIN griddata\n  ICONVERT\n    CONSTANT 0\n  SS\n    CONSTANT"
        " 1.0E-5\n  SY\n    CONSTANT 0.1\nEND griddata\n"
    )
    sim = _run(f)
    assert_equal(sim.iss, 1)


def _newton_ur(var f: Files) raises -> Files:
    """Turn on Newton with under-relaxation and BICGSTAB.

    Args:
        f: The files.

    Returns:
        The changed files.

    Raises:
        Error: A text to replace is missing.
    """
    var g = _with(
        f^,
        "model.nam",
        "BEGIN options\n",
        "BEGIN options\n  NEWTON UNDER_RELAXATION\n",
    )
    return _with(
        g^,
        "model.ims",
        "BEGIN linear\n",
        "BEGIN linear\n  LINEAR_ACCELERATION BICGSTAB\n",
    )


def test_newton_under_relaxation_columns() raises:
    """The bottom cell of each column: a lone cell, and a confined cell under a convertible one.
    """
    var f = _with(
        _base(),
        "model.dis",
        "    CONSTANT 0.0\nEND griddata",
        (
            "    CONSTANT 0.0\n  IDOMAIN\n    INTERNAL\n      1 0 1 0 0 0\nEND"
            " griddata"
        ),
    )
    f = _with(f^, "model.npf", "    CONSTANT 0\n", "    CONSTANT 1\n")
    f = _with(f^, "model.wel", "  2 1 3 -1.0\n", "  1 1 3 0.0\n")
    var sim = _run(_newton_ur(f^))
    assert_equal(sim.npf.ibotnode[2], 2)
    f = _with(
        _base(),
        "model.npf",
        "  ICELLTYPE\n    CONSTANT 0\n",
        "  ICELLTYPE LAYERED\n    CONSTANT 1\n    CONSTANT 0\n",
    )
    sim = _run(_newton_ur(f^))
    assert_equal(sim.npf.ibotnode[1], 4)
    assert_equal(sim.icnvg, 1)


def test_k22_without_angles() raises:
    """K22 alone turns the horizontal conductivity with no angle."""
    var sim = _run(
        _with(
            _base(),
            "model.npf",
            "END griddata",
            "  K22\n    CONSTANT 0.5\nEND griddata",
        )
    )
    assert_equal(sim.npf.ik22, 1)
    assert_equal(sim.npf.iangle1, 0)


def test_rewet_from_below() raises:
    """A dry cell wets from the cell below only if that cell is wet and high enough.
    """
    var f = _with(
        _base(),
        "model.npf",
        "BEGIN options\n",
        "BEGIN options\n  REWET WETFCT 1.0 IWETIT 1 IHDWET 0\n",
    )
    f = _with(
        f^,
        "model.npf",
        "END griddata",
        "  WETDRY\n    CONSTANT -1.0\nEND griddata",
    )
    var sim = _load(f)
    var ib = sim.ibound.copy()
    var h = sim.strt.copy()
    ib[2] = 0
    # The cell below is dry.
    sim.npf._rewet_check(sim.dis, 1, 2, 9.0, 0, 0, ib, h)
    assert_equal(ib[2], 0)
    # The cell below is wet but under the turn-on head of 6.
    sim.npf._rewet_check(sim.dis, 1, 2, 5.5, 1, 0, ib, h)
    assert_equal(ib[2], 0)
    sim.npf._rewet_check(sim.dis, 1, 2, 7.0, 1, 0, ib, h)
    assert_equal(ib[2], 30000)
    assert_equal(h[2], 7.0)
    # A positive WETDRY also wets from the side, by the same two checks.
    f = _with(
        _base(),
        "model.npf",
        "BEGIN options\n",
        "BEGIN options\n  REWET WETFCT 1.0 IWETIT 1 IHDWET 0\n",
    )
    f = _with(
        f^,
        "model.npf",
        "END griddata",
        "  WETDRY\n    CONSTANT 1.0\nEND griddata",
    )
    sim = _load(f)
    ib = sim.ibound.copy()
    h = sim.strt.copy()
    ib[2] = 0
    sim.npf._rewet_check(sim.dis, 1, 2, 9.0, 0, 1, ib, h)
    assert_equal(ib[2], 0)
    sim.npf._rewet_check(sim.dis, 1, 2, 5.5, 1, 1, ib, h)
    assert_equal(ib[2], 0)
    sim.npf._rewet_check(sim.dis, 1, 2, 7.0, 1, 1, ib, h)
    assert_equal(ib[2], 30000)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
