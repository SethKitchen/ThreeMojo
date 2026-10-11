#!/usr/bin/env python3
"""Focused differential classifier controls, not source qualification.

Import real canonical modules only when this script is explicitly authorized to
run. Compile just the old/new classifiers into isolated globals. Never replace
production functions, source bytes, sys.modules, or a source admission graph.
Synthetic frame records carry actual code and module-global identities. They
exercise classification only; real operation lifecycle controls remain separate.
"""
import ast
from contextlib import nullcontext
import hashlib
import importlib
import json
from pathlib import Path
import sys
import types
from unittest.mock import patch

BASELINE_SHA = 'e86bdc939aec95fe579ce38cd9ca6c5c9b287a0623003d5d5679719b56d139b5'
PROPOSAL_SHA = '8a22685850e469f0d21a1865c41ef70b9e6d8780f2887cf6e99251ba09454c51'
FILE = 'tools/carla_lane_oracle/full_audit_cleanup_contracts.py'
_UNSET = object()
_CHECK_COUNT = 0

OP_NAMES = ('coverage_invariant_contracts.py', 'winner_sign_contracts.py',
            'border_parser_contracts.py', 'coverage_loop_proofs.py')


def require(value, detail=None):
    """Always active in normal and optimized Python, unlike assert."""
    global _CHECK_COUNT
    _CHECK_COUNT += 1
    if not value:
        if detail is None:
            raise AssertionError
        raise AssertionError(detail)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def definitions(text):
    return {node.name: node for node in ast.parse(text).body
            if isinstance(node, (ast.FunctionDef, ast.ClassDef))}


def ast_key(node):
    return ast.dump(node, include_attributes=False)


def function(code, namespace):
    return types.FunctionType(code, namespace, code.co_name)


def frame(namespace, code, **locals_):
    return types.SimpleNamespace(f_globals=namespace, f_code=code, f_locals=locals_)


def outcome(call, input_flag=_UNSET):
    try:
        value = call()
        if input_flag is not _UNSET and value is input_flag:
            return {'value_is_input_flag': True}
        return {'value': value}
    except Exception as error:
        return {'exception': type(error).__module__ + '.' + type(error).__qualname__,
                'message': str(error)}


