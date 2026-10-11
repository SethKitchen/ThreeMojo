# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Give each test process a private, automatically cleaned temporary root."""

from contextlib import contextmanager
import os
from pathlib import Path
import tempfile


@contextmanager
def isolated_environment():
    """Yield a child environment; remove its private files after any outcome."""
    parent = os.environ.get('TMPDIR') or None
    with tempfile.TemporaryDirectory(prefix='threemojo-test-', dir=parent) as folder:
        environment = os.environ.copy()
        root = str(Path(folder).resolve())
        environment['THREEMOJO_TEST_TMPDIR'] = root
        environment['TMPDIR'] = root
        yield environment
