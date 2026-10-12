# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact #302 inverse, physical admission, and endpoint-coherence controls."""
from contextlib import contextmanager
import ast
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import map_station_contracts as station
import map_deviation_contracts as deviation
import seed_count_contracts as seed
import full_audit_cleanup_contracts as cleanup
import _full_audit_test_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]
LEAF = 'tools/carla_lane_oracle/map_station_contracts.py'


class StationLeafControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # The physical Map can be the later deviation endpoint (#685). Its
        # exact inverse gives the station endpoint that these controls bind.
        cls.current = deviation.station_source((ROOT/station.MODULE).read_text())
        cls.before = station.predecessor_source(cls.current)

    def test_exact_sixth_edge_reconstructs_all_five_unchanged_predecessors(self):
        self.assertEqual(station.sha(self.current), station.AFTER_SHA256)
        self.assertEqual(station.sha(self.before), seed.SCORE_AFTER_SHA256)
        self.assertEqual(station.source.token_sha256(self.before), seed.SCORE_AFTER_TOKEN_SHA256)
        text = self.before
        for _, before, after in station.EDITS:
            self.assertEqual(text.count(before), 1)
            text = text.replace(before, after, 1)
        self.assertEqual(text, self.current)
        variants = [(seed.score_predecessor_source, seed.FRONTIER_AFTER_SHA256),
                    (seed.frontier_predecessor_source, seed.SUPPORT_AFTER_SHA256),
                    (seed.support_predecessor_source, seed.OPTIONAL_AFTER_SHA256),
                    (seed.optional_predecessor_source, seed.AFTER_SHA256)]
        text = self.before
        for inverse, expected in variants:
            text = inverse(text)
            self.assertEqual(seed.sha(text), expected)
        self.assertEqual(seed.sha(seed.predecessor_source(text, seed.read_record(ROOT))), seed.BEFORE_SHA256)
        self.assertEqual(seed.score_successor_source(ROOT), self.before)

    def test_unknown_raw_and_token_endpoints_reject(self):
        for text in (self.before, self.current+'\n# unknown\n',
                     self.current.replace('return t * span', 'return t + span', 1),
                     self.current.replace('\n', '\r\n')):
            with self.subTest(digest=station.sha(text)), self.assertRaises(ValueError):
                station.predecessor_source(text)
        with patch.object(station.source, 'token_sha256', return_value=station.BEFORE_TOKEN_SHA256):
            with self.assertRaises(ValueError):
                station.predecessor_source(self.current)

    def test_missing_reordered_modified_and_ambiguous_inverse_reject(self):
        edits = station.EDITS
        for changed in (edits[:-1], edits+(edits[-1],), tuple(reversed(edits))):
            with self.subTest(count=len(changed)), patch.object(station, 'EDITS', changed):
                with self.assertRaises(ValueError): station.predecessor_source(self.current)
        for index, (name, before, after) in enumerate(edits):
            for bad_before, bad_after in ((before+'\n', after), (before, '\n'), (before, after+'\n?')):
                changed = list(edits); changed[index] = (name, bad_before, bad_after)
                with self.subTest(span=name), patch.object(station, 'EDITS', tuple(changed)):
                    with self.assertRaises(ValueError): station.predecessor_source(self.current)

    def test_complete_live_helper_and_both_callers_are_bound(self):
        mutations = (('return t * span', 'return t + span'),
                     ('var l2 = dx * dx + dy * dy', 'var l2 = dx * dx'),
                     ('elif t > 1.0:', 'elif t >= 1.0:'),
                     ('abs(end.s - start.s)', 'end.s - start.s'),
                     ('work.step(query_work.steps)', 'work.step(0)'))
        for before, after in mutations:
            self.assertIn(before, self.current)
            with self.subTest(mutation=before), self.assertRaises(ValueError):
                # Restrict the attack to a bound declaration. Similar arithmetic
                # exists in older certified helpers and must remain unchanged.
                target = next(station.declaration(self.current, name, owner)
                              for name, owner, _ in station.DECLARATIONS
                              if before in station.declaration(self.current, name, owner))
                if before == 'work.step(query_work.steps)':
                    target = station.declaration(self.current, '_closest_lane_with_build_work', ('Map',))
                # Dedented methods need their original four-space source span.
                physical = target if target.startswith('def _chord_station_delta') else ''.join(
                    '    '+line if line.strip() else line for line in target.splitlines(keepends=True))
                self.assertIn(physical, self.current)
                station.verify_live(self.current.replace(physical, physical.replace(before, after, 1), 1))
        helper = station.declaration(self.current, '_chord_station_delta', ())
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            station.verify_live(self.current+'\n'+helper)
        with self.assertRaisesRegex(ValueError, 'scoped'):
            station.declaration(self.current, 'closest_waypoint_on_road', ())

    def test_seed_score_and_fresh_guard_debits_are_unchanged(self):
        for name in ('_winner_seed_update_score', '_try_winner_seed', '_winner_seed_room'):
            self.assertEqual(seed.declaration(self.current, name), seed.declaration(self.before, name))
        self.assertEqual(seed.score_live_observables(self.current), seed.score_live_observables(self.before))

    def test_synthetic_census_never_grants_whole_map_admission(self):
        with tempfile.TemporaryDirectory(dir=Path(tempfile.gettempdir()).resolve()) as directory:
            root = Path(directory)
            path = root/station.MODULE
            path.parent.mkdir(parents=True)
            path.write_text('def _winner_seed_update_score():\n    pass\n_winner_seed_update_score()\n')
            seed.verify_score_caller_inventory(root)
            for explicit in (False, True):
                with self.subTest(endpoint=explicit), self.assertRaisesRegex(ValueError, 'endpoint differs'):
                    seed.verify_score_caller_inventory(root, station_edge=explicit)
            # Supply the genuine immutable record and numerical input so that
            # failure is the actual Map endpoint, not a missing fixture.
            for name in (seed.MIGRATION, *seed.SCORE_TESTS):
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((ROOT/name).read_bytes())
            with self.assertRaisesRegex(ValueError, 'unknown score-helper successor'):
                seed.verify_score(root)
            extra = root/'extensions/carla/extra.mojo'
            extra.write_text('from extensions.carla.map import _winner_seed_update_score\n')
            with self.assertRaisesRegex(ValueError, 'caller inventory'):
                seed.verify_score_caller_inventory(root)

    def test_all_authority_calls_pass_the_actual_endpoint_discriminant(self):
        tree = ast.parse(Path(seed.__file__).read_text())
        verify = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'verify_score')
        calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Name) and node.func.id == 'verify_score_caller_inventory']
        self.assertEqual(len(calls), 2)
        for call in calls:
            self.assertIn(call, list(ast.walk(verify)))
            keywords = [kw for kw in call.keywords if kw.arg == 'station_edge']
            self.assertEqual(len(keywords), 1)
            self.assertEqual(ast.dump(keywords[0].value), ast.dump(ast.Name(id='station_edge', ctx=ast.Load())))
        expected = ast.dump(ast.parse("station_edge = deviation_edge or sha(text) == station.AFTER_SHA256").body[0], include_attributes=False)
        self.assertEqual(sum(ast.dump(node, include_attributes=False) == expected for node in verify.body), 1)
        expected = ast.dump(ast.parse('deviation_edge = sha(text) == deviation.AFTER_SHA256').body[0], include_attributes=False)
        self.assertEqual(sum(ast.dump(node, include_attributes=False) == expected for node in verify.body), 1)
        names = [ast.unparse(node.func) for node in ast.walk(verify) if isinstance(node, ast.Call)]
        self.assertIn('station.predecessor_source', names)
        self.assertIn('score_predecessor_source', names)

    def test_new_leaf_executed_code_defaults_and_module_witness_are_bound(self):
        self.assertEqual(cleanup.executing_checker_bindings()[LEAF],
                         hashlib.sha256(Path(station.__file__).read_bytes()).hexdigest())
        original = station.predecessor_source
        with patch.object(station, 'predecessor_source', lambda text: text):
            with self.assertRaisesRegex(ValueError, 'executing function changed'):
                cleanup.executing_checker_bindings()
        with patch.object(original, '__defaults__', ('unreviewed',)):
            with self.assertRaisesRegex(ValueError, 'defaults changed'):
                cleanup.executing_checker_bindings()
        with patch.object(station, '_EXECUTED_MODULE_CODE', compile('pass', station.__file__, 'exec')):
            with self.assertRaisesRegex(ValueError, 'module-code witness changed'):
                cleanup.executing_checker_bindings()


