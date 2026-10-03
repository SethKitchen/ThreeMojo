# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Produce bounded canonical-template evidence, never certification.

Use --build once, then reuse the source-bound probe. Each native measurement
has the unchanged five-second runtime limit. This tool needs no GPU,
third-party Python package, network connection or rendered mesh.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REGIONS = ('dermis', 'cortical_apparent', 'trabecular_apparent',
           'marrow_fat_proxy', 'muscle', 'tendon', 'unresolved_fat_proxy')
SEGMENTS = ('thigh', 'shank', 'foot')
USES = ('template-estimate', 'game-fantasy', 'engineering', 'whole-body',
        'dynamic-constitutive', 'patient-specific', 'clinical-safety')
ROUNDING_TOLERANCE = 5e-6
PINNED_TOOLCHAIN = 'Mojo 1.1.0 (8189361e)'


def finite(value, name):
    """Require a finite scalar; a Boolean is not a measurement."""
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f'{name} must be a finite number')
    return value


def finite_tree(value):
    if isinstance(value, float):
        finite(value, 'report number')
    elif isinstance(value, dict):
        for child in value.values():
            finite_tree(child)
    elif isinstance(value, list):
        for child in value:
            finite_tree(child)


def grid_steps(values):
    for value in values:
        if not 2 <= finite(value, 'grid step') <= 20:
            raise ValueError('grid steps must be between 2 and 20 mm')
    ordered = sorted(set(values), reverse=True)
    if len(ordered) != len(values) or not 3 <= len(ordered) <= 10:
        raise ValueError('use 3 through 10 distinct grid steps')
    return ordered


def tensor_checks(values):
    """Check all principal minors, using a numerical roundoff tolerance."""
    if len(values) != 6:
        raise ValueError('a tensor needs six entries')
    values = [finite(v, 'inertia') for v in values]
    scale = max(map(abs, values))
    if scale == 0:
        minors, covariance_minors = [0.0]*7, [0.0]*7
    else:
        x, y, z, a, b, c = [v/scale for v in values]
        minors = [x, y, z, x*y-a*a, x*z-b*b, y*z-c*c,
                  x*y*z+2*a*b*c-x*c*c-y*b*b-z*a*a]
        # Physical inertia additionally requires a positive-semidefinite
        # central second-moment matrix C = trace(I)/2 Identity - I.
        # Coordinate-diagonal triangles alone miss rotated counterexamples.
        cx, cy, cz = (y+z-x)/2, (x+z-y)/2, (x+y-z)/2
        ca, cb, cc = -a, -b, -c
        covariance_minors = [cx, cy, cz, cx*cy-ca*ca, cx*cz-cb*cb, cy*cz-cc*cc,
                             cx*cy*cz+2*ca*cb*cc-cx*cc*cc-cy*cb*cb-cz*ca*ca]
    return {'symmetric_by_representation': True,
            'positive_semidefinite': min(minors) >= -ROUNDING_TOLERANCE,
            'triangle_inequalities': min(covariance_minors) >= -ROUNDING_TOLERANCE,
            'scaled_central_second_moment_principal_minors': covariance_minors,
            'scaled_principal_minors': minors,
            'relative_roundoff_tolerance': ROUNDING_TOLERANCE}


def vector(value, name):
    if not isinstance(value, list) or len(value) != 3:
        raise ValueError(f'{name} must contain three coordinates')
    return [finite(x, name) for x in value]


