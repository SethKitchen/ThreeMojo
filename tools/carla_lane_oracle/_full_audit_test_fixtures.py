# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Physical test data only; never a production filesystem or admission adapter.

Every historical fixture starts by verifying the complete actual current root.
The four fixed predecessors are then written as ordinary isolated test files.
"""
import os
from pathlib import Path
import shutil
import tempfile

if __package__:
    from . import full_audit_cleanup_contracts as cleanup
else:
    import full_audit_cleanup_contracts as cleanup


def verified_predecessors(source):
    record = cleanup.verify(source, exact=True)
    return {path: cleanup.reverse_exact(path, item['after_source'], item).encode('utf-8')
            for path, item in record['sources'].items()}


def write_predecessors(root, predecessors):
    if set(predecessors) != set(cleanup.SOURCE_PATHS):
        raise AssertionError('historical fixture requires all four verified predecessors')
    for name, raw in predecessors.items():
        if cleanup.sha(raw) != cleanup.BEFORE_SHA256[name]:
            raise AssertionError('historical fixture predecessor identity changed: ' + name)
        target = Path(root)/name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)


def copy_current_root(case, source, *, destination=None):
    """Copy the complete Mojo census and verifier inputs into a real root."""
    source = Path(source)
    record = cleanup.verify(source, exact=True)
    if destination is None:
        # Allocate physical fixtures below the real temp parent (macOS aliases /var).
        directory = tempfile.TemporaryDirectory(
            prefix='full-audit-physical-', dir=Path(tempfile.gettempdir()).resolve())
        case.addCleanup(directory.cleanup)
        destination = Path(directory.name)
    destination = Path(destination)
    paths = {cleanup.MIGRATION, *cleanup.CHECKER_PATHS, *cleanup.SOURCE_PATHS}
    # The accepted-successor consumer also binds this proof document.
    paths.add('tools/carla_lane_oracle/grouped-y-proof.md')
    for group in cleanup.BOUND_GROUPS:
        paths.update(record[group])
    # Entry-point/import/caller discovery scans all Mojo sources, including
    # unrelated sources. Retaining only the old closure would weaken controls.
    for folder, directories, files in os.walk(source):
        relative = Path(folder).relative_to(source)
        directories[:] = [name for name in directories if name not in cleanup.SKIP
                          and relative/name != Path('coverage/build')]
        for name in files:
            path = relative/name
            if path.suffix == '.mojo' or (path.parts[0] == 'tools' and path.suffix in ('.py', '.json')):
                paths.add(path.as_posix())
    for name in sorted(paths):
        original, target = source/name, destination/name
        if original.is_symlink():
            raise AssertionError('fixture source is a symlink: ' + name)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, target)
    cleanup.verify(destination, exact=True)
    return destination


def historical_root(case, source):
    predecessors = verified_predecessors(source)
    root = copy_current_root(case, source)
    write_predecessors(root, predecessors)
    return root
