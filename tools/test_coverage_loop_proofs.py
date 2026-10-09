# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Compiler-free fail-closed proof, identity, and cache controls."""

import copy
import contextlib
import gzip
import io
import json
import os
import signal
import shutil
import subprocess
import time
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch

import cache_key
import coverage_loop_proofs as loops
import coverage_io
import check_coverage_loop_proofs as native_check


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

    def test_receipt_rederivation_checks_custom_stage_std_package_surfaces(self):
        # Compiler-free origin fixture: demonstrate the actual receipt path
        # rejects an extra package even though it is outside input_paths.
        external = tempfile.TemporaryDirectory(prefix='external-density-stage-')
        self.addCleanup(external.cleanup)
        stage = Path(external.name)/'custom-stage'
        self.build.rename(stage)
        self.build = stage
        self.hits = stage/'hits'
        self.receipt = stage/'loop-proofs.json'
        repo = Path(__file__).resolve().parents[1]
        name = loops.DENSITY_SOURCE
        module = name.removesuffix('.mojo')
        original = self.root/name
        staged = self.build/name
        original.parent.mkdir(parents=True, exist_ok=True)
        staged.parent.mkdir(parents=True, exist_ok=True)
        original.write_text(loops.reviewed_density_source(repo, successor=True))
        staged.write_text('compiler-free modeled instrumented density\n')
        (self.build/'module.mojo').write_bytes(self.source.read_bytes())
        (self.build/'module.mojo.cov-origin').unlink()
        (self.build/'manifest.txt').write_text('B '+module+' 149\nB '+module+' 223\n')
        loops.begin_generation(self.root, self.build, 'Mojo fixture', '-Werror', sources=[name])
        model_generation(self.root, self.build, names=(name,))
        envelope = loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')
        self.assertEqual({p['line'] for p in envelope['receipt']['proofs']}, {149, 223})
        for relative in ('std.mojoc', 'tests/std.mojopkg', 'extensions/deep/std.🔥'):
            path = self.build/relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'unreviewed package or alternate source')
            self.assertNotIn(Path(relative), set(cache_key.input_paths(self.build)))
            with self.assertRaisesRegex(ValueError, 'Stale or modified'):
                self.verify()
            path.unlink()
            self.assertEqual(self.verify()['sha256'], envelope['sha256'])

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

    @unittest.skipUnless(os.name == 'posix', 'POSIX capture deadline')
    def test_checker_deadline_removes_bound_stale_receipt_after_probe(self):
        adapter = self.root/'tools/native_test_support.py'
        adapter.write_text('import sys, time\nsys.stderr.write("COVLINE:module:2:T\\n")\n'
                           'sys.stderr.flush()\ntime.sleep(60)\n')
        self.regenerate()
        self.envelope = loops.seal(self.root, self.build, 'Mojo fixture', '-Werror')
        capture, output = self.hits/'test_fixture.txt.gz', self.hits/'test_fixture.out'
        capture.write_bytes(b'old capture')
        output.write_text('PASS\n')
        self.bind(capture, output)
        loops.verify_captures([capture], self.envelope)
        with patch.dict(os.environ):
            os.environ.pop(coverage_io.DEADLINE_ENV, None)
            result = native_check.capture_with_compiler_budget(
                self.command(), output, capture, loop_proof=self.receipt,
                source_root=self.root, success=False, seconds=2)
        self.assertEqual(result.returncode, 124)
        self.assertEqual(gzip.decompress(capture.read_bytes()), b'COVLINE:module:2:T\n')
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


