# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free fail-closed proof, identity, and cache controls."""

import copy
import contextlib
import gzip
import io
import json
import os
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch

import cache_key
import coverage_loop_proofs as loops
import coverage_io


def source(expression, body='pass', ending='\n'):
    return ending.join(['def f():', '    for item in ' + expression + ':',
                        '        ' + body, ''])


def model_generation(root, build, names=('module.mojo',)):
    """Model producer bytes for compiler-free controls, never native evidence."""
    manifest = (build / 'manifest.txt').read_bytes()
    fragments = []
    for name in names:
        module = name.removesuffix('.mojo').encode()
        fragment = b''.join(row for row in manifest.splitlines(keepends=True)
                            if len(row.split()) >= 2 and row.split()[1] == module)
        fragments.append(fragment)
        parts = [name.encode(), (root / name).read_bytes(),
                 (build / name).read_bytes(), fragment]
        record = b'COVORIGIN1 ' + b' '.join(str(len(part)).encode() for part in parts) + b'\n' + b''.join(parts)
        (build / (name + '.cov-origin')).write_bytes(record)
    checkpoint = (build / 'generation-inputs.json').read_bytes()
    index = (b'COVORIGIN_INDEX2 ' + str(len(names)).encode() + b' ' + str(len(manifest)).encode()
             + b' ' + str(len(checkpoint)).encode() + b'\n' + manifest + checkpoint)
    for name in names:
        raw = name.encode()
        index += str(len(raw)).encode() + b'\n' + raw
    (build / 'origins.ready').write_bytes(index)


