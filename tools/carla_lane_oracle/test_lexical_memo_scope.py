# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep invocation-local lexical reuse separate from live source admission."""
from contextvars import copy_context
from pathlib import Path
import tempfile
from threading import Thread
import unittest
from unittest.mock import patch

import border_parser_contracts as border
import source_contracts as source
import sum2_guard_contracts as guard
import winner_sign_contracts as winner


TEXT = 'def first():\n    return 1\n\nstruct Owner:\n    def second():\n        return 2\n'


class LexicalMemoScopeTests(unittest.TestCase):
    def tearDown(self):
        self.assertIsNone(source._active_lexical_memo())

    def test_only_scoped_declarations_and_routing_reuse_immutable_results(self):
        with patch.object(guard, 'function_span', wraps=guard.function_span) as declarations, \
             patch.object(guard, '_declaration_routing', wraps=guard._declaration_routing) as routing:
            for _ in range(2):
                guard.declaration(TEXT, 'first')
                guard.declaration_routing(TEXT)
            self.assertEqual((declarations.call_count, routing.call_count), (2, 2))
            with source.lexical_memo_scope():
                for _ in range(2):
                    self.assertIs(type(guard.declaration(TEXT, 'first')), str)
                    self.assertIs(type(guard.declaration_routing(TEXT)), str)
                self.assertEqual((declarations.call_count, routing.call_count), (3, 3))
            with source.lexical_memo_scope():
                guard.declaration(TEXT, 'first')
                guard.declaration_routing(TEXT)
            self.assertEqual((declarations.call_count, routing.call_count), (4, 4))

    def test_complete_text_name_and_owner_are_separate_keys(self):
        with source.lexical_memo_scope(), \
             patch.object(guard, 'function_span', wraps=guard.function_span) as calls:
            first = guard.declaration(TEXT, 'first')
            self.assertNotEqual(first, guard.declaration(TEXT, 'second', ('Owner',)))
            self.assertEqual(guard.declaration(TEXT, 'first', None), first)
            self.assertEqual(guard.declaration(TEXT, 'first', expected_owner=()), first)
            self.assertEqual(calls.call_count, 3)
            self.assertNotEqual(guard.declaration(TEXT.replace('return 1', 'return 3'), 'first'), first)
            # A comment outside the requested declaration is still part of the key.
            self.assertEqual(guard.declaration(TEXT+'# changed\n', 'first'), first)
            self.assertEqual(calls.call_count, 5)
            for _ in range(2):
                with self.assertRaisesRegex(ValueError, 'owner/scope changed'):
                    guard.declaration(TEXT, 'second', ())
            self.assertEqual(calls.call_count, 7)

    def test_mutable_owner_is_not_retained(self):
        owner = ['Owner']
        with source.lexical_memo_scope(), \
             patch.object(guard, 'function_span', wraps=guard.function_span) as calls:
            guard.declaration(TEXT, 'second', owner)
            guard.declaration(TEXT, 'second', owner)
            owner.clear()
            with self.assertRaisesRegex(ValueError, 'owner/scope changed'):
                guard.declaration(TEXT, 'second', owner)
            self.assertEqual(calls.call_count, 3)
            self.assertEqual(source._active_lexical_memo().entries, {})

    def test_operation_identity_and_mutable_outputs_are_not_aliased(self):
        def first(text): return 'first '+text
        def second(text): return 'second '+text
        def mutable(text): return [text]
        with source.lexical_memo_scope():
            self.assertEqual(source._lexical_string(first, ('value',)), 'first value')
            self.assertEqual(source._lexical_string(second, ('value',)), 'second value')
            result = source._lexical_string(mutable, ('value',))
            result.clear()
            self.assertEqual(source._lexical_string(mutable, ('value',)), ['value'])
            self.assertEqual(len(source._active_lexical_memo().entries), 2)

    def test_changed_lexical_helper_identity_is_observed(self):
        with source.lexical_memo_scope():
            guard.declaration(TEXT, 'first')
            guard.declaration_routing(TEXT)
            with patch.object(guard, 'function_span', side_effect=ValueError('span changed')):
                with self.assertRaisesRegex(ValueError, 'span changed'):
                    guard.declaration(TEXT, 'first')
            with patch.object(source, 'tokens', side_effect=ValueError('tokens changed')):
                with self.assertRaisesRegex(ValueError, 'tokens changed'):
                    guard.declaration(TEXT, 'first')
                with self.assertRaisesRegex(ValueError, 'tokens changed'):
                    guard.declaration_routing(TEXT)
            self.assertIn('def first', guard.declaration(TEXT, 'first'))

    def test_function_spans_and_existing_token_wrappers_remain_independent(self):
        with source.lexical_memo_scope():
            expected = guard.declaration(TEXT, 'first')
            span, positions, tokens = guard.function_span(TEXT, 'first')
            self.assertEqual(span, expected)
            tokens.clear()
            self.assertEqual(guard.declaration(TEXT, 'first'), expected)
            self.assertTrue(guard.function_span(TEXT, 'first')[2])
            source.tokens(TEXT).clear()
            self.assertTrue(source.tokens(TEXT))
        self.assertEqual(source._token_snapshot.cache_info().maxsize, 32)

    def test_nested_scope_borrows_and_outer_exception_clears_every_entry(self):
        with patch.object(guard, 'function_span', wraps=guard.function_span) as calls:
            with self.assertRaisesRegex(RuntimeError, 'outer failure'):
                with source.lexical_memo_scope():
                    state = source._active_lexical_memo()
                    guard.declaration(TEXT, 'first')
                    with self.assertRaisesRegex(ValueError, 'inner failure'):
                        with source.lexical_memo_scope():
                            self.assertIs(source._active_lexical_memo(), state)
                            guard.declaration(TEXT, 'first')
                            raise ValueError('inner failure')
                    self.assertTrue(state.entries)
                    guard.declaration(TEXT, 'first')
                    self.assertEqual(calls.call_count, 1)
                    raise RuntimeError('outer failure')
            self.assertFalse(state.active)
            self.assertEqual(state.entries, {})
            self.assertIsNone(source._active_lexical_memo())
            with source.lexical_memo_scope():
                guard.declaration(TEXT, 'first')
            self.assertEqual(calls.call_count, 2)

    def test_copied_context_cannot_revive_an_expired_scope(self):
        with source.lexical_memo_scope():
            old = source._active_lexical_memo()
            guard.declaration(TEXT, 'first')
            copied = copy_context()
        self.assertFalse(old.active)
        with patch.object(guard, 'function_span', wraps=guard.function_span) as calls:
            for _ in range(2): copied.run(guard.declaration, TEXT, 'first')
            self.assertEqual(calls.call_count, 2)
            self.assertEqual(old.entries, {})
            def fresh():
                with source.lexical_memo_scope():
                    self.assertIsNot(source._active_lexical_memo(), old)
                    guard.declaration(TEXT, 'first')
                    guard.declaration(TEXT, 'first')
            copied.run(fresh)
            self.assertEqual(calls.call_count, 3)
        self.assertIsNone(copied.run(source._active_lexical_memo))

    def test_copied_context_in_another_thread_does_not_borrow_scope(self):
        failures = []
        with source.lexical_memo_scope():
            parent = source._active_lexical_memo()
            guard.declaration(TEXT, 'first')
            copied = copy_context()
            def worker():
                try:
                    self.assertIsNone(source._active_lexical_memo())
                    with source.lexical_memo_scope():
                        child = source._active_lexical_memo()
                        self.assertIsNot(child, parent)
                        guard.declaration(TEXT, 'first')
                    self.assertFalse(child.active)
                    self.assertIsNone(source._active_lexical_memo())
                except BaseException as error:
                    failures.append(error)
            thread = Thread(target=copied.run, args=(worker,))
            thread.start()
            thread.join(timeout=5)
            self.assertFalse(thread.is_alive())
            if failures: raise failures[0]
            self.assertTrue(parent.active)
            self.assertTrue(parent.entries)

    def test_bounded_entries_evict_without_changing_lexical_results(self):
        with source.lexical_memo_scope(), \
             patch.object(guard, 'function_span', wraps=guard.function_span) as calls:
            expected = guard.declaration(TEXT, 'first')
            for index in range(source._LEXICAL_MEMO_LIMIT):
                self.assertEqual(guard.declaration(TEXT+f'# {index}\n', 'first'), expected)
            self.assertEqual(len(source._active_lexical_memo().entries), source._LEXICAL_MEMO_LIMIT)
            self.assertEqual(guard.declaration(TEXT, 'first'), expected)
            self.assertEqual(calls.call_count, source._LEXICAL_MEMO_LIMIT+2)

    def test_duplicate_wrong_scope_decoy_and_invalid_tokens_still_refuse(self):
        cases = (
            (TEXT+TEXT, 'first', 'missing or ambiguous'),
            ('# def first():\nvar decoy = "def first():"\n', 'first', 'missing or ambiguous'),
            ('if True:\n    def first():\n        pass\n', 'first', 'owner/scope changed'),
            ('def first():\n    value = (\n', 'first', 'invalid source tokens'),
        )
        with source.lexical_memo_scope():
            guard.declaration(TEXT, 'first')
            before = len(source._active_lexical_memo().entries)
            for text, name, message in cases:
                for _ in range(2):
                    with self.subTest(message=message), self.assertRaisesRegex(ValueError, message):
                        guard.declaration(text, name)
            self.assertEqual(len(source._active_lexical_memo().entries), before)

    def test_routing_binds_imports_aliases_decorators_and_scope(self):
        with source.lexical_memo_scope():
            expected = guard.declaration_routing(TEXT)
            for text in ('from other import value\n'+TEXT, 'comptime Alias = Owner\n'+TEXT,
                         '@no_inline\n'+TEXT, TEXT.replace('struct Owner:', 'struct Other:')):
                self.assertNotEqual(guard.declaration_routing(text), expected)
            with self.assertRaisesRegex(ValueError, 'invalid source tokens'):
                guard.declaration_routing(TEXT+'var broken = (\n')

    def test_complete_consumer_entries_share_nested_scope_and_clear_on_error(self):
        root = Path('/lexical-scope-test')
        seen = []
        def read(path, *args, **kwargs):
            state = source._active_lexical_memo()
            self.assertIsNotNone(state)
            seen.append(state)
            guard.declaration(TEXT, 'first')
            if path == root/winner.MIGRATION:
                with self.assertRaisesRegex(OSError, 'nested read failure'):
                    border.verify(root)
                self.assertIs(source._active_lexical_memo(), state)
                self.assertTrue(state.entries)
                raise OSError('outer read failure')
            self.assertEqual(path, root/border.MIGRATION)
            raise OSError('nested read failure')
        with patch.object(Path, 'read_bytes', read), self.assertRaisesRegex(OSError, 'outer read failure'):
            winner.verify(root)
        self.assertEqual(len(seen), 2)
        self.assertIs(seen[0], seen[1])
        self.assertFalse(seen[0].active)
        self.assertEqual(seen[0].entries, {})

    def test_same_path_changed_reads_and_live_census_are_never_memoized(self):
        with tempfile.TemporaryDirectory() as directory, source.lexical_memo_scope():
            root = Path(directory)
            path = root/'entry.mojo'
            path.write_text('def _require_sum2_environment():\n    pass\n')
            initial = guard.protected_inventory(root)
            self.assertEqual(set(initial), {'entry.mojo'})
            extra = root/'new_namespace'/'__init__.mojo'
            extra.parent.mkdir()
            extra.write_text('from extensions.carla.curve_sum2 import _require_sum2_environment\n')
            self.assertEqual(set(guard.protected_inventory(root)), {'entry.mojo', 'new_namespace/__init__.mojo'})
            extra.unlink()
            self.assertEqual(guard.protected_inventory(root), initial)
            real_read = Path.read_text
            changed = 'from other import changed\n'+path.read_text()
            with patch.object(Path, 'read_text', lambda p, *a, **k:
                              changed if p == path else real_read(p, *a, **k)):
                self.assertNotEqual(guard.protected_inventory(root), initial)
            self.assertEqual(guard.protected_inventory(root), initial)
            with patch.object(Path, 'read_text', side_effect=OSError('read failure')):
                with self.assertRaisesRegex(OSError, 'read failure'):
                    guard.protected_inventory(root)
            path.unlink()
            self.assertEqual(guard.protected_inventory(root), {})


if __name__ == '__main__':
    unittest.main()