class GuardedLoopTests(unittest.TestCase):
    """Each exact theorem fails closed independently of unproved siblings."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='guarded-loop-proof-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = Path(__file__).resolve().parents[1]
        for relative in loops.GUARDED_LOOP_SOURCE_SHA256:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            if relative == 'extensions/carla/opendrive.mojo':
                # A before-source infrastructure checkout has no feature
                # parser yet. Reconstruct only the immutable reviewed after
                # fixture through the separate, source-bound parser contract.
                directory = str(self.repo / 'tools/carla_lane_oracle')
                with patch.object(sys, 'path', [directory, *sys.path]):
                    import border_parser_contracts as border
                content = border.successor_source(self.repo).encode()
            elif relative == loops.DENSITY_SOURCE:
                content = loops.reviewed_density_source(self.repo).encode('utf-8')
            elif relative == 'extensions/carla/map.mojo':
                # Preserve historical premise mutants on either physical live
                # state, using the fully verified inverse only for after.
                from carla_lane_oracle import seed_count_contracts as seed_count
                content = seed_count.historical_source(self.repo).encode('utf-8')
            else:
                content = (self.repo / relative).read_bytes()
            self.assertEqual(loops.sha256(content),
                             loops.GUARDED_LOOP_SOURCE_SHA256[relative])
            destination.write_bytes(content)

    def prove(self, rule):
        return loops.guarded_loop_proof(self.root, rule)

    def test_exact_rule_inventory_and_required_true(self):
        rules = loops.GUARDED_LOOP_RULES
        self.assertEqual(len(rules), 26)
        self.assertEqual(sum(r[0] == 'extensions/carla/opendrive' for r in rules), 7)
        self.assertEqual(len({r[5] for r in rules}), len(rules))
        self.assertEqual(len({r[:2] for r in rules}), len(rules))
        for rule in rules:
            with self.subTest(proof_id=rule[5]):
                proof = self.prove(rule)
                self.assertIsNotNone(proof)
                self.assertEqual(proof['required'], 'T')
                self.assertEqual(proof['impossible'], 'F')
                self.assertGreaterEqual(proof['cardinality'], 1)
                if proof['kind'] in {'literal-range', 'literal-list'}:
                    self.assertEqual(proof['cardinality'], rule[3])
                else:
                    self.assertEqual(proof['cardinality'], 1)
                self.assertEqual(
                    set(proof['dependency_sha256']), {rule[0] + '.mojo', *rule[6]})

    def test_each_loop_header_mutation_revokes_its_proof(self):
        for rule in loops.GUARDED_LOOP_RULES:
            path = self.root / (rule[0] + '.mojo')
            original = path.read_bytes()
            lines = original.decode().splitlines(keepends=True)
            with self.subTest(proof_id=rule[5]):
                self.assertTrue(lines[rule[1]-1].lstrip().startswith('for '))
                # This diagnostic only alters source bytes; no invented
                # runtime hit or executable coverage fixture is produced.
                lines[rule[1]-1] = lines[rule[1]-1].replace(' in ', ' in [] # ', 1)
                path.write_text(''.join(lines))
                self.assertIsNone(self.prove(rule))
                path.write_bytes(original)
                self.assertIsNotNone(self.prove(rule))

    def test_every_dependency_change_and_absence_revokes(self):
        for rule in loops.GUARDED_LOOP_RULES:
            for name in (rule[0] + '.mojo', *rule[6]):
                path = self.root / name
                original = path.read_bytes()
                with self.subTest(proof_id=rule[5], dependency=name):
                    path.write_bytes(original + b'\n# unreviewed dependency change\n')
                    self.assertIsNone(self.prove(rule))
                    path.unlink()
                    self.assertIsNone(self.prove(rule))
                    path.write_bytes(original)
                    self.assertIsNotNone(self.prove(rule))

    def test_mutable_state_guards_remain_bound(self):
        cases = (
            ('density-partitioned-nonempty-groom',
             '        if len(groom.points) == 0:\n', '        if False:\n'),
            ('dominance-explicit-nonempty-cells',
             '    if len(two.cells) == 0:\n', '    if False:\n'),
            ('resumption-explicit-nonempty-cells',
             '    if len(certificate.cells) == 0:\n', '    if False:\n'),
            ('junction-retained-two-endpoint-breaks',
             '    var breaks: List[Float64] = [a, b]\n',
             '    var breaks = List[Float64]()\n'),
            ('winner-eight-positive-dyadic-cardinalities',
             '    for level in range(8):\n', '    for level in range(-1, 8):\n'),
            ('winner-fixed-twelve-metadata-elements',
             '                var metadata: Array[Int, 12] = [\n',
             '                var metadata: Array[Int, 0] = [\n'),
            ('border-positive-record-count-keeps-ids',
             '    if bordered == 0:\n', '    if False:\n'),
            ('border-outer-list-explicitly-nonempty',
             '        if len(borders[i]) == 0:\n', '        if False:\n'),
            ('border-inner-owned-nonempty-list',
             '        var inner: List[_Cubic] = [_Cubic(0, s, 0.0, 0.0, 0.0, 0.0)]\n',
             '        var inner = List[_Cubic]()\n'),
            ('border-cuts-retain-initial-section-start',
             '        var cuts: List[Float64] = [s]\n',
             '        var cuts = List[Float64]()\n'),
        )
        by_name = {rule[5]: rule for rule in loops.GUARDED_LOOP_RULES}
        for proof_id, before, after in cases:
            rule = by_name[proof_id]
            path = self.root / (rule[0] + '.mojo')
            original = path.read_text()
            with self.subTest(proof_id=proof_id):
                self.assertIn(before, original)
                path.write_text(original.replace(before, after, 1))
                self.assertIsNone(self.prove(rule))
                path.write_text(original)

    def test_rebuild_validation_is_the_mutated_same_call_guard(self):
        rule = next(r for r in loops.GUARDED_LOOP_RULES
                    if r[5] == 'density-validated-positive-cube-count')
        path = self.root / (rule[0] + '.mojo')
        original = path.read_text()
        start = original.index('    def rebuild(')
        end = original.index('    def _slot(', start)
        body = original[start:end]
        self.assertEqual(body.count('        self.validate()\n'), 1)
        changed = (original[:start]
                   + body.replace('        self.validate()\n', '        pass\n', 1)
                   + original[end:])
        self.assertEqual(changed[:start], original[:start])
        self.assertIn('        self.validate()\n', changed[:start])
        path.write_text(changed)
        self.assertIsNone(self.prove(rule))
        path.write_text(original)
        self.assertIsNotNone(self.prove(rule))

    def test_selected_lane_validation_and_its_three_calls_are_bound(self):
        names = ('rounded-line-validated-lane-list',
                 'rounded-arc-validated-lane-list',
                 'axis-search-validated-lane-list')
        selected = [r for r in loops.GUARDED_LOOP_RULES if r[5] in names]
        self.assertEqual(len(selected), 3)
        road = self.root / 'extensions/carla/road.mojo'
        original = road.read_text()
        guard = '        if lane < 0 or lane >= len(self.sections[section].lanes):\n'
        self.assertEqual(original.count(guard), 1)
        start = original.index('    def _check_lane(')
        end = original.index('    def _lane_record_boundaries(', start)
        self.assertIn(guard, original[start:end])
        road.write_text(original.replace(guard, '        if lane < 0:\n', 1))
        for rule in selected:
            self.assertIsNone(self.prove(rule))
        road.write_text(original)
        for rule in selected:
            path = self.root / (rule[0] + '.mojo')
            source_text = path.read_text()
            lines = source_text.splitlines(keepends=True)
            preceding = [i for i in range(rule[1]-1)
                         if lines[i].startswith('def ')]
            self.assertTrue(preceding)
            start = sum(len(line) for line in lines[:preceding[-1]])
            next_definition = source_text.find('\ndef ', start + 1)
            end = len(source_text) if next_definition < 0 else next_definition + 1
            body = source_text[start:end]
            call = '    road._check_lane(section, lane)\n'
            self.assertEqual(body.count(call), 1)
            path.write_text(source_text[:start] + body.replace(call, '    pass\n', 1)
                            + source_text[end:])
            with self.subTest(proof_id=rule[5]):
                self.assertIsNone(self.prove(rule))
            path.write_text(source_text)
            self.assertIsNotNone(self.prove(rule))

    def test_groom_length_and_both_partition_endpoints_are_bound(self):
        rule = next(r for r in loops.GUARDED_LOOP_RULES
                    if r[5] == 'density-partitioned-nonempty-groom')
        groom = self.root / 'extensions/humanoid/skeleton/head/hair/groom.mojo'
        original = groom.read_text()
        start = original.index('    def __len__(')
        end = original.index('    def add(', start)
        body = original[start:end]
        self.assertEqual(body.count('        return len(self.starts) - 1\n'), 1)
        groom.write_text(original[:start]
                         + body.replace('        return len(self.starts) - 1\n',
                                        '        return 0\n', 1)
                         + original[end:])
        self.assertIsNone(self.prove(rule))
        groom.write_text(original)
        density = self.root / (rule[0] + '.mojo')
        original = density.read_text()
        start = original.index('    def rebuild(')
        end = original.index('    def _slot(', start)
        body = original[start:end]
        for before, after in (
            ('        if len(groom.starts) == 0 or groom.starts[0] != 0:\n',
             '        if len(groom.starts) == 0:\n'),
            ('        if groom.starts[len(groom.starts) - 1] != len(groom.points):\n',
             '        if False:\n'),
        ):
            self.assertEqual(body.count(before), 1)
            density.write_text(original[:start] + body.replace(before, after, 1)
                               + original[end:])
            self.assertIsNone(self.prove(rule))
            density.write_text(original)
        self.assertIsNotNone(self.prove(rule))

    def test_active_callers_and_inner_replacement_premises_are_bound(self):
        active = next(r for r in loops.GUARDED_LOOP_RULES
                      if r[5] == 'border-active-maintained-nonempty-callers')
        inner = next(r for r in loops.GUARDED_LOOP_RULES
                     if r[5] == 'border-inner-owned-nonempty-list')
        path = self.root / (active[0] + '.mojo')
        original = path.read_text()
        start = original.index('def _border_widths(')
        end = original.index('def _lane_records(', start)
        body = original[start:end]
        self.assertEqual(body.count('_active('), 2)
        for before, after in (
            ('        if len(borders[i]) == 0:\n', '        if False:\n'),
            ('                if ids[j] == id - Int(side) and len(borders[j]) > 0:\n',
             '                if ids[j] == id - Int(side):\n'),
            ('            if found < 0:\n', '            if False:\n'),
            ('            inner = borders[found].copy()\n',
             '            inner = List[_Cubic]()\n'),
        ):
            with self.subTest(premise=before.strip()):
                self.assertEqual(body.count(before), 1)
                path.write_text(original[:start] + body.replace(before, after, 1)
                                + original[end:])
                self.assertIsNone(self.prove(active))
                self.assertIsNone(self.prove(inner))
                path.write_text(original)
                self.assertIsNotNone(self.prove(active))
                self.assertIsNotNone(self.prove(inner))

    def test_groom_mutation_does_not_disable_independent_count_rule(self):
        rules = {rule[5]: rule for rule in loops.GUARDED_LOOP_RULES}
        groom = self.root / 'extensions/humanoid/skeleton/head/hair/groom.mojo'
        original = groom.read_bytes()
        groom.write_bytes(original + b'\n# changed length producer\n')
        self.assertIsNone(self.prove(rules['density-partitioned-nonempty-groom']))
        self.assertIsNotNone(self.prove(rules['density-validated-positive-cube-count']))

    def test_new_private_caller_alias_or_comment_fails_closed(self):
        rule = next(r for r in loops.GUARDED_LOOP_RULES
                    if r[5] == 'border-active-maintained-nonempty-callers')
        extra = self.root / 'tests/test_added_border_caller.mojo'
        extra.parent.mkdir(parents=True, exist_ok=True)
        for body in (
            'from extensions.carla.opendrive import _active\n',
            'alias alternate = _active\n',
            '# conservative unknown reference to _active\n',
        ):
            with self.subTest(body=body):
                extra.write_text(body)
                self.assertIsNone(self.prove(rule))
                extra.unlink()
                self.assertIsNotNone(self.prove(rule))

    def test_mask_keeps_true_and_every_nonloop_obligation(self):
        for rule in loops.GUARDED_LOOP_RULES:
            proof = self.prove(rule)
            module, number = rule[:2]
            raw = (f'L {module} {number}\nB {module} {number}\n'
                   f'L {module} {number+1}\nC {module} {number+1} 0\n'
                   f'M {module} {number+1} 0\n').encode()
            receipt = {'manifest_sha256': loops.sha256(raw),
                       'proofs': [{'module': module, **proof}]}
            envelope = {'receipt': receipt,
                        'sha256': loops.sha256(loops.canonical(receipt))}
            with self.subTest(proof_id=rule[5]):
                masked = loops.masked_manifest(raw, envelope).decode().splitlines()
                expected = raw.decode().splitlines()
                expected[1] = (f'R {module} {number} T {proof["kind"]} '
                               f'{proof["cardinality"]}')
                self.assertEqual(masked[1:], expected)
                receipt['proofs'] = []
                envelope['sha256'] = loops.sha256(loops.canonical(receipt))
                self.assertEqual(loops.masked_manifest(raw, envelope).decode().splitlines()[1:],
                                 raw.decode().splitlines())

    def map_owned_list_rules(self):
        names = {
            'query-retained-certificate-list',
            'query-nonempty-winner-rescan',
            'query-nonempty-competitor-rescan',
            'query-nonempty-prefix-certificates',
        }
        rules = [rule for rule in loops.GUARDED_LOOP_RULES if rule[5] in names]
        self.assertEqual({rule[1] for rule in rules}, {2272, 2279, 2301, 2378})
        return rules

    def test_map_owned_list_admission_appends_and_alias_boundaries_are_bound(self):
        path = self.root / 'extensions/carla/map.mojo'
        original = path.read_text()
        begin = original.index('    def _closest_lane_certificate_with_work(')
        end = original.index('    def _resume_on_segment_certificate(', begin)
        body = original[begin:end]
        cases = (
            ('        var best = -1\n', '        var best = 0\n'),
            ('        if best < 0:\n            return None\n',
             '        if False:\n            return None\n'),
            ('                best = len(indices)\n',
             '                best = 0\n'),
            ('            indices.append(index)\n', '            pass\n'),
            ('            certificates.append(result[1].copy())\n',
             '            pass\n'),
            ('            indices.append(index)\n',
             '            try:\n                indices.append(index)\n'
             '            except:\n                pass\n'),
            ('        if best < 0:\n',
             '        ref escaped = indices\n        escaped.clear()\n'
             '        if best < 0:\n'),
            ('        if best < 0:\n',
             '        ref escaped = certificates\n        escaped.clear()\n'
             '        if best < 0:\n'),
            ('        if best < 0:\n',
             '        unreviewed_outer_list_callback(indices, certificates)\n'
             '        if best < 0:\n'),
        )
        rules = self.map_owned_list_rules()
        for before, after in cases:
            with self.subTest(premise=before, replacement=after):
                self.assertEqual(body.count(before), 1)
                changed = original[:begin] + body.replace(before, after, 1) + original[end:]
                path.write_text(changed)
                for rule in rules:
                    self.assertIsNone(self.prove(rule))
                path.write_text(original)
                for rule in rules:
                    proof = self.prove(rule)
                    self.assertEqual((proof['required'], proof['impossible']), ('T', 'F'))

    def test_map_owned_list_each_exact_header_withholds_on_local_clear(self):
        path = self.root / 'extensions/carla/map.mojo'
        original = path.read_text()
        rules = self.map_owned_list_rules()
        for rule in rules:
            with self.subTest(header=rule[1]):
                lines = original.splitlines(keepends=True)
                line = lines[rule[1] - 1]
                self.assertIn(' in ' + rule[4] + ':', line)
                outer = 'indices' if 'indices' in rule[4] else 'certificates'
                indent = line[:len(line) - len(line.lstrip())]
                lines.insert(rule[1] - 1, indent + outer + '.clear()\n')
                path.write_text(''.join(lines))
                for affected in rules:
                    self.assertIsNone(self.prove(affected))
                path.write_text(original)
                for affected in rules:
                    self.assertIsNotNone(self.prove(affected))

    def hair_rules(self):
        return [rule for rule in loops.GUARDED_LOOP_RULES
                if rule[0] == 'extensions/humanoid/skeleton/head/hair/strands']

    def test_hair_constructor_current_state_and_both_shading_borrows_are_bound(self):
        prefix = 'extensions/humanoid/skeleton/head/hair/'
        cases = (
            ('strands.mojo', 'if segments <= 0:', 'if segments < 0:'),
            ('strands.mojo', 'self._topology = groom.starts.copy()',
             'self._topology = List[Int]()'),
            ('strands.mojo', '        self._check_geometry(assets)\n',
             '        pass\n'),
            ('strands.mojo', '        self.density.rebuild(self.groom)\n',
             '        pass\n'),
            ('strands.mojo',
             'if len(self.groom.starts) != len(self._topology):', 'if False:'),
            ('strands.mojo', 'if self.groom.starts != self._topology:',
             'if False:'),
            ('density.mojo',
             'if len(groom.starts) == 0 or groom.starts[0] != 0:', 'if False:'),
            ('density.mojo',
             'if groom.starts[len(groom.starts) - 1] != len(groom.points):',
             'if False:'),
            ('density.mojo',
             'if groom.starts[strand] > groom.starts[strand + 1]:', 'if False:'),
            ('groom.mojo', 'return len(self.starts) - 1', 'return 0'),
            ('strands.mojo', '        self._shadow_depths(lights)\n',
             '        self.groom.points.clear()\n        self._shadow_depths(lights)\n'),
            ('strands.mojo', '        self._upload(assets)\n',
             '        self.groom.starts.clear()\n        self._upload(assets)\n'),
            # These are separate public and private immutable borrow boundaries.
            ('shading.mojo', 'def shade_groom_into(\n    groom: HairGroom,',
             'def shade_groom_into(\n    mut groom: HairGroom,'),
            ('shading.mojo', 'def _shade_groom_into(\n    groom: HairGroom,',
             'def _shade_groom_into(\n    mut groom: HairGroom,'),
            ('strands.mojo', '        self._shadow_depths(lights)\n',
             '        ref alias = self._topology\n'
             '        alias.clear()\n        self._shadow_depths(lights)\n'),
        )
        rules = self.hair_rules()
        self.assertEqual(len(rules), 2)
        for name, before, after in cases:
            path = self.root / (prefix + name)
            original = path.read_text()
            with self.subTest(source=name, premise=before):
                self.assertEqual(original.count(before), 1)
                path.write_text(original.replace(before, after, 1))
                for rule in rules:
                    self.assertIsNone(self.prove(rule))
                path.write_text(original)
                for rule in rules:
                    self.assertIsNotNone(self.prove(rule))

    def test_hair_census_rejects_direct_calls_aliases_writes_and_unknown_references(self):
        rules = self.hair_rules()
        extra = self.root / 'tests/new_unreviewed_hair_access.mojo'
        cases = (
            'def added(hair):\n    hair._shadow_depths([])\n',
            'def added(hair, assets):\n    hair._upload(assets)\n',
            'def added(hair):\n    var alias = hair._upload\n',
            'def added(mut hair):\n    ref alias = hair._topology\n    alias.clear()\n',
            'def added(mut hair):\n    hair._topology = [0]\n',
            '# conservative unknown _shadow_depths reference\n',
            '# conservative unknown _topology reference\n',
        )
        for body in cases:
            with self.subTest(body=body):
                extra.write_text(body)
                for rule in rules:
                    self.assertIsNone(self.prove(rule))
                extra.unlink()
                for rule in rules:
                    self.assertIsNotNone(self.prove(rule))
        # Ordinary public edits before shade are handled by its current-state
        # guards. They do not rely on an exhaustive list of public mutators.
        extra.write_text('def added(mut hair, assets):\n'
                         '    hair.groom.points.clear()\n'
                         '    hair.shade(assets, [], Vector3(), Vector3())\n')
        for rule in rules:
            self.assertIsNotNone(self.prove(rule))
        extra.unlink()
        # The lexical collisions are source-bound too: adding a hair write
        # there must not pass merely because the set of paths stays unchanged.
        for name in ('extensions/carla/agents_route.mojo',
                     'tests/test_carla_route_search.mojo'):
            path = self.root / name
            original = path.read_text()
            path.write_text(original + cases[3])
            for rule in rules:
                self.assertIsNone(self.prove(rule))
            path.write_text(original)

    def test_hair_census_requires_named_rows_bound_paths_and_successful_reads(self):
        for rule in self.hair_rules():
            key = (rule[1], rule[5])
            with patch.dict(loops.HAIR_RETAINED_RULE_CENSUS, clear=True):
                self.assertIsNone(self.prove(rule))
            with patch.dict(loops.HAIR_RETAINED_RULE_CENSUS, {key: ()}):
                self.assertIsNone(self.prove(rule))
            changed = list(rule)
            changed[5] += '-unreviewed'
            self.assertIsNone(self.prove(tuple(changed)))
            changed = list(rule)
            changed[6] = tuple(name for name in rule[6]
                               if name != 'tests/test_carla_route_search.mojo')
            self.assertIsNone(self.prove(tuple(changed)))
            with patch.object(loops.cache_key, 'input_paths',
                              side_effect=OSError('unreadable census')):
                self.assertIsNone(self.prove(rule))
            self.assertIsNotNone(self.prove(rule))

    def test_hair_census_mutation_preserves_independent_historical_and_density_rows(self):
        rules = self.hair_rules()
        extra = self.root / 'tests/new_unreviewed_hair_access.mojo'
        extra.write_text('# unknown _upload caller\n')
        for rule in rules:
            self.assertIsNone(self.prove(rule))
        historical = loops.reviewed_nonempty_loops(self.root, rules[0][0])
        self.assertEqual(set(historical), {195, 201})
        density = [rule for rule in loops.GUARDED_LOOP_RULES
                   if rule[0].endswith('/hair/density')]
        for rule in density:
            self.assertIsNotNone(self.prove(rule))
        extra.unlink()
        self.assertEqual(set(loops.reviewed_nonempty_loops(self.root, rules[0][0])),
                         {180, 191, 195, 201})

    def test_resumption_transaction_keeps_cells_on_every_false_return(self):
        rules = [r for r in loops.GUARDED_LOOP_RULES
                 if r[5] == 'resumption-transaction-retains-cells']
        self.assertEqual(len(rules), 1)
        rule = rules[0]
        self.assertEqual(rule[:5], ('extensions/carla/lane_refinement', 1314,
                         'reviewed-nonempty-iterator', None, 'certificate.cells'))
        self.assertEqual(rule[6:], ((), ()))
        path = self.root / (rule[0]+'.mojo')
        original = path.read_text()

        def span(name):
            start = original.index('def '+name+'(')
            end = original.find('\ndef ', start+1)
            end = len(original) if end < 0 else end+1
            return start, end, original[start:end]

        ha, hb, helper = span('_try_rounded_arc_witness')
        ca, cb, caller = span('_continue_lane_certificate')
        ra, rb, reserve = span('_reserve_rounded_arc_box')
        false_lines = [(i, line) for i, line in enumerate(helper.splitlines(True))
                       if line.strip() == 'return False']
        self.assertEqual(len(false_lines), 9)
        mutations = []
        for i, line in false_lines:
            rows = helper.splitlines(True)
            indent = line[:len(line)-len(line.lstrip())]
            rows.insert(i, indent+'certificate.cells.clear()\n')
            mutations.append(('clear before False '+str(i),
                              original[:ha]+''.join(rows)+original[hb:]))
        for name, block, start, end, before, after in (
            ('replacement returns False', helper, ha, hb,
             '    return True\n', '    return False\n'),
            ('missing same-call nonempty guard', caller, ca, cb,
             '    if len(certificate.cells) == 0:\n', '    if False:\n'),
            ('successful replacement falls through', caller, ca, cb,
             '    if _try_rounded_arc_witness(\n', '    if not _try_rounded_arc_witness(\n'),
            ('counter reserve clears cover', reserve, ra, rb,
             '    certificate.nodes += 1\n', '    certificate.cells.clear()\n'),
        ):
            self.assertEqual(block.count(before), 1)
            mutations.append((name, original[:start]+block.replace(before, after, 1)+original[end:]))
        rows = original.splitlines(True)
        self.assertEqual(rows[1313].strip(), 'for cell in certificate.cells:')
        rows.insert(1313, '    ref alias = certificate.cells\n    alias.clear()\n')
        mutations.append(('alias before second traversal', ''.join(rows)))
        self.assertEqual(len(mutations), 14)
        for name, text in mutations:
            with self.subTest(premise=name):
                self.assertNotEqual(text, original)
                path.write_text(text)
                self.assertIsNone(self.prove(rule))
                path.write_text(original)
                proof = self.prove(rule)
                self.assertEqual((proof['required'], proof['impossible']), ('T', 'F'))
                self.assertEqual(proof['cardinality'], 1)

    def test_starts_finite_validation_and_inconclusive_sites_are_not_added(self):
        rules = loops.GUARDED_LOOP_RULES
        self.assertFalse(any(r[0] == 'extensions/carla/opendrive' and
                             'range(len(starts))' == r[4] for r in rules))
        self.assertFalse(any(r[0] == 'extensions/carla/opendrive' and
                             'cubic.a' in r[4] for r in rules))
        self.assertFalse(any(r[0] == 'renderers/renderer' for r in rules))
        self.assertFalse(any(r[0].endswith('/hair/density') and r[1] in (148, 220)
                             for r in rules))
        self.assertEqual({r[1] for r in rules if r[0].endswith('/hair/strands')},
                         {180, 191})


@unittest.skipUnless(os.name == 'posix', 'POSIX runtime alarm and capture groups')
class NativeCheckerBoundaryTests(unittest.TestCase):
    def test_runtime_alarm_is_first_and_stays_armed(self):
        body = native_check.PRODUCTION_DRIVER.split('def main() raises:\n', 1)[1]
        self.assertTrue(body.startswith('    assert_equal(external_call["alarm", UInt32](UInt32(5)), UInt32(0))\n'))
        self.assertEqual(body.count('external_call["alarm"'), 1)
        self.assertNotIn('alarm', body.splitlines()[-1])
        self.assertIn('external_call["pause", Int32]()', native_check.HANG_DRIVER)
        self.assertNotIn('sleep', native_check.HANG_DRIVER)
        self.assertEqual(native_check.RUNTIME_SECONDS, 5)

    def test_exact_command_and_proof_reach_normal_capture_with_absolute_deadline(self):
        command = ['bound-mojo', 'run', '-I', 'bound-stage', 'bound-suite.mojo']
        with patch.object(native_check, 'run') as run, \
                patch.object(native_check.time, 'monotonic', return_value=100), \
                patch.object(coverage_io, 'shared_deadline', return_value=None):
            native_check.capture_with_compiler_budget(command, Path('out'), Path('err.gz'),
                loop_proof=Path('proof.json'), source_root=Path('source'))
        args, kwargs = run.call_args
        self.assertEqual(args[0], [sys.executable, str(native_check.ROOT/'tools/coverage_io.py'),
            'capture', '--out', 'out', '--err', 'err.gz', '--loop-proof', 'proof.json',
            '--loop-proof-root', 'source', '--', *command])
        self.assertEqual(float(kwargs['env'][coverage_io.DEADLINE_ENV]), 280)
        self.assertNotIn('timeout', kwargs)
        self.assertTrue(kwargs['success'])

    def test_inherited_deadline_is_never_extended(self):
        for inherited, expected in ((110, 110), (400, 280), (99, 99)):
            with self.subTest(inherited=inherited), patch.object(native_check, 'run') as run, \
                    patch.object(native_check.time, 'monotonic', return_value=100), \
                    patch.object(coverage_io, 'shared_deadline', return_value=inherited):
                native_check.capture_with_compiler_budget(['command'], 'out', 'err', success=False)
                self.assertEqual(float(run.call_args.kwargs['env'][coverage_io.DEADLINE_ENV]), expected)
                self.assertFalse(run.call_args.kwargs['success'])

    def test_invalid_bounds_or_incomplete_proofs_do_not_launch(self):
        for seconds in (0, -1, 181, float('inf'), float('nan'), True, '5'):
            with self.subTest(seconds=seconds), patch.object(native_check, 'run') as run:
                with self.assertRaises(RuntimeError):
                    native_check.capture_with_compiler_budget(['command'], 'out', 'err', seconds=seconds)
                run.assert_not_called()
        for arguments in ({'loop_proof': Path('proof')}, {'source_root': Path('root')}):
            with patch.object(native_check, 'run') as run, self.assertRaises(RuntimeError):
                native_check.capture_with_compiler_budget(['command'], 'out', 'err', **arguments)
            run.assert_not_called()

    def test_ignored_or_blocked_alarm_is_refused(self):
        with patch.object(native_check.signal, 'getsignal', return_value=signal.SIG_IGN), \
                patch.object(native_check, 'run') as run, self.assertRaises(RuntimeError):
            native_check.capture_with_compiler_budget(['command'], 'out', 'err')
        run.assert_not_called()
        previous = signal.pthread_sigmask(signal.SIG_BLOCK, [signal.SIGALRM])
        try:
            with patch.object(native_check, 'run') as run, self.assertRaises(RuntimeError):
                native_check.capture_with_compiler_budget(['command'], 'out', 'err')
            run.assert_not_called()
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous)

    def test_integration_deadline_reaps_descendants_and_private_environment(self):
        # Exercise the maintained watchdog through this helper's actual CLI.
        from test_coverage_lifecycle import CoverageLifecycleTests, WORKER
        with tempfile.TemporaryDirectory(prefix='loop checker deadline ') as directory:
            root = Path(directory)
            worker = root/'worker.py'
            worker.write_text(WORKER)
            try:
                with patch.dict(os.environ):
                    os.environ.pop(coverage_io.DEADLINE_ENV, None)
                    result = native_check.capture_with_compiler_budget(
                        [sys.executable, str(worker), str(root), 'child', 'valid'],
                        root/'out', root/'err.gz', success=False, seconds=2)
                self.assertEqual(result.returncode, 124)
                for role in ('child', 'grandchild'):
                    pid = int((root/(role+'.pid')).read_text())
                    until = time.monotonic()+2
                    while not CoverageLifecycleTests.stopped(self, pid):
                        self.assertLess(time.monotonic(), until, 'capture left live descendant')
                        time.sleep(.01)
                self.assertFalse(Path((root/'temporary').read_text()).exists())
                self.assertFalse(loops.capture_receipt_path(root/'err.gz').exists())
            finally:
                for path in root.glob('*.pid'):
                    with contextlib.suppress(ProcessLookupError):
                        os.kill(int(path.read_text()), signal.SIGKILL)


class DensityBoundaryLoopTests(unittest.TestCase):
    """Keep historical obligations and admit only the exact local repair."""

    def setUp(self):
        GuardedLoopTests.setUp(self)
        self.density = loops.DENSITY_SOURCE.removesuffix('.mojo')
        self.strands = 'extensions/humanoid/skeleton/head/hair/strands'
        self.path = self.root / loops.DENSITY_SOURCE
        self.before = self.path.read_text()
        self.after = loops.reviewed_density_source(self.repo, successor=True)
        self.hair_rules = [rule for rule in loops.GUARDED_LOOP_RULES
                           if rule[0] in {self.density, self.strands}]

    def assert_paired_rows(self, successor):
        text = self.after if successor else self.before
        self.path.write_text(text)
        digest = loops.DENSITY_AFTER_SHA256 if successor else loops.DENSITY_BEFORE_SHA256
        density = loops.reviewed_nonempty_loops(self.root, self.density)
        expected = {101, 138, 149, 223} if successor else {100, 137}
        self.assertEqual(set(density), expected)
        for rule in self.hair_rules:
            proof = loops.guarded_loop_proof(self.root, rule)
            self.assertIsNotNone(proof)
            line = loops._DENSITY_SUCCESSOR_LINES[rule[1]] if successor and rule[0] == self.density else rule[1]
            self.assertEqual((proof['line'], proof['required'], proof['impossible']), (line, 'T', 'F'))
            self.assertEqual(proof['proof_id'], rule[5])
            self.assertEqual(proof['dependency_sha256'][loops.DENSITY_SOURCE], digest)
            header = (self.root / (rule[0]+'.mojo')).read_text().splitlines()[line-1]
            self.assertIn(' in '+proof['expression']+':', header)
        strands = loops.reviewed_nonempty_loops(self.root, self.strands)
        self.assertEqual(set(strands), {180, 191, 195, 201})
        if successor:
            self.assertEqual((density[149]['cardinality'], density[149]['maximum_cardinality']), (1, None))
            self.assertEqual((density[223]['cardinality'], density[223]['minimum_cardinality'], density[223]['maximum_cardinality']), (1, 16, 256))
            for line in (149, 223):
                self.assertEqual((density[line]['required'], density[line]['impossible']), ('T', 'F'))
                self.assertIn(' in '+density[line]['expression']+':', text.splitlines()[line-1])
        else:
            self.assertNotIn(148, density)
            self.assertNotIn(220, density)
            self.assertEqual(loops.repaired_density_loops(self.root), {})
        return density

    def test_exact_before_after_pair_preserves_four_old_rows_and_live_hashes(self):
        for successor in (False, True):
            with self.subTest(successor=successor):
                self.assert_paired_rows(successor)
                self.assertEqual(loops.reviewed_density_source(self.root), self.before)
                self.assertEqual(loops.reviewed_density_source(self.root, successor=True), self.after)
        self.assertEqual(loops.GUARDED_LOOP_SOURCE_SHA256[loops.DENSITY_SOURCE], loops.DENSITY_BEFORE_SHA256)
        self.assertEqual(len(self.hair_rules), 4)

    def test_original_masks_keep_true_and_unrelated_entries_on_both_sources(self):
        # Manifest-only controls, not manufactured native capture evidence.
        for successor in (False, True):
            density = self.assert_paired_rows(successor)
            lines = sorted(set(density) | ({149, 223} if successor else {148, 220}))
            raw = ''.join('B '+self.density+' '+str(line)+'\n' for line in lines)
            unrelated = ('L '+self.density+' 25\nB '+self.density+' 26\n'
                         'C '+self.density+' 27 0\nM '+self.density+' 27 1\n')
            raw = (raw+unrelated).encode()
            proofs = [dict(proof, module=self.density) for proof in density.values()]
            envelope = {'sha256': 'manifest-only-model', 'receipt': {
                'manifest_sha256': loops.sha256(raw), 'proofs': proofs}}
            masked = loops.masked_manifest(raw, envelope).decode()
            self.assertTrue(masked.endswith(unrelated))
            for line, proof in density.items():
                self.assertEqual(proof['cardinality'], 1)
                self.assertIn('R '+self.density+' '+str(line)+' T '+proof['kind']+' 1\n', masked)
            if not successor:
                for line in (148, 220):
                    self.assertIn('B '+self.density+' '+str(line)+'\n', masked)
            # The original manifest is unchanged; no true probe is manufactured.
            self.assertEqual(envelope['receipt']['manifest_sha256'], loops.sha256(raw))

    def test_exact_checked_conversion_and_query_premise_mutations_revoke(self):
        cases = (
            ('var rounded = ceil(ratio)', 'var rounded = ratio'),
            ('if not isfinite(rounded):', 'if False:'),
            ('if rounded <= 1:', 'if rounded < 0:'),
            ('        return 1\n', '        return 0\n'),
            ('var exclusive_limit = -Float32(Int.MIN)', 'var exclusive_limit = Float32(Int.MAX)'),
            ('if rounded >= exclusive_limit:', 'if rounded > exclusive_limit:'),
            ('if rounded >= exclusive_limit:', 'if False:'),
            ('var rounded = ceil(ratio)', 'var premature = Int(ratio)\n    var rounded = ceil(ratio)'),
            ('return Int(rounded)', 'return Int(ratio)'),
            ('size_of[Int]() == 4 or size_of[Int]() == 8', 'size_of[Int]() >= 4'),
            ('var samples = _checked_density_samples(length / (cell * 0.5))', 'var samples = Int(ceil(length / (cell * 0.5)))'),
            ('var samples = _checked_density_samples(length / (cell * 0.5))', 'var samples = 0'),
            ('for sample in range(samples):', 'for sample in range(samples - 1):'),
            ('for _ in range(self.resolution * 4):', 'for _ in range(self.resolution * 0):'),
            ('comptime MIN_HAIR_DENSITY_RESOLUTION = 4', 'comptime MIN_HAIR_DENSITY_RESOLUTION = 0'),
            ('comptime MAX_HAIR_DENSITY_RESOLUTION = 64', 'comptime MAX_HAIR_DENSITY_RESOLUTION = Int.MAX'),
            ('        self.validate()\n        if not self.populated', '        if not self.populated'),
            ('        self.validate()\n        if not self.populated', '        self.validate()\n        self.resolution = 0\n        if not self.populated'),
            ('        self.validate()\n        if not self.populated', '        self.validate()\n        unknown_alias(self)\n        if not self.populated'),
            ('        var total = Float32(0)\n', '        self.validate()\n        var total = Float32(0)\n'),
        )
        for before, after in cases:
            with self.subTest(premise=before, replacement=after):
                self.assertEqual(self.after.count(before), 1)
                self.path.write_text(self.after.replace(before, after, 1))
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, self.density), {})
                for rule in self.hair_rules:
                    self.assertIsNone(loops.guarded_loop_proof(self.root, rule))
                with self.assertRaisesRegex(ValueError, 'Unreviewed'):
                    loops.reviewed_density_source(self.root)
                self.assert_paired_rows(True)
        # Relocation past the header is different from merely deleting a call.
        late = self.after.replace('        self.validate()\n        if not self.populated', '        if not self.populated', 1)
        late = late.replace('            var slot = self._slot(p)\n', '            self.validate()\n            var slot = self._slot(p)\n')
        self.path.write_text(late)
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, self.density), {})
        for name in ('range', 'Int', 'Float32', 'ceil', 'isfinite', 'size_of'):
            self.path.write_text(self.after+'\nfrom unreviewed import '+name+'\n')
            self.assertEqual(loops.reviewed_nonempty_loops(self.root, self.density), {})
        self.assert_paired_rows(True)

    def test_missing_or_changed_dependencies_revoke_rebound_old_hair_rows(self):
        self.assert_paired_rows(True)
        for rule in self.hair_rules:
            for name in (rule[0]+'.mojo', *rule[6]):
                path = self.root/name
                original = path.read_bytes()
                with self.subTest(proof=rule[5], dependency=name):
                    path.write_bytes(original+b'\n# unreviewed dependency change\n')
                    self.assertIsNone(loops.guarded_loop_proof(self.root, rule))
                    path.unlink()
                    self.assertIsNone(loops.guarded_loop_proof(self.root, rule))
                    path.write_bytes(original)
                    self.assertIsNotNone(loops.guarded_loop_proof(self.root, rule))
        original = self.path.read_bytes()
        self.path.unlink()
        self.assertEqual(loops.repaired_density_loops(self.root), {})
        self.path.write_bytes(original)
        self.assert_paired_rows(True)

    def test_new_retained_state_caller_revokes_successor_strands_only(self):
        self.assert_paired_rows(True)
        path = self.root/'unreviewed.mojo'
        for text in ('def f(hair):\n    hair._shadow_depths([])\n',
                     'def f(hair):\n    return hair._upload\n',
                     'def f(mut hair):\n    hair._topology.clear()\n'):
            path.write_text(text)
            for rule in self.hair_rules:
                proof = loops.guarded_loop_proof(self.root, rule)
                if rule[0] == self.strands:
                    self.assertIsNone(proof)
                else:
                    self.assertIsNotNone(proof)
            self.assertEqual(set(loops.repaired_density_loops(self.root)), {149, 223})
        path.unlink()
        self.assert_paired_rows(True)

    def test_project_std_surfaces_revoke_only_repaired_and_successor_admissions(self):
        external = tempfile.TemporaryDirectory(prefix='density-external-include-root-')
        self.addCleanup(external.cleanup)
        stage = Path(external.name)/'custom-stage'
        stage.mkdir()
        roots = (stage,)
        for destination in (self.root, stage):
            for prefix in ('', 'tests', 'extensions/deep/module'):
                for leaf in ('std', 'std.mojo', 'std.mojoc', 'std.mojopkg', 'std.🔥', 'std.future', 'STD.MOJO'):
                    self.path.write_text(self.after)
                    shadow = destination/prefix/leaf
                    shadow.parent.mkdir(parents=True, exist_ok=True)
                    if leaf == 'std':
                        shadow.mkdir()
                    else:
                        shadow.write_text('unreviewed resolver surface')
                    with self.subTest(root=str(destination), name=str(shadow)):
                        self.assertEqual(loops.reviewed_nonempty_loops(self.root, self.density, include_roots=roots), {})
                        self.assertEqual(set(loops.reviewed_nonempty_loops(self.root, self.strands, include_roots=roots)), {195, 201})
                        # Old bindings are retained; this guard is specific to
                        # the newly reviewed source, not a historical repin.
                        self.path.write_text(self.before)
                        for rule in self.hair_rules:
                            self.assertIsNotNone(loops.guarded_loop_proof(self.root, rule, include_roots=roots))
                    if leaf == 'std':
                        shadow.rmdir()
                    else:
                        shadow.unlink()
                    self.assert_paired_rows(True)
                    self.assertEqual(set(loops.repaired_density_loops(self.root, include_roots=roots)), {149, 223})

    def test_std_symlinks_and_hidden_project_directory_surfaces_fail_closed(self):
        self.assert_paired_rows(True)
        outside = tempfile.TemporaryDirectory(prefix='density-std-symlink-target-')
        self.addCleanup(outside.cleanup)
        target = Path(outside.name)
        (target/'std.mojoc').write_text('unreviewed package')
        for relative, destination in (('std', target), ('tests/std.mojo', target/'missing.mojo'),
                                      ('tests/std.mojoc', target/'std.mojoc'),
                                      ('project_alias', target)):
            link = self.root/relative
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(destination, target_is_directory=destination.is_dir())
            self.assertEqual(loops.repaired_density_loops(self.root), {})
            for rule in self.hair_rules:
                self.assertIsNone(loops.guarded_loop_proof(self.root, rule))
            link.unlink()
            self.assert_paired_rows(True)
        for folder in ('.venv', '.cache'):
            # Established non-input locations may contain the actual SDK or
            # compiler cache. They are not project include-root candidates.
            link = self.root/folder
            link.symlink_to(target, target_is_directory=True)
            self.assertEqual(set(loops.repaired_density_loops(self.root)), {149, 223})
            link.unlink()
        self.assertEqual(loops.repaired_density_loops(self.root, include_roots=(self.root/'absent',)), {})
        with patch.object(loops.os, 'walk', side_effect=PermissionError('unreadable resolver surface')):
            self.assertEqual(loops.repaired_density_loops(self.root), {})
        self.assert_paired_rows(True)

    def test_supported_integer_limits_are_exact_binary32_powers(self):
        import math
        import struct
        for width in (32, 64):
            limit = 1 << (width-1)
            bits = (width+126) << 23
            decoded = struct.unpack('!f', struct.pack('!I', bits))[0]
            below = struct.unpack('!f', struct.pack('!I', bits-1))[0]
            maximum = limit-1
            self.assertEqual(decoded, limit)
            self.assertEqual(int(below), maximum-(maximum >> 24))
            self.assertLess(below, limit)
            self.assertEqual(math.ceil(below), below)
            self.assertGreater(decoded, maximum)
        self.assertNotIn('247', self.after)
        self.assertNotIn('Int(1) << 63', self.after)


class MapSuccessorLoopTests(unittest.TestCase):
    """Exercise actual live states separately from historical premise fixtures."""

    def setUp(self):
        from carla_lane_oracle import seed_count_contracts as seed_count
        self.seed = seed_count
        self.repo = Path(__file__).resolve().parents[1]
        self.name = seed_count.MODULE
        self.rules = [rule for rule in loops.GUARDED_LOOP_RULES
                      if rule[0] == 'extensions/carla/map']
        self.lines = {1491: 1485, 2272: 2264, 2279: 2271, 2301: 2293,
                      2373: 2365, 2378: 2370, 2387: 2379, 2396: 2388}
        self.raw = (self.repo/self.name).read_bytes()
        self.digest = loops.sha256(self.raw)
        self.assertIn(self.digest, (seed_count.BEFORE_SHA256, seed_count.AFTER_SHA256, seed_count.OPTIONAL_AFTER_SHA256, seed_count.SUPPORT_AFTER_SHA256, seed_count.FRONTIER_AFTER_SHA256, seed_count.SCORE_AFTER_SHA256))
        self.optional = self.digest == seed_count.OPTIONAL_AFTER_SHA256
        self.support = self.digest == seed_count.SUPPORT_AFTER_SHA256
        self.score = self.digest == seed_count.SCORE_AFTER_SHA256
        self.frontier = self.digest == seed_count.FRONTIER_AFTER_SHA256
        if self.optional:
            self.lines = {1491: 1476, 2272: 2255, 2279: 2262, 2301: 2284,
                          2373: 2356, 2378: 2361, 2387: 2370, 2396: 2379}
        if self.support:
            self.lines = {1491: 1464, 2272: 2243, 2279: 2250, 2301: 2272,
                          2373: 2344, 2378: 2349, 2387: 2358, 2396: 2367}
        if self.frontier:
            self.lines = {1491: 1463, 2272: 2242, 2279: 2249, 2301: 2271,
                          2373: 2343, 2378: 2348, 2387: 2357, 2396: 2366}
        if self.score:
            self.lines = loops._MAP_SCORE_SUCCESSOR_LINES
        self.after = self.digest != seed_count.BEFORE_SHA256

    def assert_live_proofs(self, root):
        actual = loops.reviewed_nonempty_loops(root, 'extensions/carla/map')
        expected = set(self.lines.values() if self.after else self.lines)
        if self.frontier:
            expected.add(4055)
        if self.score:
            expected.add(4069)
        self.assertEqual(set(actual), expected)
        text = (root/self.name).read_text().splitlines()
        for rule in self.rules:
            line = self.lines[rule[1]] if self.after else rule[1]
            proof = actual[line]
            self.assertEqual((proof['line'], proof['required'], proof['impossible']),
                             (line, 'T', 'F'))
            self.assertEqual(proof['proof_id'], rule[5])
            self.assertEqual(proof['dependency_sha256'][self.name], self.digest)
            self.assertIn(' in '+proof['expression']+':', text[line-1])
        tree = loops.reviewed_nonempty_loops(root, 'extensions/carla/rtree')
        self.assertEqual(set(tree), {666})
        self.assertEqual((tree[666]['required'], tree[666]['impossible']), ('T', 'F'))
        self.assertEqual(tree[666]['dependency_sha256'][self.name], self.digest)
        return actual

    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix='map-successor-loop-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        record = self.seed.read_record(self.repo)
        names = {self.name, self.seed.MIGRATION, *self.seed.SCORE_TESTS}
        for key in ('unchanged_inputs', 'historical_records',
                    'unchanged_correctness_tests', 'after_correctness_tests'):
            names.update(record[key])
        names.update(loops.REVIEWED_LOOP_RULES['extensions/carla/rtree'][0])
        for name in names:
            path = root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((self.repo/name).read_bytes())
        return root

    def test_actual_physical_state_keeps_live_hashes_and_all_true_obligations(self):
        self.assertEqual({r[1] for r in self.rules}, set(self.lines))
        expected = (loops._MAP_SCORE_SUCCESSOR_LINES if self.score else
                    loops._MAP_FRONTIER_SUCCESSOR_LINES if self.frontier else
                    loops._MAP_SUPPORT_SUCCESSOR_LINES if self.support else
                    loops._MAP_OPTIONAL_SUCCESSOR_LINES if self.optional else
                    loops._MAP_SUCCESSOR_LINES)
        self.assertEqual(expected, self.lines)
        self.assert_live_proofs(self.repo)

    def test_missing_future_fixture_cannot_activate_after_in_before_checkout(self):
        root = self.fixture()
        (root/self.name).write_text(self.seed.score_successor_source(self.repo) if self.score else
                                   self.seed.frontier_successor_source(self.repo) if self.frontier else
                                   self.seed.support_successor_source(self.repo) if self.support else
                                   self.seed.optional_successor_source(self.repo) if self.optional else
                                   self.seed.successor_source(self.repo))
        if not self.after:
            # An infrastructure-only checkout cannot manufacture the future
            # count suite. Its actual old bytes must fail the immutable pin.
            self.assertEqual(loops.reviewed_nonempty_loops(root, 'extensions/carla/map'), {})
            self.assertEqual(loops.reviewed_nonempty_loops(root, 'extensions/carla/rtree'), {})
        else:
            self.assert_live_proofs(root)

    def test_live_headers_and_frontier_call_mutations_revoke(self):
        root = self.fixture()
        self.assert_live_proofs(root)
        path = root/self.name
        lines = self.raw.decode().splitlines(keepends=True)
        for rule in self.rules:
            line = self.lines[rule[1]] if self.after else rule[1]
            mutated = list(lines)
            mutated[line-1] = mutated[line-1].replace(' in ', ' in [] # ', 1)
            with self.subTest(header=line):
                path.write_text(''.join(mutated))
                self.assertEqual(loops.reviewed_nonempty_loops(root, 'extensions/carla/map'), {})
                self.assertEqual(loops.reviewed_nonempty_loops(root, 'extensions/carla/rtree'), {})
        path.write_bytes(self.raw)
        before = 'var frontier = self._tree._nearest_begin(location, work)'
        self.assertEqual(self.raw.decode().count(before), 1)
        path.write_text(self.raw.decode().replace(before, 'var frontier = _Heap()'))
        self.assertEqual(loops.reviewed_nonempty_loops(root, 'extensions/carla/rtree'), {})
        path.write_bytes(self.raw)
        self.assert_live_proofs(root)

    def test_after_dependency_fixture_and_record_controls_fail_closed(self):
        root = self.fixture()
        # Use the source-only reconstruction to test rejection even before the
        # future fixture exists; only a physical after checkout admits it.
        (root/self.name).write_text(self.seed.score_successor_source(self.repo) if self.score else
                                   self.seed.frontier_successor_source(self.repo) if self.frontier else
                                   self.seed.support_successor_source(self.repo) if self.support else
                                   self.seed.optional_successor_source(self.repo) if self.optional else
                                   self.seed.successor_source(self.repo))
        if self.after:
            self.assert_live_proofs(root)
        else:
            self.assertEqual(loops.reviewed_nonempty_loops(root, 'extensions/carla/map'), {})
        for name in ('extensions/carla/road.mojo', self.seed.MIGRATION,
                     'tests/test_carla_winner_seed_recovery.mojo'):
            path = root/name
            original = path.read_bytes()
            with self.subTest(dependency=name):
                path.write_bytes(original+b'\n# unreviewed successor dependency\n')
                self.assertEqual(loops.reviewed_nonempty_loops(root, 'extensions/carla/map'), {})
                self.assertEqual(loops.reviewed_nonempty_loops(root, 'extensions/carla/rtree'), {})
                path.unlink()
                self.assertEqual(loops.reviewed_nonempty_loops(root, 'extensions/carla/map'), {})
                path.write_bytes(original)
        if self.after:
            self.assert_live_proofs(root)

    def test_all_six_explicit_map_states_keep_eight_required_true_rows(self):
        root = self.fixture()
        middle = self.seed.successor_source(self.repo)
        earliest = self.seed.predecessor_source(middle, self.seed.read_record(self.repo))
        optional = self.seed.optional_successor_source(self.repo)
        support = self.seed.support_successor_source(self.repo)
        newest = self.seed.frontier_successor_source(self.repo)
        maps = [(earliest, {k:k for k in self.lines}),
                (middle, loops._MAP_SUCCESSOR_LINES),
                (optional, loops._MAP_OPTIONAL_SUCCESSOR_LINES),
                (support, loops._MAP_SUPPORT_SUCCESSOR_LINES),
                (newest, loops._MAP_FRONTIER_SUCCESSOR_LINES),
                (self.seed.score_successor_source(self.repo), loops._MAP_SCORE_SUCCESSOR_LINES)]
        for text, correspondence in maps:
            (root/self.name).write_text(text)
            proof = loops.reviewed_nonempty_loops(root, 'extensions/carla/map')
            expected = set(correspondence.values())
            if loops.sha256(text.encode()) == self.seed.FRONTIER_AFTER_SHA256:
                expected.add(4055)
            if loops.sha256(text.encode()) == self.seed.SCORE_AFTER_SHA256:
                expected.add(4069)
            self.assertEqual(set(proof), expected)
            for rule in self.rules:
                line = correspondence[rule[1]]
                row = proof[line]
                self.assertEqual((row['required'],row['impossible'],row['proof_id']),('T','F',rule[5]))
                self.assertEqual(row['dependency_sha256'][self.name],loops.sha256(text.encode()))
                self.assertIn(' in '+row['expression']+':',text.splitlines()[line-1])
        (root/self.name).write_text(newest+'\n# unreviewed fifth edge\n')
        self.assertEqual(loops.reviewed_nonempty_loops(root,'extensions/carla/map'),{})
        self.assertEqual(loops.reviewed_nonempty_loops(root,'extensions/carla/rtree'),{})

    def test_complete_consumers_accept_six_exact_states_and_reject_mutations(self):
        from carla_lane_oracle import winner_sign_contracts as winner
        from carla_lane_oracle import border_parser_contracts as border
        middle = self.seed.successor_source(self.repo)
        variants = (
            self.seed.predecessor_source(middle, self.seed.read_record(self.repo)),
            middle, self.seed.optional_successor_source(self.repo),
            self.seed.support_successor_source(self.repo),
            self.seed.frontier_successor_source(self.repo),
            self.seed.score_successor_source(self.repo),
        )
        target = self.repo/self.name
        read_bytes, read_text = Path.read_bytes, Path.read_text
        for text in variants:
            for consumer in (winner, border):
                for unknown in (False, True):
                    candidate = text + ('\n# unknown consumer source\n' if unknown else '')
                    with self.subTest(consumer=consumer.__name__,
                                      sha256=loops.sha256(text.encode()), unknown=unknown), \
                         patch.object(Path, 'read_bytes', lambda p, *a, **k:
                                      candidate.encode() if p == target else read_bytes(p, *a, **k)), \
                         patch.object(Path, 'read_text', lambda p, *a, **k:
                                      candidate if p == target else read_text(p, *a, **k)):
                        if unknown:
                            with self.assertRaises(ValueError):
                                consumer.verify(self.repo)
                        else:
                            consumer.verify(self.repo)

    def test_current_lines_mask_only_the_false_loop_outcomes(self):
        proofs = self.assert_live_proofs(self.repo)
        for line, proof in proofs.items():
            module = 'extensions/carla/map'
            raw = (f'L {module} {line}\nB {module} {line}\n'
                   f'C {module} {line+1} 0\nM {module} {line+1} 0\n').encode()
            receipt = {'manifest_sha256': loops.sha256(raw),
                       'proofs': [{'module': module, **proof}]}
            envelope = {'receipt': receipt, 'sha256': loops.sha256(loops.canonical(receipt))}
            expected = raw.decode().splitlines()
            expected[1] = f'R {module} {line} T {proof["kind"]} {proof["cardinality"]}'
            self.assertEqual(loops.masked_manifest(raw, envelope).decode().splitlines()[1:], expected)


    def consumer_script_probe(self, consumer, mode, *, shadow=False,
                              internal_error=False, unknown=False):
        """Run the complete named consumer from its real script directory."""
        temporary = tempfile.TemporaryDirectory(prefix='optional-consumer-import-')
        self.addCleanup(temporary.cleanup)
        fixture = Path(temporary.name)
        (fixture/'tools/carla_lane_oracle').mkdir(parents=True)
        for folder in ('tools','tools/carla_lane_oracle'):
            for path in (self.repo/folder).glob('*.py'):
                shutil.copyfile(path, fixture/folder/path.name)
        if internal_error:
            with (fixture/'tools/carla_lane_oracle/source_contracts.py').open('a') as stream:
                stream.write('\nraise ModuleNotFoundError("optional-consumer-inner-sentinel")\n')
        root = self.repo
        if unknown:
            root = fixture/'unknown-source'
            shutil.copytree(self.repo,root,ignore=shutil.ignore_patterns(
                '__pycache__','.cache','.venv','.git'))
            with (root/self.name).open('ab') as stream:
                stream.write(b'\n# unreviewed physical Map\n')
        directory = (fixture/'tools' if mode == 'cli' else
                     fixture/'tools/carla_lane_oracle' if mode == 'direct' else fixture)
        script = directory/'probe_consumers.py'
        script.write_text("""
