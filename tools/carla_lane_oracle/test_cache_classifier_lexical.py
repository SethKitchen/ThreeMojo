# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Finite V13 differential controls for representation-only frame shortcuts."""
import ast
from contextlib import ExitStack
import hashlib
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as cleanup
import test_owner_frame_lexical as owner_fixtures

def _baseline_cache_verify_frame(frame, *, include_aliases=False):
    """Recognize supported owners; aliases may only block outer borrowing."""
    name = (__package__ + '.cache_key_contracts') if __package__ else 'cache_key_contracts'
    cache = sys.modules.get(name)
    if (frame is not None and cache is not None and frame.f_globals is vars(cache)
            and frame.f_code is _live_function_code(cache.verify)):
        return True
    main = sys.modules.get('__main__')
    if (frame is not None and main is not None and frame.f_globals is vars(main)
            and type(getattr(main, '__file__', None)) is str
            and not (type(main) is types.ModuleType
                     and type(vars(main).get('__file__')) is str
                     and _different_alias_leaf(vars(main)['__file__'], ('cache_key_contracts.py',)))
            and Path(main.__file__).absolute() == Path(__file__).absolute().with_name('cache_key_contracts.py')
            and frame.f_code is _live_function_code(getattr(main, 'verify', None))):
        return True
    # An importlib alias can run the public fresh path without being registered
    # in sys.modules. It is still a distinct operation, never an outer borrower.
    namespace = frame.f_globals if frame is not None else {}
    if include_aliases is True and _different_alias_leaf(namespace.get('__file__'), ('cache_key_contracts.py',)):
        return False
    return (include_aliases and type(namespace.get('__file__')) is str
            and Path(namespace['__file__']).absolute() == Path(__file__).absolute().with_name('cache_key_contracts.py')
            and frame.f_code is _live_function_code(namespace.get('verify')))

def _baseline_owner_module(kind):
    if kind in ('map_loops', 'rtree_loops'):
        return None
    name = {'invariant': 'coverage_invariant_contracts',
            'winner': 'winner_sign_contracts', 'border': 'border_parser_contracts'}.get(kind)
    return sys.modules.get((__package__ + '.' if __package__ else '') + name) if name else None

REFERENCE_HASHES = {'_cache_verify_frame': '430c1279085af0c279ec1e0d3ca166bdb5de822af0f3c8595246a489d3a211e8', '_owner_module': 'a5f60b07d07556090def6d3490be5dfeef8197ef71d8e3ff13efce5c110d4860'}

REFERENCE_CACHE = types.FunctionType(_baseline_cache_verify_frame.__code__, vars(cleanup))
REFERENCE_OWNER = owner_fixtures.typed_reference(_baseline_owner_module, 'owner')
PREFIX = (cleanup.__package__ + '.') if cleanup.__package__ else ''
CACHE_NAME = PREFIX + 'cache_key_contracts'
CACHE_FILE = str(Path(cleanup.__file__).with_name('cache_key_contracts.py'))