def validate_segment(row):
    if row.get('record') != 'segment' or row.get('segment') not in SEGMENTS:
        raise ValueError('a probe must name one supported segment')
    mass = finite(row.get('mass_kg'), 'mass')
    if mass <= 0 or finite(row.get('length_m'), 'length') <= 0:
        raise ValueError('segment mass and length must be positive')
    if not 0.001999999 <= finite(row.get('step_m'), 'step') <= 0.020000001:
        raise ValueError('unsupported segment grid step')
    low, high, center = [vector(row.get(key), key) for key in ('low_m', 'high_m', 'center_m')]
    if any(hi <= lo for lo, hi in zip(low, high)):
        raise ValueError('segment bounds must be strictly ordered')
    if any(c < lo-1e-7 or c > hi+1e-7 for c, lo, hi in zip(center, low, high)):
        raise ValueError('the center must be within its sampled box')
    checks = tensor_checks(row['inertia_kg_m2'])
    if not checks['positive_semidefinite'] or not checks['triangle_inequalities']:
        raise ValueError('a segment tensor fails its algebraic invariants')
    regions = row.get('regions')
    if not isinstance(regions, dict) or set(regions) != set(REGIONS):
        raise ValueError('all seven exclusive accounting regions must be present')
    for name, region in regions.items():
        for quantity in ('mass_kg', 'volume_m3'):
            if finite(region.get(quantity), f'{name}.{quantity}') < 0:
                raise ValueError('region quantities cannot be negative')
    if not math.isclose(math.fsum(r['mass_kg'] for r in regions.values()), mass,
                        rel_tol=ROUNDING_TOLERANCE, abs_tol=1e-9):
        raise ValueError('exclusive region masses must sum to the segment mass')
    if math.fsum(r['volume_m3'] for r in regions.values()) > math.prod(hi-lo for lo, hi in zip(low, high))*(1+ROUNDING_TOLERANCE):
        raise ValueError('exclusive region volumes exceed their sample box')
    finite_tree(row)
    return checks


def sampling_sensitivity(rows):
    if len(rows) < 3:
        raise ValueError('at least three grids are required')
    steps = [finite(r['step_m'], 'step') for r in rows]
    if any(a <= b for a, b in zip(steps, steps[1:])):
        raise ValueError('grid steps must be strictly decreasing')
    changes = []
    for coarse, fine in zip(rows, rows[1:]):
        dc = [a-b for a, b in zip(coarse['center_m'], fine['center_m'])]
        di = [a-b for a, b in zip(coarse['inertia_kg_m2'], fine['inertia_kg_m2'])]
        norm = math.sqrt(sum(v*v for v in di[:3])+2*sum(v*v for v in di[3:]))
        values = fine['inertia_kg_m2']
        fnorm = math.sqrt(sum(v*v for v in values[:3])+2*sum(v*v for v in values[3:]))
        changes.append({'coarse_step_m': coarse['step_m'], 'fine_step_m': fine['step_m'],
                        'mass_abs_delta_kg': abs(coarse['mass_kg']-fine['mass_kg']),
                        'mass_relative_delta': abs(coarse['mass_kg']-fine['mass_kg'])/fine['mass_kg'],
                        'center_delta_m': dc, 'center_delta_norm_m': math.sqrt(sum(x*x for x in dc)),
                        'tensor_delta_kg_m2': di, 'tensor_delta_frobenius_kg_m2': norm,
                        'tensor_relative_frobenius_delta': norm/fnorm if fnorm else None})
    return {'comparisons': changes, 'error_bound': None, 'observed_order': None,
            'converged_to_physical_reference': False,
            'interpretation': 'Observed sampling sensitivity only. Thin regions, grid phase and discontinuous density assignments can be nonmonotone. Differences are not proven sampling-error or anatomical-uncertainty bounds.'}


def compose_segments(rows):
    """Accept one set of three disjoint cuts, not arbitrary part totals."""
    if len(rows) != 3 or {r['segment'] for r in rows} != set(SEGMENTS):
        raise ValueError('composition needs exactly one thigh, shank and foot')
    for row in rows:
        validate_segment(row)
    if len({r['step_m'] for r in rows}) != 1:
        raise ValueError('composition requires the same requested grid step')
    ordered = sorted(rows, key=lambda r: r['low_m'][1])
    for a, b in zip(ordered, ordered[1:]):
        if a['high_m'][1] != b['low_m'][1]:
            raise ValueError('segment cut planes must meet exactly without overlap or gaps')
        if any(a[key][axis] != b[key][axis] for key in ('low_m', 'high_m') for axis in (0, 2)):
            raise ValueError('composition requires the same limb envelope bounds')
    mass = math.fsum(r['mass_kg'] for r in rows)
    center = [math.fsum(r['mass_kg']*r['center_m'][i] for r in rows)/mass for i in range(3)]
    total = [0.0]*6
    for row in rows:
        x, y, z = [row['center_m'][i]-center[i] for i in range(3)]
        offset = [y*y+z*z, x*x+z*z, x*x+y*y, -x*y, -x*z, -y*z]
        total = [a+b+row['mass_kg']*c for a, b, c in zip(total, row['inertia_kg_m2'], offset)]
    return {'label': 'selected-side lower-limb template estimate', 'is_whole_body': False,
            'mass_kg': mass, 'center_m': center, 'inertia_kg_m2': total,
            'tensor_checks': tensor_checks(total),
            'scope': 'Only these three canonical cuts. Pore-fluid/marrow mass and other body segments are not added.'}