import importlib,sys,types
from pathlib import Path
root=Path(sys.argv[1])
consumer,mode,shadow,internal_error,unknown=sys.argv[2:]
prefix={'cli':'carla_lane_oracle.','package':'tools.carla_lane_oracle.','direct':''}[mode]
original_path=list(sys.path)
def check(value,message):
    if not value: raise RuntimeError(message)
if shadow == 'True':
    check(bool(prefix),'shadow control requires a package namespace')
    for name in ('source_contracts','cache_key_contracts','speed_parser_contracts','seed_count_contracts','ideal_projection'):
        sys.modules[name]=types.ModuleType(name)
try:
    module=importlib.import_module(prefix+consumer)
    module.verify(root)
except ModuleNotFoundError as error:
    check(internal_error == 'True' and str(error) == 'optional-consumer-inner-sentinel',
          'internal import failure was hidden or replaced: '+str(error))
    check(sys.path == original_path,'error changed sys.path')
    print('inner dependency error propagated')
    raise SystemExit(0)
except ValueError:
    check(unknown == 'True','valid physical source was refused')
    check(sys.path == original_path,'source refusal changed sys.path')
    print('unknown physical source refused')
    raise SystemExit(0)
check(internal_error == 'False' and unknown == 'False','expected refusal was bypassed')
source=importlib.import_module(prefix+'source_contracts')
seed=importlib.import_module(prefix+'seed_count_contracts')
guard=importlib.import_module(prefix+'sum2_guard_contracts')
check(module.source is source and seed.source is source and guard.source_contracts is source,
      'consumer closure split source-module identity')
