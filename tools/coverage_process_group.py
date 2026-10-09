# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Kill a child's owned process group without masking a real denial."""

import os
import signal
import sys
import time

# Time for launchd to reap zombie descendants after their leader is reaped.
SETTLE_SECONDS = 1.0


def kill_owned_group(child, settle=SETTLE_SECONDS):
    """Send SIGKILL to the group that a `start_new_session` child leads.

    macOS (XNU `killpg1`) skips zombie members and reports EPERM when it
    signals nobody. That is the result for a group whose members have all
    exited before the leader is reaped. It is also the result for a live
    member that refuses the signal. This function accepts EPERM only after
    it reaps the leader without blocking and a signal-0 probe of the group
    reports ESRCH. It sends no destructive signal after it reaps the leader.

    Args:
        child: A `subprocess.Popen` started with `start_new_session=True`
            and not reaped yet.
        settle: Seconds to wait for the probe to report ESRCH.

    Returns:
        True when this call reaped the leader, so the caller must not signal
        its PID again. False otherwise.

    Raises:
        PermissionError: When the group may still hold a live member.
    """
    try:
        os.killpg(child.pid, signal.SIGKILL)
        return False
    except ProcessLookupError:
        return False
    except PermissionError as error:
        if sys.platform != 'darwin':
            raise
        denied = error
    if child.poll() is None:
        raise denied
    deadline = time.monotonic() + settle
    while True:
        try:
            os.killpg(child.pid, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            pass
        else:
            # A member is live and signalable, so the first SIGKILL missed it.
            raise denied
        if time.monotonic() >= deadline:
            raise denied
        time.sleep(0.01)