def main():
    old_root, root, output = map(lambda value: Path(value).absolute(), sys.argv[1:4])
    before, after = old_root/FILE, root/FILE
    old_raw, new_raw = before.read_bytes(), after.read_bytes()
    require(hashlib.sha256(old_raw).hexdigest() == BASELINE_SHA
            and hashlib.sha256(new_raw).hexdigest() == PROPOSAL_SHA)
    old_text, new_text = old_raw.decode('utf-8'), new_raw.decode('utf-8')
    old_defs, new_defs = definitions(old_text), definitions(new_text)
    changed = [name for name in old_defs if ast_key(old_defs[name]) != ast_key(new_defs[name])]
    require(changed == ['_cache_verify_frame', '_operation_frame_kind'], changed)
    require(set(new_defs) - set(old_defs) == {'_different_alias_leaf'})
    # Verify each classifier projects to the complete old body after removing
    # only its one new lexical-negative statement. No other reorder is hidden.
    for name in changed:
        tree = ast.parse(ast.get_source_segment(new_text, new_defs[name])).body[0]
        removed = [node for node in tree.body if isinstance(node, ast.If)
                   and any(isinstance(call, ast.Call) and isinstance(call.func, ast.Name)
                           and call.func.id == '_different_alias_leaf' for call in ast.walk(node.test))]
        require(len(removed) == 1)
        tree.body = [node for node in tree.body if node not in removed]
        require(ast_key(tree) == ast_key(old_defs[name]), name)

    sys.path[:0] = [str(root/'tools/carla_lane_oracle'), str(root/'tools')]
    cleanup = importlib.import_module('full_audit_cleanup_contracts')
    modules = {name: importlib.import_module(name) for name in (
        'coverage_invariant_contracts', 'winner_sign_contracts', 'border_parser_contracts',
        'cache_key_contracts', 'lane_order_contracts', 'coverage_followup_contracts',
        'coverage_loop_proofs')}
    require(Path(cleanup.__file__).absolute() == after)
    require(all((Path(module.__file__).absolute().is_relative_to(root) for module in modules.values())))
    names = ('_owner_module', '_cache_verify_frame', '_operation_frame_kind')
    counts = {'cases': 0, 'equivalent': 0, 'negative_path_elisions': 0}
    details = []

    def contexts(core_file=str(after), *, main_module=None, registration=None, os_name=None):
        result = []
        for text, defs in ((old_text, old_defs), (new_text, new_defs)):
            namespace = dict(vars(cleanup))
            namespace.pop('_different_alias_leaf', None)
            registry = dict(sys.modules)
            if main_module is not None:
                registry['__main__'] = main_module
            if registration is not None:
                registry[registration[0]] = registration[1]
            namespace['sys'] = types.SimpleNamespace(modules=registry)
            namespace['__file__'] = core_file
            if os_name is not None:
                namespace['os'] = types.SimpleNamespace(name=os_name)
            calls = []
            def observed_path(value, _calls=calls):
                _calls.append(value)
                return Path(value)
            namespace['Path'] = observed_path
            selected = [defs[name] for name in names]
            if '_different_alias_leaf' in defs:
                selected.insert(0, defs['_different_alias_leaf'])
            tree = ast.Module(body=selected, type_ignores=[])
            exec(compile(tree, '<isolated-classifier-control>', 'exec'), namespace)
            result.append((namespace, calls))
        return result

    def compare(label, candidate, *, classifiers=('_operation_frame_kind', '_cache_verify_frame'),
                include_aliases=True, core_file=str(after), main_module=None,
                registration=None, os_name=None, missing_cwd=False, elide=False,
                expected=_UNSET, expected_error=None, preserve_path_calls=False,
                flag_factory=None, expected_bool_calls=None, expected_flag_return=False):
        pair = contexts(core_file, main_module=main_module, registration=registration, os_name=os_name)
        for classifier in classifiers:
            results = []
            calls = []
            bool_calls = []
            for namespace, path_calls in pair:
                path_calls.clear()
                scope = patch('os.getcwd', side_effect=FileNotFoundError('control missing cwd')) if missing_cwd else nullcontext()
                flag = include_aliases if flag_factory is None else flag_factory()
                with scope:
                    results.append(outcome(lambda: namespace[classifier](candidate, include_aliases=flag),
                                           input_flag=flag if flag_factory is not None else _UNSET))
                calls.append(len(path_calls))
                bool_calls.append(flag.calls if flag_factory is not None else None)
            require(results[0] == results[1], (label, classifier, results))
            if 'value' in results[0] and 'value' in results[1]:
                require(type(results[0]['value']) is type(results[1]['value']), (label, results))
            if flag_factory is not None:
                require(bool_calls == [expected_bool_calls, expected_bool_calls], (label, bool_calls))
            if expected_flag_return:
                require(results[0] == {'value_is_input_flag': True}, (label, results))
            if expected is not _UNSET:
                wanted = expected[classifier] if type(expected) is dict else expected
                require(results[0] == {'value': wanted}, (label, classifier, results, wanted))
                require(type(results[0]['value']) is type(wanted), (label, results, wanted))
            if expected_error is not None:
                require(results[0] == {'exception': expected_error[0], 'message': expected_error[1]},
                        (label, classifier, results, expected_error))
            if preserve_path_calls:
                require(calls[0] > 0 and calls[0] == calls[1], (label, classifier, calls))
            if elide:
                require(calls[0] > 0 and calls[1] == 0, (label, classifier, calls))
                counts['negative_path_elisions'] += 1
            counts['cases'] += 1
            counts['equivalent'] += 1
            details.append({'label': label, 'classifier': classifier, 'include_aliases': include_aliases,
                            'outcome': results[0], 'old_path_constructions': calls[0],
                            'new_path_constructions': calls[1], 'bool_calls': bool_calls})

    live = cleanup._live_function_code
    # Real canonical function code/global identities, including decorators.
    for name, module in modules.items():
        symbol = 'reviewed_nonempty_loops' if name == 'coverage_loop_proofs' else 'verify'
        for include_aliases in (False, True):
            choices = ('extensions/carla/map', 'extensions/carla/rtree', 'other') if symbol != 'verify' else (None,)
            for module_name in choices:
                operation_kind = {
                    'coverage_invariant_contracts': 'invariant',
                    'winner_sign_contracts': 'winner',
                    'border_parser_contracts': 'border',
                }.get(name)
                if name == 'coverage_loop_proofs':
                    operation_kind = {'extensions/carla/map': 'map_loops',
                                      'extensions/carla/rtree': 'rtree_loops'}.get(module_name, 'other_loops')
                compare('canonical:' + name + ':' + str(module_name),
                        frame(vars(module), live(getattr(module, symbol)), module=module_name),
                        include_aliases=include_aliases,
                        expected={'_operation_frame_kind': operation_kind,
                                  '_cache_verify_frame': name == 'cache_key_contracts'})
    # The measured non-owner verify frames must skip all four alias Paths.
    for name in ('cache_key_contracts', 'lane_order_contracts', 'coverage_followup_contracts'):
        module = modules[name]
        compare('measured-operation-negative:' + name, frame(vars(module), live(module.verify)),
                classifiers=('_operation_frame_kind',), elide=True, expected=None)
    for name in ('coverage_invariant_contracts', 'lane_order_contracts', 'coverage_followup_contracts'):
        module = modules[name]
        compare('measured-cache-negative:' + name, frame(vars(module), live(module.verify)),
                classifiers=('_cache_verify_frame',), elide=True, expected=False)

    base_code = modules['coverage_invariant_contracts'].verify.__code__
    oracle = root/'tools/carla_lane_oracle'
    paths = [str(oracle/name) for name in (*OP_NAMES[:3], 'cache_key_contracts.py')]
    paths += [str(root/'tools/coverage_loop_proofs.py'), str(oracle/'other.py'),
              str(root/'wrong/coverage_invariant_contracts.py'),
              str(oracle) + '//./coverage_invariant_contracts.py',
              str(oracle) + '//./other.py', str(oracle/'other.py')+'/',
              str(oracle/'other.py')+'/.', str(oracle/'other.py')+'/..',
              'relative.py', '', '/', '/.', '/..', None, 7]
    class ExoticString(str):
        pass
    paths.append(ExoticString(str(oracle/'coverage_invariant_contracts.py')))
    for path in paths:
        namespace = {'__file__': path, '__name__': '_classifier_alias'}
        actual = function(base_code, namespace)
        namespace['verify'] = actual
        namespace['reviewed_nonempty_loops'] = actual
        candidate = frame(namespace, actual.__code__, module='extensions/carla/map')
        for include_aliases in (False, True):
            compare('spelling:' + repr(path), candidate, include_aliases=include_aliases)
        alias = types.ModuleType('_classifier_alias')
        alias.__dict__.update(namespace)
        alias.verify = function(base_code, vars(alias))
        alias.reviewed_nonempty_loops = alias.verify
        require(alias.verify.__globals__ is vars(alias))
        compare('registered-alias:' + repr(path), frame(vars(alias), alias.verify.__code__, module='extensions/carla/map'),
                registration=(alias.__name__, alias))
    # Explicit positive and negative alias expectations are independent of
    # differential equality; registration never grants canonical ownership.
    expected_aliases = ((oracle/'coverage_invariant_contracts.py', 'alias_invariant', False),
                        (oracle/'winner_sign_contracts.py', 'alias_winner', False),
                        (oracle/'border_parser_contracts.py', 'alias_border', False),
                        (root/'tools/coverage_loop_proofs.py', 'alias_loops', False),
                        (oracle/'cache_key_contracts.py', None, True),
                        (root/'wrong/coverage_invariant_contracts.py', None, False))
    for path, operation_kind, cache_kind in expected_aliases:
        for registered in (False, True):
            alias = types.ModuleType('_explicit_classifier_alias')
            alias.__file__ = str(path)
            alias.verify = function(base_code, vars(alias))
            alias.reviewed_nonempty_loops = alias.verify
            require(alias.verify.__globals__ is vars(alias))
            for include_aliases in (False, True):
                compare('explicit-alias:' + str(path) + ':' + str(registered),
                        frame(vars(alias), alias.verify.__code__, module='extensions/carla/map'),
                        registration=(alias.__name__, alias) if registered else None,
                        include_aliases=include_aliases,
                        expected={'_operation_frame_kind': operation_kind if include_aliases else None,
                                  '_cache_verify_frame': cache_kind if include_aliases else False})
    # Renaming the code object does not remove an alias barrier.
    namespace = {'__file__': str(oracle/'coverage_invariant_contracts.py')}
    renamed = function(base_code.replace(co_name='renamed_public_entry'), namespace)
    namespace['verify'] = renamed
    compare('renamed-matching-alias', frame(namespace, renamed.__code__),
            classifiers=('_operation_frame_kind',), expected='alias_invariant')

    class ExoticWrapped:
        def __init__(self):
            self.visits = 0
        @property
        def __wrapped__(self):
            self.visits += 1
            raise ValueError('control exotic wrapper')
    for kind in ('plain', 'wrapped', 'multiwrapped', 'cyclic', 'exotic'):
        for leaf in ('coverage_invariant_contracts.py', 'cache_key_contracts.py', 'other.py'):
            namespace = {'__file__': str(oracle/leaf)}
            target = function(base_code, namespace)
            outer = function(base_code.replace(co_name='wrapper'), namespace)
            outer.__wrapped__ = target
            if kind == 'plain': value = target
            elif kind == 'wrapped': value = outer
            elif kind == 'multiwrapped':
                value = function(base_code.replace(co_name='outer'), namespace)
                value.__wrapped__ = outer
            elif kind == 'cyclic':
                value = outer
                value.__wrapped__ = value
            else: value = ExoticWrapped()
            namespace['verify'] = value
            for classifier, matching_leaf, good in (
                    ('_operation_frame_kind', 'coverage_invariant_contracts.py', 'alias_invariant'),
                    ('_cache_verify_frame', 'cache_key_contracts.py', True)):
                negative = None if classifier == '_operation_frame_kind' else False
                matched = leaf == matching_leaf
                expected_error = None
                if matched and kind in ('cyclic', 'exotic'):
                    expected_error = ((cleanup.ContractError.__module__ + '.' + cleanup.ContractError.__qualname__,
                                       'full-audit cleanup successor: cyclic executing function wrapper')
                                      if kind == 'cyclic' else ('builtins.ValueError', 'control exotic wrapper'))
                compare('wrapper:' + kind + ':' + leaf, frame(namespace, target.__code__),
                        classifiers=(classifier,), expected=_UNSET if expected_error else (good if matched else negative),
                        expected_error=expected_error,
                        preserve_path_calls=matched)
            if kind == 'exotic':
                require(value.visits == (2 if leaf != 'other.py' else 0), (leaf, value.visits))
    # Guard ineligibility keeps old errors and normalization paths, including
    # unusual core spelling and cwd failure. Only isolated globals are changed.
    namespace = {'__file__': 'relative.py'}
    namespace['verify'] = function(base_code, namespace)
    compare('missing-cwd-relative', frame(namespace, namespace['verify'].__code__), missing_cwd=True,
            expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)
    namespace['__file__'] = str(oracle/'other.py')
    compare('missing-cwd-relative-core', frame(namespace, namespace['verify'].__code__),
            core_file='relative/core.py', missing_cwd=True,
            expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)
    for core in ('relative/core.py', '/', '/.', '/..', str(after)+'/', str(after)+'/.', None, 3, ExoticString(str(after))):
        compare('core-spelling:' + repr(core), frame(namespace, namespace['verify'].__code__), core_file=core, preserve_path_calls=True)
    compare('non-posix-fallback', frame(namespace, namespace['verify'].__code__), os_name='nt', preserve_path_calls=True)

    # Preserve __main__ cache's original path-before-code acceptance/exception.
    for leaf in ('cache_key_contracts.py', 'other.py'):
        main_module = types.ModuleType('__main__')
        main_module.__file__ = str(oracle/leaf)
        main_module.verify = function(modules['cache_key_contracts'].verify.__code__, vars(main_module))
        compare('cache-main:' + leaf, frame(vars(main_module), main_module.verify.__code__),
                classifiers=('_cache_verify_frame',), main_module=main_module,
                expected=leaf == 'cache_key_contracts.py')
    main_module = types.ModuleType('__main__')
    main_module.__file__ = str(oracle/'cache_key_contracts.py')
    main_module.verify = function(modules['cache_key_contracts'].verify.__code__, vars(main_module))
    wrong_code = base_code.replace(co_name='not_the_main_verify')
    for code in (main_module.verify.__code__, wrong_code):
        compare('cache-main-invalid-core:' + code.co_name, frame(vars(main_module), code),
                classifiers=('_cache_verify_frame',), main_module=main_module, core_file='/',
                expected_error=('builtins.ValueError', "PosixPath('/') has an empty name"),
                preserve_path_calls=True)
    compare('cache-main-relative-core-missing-cwd', frame(vars(main_module), wrong_code),
            classifiers=('_cache_verify_frame',), main_module=main_module, core_file='relative/core.py',
            missing_cwd=True, expected_error=('builtins.FileNotFoundError', 'control missing cwd'),
            preserve_path_calls=True)
    main_module.__file__ = 'relative-main.py'
    compare('cache-main-relative-file-missing-cwd', frame(vars(main_module), wrong_code),
            classifiers=('_cache_verify_frame',), main_module=main_module, missing_cwd=True,
            expected_error=('builtins.FileNotFoundError', 'control missing cwd'), preserve_path_calls=True)
    # Exact True is the only new optimized flag. All other flags retain the
    # original evaluation count, short-circuit return object, and exceptions.
    class CustomFlag:
        def __init__(self, sequence):
            self.sequence = sequence
            self.calls = 0
        def __bool__(self):
            item = self.sequence[min(self.calls, len(self.sequence)-1)]
            self.calls += 1
            if item == 'raise':
                raise ValueError('control flag truthiness')
            return item
    namespace = {'__file__': str(oracle/'cache_key_contracts.py')}
    namespace['verify'] = function(base_code, namespace)
    candidate = frame(namespace, namespace['verify'].__code__)
    for trailing in ('', '/'):
        namespace['__file__'] = str(oracle/'cache_key_contracts.py') + trailing
        for label, sequence in (('truthy', (True,)), ('falsey', (False,)),
                                ('true-false', (True, False)), ('false-true', (False, True)),
                                ('true-raise', (True, 'raise')), ('raising', ('raise',))):
            raising = sequence[0] == 'raise'
            compare('custom-flag:' + str(trailing) + ':' + label, candidate, classifiers=('_cache_verify_frame',),
                    flag_factory=lambda sequence=sequence: CustomFlag(sequence), expected_bool_calls=1,
                    expected=True if sequence[0] is True else _UNSET,
                    expected_flag_return=sequence[0] is False,
                    expected_error=('builtins.ValueError', 'control flag truthiness') if raising else None)
    namespace['__file__'] = str(oracle/'cache_key_contracts.py')
    for flag, cache_result in ((0, 0), (1, True), (None, None)):
        compare('builtin-nonbool-flag:' + repr(flag), candidate, include_aliases=flag,
                expected={'_operation_frame_kind': None, '_cache_verify_frame': cache_result})
    compare('no-frame', None, expected={'_operation_frame_kind': None, '_cache_verify_frame': False})
    require(digest(before) == BASELINE_SHA and digest(after) == PROPOSAL_SHA)
    output.write_text(json.dumps({'status': 'PASS', 'scope': __doc__, 'baseline_sha256': BASELINE_SHA,
                                 'proposal_sha256': PROPOSAL_SHA, 'optimize': sys.flags.optimize,
                                 'always_active_checks_executed': _CHECK_COUNT, **counts, 'cases': details}, indent=2)+'\n')
    print(json.dumps({'status': 'PASS', **counts, 'optimize': sys.flags.optimize,
                      'always_active_checks_executed': _CHECK_COUNT, 'output': str(output)}))


if __name__ == '__main__':
    main()
