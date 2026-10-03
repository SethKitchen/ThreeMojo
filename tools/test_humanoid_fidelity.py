# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Synthetic immutable-part, tensor, stale-bake and unsupported-path tests."""
from copy import deepcopy
import json
import math
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from humanoid_fidelity import (adapt_part, Frame, IDENTITY, Y_TO_Z, Z_TO_Y, canonical_bytes,
    digest, finite, frame_rotation, make_snapshot, read_snapshot, report_properties, rotation,
    transform_inertia, transform_point, validate_derivative, validate_snapshot,
    vector, visual_derivative, write_snapshot)


def report():
    labels = ['dermis', 'cortical_apparent', 'trabecular_apparent', 'marrow_fat_proxy',
              'muscle', 'tendon', 'unresolved_fat_proxy']
    segments = {}
    for name in ('thigh', 'shank', 'foot'):
        grids = []
        for step in (.02, .01, .005):
            grids.append({'record': 'segment', 'segment': name,
                'mass_kg': 2, 'center_m': [1, 2, 3], 'inertia_kg_m2': [3, 4, 5, .2, .3, .4],
                'step_m': step, 'length_m': 1, 'low_m': [0, 0, 0], 'high_m': [4, 4, 4],
                'regions': {label: {'mass_kg': 2 if label == 'dermis' else 0,
                                   'volume_m3': .001 if label == 'dermis' else 0} for label in labels}})
        segments[name] = {'grids': grids, 'sampling_sensitivity': {}}
    return {'schema_version': 1, 'result_label': 'template estimate',
            'build_provenance': {'synthetic': True}, 'source_file_sha256': {},
            'report_logic_sha256': 'synthetic-control', 'inventory_sha256': 'synthetic-control',
            'follow_ups': [], 'spec': {}, 'controls': {}, 'composition': {},
            'diagnostics': {}, 'geometry_findings': [], 'provenance_inventory': {},
            'segments': segments, 'gate': {'engineering_validated': False},
            'accounting': {'exclusive_density_precedence': labels},
            'tensor_convention': {'order': ['xx', 'yy', 'zz', 'xy', 'xz', 'yz'],
                                 'reference': 'center of mass', 'off_diagonal': 'negative products of inertia'},
            'diagnostic_limits': {},
            'frame': {'origin': 'tibiofemoral joint line', 'x': 'body-right', 'y': 'proximal', 'z': 'anterior'}}


def snapshot():
    return make_snapshot({'stature_m': 1.8288}, 'synthetic-canonical-v1', [{
        'part_id': 'synthetic/triangle', 'tissue_label': 'unresolved_fat_proxy',
        'frame': Frame.Y_UP.value, 'origin_label': 'synthetic origin',
        'vertices_m': [[0, 0, 0], [1, 0, 0], [0, 1, 0]], 'triangles': [[0, 1, 2]],
        'physical_properties': {'mass_kg': 2, 'center_m': [0, 0, 0],
            'frame': Frame.Y_UP.value, 'origin_label': 'synthetic origin',
            'inertia_kg_m2': [3, 4, 5, 0.2, 0.3, 0.4],
            'tensor_reference': 'center-of-mass', 'source_report_record': 'synthetic-control'},
    }], report(), origin_label='synthetic origin')


