# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Complete pair accounting and strict native/report protocol controls."""
import copy
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import anatomy_validity as av


def catalog():
    rows = []
    for region, families in av.PAIR_REGION_COUNTS.items():
        for family, count in families.items():
            for part in range(count):
                suffix = ('femur', 'tibia', 'fibula', 'patella')[part] if (region, family) == ('leg', 'bone') else ('cartilage', 'medial', 'lateral', 'mcl', 'lcl')[part] if family == 'knee' else part
                identity = f'{region}/{family}/{suffix}'
                rows.append({'record': 'component', 'index': len(rows),
                             'component_id': identity, 'label': identity,
                             'family': family, 'low_m': [0, 0, 0],
                             'high_m': [.02, .02, .02], 'translation_m': [0, 0, 0]})
    return rows


def pair_row(a, b):
    return {'record': 'pair', 'first_id': a['component_id'], 'second_id': b['component_id'],
            'first': a['label'], 'second': b['label'], 'samples': 1, 'overlap_samples': 0,
            'bounds_gap_m': 0, 'overlap_volume_m3': 0, 'signed_field_witness_m': .1}


def legacy(rows):
    result = {'bones': [], 'knee': []}
    for entry in av.pair_plan(rows, 'full'):
        group = entry['legacy_group']
        if group:
            i, j = entry['indices']
            result[group].append(pair_row(rows[i], rows[j]))
    return av.annotate_diagnostics(result)