local={p.stem for p in Path(source.__file__).parent.glob('*.py')}
loaded=[]
for name,value in list(sys.modules.items()):
    if name.startswith(prefix) and name.removeprefix(prefix) in local:
        loaded.append(name)
        for dependency in vars(value).values():
            if isinstance(dependency,types.ModuleType):
                stem=dependency.__name__.split('.')[-1]
                if stem in local:
                    check(dependency is sys.modules.get(prefix+stem),
                          'consumer closure imported a foreign namespace: '+dependency.__name__)
            elif isinstance(dependency,types.FunctionType):
                stem=dependency.__module__.split('.')[-1]
                if stem in local:
                    owner=sys.modules.get(prefix+stem)
                    check(owner is not None and getattr(owner,dependency.__name__,None) is dependency,
                          'consumer closure imported a foreign function: '+dependency.__module__)
check(sys.path == original_path,'verification changed sys.path')
print('consumer verified',consumer,mode,','.join(sorted(loaded)))
""")
        cwd=fixture/'unrelated-cwd';cwd.mkdir()
        command=[sys.executable,'-E','-B']
        if sys.flags.optimize:command.append('-O')
        command.extend([str(script),str(root),consumer,mode,str(shadow),
                        str(internal_error),str(unknown)])
        result=subprocess.run(command,cwd=cwd,capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        return result.stdout

    def test_complete_winner_and_parser_consumers_in_real_script_locations(self):
        for consumer in ('winner_sign_contracts','border_parser_contracts'):
            for mode in ('cli','package','direct'):
                with self.subTest(consumer=consumer,mode=mode):
                    self.assertIn('consumer verified',self.consumer_script_probe(consumer,mode))

    def test_complete_consumers_ignore_foreign_direct_module_shadows(self):
        for consumer in ('winner_sign_contracts','border_parser_contracts'):
            for mode in ('cli','package'):
                with self.subTest(consumer=consumer,mode=mode):
                    self.assertIn('consumer verified',self.consumer_script_probe(consumer,mode,shadow=True))

    def test_complete_consumers_propagate_inner_import_errors_and_refuse_unknown_source(self):
        for consumer in ('winner_sign_contracts','border_parser_contracts'):
            for mode in ('cli','package','direct'):
                with self.subTest(consumer=consumer,mode=mode):
                    self.assertIn('inner dependency error propagated',
                                  self.consumer_script_probe(consumer,mode,internal_error=True))
            self.assertIn('unknown physical source refused',
                          self.consumer_script_probe(consumer,'cli',unknown=True))

    def clean_import_probe(self, mode, *, root=None, shadow=False,
                           internal_error=False, rejected=False):
        """Use a real script path and fresh interpreter, never ambient imports."""
        temporary = tempfile.TemporaryDirectory(prefix='oracle-cli-import-')
        self.addCleanup(temporary.cleanup)
        fixture = Path(temporary.name)
        tools = fixture / 'tools'
        oracle = tools / 'carla_lane_oracle'
        oracle.mkdir(parents=True)
        modules = (
            'seed_count_contracts', 'sum2_guard_contracts', 'source_contracts',
            'ideal_projection', 'cache_key_contracts', 'reviewed_cleanup_contracts',
            'accepted_successor_contracts', 'coverage_invariant_contracts',
            'curve_support_dispatch_contracts', 'frozen_arc_producer_contracts',
            'grouped_table_contracts',
        )
        for name in modules:
            shutil.copyfile(self.repo / 'tools/carla_lane_oracle' / (name+'.py'),
                            oracle / (name+'.py'))
        for name in ('coverage_loop_proofs', 'cache_key',
                     'coverage_toolchain_identity', 'affected'):
            shutil.copyfile(self.repo / 'tools' / (name+'.py'), tools / (name+'.py'))
        if internal_error:
            with (oracle / 'source_contracts.py').open('a') as output:
                output.write('\nraise ModuleNotFoundError("oracle-inner-sentinel")\n')
        script = (tools if mode == 'cli' else oracle if mode == 'direct' else fixture) / 'probe.py'
        script.write_text("""