class CacheClassifierLexicalTests(unittest.TestCase):
    def test_frozen_v13_reference_asts(self):
        tree = ast.parse(Path(__file__).read_text())
        for name, digest in REFERENCE_HASHES.items():
            node = next(n for n in tree.body if isinstance(n, ast.FunctionDef)
                        and n.name == '_baseline' + name)
            node.name = name
            self.assertEqual(hashlib.sha256(ast.dump(node, include_attributes=False).encode()).hexdigest(), digest)

    @staticmethod
    def outcome(call):
        try:
            value = call()
            return ('return', type(value), value)
        except Exception as error:
            return ('raise', type(error), error.args)

    @staticmethod
    def module(filename=CACHE_FILE, namespace=None):
        module = types.ModuleType('cache_classifier_fixture')
        if namespace is None:
            namespace = vars(module)
        namespace.update(__file__=filename, sys=sys)
        exec('def verify():\n    yield sys._getframe()\n'
             'def helper():\n    yield sys._getframe()\n', namespace)
        return module, namespace

    def compare(self, *, symbol='helper', filename=CACHE_FILE, core=None,
                registration='alias', aliases=True, decorate=None,
                absent=False, path_hook=False, live_hook=False,
                namespace_factory=None, synthetic=False, nonposix=False):
        results = []
        for classifier in (REFERENCE_CACHE, cleanup._cache_verify_frame):
            events = []
            namespace = None if namespace_factory is None else namespace_factory(events)
            module, namespace = self.module(filename, namespace)
            generator = namespace[symbol]()
            self.addCleanup(generator.close)
            frame = next(generator)
            if synthetic:
                code = frame.f_code
                class Frame:
                    f_globals = namespace
                    f_locals = {}
                    @property
                    def f_code(self):
                        events.append('f_code')
                        return code
                frame = Frame()
            if absent:
                namespace.pop('verify')
            if decorate:
                inner = namespace['verify']
                def wrapper(): pass
                wrapper.__wrapped__ = inner
                if decorate == 'cycle': wrapper.__wrapped__ = wrapper
                namespace['verify'] = wrapper
            registry = {CACHE_NAME: None, '__main__': None}
            if registration == 'canonical': registry[CACHE_NAME] = module
            if registration == 'main': registry['__main__'] = module
            with ExitStack() as stack:
                stack.enter_context(patch.dict(sys.modules, registry))
                if core is not None: stack.enter_context(patch.object(cleanup, '__file__', core))
                if nonposix: stack.enter_context(patch.object(cleanup.os, 'name', 'nt'))
                if path_hook:
                    def observed(value):
                        events.append(('Path', value))
                        return Path(value)
                    stack.enter_context(patch.object(cleanup, 'Path', observed))
                if live_hook:
                    def live(value):
                        events.append(('live', value is namespace.get('verify')))
                        return frame.f_code
                    stack.enter_context(patch.object(cleanup, '_live_function_code', live))
                result = self.outcome(lambda: classifier(frame, include_aliases=aliases))
            results.append((result, events))
        self.assertEqual(results[0], results[1])
        return results[0]

    def test_genuine_canonical_main_alias_positives_and_helper_negatives(self):
        for registration in ('canonical', 'main', 'alias'):
            for symbol in ('verify', 'helper'):
                for aliases in (False, True):
                    with self.subTest(registration=registration, symbol=symbol, aliases=aliases):
                        result, _ = self.compare(registration=registration, symbol=symbol, aliases=aliases)
                        self.assertEqual(result, ('return', bool,
                            symbol == 'verify' and (registration != 'alias' or aliases)))

    def test_relative_noncanonical_and_invalid_core_fallbacks(self):
        for filename in ('cache_key_contracts.py', './cache_key_contracts.py',
                         CACHE_FILE + '/', str(Path(CACHE_FILE).parent) + '/./cache_key_contracts.py',
                         '/', '/.', '/..', '', None):
            for symbol in ('verify', 'helper'):
                with self.subTest(filename=filename, symbol=symbol):
                    self.compare(filename=filename, symbol=symbol)
        for core in ('/', '/.', '/..', '/tmp/core/', 'full_audit_cleanup_contracts.py',
                     '', None):
            # None means no replacement above, and is covered separately below.
            if core is None: continue
            with self.subTest(core=core): self.compare(core=core)
        self.compare(nonposix=True)

    def test_exact_flags_decorated_cycles_and_missing_verify(self):
        for aliases in (False, True, 0, 1, None, (), (1,), [], [1], '', 'yes'):
            for decorate in (None, 'one', 'cycle'):
                for symbol in ('verify', 'helper'):
                    with self.subTest(aliases=aliases, decorate=decorate, symbol=symbol):
                        self.compare(aliases=aliases, decorate=decorate, symbol=symbol)
        self.compare(absent=True)
        class Flag:
            def __bool__(self): raise ValueError('flag callback')
        self.compare(aliases=Flag())

    def test_replaced_path_live_helper_and_synthetic_frames_fall_back(self):
        for symbol in ('verify', 'helper'):
            self.compare(symbol=symbol, path_hook=True)
            self.compare(symbol=symbol, live_hook=True)
            self.compare(symbol=symbol, synthetic=True)
        def namespace(events):
            class Namespace(dict):
                def get(self, key, default=None):
                    events.append(('get', key))
                    return super().get(key, default)
            return Namespace()
        self.compare(namespace_factory=namespace)

    def test_mutated_live_helper_code_keeps_fallback(self):
        original = cleanup._live_function_code
        code = original.__code__
        def substitute(value): return None
        try:
            original.__code__ = substitute.__code__
            self.compare(symbol='verify')
            self.compare(symbol='helper')
        finally:
            original.__code__ = code

    def test_exotic_function_metadata_keeps_original_protocol(self):
        results = []
        for classifier in (REFERENCE_CACHE, cleanup._cache_verify_frame):
            module, namespace = self.module()
            generator = namespace['helper']()
            self.addCleanup(generator.close)
            frame = next(generator)
            events = []
            class Metadata(dict):
                def __contains__(self, key):
                    events.append(('contains', key))
                    raise ValueError('metadata membership')
            namespace['verify'].__dict__ = Metadata()
            with patch.dict(sys.modules, {CACHE_NAME: None, '__main__': None}):
                result = self.outcome(lambda: classifier(frame, include_aliases=True))
            results.append((result, events))
        self.assertEqual(*results)

    def test_negative_elides_only_lexical_path_construction(self):
        module, namespace = self.module()
        generator = namespace['helper']()
        self.addCleanup(generator.close)
        frame = next(generator)
        calls = []
        original_profile = sys.getprofile()
        target = Path.__init__.__code__
        def profile(current, event, arg):
            if event == 'call' and current.f_code is target: calls.append(current.f_code)
        try:
            with patch.dict(sys.modules, {CACHE_NAME: None, '__main__': None}):
                sys.setprofile(profile)
                self.assertIs(REFERENCE_CACHE(frame, include_aliases=True), False)
                previous = len(calls)
                calls.clear()
                self.assertIs(cleanup._cache_verify_frame(frame, include_aliases=True), False)
                current = len(calls)
        finally:
            sys.setprofile(original_profile)
        self.assertGreater(previous, 0)
        self.assertEqual(current, 0)

    def test_nearer_real_alias_verify_remains_the_barrier(self):
        module, namespace = self.module()
        exec('def verify(callback):\n    return helper(callback)\n'
             'def helper(callback):\n    return callback(sys._getframe())\n', namespace)
        def check(frame):
            for classifier in (REFERENCE_CACHE, cleanup._cache_verify_frame):
                current = frame
                while current is not None and not classifier(current, include_aliases=True):
                    current = current.f_back
                self.assertIs(current, frame.f_back)
        with patch.dict(sys.modules, {CACHE_NAME: None, '__main__': None}):
            namespace['verify'](check)

    def test_owner_module_builtin_strings_keep_fresh_registry_lookup(self):
        registry = {PREFIX + name: types.ModuleType(name) for name in (
            'coverage_invariant_contracts', 'winner_sign_contracts', 'border_parser_contracts',
            'check_runtime_support', 'check_sampled_values')}
        with patch.dict(sys.modules, registry):
            for kind in ('invariant', 'winner', 'border', 'runtime', 'sampled', 'map_loops', 'rtree_loops', '', 'other'):
                self.assertIs(cleanup._owner_module(kind), REFERENCE_OWNER(kind))
            replacement = types.ModuleType('replacement')
            sys.modules[PREFIX + 'winner_sign_contracts'] = replacement
            self.assertIs(cleanup._owner_module('winner'), replacement)

    def test_owner_module_exotic_hash_equality_and_errors_match(self):
        for spelling in ('winner', 'runtime', 'sampled', 'map_loops', 'other'):
            outputs = []
            for classifier in (REFERENCE_OWNER, cleanup._owner_module):
                events = []
                class Kind(str):
                    def __hash__(self):
                        events.append('hash')
                        return super().__hash__()
                    def __eq__(self, other):
                        events.append(('equal', other))
                        return super().__eq__(other)
                outputs.append((self.outcome(lambda: classifier(Kind(spelling))), events))
            self.assertEqual(*outputs)
        for kind in (None, 1, [], {}):
            self.assertEqual(self.outcome(lambda: REFERENCE_OWNER(kind)),
                             self.outcome(lambda: cleanup._owner_module(kind)))
        class Fault:
            def __eq__(self, other): return False
            def __hash__(self): raise ValueError('hash callback')
        self.assertEqual(self.outcome(lambda: REFERENCE_OWNER(Fault())),
                         self.outcome(lambda: cleanup._owner_module(Fault())))


if __name__ == '__main__':
    unittest.main()