class StationIntegrationControls(unittest.TestCase):
    def setUp(self):
        self.root = fixtures.copy_current_root(self, ROOT)
        # Hold the fixture at the station endpoint. The deviation successor
        # has its own controls in test_map_deviation_contracts.
        self.current = deviation.station_source(
            (self.root/station.MODULE).read_bytes().decode()).encode()
        (self.root/station.MODULE).write_bytes(self.current)
        self.before = station.predecessor_source(self.current.decode()).encode()

    @contextmanager
    def map_state(self, raw):
        path = self.root/station.MODULE
        old = path.read_bytes(); path.write_bytes(raw)
        try: yield
        finally: path.write_bytes(old)

    def test_sixth_and_fifth_edges_retain_exact_historical_chain_and_receipts(self):
        current = seed.verify(self.root)
        self.assertEqual(len(current['edges']), 6)
        self.assertEqual(current['edges'][-1], station.edge())
        with self.map_state(self.before):
            fifth = seed.verify(self.root)
            self.assertEqual(len(fifth['edges']), 5)
            self.assertEqual(current['edges'][:-1], fifth['edges'])
            self.assertEqual(cleanup.proof_bindings(self.root)[station.MODULE], station.BEFORE_SHA256)
        bound = cleanup.proof_bindings(self.root)
        self.assertEqual(bound[station.MODULE], station.AFTER_SHA256)
        self.assertEqual(bound[LEAF], hashlib.sha256((self.root/LEAF).read_bytes()).hexdigest())
        for path, digest in station.TESTS.items(): self.assertEqual(bound[path], digest)
        record = cleanup.read_record(self.root)
        for group in ('unchanged_inputs', 'native_dependency_inputs'):
            self.assertEqual(record[group][station.MODULE], station.BEFORE_SHA256)
        self.assertEqual((self.root/station.MODULE).read_bytes(), self.current)

    def test_crossed_station_census_endpoints_and_extra_caller_reject(self):
        seed.verify_score_caller_inventory(self.root, station_edge=True)
        with self.assertRaisesRegex(ValueError, 'endpoint differs'):
            seed.verify_score_caller_inventory(self.root, station_edge=False)
        with self.map_state(self.before):
            seed.verify_score_caller_inventory(self.root, station_edge=False)
            with self.assertRaisesRegex(ValueError, 'endpoint differs'):
                seed.verify_score_caller_inventory(self.root, station_edge=True)
        extra = self.root/'extensions/carla/station_extra.mojo'
        extra.write_text('from extensions.carla.map import _chord_station_delta\n')
        with self.assertRaisesRegex(ValueError, 'station helper production caller'):
            seed.verify_score_caller_inventory(self.root, station_edge=True)
        with self.assertRaises(ValueError): cleanup.verify(self.root)

    def test_supplied_old_tokens_cannot_use_new_physical_endpoint(self):
        import cache_key_contracts as cache
        import lane_order_contracts as order
        read = Path.read_text; target = self.root/station.MODULE
        for consumer in (cache, order):
            for supplied in (self.before.decode(), self.current.decode().replace('return t * span', 'return span', 1)):
                with self.subTest(consumer=consumer.__name__), patch.object(Path, 'read_text',
                        lambda path,*a,**k: supplied if path == target else read(path,*a,**k)):
                    with self.assertRaisesRegex(RuntimeError if consumer is order else ValueError, 'supplied score-helper'):
                        consumer.inventory(self.root)
            with patch.object(Path, 'read_text', lambda path,*a,**k:
                    self.current.decode()+'\n# supplied comment\n' if path == target else read(path,*a,**k)):
                consumer.inventory(self.root)

    def test_every_new_test_and_leaf_read_is_pinned_and_unreadable_fails(self):
        for name in (*station.TESTS, LEAF):
            path = self.root/name; original = path.read_bytes()
            with self.subTest(path=name):
                path.write_bytes(original+b'\n# unreviewed fixture\n')
                try:
                    with self.assertRaises(ValueError): cleanup.verify(self.root)
                finally: path.write_bytes(original)
                read = Path.read_bytes
                def denied(actual, *args, **kwargs):
                    if actual == path: raise OSError('station input read denied')
                    return read(actual, *args, **kwargs)
                with patch.object(Path, 'read_bytes', denied), self.assertRaises(ValueError):
                    cleanup.verify(self.root)

    def test_new_test_observation_failure_is_sticky_after_catch_and_restore(self):
        import winner_sign_contracts as winner
        name = next(iter(station.TESTS)); target = self.root/name
        read, original = Path.read_bytes, seed.verify_score
        injected, caught = [], []
        def changed(path, *args, **kwargs):
            value = read(path, *args, **kwargs)
            caller = sys._getframe(1)
            if path == target and caller.f_globals is vars(seed) and caller.f_code.co_name == 'verify_score' and not injected:
                injected.append(True)
                return value+b'\n# consumed transient B\n'
            return value
        def catch(root, **kwargs):
            try: return original(root, **kwargs)
            except ValueError as error:
                caught.append(str(error))
                # A fresh call cannot clear the original owner's failed state.
                return original(root, **kwargs)
        with patch.object(Path, 'read_bytes', changed), patch.object(seed, 'verify_score', catch):
            with self.assertRaises(cleanup._OperationCoherenceError): winner.verify(self.root)
        self.assertEqual(injected, [True]); self.assertTrue(caught)
        self.assertEqual((self.root/station.MODULE).read_bytes(), self.current)


if __name__ == '__main__':
    unittest.main()
