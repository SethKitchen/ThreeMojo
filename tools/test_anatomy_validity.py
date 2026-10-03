# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Report guards, accounting composition, numerical labels and use gates."""
import copy
import json
import math
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import anatomy_validity as av


def row(name='thigh', low=0.0, high=1.0, step=0.02):
    regions = {key: {'mass_kg': 0.0, 'volume_m3': 0.0} for key in av.REGIONS}
    regions['muscle'] = {'mass_kg': 1.0, 'volume_m3': 0.001}
    return {'record': 'segment', 'segment': name, 'step_m': step,
            'mass_kg': 1.0, 'length_m': 1.0, 'center_m': [0.0, (low+high)/2, 0.0],
            'low_m': [-0.1, low, -0.1], 'high_m': [0.1, high, 0.1],
            'inertia_kg_m2': [0.1, 0.02, 0.1, 0.0, 0.0, 0.0], 'regions': regions}


class AnatomyValidityTests(unittest.TestCase):
    def test_non_finite_numbers_and_grid_requests(self):
        for bad in (True, None, '2', float('nan'), float('inf'), -float('inf')):
            with self.assertRaises(ValueError):
                av.finite(bad, 'fixture')
        self.assertEqual(av.grid_steps([5, 20, 10]), [20, 10, 5])
        for bad in ([0, 10, 5], [1e-300, 10, 5], [math.inf, 10, 5],
                    [math.nan, 10, 5], [21, 10, 5], [20, 10], [20, 10, 10], list(range(2, 13))):
            with self.assertRaises(ValueError):
                av.grid_steps(bad)
        with self.assertRaises(ValueError):
            av.finite_tree({'nested': [float('nan')]})

    def test_psd_checks_use_all_principal_minors(self):
        self.assertTrue(av.tensor_checks([0]*6)['positive_semidefinite'])
        self.assertTrue(av.tensor_checks([3, 4, 5, 1, 0.2, 0.1])['positive_semidefinite'])
        for values in ([-1, 1, 1, 0, 0, 0], [1, 1, 1, 2, 0, 0], [1, 1, 1, 0.9, 0.9, -0.9]):
            self.assertFalse(av.tensor_checks(values)['positive_semidefinite'])
        self.assertFalse(av.tensor_checks([10, 1, 1, 0, 0, 0])['triangle_inequalities'])
        with self.assertRaises(ValueError):
            av.tensor_checks([1, 2])

    def test_region_accounting_must_be_complete_exclusive_and_finite(self):
        self.assertTrue(av.validate_segment(row())['positive_semidefinite'])
        mutations = [lambda r: r.update(record='body'), lambda r: r.update(segment='arm'),
                     lambda r: r.update(mass_kg=0), lambda r: r.update(length_m=0),
                     lambda r: r.update(step_m=1e-30), lambda r: r.update(center_m=[0, 2, 0]),
                     lambda r: r.update(low_m=[0, 1, 0]), lambda r: r.update(center_m=[0]),
                     lambda r: r.update(inertia_kg_m2=[-1, 1, 1, 0, 0, 0]),
                     lambda r: r['regions'].pop('dermis'),
                     lambda r: r['regions']['muscle'].update(mass_kg=-1),
                     lambda r: r['regions']['muscle'].update(mass_kg=2),
                     lambda r: r['regions']['muscle'].update(volume_m3=100)]
        for mutate in mutations:
            bad = row()
            mutate(bad)
            with self.assertRaises(ValueError):
                av.validate_segment(bad)

    def test_composition_refuses_duplicates_gaps_and_overlap(self):
        rows = [row('foot', -1, 0), row('shank', 0, 1), row('thigh', 1, 2)]
        total = av.compose_segments(rows)
        self.assertEqual(total['mass_kg'], 3)
        self.assertEqual(total['center_m'], [0, 0.5, 0])
        self.assertAlmostEqual(total['inertia_kg_m2'][0], 2.3)
        self.assertAlmostEqual(total['inertia_kg_m2'][1], 0.06)
        self.assertFalse(total['is_whole_body'])
        for bad in (rows[:2], rows+[rows[0]], [rows[0], rows[0], rows[2]]):
            with self.assertRaises(ValueError):
                av.compose_segments(bad)
        for delta in (-0.01, 0.01):
            bad = copy.deepcopy(rows)
            bad[0]['high_m'][1] += delta
            with self.assertRaisesRegex(ValueError, 'cut planes'):
                av.compose_segments(bad)
        bad = copy.deepcopy(rows)
        bad[0]['step_m'] = 0.01
        with self.assertRaisesRegex(ValueError, 'same requested grid'):
            av.compose_segments(bad)
        bad = copy.deepcopy(rows)
        bad[0]['high_m'][0] += 0.01
        with self.assertRaisesRegex(ValueError, 'same limb envelope'):
            av.compose_segments(bad)

    def test_sensitivity_never_claims_an_error_bound(self):
        rows = [row(step=s) for s in (0.02, 0.01, 0.005)]
        result = av.sampling_sensitivity(rows)
        self.assertIsNone(result['error_bound'])
        self.assertIsNone(result['observed_order'])
        self.assertFalse(result['converged_to_physical_reference'])
        self.assertEqual(result['comparisons'][0]['tensor_delta_frobenius_kg_m2'], 0)
        for bad in (rows[:2], list(reversed(rows)), [rows[0]]*3):
            with self.assertRaises(ValueError):
                av.sampling_sensitivity(bad)
        rows[0]['inertia_kg_m2'][3] = 0.01
        self.assertAlmostEqual(av.sampling_sensitivity(rows)['comparisons'][0]['tensor_delta_frobenius_kg_m2'], math.sqrt(2)*0.01)

    def test_only_template_and_fantasy_gates_are_enabled(self):
        for use in av.USES:
            gate = av.use_gate(use)
            self.assertEqual(gate['permitted_as_labeled'], use in ('template-estimate', 'game-fantasy'))
            self.assertFalse(gate['engineering_validated'])
            self.assertFalse(gate['clinical_or_safety_certification'])
            self.assertIsNone(gate['task_specific_acceptance_thresholds'])
        with self.assertRaises(ValueError):
            av.use_gate('certified')

    def test_inventory_has_explicit_unknowns_and_bounded_allowlist(self):
        data = json.loads((av.ROOT/'docs/validation/anatomy-provenance.json').read_text())
        for entry in data['parameters']:
            for key in ('units', 'classification', 'supported_population', 'empirical_range', 'uncertainty', 'unknowns'):
                self.assertIn(key, entry)
            for source in entry['source_files']:
                self.assertTrue((av.ROOT/source).is_file(), source)
        rules = {r['id']: r for r in data['intentional_overlap_allowlist']}
        self.assertEqual(rules['spine_endplane_boundary_contact']['allowed_positive_overlap_volume_m3'], 0)
        self.assertFalse(data['engineering_validated'])

    def test_unallowlisted_overlap_and_incompatible_endplanes_are_visible(self):
        pair = {'record': 'pair', 'first': 'bone', 'second': 'disc', 'overlap_samples': 1, 'overlap_volume_m3': 1e-9}
        end = {'record': 'endplane', 'body': 'cervical/2', 'disc_gap_m': 0.001,
               'body_disc_endplane_error_m': 0.0, 'next_body_disc_endplane_error_m': 0.0,
               'body_outside_field_m': 0.0001, 'next_body_outside_field_m': 0.0001,
               'disc_outside_upper_field_m': 0.0001, 'disc_outside_lower_field_m': 0.0001}
        self.assertEqual(av.diagnostic_findings({'spine': [end]}), [])
        self.assertEqual(av.diagnostic_findings({'spine': [pair]})[0]['kind'], 'unallowlisted_sampled_overlap')
        for key in ('disc_gap_m', 'body_outside_field_m', 'next_body_outside_field_m', 'disc_outside_upper_field_m', 'disc_outside_lower_field_m'):
            bad = end | {key: -0.001}
            self.assertTrue(av.diagnostic_findings({'spine': [bad]}))
        for key in ('body_disc_endplane_error_m', 'next_body_disc_endplane_error_m'):
            self.assertTrue(av.diagnostic_findings({'spine': [end | {key: 1e-3}]}))
        self.assertEqual(av.diagnostic_findings({'spine': [end | {'body': 'thoracolumbar/16', 'next_body_outside_field_m': 0}]}), [])
        with self.assertRaises(ValueError):
            av.diagnostic_findings({'spine': [{'record': 'missing'}]})

    def test_source_bound_probe_rejects_missing_or_stale_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'tools').mkdir()
            (root/'docs/validation').mkdir(parents=True)
            (root/'tools/anatomy_validity.py').write_text('one')
            (root/'docs/validation/anatomy-provenance.json').write_text('{}')
            probe = root/'probe'
            with self.assertRaisesRegex(ValueError, 'build'):
                av.prepare_probe(root, probe, 'mojo', False)
            probe.write_text('binary')
            metadata = probe.with_suffix('.provenance.json')
            metadata.write_text('{}')
            with self.assertRaisesRegex(ValueError, 'stale'):
                av.prepare_probe(root, probe, 'mojo', False)
            record = {'source_sha256': av.source_digest(root), 'binary_sha256': av.hashlib.sha256(probe.read_bytes()).hexdigest()}
            metadata.write_text(json.dumps(record))
            self.assertEqual(av.prepare_probe(root, probe, 'mojo', False), record)
            (root/'tools/anatomy_validity.py').write_text('two')
            with self.assertRaisesRegex(ValueError, 'stale'):
                av.prepare_probe(root, probe, 'mojo', False)


if __name__ == '__main__':
    unittest.main()
