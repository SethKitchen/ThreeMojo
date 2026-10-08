# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Current invariant successor and byte-exact retained lineage controls."""
import hashlib
import json
from pathlib import Path
import unittest
import subprocess
import sys
from unittest.mock import patch
import coverage_invariant_contracts as invariant
import reviewed_cleanup_contracts as cleanup
import frozen_arc_producer_contracts as frozen
import source_contracts as source
import sum2_guard_contracts as guard
import winner_sign_contracts as winner
ROOT = Path(__file__).resolve().parents[2]

class CoverageInvariantContracts(unittest.TestCase):
    def test_direct_and_qualified_package_verification(self):
        for setup in (
                'sys.path = [str(Path.cwd()/"tools/carla_lane_oracle")] + '
                '[p for p in sys.path if p and Path(p).resolve() != Path.cwd()]; '
                'import coverage_invariant_contracts as invariant',
                'from tools.carla_lane_oracle import coverage_invariant_contracts as invariant'):
            command = ('import sys; from pathlib import Path; ' + setup
                       + '; result=invariant.verify(Path.cwd()); '
                       + 'sys.exit(0 if len(result["sources"]) == 4 else 1)')
            with self.subTest(import_mode=setup):
                subprocess.run([sys.executable, '-c', command], cwd=ROOT,
                               check=True, capture_output=True, text=True, timeout=10)

    def test_live_scope_and_retained_historical_counts(self):
        record = invariant.verify(ROOT)
        result = winner.verify(ROOT)
        self.assertEqual((result['reviewed_cleanup_successors'],
                          result['canonical_dependencies_unchanged']), (8, 104))
        self.assertEqual(len(record['sources']), 4)
        self.assertEqual(len(cleanup.read_record(ROOT)['sources']), 3)
        self.assertEqual(len(cleanup.read_record(ROOT)['sources']) + 1, 4)
        original = json.loads((ROOT/winner.MIGRATION).read_text())
        self.assertEqual(len(original['canonical_source_unchanged']) - 4, 108)
        for path, item in record['sources'].items():
            self.assertEqual(item['before_sha256'], original['canonical_source_unchanged'][path])

    def test_exact_runtime_and_guard_predecessors(self):
        record = invariant.read_record(ROOT)
        runtime = record['pin_files']['runtime-source-pins.json']
        self.assertEqual({tuple(x['pointer']) for x in runtime['transitions']}, {
            ('groups', 'optional_runtime', path) for path in invariant.SOURCE_PATHS} | {
            ('groups', group, 'extensions/carla/lane_refinement.mojo')
            for group in ('canonical_accumulation', 'translation', 'support')})
        self.assertEqual(len(runtime['transitions']), 7)
        guarded = record['pin_files']['sum2-guard-pins.json']
        self.assertEqual({tuple(x['pointer']) for x in guarded['transitions']}, {
            ('callers','curve_minimizer_support','functions','_minimizer_support'),
            ('callers','curve_sample_dispatch','functions','_try_sample_dispatch_cuts'),
            ('callers','spiral_grouped_roundoff_proof','functions','_try_spiral_grouped_roundoff_envelope'),
            ('protected_inventory','extensions/carla/curve_sample_dispatch.mojo'),
            ('protected_inventory','extensions/carla/spiral_grouped_roundoff_proof.mojo'),
            ('callers','lane_refinement','functions','_run_lane_search'),
            ('protected_inventory','extensions/carla/lane_refinement.mojo')})
        previous = frozen.read_record(ROOT)
        for name, key in [('runtime-source-pins.json','runtime_pins_after_sha256'),
                          ('sum2-guard-pins.json','guard_pins_unchanged_sha256')]:
            restored = invariant.predecessor_pins(ROOT, name)
            self.assertEqual(hashlib.sha256(restored).hexdigest(), previous[key])

    def test_each_pin_edit_fails_without_reviewed_reseal(self):
        original = Path.read_bytes
        for name, record in invariant.read_record(ROOT)['pin_files'].items():
            target = ROOT/'tools/carla_lane_oracle'/name
            for change in record['transitions']:
                pins = json.loads(target.read_bytes()); ref = pins
                for key in change['pointer'][:-1]: ref = ref[key]
                ref[change['pointer'][-1]] = change['before']
                payload = (json.dumps(pins, indent=2)+'\n').encode()
                def mutated(path, *args, **kwargs):
                    return payload if path == target else original(path,*args,**kwargs)
                with self.subTest(file=name,pointer=change['pointer']):
                    with patch.object(Path,'read_bytes',mutated):
                        with self.assertRaises(ValueError): invariant.verify(ROOT)

    def test_changed_record_cannot_authorize_active_pin(self):
        target = ROOT/invariant.MIGRATION
        payload = target.read_bytes().replace(b'"schema": 1', b'"schema": 2')
        original = Path.read_bytes
        def mutated(path,*args,**kwargs):
            return payload if path == target else original(path,*args,**kwargs)
        with patch.object(Path,'read_bytes',mutated):
            with self.assertRaises(ValueError): invariant.verify(ROOT)

if __name__ == '__main__': unittest.main()
