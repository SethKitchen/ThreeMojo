# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The single adapter for the pinned Mojo 1.1 task runtime.

The public runtime has no task group in this version. Keep this private
import here so a compiler migration has one boundary to replace. Callers
must retain captured storage until TaskGroup.wait has returned.
"""

from std.runtime._asyncrt import TaskGroup