def use_gate(use):
    if use not in USES:
        raise ValueError('unknown requested use')
    return {'requested_use': use, 'permitted_as_labeled': use in ('template-estimate', 'game-fantasy'),
            'result_label': 'template estimate', 'engineering_validated': False,
            'clinical_or_safety_certification': False, 'task_specific_reference_evidence': None,
            'task_specific_acceptance_thresholds': None,
            'reason': 'Template and game/fantasy use is permitted. Other claims lack task-specific independent reference evidence and acceptance thresholds.'}



def annotate_diagnostics(groups):
    """Add stable pair IDs, retaining labels and every sampled hit."""
    seen = set()
    for group, rows in groups.items():
        for row in rows:
            if row.get('record') == 'pair':
                components = sorted((row['first'].replace(' ', '_'), row['second'].replace(' ', '_')))
                identity = 'canonical/' + group + '/' + '|'.join(components)
                row['pair_id'] = identity
                row['allowlist_applied'] = False
                row['geometry_kind'] = 'implicit component envelope intersection'
                row['contact_intent'] = 'unclassified; an anatomical attachment is not an established volume allowance'
            elif row.get('record') == 'endplane':
                identity = 'canonical/spine/endplane/' + row['body']
                row['endplane_id'] = identity
                row['boundary_contact_rule'] = 'spine_endplane_boundary_contact'
                if row['body'] == 'thoracolumbar/16':
                    # This is an authored plane, not a sampled sacral solid.
                    # Refuse protocol drift rather than discard a measurement.
                    if row['next_body_outside_field_m'] != 0:
                        raise ValueError('unexpected sacral support-plane placeholder')
                    row['next_body_sampled'] = False
                    row['next_body_outside_field_m'] = None
                    row['next_reference_kind'] = 'authored sacral support plane'
                else:
                    row['next_body_sampled'] = True
                    row['next_reference_kind'] = 'neighboring vertebral body'
            else:
                raise ValueError('unknown diagnostic record')
            if identity in seen:
                raise ValueError('duplicate diagnostic identity')
            seen.add(identity)
    return groups


def diagnostic_findings(groups):
    """Name incompatible geometry without redefining measured parameters."""
    findings = []
    for group, rows in groups.items():
        for row in rows:
            if row.get('record') == 'pair':
                if row['overlap_samples'] > 0:
                    findings.append({'kind': 'unallowlisted_sampled_overlap',
                                     'group': group, 'pair_id': row.get('pair_id'), 'first': row['first'], 'second': row['second'],
                                     'overlap_volume_m3': row['overlap_volume_m3'],
                                     'interpretation': 'Common interior was sampled. A construction-union allowance within one field does not exempt these distinct named fields.'})
            elif row.get('record') == 'endplane':
                reasons = []
                if row['disc_gap_m'] <= 0:
                    reasons.append('disc endplanes are reversed or coincident')
                for key in ('body_disc_endplane_error_m', 'next_body_disc_endplane_error_m'):
                    if row[key] > 1e-6:
                        reasons.append(key)
                for key in ('body_outside_field_m', 'disc_outside_upper_field_m', 'disc_outside_lower_field_m'):
                    if row[key] <= 0:
                        reasons.append(key)
                # L5 uses an authored support plane, not a sampled flat sacrum.
                if row['next_body_sampled'] and row['next_body_outside_field_m'] <= 0:
                    reasons.append('next_body_outside_field_m')
                if reasons:
                    findings.append({'kind': 'incompatible_endplanes', 'body': row['body'], 'reasons': reasons})
            else:
                raise ValueError('unknown diagnostic record')
    return findings


