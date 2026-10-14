# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact #685 deviation inverse, physical admission and endpoint-coherence controls."""
from contextlib import contextmanager
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import map_deviation_contracts as deviation
import map_station_contracts as station
import seed_count_contracts as seed
import full_audit_cleanup_contracts as cleanup
import _full_audit_test_fixtures as fixtures

ROOT = Path(__file__).resolve().parents[2]

LEAF = 'tools/carla_lane_oracle/map_deviation_contracts.py'
STATION_LEAF = 'tools/carla_lane_oracle/map_station_contracts.py'


def _loops(case):
    # Coverage uses its real package namespace, as the operation tests do.
    tools = str(Path(__file__).resolve().parents[1])
    if tools not in sys.path:
        case.addCleanup(sys.path.remove, tools)
        sys.path.insert(0, tools)
    import coverage_loop_proofs as loops
    return loops


class DeviationLeafControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        owner = type('HistoricalClassFixture', (), {
            'addCleanup': staticmethod(cls.addClassCleanup)})()
        cls.historical_root = fixtures.copy_historical_boundary_root(owner, ROOT)
        cls.current = (cls.historical_root/deviation.MODULE).read_text()
        cls.before = deviation.predecessor_source(cls.current)

    def test_exact_seventh_edge_reconstructs_the_station_endpoint(self):
        self.assertEqual(deviation.sha(self.current), deviation.AFTER_SHA256)
        self.assertEqual(deviation.BEFORE_SHA256, station.AFTER_SHA256)
        self.assertEqual(deviation.BEFORE_TOKEN_SHA256, station.AFTER_TOKEN_SHA256)
        self.assertEqual(deviation.sha(self.before), station.AFTER_SHA256)
        text = self.before
        for _, before, after in deviation.EDITS:
            self.assertEqual(text.count(before), 1)
            text = text.replace(before, after, 1)
        self.assertEqual(text, self.current)
        # The complete chain still reaches the immutable historical Map.
        middle = seed.score_family_predecessor_source(self.current)
        self.assertEqual(seed.sha(middle), seed.FRONTIER_AFTER_SHA256)
        self.assertEqual(deviation.station_source(self.before), self.before)

    def test_only_three_spans_differ_and_every_loop_line_maps_exactly(self):
        loops = _loops(self)
        old, new = self.before.splitlines(), self.current.splitlines()
        for historical, line in loops._MAP_STATION_SUCCESSOR_LINES.items():
            successor = loops._MAP_DEVIATION_SUCCESSOR_LINES[historical]
            self.assertEqual(old[line-1], new[successor-1])
            self.assertTrue(new[successor-1].lstrip().startswith('for '))
        self.assertEqual(set(loops._MAP_DEVIATION_SUCCESSOR_LINES), set(loops._MAP_STATION_SUCCESSOR_LINES))
        self.assertEqual(old[4099-1], new[4106-1])
        self.assertEqual(new[4106-1].strip(), 'for s in boundaries:')
        # Outside the reviewed spans the two endpoints are byte-identical.
        rest_old, rest_new = self.before, self.current
        for name, before, after in deviation.EDITS:
            rest_old = rest_old.replace(before, '<' + name + '>', 1)
            rest_new = rest_new.replace(after, '<' + name + '>', 1)
        self.assertEqual(rest_old, rest_new)

    def test_unknown_raw_and_token_endpoints_reject(self):
        skip = 'if _indexed_curve_lower(key, segment.deviation) > best_radius:'
        for text in (self.before, self.current+'\n# unknown\n',
                     self.current.replace(skip, skip.replace('>', '>='), 1),
                     self.current.replace('\n', '\r\n')):
            with self.subTest(digest=deviation.sha(text)), self.assertRaises(ValueError):
                deviation.predecessor_source(text)
        with patch.object(deviation.source, 'token_sha256', return_value=deviation.BEFORE_TOKEN_SHA256):
            with self.assertRaises(ValueError):
                deviation.predecessor_source(self.current)

    def test_missing_reordered_modified_and_ambiguous_inverse_reject(self):
        edits = deviation.EDITS
        for changed in (edits[:-1], edits+(edits[-1],), tuple(reversed(edits))):
            with self.subTest(count=len(changed)), patch.object(deviation, 'EDITS', changed):
                with self.assertRaises(ValueError): deviation.predecessor_source(self.current)
        for index, (name, before, after) in enumerate(edits):
            for bad_before, bad_after in ((before+'\n', after), (before, '\n'), (before, after+'\n?')):
                changed = list(edits); changed[index] = (name, bad_before, bad_after)
                with self.subTest(span=name), patch.object(deviation, 'EDITS', tuple(changed)):
                    with self.assertRaises(ValueError): deviation.predecessor_source(self.current)

    def test_complete_live_query_and_builder_are_bound(self):
        mutations = (
            ('if _indexed_curve_lower(key, segment.deviation) > best_radius:',
             'if _indexed_curve_lower(key, segment.deviation) >= best_radius:'),
            ('if _indexed_curve_lower(key, segment.deviation) > best_radius:',
             'if _indexed_curve_lower(key, 0.0) > best_radius:'),
            ('var lower = _indexed_curve_lower(key, self._curve_deviation)',
             'var lower = _indexed_curve_lower(key, segment.deviation)'),
            ('                certificate[0],\n            )\n        )\n',
             '                0.0,\n            )\n        )\n'),
        )
        for before, after in mutations:
            self.assertEqual(self.current.count(before), 1)
            with self.subTest(mutation=after), self.assertRaises(ValueError):
                deviation.verify_live(self.current.replace(before, after, 1))
        query = deviation.EDITS[1][2]
        self.assertIn('break', query)
        self.assertLess(query.index('break'), query.index('continue'))
        # The skip precedes candidate admission, as the box skips do.
        selector = station.declaration(self.current, '_closest_lane_certificate_with_work', ('Map',))
        self.assertLess(selector.index('segment.deviation'), selector.index('work.candidate()'))

    def test_seed_score_station_helper_and_fresh_guard_debits_are_unchanged(self):
        for name in ('_winner_seed_update_score', '_try_winner_seed', '_winner_seed_room'):
            self.assertEqual(seed.declaration(self.current, name), seed.declaration(self.before, name))
        self.assertEqual(seed.score_live_observables(self.current), seed.score_live_observables(self.before))
        station.verify_live(self.current)

    def test_score_family_tokens_are_exact(self):
        self.assertEqual(seed.score_family_token_sha256(deviation.AFTER_SHA256), deviation.AFTER_TOKEN_SHA256)
        self.assertEqual(seed.score_family_token_sha256(station.AFTER_SHA256), station.AFTER_TOKEN_SHA256)
        self.assertEqual(seed.score_family_token_sha256(seed.SCORE_AFTER_SHA256), seed.SCORE_AFTER_TOKEN_SHA256)
        self.assertIsNone(seed.score_family_token_sha256(seed.FRONTIER_AFTER_SHA256))
        self.assertIsNone(seed.score_family_token_sha256('0' * 64))

    def test_new_leaf_executed_code_defaults_and_module_witness_are_bound(self):
        self.assertEqual(cleanup.executing_checker_bindings()[LEAF],
                         hashlib.sha256(Path(deviation.__file__).read_bytes()).hexdigest())
        self.assertEqual(cleanup.DEPENDENCY_TOOL_SHA256[LEAF],
                         hashlib.sha256(Path(deviation.__file__).read_bytes()).hexdigest())
        original = deviation.predecessor_source
        with patch.object(deviation, 'predecessor_source', lambda text: text):
            with self.assertRaisesRegex(ValueError, 'executing function changed'):
                cleanup.executing_checker_bindings()
        with patch.object(original, '__defaults__', ('unreviewed',)):
            with self.assertRaisesRegex(ValueError, 'defaults changed'):
                cleanup.executing_checker_bindings()
        with patch.object(deviation, '_EXECUTED_MODULE_CODE', compile('pass', deviation.__file__, 'exec')):
            with self.assertRaisesRegex(ValueError, 'module-code witness changed'):
                cleanup.executing_checker_bindings()


