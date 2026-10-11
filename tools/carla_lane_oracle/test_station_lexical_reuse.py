# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact immutable station strings never replace live proof observations."""
import ast
from contextvars import copy_context
import hashlib
from pathlib import Path
import types
import unittest
from unittest.mock import patch

import map_station_contracts as station
import source_contracts as source

TEXT = 'def first():\n    return 1\n\nstruct Owner:\n    def second():\n        return 2\n'
SCANNER_AST = '3c7967f1d5b2e434899205a3af102f25a17c7ad59ecc42e3807a8a15cd1e447c'


class StationLexicalReuseTests(unittest.TestCase):
    def tearDown(self):
        self.assertIsNone(source._active_lexical_memo())

    def counted_scanner(self):
        calls = []
        original = station._declaration
        def scan(*args):
            calls.append(args)
            return original(*args)
        return calls, scan

    @staticmethod
    def outcome(function, *args):
        try:
            return ('return', function(*args))
        except Exception as error:
            return ('raise', type(error), error.args)

    def test_original_scanner_ast_and_public_signature_are_unchanged(self):
        tree = ast.parse(Path(station.__file__).read_text())
        scanner = next(n for n in tree.body if isinstance(n, ast.FunctionDef)
                       and n.name == '_declaration')
        scanner.name = 'declaration'
        self.assertEqual(hashlib.sha256(ast.dump(scanner, include_attributes=False).encode()).hexdigest(),
                         SCANNER_AST)
        public = next(n for n in tree.body if isinstance(n, ast.FunctionDef)
                      and n.name == 'declaration')
        self.assertEqual(ast.dump(public.args), ast.dump(scanner.args))

    def test_no_scope_recomputes_and_nested_scope_reuses_only_strings(self):
        calls, scan = self.counted_scanner()
        with patch.object(station, '_declaration', scan):
            for _ in range(2): station.declaration(TEXT, 'first', ())
            self.assertEqual(len(calls), 2)
            with source.lexical_memo_scope():
                expected = station.declaration(TEXT, 'first', ())
                self.assertIs(type(expected), str)
                with source.lexical_memo_scope():
                    self.assertEqual(station.declaration(TEXT, 'first', ()), expected)
                self.assertEqual(len(calls), 3)
            with source.lexical_memo_scope():
                station.declaration(TEXT, 'first', ())
            self.assertEqual(len(calls), 4)

    def test_exact_text_name_owner_keys_and_mutable_input_fallback(self):
        calls, scan = self.counted_scanner()
        with source.lexical_memo_scope(), patch.object(station, '_declaration', scan):
            first = station.declaration(TEXT, 'first', ())
            self.assertNotEqual(station.declaration(TEXT, 'second', ('Owner',)), first)
            self.assertEqual(station.declaration(TEXT + '# outside\n', 'first', ()), first)
            self.assertNotEqual(station.declaration(TEXT.replace('return 1', 'return 3'), 'first', ()), first)
            self.assertEqual(len(calls), 4)
            for _ in range(2):
                with self.assertRaisesRegex(ValueError, 'missing or ambiguous scoped declaration'):
                    station.declaration(TEXT, 'second', ())
            self.assertEqual(len(calls), 6)
            owner = ['Owner']
            for _ in range(2): station.declaration(TEXT, 'second', owner)
            owner.clear()
            with self.assertRaises(ValueError): station.declaration(TEXT, 'second', owner)
            class Text(str):
                pass
            for _ in range(2): station.declaration(Text(TEXT), 'first', ())
            self.assertEqual(len(calls), 11)
            self.assertEqual(len(source._active_lexical_memo().entries), 4)

    def test_changed_dependency_identity_cannot_reuse_a_warm_value(self):
        targets = ((station, '_declaration'), (source, 'tokens'),
                   (source, '_token_snapshot'), (station, 'require'),
                   (station.textwrap, 'dedent'))
        for module, name in targets:
            with self.subTest(name=name), source.lexical_memo_scope():
                station.declaration(TEXT, 'first', ())
                calls = []
                def fail(*args):
                    calls.append(args)
                    raise ValueError('changed dependency')
                with patch.object(module, name, fail):
                    for _ in range(2):
                        with self.assertRaisesRegex(ValueError, 'changed dependency'):
                            station.declaration(TEXT, 'first', ())
                self.assertEqual(len(calls), 2)
                self.assertIn('def first', station.declaration(TEXT, 'first', ()))

    def test_token_kind_changes_and_exotic_values_do_not_reuse_warm_results(self):
        kinds = ('INDENT', 'DEDENT', 'NEWLINE', 'COMMENT', 'NL', 'ENDMARKER')
        for name in kinds:
            calls, scan = self.counted_scanner()
            with self.subTest(name=name), source.lexical_memo_scope(), \
                    patch.object(station, '_declaration', scan):
                station.declaration(TEXT, 'first', ())
                with patch.object(station.tokenize, name, 10000):
                    expected = self.outcome(scan, TEXT, 'first', ())
                    self.assertEqual(self.outcome(station.declaration, TEXT, 'first', ()), expected)
                self.assertEqual(len(calls), 3)
        class Kind(int):
            __hash__ = None
        calls, scan = self.counted_scanner()
        with source.lexical_memo_scope(), patch.object(station, '_declaration', scan), \
                patch.object(station.tokenize, 'INDENT', Kind(station.tokenize.INDENT)):
            for _ in range(2): station.declaration(TEXT, 'first', ())
            self.assertEqual(len(calls), 2)
            self.assertEqual(source._active_lexical_memo().entries, {})

    def test_unhashable_callable_dependencies_use_the_unchanged_scanner(self):
        class Callable:
            __hash__ = None
            def __init__(self, original): self.original, self.calls = original, 0
            def __call__(self, *args):
                self.calls += 1
                return self.original(*args)
        targets = ((station, '_declaration'), (source, 'tokens'),
                   (source, '_token_snapshot'), (station, 'require'),
                   (station.textwrap, 'dedent'))
        for module, name in targets:
            with self.subTest(name=name), source.lexical_memo_scope():
                station.declaration(TEXT, 'first', ())
                replacement = Callable(getattr(module, name))
                with patch.object(module, name, replacement):
                    for _ in range(2): self.assertIn('def first', station.declaration(TEXT, 'first', ()))
                self.assertGreaterEqual(replacement.calls, 2)

    def test_missing_optional_cache_dependencies_and_exotic_modules_fall_back(self):
        tokens = source.tokens(TEXT)
        def token_source(text): return list(tokens)
        with patch.object(source, 'tokens', token_source), source.lexical_memo_scope():
            with patch.dict(vars(source)):
                del source._token_snapshot
                self.assertIn('def first', station.declaration(TEXT, 'first', ()))
                del source._lexical_string
                self.assertIn('def first', station.declaration(TEXT, 'first', ()))
        with patch.object(station, 'source', types.SimpleNamespace(tokens=token_source)):
            self.assertIn('def first', station.declaration(TEXT, 'first', ()))
        original = station.textwrap.dedent
        with patch.object(station, 'textwrap', types.SimpleNamespace(dedent=original)):
            self.assertIn('def first', station.declaration(TEXT, 'first', ()))
        # An uncached call must not read dependencies used only by the memo.
        with patch.dict(vars(source)):
            del source._token_snapshot
            with patch.object(source, 'tokens', token_source):
                self.assertIn('def first', station.declaration(TEXT, 'first', ()))

    def test_same_function_code_replacement_cannot_reuse_warm_declaration(self):
        targets = ((station, '_declaration'), (source, 'tokens'),
                   (station, 'require'), (station.textwrap, 'dedent'))
        def changed(*args): raise ValueError('same function code changed')
        for module, name in targets:
            with self.subTest(name=name), source.lexical_memo_scope():
                station.declaration(TEXT, 'first', ())
                function = getattr(module, name)
                code = function.__code__
                try:
                    function.__code__ = changed.__code__
                    with self.assertRaisesRegex(ValueError, 'same function code changed'):
                        station.declaration(TEXT, 'first', ())
                finally:
                    function.__code__ = code
                self.assertIn('def first', station.declaration(TEXT, 'first', ()))
        producer = source._token_snapshot.__wrapped__
        with source.lexical_memo_scope():
            station.declaration(TEXT, 'first', ())
            code = producer.__code__
            try:
                producer.__code__ = changed.__code__
                # Retain the separate token LRU's existing semantics: force a
                # producer call so this control isolates the declaration memo.
                source._token_snapshot.cache_clear()
                with self.assertRaisesRegex(ValueError, 'same function code changed'):
                    station.declaration(TEXT, 'first', ())
            finally:
                producer.__code__ = code
                source._token_snapshot.cache_clear()

    def test_equal_but_distinct_code_identity_does_not_reuse_warm_value(self):
        calls, scan = self.counted_scanner()
        with source.lexical_memo_scope(), patch.object(station, '_declaration', scan):
            station.declaration(TEXT, 'first', ())
            old = scan.__code__
            changed = old.replace(co_filename=old.co_filename + '.different')
            self.assertIsNot(changed, old)
            self.assertEqual(changed, old)
            try:
                scan.__code__ = changed
                station.declaration(TEXT, 'first', ())
            finally:
                scan.__code__ = old
            self.assertEqual(len(calls), 2)

    def test_default_and_kwdefault_mutations_take_uncached_path(self):
        targets = ((station, '_declaration'), (source, 'tokens'),
                   (station, 'require'), (station.textwrap, 'dedent'),
                   (source._token_snapshot, '__wrapped__'))
        for module, name in targets:
            for attribute, value in (('__defaults__', (None,)),
                                     ('__kwdefaults__', {'unused': None})):
                calls, scan = self.counted_scanner()
                with self.subTest(name=name, attribute=attribute), source.lexical_memo_scope(), \
                        patch.object(station, '_declaration', scan):
                    station.declaration(TEXT, 'first', ())
                    function = getattr(module, name)
                    original = getattr(function, attribute)
                    try:
                        setattr(function, attribute, value)
                        for _ in range(2): station.declaration(TEXT, 'first', ())
                    finally:
                        setattr(function, attribute, original)
                    self.assertEqual(len(calls), 3)

    def test_exotic_lru_wrapped_dependency_takes_uncached_path(self):
        calls, scan = self.counted_scanner()
        with source.lexical_memo_scope(), patch.object(station, '_declaration', scan):
            station.declaration(TEXT, 'first', ())
            with patch.object(source._token_snapshot, '__wrapped__', object()):
                for _ in range(2): station.declaration(TEXT, 'first', ())
            self.assertEqual(len(calls), 3)

    def test_outer_error_and_copied_context_do_not_retain_station_results(self):
        calls, scan = self.counted_scanner()
        with patch.object(station, '_declaration', scan):
            with self.assertRaisesRegex(RuntimeError, 'outer failure'):
                with source.lexical_memo_scope():
                    state = source._active_lexical_memo()
                    station.declaration(TEXT, 'first', ())
                    copied = copy_context()
                    raise RuntimeError('outer failure')
            self.assertFalse(state.active)
            self.assertEqual(state.entries, {})
            for _ in range(2): copied.run(station.declaration, TEXT, 'first', ())
            self.assertEqual(len(calls), 3)


if __name__ == '__main__':
    unittest.main()
