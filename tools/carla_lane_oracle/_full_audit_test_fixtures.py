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


def common758_leaf_texts(source):
    """Exact old leaf inputs derived from one fully admitted physical root.

    These strings are test data, never a production filesystem view. The old
    complete positive baselines pass before any existing negative is applied.
    """
    source = Path(source)
    bindings = cleanup.proof_bindings(source)
    typed, shared, scaled = (cleanup.typed_boundary, cleanup.shared_helpers,
                             cleanup.scaled_float32)
    paths = set(typed.SOURCE_PATHS) | set(shared.SOURCE_PATHS) | set(shared.PROVIDERS)
    paths |= set(scaled.SOURCE_PATHS) | set(scaled.PROVIDER_INPUTS)
    physical = {name: (source/name).read_bytes() for name in paths}
    if any(cleanup.sha(raw) != bindings[name] for name, raw in physical.items()):
        raise AssertionError('leaf fixture differs from admitted physical input')
    selected = cleanup._pr760_image_selected(physical)
    texts = {name: (cleanup.pr760_stage.predecessor_source(name, raw.decode('utf-8'))
             if selected and name in cleanup.pr760_stage.CARLA_REGISTRY_PATHS
             else raw.decode('utf-8')) for name, raw in physical.items()}
    typed.verify_sources({name: texts[name] for name in typed.SOURCE_PATHS})
    shared.verify_correspondence({name: texts[name] for name in
                                  (*shared.SOURCE_PATHS, *shared.PROVIDERS)})
    scaled.verify_sources({name: texts[name] for name in scaled.SOURCE_PATHS})
    for name, raw in physical.items():
        if (source/name).read_bytes() != raw:
            raise AssertionError('leaf fixture source changed after transport: ' + name)
    return texts


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
    """Build an explicitly historical arithmetic-only physical test fixture.

    The source first passes its full current admission. Current partial-root
    refusal and current complete-root positives remain separate controls.
    """
    bindings = cleanup.shared_helper_proof_bindings(source)
    bindings.update(cleanup.scaled_float32_proof_bindings(source))
    copied_bindings = {}
    for name, digest in bindings.items():
        raw = (Path(source)/name).read_bytes()
        if cleanup.sha(raw) != digest:
            raise AssertionError('shared-helper fixture source changed: ' + name)
        if name in cleanup.pr760_stage.CARLA_REGISTRY_PATHS:
            edge = cleanup.pr760_stage.EDGES[name]
            if cleanup.sha(raw) == edge['after_sha256']:
                raw = cleanup.pr760_stage.predecessor_source(name, raw.decode('utf-8')).encode('utf-8')
                if cleanup.sha(raw) != edge['before_sha256']:
                    raise AssertionError('historical helper predecessor changed: ' + name)
        if name in ('tools/test_conditioned_coverage_loops.py', 'tools/carla_lane_oracle/test_typed_boundary_contracts.py', 'tools/carla_lane_oracle/test_shared_helper_contracts.py', 'tools/carla_lane_oracle/test_scaled_float32_contracts.py', 'tools/carla_lane_oracle/test_common758_current_successor.py'):
            raw = cleanup.qualification_predecessor_bytes(name, raw)
        copied_bindings[name] = cleanup.sha(raw)
        target = Path(root)/name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)
        if cleanup.sha(target.read_bytes()) != copied_bindings[name]:
            raise AssertionError('shared-helper fixture copy changed: ' + name)
    copied = cleanup.shared_helper_proof_bindings(root)
    copied.update(cleanup.scaled_float32_proof_bindings(root))
    # Stage-only implementation metadata is not part of historical leaf admission.
    stage_only = {'tools/carla_lane_oracle/pr760_arithmetic_stage.py',
                  cleanup.PR760_IMAGE, cleanup.PR760_OWNER_PREDECESSOR}
    expected = {name: digest for name, digest in copied_bindings.items()
                if name not in stage_only}
    if copied != expected:
        raise AssertionError('shared-helper fixture closure changed')
    return copied


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
    admitted = cleanup.proof_bindings(source)
    paths = {cleanup.MIGRATION, *cleanup.CHECKER_PATHS, *cleanup.DEPENDENCY_TOOL_SHA256,
             *cleanup.SOURCE_PATHS, *admitted}
    # The accepted-successor consumer also binds this proof document.
    paths.add('tools/carla_lane_oracle/grouped-y-proof.md')
    # Supplemental witness-format proof inputs are physically copied too.
    paths.update(cleanup.witness_format.BOUND_INPUTS)
    paths.update(cleanup.scaled_float32_proof_bindings(source))
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
        if name in admitted and cleanup.sha(target.read_bytes()) != admitted[name]:
            raise AssertionError('fixture admitted input copy changed: ' + name)
    cleanup.verify(destination, exact=True)
    return destination


def copy_common758_boundary_root(case, source, *, destination=None):
    """Admit current bytes, then create the complete common758 predecessor graph.

    This is physical test data, never a production root adapter. Old tests
    retain their old byte/line and method-identity claims on this named root.
    Current source acceptance and mutation controls use copy_current_root.
    """
    root = copy_current_root(case, source, destination=destination)
    typed = cleanup.typed_boundary
    # Current root admission above owns the physical source; only this isolated
    # historical test fixture receives the reviewed exact main predecessors.
    stage = cleanup.pr760_stage
    examples = {name: (root/name).read_bytes() for name in stage.EXAMPLE_PATHS}
    selected = cleanup._pr760_image_selected(examples)
    if selected:
        for name in stage.CARLA_REGISTRY_PATHS:
            raw = (root/name).read_bytes()
            previous = stage.predecessor_source(name, raw.decode('utf-8')).encode('utf-8')
            if cleanup.sha(raw) != stage.EDGES[name]['after_sha256'] or cleanup.sha(previous) != stage.EDGES[name]['before_sha256']:
                raise AssertionError('historical fixture PR760 endpoint changed: ' + name)
            (root/name).write_bytes(previous)
    for name in ('tools/test_conditioned_coverage_loops.py', 'tools/carla_lane_oracle/test_typed_boundary_contracts.py', 'tools/carla_lane_oracle/test_shared_helper_contracts.py', 'tools/carla_lane_oracle/test_scaled_float32_contracts.py', 'tools/carla_lane_oracle/test_common758_current_successor.py'):
        target = root/name
        target.write_bytes(cleanup.qualification_predecessor_bytes(name, target.read_bytes()))
    cleanup.verify(root, exact=True)
    return root


def copy_historical_boundary_root(case, source, *, destination=None):
    """Admit current bytes, then construct the preserved pre-typed graph."""
    root = copy_common758_boundary_root(case, source, destination=destination)
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
