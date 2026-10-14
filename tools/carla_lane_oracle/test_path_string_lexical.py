# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Parsing-only acceleration preserves v9 observations and fallback protocols."""
import ast
from contextlib import ExitStack
import hashlib
import os
from pathlib import Path, PosixPath
import tempfile
import types
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as cleanup


def _baseline_regular(root, relative):
    parts = Path(relative).parts
    require(parts and (not Path(relative).is_absolute()) and ('..' not in parts), 'unsafe input path')
    path = Path(root)
    require(_root_unaliased(path), 'symbolic root or ancestor')
    for part in parts:
        path = path / part
        require(not path.is_symlink(), 'symlink input: ' + relative)
    require(stat.S_ISREG(path.stat().st_mode), 'input is not a regular file: ' + relative)
    return path


def _baseline_absolute_root_text(root):
    """Avoid reconstructing an ordinary absolute POSIX root; retain fallbacks."""
    if os.name == 'posix' and type(root) is PosixPath:
        raw = getattr(root, '_raw_paths', None)
        if type(raw) is list and len(raw) == 1 and (type(raw[0]) is str):
            text = raw[0]
            if text == '/' or (text.startswith('/') and all((part not in ('', '.', '..') for part in text[1:].split('/')))):
                return text
    return str(Path(root).absolute())


def _baseline_observe(self, root, path, value, mode):
    try:
        self._check_owner(root)
        require(type(path) is str and path and (Path(path).as_posix() == path) and (not Path(path).is_absolute()) and ('..' not in Path(path).parts), 'invalid operation observation path')
        require(mode in ('bytes', 'default', 'physical', 'utf8', 'supplied_default', 'supplied_physical'), 'unknown operation observation mode')
        require(type(value) is (bytes if mode == 'bytes' else str), 'non-builtin operation observation')
        if self._state == 'pending':
            self._observations.append((path, value, mode))
        else:
            self._match(root, path, value, mode)
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(self, error)


REFERENCE_REGULAR = types.FunctionType(_baseline_regular.__code__, vars(cleanup))
REFERENCE_ROOT = types.FunctionType(_baseline_absolute_root_text.__code__, vars(cleanup))
REFERENCE_OBSERVE = types.FunctionType(_baseline_observe.__code__, vars(cleanup))
ROOT_UNALIASED_AST = '080cd357266f42f087c52275240b84203b3dd054ad18b69a28e47ccf8edf6b0e'


class PathStringLexicalTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='path-string-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        for relative in ('file', 'nested/file', 'alternate', r'back\slash', '.hidden/file', 'a/.../file'):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture\n')

    @staticmethod
    def outcome(function, *args):
        try:
            result = function(*args)
            return ('return', str(result) if isinstance(result, Path) else result)
        except Exception as error:
            return ('raise', type(error), error.args)

    def test_root_alias_checker_ast_is_unchanged(self):
        tree = ast.parse(Path(cleanup.__file__).read_text())
        node = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == '_root_unaliased')
        self.assertEqual(hashlib.sha256(ast.dump(node, include_attributes=False).encode()).hexdigest(),
                         ROOT_UNALIASED_AST)

    def regular_events(self, function, relative, *, root=None, fault=None, mutate=False):
        events = []
        original_symlink, original_stat = Path.is_symlink, Path.stat
        original_os_stat = os.stat
        target_root = self.root if root is None else root
        root_text, alternate = str(self.root), str(self.root/'alternate')
        def symlink(path):
            # Inspect raw storage before str(path) can populate its string cache.
            raw = getattr(path, '_raw_paths', None)
            if mutate and type(raw) is list and raw == [root_text, 'file']:
                path._raw_paths = [alternate]
                for name in ('_str', '_drv', '_root', '_tail_cached'):
                    if hasattr(path, name): delattr(path, name)
                events.append(('raw-mutated', alternate))
            events.append(('is_symlink', str(path)))
            if fault == 'symlink': raise OSError('probe denied')
            return original_symlink(path)
        def stat(path, *args, **kwargs):
            events.append(('stat', str(path), args, tuple(sorted(kwargs.items()))))
            if fault == 'stat' and kwargs.get('follow_symlinks', True):
                raise OSError('final stat denied')
            return original_stat(path, *args, **kwargs)
        def os_stat(path, *args, **kwargs):
            events.append(('os.stat', str(path), args, tuple(sorted(kwargs.items()))))
            return original_os_stat(path, *args, **kwargs)
        with patch.object(Path, 'is_symlink', symlink), patch.object(Path, 'stat', stat), \
                patch.object(os, 'stat', os_stat):
            outcome = self.outcome(function, target_root, relative)
        return outcome, events

    def equivalent_regular(self, relative, **kwargs):
        expected = self.regular_events(REFERENCE_REGULAR, relative, **kwargs)
        actual = self.regular_events(cleanup._regular, relative, **kwargs)
        self.assertEqual(actual, expected)
        return actual

    def test_regular_canonical_names_keep_every_ordered_filesystem_hook(self):
        for relative in ('file', 'nested/file', r'back\slash', '.hidden/file', 'a/.../file'):
            with self.subTest(relative=relative):
                outcome, events = self.equivalent_regular(relative)
                self.assertEqual(outcome[0], 'return')
                root_probes = [target for kind, target, *rest in events if kind == 'is_symlink']
                expected = [self.root, *self.root.parents]
                path = self.root
                for part in Path(relative).parts:
                    path = path/part
                    expected.append(path)
                self.assertEqual(root_probes, list(map(str, expected)))
                self.assertEqual(events[-2][0], 'stat')
                self.assertEqual(events[-1][0], 'os.stat')

    def test_regular_noncanonical_invalid_and_missing_paths_keep_fallback(self):
        for relative in ('./file', 'nested//file', 'nested/./file', 'nested/file/', '', '.', '..',
                         '../file', 'nested/../file', '/file', '//file', 'missing', 'nested',
                         'file/child', '\x00', 'nul\x00name'):
            with self.subTest(relative=relative): self.equivalent_regular(relative)
        class Text(str): pass
        for relative in (Text('file'), Text('./file'), Path('file'), None, 7, b'file'):
            with self.subTest(type=type(relative)): self.equivalent_regular(relative)

    def test_regular_symlinks_errors_and_preprobe_path_mutation_match(self):
        alias = self.root/'alias'
        alias.symlink_to(self.root/'nested', target_is_directory=True)
        self.equivalent_regular('alias/file')
        root_alias = self.root/'root-alias'
        root_alias.symlink_to(self.root, target_is_directory=True)
        self.equivalent_regular('file', root=root_alias)
        for fault in ('symlink', 'stat'):
            self.equivalent_regular('nested/file', fault=fault)
        outcome, events = self.equivalent_regular('file', mutate=True)
        if type(getattr(self.root, '_raw_paths', None)) is list:
            self.assertIn(('raw-mutated', str(self.root/'alternate')), events)
            self.assertEqual(outcome, ('return', str(self.root/'alternate')))

    def test_replaced_constructor_and_pathlike_protocol_order_are_preserved(self):
        real_path = cleanup.Path
        def run(function, relative):
            calls = []
            def constructor(*args):
                calls.append(tuple(str(arg) for arg in args))
                return real_path(*args)
            with patch.object(cleanup, 'Path', constructor):
                result = self.outcome(function, self.root, relative)
            return result, calls
        for relative in ('file', './file', '.', ''):
            with self.subTest(relative=relative):
                self.assertEqual(run(cleanup._regular, relative), run(REFERENCE_REGULAR, relative))
        def protocol(function):
            events = []
            class Name:
                def __fspath__(self):
                    events.append('fspath')
                    return 'file'
            return self.outcome(function, self.root, Name()), events
        self.assertEqual(protocol(cleanup._regular), protocol(REFERENCE_REGULAR))

    def test_regular_require_call_and_error_order_is_unchanged(self):
        original = cleanup.require
        def run(function, fail):
            events = []
            def require(ok, message):
                events.append((ok, message))
                if fail and message == 'unsafe input path': raise ValueError('require replaced')
                return original(ok, message)
            with patch.object(cleanup, 'require', require):
                outcome = self.outcome(function, self.root, 'file')
            return outcome, events
        for fail in (False, True):
            self.assertEqual(run(cleanup._regular, fail), run(REFERENCE_REGULAR, fail))

    def test_canonical_regular_parser_skips_only_two_lexical_conversions(self):
        calls = []
        original = PosixPath.parts
        def parts(path):
            calls.append(tuple(getattr(path, '_raw_paths', (str(path),))))
            return original.fget(path)
        with patch.object(PosixPath, 'parts', property(parts)):
            self.assertEqual(self.outcome(cleanup._regular, self.root, 'nested/file'),
                             ('return', str(self.root/'nested/file')))
        if os.name == 'posix': self.assertNotIn(('nested/file',), calls)

    @staticmethod
    def observation(function, path, *, state='pending', mode='bytes', value=b'value'):
        events = []
        class Owner:
            _kind = 'invariant'
            _state = state
            def __init__(self): self._observations = []
            def _check_owner(self, root): events.append(('owner', root))
            def _match(self, root, path, value, mode): events.append(('match', root, path, value, mode))
        owner = Owner()
        outcome = PathStringLexicalTests.outcome(function, owner, '/root', path, value, mode)
        return outcome, events, owner._observations

    def test_observation_canonical_dot_and_fallback_spellings_match(self):
        class Text(str): pass
        paths = ('file', 'nested/file', '.', '.hidden/file', 'a/.../file', r'back\slash',
                 '', '..', './file', '../file', 'nested/../file', 'nested//file', 'nested/./file',
                 'nested/file/', '/file', '//file', '\x00', 'nul\x00name', Text('file'), None, 3)
        for path in paths:
            for state in ('pending', 'active'):
                with self.subTest(path=path, state=state):
                    self.assertEqual(self.observation(cleanup._InvariantInputs._observe, path, state=state),
                                     self.observation(REFERENCE_OBSERVE, path, state=state))
        self.assertEqual(self.observation(cleanup._InvariantInputs._observe, '.')[0], ('return', None))

    def test_observation_mode_value_and_owner_checks_are_not_skipped(self):
        for mode, value in (('bytes', b'value'), ('default', 'value'), ('bytes', 'value'),
                            ('unknown', b'value')):
            for state in ('pending', 'active'):
                with self.subTest(mode=mode, state=state):
                    self.assertEqual(self.observation(cleanup._InvariantInputs._observe, 'file',
                                                     mode=mode, value=value, state=state),
                                     self.observation(REFERENCE_OBSERVE, 'file',
                                                     mode=mode, value=value, state=state))

    def test_observation_replaced_constructor_keeps_all_three_lookups(self):
        real_path = cleanup.Path
        def run(function, name):
            calls = []
            def constructor(*args):
                calls.append(args)
                return real_path(*args)
            with patch.object(cleanup, 'Path', constructor):
                result = self.observation(function, name)
            return result, calls
        for path in ('file', '.', './file', '/file', ''):
            with self.subTest(path=path):
                self.assertEqual(run(cleanup._InvariantInputs._observe, path), run(REFERENCE_OBSERVE, path))
        self.assertEqual(len(run(cleanup._InvariantInputs._observe, 'file')[1]), 3)

    def test_root_spelling_classifier_matches_reference_forms_and_storage(self):
        roots = ('/', '/a', '/a/b', '/.hidden', '/a/.../b', r'/back\slash', '//a', '///a',
                 '/a/', '/a//b', '/a/./b', '/a/../b', '/.', '/..', '', '.', '..', 'relative',
                 '/nul\x00name')
        for spelling in roots:
            for root in (spelling, Path(spelling)):
                with self.subTest(spelling=spelling, kind=type(root)):
                    self.assertEqual(self.outcome(cleanup._absolute_root_text, root),
                                     self.outcome(REFERENCE_ROOT, root))
        class Text(str): pass
        class Root(PosixPath): pass
        for root in (Root(self.root), Path(Text(str(self.root))), Path('/a', 'b')):
            with self.subTest(root=type(root)):
                self.assertEqual(self.outcome(cleanup._absolute_root_text, root),
                                 self.outcome(REFERENCE_ROOT, root))

    def test_nonposix_context_retains_original_expressions(self):
        root = self.root
        with patch.object(cleanup.os, 'name', 'nt'):
            self.assertEqual(self.outcome(cleanup._absolute_root_text, root),
                             self.outcome(REFERENCE_ROOT, root))
            self.assertEqual(self.outcome(cleanup._regular, root, 'file'),
                             self.outcome(REFERENCE_REGULAR, root, 'file'))
            self.assertEqual(self.observation(cleanup._InvariantInputs._observe, 'file'),
                             self.observation(REFERENCE_OBSERVE, 'file'))


if __name__ == '__main__':
    unittest.main()
