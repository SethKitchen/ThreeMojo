#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free fail-closed controls, discovered by make test-tools."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
try:
    from carla_lane_oracle import _full_audit_test_fixtures as cleanup_fixtures
except ModuleNotFoundError:
    from tools.carla_lane_oracle import _full_audit_test_fixtures as cleanup_fixtures

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT/'tools/carla_lane_oracle/check_sampled_values.py'
from tools.carla_lane_oracle import check_sampled_values as m


class SampledValueCorrespondenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        owner = type('HistoricalClassFixture', (), {
            'addCleanup': staticmethod(cls.addClassCleanup)})()
        cls.historical_root = cleanup_fixtures.copy_historical_boundary_root(owner, ROOT)
        cls.cleanup_sources = cleanup_fixtures.verified_predecessors(cls.historical_root)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=Path(tempfile.gettempdir()).resolve())
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        pin = self.root/'tools/carla_lane_oracle/runtime-source-pins.json'
        pin.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(self.historical_root/'tools/carla_lane_oracle/runtime-source-pins.json', pin)
        moment_pin = self.root/'tools/carla_lane_oracle/spiral-moment-pins.json'
        shutil.copyfile(self.historical_root/'tools/carla_lane_oracle/spiral-moment-pins.json', moment_pin)
        guard_pin = self.root/'tools/carla_lane_oracle/sum2-guard-pins.json'
        shutil.copyfile(self.historical_root/'tools/carla_lane_oracle/sum2-guard-pins.json', guard_pin)
        migration = 'tools/carla_lane_oracle/winner-sign-query-migration.json'
        shutil.copyfile(self.historical_root/migration, self.root/migration)
        from tools.carla_lane_oracle.source_contracts import GROUP_PATHS
        from tools.carla_lane_oracle import seed_count_contracts as seed_count
        from tools.carla_lane_oracle.reviewed_cleanup_contracts import PROTECTED_INPUTS
        paths = set(GROUP_PATHS['canonical_accumulation']) | set(PROTECTED_INPUTS)
        paths.update(json.loads(guard_pin.read_text())['protected_inventory'])
        paths.update(GROUP_PATHS['optional_runtime'])
        paths.update('extensions/carla/' + name for name in
                     ('curve_trig.mojo', 'geometry.mojo', 'lane_value_bounds.mojo'))
        for name in paths:
            target = self.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            if name == seed_count.MODULE:
                # Isolated graph mutations use the verified historical fixture;
                # the live successor binds these dependencies byte-for-byte.
                target.write_bytes(seed_count.historical_source(self.historical_root).encode('utf-8'))
            else:
                shutil.copyfile(self.historical_root/name, target)

        cleanup_fixtures.write_predecessors(self.root, self.cleanup_sources)

    def change(self, name, before, after):
        path = self.root/'extensions/carla'/name
        text = path.read_text()
        self.assertIn(before, text)
        path.write_text(text.replace(before, after, 1))

    def rejected(self):
        with self.assertRaises((m.CheckError, SyntaxError)):
            m.verify(self.root)
        result = subprocess.run([sys.executable, '-O', '-B', str(SCRIPT),
                                 '--repo-root', str(self.root)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'FAIL:', result.stdout)

    def test_current_exact_correspondence(self):
        result = m.verify(self.root)
        self.assertEqual(result['copied_functions'], 8)
        self.assertEqual(result['dispatch_functions'], 6)

    def live_successor_fixture(self):
        # The fixed pre-#333 Map successor remains a historical claim.
        # Current typed source is exercised by the complete-root test below.
        from tools.carla_lane_oracle import seed_count_contracts as seed_count
        record = seed_count.read_record(self.historical_root)
        paths = {seed_count.MODULE, seed_count.MIGRATION}
        for group in ('unchanged_inputs', 'historical_records',
                      'unchanged_correctness_tests', 'after_correctness_tests'):
            paths.update(record[group])
        physical = (self.historical_root/seed_count.MODULE).read_bytes().decode('utf-8')
        score_tests = ()
        if seed_count.sha(physical) in {seed_count.SCORE_AFTER_SHA256, seed_count.station.AFTER_SHA256, seed_count.deviation.AFTER_SHA256}:
            # Only the fully verified physical score endpoint can add its
            # separate numerical fixture. Historical mutation setup stays fixed.
            seed_count.verify_score(self.historical_root)
            self.assertEqual((self.historical_root/seed_count.MODULE).read_bytes().decode('utf-8'), physical)
            score_tests = tuple(seed_count.SCORE_TESTS)
            paths.update(score_tests)
            if seed_count.sha(physical) in {seed_count.station.AFTER_SHA256, seed_count.deviation.AFTER_SHA256}:
                paths.update(seed_count.station.TESTS)
            if seed_count.sha(physical) == seed_count.deviation.AFTER_SHA256:
                paths.update(seed_count.deviation.TESTS)
        for name in paths:
            target = self.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self.historical_root/name, target)
        # This Map-successor control keeps its exact historical dependencies.
        # Complete current-cleanup admission has a separate test below.
        cleanup_fixtures.write_predecessors(self.root, self.cleanup_sources)
        cleanup_fixtures.copy_shared_helper_inputs(self.root, self.historical_root)
        for name, raw in self.cleanup_sources.items():
            self.assertEqual((self.root/name).read_bytes(), raw)
        self.assertEqual((self.root/seed_count.MODULE).read_bytes().decode('utf-8'), physical)
        return score_tests

    def test_live_source_correspondence_and_missing_successor_dependency(self):
        score_tests = self.live_successor_fixture()
        result = m.verify(self.root)
        self.assertEqual(result['copied_functions'], 8)
        self.assertEqual(result['dispatch_functions'], 6)
        self.test_optimized_python_keeps_checks()
        # This source belongs to the real Map import closure, not to the
        # partial historical graph fixture. Its absence must revoke admission.
        for name in ('tools/carla_lane_oracle/seed-count-successor.json',
                     'extensions/carla/map_search.mojo', *score_tests):
            with self.subTest(missing=name):
                path = self.root/name
                original = path.read_bytes()
                path.unlink()
                try:
                    with self.assertRaisesRegex(m.CheckError, 'canonical_accumulation'):
                        m.verify(self.root)
                    self.rejected()
                finally:
                    path.write_bytes(original)

        for name in score_tests:
            with self.subTest(changed=name):
                path = self.root/name
                original = path.read_bytes()
                path.write_bytes(original + b'\n# Changed numerical fixture.\n')
                try:
                    with self.assertRaisesRegex(m.CheckError, 'canonical_accumulation'):
                        m.verify(self.root)
                    self.rejected()
                finally:
                    path.write_bytes(original)

    def test_complete_current_cleanup_correspondence_and_revocation(self):
        cleanup = cleanup_fixtures.cleanup
        root = cleanup_fixtures.copy_current_root(self, ROOT)
        self.assertEqual(m.verify(root)['copied_functions'], 8)
        self.assertEqual(m.verify(root)['dispatch_functions'], 6)
        for mode in ([], ['-O']):
            result = subprocess.run([sys.executable, *mode, '-B', str(SCRIPT),
                                     '--repo-root', str(root)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for name in (cleanup.MIGRATION, 'extensions/carla/map_search.mojo',
                     *cleanup.SOURCE_PATHS):
            path = root/name
            original = path.read_bytes()
            with self.subTest(missing_current_input=name):
                try:
                    path.unlink()
                    with self.assertRaises((m.CheckError, OSError, ValueError)):
                        m.verify(root)
                finally:
                    path.write_bytes(original)
                self.assertEqual(m.verify(root)['copied_functions'], 8)

    def test_optimized_python_keeps_checks(self):
        result = subprocess.run([sys.executable, '-O', '-B', str(SCRIPT),
                                 '--repo-root', str(self.root)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(b'"status": "PASS"', result.stdout)

    def test_comments_and_redundant_grouping_preserve_correspondence(self):
        self.change('lane_value_bounds.mojo', 'var magnitude = value',
                    '# Documentation only.\n    var magnitude = (\n        value\n    )')
        m.verify(self.root)

    def test_changed_value_arithmetic_rejected(self):
        self.change('lane_value_bounds.mojo',
                    'var result = magnitude * _expression_polynomial(',
                    'var result = magnitude + _expression_polynomial(')
        self.rejected()

    def test_stale_copy_after_full_jet_change_rejected(self):
        self.change('curve_trig.mojo',
                    'var result = magnitude * _jet_polynomial(',
                    'var result = magnitude + _jet_polynomial(')
        self.rejected()

    def test_nonfinite_guard_change_rejected(self):
        self.change('lane_value_bounds.mojo', 'if not domain.is_finite():',
                    'if domain.is_finite():')
        self.rejected()

    def test_signed_zero_guard_change_rejected(self):
        self.change('lane_value_bounds.mojo', 'and not _sign_bit(one.tv)',
                    'and _sign_bit(one.tv)')
        self.rejected()

    def test_derivative_read_rejected(self):
        self.change('lane_value_bounds.mojo', 'var magnitude = value',
                    'var leaked = value.first\n    var magnitude = value')
        self.rejected()

    def test_type_and_primitive_changes_require_renewed_review(self):
        self.change('curve_interval.mojo', 'var error: Float64',
                    'var error: Float32')
        self.rejected()

    def test_derivative_free_alias_change_rejected(self):
        self.change('curve_interval.mojo',
                    'comptime _ValueJet = _JetExpression[False]',
                    'comptime _ValueJet = _JetExpression[True]')
        self.rejected()

    def test_missing_or_extra_helper_rejected(self):
        self.change('lane_value_bounds.mojo', 'def _sample_value(',
                    'def _sample_value_changed(')
        self.rejected()

    def test_wrong_shared_import_rejected(self):
        self.change('lane_value_bounds.mojo',
                    '    _ValueJet,',
                    '    _Jet as _ValueJet,')
        self.rejected()


    def test_commented_alias_cannot_spoof_actual_declaration(self):
        self.change('curve_interval.mojo',
                    'comptime _ValueJet = _JetExpression[False]',
                    '# comptime _ValueJet = _JetExpression[False]\ncomptime _ValueJet = _JetExpression[True]')
        self.rejected()

    def test_duplicate_actual_alias_rejected(self):
        self.change('curve_interval.mojo',
                    'comptime _ValueJet = _JetExpression[False]',
                    'comptime _ValueJet = _JetExpression[False]\ncomptime _ValueJet = _JetExpression[False]')
        self.rejected()

    def test_shared_generic_derivative_read_rejected(self):
        self.change('curve_trig.mojo',
                    'comptime Expression = _JetExpression[derivatives]\n    var domain = value.rounded_value()',
                    'comptime Expression = _JetExpression[derivatives]\n    var domain = value.first')
        self.rejected()

    def test_full_jet_bridge_change_rejected(self):
        self.change('curve_trig.mojo',
                    'return _expression_polynomial(coefficients, x)',
                    'return _expression_polynomial(coefficients, x + x)')
        self.rejected()

    def test_target_decorator_not_dropped_by_function_slice(self):
        self.change('lane_value_bounds.mojo',
                    'def _uncertain_value(', '@no_inline\ndef _uncertain_value(')
        self.rejected()

    def test_copied_source_decorator_change_rejected(self):
        self.change('curve_trig.mojo',
                    'def _atan_branch(', '@no_inline\ndef _atan_branch(')
        self.rejected()

    def test_full_reference_dispatch_change_rejected(self):
        path = self.root/'extensions/carla/curve_bounds.mojo'
        text = path.read_text()
        start = text.index('def _reference_jet_capture[')
        before = text[start:]
        self.assertIn('if geometry.kind == LINE:', before)
        after = before.replace('if geometry.kind == LINE:',
                               'if geometry.kind == PARAM_POLY3:', 1)
        path.write_text(text[:start] + after)
        self.rejected()

    def test_full_lane_dispatch_change_rejected(self):
        path = self.root/'extensions/carla/curve_bounds.mojo'
        text = path.read_text()
        start = text.index('def _lane_jet_model_proof[')
        before = text[start:]
        self.assertIn('if record.geometry.kind == ARC:', before)
        after = before.replace('if record.geometry.kind == ARC:',
                               'if record.geometry.kind == PARAM_POLY3:', 1)
        path.write_text(text[:start] + after)
        self.rejected()


    def test_union_setup_before_return_is_bound(self):
        path = self.root/'extensions/carla/curve_bounds.mojo'
        text = path.read_text()
        start = text.index('def _union_points[')
        end = text.index('def _arc_offset_jet(', start)
        region = text[start:end]
        self.assertIn('    return (', region)
        region = region.replace('    one: Tuple[', '    var one: Tuple[', 1)
        region = region.replace('    return (', '    one = two\n    return (', 1)
        path.write_text(text[:start] + region + text[end:])
        self.rejected()

    def test_reference_scalar_alias_routing_is_bound(self):
        self.change('curve_bounds.mojo', '    _curve_cos,',
                    '    _curve_sin as _curve_cos,')
        self.rejected()

    def test_primitive_import_routing_is_bound(self):
        path = self.root/'extensions/carla/curve_interval.mojo'
        text = path.read_text()
        self.assertIn('from std.math import ', text)
        text = text.replace('from std.math import ', 'from unrelated.math import ', 1)
        path.write_text(text)
        self.rejected()


    def test_type_flag_query_is_forbidden(self):
        self.change('lane_value_bounds.mojo', '    var magnitude = value',
                    '    comptime if _ValueJet.derivatives:\n        var forbidden = 0.0\n    var magnitude = value')
        with self.assertRaisesRegex(m.CheckError, 'derivative-field/flag'):
            m.verify(self.root)
        self.rejected()

    def test_matched_derivative_sensitive_edits_still_require_review(self):
        self.change('curve_trig.mojo', '    var magnitude = value',
                    '    var magnitude = value\n    comptime if _Jet.derivatives:\n        magnitude = _Jet.constant(0.0)')
        self.change('lane_value_bounds.mojo', '    var magnitude = value',
                    '    var magnitude = value\n    comptime if _ValueJet.derivatives:\n        magnitude = _ValueJet.constant(0.0)')
        self.rejected()


class SampledLoaderBoundaryTests(unittest.TestCase):
    def test_unregistered_alias_stays_unowned_before_first_observation(self):
        # The actual-current fixture above uses the canonical owner. Keep the
        # old unregistered loader boundary explicit in its own fresh process.
        # This deliberately stops before verification; it is not a PASS claim
        # for the expensive unowned sampled correspondence calculation.
        command = r'''import importlib.util, pathlib, sys, tempfile
root = pathlib.Path(sys.argv[1]).resolve()
sys.path[:0] = [str(root / 'tools'), str(root)]
name = 'carla_lane_oracle.carla_sampled_value_checker'
if name in sys.modules:
    raise RuntimeError('alias was registered before loading')
spec = importlib.util.spec_from_file_location(
    name, root / 'tools/carla_lane_oracle/check_sampled_values.py')
alias = importlib.util.module_from_spec(spec)
spec.loader.exec_module(alias)
class IntentionalObservationStop(BaseException):
    pass
observations = []
class FirstObservation:
    def historical_text(self, *args, **kwargs):
        raise RuntimeError('observation sentinel was bypassed')
    def _observe_text(self, *args, **kwargs):
        operation = kwargs.get('_operation', 'missing')
        if operation is not None:
            raise RuntimeError('unregistered alias received an operation owner')
        observations.append(operation)
        raise IntentionalObservationStop()
original = alias._typed_source
with tempfile.TemporaryDirectory() as directory:
    fixture = pathlib.Path(directory)
    path = fixture / 'extensions/carla/curve_bounds.mojo'
    path.parent.mkdir(parents=True)
    path.write_text('# First observation only; never an admitted source root.\n')
    alias._typed_source = FirstObservation()
    try:
        try:
            alias.verify(fixture)
        except IntentionalObservationStop:
            pass
        else:
            raise RuntimeError('alias did not reach the intentional stop')
    finally:
        alias._typed_source = original
if observations != [None] or name in sys.modules:
    raise RuntimeError('alias observation or registration changed')
print('PASS: alias unowned; intentionally stopped before verification')
'''
        result = subprocess.run([sys.executable, '-B', '-c', command, str(ROOT)],
                                cwd=ROOT, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout,
                         'PASS: alias unowned; intentionally stopped before verification\n')
        self.assertEqual(result.stderr, '')


class RestoredSyntaxCacheTests(unittest.TestCase):
    def tearDown(self):
        m._RESTORED_SYNTAX.clear()

    def test_the_shared_bridge_reuses_the_restored_syntax(self):
        prepared = ('def ok():\n    return 1\n', [], {'def_word': 'def'})
        m._RESTORED_SYNTAX[('source', 'replacement')] = ('historical', prepared)
        restored, syntax = m._restored_then_syntax('source', 'replacement')
        self.assertEqual(restored, 'historical')
        self.assertEqual(syntax, prepared)


class AliasGraphTests(unittest.TestCase):
    def test_a_missing_alias_fails_before_the_graph_digest(self):
        message = (
            'Jet primitive graph changed; renewed'
            ' derivative-independence review required'
        )
        with self.assertRaises(m.CheckError) as caught:
            m._aliases_then_graph(
                'def f():\n    return 1\n', 'graph', '0' * 64, message)
        self.assertIn(
            'missing or ambiguous actual alias: _Jet', str(caught.exception))
        self.assertNotIn('Jet primitive graph changed', str(caught.exception))


class SharedGraphTests(unittest.TestCase):
    def test_an_earlier_graph_mismatch_precedes_a_missing_function(self):
        tree = m.syntax_tree('def ok():\n    return 1\n')
        label = 'shared generic or full-Jet bridge changed: '
        with self.assertRaises(m.CheckError) as caught:
            m._shared_reference_graphs(
                {'trig': tree},
                {'trig:ok': '0' * 64, 'trig:missing': '1' * 64},
                label,
                'def f():\n    return x.first\n',
            )
        self.assertIn('trig:ok', str(caught.exception))
        self.assertNotIn('missing or ambiguous function', str(caught.exception))


class PlainReferenceGraphTests(unittest.TestCase):
    def test_a_graph_mismatch_precedes_a_later_syntax_error(self):
        label = 'reference module changed; renewed review required: '
        with self.assertRaises(m.CheckError) as caught:
            m._plain_reference_graphs([
                ('curve_trig.mojo', 'def ok():\n    return 1\n', '0' * 64),
                ('curve_interval.mojo',
                 'def f[T: Int]():\n    return 1\ndef f[T: Int]():\n    return 2\n',
                 '1' * 64),
            ], label)
        self.assertIn('reference module changed', str(caught.exception))
        self.assertNotIn('ambiguous generic', str(caught.exception))

    def test_the_reviewed_module_stays_ahead_of_the_plain_modules(self):
        seen = []

        def review(filename, expected):
            seen.append(filename)
            self.assertEqual(expected, 'keep')
            return 'graph'

        texts = {'curve_trig.mojo': 'def ok():\n    return 1\n'}
        label = 'reference module changed; renewed review required: '
        with self.assertRaises(m.CheckError) as caught:
            m._reviewed_reference_graphs([
                ('curve_bounds.mojo', 'keep'),
                ('curve_trig.mojo', '0' * 64),
            ], texts, 'curve_bounds.mojo', label, review)
        self.assertEqual(seen, ['curve_bounds.mojo'])
        self.assertIn('curve_bounds.mojo', str(caught.exception))
        self.assertNotIn('curve_trig.mojo', str(caught.exception))

    def test_a_matching_reviewed_graph_reaches_the_plain_module(self):
        import hashlib
        graph = 'graph'
        digest = hashlib.sha256(graph.encode()).hexdigest()
        label = 'reference module changed; renewed review required: '

        def review(filename, expected):
            self.assertEqual(filename, 'curve_bounds.mojo')
            self.assertEqual(expected, digest)
            return graph

        rows = m._reviewed_reference_graphs([
            ('curve_bounds.mojo', digest),
            ('curve_trig.mojo', '0' * 64),
        ], {'curve_trig.mojo': 'def ok():\n    return 1\n'},
            'curve_bounds.mojo', label, review)
        self.assertEqual(len(rows), 1)
        with self.assertRaises(m.CheckError) as caught:
            m._graph_digest_rows(rows)
        self.assertIn('curve_trig.mojo', str(caught.exception))
        self.assertNotIn('curve_bounds.mojo', str(caught.exception))


class CurrentDispatchTokenTests(unittest.TestCase):
    def test_current_sources_skip_the_second_token_list(self):
        from tools.carla_lane_oracle import curve_support_dispatch_contracts as dispatch
        calls = []
        original = dispatch._gate_tokens
        dispatch._gate_tokens = lambda pairs: calls.append(pairs)
        try:
            dispatch._complete_tokens(
                [('a.mojo', {'after_token_sha256': 'aa'})], ['text'], True)
        finally:
            dispatch._gate_tokens = original
        self.assertEqual(calls, [])

    def test_restored_edges_are_checked_together(self):
        from tools.carla_lane_oracle import curve_support_dispatch_contracts as dispatch
        from tools.carla_lane_oracle import raw_cut_inverse_contracts as raw
        calls = []
        original_choices = dispatch._labeled_choices
        original_verify = raw.verify
        original_edges = dispatch._gate_edges
        dispatch._REVIEWED_CURRENT.clear()

        def choices(items, tokens=False):
            return {
                'labels': {
                    'current': 'current', 'restore': 'restore',
                    'unreviewed': 'unreviewed ',
                },
                'choices': ['restore', 'unreviewed'],
                'tokens': False,
            }

        def verify(root, **kwargs):
            return {'before_token_sha256': 'aa', 'before_source': 'old'}

        def edges(recorded, expected):
            calls.append((recorded, list(expected)))

        dispatch._labeled_choices = choices
        raw.verify = verify
        dispatch._gate_edges = edges
        root = Path('dispatch-restored-edges')
        try:
            root.mkdir(parents=True)
            (root / 'one.txt').write_text('live-one')
            (root / 'two.txt').write_text('live-two')
            with self.assertRaises(ValueError) as caught:
                dispatch.reviewed_sources(
                    root, [('one.txt', 'aa'), ('two.txt', 'bb')])
            self.assertIn('unreviewed ', str(caught.exception))
            self.assertEqual(calls, [('aa', ['aa'])])
        finally:
            dispatch._labeled_choices = original_choices
            raw.verify = original_verify
            dispatch._gate_edges = original_edges
            dispatch._REVIEWED_CURRENT.clear()
            shutil.rmtree(root, ignore_errors=True)

    def test_a_repeated_current_source_skips_the_second_choice(self):
        from tools.carla_lane_oracle import curve_support_dispatch_contracts as dispatch
        calls = []
        original = dispatch._labeled_choices
        dispatch._REVIEWED_CURRENT.clear()

        def choices(items, tokens=False):
            calls.append(tokens)
            return {
                'labels': {
                    'current': 'current', 'restore': 'restore',
                    'unreviewed': 'unreviewed ',
                },
                'choices': ['current'] * len(items),
                'tokens': True,
            }

        dispatch._labeled_choices = choices
        root = Path(self.id().replace('.', '-'))
        try:
            root.mkdir(parents=True)
            source = root / 'fixture.txt'
            source.write_text('def f():\n    return 1\n')
            first, done = dispatch.reviewed_sources(
                root, [('fixture.txt', 'aa')], check_tokens=True)
            second = dispatch.reviewed_sources(root, [('fixture.txt', 'aa')])
            self.assertTrue(done)
            self.assertEqual(second, first)
            self.assertEqual(calls, [True])
            source.write_text('def f():\n    return 2\n')
            third = dispatch.reviewed_sources(root, [('fixture.txt', 'aa')])
            self.assertEqual(third, ['def f():\n    return 2\n'])
            self.assertEqual(calls, [True, False])
        finally:
            dispatch._labeled_choices = original
            dispatch._REVIEWED_CURRENT.clear()
            shutil.rmtree(root, ignore_errors=True)

    def test_a_restore_still_checks_the_token_list(self):
        from tools.carla_lane_oracle import curve_support_dispatch_contracts as dispatch
        calls = []
        original_gate = dispatch._gate_tokens
        original_labels = dispatch._dispatch_labels
        dispatch._gate_tokens = lambda pairs: calls.append(pairs)
        dispatch._dispatch_labels = lambda: {'complete': 'complete '}
        try:
            dispatch._complete_tokens(
                [('a.mojo', {'after_token_sha256': 'aa'})], ['text'], False)
        finally:
            dispatch._gate_tokens = original_gate
            dispatch._dispatch_labels = original_labels
        self.assertEqual(calls, [[('text', 'aa', 'complete a.mojo')]])


class RecordGateCacheTests(unittest.TestCase):
    def test_repeated_records_skip_the_second_gate(self):
        from tools.carla_lane_oracle import curve_support_dispatch_contracts as dispatch
        from tools.carla_lane_oracle import frozen_arc_producer_contracts as frozen
        from tools.carla_lane_oracle import reviewed_cleanup_contracts as cleanup
        from tools.carla_lane_oracle import rounded_line_singleton_contracts as singleton
        cases = (
            (
                dispatch, '_GATED_DISPATCH',
                'tools/carla_lane_oracle/curve-support-dispatch-migration.json',
                None,
            ),
            (
                singleton, '_GATED_SINGLETON',
                'tools/carla_lane_oracle/rounded-line-singleton-migration.json',
                None,
            ),
            (
                frozen, '_FROZEN_RECORD',
                'tools/carla_lane_oracle/frozen-arc-producer-migration.json',
                {'reviewed_cleanup':
                 'tools/carla_lane_oracle/reviewed-cleanup-migration.json'},
            ),
            (
                cleanup, '_CLEANUP_RECORD',
                'tools/carla_lane_oracle/reviewed-cleanup-migration.json',
                {'winner_sign':
                 'tools/carla_lane_oracle/winner-sign-query-migration.json'},
            ),
        )
        for module, cache_name, migration, path_record in cases:
            with self.subTest(module=module.__name__):
                calls = []
                path_calls = []
                original_gate = module._gate
                original_cache = getattr(module, cache_name)
                original_migration = getattr(module, 'MIGRATION', None)
                original_paths = getattr(module, '_paths_after_record', None)

                def gate(*args, _calls=calls):
                    _calls.append(args)

                def count_paths(payload, _record=path_record, _calls=path_calls):
                    _calls.append(payload)
                    return dict(_record)

                module._gate = gate
                module.MIGRATION = migration
                setattr(module, cache_name, None)
                if path_record is not None:
                    module._paths_after_record = count_paths
                try:
                    first = module.read_record(ROOT)
                    second = module.read_record(ROOT)
                    self.assertEqual(first['schema'], second['schema'])
                    self.assertEqual(len(calls), 1)
                    if path_record is not None:
                        self.assertEqual(len(path_calls), 1)
                    setattr(module, cache_name, None)
                    module.read_record(ROOT)
                    self.assertEqual(len(calls), 2)
                finally:
                    module._gate = original_gate
                    module.MIGRATION = original_migration
                    setattr(module, cache_name, original_cache)
                    if path_record is not None:
                        module._paths_after_record = original_paths


class RoundedMatchCacheTests(unittest.TestCase):
    def test_a_repeated_rounded_match_is_reused(self):
        from tools.carla_lane_oracle import rounded_line_singleton_contracts as singleton
        calls = []
        original_matches = singleton._significant_matches
        original_rounded = singleton._ROUNDED
        singleton._MATCHED_PAIRS.clear()
        singleton._ROUNDED = {'notes/fake.mojo'}

        def matches(pairs):
            calls.append([(actual, source) for actual, source in pairs])
            flags = [True] * len(pairs)
            for (actual, source), flag in zip(pairs, flags):
                if flag:
                    singleton._MATCHED_PAIRS[(actual, source)] = True
            return flags

        singleton._significant_matches = matches
        root = Path('rounded-match-cache')
        path = 'notes/fake.mojo'
        record = {'modules': {path: {'source': 'recorded'}}}
        try:
            (root / 'notes').mkdir(parents=True)
            target = root / path
            target.write_text('live')
            first = singleton._reviewed_text(root, path, record)
            second = singleton._reviewed_text(root, path, record)
            self.assertEqual(first, 'live')
            self.assertEqual(second, 'live')
            self.assertEqual(len(calls), 1)
            target.write_text('changed')
            third = singleton._reviewed_text(root, path, record)
            self.assertEqual(third, 'changed')
            self.assertEqual(len(calls), 2)
        finally:
            singleton._significant_matches = original_matches
            singleton._ROUNDED = original_rounded
            singleton._MATCHED_PAIRS.clear()
            shutil.rmtree(root, ignore_errors=True)


class PinPairCacheTests(unittest.TestCase):
    def test_a_repeated_pin_pair_skips_the_second_gate(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import coverage_invariant_contracts as invariant
        original = invariant._GATED_PAIR
        names = {
            'runtime-source-pins.json': {},
            'sum2-guard-pins.json': {},
        }
        same = ['runtime-source-pins.json', 'sum2-guard-pins.json']
        other = ('other.json',)
        try:
            invariant._GATED_PAIR = None
            ok = Mock(returncode=0, stdout='', stderr='')
            with patch('subprocess.run', return_value=ok) as run:
                invariant._gate_pair(names)
                invariant._gate_pair(same)
                self.assertEqual(run.call_count, 1)
                invariant._gate_pair(other)
                self.assertEqual(run.call_count, 2)
            self.assertEqual(invariant._GATED_PAIR, other)
            failed = Mock(
                returncode=1, stdout='', stderr='wrong fixed ordered pin pair\n')
            with patch('subprocess.run', return_value=failed) as run:
                with self.assertRaisesRegex(ValueError, 'wrong fixed ordered pin pair'):
                    invariant._gate_pair(names)
                self.assertEqual(run.call_count, 1)
            self.assertEqual(invariant._GATED_PAIR, other)
            with patch('subprocess.run', return_value=ok) as run:
                invariant._gate_pair(other)
                self.assertEqual(run.call_count, 0)
        finally:
            invariant._GATED_PAIR = original


class ComponentPairTests(unittest.TestCase):
    def test_the_component_gate_checks_the_ordered_pin_pair(self):
        import json
        from pathlib import Path
        from unittest.mock import patch
        from tools.carla_lane_oracle import coverage_invariant_contracts as invariant
        original_labels = invariant._INVARIANT_LABELS
        original_migration = invariant.__dict__.get('MIGRATION')
        original_pair = invariant._GATED_PAIR
        payload = json.dumps({
            'components': {'a.json': 'abc'},
            'pin_files': {
                'runtime-source-pins.json': {},
                'sum2-guard-pins.json': {},
            },
        }).encode()
        root = Path('component-pair')
        calls = []

        def gate(*args, **kwargs):
            calls.append(kwargs.get('_then_pair', False))
            if kwargs.get('_then_pair') and gate.fail:
                raise ValueError('component record changed: a.json')

        gate.fail = False

        def read_bytes(self):
            return payload if self.name == 'migration.json' else b'bytes'

        def historical_bytes(_root, _path, raw, _operation=None):
            return raw

        try:
            (root / 'oracle').mkdir(parents=True)
            invariant._INVARIANT_LABELS = {
                'prior': 'prior.json',
                'oracle': 'oracle',
            }
            invariant.MIGRATION = 'migration.json'
            invariant._GATED_PAIR = None
            with patch.object(Path, 'read_bytes', read_bytes), patch.object(
                invariant._typed_source, 'historical_bytes', historical_bytes
            ), patch.object(invariant, '_gate', gate):
                record = invariant.read_record(root, _then_pair=True)
            self.assertEqual(calls, [False, False, True])
            self.assertEqual(
                invariant._GATED_PAIR,
                ('runtime-source-pins.json', 'sum2-guard-pins.json'),
            )
            self.assertEqual(
                tuple(record['pin_files']), invariant._GATED_PAIR
            )
            with patch('subprocess.run') as run:
                invariant._gate_pair(record['pin_files'])
                self.assertEqual(run.call_count, 0)
            invariant._GATED_PAIR = None
            calls.clear()
            gate.fail = True
            with patch.object(Path, 'read_bytes', read_bytes), patch.object(
                invariant._typed_source, 'historical_bytes', historical_bytes
            ), patch.object(invariant, '_gate', gate):
                with self.assertRaisesRegex(ValueError, 'component record changed'):
                    invariant.read_record(root, _then_pair=True)
            self.assertIsNone(invariant._GATED_PAIR)
            self.assertEqual(calls, [False, False, True])
        finally:
            invariant._INVARIANT_LABELS = original_labels
            if original_migration is None:
                invariant.__dict__.pop('MIGRATION', None)
            else:
                invariant.MIGRATION = original_migration
            invariant._GATED_PAIR = original_pair
            import shutil
            shutil.rmtree(root, ignore_errors=True)


class ComponentGateTests(unittest.TestCase):
    def test_component_names_join_the_record_gate(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import coverage_invariant_contracts as invariant
        calls = []

        def run(args, **kwargs):
            calls.append(list(args))
            return Mock(returncode=0, stdout='', stderr='')

        with patch('subprocess.run', side_effect=run):
            invariant._gate(b'{}', b'prior', [('a/b', b'abc'), ('ok.json', b'def')])
        self.assertEqual(len(calls), 1)
        joined = ' '.join(str(part) for part in calls[0])
        self.assertIn('carla_invariant_gate', joined)
        self.assertNotIn('carla_component_path', joined)


class MigrationDocumentTests(unittest.TestCase):
    def test_checkers_share_one_migration_record_document(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import ideal_projection
        from tools.carla_lane_oracle import frozen_arc_producer_contracts as frozen
        from tools.carla_lane_oracle import reviewed_cleanup_contracts as cleanup
        from tools.carla_lane_oracle import speed_parser_contracts as speed
        original_doc = ideal_projection._MIGRATION_RECORD_DOCUMENT
        originals = (
            (frozen, frozen._MIGRATION_RECORDS),
            (cleanup, cleanup._MIGRATION_RECORDS),
            (speed, speed._MIGRATION_RECORDS),
        )
        payload = (
            '{"frozen":{"path":"f","sha":"1"},'
            '"cleanup":{"path":"c","sha":"2"},'
            '"speed":{"path":"s","sha":"3"}}'
        )
        try:
            ideal_projection._MIGRATION_RECORD_DOCUMENT = None
            for module, _saved in originals:
                module._MIGRATION_RECORDS = None
            ok = Mock(returncode=0, stdout=payload, stderr='')
            with patch('subprocess.run', return_value=ok) as run:
                self.assertEqual(frozen._migration_records()['frozen']['path'], 'f')
                self.assertEqual(cleanup._migration_records()['cleanup']['path'], 'c')
                self.assertEqual(speed._migration_records()['speed']['path'], 's')
                self.assertEqual(run.call_count, 1)
            ideal_projection._MIGRATION_RECORD_DOCUMENT = None
            frozen._MIGRATION_RECORDS = None
            failed = Mock(returncode=1, stdout='', stderr='broken record\n')
            with patch('subprocess.run', return_value=failed):
                with self.assertRaisesRegex(ValueError, 'broken record'):
                    frozen._migration_records()
            self.assertIsNone(ideal_projection._MIGRATION_RECORD_DOCUMENT)
        finally:
            ideal_projection._MIGRATION_RECORD_DOCUMENT = original_doc
            for module, saved in originals:
                module._MIGRATION_RECORDS = saved


class ConstantDocumentTests(unittest.TestCase):
    def test_checkers_share_failure_and_contract_prefixes(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import ideal_projection
        from tools.carla_lane_oracle import spiral_moments
        from tools.carla_lane_oracle import sum2_contracts
        from tools.carla_lane_oracle import frozen_arc_producer_contracts as frozen
        original_docs = dict(ideal_projection._CONSTANT_DOCUMENTS)
        original_spiral = spiral_moments._CLI_FAILURES
        original_sum2 = sum2_contracts._CLI_FAILURES
        original_ideal = ideal_projection._CONTRACT_PREFIXES
        original_frozen = frozen._CONTRACT_PREFIXES
        try:
            ideal_projection._CONSTANT_DOCUMENTS.clear()
            spiral_moments._CLI_FAILURES = None
            sum2_contracts._CLI_FAILURES = None
            ideal_projection._CONTRACT_PREFIXES = None
            frozen._CONTRACT_PREFIXES = None
            seen = []

            def run(args, **kwargs):
                seen.append(args[-1])
                if args[-1] == 'carla_cli_failures':
                    stdout = '{"word":"spiral moment word: "}'
                else:
                    stdout = '{"frozen":"frozen ARC producer contract: ","scalar":"x: "}'
                return Mock(returncode=0, stdout=stdout, stderr='')

            with patch('subprocess.run', side_effect=run):
                self.assertEqual(
                    spiral_moments._cli_failures()['word'], 'spiral moment word: ')
                self.assertEqual(
                    sum2_contracts._cli_failures()['word'], 'spiral moment word: ')
                self.assertEqual(
                    frozen._contract_prefixes()['frozen'],
                    'frozen ARC producer contract: ')
                self.assertEqual(
                    ideal_projection._contract_prefixes()['scalar'], 'x: ')
            self.assertEqual(seen, ['carla_cli_failures', 'carla_contract_prefixes'])
            ideal_projection._CONSTANT_DOCUMENTS.clear()
            spiral_moments._CLI_FAILURES = None
            failed = Mock(returncode=1, stdout='', stderr='missing prefixes\n')
            with patch('subprocess.run', return_value=failed):
                with self.assertRaisesRegex(ValueError, 'missing prefixes'):
                    spiral_moments._cli_failures()
            self.assertNotIn('carla_cli_failures', ideal_projection._CONSTANT_DOCUMENTS)
        finally:
            ideal_projection._CONSTANT_DOCUMENTS.clear()
            ideal_projection._CONSTANT_DOCUMENTS.update(original_docs)
            spiral_moments._CLI_FAILURES = original_spiral
            sum2_contracts._CLI_FAILURES = original_sum2
            ideal_projection._CONTRACT_PREFIXES = original_ideal
            frozen._CONTRACT_PREFIXES = original_frozen


class PredecessorPairCacheTests(unittest.TestCase):
    def test_a_repeated_predecessor_pair_skips_the_second_placement(self):
        import hashlib
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import coverage_invariant_contracts as invariant
        original_labels = invariant._INVARIANT_LABELS
        original_placed = invariant._PLACED_PREDECESSORS
        runtime = b'{"runtime":1}'
        guard = b'{"guard":1}'
        digest = hashlib.sha256(runtime).hexdigest()
        runtime_record = {
            'after_sha256': digest,
            'before_sha256': 'before',
            'transitions': [],
        }
        guard_record = {
            'after_sha256': 'guard-after',
            'before_sha256': 'guard-before',
            'transitions': [],
        }
        placed = b'2\nRT2\nGD'

        def call(runtime_payload, guard_payload):
            return invariant._pin_predecessors(
                runtime_payload, runtime_record, 'runtime-source-pins.json',
                guard_payload, guard_record, 'sum2-guard-pins.json')

        try:
            invariant._INVARIANT_LABELS = {'after': 'after'}
            invariant._PLACED_PREDECESSORS = None
            ok = Mock(returncode=0, stdout=placed, stderr=b'')
            with patch('subprocess.run', return_value=ok) as run:
                first = call(runtime, guard)
                second = call(runtime, guard)
                self.assertEqual(first, (b'RT', b'GD'))
                self.assertEqual(second, first)
                self.assertEqual(run.call_count, 1)
            failed = Mock(
                returncode=1, stdout=b'', stderr=b'unreviewed guarded pin successor\n')
            with patch('subprocess.run', return_value=failed) as run:
                with self.assertRaisesRegex(ValueError, 'unreviewed guarded pin successor'):
                    call(runtime, b'{"guard":3}')
                self.assertEqual(run.call_count, 1)
                self.assertEqual(call(runtime, guard), (b'RT', b'GD'))
                self.assertEqual(run.call_count, 1)
            with patch('subprocess.run', return_value=ok) as run:
                self.assertEqual(call(runtime, b'{"guard":2}'), (b'RT', b'GD'))
                self.assertEqual(run.call_count, 1)
            duplicate = b'{"a":1,"a":2}'
            runtime_record['after_sha256'] = hashlib.sha256(duplicate).hexdigest()
            with patch('subprocess.run') as run:
                with self.assertRaisesRegex(
                        ValueError, 'duplicate runtime source pin key: a'):
                    call(duplicate, guard)
                self.assertEqual(run.call_count, 0)
            self.assertEqual(invariant._PLACED_PREDECESSORS[0], runtime)
        finally:
            invariant._INVARIANT_LABELS = original_labels
            invariant._PLACED_PREDECESSORS = original_placed


class RepeatedByteGateTests(unittest.TestCase):
    def test_repeated_speed_runtime_and_render_bytes_skip_the_second_gate(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import render_actor_reuse_contracts as render
        from tools.carla_lane_oracle import runtime_boundary_contracts as runtime
        from tools.carla_lane_oracle import speed_parser_contracts as speed
        saved = (
            speed._GATED_SPEED,
            runtime._GATED_RUNTIME_RECORD,
            runtime._GATED_RUNTIME_BYTES,
            runtime._EDGES_AFTER_STEPS,
            runtime._GATED_RUNTIME_EDGES,
            runtime._RUNTIME_MESSAGES,
            render._GATED_RENDER_RECORD,
            render._GATED_RENDER_BYTES,
            render._GATED_RENDER_EDGES,
            render._RENDER_MESSAGES,
            render._PATHS,
        )
        stdout = (
            '{"modules":["m.mojo"],"decisions":[],'
            '"edges":[{"path":"m.mojo"}],'
            '"messages":{"runtime_test":"rt","render_test":"r"}}'
        )
        edge = ('m.mojo', {'path': 'm.mojo'}, b'payload', 'digest', None)
        try:
            speed._GATED_SPEED = None
            runtime._GATED_RUNTIME_RECORD = None
            runtime._GATED_RUNTIME_BYTES = None
            runtime._EDGES_AFTER_STEPS = None
            runtime._GATED_RUNTIME_EDGES = None
            runtime._RUNTIME_MESSAGES = None
            render._GATED_RENDER_RECORD = None
            render._GATED_RENDER_BYTES = None
            render._GATED_RENDER_EDGES = None
            render._RENDER_MESSAGES = None
            render._PATHS = None
            ok = Mock(returncode=0, stdout=stdout, stderr='')
            with patch('subprocess.run', return_value=ok) as run:
                speed._gate(b'm', b'a', 'module', b'l', b'x')
                speed._gate(b'm', b'a', 'module', b'l', b'x')
                runtime._gate_record(b'record')
                runtime._gate_record(b'record')
                runtime._gate_bytes_all([(b'file', 'sha', None, 'label')])
                runtime._gate_bytes_all([(b'file', 'sha', None, 'label')])
                first = runtime._edges_after_steps({'lane': {}}, {'m.mojo': {}})
                second = runtime._edges_after_steps({'lane': {}}, {'m.mojo': {}})
                self.assertEqual(first, second)
                runtime._checked_edges_with_messages([edge])
                runtime._checked_edges_with_messages([edge])
                render._paths_after_record(b'render')
                render._paths_after_record(b'render')
                render._gate_bytes_all([(b'file', 'sha', None, 'label')])
                render._gate_bytes_all([(b'file', 'sha', None, 'label')])
                render._checked_edges_with_messages([edge])
                render._checked_edges_with_messages([edge])
                self.assertEqual(run.call_count, 8)
            failed = Mock(returncode=1, stdout='', stderr='speed record changed\n')
            with patch('subprocess.run', return_value=failed) as run:
                with self.assertRaisesRegex(ValueError, 'speed record changed'):
                    speed._gate(b'm', b'a', 'module', b'l', b'other')
                self.assertEqual(run.call_count, 1)
                speed._gate(b'm', b'a', 'module', b'l', b'x')
                self.assertEqual(run.call_count, 1)
        finally:
            (
                speed._GATED_SPEED,
                runtime._GATED_RUNTIME_RECORD,
                runtime._GATED_RUNTIME_BYTES,
                runtime._EDGES_AFTER_STEPS,
                runtime._GATED_RUNTIME_EDGES,
                runtime._RUNTIME_MESSAGES,
                render._GATED_RENDER_RECORD,
                render._GATED_RENDER_BYTES,
                render._GATED_RENDER_EDGES,
                render._RENDER_MESSAGES,
                render._PATHS,
            ) = saved


class LaneTokenPredecessorTests(unittest.TestCase):
    def test_declaration_tokens_and_predecessors_are_one_call(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import lane_control_contracts as lane
        pairs = [('left', 'right', 'lane token changed')]
        declarations = [{'path': 'p', 'name': 'n', 'before': 'b'}]
        items = [('p', 'n', (), 'expected')]
        ok = Mock(returncode=0, stdout='["true"]', stderr='')
        with patch('subprocess.run', return_value=ok) as run:
            flags = lane._tokens_then_predecessors(pairs, declarations, items)
            self.assertEqual(flags, [True])
            self.assertEqual(run.call_count, 1)
            command = ' '.join(str(part) for part in run.call_args[0][0])
            self.assertIn('--tokens-then-predecessors', command)
            self.assertNotIn('carla_lane_predecessor', command)
        failed = Mock(returncode=1, stdout='', stderr='lane token changed\n')
        with patch('subprocess.run', return_value=failed):
            with self.assertRaises(RuntimeError):
                lane._tokens_then_predecessors(pairs, declarations, items)
        other = Mock(returncode=1, stdout='', stderr='missing predecessor field\n')
        with patch('subprocess.run', return_value=other):
            with self.assertRaises(ValueError):
                lane._tokens_then_predecessors(pairs, declarations, items)


class SelectionGroupedTests(unittest.TestCase):
    def test_the_grouped_table_follows_the_restored_predecessor(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import selection_finiteness_contracts as selection
        ok = Mock(returncode=0, stdout='{"status":"PASS"}', stderr='')
        with patch('subprocess.run', return_value=ok) as run:
            record = selection._predecessor_then_grouped(
                {'path': 'extensions/carla/curve_roundoff.mojo'}, 'geometry')
        self.assertEqual(record['status'], 'PASS')
        self.assertEqual(run.call_count, 1)
        command = ' '.join(str(part) for part in run.call_args[0][0])
        self.assertIn('--then-grouped', command)
        self.assertNotIn('carla_grouped_gate', command)
        failed = Mock(returncode=1, stdout='', stderr='unlisted\n')
        with patch('subprocess.run', return_value=failed):
            with self.assertRaisesRegex(ValueError, 'unlisted'):
                selection._predecessor_then_grouped({'path': 'other.mojo'}, 'nope')


class RoundedWordMatchTests(unittest.TestCase):
    def test_matching_pairs_skip_the_second_comparison(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import rounded_line_singleton_contracts as singleton
        saved = dict(singleton._MATCHED_PAIRS)
        singleton._MATCHED_PAIRS.clear()
        try:
            ok = Mock(
                returncode=0, stdout='{"flags":["true","false"]}', stderr='')
            with patch('subprocess.run', return_value=ok) as run:
                flags = singleton._words_then_matches(
                    [('p', 'text', 'tok')],
                    [('text', 'source'), ('other', 'nope')])
                self.assertEqual(flags, [True, False])
                self.assertEqual(run.call_count, 1)
                command = ' '.join(str(part) for part in run.call_args[0][0])
                self.assertIn('--words-then-matches', command)
            self.assertTrue(singleton._MATCHED_PAIRS[('text', 'source')])
            self.assertNotIn(('other', 'nope'), singleton._MATCHED_PAIRS)
            with patch('subprocess.run', return_value=ok) as run:
                self.assertEqual(
                    singleton._significant_matches([('text', 'source')]),
                    [True])
                self.assertEqual(run.call_count, 0)
                singleton._significant_matches([('text', 'source'), ('other', 'nope')])
                self.assertEqual(run.call_count, 1)
            deferred = Mock(
                returncode=0, stdout='{"defer":"bad tokens"}', stderr='')
            with patch('subprocess.run', return_value=deferred):
                self.assertIsNone(singleton._words_then_matches(
                    [('p', 'text', 'tok')], [('bad', 'bad')]))
            self.assertNotIn(('bad', 'bad'), singleton._MATCHED_PAIRS)
            failed = Mock(returncode=1, stdout='', stderr='word list changed\n')
            with patch('subprocess.run', return_value=failed):
                with self.assertRaisesRegex(ValueError, 'word list changed'):
                    singleton._words_then_matches(
                        [('p', 'text', 'tok')], [('text', 'source')])
        finally:
            singleton._MATCHED_PAIRS.clear()
            singleton._MATCHED_PAIRS.update(saved)


class LaneCheckCacheTests(unittest.TestCase):
    def test_repeated_lane_checks_skip_the_second_call(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import ideal_projection
        from tools.carla_lane_oracle import lane_control_contracts as lane
        saved = (
            lane._GATED_LANE,
            lane._PREPARED_LANE,
            lane._LANE_LABELS,
            lane._LANE_TOKEN_PAIRS,
            lane._LANE_TOKEN_FULL,
            dict(ideal_projection._TOKEN_DIGESTS),
        )
        try:
            lane._GATED_LANE = None
            lane._PREPARED_LANE = None
            lane._LANE_LABELS = None
            lane._LANE_TOKEN_PAIRS = None
            lane._LANE_TOKEN_FULL = None
            ideal_projection._TOKEN_DIGESTS.clear()
            ok = Mock(returncode=0, stdout='true', stderr='')
            with patch('subprocess.run', return_value=ok) as run:
                self.assertTrue(ideal_projection.token_texts_match('left', 'right'))
                self.assertTrue(ideal_projection.token_texts_match('left', 'right'))
                self.assertEqual(run.call_count, 1)
                self.assertTrue(ideal_projection.token_texts_match('left', 'other'))
                self.assertEqual(run.call_count, 2)
            with patch('subprocess.run', return_value=ok) as run:
                lane._gate(b'record')
                lane._gate(b'record')
                self.assertEqual(run.call_count, 1)
                lane._gate(b'other')
                self.assertEqual(run.call_count, 2)
            prepared = Mock(
                returncode=0,
                stdout='{"replaced":["a"],"declared":["b"],"labels":{"s":"t"}}',
                stderr='')
            with patch('subprocess.run', return_value=prepared) as run:
                first = lane._prepare_with_labels({'current': 'text'})
                second = lane._prepare_with_labels({'current': 'text'})
                self.assertEqual(first, second)
                self.assertEqual(run.call_count, 1)
            pairs = [('left', 'right', 'lane token changed')]
            with patch('subprocess.run', return_value=ok) as run:
                lane._gate_tokens(pairs)
                lane._gate_tokens(pairs)
                self.assertEqual(run.call_count, 1)
            flags = Mock(returncode=0, stdout='["true"]', stderr='')
            with patch('subprocess.run', return_value=flags) as run:
                self.assertEqual(
                    lane._tokens_then_predecessors(
                        pairs,
                        [{'path': 'p', 'name': 'n', 'before': 'b'}],
                        [('p', 'n', (), 'expected')]),
                    [True])
                self.assertEqual(run.call_count, 1)
                lane._gate_tokens(pairs)
                self.assertEqual(run.call_count, 1)
            failed = Mock(returncode=1, stdout='', stderr='lane record changed\n')
            with patch('subprocess.run', return_value=failed) as run:
                with self.assertRaises(RuntimeError):
                    lane._gate(b'bad')
                self.assertEqual(run.call_count, 1)
                with self.assertRaises(RuntimeError):
                    lane._gate(b'bad')
                self.assertEqual(run.call_count, 2)
        finally:
            (
                lane._GATED_LANE,
                lane._PREPARED_LANE,
                lane._LANE_LABELS,
                lane._LANE_TOKEN_PAIRS,
                lane._LANE_TOKEN_FULL,
            ) = saved[:5]
            ideal_projection._TOKEN_DIGESTS.clear()
            ideal_projection._TOKEN_DIGESTS.update(saved[5])


class FrozenPredecessorReuseTests(unittest.TestCase):
    def test_a_placed_predecessor_is_not_rebuilt(self):
        import hashlib
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import frozen_arc_producer_contracts as frozen
        saved = (frozen._ACCEPTED_PREDECESSOR, frozen._PATHS)
        payload = b'{}'
        record = {
            'runtime_pins_after_sha256': hashlib.sha256(payload).hexdigest(),
            'runtime_token_successors': [],
        }
        prior = '00'
        try:
            frozen._ACCEPTED_PREDECESSOR = None
            frozen._PATHS = None
            request = frozen._predecessor_request(payload, record, prior)
            frozen._ACCEPTED_PREDECESSOR = (payload, request, b'pred\n')
            frozen._PATHS = {'source': 'extensions/carla/curve_frozen_arc.mojo'}
            ok = Mock(returncode=0, stdout='', stderr='')
            with patch('subprocess.run', return_value=ok) as run:
                self.assertEqual(
                    frozen._runtime_predecessor(
                        payload, record, prior, _then_paths=True),
                    b'pred\n')
                self.assertEqual(run.call_count, 0)
            other = b'{"a":1}'
            other_record = {
                'runtime_pins_after_sha256': hashlib.sha256(other).hexdigest(),
                'runtime_token_successors': [],
            }
            placed = Mock(
                returncode=0,
                stdout='{"predecessor":"next","paths":{"source":"s"}}',
                stderr='')
            with patch('subprocess.run', return_value=placed) as run:
                self.assertEqual(
                    frozen._runtime_predecessor(
                        other, other_record, prior, _then_paths=True),
                    b'next')
                self.assertEqual(run.call_count, 1)
            with patch('subprocess.run', return_value=ok) as run:
                with self.assertRaisesRegex(
                        ValueError, 'unreviewed runtime pin successor'):
                    frozen._runtime_predecessor(
                        b'{', record, prior, _then_paths=True)
                self.assertEqual(run.call_count, 0)
                self.assertEqual(
                    frozen._runtime_predecessor(
                        payload, record, prior, _then_paths=True),
                    b'pred\n')
                self.assertEqual(run.call_count, 0)
        finally:
            frozen._ACCEPTED_PREDECESSOR, frozen._PATHS = saved


class PriorDigestCacheTests(unittest.TestCase):
    def test_the_same_prior_digest_pair_skips_the_second_gate(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import frozen_arc_producer_contracts as frozen
        saved = frozen._GATED_PRIOR
        try:
            frozen._GATED_PRIOR = None
            ok = Mock(returncode=0, stdout='', stderr='')
            with patch('subprocess.run', return_value=ok) as run:
                frozen._gate_prior('before', 'before')
                frozen._gate_prior('before', 'before')
                self.assertEqual(run.call_count, 1)
                frozen._gate_prior('before', 'after')
                self.assertEqual(run.call_count, 2)
            failed = Mock(returncode=1, stdout='', stderr='prior digest changed\n')
            with patch('subprocess.run', return_value=failed) as run:
                with self.assertRaisesRegex(ValueError, 'prior digest changed'):
                    frozen._gate_prior('bad', 'bad')
                self.assertEqual(run.call_count, 1)
                with self.assertRaisesRegex(ValueError, 'prior digest changed'):
                    frozen._gate_prior('bad', 'bad')
                self.assertEqual(run.call_count, 2)
            with patch('subprocess.run', return_value=ok) as run:
                frozen._gate_prior('before', 'after')
                self.assertEqual(run.call_count, 0)
        finally:
            frozen._GATED_PRIOR = saved


class LaneViewCacheTests(unittest.TestCase):
    def test_the_same_lane_views_skip_the_second_comparison(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import rounded_line_singleton_contracts as singleton
        saved = singleton._LANE_VIEWS
        try:
            singleton._LANE_VIEWS = None
            ok = Mock(returncode=0, stdout='', stderr='')
            with patch('subprocess.run', return_value=ok) as run:
                singleton._views_after_newlines('text\n', 'text\n')
                singleton._views_after_newlines('text\n', 'text\n')
                self.assertEqual(run.call_count, 1)
                singleton._views_after_newlines('text\n', 'other\n')
                self.assertEqual(run.call_count, 2)
            failed = Mock(returncode=1, stdout='', stderr='lane text changed\n')
            with patch('subprocess.run', return_value=failed) as run:
                with self.assertRaisesRegex(ValueError, 'lane text changed'):
                    singleton._views_after_newlines('bad', 'bad')
                self.assertEqual(run.call_count, 1)
                with self.assertRaisesRegex(ValueError, 'lane text changed'):
                    singleton._views_after_newlines('bad', 'bad')
                self.assertEqual(run.call_count, 2)
            with patch('subprocess.run', return_value=ok) as run:
                singleton._views_after_newlines('text\n', 'other\n')
                self.assertEqual(run.call_count, 0)
        finally:
            singleton._LANE_VIEWS = saved


class RestoredScopeTests(unittest.TestCase):
    def test_the_restored_scope_and_the_minima_are_one_call(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import rounded_line_singleton_contracts as singleton
        ok = Mock(returncode=0, stdout='["true"]', stderr='')
        with patch('subprocess.run', return_value=ok) as run:
            flags = singleton._restored_scope_then_minima(
                ['stale'], 0, 'def f():\n    return 1\n', [''], ['ok'],
                [('extensions/carla/lane_refinement.mojo',
                  '_rounded_axis_lane_minimum', ())],
            )
        self.assertEqual(flags, [True])
        self.assertEqual(run.call_count, 1)
        command = ' '.join(str(part) for part in run.call_args[0][0])
        self.assertIn('--restored-scope-then-minima', command)
        self.assertNotIn('carla_import_scopes', command)
        failed = Mock(returncode=1, stdout='', stderr='lane scope changed\n')
        with patch('subprocess.run', return_value=failed):
            with self.assertRaisesRegex(ValueError, 'lane scope changed'):
                singleton._restored_scope_then_minima(
                    ['stale'], 0, 'def f():\n    return 1\n', ['nope'],
                    ['lane scope changed'],
                    [('p', 'n', ())],
                )


class DistanceGateCacheTests(unittest.TestCase):
    def test_the_same_spiral_domain_texts_skip_the_second_gate(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import distance_validation_contracts as distance
        saved_gate = distance._GATED_DISTANCE
        saved_path = distance._MODULE_PATH
        saved_module = distance.__dict__.get('MODULE')
        reads = []

        def read_text(self, *args, **kwargs):
            reads.append(self.name)
            return 'text-' + self.name

        try:
            distance._GATED_DISTANCE = None
            distance._MODULE_PATH = 'extensions/carla/curve_distance.mojo'
            ok = Mock(returncode=0, stdout='{"status":"PASS"}', stderr='')
            with patch('subprocess.run', return_value=ok) as run:
                first = distance.verify_text('module', 'interval')
                second = distance.verify_text('module', 'interval')
                self.assertEqual(first, {'status': 'PASS'})
                self.assertEqual(second, first)
                self.assertEqual(run.call_count, 1)
                distance.verify_text('module', 'other')
                self.assertEqual(run.call_count, 2)
            failed = Mock(
                returncode=1, stdout='', stderr='distance token changed\n')
            with patch('subprocess.run', return_value=failed) as run:
                with self.assertRaisesRegex(ValueError, 'distance token changed'):
                    distance.verify_text('bad', 'bad')
                self.assertEqual(run.call_count, 1)
                with self.assertRaisesRegex(ValueError, 'distance token changed'):
                    distance.verify_text('bad', 'bad')
                self.assertEqual(run.call_count, 2)
            with patch('subprocess.run', return_value=ok) as run:
                distance.verify_text('module', 'other')
                self.assertEqual(run.call_count, 0)
            with patch.object(Path, 'read_text', read_text), patch.object(
                distance._typed_source, 'historical_text',
                lambda root, path, text, _operation=None: text,
            ), patch('subprocess.run', return_value=ok) as run:
                distance.verify(Path('distance-root'))
                distance.verify(Path('distance-root'))
                self.assertEqual(run.call_count, 1)
                self.assertEqual(
                    reads,
                    ['curve_distance.mojo', 'curve_interval.mojo'] * 2,
                )
        finally:
            distance._GATED_DISTANCE = saved_gate
            distance._MODULE_PATH = saved_path
            if saved_module is None:
                distance.__dict__.pop('MODULE', None)
            else:
                distance.MODULE = saved_module


class InvariantRecordGateTests(unittest.TestCase):
    def test_the_same_record_bytes_skip_the_second_gate(self):
        import json
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import coverage_invariant_contracts as invariant
        saved_gates = invariant._GATED_INVARIANT
        saved_labels = invariant._INVARIANT_LABELS
        saved_migration = invariant.__dict__.get('MIGRATION')
        saved_pair = invariant._GATED_PAIR
        payload = json.dumps({
            'components': {'a.json': 'abc'},
            'pin_files': {
                'runtime-source-pins.json': {},
                'sum2-guard-pins.json': {},
            },
        }).encode()
        duplicate = b'{"a": 1, "a": 2}'
        reads = []

        def read_bytes(self):
            reads.append(self.name)
            if self.name == 'migration.json':
                return read_bytes.payload
            return b'bytes'

        read_bytes.payload = payload

        def historical_bytes(_root, _path, raw, _operation=None):
            return raw

        try:
            invariant._GATED_INVARIANT = set()
            invariant._INVARIANT_LABELS = {
                'prior': 'prior.json',
                'oracle': 'oracle',
            }
            invariant.MIGRATION = 'migration.json'
            invariant._GATED_PAIR = None
            ok = Mock(returncode=0, stdout='', stderr='')
            with patch.object(Path, 'read_bytes', read_bytes), patch.object(
                invariant._typed_source, 'historical_bytes', historical_bytes
            ), patch('subprocess.run', return_value=ok) as run:
                invariant._gate(b'migration')
                invariant._gate(b'migration')
                invariant._gate(b'migration', b'prior')
                invariant._gate(b'migration', b'prior', [('a.json', b'abc')])
                invariant._gate(
                    b'migration', b'prior', [('a.json', b'abc')], _then_pair=True)
                self.assertEqual(run.call_count, 4)
                invariant._gate(b'migration')
                invariant._gate(b'migration', b'prior')
                invariant._gate(b'migration', b'prior', [('a.json', b'abc')])
                invariant._gate(
                    b'migration', b'prior', [('a.json', b'abc')], _then_pair=True)
                self.assertEqual(run.call_count, 4)
                invariant._gate(b'other')
                self.assertEqual(run.call_count, 5)
                first = invariant.read_record(Path('invariant-gate'), _then_pair=True)
                second = invariant.read_record(Path('invariant-gate'), _then_pair=True)
                self.assertEqual(first['components'], second['components'])
                self.assertEqual(run.call_count, 8)
                self.assertEqual(
                    reads,
                    ['migration.json', 'prior.json', 'a.json'] * 2,
                )
                read_bytes.payload = duplicate
                with self.assertRaisesRegex(
                        ValueError, 'duplicate runtime source pin key: a'):
                    invariant.read_record(Path('invariant-gate'))
                with self.assertRaisesRegex(
                        ValueError, 'duplicate runtime source pin key: a'):
                    invariant.read_record(Path('invariant-gate'))
                self.assertEqual(run.call_count, 9)
                self.assertEqual(
                    reads[-2:], ['migration.json', 'migration.json'])
            failed = Mock(returncode=1, stdout='', stderr='bad migration\n')
            reads.clear()
            read_bytes.payload = b'{}'
            with patch.object(Path, 'read_bytes', read_bytes), patch.object(
                invariant._typed_source, 'historical_bytes', historical_bytes
            ), patch('subprocess.run', return_value=failed) as run:
                with self.assertRaisesRegex(ValueError, 'bad migration'):
                    invariant.read_record(Path('invariant-gate'))
                with self.assertRaisesRegex(ValueError, 'bad migration'):
                    invariant.read_record(Path('invariant-gate'))
                self.assertEqual(run.call_count, 2)
                self.assertEqual(reads, ['migration.json', 'migration.json'])
        finally:
            invariant._GATED_INVARIANT = saved_gates
            invariant._INVARIANT_LABELS = saved_labels
            if saved_migration is None:
                invariant.__dict__.pop('MIGRATION', None)
            else:
                invariant.MIGRATION = saved_migration
            invariant._GATED_PAIR = saved_pair

    def test_a_paired_component_gate_covers_the_plain_gate(self):
        from unittest.mock import Mock, patch
        from tools.carla_lane_oracle import coverage_invariant_contracts as invariant
        from tools.carla_lane_oracle import curve_support_dispatch_contracts as curve
        from tools.carla_lane_oracle import grouped_table_contracts as grouped
        from tools.carla_lane_oracle import lane_control_contracts as lane
        saved_gates = invariant._GATED_INVARIANT
        calls = []

        def read_record(root, _then_pair=False):
            calls.append(_then_pair)
            return {'sources': {}}

        try:
            invariant._GATED_INVARIANT = set()
            ok = Mock(returncode=0, stdout='', stderr='')
            components = [('a.json', b'abc')]
            with patch('subprocess.run', return_value=ok) as run:
                invariant._gate(b'migration', b'prior', components, _then_pair=True)
                invariant._gate(b'migration', b'prior', components)
                self.assertEqual(run.call_count, 1)
                invariant._gate(b'other', b'prior', components)
                invariant._gate(b'other', b'prior', components, _then_pair=True)
                self.assertEqual(run.call_count, 3)
            failed = Mock(returncode=1, stdout='', stderr='wrong fixed ordered pin pair\n')
            with patch('subprocess.run', return_value=failed) as run:
                with self.assertRaisesRegex(ValueError, 'wrong fixed ordered pin pair'):
                    invariant._gate(b'bad', b'prior', components, _then_pair=True)
                self.assertEqual(run.call_count, 1)
            with patch('subprocess.run', return_value=ok) as run:
                invariant._gate(b'bad', b'prior', components)
                self.assertEqual(run.call_count, 1)
            with patch.object(invariant, 'read_record', read_record), patch.object(
                invariant, 'predecessor_pin_pair', lambda root: (b'runtime', b'guard')
            ), patch.object(
                invariant, '_predecessor_pin_pair',
                lambda root, _operation=None: (b'runtime', b'guard'),
            ), patch.object(
                invariant, '_matches_then_dispatch',
                return_value={'flags': [], 'matched': False},
            ), patch.object(curve, 'verify', lambda *args, **kwargs: None), patch.object(
                grouped, 'verify', lambda *args, **kwargs: None
            ), patch.object(lane, 'verify', lambda *args, **kwargs: None), patch(
                'tools.carla_lane_oracle.full_audit_cleanup_contracts._operation_enter',
                lambda root, kind, _operation=None, **kwargs: (None, False),
            ):
                invariant.verify(Path('invariant-verify'))
            self.assertEqual(calls, [True])
        finally:
            invariant._GATED_INVARIANT = saved_gates


if __name__ == '__main__':
    unittest.main()
