# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a pass over the rows of an image is cut into tasks.

The water frame runs each of its passes over disjoint runs of rows. Every
pixel has one writer and the serial arithmetic, so the picture does not depend
on the number of tasks. This module only counts the tasks.
"""

from std.sys import num_logical_cores


def row_tasks(workers: Int, per_worker: Int, height: Int) -> Int:
    """Return how many runs of rows a pass is cut into.

    Zero or fewer `workers` means every logical core. One worker runs one task
    over every row: the serial pass, which a test compares with the parallel
    one. The count of threads is clamped to the rows before it is multiplied,
    so a huge count cannot overflow.

    Args:
        workers: The threads that share the pass. Zero or less means every
            logical core.
        per_worker: The runs of rows for each thread. A pass whose rows cost
            unequal time uses more, so that the threads balance.
        height: The rows of the image.

    Returns:
        The number of tasks. It is 1 for one thread, and at most `height`
        otherwise, so each task gets at least one row.
    """
    var threads = workers if workers > 0 else num_logical_cores()
    if threads == 1:
        return 1
    return min(min(threads, height) * per_worker, height)
