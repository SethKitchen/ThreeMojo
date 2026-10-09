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
        self.polls = 0

    def poll(self):
        self.polls += 1
        return self.exit_status


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
                patch.object(group.os, 'killpg', side_effect=killpg), \
                patch.object(group.time, 'sleep'):
            try:
                return group.kill_owned_group(child, settle=0.05), calls
            except PermissionError as error:
                return error, calls

    def test_signaled_or_absent_group_keeps_leader_for_the_caller(self):
        for first in (None, gone()):
            child = FakeChild(0)
            reaped, calls = self.kill(child, [first])
            self.assertIs(reaped, False)
            self.assertEqual(calls, [(4242, signal.SIGKILL)])
            self.assertEqual(child.polls, 0)

    def test_eperm_off_macos_is_a_real_denial(self):
        child = FakeChild(0)
        error, calls = self.kill(child, [denied()], platform='linux')
        self.assertIsInstance(error, PermissionError)
        self.assertEqual(calls, [(4242, signal.SIGKILL)])
        self.assertEqual(child.polls, 0)

    def test_live_leader_with_eperm_is_rejected(self):
        child = FakeChild(None)
        error, calls = self.kill(child, [denied()])
        self.assertIsInstance(error, PermissionError)
        self.assertEqual(calls, [(4242, signal.SIGKILL)])
        self.assertEqual(child.polls, 1)

    def test_reaped_leader_with_absent_group_is_accepted(self):
        child = FakeChild(-9)
        reaped, calls = self.kill(child, [denied(), denied(), gone()])
        self.assertIs(reaped, True)
        # After the reap, only signal 0 reaches the group.
        self.assertEqual(calls, [(4242, signal.SIGKILL), (4242, 0), (4242, 0)])

    def test_reaped_leader_with_surviving_group_is_rejected(self):
        child = FakeChild(0)
        error, calls = self.kill(child, [denied(), None])
        self.assertIsInstance(error, PermissionError)
        self.assertEqual(calls, [(4242, signal.SIGKILL), (4242, 0)])

    def test_reaped_leader_with_denied_group_is_rejected_after_settle(self):
        child = FakeChild(0)
        error, calls = self.kill(child, [denied()])
        self.assertIsInstance(error, PermissionError)
        self.assertGreater(len(calls), 2)
        self.assertTrue(all(number == 0 for _, number in calls[1:]))

    def test_capture_stops_signaling_a_leader_it_reaped(self):
        process = coverage_io._CaptureProcess(['true'], None, None, None)
        process.child, process.active = FakeChild(0), True
        with patch.object(coverage_io, 'kill_owned_group', return_value=True) as kill:
            process._kill()
            process._kill()
        kill.assert_called_once_with(process.child)
        self.assertFalse(process.active)

    def test_capture_keeps_ownership_while_the_leader_is_unreaped(self):
        process = coverage_io._CaptureProcess(['true'], None, None, None)
        process.child, process.active = FakeChild(None), True
        with patch.object(coverage_io, 'kill_owned_group', return_value=False) as kill:
            process._kill()
        kill.assert_called_once_with(process.child)
        self.assertTrue(process.active)

    @unittest.skipUnless(hasattr(os, 'killpg'), 'POSIX process groups')
    def test_real_group_is_killed_and_left_for_the_caller_to_reap(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'],
                                 start_new_session=True)
        try:
            self.assertIs(group.kill_owned_group(child), False)
            self.assertEqual(child.wait(timeout=5), -signal.SIGKILL)
        finally:
            if child.returncode is None:
                child.kill()
                child.wait()


if __name__ == '__main__':
    unittest.main()
