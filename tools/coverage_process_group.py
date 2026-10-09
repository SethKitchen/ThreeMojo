# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Kill a child's owned process group without masking a real denial."""

import errno
import os
import signal
import subprocess
import sys


def kill_owned_group(child, *, reap):
    """Signal an owned group; accept Darwin EPERM only after proven absence.

    Args:
        child: An unreaped child started with `start_new_session=True`.
        reap: Owner-managed wait callback accepting `timeout=0`. It must
            disarm destructive signals before reaping, restore ownership
            only on TimeoutExpired, and retain uncertain/reaped state on
            every error path. The caller must also prevent reentrant kills.

    Returns:
        None after SIGKILL succeeds or the group is confirmed absent. The
        callback updates ownership before reaping, not after this returns.

    Raises:
        PermissionError: If a live leader or a present/denied group remains.
        BaseException: If the owner-managed reap or group probe fails.
    """
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except PermissionError as error:
        if sys.platform != 'darwin' or error.errno != errno.EPERM:
            raise
        # EPERM alone cannot distinguish a zombie-only group from denial.
        try:
            reap(timeout=0)
        except subprocess.TimeoutExpired:
            raise error
        # The owner disarmed the identity before releasing its PID. Never
        # send another destructive signal, and add no fresh settling budget.
        try:
            os.killpg(child.pid, 0)
        except ProcessLookupError:
            return
        raise error
