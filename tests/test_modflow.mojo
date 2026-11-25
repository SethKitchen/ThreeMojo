# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Run the MODFLOW 6 reference cases and compare each value with the real program.

Each folder under `assets/modflow/cases/` is a simulation.
`assets/modflow/make_modflow_cases.py` writes it, runs MODFLOW 6.9.0.dev0
(commit 59d89e9f) on it and stores the heads and the budget of every time
step in `expected.txt`. The port must give the same doubles.
"""

from std.testing import TestSuite, assert_equal, assert_true

from extensions.groundwater.cmath import cstrtod
from extensions.groundwater.simulation import Simulation


def _number(text: String) raises -> Float64:
    """Read a number that the generator wrote.

    Args:
        text: The text.

    Returns:
        The number.

    Raises:
        Error: The text is not a number.
    """
    var used = 0
    var v = cstrtod(text, used)
    if used != text.byte_length():
        raise Error(String("not a number: ", text))
    return v


def _same(got: Float64, want: Float64, what: String) raises:
    """Check that two doubles are the same.

    Args:
        got: The value of the port.
        want: The value of MODFLOW 6.
        what: The name of the value, for the message.

    Raises:
        Error: The values differ.
    """
    if got != want:
        raise Error(
            String(what, ": port ", repr(got), ", MODFLOW 6 ", repr(want))
        )


def _check_step(sim: Simulation, lines: List[String], mut at: Int) raises:
    """Compare the results of one step with the lines of `expected.txt`.

    Args:
        sim: The simulation after the step.
        lines: The lines of the file.
        at: The line of the `step` record. Receives the line after the step.

    Raises:
        Error: A value differs.
    """
    var head = lines[at].split(" ")
    var tag = String(head[1], " ", head[2])
    assert_equal(Int(head[1]), sim.tdis.kper)
    assert_equal(Int(head[2]), sim.tdis.kstp)
    _same(sim.tdis.totim, _number(String(head[3])), String("totim ", tag))
    assert_equal(Int(head[4]), sim.icnvg)
    at += 1
    var nodesuser = sim.dis.nodesuser
    while at < len(lines) and not lines[at].startswith("step "):
        var w = lines[at].split(" ")
        var name = String(w[0])
        if name == "head":
            var h = sim.heads()
            assert_equal(len(w) - 1, nodesuser)
            for u in range(1, nodesuser + 1):
                _same(h[u], _number(String(w[u])), String("head ", u, " ", tag))
        elif name == "FLOW-JA-FACE":
            assert_equal(len(w) - 1, sim.dis.con.nja)
            for i in range(1, sim.dis.con.nja + 1):
                _same(
                    sim.flowja[i],
                    _number(String(w[i])),
                    String("flowja ", i, " ", tag),
                )
        elif name == "STO-SS" or name == "STO-SY":
            assert_equal(len(w) - 1, nodesuser)
            for u in range(1, nodesuser + 1):
                var n = sim.dis.reduced(u)
                var v = 0.0
                if n > 0:
                    v = (
                        sim.sto.strgss[n] if name
                        == "STO-SS" else sim.sto.strgsy[n]
                    )
                _same(v, _number(String(w[u])), String(name, " ", u, " ", tag))
        else:
            # A list record names its package. A package without
            # SAVE_FLOWS writes no record.
            var pname = String(w[1])
            var ibnd = -1
            for i in range(len(sim.bnds)):
                if sim.bnds[i].name == pname:
                    ibnd = i
            assert_true(ibnd >= 0, String("no package ", pname))
            ref b = sim.bnds[ibnd]
            var count = Int(w[2])
            var k = 0
            for i in range(1, b.nbound + 1):
                var node = b.nodelist[i]
                if node <= 0:
                    continue
                assert_true(k < count, String(pname, " has more records ", tag))
                assert_equal(sim.dis.user(node), Int(w[3 + 2 * k]))
                _same(
                    b.simvals[i],
                    _number(String(w[4 + 2 * k])),
                    String(pname, " ", i, " ", tag),
                )
                k += 1
            assert_equal(k, count)
        at += 1


def _run(name: String) raises:
    """Run one case and compare every step.

    Args:
        name: The folder name of the case.

    Raises:
        Error: A value differs.
    """
    var folder = String("assets/modflow/cases/", name)
    var lines = List[String]()
    for s in open(String(folder, "/expected.txt"), "r").read().split("\n"):
        if s.byte_length() > 0:
            lines.append(String(s))
    var sim = Simulation(folder)
    var at = 0
    while not sim.done():
        sim.step()
        _check_step(sim, lines, at)
    assert_equal(at, len(lines))


def test_angles3d() raises:
    """The `angles3d` case gives the numbers of MODFLOW 6."""
    _run("angles3d")


def test_arrays_two_layers() raises:
    """The `arrays_two_layers` case gives the numbers of MODFLOW 6."""
    _run("arrays_two_layers")


def test_auxmult_periods() raises:
    """The `auxmult_periods` case gives the numbers of MODFLOW 6."""
    _run("auxmult_periods")


def test_average_amt_hmk() raises:
    """The `average_amt_hmk` case gives the numbers of MODFLOW 6."""
    _run("average_amt_hmk")


def test_average_amt_lmk() raises:
    """The `average_amt_lmk` case gives the numbers of MODFLOW 6."""
    _run("average_amt_lmk")


def test_average_logarithmic() raises:
    """The `average_logarithmic` case gives the numbers of MODFLOW 6."""
    _run("average_logarithmic")


def test_backtrack_once() raises:
    """The `backtrack_once` case gives the numbers of MODFLOW 6."""
    _run("backtrack_once")


def test_backtrack_res_limit() raises:
    """The `backtrack_res_limit` case gives the numbers of MODFLOW 6."""
    _run("backtrack_res_limit")


def test_bounds_edge() raises:
    """The `bounds_edge` case gives the numbers of MODFLOW 6."""
    _run("bounds_edge")


def test_complexity_moderate() raises:
    """The `complexity_moderate` case gives the numbers of MODFLOW 6."""
    _run("complexity_moderate")


def test_complexity_simple() raises:
    """The `complexity_simple` case gives the numbers of MODFLOW 6."""
    _run("complexity_simple")


def test_confined_steady() raises:
    """The `confined_steady` case gives the numbers of MODFLOW 6."""
    _run("confined_steady")


def test_cooley_bicgstab() raises:
    """The `cooley_bicgstab` case gives the numbers of MODFLOW 6."""
    _run("cooley_bicgstab")


def test_cooley_oscillate() raises:
    """The `cooley_oscillate` case gives the numbers of MODFLOW 6."""
    _run("cooley_oscillate")


def test_cooley_reverse() raises:
    """The `cooley_reverse` case gives the numbers of MODFLOW 6."""
    _run("cooley_reverse")


def test_dbd_theta_floor() raises:
    """The `dbd_theta_floor` case gives the numbers of MODFLOW 6."""
    _run("dbd_theta_floor")


def test_dry_lower_layer() raises:
    """The `dry_lower_layer` case gives the numbers of MODFLOW 6."""
    _run("dry_lower_layer")


def test_evt_depths() raises:
    """The `evt_depths` case gives the numbers of MODFLOW 6."""
    _run("evt_depths")


def test_evt_list() raises:
    """The `evt_list` case gives the numbers of MODFLOW 6."""
    _run("evt_list")


def test_ims_keywords() raises:
    """The `ims_keywords` case gives the numbers of MODFLOW 6."""
    _run("ims_keywords")


def test_isolated_cell() raises:
    """The `isolated_cell` case gives the numbers of MODFLOW 6."""
    _run("isolated_cell")


def test_l2norm_relative() raises:
    """The `l2norm_relative` case gives the numbers of MODFLOW 6."""
    _run("l2norm_relative")


def test_mixed_celltype() raises:
    """The `mixed_celltype` case gives the numbers of MODFLOW 6."""
    _run("mixed_celltype")


def test_newton_chd_downstream() raises:
    """The `newton_chd_downstream` case gives the numbers of MODFLOW 6."""
    _run("newton_chd_downstream")


def test_newton_dbd_backtracking() raises:
    """The `newton_dbd_backtracking` case gives the numbers of MODFLOW 6."""
    _run("newton_dbd_backtracking")


def test_newton_exact() raises:
    """The `newton_exact` case gives the numbers of MODFLOW 6."""
    _run("newton_exact")


def test_newton_highest_cell() raises:
    """The `newton_highest_cell` case gives the numbers of MODFLOW 6."""
    _run("newton_highest_cell")


def test_newton_nur_dry() raises:
    """The `newton_nur_dry` case gives the numbers of MODFLOW 6."""
    _run("newton_nur_dry")


def test_newton_steady() raises:
    """The `newton_steady` case gives the numbers of MODFLOW 6."""
    _run("newton_steady")


def test_newton_sto_confined_only() raises:
    """The `newton_sto_confined_only` case gives the numbers of MODFLOW 6."""
    _run("newton_sto_confined_only")


def test_newton_sto_original() raises:
    """The `newton_sto_original` case gives the numbers of MODFLOW 6."""
    _run("newton_sto_original")


def test_nur_converges() raises:
    """The `nur_converges` case gives the numbers of MODFLOW 6."""
    _run("nur_converges")


def test_nur_overshoot() raises:
    """The `nur_overshoot` case gives the numbers of MODFLOW 6."""
    _run("nur_overshoot")


def test_nur_single_cell() raises:
    """The `nur_single_cell` case gives the numbers of MODFLOW 6."""
    _run("nur_single_cell")


def test_original_ss() raises:
    """The `original_ss` case gives the numbers of MODFLOW 6."""
    _run("original_ss")


def test_perched_varcv() raises:
    """The `perched_varcv` case gives the numbers of MODFLOW 6."""
    _run("perched_varcv")


def test_ptc_del0() raises:
    """The `ptc_del0` case gives the numbers of MODFLOW 6."""
    _run("ptc_del0")


def test_ptc_no_first() raises:
    """The `ptc_no_first` case gives the numbers of MODFLOW 6."""
    _run("ptc_no_first")


def test_ptc_none() raises:
    """The `ptc_none` case gives the numbers of MODFLOW 6."""
    _run("ptc_none")


def test_ptc_option_exponent() raises:
    """The `ptc_option_exponent` case gives the numbers of MODFLOW 6."""
    _run("ptc_option_exponent")


def test_rewet_ihdwet() raises:
    """The `rewet_ihdwet` case gives the numbers of MODFLOW 6."""
    _run("rewet_ihdwet")


def test_rewet_perched() raises:
    """The `rewet_perched` case gives the numbers of MODFLOW 6."""
    _run("rewet_perched")


def test_rewet_vertical() raises:
    """The `rewet_vertical` case gives the numbers of MODFLOW 6."""
    _run("rewet_vertical")


def test_rewet_wetfct() raises:
    """The `rewet_wetfct` case gives the numbers of MODFLOW 6."""
    _run("rewet_wetfct")


def test_simple_strict() raises:
    """The `simple_strict` case gives the numbers of MODFLOW 6."""
    _run("simple_strict")


def test_single_cell() raises:
    """The `single_cell` case gives the numbers of MODFLOW 6."""
    _run("single_cell")


def test_solver_bicgstab_alpha() raises:
    """The `solver_bicgstab_alpha` case gives the numbers of MODFLOW 6."""
    _run("solver_bicgstab_alpha")


def test_solver_bicgstab_breakdown() raises:
    """The `solver_bicgstab_breakdown` case gives the numbers of MODFLOW 6."""
    _run("solver_bicgstab_breakdown")


def test_solver_bicgstab_rho_omega() raises:
    """The `solver_bicgstab_rho_omega` case gives the numbers of MODFLOW 6."""
    _run("solver_bicgstab_rho_omega")


def test_solver_cg_same_rho() raises:
    """The `solver_cg_same_rho` case gives the numbers of MODFLOW 6."""
    _run("solver_cg_same_rho")


def test_solver_cg_zero_residual() raises:
    """The `solver_cg_zero_residual` case gives the numbers of MODFLOW 6."""
    _run("solver_cg_zero_residual")


def test_solver_cg_zero_rho() raises:
    """The `solver_cg_zero_rho` case gives the numbers of MODFLOW 6."""
    _run("solver_cg_zero_rho")


def test_solver_ptc_zero_residual() raises:
    """The `solver_ptc_zero_residual` case gives the numbers of MODFLOW 6."""
    _run("solver_ptc_zero_residual")


def test_ss_confined_only() raises:
    """The `ss_confined_only` case gives the numbers of MODFLOW 6."""
    _run("ss_confined_only")


def test_storage_coefficient() raises:
    """The `storage_coefficient` case gives the numbers of MODFLOW 6."""
    _run("storage_coefficient")


def test_thickstrt_anisotropy_idomain() raises:
    """The `thickstrt_anisotropy_idomain` case gives the numbers of MODFLOW 6.
    """
    _run("thickstrt_anisotropy_idomain")


def test_unconfined_transient() raises:
    """The `unconfined_transient` case gives the numbers of MODFLOW 6."""
    _run("unconfined_transient")


def test_varcv_lower_partial() raises:
    """The `varcv_lower_partial` case gives the numbers of MODFLOW 6."""
    _run("varcv_lower_partial")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