class PairInventoryTests(unittest.TestCase):
    def test_complete_catalog_contract_refuses_incomplete_or_ambiguous_fields(self):
        self.assertEqual(len(av.validate_catalog(catalog())), 134)
        mutations = [lambda r: r.pop(), lambda r: r[0].update(index=True),
                     lambda r: r[1].update(component_id=r[0]['component_id']),
                     lambda r: r[1].update(label=r[0]['label']),
                     lambda r: r[0].update(low_m=[float('nan'), 0, 0]),
                     lambda r: r[0].update(high_m=[0, 0, 0]),
                     lambda r: r[0].update(family='unknown'),
                     lambda r: r[-1].update(component_id='foot/lymphatic/999'),
                     lambda r: r[5].update(translation_m=[1, 0, 0]),
                     lambda r: r[-1].update(translation_m=[1, 0, 0])]
        for change in mutations:
            rows = catalog()
            change(rows)
            with self.assertRaises(ValueError):
                av.validate_catalog(rows)

    def test_all_8911_pairs_have_stable_identity_and_exact_class_accounting(self):
        rows = catalog()
        plan = av.pair_plan(rows, 'full')
        self.assertEqual(len(plan), 134*133//2)
        self.assertEqual(len({p['pair_id'] for p in plan}), len(plan))
        self.assertEqual(sum(p['legacy_group'] == 'bones' for p in plan), 435)
        self.assertEqual(sum(p['legacy_group'] == 'knee' for p in plan), 30)
        self.assertTrue(all(p['status'] == 'checked' for p in plan))
        self.assertEqual(av.pair_identity(rows[0], rows[1]), av.pair_identity(rows[1], rows[0]))
        renamed = rows[0] | {'label': 'a new display name'}
        self.assertEqual(av.pair_identity(rows[0], rows[1]), av.pair_identity(renamed, rows[1]))
        representative = av.pair_plan(rows, 'representative')
        classes = {p['class'] for p in plan}
        self.assertEqual(classes, {p['class'] for p in representative if p['status'] == 'checked'})
        self.assertTrue(any(p['status'] == 'intentionally_omitted' for p in representative))
        self.assertFalse(any(p['status'] == 'unsupported' for p in representative))
        with self.assertRaises(ValueError):
            av.pair_plan(rows, 'unchecked')

    def test_representative_selects_the_largest_intersection_not_the_first_pair(self):
        rows = catalog()
        for row in rows:
            row['high_m'] = [.001, .001, .001]
        muscles = [row for row in rows
                   if row['family'] == 'muscle' and row['component_id'].startswith('leg/')]
        a, b, c = muscles[:3]
        a['high_m'] = [.06, .06, .06]
        b['high_m'] = [.02, .02, .02]
        c['high_m'] = [.04, .04, .04]

        def selected():
            return {entry['pair_id'] for entry in av.pair_plan(rows, 'representative')
                    if entry['status'] == 'checked' and entry['class'] == 'muscle|muscle'
                    and entry['first_id'].startswith('leg/')
                    and entry['second_id'].startswith('leg/')}

        # The later A/C pair intersects in a 4 cm cube; A/B has only 2 cm.
        self.assertEqual(selected(), {av.pair_identity(a, c)})
        b['high_m'] = [.05, .05, .05]
        c['high_m'] = [.03, .03, .03]
        self.assertEqual(selected(), {av.pair_identity(a, b)})
        # Equal maximum boxes retain the first pair in catalog order.
        b['high_m'] = c['high_m'] = [.04, .04, .04]
        self.assertEqual(selected(), {av.pair_identity(a, b)})

    def test_batches_are_exhaustive_bounded_and_never_drop_large_pairs(self):
        rows = catalog()
        plan = av.pair_plan(rows, 'full')
        batches = av.pair_batches(plan, rows, 5)
        self.assertEqual(sum(map(len, batches)), 8911-435-30)
        self.assertTrue(all(len(b) <= 16 for b in batches))
        self.assertEqual([e['pair_id'] for b in batches for e in b],
                         [e['pair_id'] for e in plan if not e['legacy_group']])
        for step in (0, 1, 21, True, float('nan')):
            with self.assertRaises(ValueError):
                av.pair_batches(plan, rows, step)
        for row in rows:
            row['high_m'] = [1, 1, 1]
        with self.assertRaisesRegex(ValueError, 'work budget'):
            av.pair_batches(plan, rows, 2)

    def test_probe_protocol_retains_unknowns_and_refuses_invalid_evidence(self):
        a, b = catalog()[:2]
        base = pair_row(a, b)
        valid = av.validate_pair_row(base.copy(), a, b)
        self.assertFalse(valid['allowlist_applied'])
        self.assertEqual(valid['allowed_positive_overlap_volume_m3'], 0)
        disjoint = b | {'low_m': [.02, 0, 0], 'high_m': [.04, .02, .02]}
        zero = av.validate_pair_row(base | {'samples': 0, 'signed_field_witness_m': 0}, a, disjoint)
        self.assertIsNone(zero['signed_field_witness_m'])
        for change in ({'first_id': 'missing'}, {'samples': True}, {'samples': 2_000_001},
                       {'samples': -1}, {'overlap_samples': 2}, {'bounds_gap_m': -1},
                       {'overlap_volume_m3': float('inf')}, {'overlap_volume_m3': 1},
                       {'overlap_samples': 1}, {'samples': 0}, {'bounds_gap_m': 1},
                       {'samples': 0, 'signed_field_witness_m': 0}, {'signed_field_witness_m': -.1}):
            with self.assertRaises(ValueError):
                av.validate_pair_row(base | change, a, b)
        overlap = base | {'overlap_samples': 1, 'overlap_volume_m3': 1e-9, 'signed_field_witness_m': -1e-4}
        measured = av.validate_pair_row(overlap, a, b)
        findings = av.diagnostic_findings({'lower_limb_tissues': [measured]})
        self.assertEqual(findings[0]['kind'], 'unallowlisted_sampled_overlap')

    def test_collect_requires_every_measurement_and_preserves_legacy_ids(self):
        for scope in av.PAIR_SCOPES:
            rows = catalog()
            old = legacy(rows)
            original = copy.deepcopy(old)
            args = SimpleNamespace(pair_scope=scope)
            def probe(_probe, mode, part, _step, _args):
                self.assertEqual(mode, 'pairs')
                if part == 'catalog':
                    return rows
                i, start, stop = map(int, part.split(':'))
                return [pair_row(rows[i], rows[j]) for j in range(start, stop)]
            with patch.object(av, 'probe_rows', side_effect=probe):
                measured, inventory = av.collect_pair_diagnostics(None, 5, args, old)
            self.assertEqual(old, original)
            self.assertEqual(inventory['total_pairs'], 8911)
            self.assertEqual(inventory['all_catalog_pairs_checked'], scope == 'full')
            self.assertEqual(sum(p['status'] == 'checked' for p in inventory['pairs']), len(measured)+465)
            self.assertTrue(all('diagnostic_id' in p for p in inventory['pairs']
                                if p['class'] in ('bone|bone', 'knee|knee')))
            self.assertEqual(inventory['positive_volume_attachment_allowances'], [])
        for failure in ('missing_legacy', 'extra_legacy', 'empty_batch', 'wrong_identity'):
            rows = catalog()
            old = legacy(rows)
            if failure == 'missing_legacy':
                old['bones'].pop()
            elif failure == 'extra_legacy':
                old['bones'].append(pair_row(rows[0], rows[-1]) | {'pair_id': 'extra'})
            def broken(_probe, mode, part, _step, _args):
                if part == 'catalog':
                    return rows
                if failure == 'empty_batch':
                    return []
                i, start, stop = map(int, part.split(':'))
                return [pair_row(rows[j], rows[i]) for j in range(start, stop)]
            with patch.object(av, 'probe_rows', side_effect=broken), self.assertRaises(ValueError):
                av.collect_pair_diagnostics(None, 5, SimpleNamespace(pair_scope='representative'), old)


if __name__ == '__main__':
    unittest.main()