class ConstantLoopTests(unittest.TestCase):
    def required(self, text):
        return {line: proof['required'] for line, proof in loops.constant_loops(text).items()}

    def test_literal_ranges_keep_the_only_reachable_outcome(self):
        for expression, required, count in [
                ('range(0)', 'F', 0), ('range(1)', 'T', 1),
                ('range(3)', 'T', 3), ('range(1, 1)', 'F', 0),
                ('range(2, 1)', 'F', 0), ('range(1, 22)', 'T', 21),
                (f'range({loops.MAX_ENDPOINT})', 'T', loops.MAX_ENDPOINT)]:
            with self.subTest(expression=expression):
                proof = loops.constant_loops(source(expression))[2]
                self.assertEqual((proof['required'], proof['cardinality']), (required, count))

    def test_direct_lists_count_elements_not_values(self):
        for expression, count in [('[]', 0), ('[0]', 1), ('[one, two,]', 2),
                                  ('[call(), (a, b), "a,b[for]", x[0]]', 4)]:
            with self.subTest(expression=expression):
                proof = loops.constant_loops(source(expression))[2]
                self.assertEqual(proof['cardinality'], count)
                self.assertEqual(proof['required'], 'T' if count else 'F')

    def test_dynamic_and_unsupported_expressions_are_not_proofs(self):
        expressions = ['range(n)', 'range(len(values))', 'range(CONSTANT)',
                       'range(steps + 1)', 'range(Int(3))', 'range(-1)',
                       'range(0, 3, 1)', 'range(stop=3)', 'range(True)',
                       f'range({loops.MAX_ENDPOINT + 1})', 'other.range(3)',
                       'iterable()', 'values', '[*values]', '[x for x in values]']
        for expression in expressions:
            with self.subTest(expression=expression):
                self.assertEqual(loops.constant_loops(source(expression)), {})

    def test_whole_module_shadowing_veto_covers_binding_forms(self):
        bindings = ['var range = custom\n', 'comptime range = custom\n',
                    'from other import range\n', 'from other import custom as range\n',
                    'import custom as range\n', 'from other import *\n',
                    'from other import (\n    *\n)\n',
                    'def range(n: Int):\n    return []\n',
                    'def other(range: Int):\n    pass\n',
                    'def other[range: Int]():\n    pass\n',
                    'struct Other:\n    var range: Int\n']
        for binding in bindings:
            for text in [binding + source('range(3)'), source('range(3)') + binding]:
                with self.subTest(binding=binding):
                    self.assertEqual(loops.constant_loops(text), {})

    def test_shadowing_loop_target_is_not_a_builtin_proof(self):
        self.assertEqual(loops.constant_loops('def f():\n    for range in range(3):\n        pass\n'), {})

    def test_list_name_or_wildcard_veto_prevents_literal_inference(self):
        for binding in ['var List = custom\n', 'from custom import List\n',
                        'def other(List: Int):\n    pass\n', 'from custom import *\n']:
            self.assertEqual(loops.constant_loops(binding + source('[one, two]')), {})

    def test_comments_and_quoted_binding_names_do_not_shadow(self):
        text = '"""def range():\nfrom custom import *\nList"""\n# range List\n'
        text += source('range(3)', 'print("range List [a,b]")')
        proofs = loops.constant_loops(text)
        self.assertEqual(len(proofs), 1)
        self.assertEqual(next(iter(proofs.values()))['cardinality'], 3)

    def test_multiline_literals_comments_and_endings_keep_source_line(self):
        for ending in ['\n', '\r\n', '\r']:
            text = 'def f():\n    for item in [ # header\n        one, # comma,\n        two,\n    ]:\n        pass\n'.replace('\n', ending)
            self.assertEqual(self.required(text), {2: 'T'})

    def test_nested_loops_in_a_top_level_function_are_supported(self):
        text = 'def f(n: Int):\n    for outer in range(n):\n        for inner in range(3):\n            pass\n'
        self.assertEqual(self.required(text), {3: 'T'})

    def test_unknown_name_resolution_contexts_keep_both_requirements(self):
        texts = ['struct S:\n    def f(self):\n        for x in range(3):\n            pass\n',
                 'trait T:\n    def f(self):\n        for x in range(3):\n            pass\n',
                 'def f[T: AnyType]():\n    for x in range(3):\n        pass\n',
                 'def outer():\n    def inner():\n        for x in range(3):\n            pass\n']
        for text in texts:
            self.assertEqual(loops.constant_loops(text), {})

    def test_scope_closes_after_nested_function_and_structure(self):
        text = 'struct S:\n    def nested(self):\n        pass\n' + source('range(3)')
        self.assertEqual(self.required(text), {5: 'T'})

    def test_malformed_or_unknown_tokenization_fails_closed(self):
        for text in ['def f():\n    for x in range(3:\n        pass\n',
                     'def f():\n    for x in range(3):\n        "unterminated\n',
                     'def f():\n    for x in range(3): pass\n']:
            self.assertEqual(loops.constant_loops(text), {})

    def test_positive_to_zero_and_dynamic_mutations_restore_correct_masks(self):
        self.assertEqual(self.required(source('range(3)')), {2: 'T'})
        self.assertEqual(self.required(source('range(0)')), {2: 'F'})
        self.assertEqual(self.required(source('range(n)')), {})
        self.assertEqual(self.required(source('[one]')), {2: 'T'})
        self.assertEqual(self.required(source('[*one]')), {})


class ProofBindingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='loop proof binding ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.build = self.root / 'build'
        self.build.mkdir()
        self.hits = self.build / 'hits'
        self.hits.mkdir()
        for name in loops.TOOL_INPUTS:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('tool input ' + name + '\n')
        (self.root / 'tools/coverage_loop_proofs.py').write_bytes(Path(loops.__file__).read_bytes())
        (self.root / 'tools/coverage_toolchain_identity.py').write_bytes(Path(loops.coverage_toolchain_identity.__file__).read_bytes())
        (self.root / 'tools/cache_key.py').write_bytes(Path(cache_key.__file__).read_bytes())
        (self.root / 'tools/coverage_io.py').write_bytes(Path(coverage_io.__file__).read_bytes())
        (self.root / 'tools/native_test_support.py').write_text(
            'import os, sys\nprint("PASS")\n'
            'sys.stderr.write("COVLINE:module:2:T\\n")\n'
            'raise SystemExit(int(os.environ.get("LOOP_FIXTURE_STATUS", "0")))\n')
        compiler = self.root / '.venv/bin/mojo'
        compiler.parent.mkdir(parents=True)
        compiler.write_text('compiler-free invocation identity\n')
        for base in [self.root, self.build]:
            suite = base / 'tests/test_fixture.mojo'
            suite.parent.mkdir(parents=True)
            suite.write_text('def main():\n    pass\n')
        self.source = self.root / 'module.mojo'
        self.source.write_text(source('range(3)'))
        (self.build / 'module.mojo').write_text('instrumented copy\n')
        (self.build / 'manifest.txt').write_text('L module 2\nL module 3\nB module 2\n')
        self.regenerate()
        self.envelope = loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')
        self.receipt = self.build / 'loop-proofs.json'

    def verify(self):
        return loops.verify(self.receipt, self.root, self.build, 'Mojo fixture', '-Werror')

    def regenerate(self):
        loops.begin_generation(self.root, self.build, 'Mojo fixture', '-Werror', sources=['module.mojo'])
        model_generation(self.root, self.build)

    def replace_receipt(self, receipt):
        envelope = {'receipt': receipt, 'sha256': loops.sha256(loops.canonical(receipt))}
        self.receipt.write_bytes(loops.canonical(envelope))

    def command(self, envelope=None, profile='raw'):
        current = self.envelope if envelope is None else envelope
        expected = loops.expected_capture_command(current['receipt']['execution'],
                                                   'tests/test_fixture.mojo', profile)
        return [loops._expand_path(word, self.root, self.build) for word in expected]

    def bind(self, capture, output, envelope=None):
        current = self.envelope if envelope is None else envelope
        loops.bind_capture(capture, output, current, self.command(current),
                           root=self.root, build=self.build)

    def test_sealed_manifest_retains_potential_and_required_totals(self):
        actual = self.verify()
        counts = actual['receipt']['denominator']
        self.assertEqual((counts['potential_total'], counts['required_total'], counts['proven_impossible']), (4, 3, 1))
        original = (self.build / 'manifest.txt').read_bytes()
        masked = loops.masked_manifest(original, actual).decode()
        self.assertIn('L module 2\nL module 3\nR module 2 T literal-range 3\n', masked)
        self.assertEqual((self.build / 'manifest.txt').read_bytes(), original)
        self.assertNotIn('COVLINE:', masked)

    def test_no_proof_for_a_branch_excluded_from_original_manifest(self):
        (self.build / 'manifest.txt').write_text('L module 2\nL module 3\n')
        self.regenerate()
        self.assertEqual(loops.build_receipt(self.root, self.build, 'Mojo fixture', '-Werror')['proofs'], [])

    def test_changed_source_invalidates_the_proof(self):
        self.source.write_text(source('range(n)'))
        with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
            self.verify()

    def test_changed_instrumented_source_invalidates_the_proof(self):
        (self.build / 'module.mojo').write_text('different probes\n')
        with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
            self.verify()

    def test_changed_tool_invalidates_the_proof(self):
        for name in loops.TOOL_INPUTS:
            path = self.root / name
            original = path.read_bytes()
            path.write_bytes(original + b'mutated\n')
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'Stale or modified'):
                self.verify()
            path.write_bytes(original)

    def test_changed_manifest_or_compiler_binding_is_rejected(self):
        for compiler, flags in [('other compiler', '-Werror'), ('Mojo fixture', '-O0')]:
            with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
                loops.verify(self.receipt, self.root, self.build, compiler, flags)
        (self.build / 'manifest.txt').write_text('L module 2\nB module 2\n')
        with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
            self.verify()

    def test_resealed_tampered_mask_is_independently_rejected(self):
        changed = copy.deepcopy(self.envelope['receipt'])
        changed['proofs'][0]['required'] = 'F'
        self.replace_receipt(changed)
        with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
            self.verify()

    def test_resealed_dropped_proof_or_changed_denominator_is_rejected(self):
        for field, value in [('proofs', []), ('denominator', {})]:
            changed = copy.deepcopy(self.envelope['receipt'])
            changed[field] = value
            self.replace_receipt(changed)
            with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
                self.verify()

    def test_bad_digest_schema_and_duplicate_json_keys_are_rejected(self):
        changed = copy.deepcopy(self.envelope)
        changed['sha256'] = '0' * 64
        self.receipt.write_bytes(loops.canonical(changed))
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            self.verify()
        changed = copy.deepcopy(self.envelope['receipt'])
        changed['schema'] = 'future-schema'
        self.replace_receipt(changed)
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            self.verify()
        self.receipt.write_text('{"receipt": {}, "receipt": {}}')
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.verify()

    def test_copied_unmeasured_and_test_inputs_are_bound_too(self):
        for name in ['tests/helper.mojo', 'unmeasured.mojo']:
            original, copied = self.root / name, self.build / name
            original.parent.mkdir(parents=True, exist_ok=True)
            copied.parent.mkdir(parents=True, exist_ok=True)
            original.write_text('helper input\n')
            copied.write_text('helper input\n')
        self.regenerate()
        loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')
        (self.root / 'tests/helper.mojo').write_text('different helper\n')
        with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
            self.verify()

    def test_malformed_original_manifest_and_compound_conflict_are_rejected(self):
        for raw in ['R module 2 T literal-range 3\n', 'B module 2\nB module 2\n',
                    'B module 2\nC module 2 0\n', 'B module nope\n']:
            (self.build / 'manifest.txt').write_text(raw)
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                loops.build_receipt(self.root, self.build, 'fixture', '')

    def test_escaped_source_identity_is_rejected(self):
        (self.build / 'manifest.txt').write_text('B ../outside 2\n')
        with self.assertRaisesRegex(ValueError, 'Invalid coverage source identity'):
            loops.build_receipt(self.root, self.build, 'fixture', '')

    def test_capture_receipt_rejects_missing_stale_and_tampered_captures(self):
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        output.write_text('PASSED\n')
        with gzip.open(capture, 'wb') as stream:
            stream.write(b'COVLINE:module:2:T\n')
        with self.assertRaises(FileNotFoundError):
            loops.verify_captures([capture], self.envelope)
        self.bind(capture, output)
        loops.verify_captures([capture], self.envelope)
        changed = copy.deepcopy(self.envelope)
        changed['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
            loops.verify_captures([capture], changed)
        capture.write_bytes(capture.read_bytes() + b'tampered')
        with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
            loops.verify_captures([capture], self.envelope)

    def test_capture_output_is_also_bound(self):
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        capture.write_bytes(b'capture')
        output.write_text('PASSED\n')
        self.bind(capture, output)
        output.write_text('FAILED\n')
        with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
            loops.verify_captures([capture], self.envelope)

    def test_generator_contents_invalidate_the_repository_cache_key(self):
        before = cache_key.cache_key(self.root, [])
        path = self.root / 'tools/coverage_loop_proofs.py'
        path.write_text(path.read_text() + '# new rule\n')
        self.assertNotEqual(cache_key.cache_key(self.root, []), before)

    def test_successful_capture_binds_actual_reduced_bytes(self):
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        command = self.command()
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(coverage_io.capture(command, output, capture,
                                                loop_proof=self.receipt, source_root=self.root), 0)
        loops.verify_captures([capture], self.envelope)
        with gzip.open(capture, 'rb') as stream:
            self.assertEqual(stream.read(), b'COVLINE:module:2:T\n')

    def test_failed_replacement_capture_cannot_reuse_old_success_receipt(self):
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        capture.write_bytes(b'old capture')
        output.write_text('PASS\n')
        self.bind(capture, output)
        with contextlib.redirect_stdout(io.StringIO()), patch.dict('os.environ', {'LOOP_FIXTURE_STATUS': '7'}):
            status = coverage_io.capture(self.command(), output, capture, loop_proof=self.receipt, source_root=self.root)
        self.assertEqual(status, 7)
        self.assertFalse(loops.capture_receipt_path(capture).exists())

    def test_failed_capture_preflight_also_invalidates_old_success_receipt(self):
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        capture.write_bytes(b'old capture')
        output.write_text('PASS\n')
        self.bind(capture, output)
        self.receipt.write_text('malformed')
        with patch.object(coverage_io.subprocess, 'Popen') as process:
            with self.assertRaises(ValueError):
                coverage_io.capture(['unused'], output, capture, loop_proof=self.receipt)
            process.assert_not_called()
        self.assertFalse(loops.capture_receipt_path(capture).exists())

    def test_report_wrapper_validates_then_supplies_only_temporary_masks(self):
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        capture.write_bytes(b'captured bytes')
        output.write_text('PASS\n')
        self.bind(capture, output)
        original = self.build / 'manifest.txt'
        original_bytes = original.read_bytes()
        observed_paths = []

        def reporter(command, captures):
            path = Path(command[-1])
            observed_paths.append(path)
            self.assertNotEqual(path, original)
            self.assertIn('R module 2 T literal-range 3', path.read_text())
            self.assertEqual(captures, [capture])
            return 0

        with patch.object(coverage_io, 'report', side_effect=reporter), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(coverage_io.report_with_loop_proofs(
                ['report', str(original)], [capture], root=self.root,
                build=self.build, compiler='Mojo fixture', flags='-Werror'), 0)
        self.assertEqual(original.read_bytes(), original_bytes)
        self.assertFalse(observed_paths[0].exists())

    def test_stale_capture_stops_before_the_reporter(self):
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        capture.write_bytes(b'captured bytes')
        output.write_text('PASS\n')
        self.bind(capture, output)
        capture.write_bytes(b'changed capture')
        with patch.object(coverage_io, 'report') as reporter:
            with self.assertRaisesRegex(ValueError, 'Stale or modified coverage capture'):
                coverage_io.report_with_loop_proofs(
                    ['report', str(self.build / 'manifest.txt')], [capture],
                    root=self.root, build=self.build, compiler='Mojo fixture', flags='-Werror')
            reporter.assert_not_called()

    def test_source_change_during_reporting_invalidates_success(self):
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        capture.write_bytes(b'captured bytes')
        output.write_text('PASS\n')
        self.bind(capture, output)

        def reporter(command, captures):
            self.source.write_text(source('range(n)'))
            return 0

        with patch.object(coverage_io, 'report', side_effect=reporter), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ValueError, 'Stale or modified|generation origin|Generation manifest|Staged input'):
                coverage_io.report_with_loop_proofs(
                    ['report', str(self.build / 'manifest.txt')], [capture],
                    root=self.root, build=self.build, compiler='Mojo fixture', flags='-Werror')

    def test_maintained_closure_binds_helpers_and_native_fixture_copies(self):
        names = ['tools/affected.py', 'tools/suite_key.py',
                 'tools/new_consumed_helper.py', 'tools/fixtures/carla_sum2_fp_state.c']
        for name in names:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('before\n')
        fixture = self.build / names[-1]
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_text('before\n')
        self.regenerate()
        loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')
        for name in names:
            path = self.root / name
            original = path.read_bytes()
            path.write_bytes(b'after\n')
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.verify()
            path.write_bytes(original)
        fixture.write_text('changed staged native fixture\n')
        with self.assertRaisesRegex(ValueError, 'Staged input'):
            self.verify()

    def test_new_maintained_input_cannot_silently_join_an_old_proof(self):
        (self.root / 'tools/later_helper.py').write_text('later\n')
        with self.assertRaisesRegex(ValueError, 'Stale or modified'):
            self.verify()

    def test_reseal_during_report_cannot_return_old_success(self):
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        capture.write_bytes(b'old capture')
        output.write_text('PASS\n')
        self.bind(capture, output)

        def reporter(command, captures):
            self.source.write_text(source('range(0)'))
            (self.build / 'module.mojo').write_text('new instrumented copy\n')
            self.regenerate()
            loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')
            return 0

        with patch.object(coverage_io, 'report', side_effect=reporter) as child, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ValueError, 'identity changed during reporting'):
                coverage_io.report_with_loop_proofs(
                    ['report', str(self.build / 'manifest.txt')], [capture],
                    root=self.root, build=self.build, compiler='Mojo fixture', flags='-Werror')
            child.assert_called_once()
        self.assertEqual(self.verify()['receipt']['proofs'][0]['required'], 'F')

    def test_alias_change_after_generation_cannot_be_resealed(self):
        before = ('from custom import custom_range as range\n\n'
                  'def f():\n    for item in range(3):\n        pass\n')
        after = before.replace('from custom import custom_range as range',
                               '# now resolves to builtin range')
        self.source.write_text(before)
        (self.build / 'module.mojo').write_text('custom-range stage with module:4 probes\n')
        (self.build / 'manifest.txt').write_text('L module 4\nL module 5\nB module 4\n')
        self.regenerate()
        original = loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')
        self.assertEqual(original['receipt']['proofs'], [])
        saved = self.receipt.read_bytes()
        self.source.write_text(after)
        with self.assertRaisesRegex(ValueError, 'generation origin'):
            loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')
        self.assertEqual(self.receipt.read_bytes(), saved)

    def test_generation_records_reject_truncation_duplicates_and_extra_bytes(self):
        index = self.build / 'origins.ready'
        origin = self.build / 'module.mojo.cov-origin'
        saved_index, saved_origin = index.read_bytes(), origin.read_bytes()
        for corrupted in [b'', saved_index[:-1], saved_index + b'extra',
                          saved_index.replace(b'COVORIGIN_INDEX2 1 ', b'COVORIGIN_INDEX2 01 ', 1)]:
            index.write_bytes(corrupted)
            with self.subTest(kind='index', payload=corrupted[:40]), self.assertRaises(ValueError):
                self.verify()
        index.write_bytes(saved_index)
        for corrupted in [saved_origin[:-1], saved_origin + b'\n',
                          saved_origin.replace(b'COVORIGIN1 ', b'COVORIGIN2 ', 1)]:
            origin.write_bytes(corrupted)
            with self.subTest(kind='origin'), self.assertRaises(ValueError):
                self.verify()
        origin.write_bytes(saved_origin)
        (self.build / 'extra.mojo.cov-origin').write_bytes(saved_origin)
        with self.assertRaisesRegex(ValueError, 'extra generation'):
            self.verify()

    def test_generation_fragment_cannot_change_the_denominator(self):
        origin = self.build / 'module.mojo.cov-origin'
        raw = origin.read_bytes()
        header, offset = loops._origin_header(raw, 0)
        parts = []
        for size in header[1:]:
            part, offset = loops._origin_part(raw, offset, int(size))
            parts.append(part)
        parts[-1] = b'L module 2\n'
        origin.write_bytes(b'COVORIGIN1 ' + b' '.join(str(len(part)).encode() for part in parts) + b'\n' + b''.join(parts))
        with self.assertRaisesRegex(ValueError, 'fragments do not reconstruct'):
            self.verify()

    def test_generation_pair_uses_exact_utf8_and_physical_line_bytes(self):
        for ending in ['\n', '\r\n', '\r']:
            original = source('["é", "λ"]', ending=ending).encode()
            self.source.write_bytes(original)
            (self.build / 'module.mojo').write_bytes(b'generated:' + original)
            self.regenerate()
            sealed = loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')
            self.assertEqual(sealed['receipt']['generation']['modules']['module.mojo']['source'], loops.sha256(original))
            self.verify()

    def test_custom_output_root_is_excluded_by_identity(self):
        target = self.root / 'custom/nested-stage'
        target.parent.mkdir()
        self.build.rename(target)
        self.build = target
        self.hits = target / 'hits'
        self.receipt = target / 'loop-proofs.json'
        self.assertEqual(self.verify(), self.envelope)

    def test_capture_command_edits_are_rejected(self):
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        capture.write_bytes(b'capture')
        output.write_text('PASS\n')
        self.bind(capture, output)
        path = loops.capture_receipt_path(capture)
        binding = json.loads(path.read_text())
        binding['command'] = ['different-compiler', 'wrong-suite.mojo']
        path.write_text(json.dumps(binding))
        with self.assertRaisesRegex(ValueError, 'Modified capture command provenance'):
            loops.verify_captures([capture], self.envelope)

    def test_actual_wrong_wrapper_compiler_flags_and_suite_fail_before_launch(self):
        correct = self.command()
        commands = []
        wrong = correct.copy(); wrong[1] = str(self.root / 'tools/other.py'); commands.append(wrong)
        wrong = correct.copy(); wrong[-3] = '-O0'; commands.append(wrong)
        wrong = correct.copy(); wrong[-1] = str(self.source); commands.append(wrong)
        wrong = correct.copy(); wrong[-5] = str(self.root / 'wrong-compiler'); commands.append(wrong)
        capture, output = self.hits / 'test_fixture.txt.gz', self.hits / 'test_fixture.out'
        for command in commands:
            with patch.object(coverage_io.subprocess, 'Popen') as process, self.assertRaises(ValueError):
                coverage_io.capture(command, output, capture, loop_proof=self.receipt, source_root=self.root)
            process.assert_not_called()

    def test_changed_compiler_executable_cannot_reuse_a_capture_contract(self):
        (self.root / '.venv/bin/mojo').write_text('changed compiler\n')
        with self.assertRaisesRegex(ValueError, 'compiler/execution identity'):
            loops.check_capture_inputs(self.envelope, self.root, self.build)

    def test_changed_native_compiler_bytes_invalidate_same_command(self):
        with tempfile.TemporaryDirectory() as directory:
            compiler = Path(directory) / 'cc'
            compiler.write_text('same-path native compiler, before\n')
            with patch.dict(os.environ, {'CC': str(compiler)}):
                envelope = loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')
                loops.check_capture_inputs(envelope, self.root, self.build)
                compiler.write_text('same-path native compiler, after\n')
                with self.assertRaisesRegex(ValueError, 'compiler/execution identity'):
                    loops.check_capture_inputs(envelope, self.root, self.build)
                with self.assertRaisesRegex(ValueError, 'Stale or modified'):
                    self.verify()

    def test_producer_edit_after_generation_cannot_be_resealed(self):
        tool = self.root / 'coverage/instrument.mojo'
        tool.write_bytes(tool.read_bytes() + b'changed producer\n')
        staged = self.build / 'coverage/instrument.mojo'
        staged.parent.mkdir(parents=True)
        staged.write_bytes(tool.read_bytes())
        with self.assertRaisesRegex(ValueError, 'generation origin checkpoint'):
            loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')

    def test_begin_invalidates_old_ready_before_failed_generation(self):
        loops.begin_generation(self.root, self.build, 'Mojo fixture', '-Werror', sources=['module.mojo'])
        self.assertEqual((self.build / 'origins.ready').read_bytes(), b'')
        with self.assertRaises(ValueError):
            self.verify()

    def test_changed_generation_checkpoint_requires_new_producer_run(self):
        self.source.write_text(source('range(0)'))
        loops.begin_generation(self.root, self.build, 'Mojo fixture', '-Werror', sources=['module.mojo'])
        with self.assertRaises(ValueError):
            loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')

    def test_generation_selection_and_embedded_checkpoint_are_bound(self):
        path = self.build / 'generation-inputs.json'
        saved = path.read_bytes()
        path.write_bytes(saved + b' ')
        with self.assertRaisesRegex(ValueError, 'generation origin checkpoint'):
            self.verify()
        path.write_bytes(saved)
        (self.root / 'other.mojo').write_text(source('range(1)'))
        self.regenerate()
        checkpoint = json.loads(path.read_bytes())
        checkpoint['sources'] = ['other.mojo']
        path.write_bytes(loops.canonical(checkpoint) + b'\n')
        model_generation(self.root, self.build)
        with self.assertRaisesRegex(ValueError, 'generation origin checkpoint'):
            loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')


if __name__ == '__main__':
    unittest.main()
