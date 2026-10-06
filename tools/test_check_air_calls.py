# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the AIR call checker against small hand-written modules."""

import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import check_air_calls as air

CALLEE = ('define internal float @run({ ptr, i64, float, i1 } noundef %0, '
          'i64 noundef %1) #1 {\n  ret float 0.0\n}\n')
MATCHED = CALLEE.replace('{ ptr,', '{ ptr addrspace(1),') + (
    'define void @kernel(ptr addrspace(1) noundef %0) {\n'
    '  %3 = call float @run({ ptr addrspace(1), i64, float, i1 } %2, i64 5)\n'
    '  ret void\n}\n')
LOST = CALLEE + (
    'define void @kernel(ptr addrspace(1) noundef %0) {\n'
    '  %3 = call float @run({ ptr addrspace(1), i64, float, i1 } %2, i64 5)\n'
    '  ret void\n}\n')


class AirCallTests(unittest.TestCase):
    def test_matching_calls_pass(self):
        self.assertEqual(air.mismatches(MATCHED), [])

    def test_a_lost_address_space_in_an_aggregate_is_found(self):
        bad = air.mismatches(LOST)
        self.assertEqual(len(bad), 1)
        self.assertEqual(bad[0][0], 'run')
        self.assertIn('argument 0', bad[0][1])

    def test_a_lost_address_space_on_a_pointer_is_found(self):
        module = ('define internal void @load(ptr addrspace(1) noundef %0) {\n'
                  '  ret void\n}\n'
                  'define void @kernel(ptr noundef %0) {\n'
                  '  call void @load(ptr %0)\n  ret void\n}\n')
        self.assertEqual([b[0] for b in air.mismatches(module)], ['load'])

    def test_constants_and_attributes_are_not_types(self):
        module = ('define internal float @scale(float noundef %0, '
                  '{ i64 } noundef %1) {\n  ret float %0\n}\n'
                  'define void @kernel() {\n'
                  '  %1 = call noundef float @scale(float 1.000000e+00, '
                  '{ i64 } { i64 4 })\n  ret void\n}\n')
        self.assertEqual(air.mismatches(module), [])

    def test_return_and_count_mismatches_are_found(self):
        module = ('define internal i32 @f(i64 noundef %0) {\n  ret i32 0\n}\n'
                  'define void @kernel() {\n'
                  '  %1 = call float @f(i64 1)\n'
                  '  %2 = call i32 @f(i64 1, i64 2)\n  ret void\n}\n')
        details = [b[1] for b in air.mismatches(module)]
        self.assertTrue(any('returns float' in d for d in details))
        self.assertTrue(any('2 arguments' in d for d in details))

    def test_kernels_are_found_from_launches(self):
        found = air.kernels(air.ROOT)
        self.assertIn(('render/gpu.mojo', 'rasterize_kernel'), found)
        self.assertEqual(len(found), 37)


class DiscoveryTests(unittest.TestCase):
    def discover(self, source):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'fixture.mojo').write_text(source)
            with patch.object(air, 'MODULES', ('fixture.mojo',)):
                return air.kernels(root)

    def test_all_launch_sites_resolve_before_unique_kernels_are_returned(self):
        source = ('def kernel():\n    pass\n'
                  'ctx.enqueue_function[kernel]()\n'
                  'ctx.enqueue_function [\n    kernel\n] ()\n')
        self.assertEqual(self.discover(source), [('fixture.mojo', 'kernel')])

    def test_comments_and_strings_are_not_launches_or_definitions(self):
        source = ('# enqueue_function[unknown]()\n'
                  'var text = "enqueue_function[unknown[T]]()"\n'
                  '"""\ndef unknown():\n    pass\n"""\n')
        self.assertEqual(self.discover(source), [])
        with self.assertRaisesRegex(air.AirError, 'local, non-parameterized'):
            self.discover(source + 'ctx.enqueue_function[unknown]()\n')

    def test_parameterized_imported_or_missing_definitions_fail(self):
        for definition in ['def other[T: Int]():\n    pass\n',
                           'from imported import other\n', '',
                           'def outer():\n    def other():\n        pass\n']:
            with self.subTest(definition=definition):
                source = ('def good():\n    pass\n'
                          'ctx.enqueue_function[good]()\n' + definition +
                          'ctx.enqueue_function[other]()\n')
                with self.assertRaisesRegex(air.AirError, 'kernel other must have a local'):
                    self.discover(source)

    def test_unsupported_launch_syntax_cannot_hide_beside_a_good_launch(self):
        for launch in ['ctx.enqueue_function[good[T]]()',
                       'ctx.enqueue_function[module.good]()',
                       'ctx.enqueue_function[good, T]()',
                       'ctx.enqueue_function[](good)',
                       'ctx.enqueue_function(good)',
                       'var launch = ctx.enqueue_function']:
            with self.subTest(launch=launch):
                with self.assertRaisesRegex(air.AirError, 'unsupported enqueue_function syntax'):
                    self.discover('def good():\n    pass\n'
                                  'ctx.enqueue_function[good]()\n' + launch + '\n')

    def test_unterminated_source_fails(self):
        with self.assertRaisesRegex(air.AirError, 'unsupported kernel source syntax'):
            self.discover('ctx.enqueue_function[good\n')

    def test_unsupported_discovery_fails_cli_before_emitting(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'fixture.mojo').write_text(
                'from imported import kernel\nctx.enqueue_function[kernel]()\n')
            out, err = io.StringIO(), io.StringIO()
            with patch.object(air, 'ROOT', root), patch.object(air, 'MODULES', ('fixture.mojo',)):
                with patch.object(air.subprocess, 'run') as run:
                    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                        code = air.main([])
            run.assert_not_called()
            self.assertEqual(code, 1)
            self.assertNotIn('PASS', out.getvalue())
            self.assertIn('local, non-parameterized', err.getvalue())


