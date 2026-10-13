# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Physical test data only; never a production filesystem or admission adapter.

Every historical fixture starts by verifying the complete actual current root.
The four fixed predecessors are then written as ordinary isolated test files.
"""
import hashlib
import json
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


def copy_shared_helper_inputs(root, source):
    """Copy the verified arithmetic helper closure into a partial fixture."""
    bindings = cleanup.shared_helper_proof_bindings(source)
    for name, digest in bindings.items():
        raw = (Path(source)/name).read_bytes()
        if cleanup.sha(raw) != digest:
            raise AssertionError('shared-helper fixture source changed: ' + name)
        target = Path(root)/name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        if cleanup.sha(target.read_bytes()) != digest:
            raise AssertionError('shared-helper fixture copy changed: ' + name)
    if cleanup.shared_helper_proof_bindings(root) != bindings:
        raise AssertionError('shared-helper fixture closure changed')
    return bindings


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
    # Supplemental witness-format proof inputs are physically copied too.
    paths.update(cleanup.witness_format.BOUND_INPUTS)
    paths.update(cleanup.typed_boundary.NEW_INPUTS)
    paths.update(cleanup.typed_boundary.TESTS)
    paths.update(cleanup.typed_boundary.BINDING_INPUTS)
    paths.update(cleanup.conditioned_cubic.BINDING_INPUTS)
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
    # A historical boundary root has already removed the new #333 Mojo
    # inputs; copying from it keeps that historical graph.
    absent = {name for name in cleanup.typed_boundary.NEW_INPUTS
              if name.endswith('.mojo') and not (source/name).exists()}
    for name in sorted(paths - absent):
        original, target = source/name, destination/name
        if original.is_symlink():
            raise AssertionError('fixture source is a symlink: ' + name)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, target)
    cleanup.verify(destination, exact=True)
    return destination


def copy_historical_boundary_root(case, source, *, destination=None):
    """Admit current bytes, then create the complete historical main2d81 graph.

    This is physical test data, never a production root adapter. Old tests
    retain their old byte/line and method-identity claims on this named root.
    Current source acceptance and mutation controls use copy_current_root.
    """
    root = copy_current_root(case, source, destination=destination)
    typed = cleanup.typed_boundary
    for name in typed.SOURCE_PATHS:
        path = root/name
        if name in typed.NEW_INPUTS and not path.exists():
            continue  # Copied from a root that is already historical.
        text = path.read_text(encoding='utf-8')
        if typed.is_current(name, text):
            path.write_text(typed.historical_source(name, text), encoding='utf-8')
    for name in typed.NEW_INPUTS:
        if name.endswith('.mojo'):
            (root/name).unlink(missing_ok=True)
    cleanup.verify(root, exact=True)
    return root


def historical_root(case, source):
    predecessors = verified_predecessors(source)
    root = copy_historical_boundary_root(case, source)
    write_predecessors(root, predecessors)
    return root


# The reviewed pre-border closure, including the four #333 runtime consumers
# and the #306 render-actor successor. Later edges may extend these paths,
# but only a new canonical path changes the partition count.
WINNER_PRE_BORDER_SUCCESSORS = frozenset({
    'extensions/carla/cameras.mojo',
    'extensions/carla/curve_bounds.mojo',
    'extensions/carla/curve_frozen_arc.mojo',
    'extensions/carla/curve_minimizer_support.mojo',
    'extensions/carla/curve_rounded_arc.mojo',
    'extensions/carla/curve_rounded_line.mojo',
    'extensions/carla/curve_sample_dispatch.mojo',
    'extensions/carla/junction_bounds.mojo',
    'extensions/carla/lane_invasion.mojo',
    'extensions/carla/lane_refinement.mojo',
    'extensions/carla/render_actors.mojo',
    'extensions/carla/sensor_manager.mojo',
    'extensions/carla/speed_limits.mojo',
    'extensions/carla/spiral_domain_proof.mojo',
    'extensions/carla/spiral_grouped_roundoff_proof.mojo',
    'extensions/carla/spiral_moment_proof.mojo',
    'extensions/carla/spiral_roundoff_proof.mojo',
    'extensions/carla/world.mojo',
})
WINNER_SHARED_HELPER_SUCCESSORS = frozenset({
    'extensions/carla/curve_distance.mojo',
    'extensions/carla/render_sky.mojo',
    'extensions/carla/render_weather.mojo',
})
WINNER_FULL_AUDIT_NEW_DEPENDENCY = 'extensions/carla/lane_value_bounds.mojo'


def assert_winner_canonical_partition(case, root, result, prior_successors, prior_counts):
    """Bind a verified winner result to the exact 112-path physical partition."""
    helpers = cleanup.shared_helpers
    # winner.verify has admitted the actual source/proof closure. Independently
    # bind its count to every physical canonical path, not just a new number.
    record = root/'tools/carla_lane_oracle/winner-sign-query-migration.json'
    canonical = json.loads(record.read_bytes())['canonical_source_unchanged']
    case.assertEqual(len(canonical), 112)
    case.assertEqual(set(helpers.SOURCE_PATHS) & set(canonical), WINNER_SHARED_HELPER_SUCCESSORS)
    case.assertNotIn('loaders/xml.mojo', canonical)
    case.assertTrue(prior_successors.isdisjoint(WINNER_SHARED_HELPER_SUCCESSORS))
    for path in WINNER_SHARED_HELPER_SUCCESSORS:
        with case.subTest(shared_helper=path):
            case.assertEqual(canonical[path], helpers.BEFORE_SHA256[path])
            raw = (root/path).read_bytes()
            case.assertEqual(hashlib.sha256(raw).hexdigest(), helpers.AFTER_SHA256[path])
            before = helpers.predecessor_source(path, raw.decode('utf-8'))
            case.assertEqual(hashlib.sha256(before.encode('utf-8')).hexdigest(),
                             canonical[path])
    changed = {path for path, digest in canonical.items()
               if hashlib.sha256((root/path).read_bytes()).hexdigest() != digest}
    case.assertEqual(changed, prior_successors | WINNER_SHARED_HELPER_SUCCESSORS)
    case.assertEqual((len(prior_successors), len(canonical) - len(prior_successors)),
                     prior_counts)
    counts = (result['reviewed_cleanup_successors'],
              result['canonical_dependencies_unchanged'])
    case.assertEqual(counts, (len(changed), len(canonical) - len(changed)))
    case.assertEqual(sum(counts), 112)
    case.assertEqual(counts, (prior_counts[0] + len(WINNER_SHARED_HELPER_SUCCESSORS),
                             prior_counts[1] - len(WINNER_SHARED_HELPER_SUCCESSORS)))
    return changed