import hashlib, importlib, json, sys, types
from pathlib import Path
root = Path(sys.argv[1])
mode, shadow, internal_error, rejected = sys.argv[2:]
original_path = list(sys.path)
prefix = {'cli': 'carla_lane_oracle.', 'package': 'tools.carla_lane_oracle.', 'direct': ''}[mode]
def check(value, message):
    if not value:
        raise RuntimeError(message)
if shadow == 'True':
    check(bool(prefix), 'shadow control requires package execution')
    shadow_module = types.ModuleType('source_contracts')
    sys.modules['source_contracts'] = shadow_module
try:
    seed = importlib.import_module(prefix + 'seed_count_contracts')
except ModuleNotFoundError as error:
    check(internal_error == 'True' and str(error) == 'oracle-inner-sentinel',
          'an internal import error was hidden by alternate import resolution: ' + str(error))
    check(sys.path == original_path, 'failure changed the import path')
    print('internal import error propagated without fallback')
    raise SystemExit(0)
check(internal_error == 'False', 'internal dependency error was swallowed')
source = importlib.import_module(prefix + 'source_contracts')
guard = importlib.import_module(prefix + 'sum2_guard_contracts')
check(seed.source is source and seed.guard is guard, 'split seed dependency identity')
check(guard.source_contracts is source, 'split guard source identity')
check(guard.cache_key.source is source, 'split cache source identity')
check(guard.reviewed_cleanup_contracts.source is source, 'split cleanup source identity')
check(guard.reviewed_cleanup_contracts.invariant.source is source, 'split invariant source identity')
check(guard.reviewed_cleanup_contracts.frozen.source is source, 'split frozen source identity')
check(guard.reviewed_cleanup_contracts.accepted.source is source, 'split accepted source identity')
check(guard.reviewed_cleanup_contracts.invariant.curve.source is source, 'split curve source identity')
check(guard.reviewed_cleanup_contracts.invariant.grouped.token_sha256 is source.token_sha256,
      'split grouped token function identity')