BODY = 'define void @kernel() {\n  ret void\n}\n'


def kernel_symbol(kernel):
    path, name = kernel
    return (path[:-len('.mojo')].replace('/', '_') + '_' + name +
            '6A6A6A6AoA6A_b8ccca8f7480edaa')


def kernel_module(kernel, module=BODY, symbol=None, emitted=None):
    # Reduced from the pinned compiler's actual copy_bytes_kernel AIR captured
    # during qualification: !air.kernel -> entry node -> defined symbol, and
    # the entry's attribute group marks it as a Metal kernel.
    symbol = symbol or kernel_symbol(kernel)
    emitted = symbol if emitted is None else emitted
    lines = []
    for line in module.splitlines():
        if line.startswith('define void @kernel('):
            line = line.replace('@kernel(', '@' + symbol + '(')
            line = line.removesuffix('{') + '#0 {'
        lines.append(line)
    return air.ENTRY + emitted + '\n' + '\n'.join(lines) + ('\nattributes #0 = { "metal.kernel"="true" }\n'
                              '!air.kernel = !{!29}\n'
                              '!19 = !{}\n!28 = !{}\n'
                              f'!29 = !{{ptr @{symbol}, !19, !28}}\n')


class SignatureTests(unittest.TestCase):
    def test_declarations_are_checked_in_both_directions(self):
        for expected, actual in [('ptr', 'ptr addrspace(1)'),
                                 ('ptr addrspace(1)', 'ptr')]:
            with self.subTest(expected=expected):
                module = (f'declare void @f({expected})\n'
                          'define void @kernel() {\n'
                          f'  call void @f({actual} null)\n  ret void\n}}\n')
                self.assertEqual(len(air.mismatches(module)), 1)
                self.assertEqual(air.mismatches(module.replace(
                    f'@f({actual} null)', f'@f({expected} null)')), [])

    def test_quoted_names_resolve_to_the_same_symbol(self):
        for definition, call in [('f', '"f"'), ('"f"', 'f'),
                                 ('"f with ; space"', '"f with ; space"'),
                                 ('"f\\22q"', '"f\\22q"'), ('f', '"\\66"')]:
            with self.subTest(definition=definition, call=call):
                module = (f'declare void @{definition}(ptr addrspace(1))\n'
                          'define void @kernel() {\n'
                          f'  call void @{call}(ptr null)\n  ret void\n}}\n')
                self.assertEqual(len(air.mismatches(module)), 1)
                self.assertEqual(air.mismatches(module.replace(
                    '(ptr null)', '(ptr addrspace(1) null)')), [])

    def test_pointer_and_aggregate_returns_are_checked(self):
        for expected, actual in [('ptr addrspace(1)', 'ptr'),
                                 ('{ ptr addrspace(1), i64 }', '{ ptr, i64 }')]:
            with self.subTest(expected=expected):
                module = (f'declare {expected} @f()\n'
                          'define void @kernel() {\n'
                          f'  %v = call {actual} @f()\n  ret void\n}}\n')
                self.assertEqual(len(air.mismatches(module)), 1)
                self.assertEqual(air.mismatches(module.replace(
                    f'call {actual}', f'call {expected}')), [])

    def test_literal_aggregate_array_and_vector_types(self):
        kind = '{ [2 x ptr addrspace(1)], <4 x float>, <{ i32, ptr }> }'
        module = (f'declare void @f({kind})\n'
                  'define void @kernel() {\n'
                  f'  call void @f({kind} zeroinitializer)\n  ret void\n}}\n')
        self.assertEqual(air.mismatches(module), [])
        self.assertEqual(len(air.mismatches(module.replace(
            'declare void @f(' + kind,
            'declare void @f(' + kind.replace('ptr addrspace(1)', 'ptr')))), 1)

    def test_captured_metal_float_and_splat_literals(self):
        for kind, value in [('float', 'f0xBF490000'),
                            ('<4 x float>', 'splat (float f0xCF000000)'),
                            ('<4 x float>', 'splat (float 1.000000e+00)')]:
            with self.subTest(value=value):
                module = (f'declare void @f({kind})\n' + BODY.replace(
                    'ret void', f'call void @f({kind} {value})\n  ret void'))
                self.assertEqual(air.mismatches(module), [])
                self.assertEqual(len(air.mismatches(module.replace(
                    f'declare void @f({kind})', 'declare void @f(i32)'))), 1)

    def test_uncaptured_or_malformed_float_forms_fail(self):
        for item in ['float f0xBAD', 'float f0xBF490000extra',
                     'i32 f0xBF490000', '<4 x i32> splat (i32 1)',
                     '<4 x float> splat ()', '<4 x float> splat (float)',
                     '<4 x float> splat (float f0xBAD)',
                     '<4 x float> splat (float 1.0) trailing']:
            with self.subTest(item=item), self.assertRaises(air.AirError):
                air.mismatches('declare void @f(float)\n' + BODY.replace(
                    'ret void', f'call void @f({item})\n  ret void'))

    def test_supported_call_flags_attributes_and_indentation(self):
        module = ('  declare fastcc noundef float @f(float noundef)\n'
                  'define void @kernel() local_unnamed_addr #0 !dbg !1 {\n'
                  '  %x = tail call fast fastcc noundef float @f(float 1.0) #1, !dbg !2\n'
                  '  ret void\n}\n')
        self.assertEqual(air.mismatches(module), [])

    def test_comments_strings_and_no_call_bodies_are_allowed(self):
        module = ('source_filename = "call @fake()"\n'
                  '; call ptr @missing()\n' + BODY.replace(
                      'ret void', 'ret void ; call ptr @missing()'))
        self.assertEqual(air.mismatches(module), [])

    def test_call_words_in_values_globals_and_labels_are_not_opcodes(self):
        module = ('@call = external global float\n'
                  'define void @kernel(ptr %call) {\n'
                  '  %x = load float, ptr %call\n'
                  '  %y = load float, ptr @call\n'
                  '  br label %invoke\n'
                  'invoke:\n  br label %callbr\n'
                  'callbr:\n  ret void\n}\n')
        self.assertEqual(air.mismatches(module), [])

    def test_conflicting_or_duplicate_definitions_fail(self):
        for module in [BODY + BODY,
                       'declare void @f(ptr)\ndeclare void @f(i32)\n' + BODY]:
            with self.subTest(module=module), self.assertRaises(air.AirError):
                air.mismatches(module)

    def test_missing_declaration_fails(self):
        with self.assertRaisesRegex(air.AirError, 'missing definition or declaration'):
            air.mismatches(BODY.replace('ret void', 'call void @missing()\n  ret void'))

    def test_calls_outside_a_function_fail(self):
        for instruction in ['call void @f(ptr null)',
                            '%x = call i32 @f(ptr null)']:
            with self.subTest(instruction=instruction):
                with self.assertRaisesRegex(air.AirError, 'call outside function'):
                    air.mismatches('declare i32 @f(ptr addrspace(1))\n' +
                                   BODY + instruction + '\n')

    def test_missing_or_incomplete_function_bodies_fail(self):
        for module in ['', 'not AIR\n', '; a comment\n', 'declare void @f()\n',
                       'define void @f()\n', 'define void @f() {\n',
                       'define void @f() {\n}\n',
                       'define void @f() {\nnot an instruction\n}\n',
                       'define void @f() {\n%x = add i32 1, 2\n}\n',
                       'define void @f() {\nentry:\n; no instructions\n}\n']:
            with self.subTest(module=module), self.assertRaises(air.AirError):
                air.mismatches(module)

    def test_unsupported_call_forms_fail(self):
        for instruction in ['call void %f()', 'call void asm "", ""()',
                            'invoke void @f() to label %a unwind label %b',
                            'callbr void @f() to label %a [label %b]',
                            'call void (i32, ...) @f(i32 1)',
                            'call cc 10 void @f()', 'call unknown @f()',
                            'call void @f(unknown %x)',
                            'call void @f() [ "deopt"(i32 1) ]',
                            'call void @f() unknown_attribute']:
            with self.subTest(instruction=instruction), self.assertRaises(air.AirError):
                air.mismatches('declare void @f()\n' + BODY.replace(
                    'ret void', instruction + '\n  ret void'))

    def test_malformed_call_inputs_fail(self):
        for instruction in ['call void @f(', 'call void @f(i32 1,)',
                            'call void @f(i32)', 'call void @f(i32 noundef)',
                            'call void @f(i32 align 4)', 'call void @f({ i32 ] %x)',
                            'call void @f()(',
                            'call void @"unterminated()', 'call void @f(i8* %x)',
                            'call void @f(ptr addrspace(no) %x)']:
            with self.subTest(instruction=instruction), self.assertRaises(air.AirError):
                air.mismatches('declare void @f(i32)\n' + BODY.replace(
                    'ret void', instruction + '\n  ret void'))

    def test_unsupported_or_malformed_signatures_fail(self):
        for declaration in ['declare void @f(...)', 'declare void @f(%T)',
                            'declare void @f(i32,)', 'declare void @f({ ptr ])',
                            'declare unknown @f()', 'declare void @f(']:
            with self.subTest(declaration=declaration), self.assertRaises(air.AirError):
                air.mismatches(declaration + '\n' + BODY)

    def test_split_top_respects_quoted_delimiters(self):
        self.assertEqual(air.split_top('ptr %"a,b(c)", i32 0'),
                         ['ptr %"a,b(c)"', 'i32 0'])


