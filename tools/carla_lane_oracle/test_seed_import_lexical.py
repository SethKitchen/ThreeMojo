# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact observed text may share only immutable import-name computations."""
import ast
from contextlib import contextmanager
from contextvars import copy_context
import hashlib
from pathlib import Path
import re
import sys
import tempfile
import threading
import types
import unittest
from unittest.mock import patch

import seed_count_contracts as seed
import source_contracts as source

TEXT = ('# import ignored\nfrom extensions.carla.foo import Bar, baz as alias\n'
        'from pkg import (\n    one,\n    two as second,\n)\n'
        'import loaders.xml, render.color_math as colors\nvar ignored = 1\n')
PARSER_AST = '0ee9c9e554df9ab36dde92ed523a7d9271a12d7b1ce2731e00edc0942f8c23cf'
DEPENDENCY_AST = '311bade2b41a5d4c61a6cbf796a361cc2e07624f5404ef0c550ef781b79fd61f'


class SeedImportLexicalTests(unittest.TestCase):
    def tearDown(self):
        self.assertIsNone(source._active_lexical_memo())

    @contextmanager
    def parser_calls(self):
        calls = []
        previous = sys.getprofile()
        code = seed.affected.imported_names.__code__
        def profile(frame, event, argument):
            if event == 'call' and frame.f_code is code: calls.append(frame.f_locals['source'])
        sys.setprofile(profile)
        try: yield calls
        finally: sys.setprofile(previous)

    def test_actual_parser_and_observation_traversal_ast_unchanged(self):
        tree = ast.parse(Path(seed.affected.__file__).read_text())
        parser = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'imported_names')
        self.assertEqual(hashlib.sha256(ast.dump(parser, include_attributes=False).encode()).hexdigest(), PARSER_AST)
        tree = ast.parse(Path(seed.__file__).read_text())
        dependency = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'dependency_inventory')
        calls = [n for n in ast.walk(dependency) if isinstance(n, ast.Call)
                 and isinstance(n.func, ast.Name) and n.func.id == '_imported_names']
        self.assertEqual(len(calls), 1)
        calls[0].func = ast.Attribute(value=ast.Name(id='affected', ctx=ast.Load()),
                                     attr='imported_names', ctx=ast.Load())
        self.assertEqual(hashlib.sha256(ast.dump(dependency, include_attributes=False).encode()).hexdigest(), DEPENDENCY_AST)

    def test_actual_parser_no_scope_nested_reuse_and_fresh_lists(self):
        expected = seed.affected.imported_names(TEXT)
        with self.parser_calls() as calls:
            for _ in range(2): self.assertEqual(seed._imported_names(TEXT), expected)
            self.assertEqual(len(calls), 2)
            with source.lexical_memo_scope():
                first = seed._imported_names(TEXT)
                first.clear()
                with source.lexical_memo_scope():
                    second = seed._imported_names(TEXT)
                self.assertEqual(second, expected)
                self.assertIsNot(first, second)
                self.assertEqual(len(calls), 3)
            self.assertEqual(seed._imported_names(TEXT), expected)
            self.assertEqual(len(calls), 4)

    def test_exact_text_keys_and_string_subclass_fallback(self):
        class Text(str): pass
        with self.parser_calls() as calls, source.lexical_memo_scope():
            for value in (TEXT, TEXT + '# different\n', TEXT.replace('pkg', 'other'), Text(TEXT), Text(TEXT)):
                self.assertEqual(seed._imported_names(value), seed._IMPORT_NAME_PARSER(value))
            # Each explicit expected call is separate; the subclass never enters the memo.
            self.assertEqual(len(calls), 10)
            self.assertEqual(len(source._active_lexical_memo().entries), 3)

    def test_exact_regex_changes_recompute_with_actual_parser(self):
        replacements = {'FROM_IMPORT': re.compile(r'^\s*from\s+([A-Za-z_][\w.]*)\s+import\s+(.*)$', re.I),
                        'PLAIN_IMPORT': re.compile(r'^\s*import\s+(.*)$', re.I),
                        'ALIAS': re.compile(r'\s+(?:as|alias)\s+')}
        for name, replacement in replacements.items():
            with self.subTest(name=name), source.lexical_memo_scope(), self.parser_calls() as calls:
                seed._imported_names(TEXT)
                with patch.object(seed.affected, name, replacement):
                    expected = seed._IMPORT_NAME_PARSER(TEXT)
                    self.assertEqual(seed._imported_names(TEXT), expected)
                    self.assertEqual(seed._imported_names(TEXT), expected)
                self.assertEqual(len(calls), 3)
                self.assertEqual(len(source._active_lexical_memo().entries), 2)

    def test_exotic_regex_and_parser_replacements_preserve_behavior(self):
        class Pattern:
            __hash__ = None
            def __init__(self, original): self.original = original; self.calls = 0
            def match(self, value): self.calls += 1; return self.original.match(value)
        with source.lexical_memo_scope():
            seed._imported_names(TEXT)
            pattern = Pattern(seed.affected.FROM_IMPORT)
            with patch.object(seed.affected, 'FROM_IMPORT', pattern):
                for _ in range(2): self.assertEqual(seed._imported_names(TEXT), seed._IMPORT_NAME_PARSER(TEXT))
            self.assertGreater(pattern.calls, 0)
            for output in (None, 'not an encoded result', [''], ['a\nb'], object()):
                def replacement(text): return output
                with patch.object(seed.affected, 'imported_names', replacement):
                    self.assertIs(seed._imported_names(TEXT), output)
            class Callable:
                __hash__ = None
                def __call__(self, text): return self
            replacement = Callable()
            with patch.object(seed.affected, 'imported_names', replacement):
                self.assertIs(seed._imported_names(TEXT), replacement)

    def test_parser_same_object_code_defaults_and_equal_code_fall_back(self):
        parser = seed._IMPORT_NAME_PARSER
        def changed(source): raise ValueError('changed parser code')
        with source.lexical_memo_scope():
            seed._imported_names(TEXT)
            old = parser.__code__
            try:
                parser.__code__ = changed.__code__
                for _ in range(2):
                    with self.assertRaisesRegex(ValueError, 'changed parser code'): seed._imported_names(TEXT)
            finally: parser.__code__ = old
            equal = old.replace(co_filename=old.co_filename + '.equal')
            self.assertEqual(old, equal)
            try:
                parser.__code__ = equal
                with self.parser_calls() as calls:
                    for _ in range(2): seed._imported_names(TEXT)
                self.assertEqual(len(calls), 2)
            finally: parser.__code__ = old
            for attribute, value in (('__defaults__', (None,)), ('__kwdefaults__', {'unused': None})):
                original = getattr(parser, attribute)
                try:
                    setattr(parser, attribute, value)
                    with self.parser_calls() as calls:
                        for _ in range(2): seed._imported_names(TEXT)
                    self.assertEqual(len(calls), 2)
                finally: setattr(parser, attribute, original)

    def test_encoder_replacement_and_same_object_code_or_defaults_fall_back(self):
        encoder = seed._imported_name_lines
        def changed(text): raise ValueError('optional encoder must not run')
        with source.lexical_memo_scope():
            seed._imported_names(TEXT)
            with patch.object(seed, '_imported_name_lines', changed):
                self.assertEqual(seed._imported_names(TEXT), seed._IMPORT_NAME_PARSER(TEXT))
            old = encoder.__code__
            try:
                encoder.__code__ = changed.__code__
                self.assertEqual(seed._imported_names(TEXT), seed._IMPORT_NAME_PARSER(TEXT))
            finally: encoder.__code__ = old
            for attribute, value in (('__defaults__', (None,)), ('__kwdefaults__', {'unused': None})):
                original = getattr(encoder, attribute)
                try:
                    setattr(encoder, attribute, value)
                    with self.parser_calls() as calls:
                        for _ in range(2): seed._imported_names(TEXT)
                    self.assertEqual(len(calls), 2)
                finally: setattr(encoder, attribute, original)

    def test_original_parser_with_unsupported_names_is_not_encoded(self):
        with source.lexical_memo_scope(), patch.object(seed.affected, 'FROM_IMPORT', re.compile(r'^from ()(.*)$')):
            text = 'from thing import value\n'
            expected = seed._IMPORT_NAME_PARSER(text)
            self.assertIn('', expected)
            for _ in range(2): self.assertEqual(seed._imported_names(text), expected)
            self.assertEqual(source._active_lexical_memo().entries, {})
        for result in (None, [''], ['line\nbreak'], 'literal', object()):
            with patch.object(seed.affected, 'imported_names', lambda text: result):
                encoded = seed._imported_name_lines(TEXT)
                self.assertIs(type(encoded), tuple)
                self.assertIs(encoded[0], result)

    def test_wrong_parser_namespace_and_missing_optional_dependencies_fall_back(self):
        actual = seed.affected
        replacement = types.ModuleType('reexport')
        replacement.__dict__.update(vars(actual))
        replacement.FROM_IMPORT = object()
        with source.lexical_memo_scope(), patch.object(seed, 'affected', replacement), self.parser_calls() as calls:
            for _ in range(2): self.assertEqual(seed._imported_names(TEXT), seed._IMPORT_NAME_PARSER(TEXT))
            self.assertEqual(len(calls), 4)
            self.assertEqual(source._active_lexical_memo().entries, {})
        with patch.dict(vars(source)):
            del source._lexical_string
            self.assertEqual(seed._imported_names(TEXT), seed._IMPORT_NAME_PARSER(TEXT))
            with source.lexical_memo_scope():
                self.assertEqual(seed._imported_names(TEXT), seed._IMPORT_NAME_PARSER(TEXT))
        with patch.object(seed, 'source', object()):
            self.assertEqual(seed._imported_names(TEXT), seed._IMPORT_NAME_PARSER(TEXT))

    def test_parser_errors_never_create_entries(self):
        with source.lexical_memo_scope(), patch.object(seed.affected, 'FROM_IMPORT', re.compile(r'^(from)')):
            for _ in range(2):
                with self.assertRaises(IndexError): seed._imported_names(TEXT)
            self.assertEqual(source._active_lexical_memo().entries, {})

    def test_scope_exit_error_copied_context_and_other_thread(self):
        with self.parser_calls() as calls:
            with self.assertRaisesRegex(RuntimeError, 'outer failure'):
                with source.lexical_memo_scope():
                    state = source._active_lexical_memo()
                    seed._imported_names(TEXT)
                    copied = copy_context()
                    raise RuntimeError('outer failure')
            self.assertFalse(state.active)
            self.assertEqual(state.entries, {})
            for _ in range(2): copied.run(seed._imported_names, TEXT)
            self.assertEqual(len(calls), 3)
        with source.lexical_memo_scope():
            seed._imported_names(TEXT)
            state = source._active_lexical_memo()
            copied = copy_context()
            values = []
            def other(): values.append((source._active_lexical_memo(), seed._imported_names(TEXT)))
            thread = threading.Thread(target=lambda: copied.run(other))
            thread.start(); thread.join(timeout=5)
            self.assertFalse(thread.is_alive())
            self.assertEqual(len(values), 1)
            self.assertIsNone(values[0][0])
            self.assertEqual(values[0][1], seed._IMPORT_NAME_PARSER(TEXT))
            self.assertEqual(len(state.entries), 1)

    def test_dependency_census_reads_resolves_and_changed_text_remain_live(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = root / seed.MODULE
            module.parent.mkdir(parents=True)
            module.write_text('import dependency\n')
            (root / 'dependency.mojo').write_text('def helper():\n    pass\n')
            expected = {seed.MODULE, 'dependency.mojo'}
            reads, resolutions = [], []
            read_bytes, resolve = Path.read_bytes, seed.affected.resolve
            def read(path): reads.append(path.relative_to(root).as_posix()); return read_bytes(path)
            def resolving(*args): resolutions.append(args); return resolve(*args)
            with source.lexical_memo_scope(), patch.object(Path, 'read_bytes', read), \
                    patch.object(seed.affected, 'resolve', resolving):
                self.assertEqual(seed.dependency_inventory(root), expected)
                count, resolved = len(reads), len(resolutions)
                self.assertEqual(seed.dependency_inventory(root), expected)
                self.assertEqual(len(reads), 2 * count)
                self.assertEqual(len(resolutions), 2 * resolved)
                module.write_text('import other\n')
                (root / 'other.mojo').write_text('def other():\n    pass\n')
                self.assertEqual(seed.dependency_inventory(root), {seed.MODULE, 'other.mojo'})
                self.assertIn('other.mojo', reads)


if __name__ == '__main__':
    unittest.main()