def source_snapshot(root):
    """Read bound inputs once, retaining hashes and the exact inventory bytes."""
    digest = hashlib.sha256()
    hashes = {}
    inventory_path = root/'docs/validation/anatomy-provenance.json'
    paths = [p for p in root.rglob('*.mojo') if not any(s in ('.cache', '.git', 'build', '.venv', 'node_modules') for s in p.relative_to(root).parts)]
    paths += [root/'tools/anatomy_validity.py', inventory_path]
    for path in sorted(paths):
        content = path.read_bytes()
        name = str(path.relative_to(root))
        digest.update(name.encode()+b'\0'+content+b'\0')
        hashes[name] = hashlib.sha256(content).hexdigest()
        if path == inventory_path:
            inventory = content
    return digest.hexdigest(), hashes, inventory


def source_digest(root):
    return source_snapshot(root)[0]


def verify_report_inputs(root, probe, provenance, snapshot, metadata):
    """Reject observed input changes; this is not an atomic filesystem transaction."""
    current = source_snapshot(root)
    if (current != snapshot or current[0] != provenance['source_sha256']
            or hashlib.sha256(probe.read_bytes()).hexdigest() != provenance['binary_sha256']
            or probe.with_suffix(probe.suffix+'.provenance.json').read_bytes() != metadata
            or json.loads(metadata) != provenance):
        raise ValueError('report inputs changed during execution; rebuild before reporting')


def prepare_probe(root, probe, mojo, build):
    digest = source_digest(root)
    metadata = probe.with_suffix(probe.suffix+'.provenance.json')
    if build:
        version = subprocess.run([mojo, '--version'], check=True, text=True, capture_output=True).stdout.strip()
        if version != PINNED_TOOLCHAIN:
            raise ValueError('the report requires pinned Mojo 1.1.0 (8189361e)')
        probe.parent.mkdir(parents=True, exist_ok=True)
        # Use the repository's relative invocation. The pinned compiler can
        # crash for the equivalent all-absolute include/source/output form.
        command = [mojo, 'build', '--Werror', '-I', '.', 'tools/anatomy_probe.mojo',
                   '-o', os.path.relpath(probe, root)]
        subprocess.run(command, check=True, timeout=600, cwd=root)
        if source_digest(root) != digest:
            raise ValueError('source changed during compilation; rebuild before reporting')
        record = {'source_sha256': digest, 'toolchain': version, 'flags': ['--Werror'],
                  'binary_sha256': hashlib.sha256(probe.read_bytes()).hexdigest()}
        metadata.write_text(json.dumps(record, indent=2)+'\n')
    else:
        if not probe.is_file() or not metadata.is_file():
            raise ValueError('build the source-bound probe with --build first')
        record = json.loads(metadata.read_text())
        if record.get('toolchain') != PINNED_TOOLCHAIN or record.get('flags') != ['--Werror']:
            raise ValueError('probe provenance must record the exact pinned compiler and --Werror')
        if record.get('source_sha256') != digest or record.get('binary_sha256') != hashlib.sha256(probe.read_bytes()).hexdigest():
            raise ValueError('probe provenance is stale; rebuild with --build')
    return record


def probe_rows(probe, mode, part, step, args):
    command = [str(probe), mode, part, str(step), str(args.stature_m), args.sex, args.side, args.athleticism]
    result = subprocess.run(command, check=True, text=True, capture_output=True, timeout=5, cwd=ROOT)
    rows = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    if not rows:
        raise ValueError(f'{mode} probe produced no evidence')
    finite_tree(rows)
    return rows