class KernelEntryTests(unittest.TestCase):
    KERNEL = ('render/gpu.mojo', 'copy_bytes_kernel')

    def test_metadata_binds_the_defined_marked_entry(self):
        self.assertEqual(air.mismatches(kernel_module(self.KERNEL), self.KERNEL), [])

    def test_quoted_entry_symbols_are_resolved(self):
        module = kernel_module(self.KERNEL)
        name = 'render_gpu_copy_bytes_kernel6A6A6A6AoA6A_b8ccca8f7480edaa'
        module = module.replace('@' + name, '@"' + name + '"')
        self.assertEqual(air.mismatches(module, self.KERNEL), [])

    def test_a_helper_only_record_cannot_claim_a_kernel(self):
        helper = BODY.replace('@kernel', '@helper')
        with self.assertRaisesRegex(air.AirError, '!air.kernel'):
            air.mismatches(air.ENTRY + kernel_symbol(self.KERNEL) + '\n' + helper, self.KERNEL)
        with self.assertRaisesRegex(air.AirError, 'no function body'):
            air.mismatches(kernel_module(self.KERNEL, helper), self.KERNEL)

    def test_a_different_marked_kernel_cannot_use_the_label(self):
        for other in [('render/gpu.mojo', 'copy_floats_kernel'),
                      ('render/gpu_vxgi.mojo', 'copy_bytes_kernel'),
                      ('render/gpu.mojo', 'copy_bytes_kernel_helper'),
                      ('render/gpu.mojo', 'copy_bytes_kernel2')]:
            with self.subTest(other=other):
                with self.assertRaisesRegex(air.AirError, 'does not match'):
                    air.mismatches(kernel_module(other, emitted=kernel_symbol(self.KERNEL)), self.KERNEL)

    def test_missing_malformed_duplicate_or_ambiguous_metadata_fails(self):
        valid = kernel_module(self.KERNEL)
        for module in [valid.replace('!{!29}', '!{}'),
                       valid.replace('!{!29}', '!{!29, !30}'),
                       valid.replace('!{!29}', '!{!99}'),
                       valid.replace('!19 = !{}\n', ''),
                       valid.replace('!29 = !{ptr', '!29 = !{i64'),
                       valid + '!air.kernel = !{!29}\n',
                       valid + '!29 = !{}\n']:
            with self.subTest(module=module), self.assertRaises(air.AirError):
                air.mismatches(module, self.KERNEL)

    def test_actual_truncated_and_specialized_names_need_no_guessing(self):
        for kernel, symbol in [
                (('render/gpu.mojo', 'bloom_composite_kernel'),
                 'render_gpu_bloom_composite_ker6A6A6A6A_d1876a7b8107b01b'),
                (('render/gpu.mojo', 'blur_kernel'),
                 'render_gpu_blur_kernel_Point6A6A6A6AoA6A6A_40ffe11d65f1390d')]:
            with self.subTest(symbol=symbol):
                self.assertEqual(air.mismatches(
                    kernel_module(kernel, symbol=symbol), kernel), [])

    def test_colliding_source_prefixes_bind_distinct_exact_symbols(self):
        kernels = [('render/gpu.mojo', 'a_long_kernel_name_with_a_common_prefix_one'),
                   ('render/gpu.mojo', 'a_long_kernel_name_with_a_common_prefix_two')]
        self.assertEqual(kernel_symbol(kernels[0])[:30], kernel_symbol(kernels[1])[:30])
        symbols = ['render_gpu_a_long_kernel_name6A_' + digit * 16 for digit in '12']
        records = [kernel_module(kernel, symbol=symbol)
                   for kernel, symbol in zip(kernels, symbols)]
        for kernel, record in zip(kernels, records):
            self.assertEqual(air.mismatches(record, kernel), [])
        for index in range(2):
            swapped = air.ENTRY + symbols[index] + '\n' + records[1 - index].split('\n', 1)[1]
            with self.assertRaisesRegex(air.AirError, 'does not match compiler-returned'):
                air.mismatches(swapped, kernels[index])

    def test_entry_name_must_be_present_once_before_ir(self):
        valid = kernel_module(self.KERNEL)
        entry, ir = valid.split('\n', 1)
        for module in [ir, air.ENTRY + '\n' + ir, valid + entry + '\n', ir + entry + '\n']:
            with self.subTest(module=module):
                with self.assertRaisesRegex(air.AirError, 'emitted entry name'):
                    air.mismatches(module, self.KERNEL)

    def test_missing_or_false_metal_kernel_attribute_fails(self):
        valid = kernel_module(self.KERNEL)
        for module in [valid.replace('"metal.kernel"="true"', ''),
                       valid.replace('"metal.kernel"="true"', '"metal.kernel"="false"'),
                       valid.replace('attributes #0', 'attributes #1')]:
            with self.subTest(module=module):
                with self.assertRaisesRegex(air.AirError, 'lacks metal.kernel'):
                    air.mismatches(module, self.KERNEL)


