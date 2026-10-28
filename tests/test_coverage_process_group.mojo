# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An owned process group accepts Darwin EPERM only after the group is gone."""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tools._owned_process import (
    EACCES,
    EPERM,
    ESRCH,
    SIGKILL,
    SignalHold,
    signal_group,
    spawn,
    wait_blocking,
)
from tools.coverage_io import kill_owned_group, owned_group_kill


def _signals(first: Int, second: Int, count: Int) -> List[Int]:
    """Return `count` scripted errno values."""
    var script = List[Int]()
    if count > 0:
        script.append(first)
    if count > 1:
        script.append(second)
    return script^


def _kill(
    macos: Bool,
    script: List[Int],
    reap_ready: Bool,
    mut calls: List[Int],
    mut waits: Int,
) raises -> Bool:
    """Run one scripted group kill."""
    return owned_group_kill(
        4242, macos, False, script, calls, reap_ready, waits
    )


def _expect_denial(
    macos: Bool,
    script: List[Int],
    reap_ready: Bool,
    signals: Int,
    waited: Int,
    errno_text: String,
) raises:
    """Require one denial, with the recorded signals and reap count."""
    var calls = List[Int]()
    var waits = 0
    var denied = False
    try:
        _ = _kill(macos, script, reap_ready, calls, waits)
    except error:
        denied = True
        var text = String(error)
        if text.find(errno_text) < 0:
            raise Error(text)
    assert_true(denied)
    assert_equal(waits, waited)
    assert_equal(len(calls), signals)
    if signals > 0:
        assert_equal(calls[0], SIGKILL)
    if signals > 1:
        assert_equal(calls[1], 0)


def test_a_delivered_or_absent_signal_leaves_the_leader() raises:
    """SIGKILL success and ESRCH do not reap."""
    for code in [0, ESRCH]:
        var calls = List[Int]()
        var waits = 0
        var script = _signals(code, 0, 1)
        var reaped = _kill(True, script, False, calls, waits)
        assert_false(reaped)
        assert_equal(waits, 0)
        assert_equal(len(calls), 1)
        assert_equal(calls[0], SIGKILL)


def test_eperm_off_macos_and_eacces_stay_denials() raises:
    """Linux EPERM and Darwin EACCES are not treated as a vanished group."""
    var eperm = _signals(EPERM, 0, 1)
    _expect_denial(False, eperm, False, 1, 0, "Errno 1")
    var access = _signals(EACCES, 0, 1)
    _expect_denial(True, access, False, 1, 0, "Errno 13")


def test_a_live_leader_with_eperm_is_rejected() raises:
    """Darwin EPERM with no exit status does not probe the group."""
    var script = _signals(EPERM, 0, 1)
    _expect_denial(True, script, False, 1, 1, "Errno 1")


def test_a_reaped_leader_with_an_absent_group_is_accepted() raises:
    """After the reap, only signal 0 runs, and ESRCH accepts the group."""
    var calls = List[Int]()
    var waits = 0
    var script = _signals(EPERM, ESRCH, 2)
    var reaped = _kill(True, script, True, calls, waits)
    assert_true(reaped)
    assert_equal(waits, 1)
    assert_equal(len(calls), 2)
    assert_equal(calls[0], SIGKILL)
    assert_equal(calls[1], 0)


def test_a_reaped_leader_with_a_surviving_or_denied_group_is_rejected() raises:
    """A present or still-denied group is not killed again."""
    var present = _signals(EPERM, 0, 2)
    _expect_denial(True, present, True, 2, 1, "Errno 1")
    var denied = _signals(EPERM, 0, 1)
    _expect_denial(True, denied, True, 2, 1, "Errno 1")


def test_a_real_group_is_killed_and_left_to_reap() raises:
    """SIGKILL stops the session and the caller still reaps the leader."""
    var pid = spawn(["sleep", "2"], SignalHold(), -1, True)
    try:
        var reaped = kill_owned_group(pid)
        assert_false(reaped)
        var waited = wait_blocking(pid)
        assert_true(waited.done, String(waited.error))
        assert_equal(waited.status, -SIGKILL)
    finally:
        _ = signal_group(pid, SIGKILL)
        _ = wait_blocking(pid)


def main() raises:
    """Run the process-group tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