if shadow == 'True':
    check(source is not shadow_module and sys.modules['source_contracts'] is shadow_module,
          'package import reused or replaced an unrelated direct module')
check(sys.path == original_path, 'imports changed sys.path')
if mode == 'cli':
    import coverage_loop_proofs as loops
    actual = loops.reviewed_nonempty_loops(root, 'extensions/carla/map')
    tree = loops.reviewed_nonempty_loops(root, 'extensions/carla/rtree')
    if rejected == 'True':
        check(not actual and not tree, 'unknown source activated a named proof')
        print('unknown successor withheld all named Map and R-tree proofs')
        raise SystemExit(0)
    digest = hashlib.sha256((root/seed.MODULE).read_bytes()).hexdigest()
    after = digest in {seed.AFTER_SHA256, seed.OPTIONAL_AFTER_SHA256, seed.SUPPORT_AFTER_SHA256, seed.FRONTIER_AFTER_SHA256, seed.SCORE_AFTER_SHA256}
    mapping = (loops._MAP_SCORE_SUCCESSOR_LINES if digest == seed.SCORE_AFTER_SHA256 else
               loops._MAP_FRONTIER_SUCCESSOR_LINES if digest == seed.FRONTIER_AFTER_SHA256 else
               loops._MAP_SUPPORT_SUCCESSOR_LINES if digest == seed.SUPPORT_AFTER_SHA256 else
               loops._MAP_OPTIONAL_SUCCESSOR_LINES if digest == seed.OPTIONAL_AFTER_SHA256 else
               loops._MAP_SUCCESSOR_LINES)
    expected = set(mapping.values() if after else mapping)
    if digest == seed.FRONTIER_AFTER_SHA256:
        expected.add(4055)
    if digest == seed.SCORE_AFTER_SHA256:
        expected.add(4069)
    check(set(actual) == expected and set(tree) == {666}, 'clean CLI lost expected named proofs')
    for proof in [*actual.values(), *tree.values()]:
        check((proof['required'], proof['impossible']) == ('T', 'F'), 'reachable outcome weakened')
        check(proof['dependency_sha256'][seed.MODULE] == digest, 'proof replaced live source identity')
    print(json.dumps({'map_lines': sorted(actual), 'rtree_lines': sorted(tree), 'map_sha256': digest}))