class EmissionTests(unittest.TestCase):
    # Keep the CLI probes at the real discovery count. No compiler is run:
    # every invocation of subprocess.run is replaced by a fixed result.
    def setUp(self):
        self.found = air.kernels(air.ROOT)
        self.assertTrue(self.found)

    def output(self, records):
        return ''.join(air.SEPARATOR + ':'.join(kernel) + '\n' + module
                       for kernel, module in records)

    def cli(self, stdout, returncode=0):
        result = subprocess.CompletedProcess(['mock-mojo'], returncode, stdout,
                                             'fixture emission failed')
        out, err = io.StringIO(), io.StringIO()
        with patch.object(air.subprocess, 'run', return_value=result) as run:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = air.main(['--mojo', '/mock-mojo-never-executed'])
        run.assert_called_once()
        return code, out.getvalue(), err.getvalue()

    def assert_fails(self, stdout, reason):
        code, out, err = self.cli(stdout)
        self.assertEqual(code, 1)
        self.assertNotIn('PASS', out)
        self.assertIn(reason, err)

    def test_complete_modules_with_no_calls_pass(self):
        code, out, err = self.cli(self.output((k, kernel_module(k)) for k in self.found))
        self.assertEqual((code, err), (0, ''))
        self.assertIn(f'PASS {len(self.found)} Metal kernel AIR modules', out)
        self.assertIn('supported direct-call types', out)

    def test_empty_output_fails(self):
        self.assert_fails('', 'missing AIR records')

    def test_missing_records_fail(self):
        self.assert_fails(self.output([(self.found[0], kernel_module(self.found[0]))]), 'missing AIR records')

    def test_all_empty_records_fail(self):
        self.assert_fails(self.output((k, '') for k in self.found), 'empty AIR record')

    def test_entry_names_cannot_be_missing_duplicated_or_reused(self):
        first = kernel_module(self.found[0])
        entry, ir = first.split('\n', 1)
        for bad in [ir, first + entry + '\n']:
            with self.subTest(bad=bad):
                records = [(k, bad if index == 0 else kernel_module(k))
                           for index, k in enumerate(self.found)]
                self.assert_fails(self.output(records), 'emitted entry name')
        records = [(k, kernel_module(k, emitted=kernel_symbol(self.found[0])))
                   for k in self.found]
        self.assert_fails(self.output(records), 'entry reused across kernel records')

    def test_emitter_pairs_name_and_asm_from_each_compile_result(self):
        def capture(command, **kwargs):
            self.assertIn('--Werror', command)
            program = Path(command[-1]).read_text()
            for index, (module, name) in enumerate(self.found):
                self.assertIn(f'var compiled_{index} = _compile_code[kernel_{index},', program)
                self.assertIn(f'print("{air.ENTRY}" + String(compiled_{index}.function_name))', program)
                self.assertIn(f'print(compiled_{index}.asm)', program)
            return subprocess.CompletedProcess(command, 0, self.output(
                (k, kernel_module(k)) for k in self.found), '')
        with patch.object(air.subprocess, 'run', side_effect=capture):
            self.assertEqual(len(air.emit(air.ROOT, '/mock-mojo', self.found)), len(self.found))

    def test_duplicate_cannot_hide_a_bad_record(self):
        records = [(k, kernel_module(k, LOST if index == 0 else BODY))
                   for index, k in enumerate(self.found)]
        self.assert_fails(self.output(records + [(self.found[0], kernel_module(self.found[0]))]),
                          'duplicate AIR record')
        # Negative control: the original bad record itself is a type failure.
        self.assert_fails(self.output(records), 'call type mismatches')

    def test_unexpected_record_fails(self):
        self.assert_fails(self.output([(('/unexpected.mojo', 'unknown'), BODY)]),
                          'unexpected AIR record')

    def test_unexpected_preamble_fails(self):
        self.assert_fails('diagnostic text\n' + self.output((k, kernel_module(k)) for k in self.found),
                          'unexpected output')

    def test_each_record_requires_a_function_body(self):
        for bad in ['not AIR\n', '; comment only\n', 'declare void @f()\n']:
            with self.subTest(bad=bad):
                records = [(k, bad if index == 0 else kernel_module(k))
                           for index, k in enumerate(self.found)]
                self.assert_fails(self.output(records), 'AIR check failed')

    def test_diagnostics_after_a_module_fail(self):
        records = [(k, kernel_module(k) + 'emission failed\n' if index == 0 else kernel_module(k))
                   for index, k in enumerate(self.found)]
        self.assert_fails(self.output(records), 'unrecognized output')

    def test_no_discovery_fails_without_running_a_compiler(self):
        out, err = io.StringIO(), io.StringIO()
        with patch.object(air, 'kernels', return_value=[]):
            with patch.object(air.subprocess, 'run') as run:
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                    code = air.main([])
        run.assert_not_called()
        self.assertEqual(code, 1)
        self.assertNotIn('PASS', out.getvalue())
        self.assertIn('no kernels discovered', err.getvalue())

    def test_duplicate_discovery_fails(self):
        with self.assertRaisesRegex(air.AirError, 'duplicate entries'):
            air.emitted_modules('', [self.found[0], self.found[0]])

    def test_emitter_failure_does_not_pass(self):
        code, out, err = self.cli('', returncode=1)
        self.assertEqual(code, 1)
        self.assertNotIn('PASS', out)
        self.assertIn('AIR emission failed', err)

    def test_emitter_timeout_does_not_pass(self):
        out, err = io.StringIO(), io.StringIO()
        with patch.object(air.subprocess, 'run', side_effect=subprocess.TimeoutExpired(
                'mock-mojo', 1800)):
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = air.main([])
        self.assertEqual(code, 1)
        self.assertNotIn('PASS', out.getvalue())
        self.assertIn('AIR check failed', err.getvalue())


if __name__ == '__main__':
    unittest.main()
