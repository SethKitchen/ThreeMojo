# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Owned process-group cleanup accepts EPERM only for a vanished group."""

import errno
import os
import signal
import subprocess
import sys
import unittest
from unittest.mock import patch

import coverage_io
import coverage_process_group as group


class FakeChild:
    def __init__(self, exit_status):
        self.pid = 4242
        self.exit_status = exit_status
        self.waits = 0
        self.returncode = None

    def wait(self, timeout):
        if timeout != 0:
            raise AssertionError('the helper must never use a blocking wait')
        self.waits += 1
        if self.exit_status is None:
            raise subprocess.TimeoutExpired('owned', timeout)
        self.returncode = self.exit_status
        return self.returncode


def denied():
    return PermissionError(errno.EPERM, 'Operation not permitted')


def gone():
    return ProcessLookupError(errno.ESRCH, 'No such process')


class KillOwnedGroupTests(unittest.TestCase):
    def kill(self, child, results, platform='darwin'):
        calls = []

        def killpg(pid, number):
            calls.append((pid, number))
            result = results[min(len(calls), len(results)) - 1]
            if result is not None:
                raise result
        with patch.object(group.sys, 'platform', platform), \
                patch.object(group.os, 'killpg', side_effect=killpg):
            try:
                return group.kill_owned_group(child, reap=child.wait), calls
            except PermissionError as error:
                return error, calls

    def test_signaled_or_absent_group_keeps_leader_for_the_caller(self):
        for first in (None, gone()):
            child = FakeChild(0)
            reaped, calls = self.kill(child, [first])
            self.assertIsNone(reaped)
            self.assertEqual(calls, [(4242, signal.SIGKILL)])
            self.assertEqual(child.waits, 0)

    def test_eperm_off_macos_is_a_real_denial(self):
        child = FakeChild(0)
        error, calls = self.kill(child, [denied()], platform='linux')
        self.assertIsInstance(error, PermissionError)
        self.assertEqual(calls, [(4242, signal.SIGKILL)])
        self.assertEqual(child.waits, 0)

    def test_darwin_eacces_is_not_reclassified_as_eperm(self):
        child = FakeChild(0)
        error, calls = self.kill(child, [PermissionError(errno.EACCES, 'denied')])
        self.assertEqual(error.errno, errno.EACCES)
        self.assertEqual(calls, [(4242, signal.SIGKILL)])
        self.assertEqual(child.waits, 0)

    def test_ownership_callback_is_required_before_a_destructive_signal(self):
        with patch.object(group.os, 'killpg') as kill:
            with self.assertRaises(TypeError):
                group.kill_owned_group(FakeChild(0))
        kill.assert_not_called()

    def test_live_leader_with_eperm_is_rejected(self):
        child = FakeChild(None)
        error, calls = self.kill(child, [denied()])
        self.assertIsInstance(error, PermissionError)
        self.assertEqual(calls, [(4242, signal.SIGKILL)])
        self.assertEqual(child.waits, 1)

    def test_reaped_leader_with_absent_group_is_accepted(self):
        child = FakeChild(-9)
        reaped, calls = self.kill(child, [denied(), gone()])
        self.assertIsNone(reaped)
        # After the reap, only signal 0 reaches the group.
        self.assertEqual(calls, [(4242, signal.SIGKILL), (4242, 0)])

    def test_reaped_leader_with_surviving_group_is_rejected(self):
        child = FakeChild(0)
        error, calls = self.kill(child, [denied(), None])
        self.assertIsInstance(error, PermissionError)
        self.assertEqual(calls, [(4242, signal.SIGKILL), (4242, 0)])

    def test_reaped_leader_with_denied_group_is_rejected_without_a_new_budget(self):
        child = FakeChild(0)
        error, calls = self.kill(child, [denied()])
        self.assertIsInstance(error, PermissionError)
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(number == 0 for _, number in calls[1:]))

    def test_capture_stops_signaling_a_leader_it_reaped(self):
        process = coverage_io._CaptureProcess(['true'], None, None, None)
        process.child, process.active = FakeChild(0), True
        with patch.object(group.sys, 'platform', 'darwin'), \
                patch.object(group.os, 'killpg', side_effect=[denied(), gone()]) as kill:
            process._kill()
            process._kill()
        self.assertEqual(kill.call_count, 2)
        self.assertEqual(process.child.waits, 1)
        self.assertFalse(process.active)

    def test_capture_keeps_ownership_while_the_leader_is_unreaped(self):
        process = coverage_io._CaptureProcess(['true'], None, None, None)
        process.child, process.active = FakeChild(None), True
        with patch.object(coverage_io, 'kill_owned_group') as kill:
            process._kill()
        kill.assert_called_once_with(process.child, reap=process._reap)
        self.assertTrue(process.active)

    @unittest.skipUnless(hasattr(os, 'killpg'), 'POSIX process groups')
    def test_real_group_is_killed_and_left_for_the_caller_to_reap(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'],
                                 start_new_session=True)
        try:
            self.assertIsNone(group.kill_owned_group(child, reap=child.wait))
            self.assertEqual(child.wait(timeout=5), -signal.SIGKILL)
        finally:
            if child.returncode is None:
                child.kill()
                child.wait()


if __name__ == '__main__':
    unittest.main()
