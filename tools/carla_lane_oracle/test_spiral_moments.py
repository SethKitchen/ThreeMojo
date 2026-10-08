#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Stdlib-only controls: python3 -B tools/carla_lane_oracle/test_spiral_moments.py."""
import contextlib
from fractions import Fraction as F
import io
import json
import math
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
import spiral_moments as m
import seed_count_contracts as seed_count


def sparse_add(left, right):
    out = left.copy()
    for power, coefficient in right.items():
        out[power] = out.get(power, F(0)) + coefficient
    return {power: value for power, value in out.items() if value}


def sparse_multiply(left, right):
    out = {}
    for (d1, beta1), c1 in left.items():
        for (d2, beta2), c2 in right.items():
            power = d1 + d2, beta1 + beta2
            out[power] = out.get(power, F(0)) + c1 * c2
    return {power: value for power, value in out.items() if value}


def constant(value):
    return {(0, 0): F(value)}


def horner(coefficients, variable):
    out = constant(coefficients[-1])
    for value in reversed(coefficients[:-1]):
        out = sparse_add(sparse_multiply(out, variable), constant(value))
    return out


def literal_coefficients(count, constants):
    """Distribute literal GL/trig expressions with symbolic d AND beta.

    No moment routine, prefix sum, endpoint helper, or stored expected table
    enters this route. beta = stored_rate/2 is an exact symbolic parameter.
    """
    step = {(1, 0): F(1, count)}
    beta = {(0, 1): F(1)}
    x, y = {}, {}
    for piece in range(count):
        start = sparse_multiply(step, constant(piece))
        for node, weight in zip(constants['node_sums'], constants['_GL_WEIGHTS']):
            offset = sparse_multiply(sparse_multiply(step, constant(F(1, 2))),
                                     constant(node))
            t = sparse_add(start, offset)
            theta = sparse_multiply(t, sparse_multiply(beta, t))
            square = sparse_multiply(theta, theta)
            cosine = horner(constants['_COS_COEFFICIENTS'], square)
            sine = sparse_multiply(theta, horner(constants['_SIN_COEFFICIENTS'], square))
            factor = sparse_multiply(sparse_multiply(step, constant(F(1, 2))),
                                     constant(weight))
            x = sparse_add(x, sparse_multiply(factor, cosine))
            y = sparse_add(y, sparse_multiply(factor, sine))
    if set(x) != {(4*j + 1, 2*j) for j in range(11)}:
        raise AssertionError('unexpected cosine polynomial support')
    if set(y) != {(4*j + 3, 2*j + 1) for j in range(11)}:
        raise AssertionError('unexpected sine polynomial support')
    return ([x[4*j + 1, 2*j] for j in range(11)],
            [y[4*j + 3, 2*j + 1] for j in range(11)])


class RoundingTests(unittest.TestCase):
    def test_stored_words_round_trip(self):
        for word in [0, 1, (1 << 52)-1, 1 << 52, 0x3FEFFFFFFFFFFFFF,
                     0x3FF0000000000000, 0x3FF0000000000001, m.MAX_FINITE]:
            for sign in (0, m.SIGN):
                signed = word | sign
                value = m.fraction_of_word(signed)
                expected = (m.SIGN, 0) if not value else (signed, signed)
                self.assertEqual(m.bracket(value), expected)

    def test_halfway_rounding_is_even(self):
        for low in [0, 1, (1 << 52)-1, 1 << 52, 0x3FEFFFFFFFFFFFFF,
                    0x3FF0000000000000, 0x3FF0000000000001]:
            mid = (m.fraction_of_word(low) + m.fraction_of_word(low+1))/2
            even = low if low % 2 == 0 else low+1
            self.assertEqual(m.nearest_even(mid), even)
            self.assertEqual(m.nearest_even(-mid), even | m.SIGN)

    def test_decimal_sign_and_exact_rounding(self):
        self.assertEqual(m.decimal_word('-0.0'), m.SIGN)
        self.assertEqual(m.decimal_word('0.0'), 0)
        self.assertEqual(m.decimal_word('0.1'), 0x3FB999999999999A)
        self.assertEqual(m.decimal_word('-0.1'), 0xBFB999999999999A)

    def test_subnormal_underflow_brackets(self):
        tiny = F(1, 1 << 1076)
        self.assertEqual(m.bracket(tiny), (0, 1))
        self.assertEqual(m.bracket(-tiny), (m.SIGN | 1, m.SIGN))

    def test_bad_and_nonfinite_words_rejected(self):
        for word in [-1, 1 << 64, m.INFINITY, m.INFINITY + 1, m.SIGN | m.INFINITY]:
            with self.subTest(word=word), self.assertRaises(m.CheckError):
                m.fraction_of_word(word)
        with self.assertRaises(m.CheckError):
            m.bracket(m.fraction_of_word(m.MAX_FINITE) * 2)

    def test_enclosing_but_wide_endpoint_rejected(self):
        with self.assertRaises(m.CheckError):
            m.verify_bracket(F(1), 0x3FEFFFFFFFFFFFFF, 0x3FF0000000000001)


class TableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.constants, cls.pins = m.verify_inputs(m.ROOT)
        cls.rows = m.derive_coefficients(cls.constants)
        cls.source = m.generate_source(cls.rows)
        cls.original = (m.ROOT/m.DATA).read_bytes()
        # Partial mutation fixtures use the verified historical Map bytes.
        cls.historical_map = seed_count.historical_source(m.ROOT).encode('utf-8')

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)/'repo'
        paths = {m.PINS, m.DATA, m.source_contracts.PINS,
                 Path(m.DEPENDENCIES['guard_pin_file']),
                 Path('tools/carla_lane_oracle/winner-sign-query-migration.json')}
        from reviewed_cleanup_contracts import PROTECTED_INPUTS
        paths.update(Path(path) for path in PROTECTED_INPUTS)
        paths.update(Path(path) for path in m.DEPENDENCIES['paths'])
        guard_pins = json.loads((m.ROOT/m.DEPENDENCIES['guard_pin_file']).read_text())
        paths.update(Path(path) for path in guard_pins['protected_inventory'])
        paths.update(Path(record['path']) for group in ('arrays', 'scalars', 'blocks')
                     for record in self.pins[group].values())
        for path in paths:
            destination = self.root/path
            destination.parent.mkdir(parents=True, exist_ok=True)
            if path == Path(seed_count.MODULE):
                destination.write_bytes(self.historical_map)
            else:
                shutil.copyfile(m.ROOT/path, destination)

    def change(self, path, before, after):
        target = self.root/path
        content = target.read_text()
        self.assertIn(before, content)
        target.write_text(content.replace(before, after, 1))

    def run_main(self, arguments):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return m.main(['--repo-root', str(self.root)] + arguments)

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes()
                for p in self.root.rglob('*') if p.is_file()}

    def test_all_endpoints_and_canonical_bytes(self):
        self.assertEqual(len(m.verify_table(self.original, self.rows)), 2816)
        for row in self.rows:
            for side in ('cosine', 'sine'):
                for coefficient in row[side]:
                    exact = F(coefficient['exact'])
                    low, high = map(lambda w: int(w, 16), coefficient['words'])
                    m.verify_bracket(exact, low, high)
                    # Independent host conversion/nextafter cross-check.
                    nearest = float(exact)
                    lo = math.nextafter(nearest, -math.inf) if F(nearest)>exact else nearest
                    hi = math.nextafter(nearest, math.inf) if F(nearest)<exact else nearest
                    words = [struct.unpack('>Q', struct.pack('>d', value))[0] for value in (lo,hi)]
                    self.assertEqual(words, [low, high])
        payload = b''.join(struct.pack('>Q', w) for w in m.words_from_rows(self.rows))
        self.assertEqual(m.digest(payload), '72f5e5d09a6f4091e1a537aa89bf80493a427576b5ff86619830721edbc5f446')

    def test_literal_bivariate_graph_independent(self):
        for count in range(1, 65):
            with self.subTest(count=count):
                cosine, sine = literal_coefficients(count, self.constants)
                row = self.rows[count-1]
                self.assertEqual(cosine, [F(c['exact']) for c in row['cosine']])
                self.assertEqual(sine, [F(c['exact']) for c in row['sine']])

    def test_canonical_source_matches_retained_formatter_output(self):
        self.assertEqual(m.digest(self.source),
                         '63b07b8aa1567ad3e1c8b09a71e5619073e5255b4dc6f733d4ef6bf6b7088c8c')

    def test_paired_endpoint_layout_is_noncanonical(self):
        paired = self.source.replace(b'),\n    UInt64(', b'), UInt64(', 1)
        self.assertNotEqual(paired, self.source)
        self.assertEqual(m.parse_table(paired), m.parse_table(self.source))
        with self.assertRaisesRegex(m.CheckError, 'not canonical'):
            m.verify_table(paired, self.rows)

    def test_zeroth_moment_is_not_one(self):
        expected = F(1) + F(3, 1 << 55)
        self.assertNotEqual(expected, 1)
        for row in self.rows:
            self.assertEqual(F(row['cosine'][0]['exact']), expected)
            self.assertEqual(row['cosine'][0]['words'], ['0x3FF0000000000000', '0x3FF0000000000001'])

    def test_one_plus_node_is_rounded_first(self):
        nodes = self.constants['_GL_NODES']
        sums = self.constants['node_sums']
        self.assertTrue(any(F(1)+node != total for node,total in zip(nodes,sums)))
        for node,total in zip(nodes,sums):
            self.assertEqual(total, m.fraction_of_word(m.nearest_even(F(1)+node)))
            self.assertEqual(total, F(1.0 + float(node)))

    def test_corrupted_word_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'endpoint differs'):
            m.verify_table(self.source.replace(b'0x3FF0000000000000', b'0x3FF0000000000001',1), self.rows)

    def test_missing_word_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'missing or extra'):
            m.verify_table(self.source.replace(b'UInt64(0x3FF0000000000000),', b'',1), self.rows)

    def test_extra_word_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'missing or extra'):
            m.verify_table(self.source.replace(b'\n]\n', b'\nUInt64(0x0000000000000000),\n]\n'), self.rows)

    def test_wrong_shape_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'declaration shape'):
            m.verify_table(self.source.replace(b'Array[UInt64, 2816]',b'Array[UInt64, 2815]'), self.rows)

    def test_malformed_word_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'malformed coefficient'):
            m.verify_table(self.source.replace(b'0x3FF0000000000000',b'0x3FF000000000000',1), self.rows)

    def test_same_words_noncanonical_format_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'not canonical'):
            m.verify_table(self.source + b'# extra comment\n', self.rows)

    def test_executable_trailer_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'malformed table declaration'):
            m.verify_table(self.source + b'comptime unexpected = 1\n', self.rows)

    def test_changed_weight_rejected(self):
        self.change('extensions/carla/geometry.mojo', '0.2369268850561891,', '0.2369268850561892,')
        with self.assertRaisesRegex(m.CheckError, 'constant words changed'):
            m.verify_inputs(self.root)

    def test_signed_zero_constant_change_rejected(self):
        self.change('extensions/carla/geometry.mojo', '    0.0,\n    0.5384693101056831', '    -0.0,\n    0.5384693101056831')
        with self.assertRaisesRegex(m.CheckError, 'constant words changed'):
            m.verify_inputs(self.root)

    def test_same_stored_constant_spelling_allowed(self):
        self.change('extensions/carla/geometry.mojo', '0.2369268850561891,', '0.23692688505618910000,')
        m.verify_inputs(self.root)

    def test_changed_phase_scalar_rejected(self):
        self.change('extensions/carla/curve_trig.mojo', '_PHASE_LIMIT = Float64(1048576.0)', '_PHASE_LIMIT = Float64(1048577.0)')
        with self.assertRaisesRegex(m.CheckError, 'scalar word changed'):
            m.verify_inputs(self.root)

    def test_changed_scalar_phase_graph_rejected(self):
        self.change('extensions/carla/lane_geometry.mojo', 'start + step * 0.5 * (1.0 + nodes[i])', 'start + step * 0.25 * (1.0 + nodes[i])')
        with self.assertRaisesRegex(m.CheckError, 'operation graph changed'):
            m.verify_inputs(self.root)

    def test_changed_canonical_alias_rejected(self):
        self.change('extensions/carla/lane_geometry.mojo', '_curve_cos as cos,', '_curve_sin as cos,')
        with self.assertRaisesRegex(m.CheckError, 'operation graph changed'):
            m.verify_inputs(self.root)

    def test_changed_ideal_graph_rejected(self):
        self.change('extensions/carla/curve_bounds.mojo', '1.0 + nodes[i]', 'nodes[i]')
        with self.assertRaisesRegex(m.CheckError, 'operation graph changed'):
            m.verify_inputs(self.root)

    def test_unrelated_module_comment_allowed(self):
        target = self.root/'extensions/carla/geometry.mojo'
        target.write_text('# Unrelated documentation.\n' + target.read_text())
        m.verify_inputs(self.root)

    def test_removed_graph_pin_rejected(self):
        pins = json.loads((self.root/m.PINS).read_text())
        del pins['blocks']['scalar_spiral']
        (self.root/m.PINS).write_text(json.dumps(pins))
        with self.assertRaisesRegex(m.CheckError, 'pin set'):
            m.verify_inputs(self.root)

    def test_missing_table_is_cli_failure(self):
        (self.root/m.DATA).unlink()
        self.assertEqual(self.run_main([]), 1)

    def test_default_and_check_never_write(self):
        before = self.snapshot()
        output = Path(self.temp.name)/'should-not-exist'
        with patch.dict(os.environ, {'CARLA_LANE_ORACLE_OUTPUT':str(output)}):
            self.assertEqual(self.run_main([]), 0)
            self.assertEqual(self.run_main(['--check']), 0)
        self.assertFalse(output.exists())
        self.assertEqual(self.snapshot(), before)

    def test_check_cannot_request_report(self):
        with self.assertRaises(SystemExit) as raised:
            self.run_main(['--check', '--report'])
        self.assertEqual(raised.exception.code, 2)

    def test_generate_explicit_outputs_using_existing_env(self):
        output = Path(self.temp.name)/'generated'
        (self.root/m.DATA).unlink()
        before = self.snapshot()
        with patch.dict(os.environ, {'CARLA_LANE_ORACLE_OUTPUT':str(output)}):
            self.assertEqual(self.run_main(['--generate']), 0)
        self.assertEqual((output/m.DATA.name).read_bytes(), self.source)
        self.assertEqual(len((output/'spiral_moment_words.be64').read_bytes()), 22528)
        self.assertEqual(self.snapshot(), before)

    def test_generate_cannot_overwrite_source(self):
        before = self.snapshot()
        self.assertEqual(self.run_main(['--generate', '--output', str(self.root/m.DATA.parent)]), 1)
        self.assertEqual(self.snapshot(), before)

    def test_report_is_explicit_and_bounded(self):
        output = Path(self.temp.name)/'report'
        self.assertEqual(self.run_main(['--report','--output',str(output)]), 0)
        self.assertEqual([p.name for p in output.iterdir()], ['spiral-moment-report.json'])


    def reject_source_case(self, path, original, changed, diagnostic):
        target = self.root/path
        self.assertNotEqual(original, changed)
        fixed = {pin: (self.root/pin).read_bytes()
                 for pin in (m.PINS, m.source_contracts.PINS)}
        target.write_text(changed)
        try:
            with self.assertRaisesRegex(m.CheckError, diagnostic):
                m.verify_inputs(self.root)
            # Exercise the actual fail-closed CLI path in normal and -O runs.
            self.assertEqual(self.run_main(['--check']), 1)
            self.assertEqual(fixed, {pin: (self.root/pin).read_bytes() for pin in fixed})
        finally:
            target.write_text(original)

    def test_fixed_pin_stored_half_dependency_mutations(self):
        path = 'extensions/carla/curve_interval.mojo'
        original = (self.root/path).read_text()
        marker = 'def _stored_half['
        prefix, helper = original.split(marker)
        cases = [
            ('half factor', 'constant(0.5)', 'constant(0.25)'),
            ('wrong operand', 'var result = value *', 'var result = _JetExpression[derivatives].constant(1.0) *'),
            ('inherited error', '_Interval.point(value.error)', '_Interval.point(0.0)'),
            ('lower exponent', 'UInt64(623)', 'UInt64(622)'),
            ('upper exponent', 'UInt64(1423)', 'UInt64(1424)'),
            ('lower inequality', 'actual.low >=', 'actual.low >'),
            ('upper inequality', 'actual.high <=', 'actual.high <'),
            ('finite ideal fallback', 'not value.value.is_finite()', 'False'),
            ('unordered fallback', 'value.value.low > value.value.high', 'False'),
            ('finite error fallback', 'not isfinite(value.error)', 'False'),
            ('negative error fallback', 'value.error < 0.0', 'False'),
            ('fallback return', 'return result', 'return value'),
            ('changed ideal field', 'var actual =', 'result.value = value.value\n    var actual ='),
        ]
        for label, before, after in cases:
            with self.subTest(label=label):
                self.assertIn(before, helper)
                self.reject_source_case(path, original,
                    prefix + marker + helper.replace(before, after, 1), 'stored-half dependency closure')

    def test_fixed_pin_complete_helper_closure_mutations(self):
        path = 'extensions/carla/curve_interval.mojo'
        original = (self.root/path).read_text()
        cases = [
            ('math import', 'import fma, inf', 'import sqrt as fma, inf'),
            ('bitcast import', 'from std.memory import bitcast', 'from unexpected.memory import bitcast'),
            ('primitive half constant', 'var zero = _Interval.point(0.0)', 'var zero = _Interval.point(1.0)'),
            ('primitive product value', '_tight_product_bound(self.value, other.value)', '_tight_product_bound(self.value, self.value)'),
            ('primitive product inherited error', '_Interval.point(other.error)', '_Interval.point(0.0)'),
            ('rounded value error', 'return self.value + _Interval(-self.error, self.error)', 'return self.value'),
            ('interval product operand', 'var a = self.low * other.low', 'var a = self.low * other.high'),
            ('tight product endpoint', '_directed_endpoint_product(one.low, two.low)', '_directed_endpoint_product(one.high, two.low)'),
            ('product residual', 'fma(one, two, -value)', 'fma(one, two, value)'),
            ('roundoff threshold', 'if exponent <= 1:', 'if exponent < 1:'),
            ('next representable', 'bits + 1)', 'bits + 2)'),
            ('qualifier removal', 'comptime if not Self.derivatives:', 'if not Self.derivatives:'),
            ('helper generic', 'def _stored_half[\n    derivatives: Bool', 'def _stored_half[\n    derivatives: Int'),
            ('helper decorator', 'def _stored_half[', '@no_inline\ndef _stored_half['),
            ('missing helper', 'def _stored_half[', 'def _stored_half_missing['),
        ]
        for label, before, after in cases:
            with self.subTest(label=label):
                self.assertIn(before, original)
                self.reject_source_case(path, original, original.replace(before, after, 1),
                                        'stored-half dependency closure')
        self.reject_source_case(path, original, original + '\n' + original[original.index('def _stored_half['):],
                                'stored-half dependency closure')

    def test_fixed_pin_ideal_caller_mutations(self):
        path = 'extensions/carla/curve_bounds.mojo'
        original = (self.root/path).read_text()
        begin, end = m.BLOCK_BOUNDARIES['ideal_spiral']
        body = m.selected_block(original, begin, end)
        cases = [
            ('wrong step', '_stored_half(step)', '_stored_half(rate)'),
            ('wrong rate', '_stored_half(rate)', '_stored_half(step)'),
            ('missing half call', '_stored_half(step)', 'step'),
            ('extra half call', '_stored_half(step)', '_stored_half(_stored_half(step))'),
            ('helper keyword', '_stored_half(step)', '_stored_half(value=step)'),
            ('node rounding moved', '1.0 + nodes[i]', 'nodes[i]'),
            ('wrong subtraction', 'geometry.curvature_end - geometry.curvature_start', 'geometry.curvature_start - geometry.curvature_end'),
            ('wrong result index', 'trig[1]', 'trig[0]'),
            ('qualifier removal', 'comptime Expression', 'Expression'),
        ]
        # The live block contains comments/blank lines, so replace within its
        # exact raw region, not by regenerating a production module.
        start, stop = original.index(begin), original.index(end)
        raw = original[start:stop]
        for label, before, after in cases:
            with self.subTest(label=label):
                self.assertIn(before, raw)
                changed = original[:start] + raw.replace(before, after, 1) + original[stop:]
                self.reject_source_case(path, original, changed, 'operation graph changed: ideal_spiral')

    def test_fixed_pin_scalar_and_routing_mutations(self):
        cases = [
            ('extensions/carla/lane_geometry.mojo', 'step * 0.5 * weights[i] * cos(theta)',
             'weights[i] * (step * 0.5) * cos(theta)', 'operation graph changed: scalar_spiral'),
            ('extensions/carla/lane_geometry.mojo', '_curve_cos as cos,',
             '_curve_sin as cos,', 'operation graph changed: geometry_trig_aliases'),
            ('extensions/carla/curve_bounds.mojo', '    _stored_half,',
             '    _stored_difference as _stored_half,', 'source routing changed: ideal_caller'),
            ('extensions/carla/curve_bounds.mojo', '    _sincos_expression,',
             '    _sincos_jet as _sincos_expression,', 'source routing changed: ideal_caller'),
            ('extensions/carla/curve_trig.mojo', 'import _Interval, _Jet, _JetExpression',
             'import _Interval, _Jet, _Jet as _JetExpression', 'source routing changed: trig_dependencies'),
            ('extensions/carla/curve_trig.mojo', 'import atan, atan2, cos, floor',
             'import atan, atan2, sin as cos, floor', 'source routing changed: trig_dependencies'),
            ('extensions/carla/curve_trig.mojo', '@no_inline\ndef _curve_sincos',
             'def _curve_sincos', 'source-block start'),
        ]
        for path, before, after, diagnostic in cases:
            with self.subTest(path=path, mutation=before):
                original = (self.root/path).read_text()
                self.assertIn(before, original)
                self.reject_source_case(path, original, original.replace(before, after, 1), diagnostic)
        path = 'extensions/carla/curve_bounds.mojo'
        original = (self.root/path).read_text()
        self.reject_source_case(path, original, original + '\ncomptime _stored_half = _stored_difference\n',
                                'source routing changed: ideal_caller')
        self.reject_source_case(path, original, original + '\nfrom unexpected import _stored_half\n',
                                'source routing changed: ideal_caller')

    def test_fixed_pin_sentinel_and_declaration_mutations(self):
        path = 'extensions/carla/curve_bounds.mojo'
        original = (self.root/path).read_text()
        begin, end = m.BLOCK_BOUNDARIES['ideal_spiral']
        cases = [
            ('missing start', original.replace(begin, 'def _different_expression[', 1), 'source-block start'),
            ('duplicate start', original + '\n# ' + begin + '\n', 'source-block start'),
            ('duplicate end', original + '\n# ' + end + '\n', 'source-block end'),
            ('end before start', end + '\n' + original.replace(end, 'def _other_index(', 1), 'moved source-block boundary'),
            ('unbound decorator', original.replace(begin, '@no_inline\n' + begin, 1), 'unbound decorator'),
            ('indented start', original.replace(begin, '    ' + begin, 1), 'not top-level'),
        ]
        for label, changed, diagnostic in cases:
            with self.subTest(label=label):
                self.reject_source_case(path, original, changed, diagnostic)

    def test_strict_pin_keys_paths_and_sentinels(self):
        original = (self.root/m.PINS).read_bytes()
        cases = [
            ('top-level extra', lambda p: p.update(unexpected=True), 'top-level pin set'),
            ('block extra', lambda p: p['blocks']['ideal_spiral'].update(unexpected=True), 'operation pin keys'),
            ('block path', lambda p: p['blocks']['ideal_spiral'].update(path='other.mojo'), 'operation pin path'),
            ('block sentinel', lambda p: p['blocks']['ideal_spiral'].update(begin='def _spiral_jet('), 'source-block boundary pin'),
            ('dependency path', lambda p: p['dependencies'].update(paths=['other.mojo']), 'dependency closure pin'),
            ('dependency group', lambda p: p['dependencies'].update(group='eligibility'), 'dependency closure pin'),
            ('missing routing', lambda p: p['routing'].pop('ideal_caller'), 'routing pin set'),
            ('routing path', lambda p: p['routing']['ideal_caller'].update(path='other.mojo'), 'routing pin path'),
            ('extra projection', lambda p: p['ideal_projection'].update(unexpected=True), 'ideal-projection pin set'),
            ('projection count', lambda p: p['ideal_projection'].update(helper_projections=4), 'ideal-projection result pins'),
            ('commutation count', lambda p: p['ideal_projection'].update(rate_half_commutations=3), 'ideal-projection result pins'),
            ('historical source', lambda p: p['ideal_projection'].update(legacy_normalized_source='changed'), 'historical ideal source changed'),
        ]
        for label, mutate, diagnostic in cases:
            with self.subTest(label=label):
                pins = json.loads(original)
                mutate(pins)
                (self.root/m.PINS).write_text(json.dumps(pins))
                with self.assertRaisesRegex(m.CheckError, diagnostic):
                    m.verify_inputs(self.root)
                self.assertEqual(self.run_main(['--check']), 1)
                (self.root/m.PINS).write_bytes(original)

    def test_runtime_dependency_pin_path_and_key_controls(self):
        path = self.root/m.source_contracts.PINS
        original = path.read_bytes()
        for variant in ('missing', 'extra', 'path'):
            with self.subTest(variant=variant):
                pins = json.loads(original)
                group = pins['groups']['stored_arithmetic']
                key = m.DEPENDENCIES['paths'][0]
                if variant == 'missing':
                    group.pop(key)
                elif variant == 'extra':
                    group['other.mojo'] = group[key]
                else:
                    group['other.mojo'] = group.pop(key)
                path.write_text(json.dumps(pins))
                with self.assertRaisesRegex(m.CheckError, 'dependency closure.*path set'):
                    m.verify_inputs(self.root)
                self.assertEqual(self.run_main(['--check']), 1)
                path.write_bytes(original)

    def test_projection_claim_is_narrow_and_executed(self):
        pins = self.pins['ideal_projection']
        interval = (self.root/m.DEPENDENCIES['paths'][0]).read_text()
        helper = interval[interval.index('def _stored_half['):]
        legacy = pins['legacy_normalized_source']
        current = self.pins['blocks']['ideal_spiral']['normalized_source']
        result = m.ideal_projection.verify_projection(legacy, current, helper)
        self.assertEqual(result['helper_projections'], 5)
        self.assertEqual(result['rate_half_commutations'], 2)
        self.assertEqual(result['projected_ast_sha256'],
                         'f0f94e038fd4a783b3ed400ffd32801ca0c3bdc54980e2c408d44f50211b9e06')
        # Directly test the projection with the source guard bypassed locally:
        # an exact-current graph pin alone must not masquerade as the proof.
        for changed in (current.replace('_stored_half(step)', '_stored_half(rate)', 1),
                        current.replace('_stored_half(rate)', '_stored_half(step)', 1),
                        current.replace('_stored_half(step)', 'step', 1),
                        current.replace('1.0 + nodes[i]', 'nodes[i]', 1)):
            with self.assertRaises(ValueError):
                m.ideal_projection.verify_projection(legacy, changed, helper)
        with self.assertRaisesRegex(ValueError, 'initial expression'):
            m.ideal_projection.verify_projection(legacy, current, helper.replace('constant(0.5)', 'constant(0.25)', 1))
        with self.assertRaisesRegex(ValueError, 'non-error result'):
            m.ideal_projection.verify_projection(legacy, current, helper.replace('var actual =', 'result.value = value.value\n    var actual =', 1))

    def test_dependency_comments_and_equivalent_trig_words_allowed(self):
        path = self.root/'extensions/carla/curve_interval.mojo'
        path.write_text(path.read_text() + '\n# Benign dependency comment.\n')
        self.change('extensions/carla/curve_trig.mojo', '    -0.5,', '    -0.5000000000000,')
        m.verify_inputs(self.root)
        self.assertEqual(self.run_main(['--check']), 0)



    def test_complete_array_rhs_suffixes_rejected(self):
        for name in ('_COS_COEFFICIENTS', '_GL_NODES'):
            path, size = m.ARRAY_SPECS[name]
            original = (self.root/path).read_text()
            marker = f'comptime {name}: Array[Float64, {size}] = ['
            start = original.index(marker)
            stop = original.index(']', start + len(marker)) + 1
            zeros = ','.join(['0.0'] * size)
            for suffix in (f' if False else [{zeros}]', ' + [0.0]', '[0]',
                           '; comptime unexpected = 0',
                           ' \\\n    if False else [' + zeros + ']'):
                with self.subTest(array=name, suffix=suffix):
                    changed = original[:stop] + suffix + original[stop:]
                    self.reject_source_case(path, original, changed,
                                            'constant-array|constant literal')

    def test_array_docstring_decoys_rejected(self):
        for name in ('_COS_COEFFICIENTS', '_GL_NODES'):
            path, size = m.ARRAY_SPECS[name]
            original = (self.root/path).read_text()
            marker = f'comptime {name}: Array[Float64, {size}] = ['
            start = original.index(marker)
            stop = original.index(']', start + len(marker)) + 1
            declaration = original[start:stop]
            zeros = ', '.join(['0.0'] * size)
            replacement = f'comptime {name} : Array[Float64, {size}] = [{zeros}]'
            changed = original[:start] + replacement + original[stop:]
            closing = changed.index('"""', changed.index('"""') + 3)
            changed = changed[:closing] + '\n' + declaration + '\n' + changed[closing:]
            with self.subTest(array=name):
                self.reject_source_case(path, original, changed, 'stored constant words changed')

    def test_stored_geometry_shadow_import_and_redeclaration_rejected(self):
        path = 'extensions/carla/geometry.mojo'
        original = (self.root/path).read_text()
        for suffix in ('\n_GL_NODES = [0.0, 0.0, 0.0, 0.0, 0.0]\n',
                       '\nfrom unexpected import _GL_NODES\n',
                       '\ndef _GL_NODES() -> Float64:\n    return 0.0\n'):
            with self.subTest(suffix=suffix):
                self.reject_source_case(path, original, original + suffix,
                                        'source routing changed: stored_geometry')
        self.reject_source_case(path, original,
            original + '\ncomptime _GL_NODES : Array[Float64, 5] = [0.0,0.0,0.0,0.0,0.0]\n',
            'ambiguous constant array')

    def test_complete_array_literals_allow_comments_and_word_spellings(self):
        for name in ('_COS_COEFFICIENTS', '_GL_NODES'):
            path, size = m.ARRAY_SPECS[name]
            target = self.root/path
            original = target.read_text()
            marker = f'comptime {name}: Array[Float64, {size}] = ['
            start = original.index(marker)
            stop = original.index(']', start + len(marker)) + 1
            declaration = original[start:stop]
            declaration = declaration.replace(f'{name}:', f'{name} :', 1)
            declaration = declaration.replace('0.0,', '0.0000000,', 1)
            declaration = declaration.replace('[\n', '[  # literal-only array\n', 1)
            target.write_text(original[:start] + declaration + '  # trailing comment' + original[stop:])
        m.verify_inputs(self.root)
        self.assertEqual(self.run_main(['--check']), 0)



    def test_scalar_docstring_decoys_and_suffixes_rejected(self):
        path = 'extensions/carla/curve_trig.mojo'
        original = (self.root/path).read_text()
        for name in sorted(m.SCALAR_NAMES):
            marker = f'comptime {name} = Float64('
            start = original.index(marker)
            stop = original.index(')', start + len(marker)) + 1
            declaration = original[start:stop]
            replacement = f'comptime {name}=Float64(0.0)'
            changed = original[:start] + replacement + original[stop:]
            closing = changed.index('"""', changed.index('"""') + 3)
            changed = changed[:closing] + '\n' + declaration + '\n' + changed[closing:]
            with self.subTest(scalar=name, variant='docstring decoy'):
                self.reject_source_case(path, original, changed, 'stored scalar word changed')
            for suffix in (' if False else Float64(0.0)', ' + Float64(0.0)',
                           '; comptime unexpected = 0'):
                with self.subTest(scalar=name, suffix=suffix):
                    self.reject_source_case(path, original,
                        original[:stop] + suffix + original[stop:], 'scalar declaration|scalar literal')

    def test_scalar_logical_declaration_allows_same_word_spelling(self):
        path = self.root/'extensions/carla/curve_trig.mojo'
        text = path.read_text()
        for name in sorted(m.SCALAR_NAMES):
            marker = f'comptime {name} = Float64('
            start = text.index(marker)
            stop = text.index(')', start + len(marker)) + 1
            declaration = text[start:stop]
            literal = declaration[len(marker):-1]
            # Every pinned scalar has an ordinary finite decimal spelling.
            same_word = str(F(literal)) if '/' not in str(F(literal)) else literal
            replacement = f'comptime {name}=Float64({same_word})  # same stored word'
            text = text[:start] + replacement + text[stop:]
        path.write_text(text)
        m.verify_inputs(self.root)
        self.assertEqual(self.run_main(['--check']), 0)

    def test_function_sentinel_docstring_decoys_rejected(self):
        for block in ('ideal_spiral', 'scalar_spiral'):
            path = m.BLOCK_PATHS[block]
            original = (self.root/path).read_text()
            begin, end = m.BLOCK_BOUNDARIES[block]
            start, stop = original.index(begin), original.index(end)
            raw = original[start:stop]
            changed = original.replace(begin, begin.replace('(', ' (', 1)
                                       if '(' in begin else begin.replace('[', ' [', 1), 1)
            changed = changed.replace(end, end.replace('(', ' (', 1), 1)
            if block == 'ideal_spiral':
                changed = changed.replace('_stored_half(step)', '_stored_half(rate)', 1)
            else:
                changed = changed.replace('step * 0.5', 'step * 0.25', 1)
            closing = changed.index('"""', changed.index('"""') + 3)
            changed = changed[:closing] + '\n' + raw + end + '\n' + changed[closing:]
            with self.subTest(block=block):
                self.reject_source_case(path, original, changed, 'not an actual top-level token')



    def test_adjacent_number_tokens_and_empty_array_entries_rejected(self):
        cases = [
            ('extensions/carla/curve_trig.mojo', '    1.0,', '    1 .0,', 'constant literal'),
            ('extensions/carla/curve_trig.mojo', '    1.0,', '    1 e0,', 'constant literal'),
            ('extensions/carla/curve_trig.mojo', '    1.0,', '    1.0,,', 'constant literal'),
            ('extensions/carla/curve_trig.mojo', 'Float64(1048576.0)', 'Float64(1048576 .0)', 'scalar literal'),
            ('extensions/carla/curve_trig.mojo', 'Float64(1048576.0)', 'Float64(1048576 e0)', 'scalar literal'),
        ]
        for path, before, after, diagnostic in cases:
            with self.subTest(mutation=after):
                original = (self.root/path).read_text()
                self.assertIn(before, original)
                self.reject_source_case(path, original, original.replace(before, after, 1), diagnostic)

    def test_helper_projection_rejects_all_unapproved_result_uses(self):
        interval = (self.root/m.DEPENDENCIES['paths'][0]).read_text()
        helper = interval[interval.index('def _stored_half['):]
        for statement in ('result.value.low = 0.0', 'f(value=result)',
                          'result.some_method()', 'var alias = result'):
            with self.subTest(statement=statement):
                changed = helper.replace('var actual =', statement + '\n    var actual =', 1)
                with self.assertRaisesRegex(ValueError, 'unapproved ideal helper result use'):
                    m.ideal_projection.verify_helper_projection(changed)


if __name__ == '__main__':
    unittest.main()