class FidelityTest(unittest.TestCase):
    def test_full_tensor_rotation_and_reference_shift(self):
        self.assertEqual(frame_rotation(Frame.Y_UP, Frame.Z_UP), Y_TO_Z)
        self.assertEqual(frame_rotation(Frame.Z_UP, Frame.Y_UP), Z_TO_Y)
        self.assertEqual(frame_rotation(Frame.Y_UP, Frame.Y_UP), IDENTITY)
        self.assertTrue(Frame.Y_UP.is_valid())
        self.assertEqual(transform_point([1, 2, 3], Y_TO_Z), [1, -3, 2])
        before = [3, 4, 5, 0.2, 0.3, 0.4]
        transformed = transform_inertia(2, [1, 2, 3], before, Y_TO_Z, [4, 5, 6])
        self.assertEqual(transformed['center_m'], [5, 2, 8])
        self.assertEqual(transformed['reference_m'], [5, 2, 8])
        self.assertEqual(transformed['inertia_kg_m2'], [3, 5, 4, -0.3, 0.2, -0.4])
        back = transform_inertia(2, transformed['center_m'], transformed['inertia_kg_m2'], Z_TO_Y, [-4, -6, 5])
        self.assertEqual(back['center_m'], [1, 2, 3])
        self.assertEqual(back['inertia_kg_m2'], before)
        shifted = transform_inertia(2, [1, 2, 3], before, IDENTITY, reference_m=[0, 0, 0])
        self.assertEqual(shifted['inertia_kg_m2'], [29, 24, 15, -3.8, -5.7, -11.6])
        # Independent sum of point-mass contributions validates all terms.
        points = [[1, 0, 0], [-1, 0, 0], [0, 2, 1], [0, -2, -1]]
        angle = 0.37
        r = [[math.cos(angle), -math.sin(angle), 0], [math.sin(angle), math.cos(angle), 0], [0, 0, 1]]
        expected = [0.0]*6
        for p in points:
            x, y, z = transform_point(p, r, [1, 3, -2])
            expected = [a+b for a,b in zip(expected, [y*y+z*z, x*x+z*z, x*x+y*y, -x*y, -x*z, -y*z])]
        actual = transform_inertia(4, [0, 0, 0], [10, 4, 10, 0, 0, -4], r, [1, 3, -2], [0, 0, 0])
        for a, b in zip(actual['inertia_kg_m2'], expected):
            self.assertAlmostEqual(a, b, places=12)

    def test_part_adapter_moves_geometry_and_physics_together(self):
        part = snapshot()['parts'][0]
        before = canonical_bytes(part)
        out = adapt_part(part, Frame.Y_UP, Frame.Z_UP, [1, 2, 3], target_origin_label='translated origin')
        self.assertEqual(out['vertices_m'][0], [1, 2, 3])
        self.assertEqual(out['physical_properties']['center_m'], [1, 2, 3])
        self.assertEqual(out['physical_properties']['inertia_kg_m2'], [3, 5, 4, -.3, .2, -.4])
        back = adapt_part(out, Frame.Z_UP, Frame.Y_UP, [-1, -3, 2], target_origin_label='synthetic origin')
        self.assertEqual(back['vertices_m'], part['vertices_m'])
        self.assertEqual(back['physical_properties']['center_m'], [0, 0, 0])
        self.assertEqual(back['physical_properties']['inertia_kg_m2'], part['physical_properties']['inertia_kg_m2'])
        shifted = adapt_part(part, Frame.Y_UP, Frame.Y_UP, [1, 2, 3], [0, 0, 0], target_origin_label='translated origin')
        self.assertEqual(shifted['physical_properties']['tensor_reference'], 'explicit-target-reference')
        with self.assertRaises(ValueError): adapt_part(shifted, Frame.Y_UP, Frame.Z_UP)
        part['physical_properties'] = None
        self.assertIsNone(adapt_part(part, Frame.Y_UP, Frame.Z_UP)['physical_properties'])
        self.assertEqual(canonical_bytes(snapshot()['parts'][0]), before)

    def test_frame_and_origin_contradictions_are_refused(self):
        part = snapshot()['parts'][0]
        z_up = adapt_part(part, Frame.Y_UP, Frame.Z_UP)
        with self.assertRaisesRegex(ValueError, 'part frame'):
            make_snapshot({'stature_m':1.8288}, 'synthetic', [z_up], report(), origin_label='synthetic origin')
        with self.assertRaisesRegex(ValueError, 'source frame'):
            adapt_part(z_up, Frame.Y_UP, Frame.Z_UP)
        back = adapt_part(z_up, Frame.Z_UP, Frame.Y_UP)
        restored = make_snapshot({'stature_m':1.8288}, 'synthetic', [back], report(), origin_label='synthetic origin')
        self.assertEqual(restored['parts'][0]['vertices_m'], part['vertices_m'])
        for key, value in [('frame', Frame.Z_UP.value), ('origin_label', 'different')]:
            bad = snapshot(); bad['parts'][0]['physical_properties'][key] = value
            with self.assertRaises(ValueError): validate_snapshot(bad)
            with self.assertRaises(ValueError): adapt_part(bad['parts'][0], Frame.Y_UP, Frame.Z_UP)
        for key, value in [('frame', None), ('origin_label', 'different')]:
            bad = snapshot(); bad['parts'][0][key] = value
            with self.assertRaises(ValueError): validate_snapshot(bad)
        with self.assertRaisesRegex(ValueError, 'target origin'):
            adapt_part(part, Frame.Y_UP, Frame.Z_UP, [1, 0, 0])
        with self.assertRaises(ValueError): adapt_part(None, Frame.Y_UP, Frame.Z_UP)
        no_physics = deepcopy(part); no_physics['physical_properties'] = None
        no_physics['vertices_m'][0] = [1e308, 0, 0]
        with self.assertRaises(ValueError):
            adapt_part(no_physics, Frame.Y_UP, Frame.Y_UP, [1e308, 0, 0], target_origin_label='overflow')
        with self.assertRaises(ValueError): transform_point([1e308, 0, 0], IDENTITY, [1e308, 0, 0])

    def test_report_structure_frame_and_tensor_semantics_are_required(self):
        for key in ('build_provenance', 'segments', 'accounting', 'tensor_convention',
                    'diagnostic_limits', 'frame', 'follow_ups', 'result_label'):
            broken = report(); broken[key] = None
            with self.assertRaises(ValueError, msg=key): report_properties(broken, 'thigh', 0)
        for key, value in [('reference','global origin'), ('order',['xx','yy','zz','yz','xz','xy']),
                           ('off_diagonal','positive products of inertia')]:
            broken = report(); broken['tensor_convention'][key] = value
            with self.assertRaisesRegex(ValueError, 'tensor'): report_properties(broken, 'thigh', 0)
        broken = report(); broken['frame']['y'] = 'distal'
        with self.assertRaisesRegex(ValueError, 'coordinate frame'): report_properties(broken, 'thigh', 0)
        broken = report(); del broken['segments']['foot']
        with self.assertRaises(ValueError): report_properties(broken, 'thigh', 0)
        broken = report(); broken['accounting']['exclusive_density_precedence'] = ['one']
        with self.assertRaises(ValueError): report_properties(broken, 'thigh', 0)
        for entry in (None, {'grids':None, 'sampling_sensitivity':{}}, {'grids':[], 'sampling_sensitivity':{}}):
            broken = report(); broken['segments']['thigh'] = entry
            with self.assertRaises(ValueError): report_properties(broken, 'thigh', 0)
        for key, value in [('record','wrong'), ('mass_kg',0), ('inertia_kg_m2',[]), ('regions',{})]:
            broken = report(); broken['segments']['thigh']['grids'][0][key] = value
            with self.assertRaises(ValueError): report_properties(broken, 'thigh', 0)
        for value in (None, {'mass_kg':-1,'volume_m3':0}):
            broken = report(); broken['segments']['thigh']['grids'][0]['regions']['dermis'] = value
            with self.assertRaises(ValueError): report_properties(broken, 'thigh', 0)

    def test_bad_transforms_and_numbers_are_refused(self):
        for bad in (True, 'x', float('nan'), float('inf')):
            with self.assertRaises(ValueError): finite(bad)
        for bad in (None, [1, 2], [1, False, 3]):
            with self.assertRaises(ValueError): vector(bad)
        for bad in (None, [1, 2], [[1, 0, 0]]*3, [[1, 0, 0], [0, 1, 0], [0, 0, -1]]):
            with self.assertRaises(ValueError): rotation(bad)
        with self.assertRaises(ValueError): frame_rotation('y', Frame.Z_UP)
        with self.assertRaises(ValueError): frame_rotation(Frame.Y_UP, 'z')
        with self.assertRaises(ValueError): transform_inertia(-1, [0]*3, [0]*6, IDENTITY)
        with self.assertRaises(ValueError): transform_inertia(1, [0]*3, [0]*5, IDENTITY)
        with self.assertRaises(ValueError): transform_inertia(1e308, [1e308]*3, [0]*6, IDENTITY, reference_m=[0]*3)

    def test_snapshot_copy_and_immutable_bytes(self):
        original = snapshot()
        self.assertEqual(validate_snapshot(original), original)
        self.assertFalse(original['engineering_validated'])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'canonical.json'
            key = write_snapshot(path, original)
            self.assertEqual(key, digest(original))
            self.assertEqual(write_snapshot(path, original), key)
            self.assertEqual(read_snapshot(path, key), original)
            changed = deepcopy(original)
            changed['parts'][0]['vertices_m'][0][0] = 2
            with self.assertRaises(ValueError): write_snapshot(path, changed)
            with self.assertRaises(ValueError): read_snapshot(path, 'wrong')
            # Exporters receive a copy. Editing it cannot change disk evidence.
            original['parts'][0]['physical_properties']['mass_kg'] = 10
            self.assertEqual(read_snapshot(path, key)['parts'][0]['physical_properties']['mass_kg'], 2)

    def test_stale_geometry_identity_lod_assets_and_sources(self):
        canonical = snapshot()
        unchanged = canonical_bytes(canonical)
        with tempfile.TemporaryDirectory() as tmp:
            asset = Path(tmp)/'visual.glb'
            asset.write_bytes(b'synthetic visual bytes')
            recipe = {'spec': {'identity': [-1]*8}, 'triangles': 20, 'source': 'v1'}
            manifest = visual_derivative(canonical, asset, recipe)
            validate_derivative(manifest, canonical, asset, recipe)
            self.assertFalse(manifest['engineering_use'])
            self.assertEqual(set(manifest['mappings'].values()), {'unsupported'})
            self.assertEqual(len(manifest['dental_representations']), 2)
            for changed in ({**recipe, 'triangles': 10}, {**recipe, 'source': 'v2'},
                            {**recipe, 'spec': {'identity': [1]*8}}):
                with self.assertRaises(ValueError): validate_derivative(manifest, canonical, asset, changed)
            for at in range(8):
                for extreme in (-1, 1):
                    weights = [0]*8
                    weights[at] = extreme
                    current = visual_derivative(canonical, asset, {'identity': weights})
                    self.assertFalse(current['engineering_use'])
                    self.assertEqual(current['canonical_snapshot_sha256'], digest(canonical))
            self.assertEqual(canonical_bytes(canonical), unchanged)
            changed = deepcopy(canonical)
            changed['parts'][0]['triangles'] = [[2, 1, 0]]
            with self.assertRaises(ValueError): validate_derivative(manifest, changed, asset, recipe)
            manifest['engineering_use'] = True
            with self.assertRaises(ValueError): validate_derivative(manifest, canonical, asset, recipe)
            manifest['engineering_use'] = False
            asset.write_bytes(b'changed')
            with self.assertRaises(ValueError): validate_derivative(manifest, canonical, asset, recipe)
            with self.assertRaises(ValueError): visual_derivative(canonical, asset, {})

    def test_report_properties_copy_the_exact_authoritative_row(self):
        evidence = report()
        copied = report_properties(evidence, 'thigh', 0)
        self.assertEqual(copied['source_report_record'], 'segments/thigh/grids/0')
        self.assertEqual(copied['frame'], Frame.Y_UP.value)
        self.assertEqual(copied['source_report_frame'], evidence['frame'])
        self.assertEqual(copied['origin_label'], evidence['frame']['origin'])
        self.assertEqual(copied['regions'], evidence['segments']['thigh']['grids'][0]['regions'])
        evidence['segments']['thigh']['grids'][0]['mass_kg'] = 7
        self.assertEqual(copied['mass_kg'], 2)
        for part, index in [('unknown', 0), ('thigh', -1), ('thigh', True), ('thigh', 4), ('foot', 9)]:
            with self.assertRaises(ValueError): report_properties(evidence, part, index)

    def test_cli_reports_verified_bytes_or_a_controlled_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'canonical.json'
            key = write_snapshot(path, snapshot())
            tool = Path(__file__).with_name('humanoid_fidelity.py')
            command = [sys.executable, str(tool), str(path), '--sha256']
            passed = subprocess.run(command+[key], capture_output=True, text=True, check=False)
            self.assertEqual(passed.returncode, 0)
            self.assertIn('engineering use remains unsupported', passed.stdout)
            failed = subprocess.run(command+['stale'], capture_output=True, text=True, check=False)
            self.assertEqual(failed.returncode, 2)
            self.assertIn('content changed', failed.stderr)
            self.assertNotIn('Traceback', failed.stderr)

    def test_malformed_snapshots_fail_closed(self):
        cases = [('schema_version', 2), ('schema_version', True), ('units', {}), ('frame', Frame.Z_UP.value),
                 ('origin_m', [0]), ('origin_label', ''), ('source_revision', ''), ('canonical_inputs', {}),
                 ('engineering_validated', True), ('parts', []), ('canonical_validity_report', {}),
                 ('canonical_validity_report', {'schema_version': 1, 'gate': {'engineering_validated': True}})]
        with self.assertRaises(ValueError): validate_snapshot([])
        invalid = snapshot(); invalid['parts'] = [None]
        with self.assertRaises(ValueError): validate_snapshot(invalid)
        for key, value in cases:
            bad = snapshot(); bad[key] = value
            with self.assertRaises(ValueError, msg=key): validate_snapshot(bad)
        bad = snapshot(); bad['parts'].append(deepcopy(bad['parts'][0]))
        with self.assertRaises(ValueError): validate_snapshot(bad)
        for key, value in [('part_id',''), ('tissue_label',''), ('vertices_m',[]), ('triangles',[]),
                           ('triangles',[[0,1]]), ('triangles',[[0,1,9]]), ('triangles',[[0,1,True]]),
                           ('physical_properties',{})]:
            bad = snapshot(); bad['parts'][0][key] = value
            with self.assertRaises(ValueError, msg=key): validate_snapshot(bad)
        bad = snapshot(); bad['parts'][0]['physical_properties'] = None
        validate_snapshot(bad)
        for bad_report in ({}, {'schema_version': 1}, {**report(), 'gate': {'engineering_validated': True}}):
            with self.assertRaises(ValueError): make_snapshot({'x':1}, 'v1', snapshot()['parts'], bad_report, origin_label='test origin')
        # A complete report is copied, with all unresolved limitations intact.
        evidence = report(); evidence['diagnostic_limits']['missing'] = ['eye fit', 'tissue clearance']
        parts = snapshot()['parts']
        held = make_snapshot({'x':1}, 'v1', parts, evidence, origin_label='synthetic origin')
        evidence['diagnostic_limits'].clear(); parts.clear()
        self.assertEqual(held['canonical_validity_report']['diagnostic_limits']['missing'], ['eye fit', 'tissue clearance'])
        self.assertEqual(len(held['parts']), 1)


if __name__ == '__main__':
    unittest.main()