else:
    before = seed.historical_source(root)
    check(hashlib.sha256(before.encode()).hexdigest() == seed.BEFORE_SHA256,
          'source inverse did not reconstruct the reviewed predecessor')
    print('canonical ' + (prefix or 'direct') + ' imports and reviewed inverse passed')
check(sys.path == original_path, 'verification changed sys.path')
""")
        # -E excludes inherited PYTHONPATH. The real script location supplies
        # tools, the repository package root, or the direct oracle directory.
        # The unrelated cwd prevents repository-root discovery from hiding bugs.
        cwd = fixture / 'unrelated-cwd'
        cwd.mkdir()
        command = [sys.executable, '-E', '-B']
        if sys.flags.optimize:
            command.append('-O')
        command.extend([str(script), str(root or self.repo), mode, str(shadow),
                        str(internal_error), str(rejected)])
        result = subprocess.run(command, cwd=cwd, check=False, capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_clean_cli_admits_named_rules_without_ambient_root_imports(self):
        self.assertIn('map_lines', self.clean_import_probe('cli'))

    def test_package_and_direct_modes_keep_canonical_dependency_identity(self):
        for mode, shadow in [('package', False), ('package', True),
                             ('cli', True), ('direct', False)]:
            with self.subTest(mode=mode, shadow=shadow):
                self.assertIn('passed' if mode != 'cli' else 'map_lines',
                              self.clean_import_probe(mode, shadow=shadow))

    def test_internal_dependency_importerror_propagates_without_fallback(self):
        for mode in ('cli', 'package', 'direct'):
            with self.subTest(mode=mode):
                self.assertIn('without fallback',
                              self.clean_import_probe(mode, internal_error=True))

    def test_clean_cli_unknown_successor_keeps_both_loop_outcomes_required(self):
        root = self.fixture()
        with (root/self.name).open('ab') as output:
            output.write(b'\n# unknown complete source\n')
        self.assertIn('withheld', self.clean_import_probe('cli', root=root, rejected=True))



class ConstructionBoundaryLoopTests(unittest.TestCase):
    """Final-only typed producer proof; prior envelopes remain independent."""

    line = 4055
    score = False

    def setUp(self):
        self.repo = Path(__file__).resolve().parents[1]
        temporary = tempfile.TemporaryDirectory(prefix='construction-boundary-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.map = 'extensions/carla/map.mojo'
        self.road = 'extensions/carla/road.mojo'
        self.loft = 'extensions/humanoid/skeleton/loft.mojo'
        from carla_lane_oracle import seed_count_contracts as seed
        record = seed.read_record(self.repo)
        names = {*loops.CONSTRUCTION_BOUNDARY_SOURCE_SHA256, self.loft, seed.MIGRATION, *seed.SCORE_TESTS}
        for group in ('historical_records', 'unchanged_correctness_tests',
                      'after_correctness_tests'):
            names.update(record[group])
        for name in names:
            target = self.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((self.repo/name).read_bytes())

        (self.root/self.map).write_text(seed.score_successor_source(self.repo) if self.score
                                         else seed.frontier_successor_source(self.repo))

    def proof(self):
        return loops.construction_boundary_loops(self.root)

    def test_exact_final_source_keeps_true_and_masks_only_false(self):
        proof = self.proof()
        self.assertEqual(set(proof), {self.line})
        row = proof[self.line]
        self.assertEqual((row['required'], row['impossible'], row['cardinality'],
                          row['minimum_cardinality'], row['maximum_cardinality']),
                         ('T', 'F', 1, 1, None))
        self.assertEqual(row['proof_id'], 'construction-geometry-boundary-list')
        for name, expected in loops.CONSTRUCTION_BOUNDARY_SOURCE_SHA256.items():
            self.assertEqual(row['dependency_sha256'][name],
                             loops.file_sha256(self.root/name) if self.score and name == self.map else expected)
        for name, expected in row['dependency_sha256'].items():
            self.assertEqual(loops.file_sha256(self.root/name), expected)
        self.assertEqual((self.root/self.map).read_text().splitlines()[self.line-1].strip(),
                         'for s in boundaries:')
        raw = f'B extensions/carla/map {self.line}\nL extensions/carla/map {self.line}\n'.encode()
        envelope = {'sha256': 'test', 'receipt': {
            'manifest_sha256': loops.sha256(raw),
            'proofs': [{'module': 'extensions/carla/map', **row}]}}
        masked = loops.masked_manifest(raw, envelope)
        self.assertIn(f'R extensions/carla/map {self.line} T reviewed-nonempty-iterator 1'.encode(), masked)
        self.assertIn(f'L extensions/carla/map {self.line}'.encode(), masked)

    def test_geometry_guard_append_lifetime_receiver_and_types_are_bound(self):
        cases = [
            (self.road, 'if geometry_at < 0:', 'if geometry_at < -1:'),
            (self.road, '        if geometry_at < 0:\n            raise Error("The road has no geometry at that s")\n', ''),
            (self.road, '            result.append(record.s)',
             '            if record.s > 0.0:\n                result.append(record.s)'),
            (self.road, '        return result^',
             '        result.clear()\n        return result^'),
            (self.map, '            for s in boundaries:',
             '            boundaries.clear()\n            for s in boundaries:'),
            (self.map, 'var current_t = self._build_transform(current)',
             'var current_t = self._build_transform(start)'),
            (self.map, 'self._add_segment(current_t, next_t, current, next_w)',
             'other._add_segment(current_t, next_t, current, next_w)'),
            (self.map, 'var roads: List[Road]', 'var roads: List[OtherRoad]'),
            (self.road, 'var info: InformationSet', 'var info: OtherInformationSet'),
            ('extensions/carla/road_info.mojo', 'var geometries: List[RoadInfoGeometry]',
             'var geometries: List[OtherGeometry]'),
        ]
        for name, before, after in cases:
            path = self.root/name
            original = path.read_text()
            with self.subTest(name=name, before=before):
                self.assertIn(before, original)
                path.write_text(original.replace(before, after))
                self.assertEqual(self.proof(), {})
                path.write_text(original)
        self.assertEqual(set(self.proof()), {self.line})

    def test_new_map_call_alias_and_unresolved_receiver_reject(self):
        path = self.root/'tests/new_boundary_call.mojo'
        path.parent.mkdir(parents=True, exist_ok=True)
        for text in (
            'from extensions.carla.map import Map\ndef f(mut road_map: Map):\n    road_map._add_segment(a, b, first, second)\n',
            'from extensions.carla.map import Map as M\ndef f(mut road_map: M):\n    road_map._add_segment(a, b, first, second)\n',
            'def f(mut unknown: Other):\n    unknown._add_segment(a, b, first, second)\n',
            'alias insert = Map._add_segment\n',
            'def f():\n    _add_segment(a, b, first, second)\n',
            'def _add_segment(x: Int):\n    pass\ndef f():\n    var _add_segment = Map._add_segment\n',
        ):
            with self.subTest(text=text):
                path.write_text(text)
                self.assertEqual(self.proof(), {})
        path.unlink()
        self.assertEqual(set(self.proof()), {self.line})

    def test_string_method_spellings_reject_but_comments_do_not(self):
        path = self.root/'tests/string_boundary_lookup.mojo'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('# _add_segment is an unrelated comment\ndef f():\n    pass\n')
        self.assertEqual(set(self.proof()), {self.line})
        for text in (
            'def f(mut m: Map):\n    getattr(m, "_add_segment")(a, b, first, second)\n',
            'alias member_name = "_add_segment"\n',
        ):
            with self.subTest(text=text):
                path.write_text(text)
                self.assertEqual(self.proof(), {})
        path.unlink()
        self.assertEqual(set(self.proof()), {self.line})

    def test_unrelated_module_local_spelling_does_not_establish_or_veto(self):
        # The real loft declaration is concrete List[_Ellipse]/LoftSample;
        # modifying its independent body cannot affect the CARLA theorem.
        path = self.root/self.loft
        path.write_text(path.read_text()+'\n# unrelated local loft change\n')
        extra = self.root/'tests/unrelated_boundary_name.mojo'
        extra.parent.mkdir(parents=True, exist_ok=True)
        extra.write_text('def _add_segment(x: Int):\n    pass\ndef f():\n    _add_segment(1)\n')
        self.assertEqual(set(self.proof()), {self.line})
        path.unlink()
        self.assertEqual(set(self.proof()), {self.line})
        road = self.root/self.road
        road.write_text(road.read_text().replace('if geometry_at < 0:', 'if geometry_at < -1:'))
        self.assertEqual(self.proof(), {})

    def test_unknown_endpoint_dependency_import_and_std_shadow_reject(self):
        for name in loops.CONSTRUCTION_BOUNDARY_SOURCE_SHA256:
            path = self.root/name
            original = path.read_bytes()
            with self.subTest(name=name):
                path.write_bytes(original+b'\n# unknown source\n')
                self.assertEqual(self.proof(), {})
                path.write_bytes(original)
        shadow = self.root/'std.mojo'
        shadow.write_text('struct List: pass\n')
        self.assertEqual(self.proof(), {})
        shadow.unlink()
        self.assertEqual(set(self.proof()), {self.line})

    def test_final_source_data_guards_and_staged_callers_fail_closed(self):
        from carla_lane_oracle import seed_count_contracts as seed
        record = seed.read_record(self.repo)
        for name in (seed.MIGRATION, *record['after_correctness_tests'],
                     *(seed.SCORE_TESTS if self.score else ())):
            path = self.root/name
            original = path.read_bytes()
            path.write_bytes(original+b'\n# unknown proof data\n')
            self.assertEqual(self.proof(), {})
            path.unlink()
            self.assertEqual(self.proof(), {})
            path.write_bytes(original)
        temporary = tempfile.TemporaryDirectory(prefix='boundary-staged-source-')
        self.addCleanup(temporary.cleanup)
        stage = Path(temporary.name)
        call = stage/'new.mojo'
        call.write_text('def f(mut m: Map):\n    m._add_segment(a, b, first, second)\n')
        self.assertEqual(set(self.proof()), {self.line})
        self.assertEqual(loops.construction_boundary_loops(
            self.root, include_roots=(stage,)), {})
        call.unlink()
        self.assertEqual(set(self.proof()), {self.line})

    def test_all_earlier_endpoints_withhold_new_row(self):
        from carla_lane_oracle import seed_count_contracts as seed
        middle = seed.successor_source(self.repo)
        for text in (seed.predecessor_source(middle, seed.read_record(self.repo)),
                     middle, seed.optional_successor_source(self.repo),
                     seed.support_successor_source(self.repo)):
            (self.root/self.map).write_text(text)
            self.assertEqual(self.proof(), {})


class ScoreConstructionBoundaryLoopTests(ConstructionBoundaryLoopTests):
    """Repeat every frozen constructor control on the fully verified new edge."""

    line = 4069
    score = True

    def test_score_refusal_remains_measured_and_mutations_revoke(self):
        text = (self.root/self.map).read_text()
        lines = text.splitlines()
        refusal = next(i for i, line in enumerate(lines, 1)
                       if 'if not score.is_finite():' in line)
        proofs = loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map')
        self.assertNotIn(refusal, proofs)
        raw = f'B extensions/carla/map {refusal}\n'.encode()
        receipt = {'manifest_sha256': loops.sha256(raw), 'proofs': []}
        envelope = {'sha256': loops.sha256(loops.canonical(receipt)), 'receipt': receipt}
        self.assertIn(raw, loops.masked_manifest(raw, envelope))
        (self.root/self.map).write_text(text.replace('if not score.is_finite():', 'if False:'))
        self.assertEqual(self.proof(), {})
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, 'extensions/carla/map'), {})


if __name__ == '__main__':
    unittest.main()