def report(args):
    steps = grid_steps(args.steps_mm)
    if not 1.2 <= finite(args.stature_m, 'stature') <= 2.5:
        raise ValueError('stature must be in the software range 1.2 through 2.5 m')
    probe = args.probe.resolve()
    provenance = prepare_probe(ROOT, probe, args.mojo, args.build)
    snapshot = source_snapshot(ROOT)
    metadata = probe.with_suffix(probe.suffix+'.provenance.json').read_bytes()
    verify_report_inputs(ROOT, probe, provenance, snapshot, metadata)
    inventory = json.loads(snapshot[2])
    source_files = sorted({path for item in inventory['parameters'] for path in item['source_files']})
    controls = probe_rows(probe, 'controls', 'none', 5, args)
    if len(controls) != 1 or controls[0].get('record') != 'controls' or controls[0].get('passed') is not True:
        raise ValueError('independent controls did not pass')
    segments = {}
    for segment in SEGMENTS:
        rows = []
        for step in steps:
            found = probe_rows(probe, 'segment', segment, step, args)
            if len(found) != 1 or found[0].get('segment') != segment:
                raise ValueError('probe returned the wrong segment')
            row = found[0]
            if not math.isclose(row['step_m'], step/1000, rel_tol=1e-6):
                raise ValueError('probe returned the wrong grid step')
            row['tensor_checks'] = validate_segment(row)
            rows.append(row)
        segments[segment] = {'grids': rows, 'sampling_sensitivity': sampling_sensitivity(rows)}
    diagnostics = annotate_diagnostics({mode: probe_rows(probe, mode, 'none', min(steps), args) for mode in ('bones', 'knee', 'spine')})
    result = {'schema_version': 1, 'result_label': 'template estimate', 'gate': use_gate(args.use),
              'build_provenance': provenance,
              'source_file_sha256': {path: snapshot[1][path] for path in source_files},
              'report_logic_sha256': snapshot[1]['tools/anatomy_validity.py'],
              'inventory_sha256': snapshot[1]['docs/validation/anatomy-provenance.json'],
              'follow_ups': ['https://github.com/SethKitchen/ThreeMojo/issues/595', 'https://github.com/SethKitchen/ThreeMojo/issues/596'],
              'spec': {'stature_m': args.stature_m, 'sex': args.sex, 'side': args.side, 'athleticism': args.athleticism, 'genome': 'template'},
              'frame': {'origin': 'tibiofemoral joint line', 'x': 'body-right', 'y': 'proximal', 'z': 'anterior'},
              'tensor_convention': {'order': ['xx','yy','zz','xy','xz','yz'], 'reference': 'center of mass', 'off_diagonal': 'negative products of inertia'},
              'controls': controls[0], 'segments': segments,
              'composition': compose_segments([segments[s]['grids'][-1] for s in SEGMENTS]),
              'diagnostics': diagnostics, 'geometry_findings': diagnostic_findings(diagnostics),
              'diagnostic_limits': {'step_m': min(steps)/1000, 'absence_of_hits_proves_clearance': False, 'field_values_are_true_clearance': False, 'bone_fields_are_disjoint_material_regions': False,
                'not_evaluated': ['muscle-to-muscle and muscle-to-bone pairs', 'foot ligaments', 'vascular, nerve and lymphatic pairs', 'whole-body overlap', 'dynamic contact', 'visual/rig/bake mapping (#297)']},
              'accounting': {'exclusive_density_precedence': list(REGIONS), 'bone_precedence': ['femur','tibia','fibula','patella'] + [r['second'] for r in diagnostics['bones'] if r['first'] == 'femur' and r['second'].startswith('foot/')],
                'soft_precedence': 'First leg muscle/tendon, then first foot muscle/tendon, then unresolved fat proxy.',
                'do_not_add': ['individual bone/soft-part mass reports','skin envelope mass a second time','SweepField.volume totals'],
                'missing': ['contralateral limb','pelvis/trunk/head/arms/hands','tissue above the hip cut','bone pore-fluid and pore-marrow mass','separate unresolved tissue densities']},
              'provenance_inventory': inventory}
    finite_tree(result)
    verify_report_inputs(ROOT, probe, provenance, snapshot, metadata)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--mojo', default=str(ROOT/'.venv/bin/mojo'))
    parser.add_argument('--probe', type=Path, default=ROOT/'.cache/anatomy-probe')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--steps-mm', nargs='+', type=float, default=[20,10,5])
    parser.add_argument('--stature-m', type=float, default=1.8288)
    parser.add_argument('--sex', choices=('male','female'), default='male')
    parser.add_argument('--side', choices=('right','left'), default='right')
    parser.add_argument('--athleticism', choices=('untoned','toned'), default='untoned')
    parser.add_argument('--use', choices=USES, default='template-estimate')
    args = parser.parse_args(argv)
    try:
        result = report(args)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError) as error:
        print(f'anatomy validity report failed: {error}', file=sys.stderr)
        return 1
    print(f'{args.output}: template estimate; engineering validation remains unsupported')
    return 0 if result['gate']['permitted_as_labeled'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
