# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact followup composition without rewriting historical proof records."""
import hashlib
import json
from pathlib import Path
import _full_audit_test_fixtures as cleanup_fixtures
import unittest
from unittest.mock import patch
import coverage_followup_contracts as followup
import coverage_invariant_contracts as invariant
import winner_sign_contracts as winner
import border_parser_contracts as border
ROOT=Path(__file__).resolve().parents[2]


# This module's fixed byte/line/body assertions describe the historical main
# graph. The #333 current graph has separate physical admission/mutation tests.
_CURRENT_SOURCE_ROOT = ROOT


def setUpModule():
    global ROOT
    import _full_audit_test_fixtures as historical_fixtures
    owner = type('HistoricalModuleFixture', (), {
        'addCleanup': staticmethod(unittest.addModuleCleanup)})()
    ROOT = historical_fixtures.copy_historical_boundary_root(owner, _CURRENT_SOURCE_ROOT)
    unittest.addModuleCleanup(globals().__setitem__, 'ROOT', _CURRENT_SOURCE_ROOT)


class CoverageFollowupContracts(unittest.TestCase):
    def test_current_cleanup_adds_exactly_one_canonical_dependency(self):
        prior_successors = cleanup_fixtures.WINNER_PRE_BORDER_SUCCESSORS
        new_dependency = cleanup_fixtures.WINNER_FULL_AUDIT_NEW_DEPENDENCY
        result = winner.verify(ROOT)
        current = cleanup_fixtures.assert_winner_canonical_partition(
            self, ROOT, result, prior_successors | {border.MODULE, new_dependency},
            (20, 92))
        canonical = json.loads((ROOT/winner.MIGRATION).read_bytes())['canonical_source_unchanged']
        full_audit = cleanup_fixtures.cleanup
        self.assertEqual({path for path in full_audit.SOURCE_PATHS
                          if canonical[path] == full_audit.BEFORE_SHA256[path]},
                         {new_dependency})
        historical = cleanup_fixtures.historical_root(self, ROOT)
        for name in full_audit.SOURCE_PATHS:
            self.assertEqual(hashlib.sha256((ROOT/name).read_bytes()).hexdigest(),
                             full_audit.AFTER_SHA256[name])
            self.assertEqual(hashlib.sha256((historical/name).read_bytes()).hexdigest(),
                             full_audit.BEFORE_SHA256[name])
        path = historical/border.MODULE
        original = path.read_text()
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), border.AFTER_SHA256)
        record = border.read_record(historical)
        states = ((original, (19, 93), {border.MODULE}),
                  (border.predecessor_source(original, record), (18, 94), set()))
        try:
            for text, expected, border_paths in states:
                with self.subTest(expected=expected):
                    path.write_text(text)
                    result = winner.verify(historical)
                    changed = cleanup_fixtures.assert_winner_canonical_partition(
                        self, historical, result, prior_successors | border_paths, expected)
                    self.assertEqual(current - changed,
                                     {new_dependency} | ({border.MODULE} - border_paths))
                    self.assertEqual(changed - current, set())
        finally:
            path.write_text(original)

    def test_six_module_edges_and_shared_source_chain(self):
        record=followup.verify(ROOT);prior=invariant.read_record(ROOT)
        self.assertEqual(len(record['sources']),6)
        self.assertEqual(set(record['sources']) & set(prior['sources']),
                         {'extensions/carla/curve_sample_dispatch.mojo','extensions/carla/lane_refinement.mojo','extensions/carla/spiral_grouped_roundoff_proof.mojo'})
        step=record['sources']['extensions/carla/curve_sample_dispatch.mojo']
        self.assertEqual(step['before_sha256'],prior['sources']['extensions/carla/curve_sample_dispatch.mojo']['after_sha256'])
        historical = cleanup_fixtures.historical_root(self, ROOT)
        result=winner.verify(historical)
        # Retain the pre-extraction counts; the physical fixture keeps
        # the three shared-helper successors in either border-parser state.
        expected = {border.BEFORE_SHA256: (18, 94), border.AFTER_SHA256: (19, 93)}
        parser_sha = hashlib.sha256((historical/border.MODULE).read_bytes()).hexdigest()
        self.assertIn(parser_sha, expected)
        border_paths = {border.MODULE} if parser_sha == border.AFTER_SHA256 else set()
        prior_successors = cleanup_fixtures.WINNER_PRE_BORDER_SUCCESSORS
        cleanup_fixtures.assert_winner_canonical_partition(
            self, historical, result, prior_successors | border_paths, expected[parser_sha])
        self.assertEqual(len(prior['sources'])+4,8)
        self.assertEqual(112-8,104)

    def test_exact_pin_scope_reconstructs_previous_checkpoint(self):
        record=followup.read_record(ROOT);prior=invariant.read_record(ROOT)
        runtime=record['pin_files']['runtime-source-pins.json']
        self.assertEqual({tuple(x['pointer']) for x in runtime['transitions']},{
            ('groups',group,'extensions/carla/spiral_moment_proof.mojo')
            for group in ('canonical_accumulation','eligibility','support','optional_runtime')} | {
            ('groups',group,'extensions/carla/curve_bounds.mojo')
            for group in ('canonical_accumulation','translation','optional_runtime')} | {
            ('groups','optional_runtime','extensions/carla/curve_sample_dispatch.mojo'),
            ('qualifiers','curve_bounds.mojo')} | {
            ('groups',group,'extensions/carla/lane_refinement.mojo')
            for group in ('canonical_accumulation','translation','support','optional_runtime')} | {
            ('groups',group,'extensions/carla/spiral_roundoff_proof.mojo')
            for group in ('canonical_accumulation','eligibility','support','optional_runtime')} | {
            ('groups','optional_runtime','extensions/carla/spiral_grouped_roundoff_proof.mojo')})
        guarded=record['pin_files']['sum2-guard-pins.json']
        self.assertEqual({tuple(x['pointer']) for x in guarded['transitions']},{
            ('callers','curve_sample_dispatch','functions','_sample_dispatch_cut'),
            ('callers','curve_sample_dispatch','routing'),
            ('callers','spiral_moment_proof','functions','_try_build_spiral_moments'),
            ('callers','lane_refinement','functions','_run_lane_search'),
            ('callers','spiral_grouped_roundoff_proof','functions','_try_spiral_grouped_roundoff_envelope'),
            *{('protected_inventory',path) for path in followup.SOURCE_PATHS
               if path != 'extensions/carla/spiral_roundoff_proof.mojo'}})
        for name in record['pin_files']:
            restored=followup.predecessor_pins(ROOT,name)
            self.assertEqual(hashlib.sha256(restored).hexdigest(),prior['pin_files'][name]['after_sha256'])
        route=next(x for x in guarded['transitions'] if x['pointer']==['callers','curve_sample_dispatch','routing'])
        self.assertEqual(json.loads(route['before'])[1:],json.loads(route['after'])[1:])

    def test_each_active_pin_and_record_mutation_rejects(self):
        original=Path.read_bytes
        for name,record in followup.read_record(ROOT)['pin_files'].items():
            target=ROOT/'tools/carla_lane_oracle'/name
            for change in record['transitions']:
                data=json.loads(target.read_bytes());ref=data
                for part in change['pointer'][:-1]:ref=ref[part]
                ref[change['pointer'][-1]]=change['before']
                payload=(json.dumps(data,indent=2)+'\n').encode()
                def changed(path,*a,**k):return payload if path==target else original(path,*a,**k)
                with self.subTest(pointer=change['pointer']),patch.object(Path,'read_bytes',changed):
                    with self.assertRaises(ValueError):followup.verify(ROOT)
        target=ROOT/followup.MIGRATION;payload=target.read_bytes()+b' '
        def changed(path,*a,**k):return payload if path==target else original(path,*a,**k)
        with patch.object(Path,'read_bytes',changed):
            with self.assertRaises(ValueError):followup.verify(ROOT)

if __name__=='__main__':unittest.main()