class DeviationIntegrationControls(unittest.TestCase):
    def setUp(self):
        self.root = fixtures.copy_historical_boundary_root(self, ROOT)
        self.current = (self.root/deviation.MODULE).read_bytes()
        self.before = deviation.predecessor_source(self.current.decode()).encode()

    @contextmanager
    def map_state(self, raw):
        path = self.root/deviation.MODULE
        old = path.read_bytes(); path.write_bytes(raw)
        try: yield
        finally: path.write_bytes(old)

    def test_seventh_and_sixth_edges_retain_exact_historical_chain_and_receipts(self):
        current = seed.verify(self.root)
        self.assertEqual(len(current['edges']), 7)
        self.assertEqual(current['edges'][-1], deviation.edge())
        self.assertEqual(current['edges'][-2], station.edge())
        self.assertEqual(current['after_sha256'], deviation.AFTER_SHA256)
        self.assertEqual(current['after_token_sha256'], deviation.AFTER_TOKEN_SHA256)
        with self.map_state(self.before):
            sixth = seed.verify(self.root)
            self.assertEqual(len(sixth['edges']), 6)
            self.assertEqual(current['edges'][:-1], sixth['edges'])
            bound = cleanup.proof_bindings(self.root)
            self.assertEqual(bound[deviation.MODULE], station.AFTER_SHA256)
            self.assertNotIn(LEAF, cleanup.station_proof_bindings(self.root))
        bound = cleanup.proof_bindings(self.root)
        self.assertEqual(bound[deviation.MODULE], deviation.AFTER_SHA256)
        for leaf in (LEAF, STATION_LEAF):
            self.assertEqual(bound[leaf], hashlib.sha256((self.root/leaf).read_bytes()).hexdigest())
        for path, digest in {**deviation.TESTS, **station.TESTS}.items():
            self.assertEqual(bound[path], digest)
        record = cleanup.read_record(self.root)
        for group in ('unchanged_inputs', 'native_dependency_inputs'):
            self.assertEqual(record[group][deviation.MODULE], station.BEFORE_SHA256)
        self.assertEqual((self.root/deviation.MODULE).read_bytes(), self.current)

    def test_mutated_or_forged_map_endpoints_reject(self):
        skip = b'if _indexed_curve_lower(key, segment.deviation) > best_radius:'
        variants = (self.current + b'\n# forged\n',
                    self.current.replace(skip, skip.replace(b'>', b'>='), 1),
                    self.current.replace(b'                certificate[0],\n            )\n', b'                0.0,\n            )\n', 1))
        for raw in variants:
            with self.subTest(digest=hashlib.sha256(raw).hexdigest()), self.map_state(raw):
                with self.assertRaises(ValueError): cleanup.verify(self.root)
                with self.assertRaises(ValueError): seed.verify(self.root)

    def test_station_census_keeps_three_helper_uses_on_the_new_endpoint(self):
        seed.verify_score_caller_inventory(self.root, station_edge=True)
        with self.assertRaisesRegex(ValueError, 'endpoint differs'):
            seed.verify_score_caller_inventory(self.root, station_edge=False)

    def test_supplied_old_tokens_cannot_use_new_physical_endpoint(self):
        import cache_key_contracts as cache
        import lane_order_contracts as order
        read = Path.read_text; target = self.root/deviation.MODULE
        skip = 'if _indexed_curve_lower(key, segment.deviation) > best_radius:'
        for consumer in (cache, order):
            for supplied in (self.before.decode(), self.current.decode().replace(skip, skip.replace('>', '>='), 1)):
                with self.subTest(consumer=consumer.__name__), patch.object(Path, 'read_text',
                        lambda path,*a,**k: supplied if path == target else read(path,*a,**k)):
                    with self.assertRaisesRegex(RuntimeError if consumer is order else ValueError, 'supplied score-helper'):
                        consumer.inventory(self.root)
            with patch.object(Path, 'read_text', lambda path,*a,**k:
                    self.current.decode()+'\n# supplied comment\n' if path == target else read(path,*a,**k)):
                consumer.inventory(self.root)

    def test_every_new_test_and_leaf_read_is_pinned_and_unreadable_fails(self):
        for name in (*deviation.TESTS, LEAF):
            path = self.root/name; original = path.read_bytes()
            with self.subTest(path=name):
                path.write_bytes(original+b'\n# unreviewed fixture\n')
                try:
                    with self.assertRaises(ValueError): cleanup.verify(self.root)
                    if name in deviation.TESTS:
                        current_typed = cleanup.typed_boundary.is_current(name, original.decode('utf-8'))
                        reason = (('reviewed typed boundary successor: unknown complete typed endpoint: '
                                   if current_typed else
                                   'reviewed seed-count successor: deviation correctness fixture changed: ')
                                  + name)
                        with self.assertRaises(cleanup._OperationCoherenceError) as caught:
                            seed.verify(self.root)
                        self.assertIs(type(caught.exception), cleanup._OperationCoherenceError)
                        self.assertEqual(str(caught.exception), reason)
                        self.assertIs(type(caught.exception.__cause__), ValueError)
                        self.assertEqual(str(caught.exception.__cause__), reason)
                finally: path.write_bytes(original)
                read = Path.read_bytes
                def denied(actual, *args, **kwargs):
                    if actual == path: raise OSError('deviation input read denied')
                    return read(actual, *args, **kwargs)
                with patch.object(Path, 'read_bytes', denied), self.assertRaises(ValueError):
                    cleanup.verify(self.root)

    def test_loop_proofs_map_every_row_and_bind_the_new_leaf(self):
        loops = _loops(self)
        proofs = loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')
        self.assertEqual(sorted(proofs), sorted([*loops._MAP_DEVIATION_SUCCESSOR_LINES.values(), 4106]))
        for line, proof in proofs.items():
            self.assertEqual(proof['required'], 'T')
            self.assertEqual(proof['dependency_sha256'][deviation.MODULE], deviation.AFTER_SHA256)
            self.assertIn(LEAF, proof['dependency_sha256'])
            for path in deviation.TESTS:
                self.assertIn(path, proof['dependency_sha256'])
        with self.map_state(self.before):
            earlier = loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')
            self.assertEqual(sorted(earlier), sorted([*loops._MAP_STATION_SUCCESSOR_LINES.values(), 4099]))
        with self.map_state(self.current + b'\n# forged\n'):
            self.assertEqual(loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map'), {})


class DeviationCurrentIntegrationControls(DeviationIntegrationControls):
    """Retain the same physical attack matrix on the complete typed graph."""

    def setUp(self):
        self.root = fixtures.copy_current_root(self, ROOT)
        self.current = (self.root/deviation.MODULE).read_bytes()
        self.historical = cleanup.typed_boundary.historical_source(
            deviation.MODULE, self.current.decode())
        self.before = deviation.predecessor_source(self.historical).encode()

    def test_seventh_and_sixth_edges_retain_exact_historical_chain_and_receipts(self):
        edge = cleanup.typed_boundary.edge(deviation.MODULE)
        self.assertEqual(edge['before_sha256'], deviation.AFTER_SHA256)
        self.assertEqual(edge['after_sha256'], cleanup.sha(self.current))
        current = seed.verify(self.root)
        self.assertEqual(len(current['edges']), 7)
        self.assertEqual(current['edges'][-2:], [station.edge(), deviation.edge()])
        bound = cleanup.proof_bindings(self.root)
        self.assertEqual(bound[deviation.MODULE], cleanup.sha(self.current))
        for name in (*deviation.TESTS, *station.TESTS, LEAF, STATION_LEAF):
            self.assertEqual(bound[name], cleanup.sha((self.root/name).read_bytes()))
        record = cleanup.read_record(self.root)
        for group in ('unchanged_inputs', 'native_dependency_inputs'):
            self.assertEqual(record[group][deviation.MODULE], station.BEFORE_SHA256)
        with self.map_state(self.before):
            with self.assertRaises(ValueError): cleanup.verify(self.root)
        self.assertEqual((self.root/deviation.MODULE).read_bytes(), self.current)

    def test_loop_proofs_map_every_row_and_bind_the_new_leaf(self):
        import difflib
        loops = _loops(self)
        proofs = loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')
        # Derive physical coordinates independently from the sealed old/new
        # full sources, not from the production mapper. Current loop headers
        # carry this exact coverage annotation; executable text stays bound.
        old, new = self.historical.splitlines(), self.current.decode().splitlines()
        annotated = [line.removesuffix('  # pragma: no branch') for line in new]
        mapping = {}
        for block in difflib.SequenceMatcher(None, old, annotated, autojunk=False).get_matching_blocks():
            mapping.update({block.a + offset + 1: block.b + offset + 1
                            for offset in range(block.size)})
        historical_lines = [*loops._MAP_DEVIATION_SUCCESSOR_LINES.values(), 4106]
        expected = {mapping[line] for line in historical_lines}
        self.assertEqual(len(expected), len(historical_lines))
        for line in historical_lines:
            self.assertEqual(annotated[mapping[line] - 1], old[line - 1])
        self.assertEqual(set(proofs), expected)
        for line, proof in proofs.items():
            self.assertTrue(new[line - 1].lstrip().startswith('for '))
            self.assertEqual(proof['required'], 'T')
            self.assertEqual(proof['dependency_sha256'][deviation.MODULE], cleanup.sha(self.current))
            for name in (*deviation.TESTS, LEAF, STATION_LEAF):
                self.assertEqual(proof['dependency_sha256'][name],
                                 cleanup.sha((self.root/name).read_bytes()))
        for raw in (self.before, self.current + b'\n# forged\n'):
            with self.map_state(raw):
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map'), {})


if __name__ == '__main__':
    unittest.main()
