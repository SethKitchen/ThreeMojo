#!/usr/bin/env python3
"""Focused lexical-only differential controls; run only after source approval.

Extract one exact helper AST from sealed bytes. Do not import any repository
module or alter a candidate. Every predicate remains active under Python -O.
"""
import ast
import builtins
from contextlib import ExitStack
import hashlib
import json
import os
import pathlib
from pathlib import Path, PosixPath, PurePosixPath, PureWindowsPath
import sys
import types
from unittest.mock import patch

SOURCE_SHA = '9b3848e41376ca31b7399998187b30f1c05519ba263961e16380a780b92f4643'
HELPER_AST_SHA = 'd02f09663ba33ad79ce4f5025c317f6c7bfad2e0529286b7a31430994754835f'
PATHLIB_SHA = '10ba48ae8063cfe7589436041d0d4628c05f427c7709cf8e75e486f8930cc32c'
_UNSET = object()
CHECKS = 0
AUDIT_ACTIVE = False
AUDIT_EVENTS = []


def require(value, detail):
    global CHECKS
    CHECKS += 1
    if not value:
        raise AssertionError(detail)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def audit(event, args):
    if AUDIT_ACTIVE and (event == 'open' or event in {
            'os.listdir', 'os.scandir', 'os.chdir', 'os.fchdir',
            'os.truncate', 'os.remove', 'os.rename', 'os.mkdir', 'os.rmdir',
            'os.symlink', 'os.link'} or event.startswith('pathlib.')):
        AUDIT_EVENTS.append(event)
        raise AssertionError('filesystem audit event: ' + event)


class LoggedText(str):
    def __new__(cls, value, log, label, fail=False):
        obj = super().__new__(cls, value)
        obj.log, obj.label, obj.fail = log, label, fail
        return obj

    def __bool__(self):
        self.log.append((self.label, 'bool'))
        if self.fail is True:
            raise RuntimeError(self.label + ' text parse blocked')
        return str.__len__(self) != 0

    def __getitem__(self, key):
        label = ('slice', key.start, key.stop, key.step) if isinstance(key, slice) else key
        self.log.append((self.label, 'getitem', label))
        if self.fail == 'getitem':
            raise RuntimeError(self.label + ' splitroot blocked')
        return str.__getitem__(self, key)

    def split(self, *args, **kwargs):
        self.log.append((self.label, 'split'))
        if self.fail == 'split':
            raise RuntimeError(self.label + ' split blocked')
        return str.split(self, *args, **kwargs)


class ForeignRoot:
    def __init__(self, log, value='/a', fail=False):
        self.log, self.value, self.fail = log, value, fail

    def __fspath__(self):
        self.log.append(('root', 'fspath'))
        if self.fail:
            raise RuntimeError('root fspath blocked')
        return self.value


class LoggedPath(PosixPath):
    def __init__(self, *args, log=None):
        super().__init__(*args)
        self.log = log if log is not None else []

    @property
    def parts(self):
        self.log.append(('path', 'parts'))
        return super().parts

    @property
    def anchor(self):
        self.log.append(('path', 'anchor'))
        return super().anchor

    def with_segments(self, *segments):
        self.log.append(('path', 'with_segments', tuple(type(x).__name__ for x in segments)))
        return type(self)(*segments, log=self.log)

    def relative_to(self, root):
        self.log.append(('path', 'relative_to'))
        return super().relative_to(root)


class DispatchOnlyPath(PosixPath):
    def __init__(self, *args, log=None, fail=False):
        super().__init__(*args)
        self.log, self.fail = log, fail

    @property
    def parts(self):
        raise AssertionError('helper inspected subclass parts')

    @property
    def anchor(self):
        raise AssertionError('helper inspected subclass anchor')

    def relative_to(self, root):
        self.log.append(('dispatch', 'relative_to', type(root).__name__))
        if self.fail:
            raise RuntimeError('custom relative_to blocked')
        return PosixPath('custom-result')


class RawList(list):
    def __init__(self, values, log, label):
        super().__init__(values)
        self.log, self.label = log, label

    def __iter__(self):
        self.log.append((self.label, 'raw-list-iter'))
        return super().__iter__()


def describe(value):
    # Keep the exact type object in the comparison, not merely its class name.
    if isinstance(value, pathlib.PurePath):
        return ('value', type(value), str(value), value.parts)
    return ('value', type(value), value)


def invoke(call, helper, fast_line, fallback_line):
    """Deny filesystem observations only around this one reference/helper call."""
    global AUDIT_ACTIVE
    events, blocked = [], []
    old_trace = sys.gettrace()
    require(old_trace is None, 'unexpected existing trace callback')

    def trace(frame, event, arg):
        if frame.f_code is helper.__code__:
            if event == 'line' and frame.f_lineno in (fast_line, fallback_line):
                events.append('fast' if frame.f_lineno == fast_line else 'fallback')
            return trace
        return None

    def deny(*args, **kwargs):
        blocked.append('filesystem surface')
        raise AssertionError('filesystem surface called')

    # These mocks are restored before result formatting or any receipt I/O.
    with ExitStack() as stack:
        for name in ('stat', 'lstat', 'resolve', 'cwd', 'absolute', 'open',
                     'read_bytes', 'read_text', 'iterdir', 'glob', 'rglob', 'walk'):
            stack.enter_context(patch.object(Path, name, deny))
        for name in ('stat', 'lstat', 'getcwd', 'listdir', 'scandir', 'readlink',
                     'open', 'access'):
            stack.enter_context(patch.object(os, name, deny))
        stack.enter_context(patch.object(builtins, 'open', deny))
        sys.settrace(trace)
        AUDIT_ACTIVE = True
        try:
            try:
                value = call()
            except Exception as error:
                result = ('exception', type(error), str(error))
            else:
                result = value
        finally:
            AUDIT_ACTIVE = False
            sys.settrace(old_trace)
    require(not blocked, 'reference/helper attempted filesystem observation')
    require(not AUDIT_EVENTS, 'reference/helper emitted filesystem audit event')
    if not (type(result) is tuple and result and result[0] == 'exception'):
        result = describe(result)
    return result, events


def ordinary(path, root, path_type=PosixPath, root_type=PosixPath):
    def factory(log):
        return path_type(path), root_type(root)
    return factory


def exotic_text(path_exotic=False, root_exotic=False, preparse=False,
                fail_path=False, fail_root=False):
    def factory(log):
        p = LoggedText('/a/b', log, 'path', fail_path) if path_exotic else '/a/b'
        r = LoggedText('/a', log, 'root', fail_root) if root_exotic else '/a'
        path, root = PosixPath(p), PosixPath(r)
        if preparse:
            root.parts
            path.parts
        log.clear()
        return path, root
    return factory


def foreign_root(value='/a', fail=False):
    return lambda log: (PosixPath('/a/b'), ForeignRoot(log, value, fail))


def raw_layout(which, layout):
    def factory(log):
        path, root = PosixPath('/a/b'), PosixPath('/a')
        target = root if which == 'root' else path
        if layout == 'missing':
            del target._raw_paths
        elif layout == 'tuple':
            target._raw_paths = tuple(target._raw_paths)
        elif layout == 'list-subclass':
            target._raw_paths = RawList(target._raw_paths, log, which)
        elif layout == 'non-string':
            target._raw_paths = [17]
        else:
            raise AssertionError('unknown private layout case')
        return path, root
    return factory


def main():
    require(len(sys.argv) == 4, 'usage: harness.py SOURCE OUTPUT_JSON REVIEWED_HARNESS_SHA')
    harness_raw = Path(__file__).read_bytes()
    require(sha(harness_raw) == sys.argv[3], 'wrapper-provided reviewed harness identity')
    source_path, output_path = Path(sys.argv[1]), Path(sys.argv[2])
    source_raw = source_path.read_bytes()
    require(sha(source_raw) == SOURCE_SHA, 'unreviewed source seal')
    require(sys.version_info[:2] == (3, 12), 'requires reviewed Python 3.12 layout')
    require(os.name == 'posix', 'requires reviewed POSIX host')
    stdlib_path = Path(pathlib.__file__)
    stdlib_raw = stdlib_path.read_bytes()
    require(sha(stdlib_raw) == PATHLIB_SHA, 'unreviewed pathlib reference')
    require(pathlib.PurePath.relative_to.__code__.co_filename == str(stdlib_path),
            'reference code source identity')
    compiled_stdlib = compile(stdlib_raw, str(stdlib_path), 'exec',
                              dont_inherit=True, optimize=sys.flags.optimize)
    pending, reference_codes = [compiled_stdlib], []
    while pending:
        code = pending.pop()
        if code.co_qualname == 'PurePath.relative_to':
            reference_codes.append(code)
        pending.extend(value for value in code.co_consts
                       if isinstance(value, types.CodeType))
    require(len(reference_codes) == 1, 'one hashed-source reference code')
    require(reference_codes[0] == pathlib.PurePath.relative_to.__code__,
            'live reference equals compiled checked pathlib bytes')
    tree = ast.parse(source_raw.decode('utf-8'), filename=str(source_path))
    matches = [n for n in tree.body if isinstance(n, ast.FunctionDef)
               and n.name == '_relative_path']
    require(len(matches) == 1, 'one helper definition')
    node = matches[0]
    require(sha(ast.dump(node, include_attributes=False).encode()) == HELPER_AST_SHA,
            'reviewed helper AST identity')
    require(not any(isinstance(n, ast.Assert) for n in ast.walk(node)),
            'helper contains no optimized-away checks')
    returns = [n for n in ast.walk(node) if isinstance(n, ast.Return)]
    fast = [n for n in returns if isinstance(n.value, ast.Call)
            and isinstance(n.value.func, ast.Name) and n.value.func.id == 'PosixPath']
    fallback = [n for n in returns if isinstance(n.value, ast.Call)
                and isinstance(n.value.func, ast.Attribute) and n.value.func.attr == 'relative_to']
    require(len(returns) == 2 and len(fast) == len(fallback) == 1,
            'exact two return branches')
    namespace = {'PosixPath': PosixPath, 'os': types.SimpleNamespace(name='posix')}
    exec(compile(ast.Module(body=[node], type_ignores=[]), str(source_path), 'exec'), namespace)
    helper = namespace['_relative_path']
    require(not any(isinstance(n, ast.Assert) for n in ast.walk(ast.parse(harness_raw))),
            'all harness checks remain active under -O')
    sys.addaudithook(audit)
    records, totals = [], {'fast': 0, 'fallback': 0}

    def compare(name, factory, branch, *, expected=_UNSET, error_type=None,
                first_callback=None, minimum_callbacks=0, exact_log=None,
                platform='posix'):
        old_log, new_log = [], []
        old_args, new_args = factory(old_log), factory(new_log)
        require(old_log == new_log, (name, 'independent fixture construction'))
        namespace['os'] = types.SimpleNamespace(name=platform)
        old, old_events = invoke(lambda: old_args[0].relative_to(old_args[1]),
                                 helper, fast[0].lineno, fallback[0].lineno)
        new, new_events = invoke(lambda: helper(*new_args),
                                 helper, fast[0].lineno, fallback[0].lineno)
        require(old == new, (name, 'result/type/exception mismatch', old, new))
        require(new[0] == ('value' if error_type is None else 'exception'),
                (name, 'explicit success/exception route', new))
        require(old_log == new_log, (name, 'callback order/count mismatch', old_log, new_log))
        require(old_events == [], (name, 'reference unexpectedly entered proposal'))
        require(new_events == [branch], (name, 'actual helper branch', new_events, branch))
        require(len(new_log) >= minimum_callbacks, (name, 'callback route not exercised'))
        if first_callback is not None:
            require(bool(new_log) and new_log[0][0] == first_callback,
                    (name, 'first parsing callback', new_log))
        if exact_log is not None:
            require(new_log == exact_log, (name, 'explicit callback route', new_log))
        if expected is not _UNSET:
            require(new[0] == 'value' and new[1] is PosixPath and new[2] == expected,
                    (name, 'explicit successful result', new, expected))
        if error_type is not None:
            require(new[0] == 'exception' and new[1] is error_type,
                    (name, 'explicit exception route', new, error_type))
        totals[branch] += 1
        records.append({'case': name, 'branch': branch, 'outcome': new[0],
                        'type': new[1].__module__ + '.' + new[1].__qualname__,
                        'detail': new[2], 'callbacks': new_log})

    successes = [
        ('equal', '/a', '/a', '.'), ('root-equal', '/', '/', '.'),
        ('root', '/a/b', '/', 'a/b'), ('nested', '/a/b/c', '/a', 'b/c'),
        ('dotfiles', '/a/.dot', '/a', '.dot'), ('unicode', '/a/é/漢', '/a', 'é/漢'),
        ('spaces', '/a/a b', '/a', 'a b'), ('case-retained', '/a/A', '/a', 'A'),
        ('nul', '/a/\0x', '/a', '\0x'), ('slashes-dots', '/a//./b///c/', '/a/.', 'b/c'),
        ('triple-anchor', '///a/b', '///a', 'b'), ('backslash-name', '/a/x\\y', '/a', 'x\\y'),
        ('colon-name', '/a/C:', '/a', 'C:'), ('prefix-root', '/a/ab', '/a', 'ab'),
    ]
    for name, path, root, expected in successes:
        compare(name, ordinary(path, root), 'fast', expected=expected)
    # Finite deterministic cross-product catches string-prefix and depth mistakes.
    components = ('a', 'ab', 'A', '.hidden', 'é', 'space x', '\0x')
    for root_part in components:
        for leaf in components:
            compare('components:' + repr((root_part, leaf)),
                    ordinary('/' + root_part + '/' + leaf, '/' + root_part),
                    'fast', expected=leaf)

    for name, path, root, succeeds in [
        ('sibling-prefix', '/ab/x', '/a', False), ('deeper-root', '/a', '/a/b', False),
        ('outside', '/b/x', '/a', False), ('case-mismatch', '/A/x', '/a', False),
        ('relative', 'a/b', 'a', True), ('relative-empty', '', '', True),
        ('relative-dot', './a/b', '.', True), ('mixed-path', 'a/b', '/a', False),
        ('mixed-root', '/a/b', 'a', False), ('double-slash', '//a/b', '//a', True),
        ('double-mixed', '//a/b', '/a', False), ('path-dotdot', '/a/../b', '/a', True),
        ('root-dotdot', '/a/../b', '/a/..', True), ('windows-looking', 'C:\\a\\b', 'C:\\a', False),
        ('windows-slashes', 'C:/a/b', 'C:/a', True),
    ]:
        compare(name, ordinary(path, root), 'fallback',
                error_type=None if succeeds else ValueError)
    compare('platform-fallback', ordinary('/a/b', '/a'), 'fallback', expected='b', platform='nt')
    compare('pure-posix', ordinary('/a/b', '/a', PurePosixPath, PurePosixPath), 'fallback')
    compare('pure-windows', ordinary('C:/a/b', 'C:/a', PureWindowsPath, PureWindowsPath), 'fallback')
    compare('windows-foreign-root', ordinary('/a/b', 'C:/a', PosixPath, PureWindowsPath),
            'fallback', error_type=ValueError)
    compare('str-root', lambda log: (PosixPath('/a/b'), '/a'), 'fallback', expected='b')
    compare('invalid-root', lambda log: (PosixPath('/a/b'), 17), 'fallback', error_type=TypeError)
    compare('pathlike-root', foreign_root(), 'fallback', expected='b',
            exact_log=[('root', 'fspath')])
    compare('pathlike-raising', foreign_root(fail=True), 'fallback', error_type=RuntimeError,
            exact_log=[('root', 'fspath')])
    compare('pathlike-invalid-result', foreign_root(value=b'/a'), 'fallback', error_type=TypeError,
            exact_log=[('root', 'fspath')])
    compare('subclass-normal', lambda log: (LoggedPath('/a/b', log=log), PosixPath('/a')),
            'fallback', first_callback='path', minimum_callbacks=2)
    compare('subclass-root', lambda log: (PosixPath('/a/b'), LoggedPath('/a', log=log)),
            'fallback', expected='b', exact_log=[])
    compare('subclass-dispatch', lambda log: (DispatchOnlyPath('/a/b', log=log), ForeignRoot(log)),
            'fallback', expected='custom-result', exact_log=[('dispatch', 'relative_to', 'ForeignRoot')])
    compare('subclass-raising', lambda log: (DispatchOnlyPath('/a/b', log=log, fail=True), PosixPath('/a')),
            'fallback', error_type=RuntimeError, exact_log=[('dispatch', 'relative_to', 'PosixPath')])

    for path_exotic, root_exotic in ((True, False), (False, True), (True, True)):
        for preparse in (False, True):
            name = 'str-subclass:' + repr((path_exotic, root_exotic, preparse))
            # A pre-parsed path may have no callbacks; root is freshly copied by relative_to.
            first = 'root' if root_exotic else ('path' if not preparse else None)
            compare(name, exotic_text(path_exotic, root_exotic, preparse), 'fallback',
                    expected='b', first_callback=first,
                    minimum_callbacks=1 if first else 0)
    for fail_path, fail_root in ((True, False), (False, True), (True, True)):
        compare('str-raising:' + repr((fail_path, fail_root)),
                exotic_text(True, True, fail_path=fail_path, fail_root=fail_root),
                'fallback', error_type=RuntimeError, first_callback='root', minimum_callbacks=1)
    for stage in ('getitem', 'split'):
        def late_parser(log, stage=stage):
            absolute = stage == 'getitem'
            path = PosixPath('/a/b' if absolute else 'a/b')
            root = PosixPath(LoggedText('/a' if absolute else 'a', log, 'root', stage))
            return path, root
        compare('late-parser-raising:' + stage, late_parser, 'fallback',
                error_type=RuntimeError, first_callback='root', minimum_callbacks=2)
    for which in ('root', 'path'):
        for layout in ('missing', 'tuple', 'list-subclass', 'non-string'):
            compare('layout:' + which + ':' + layout, raw_layout(which, layout), 'fallback',
                    error_type=(AttributeError if layout == 'missing' else
                                TypeError if layout == 'non-string' else None))

    require(totals['fast'] == len(successes) + len(components) ** 2, 'all expected fast cases')
    require(totals['fallback'] == 47, 'all expected fallback cases')
    require(sum(totals.values()) == len(records), 'all cases have explicit branch evidence')
    require(sha(source_path.read_bytes()) == SOURCE_SHA, 'source changed during controls')
    require(sha(stdlib_path.read_bytes()) == PATHLIB_SHA, 'pathlib changed during controls')
    require(sha(Path(__file__).read_bytes()) == sha(harness_raw), 'harness changed during controls')
    receipt = {'status': 'PASS', 'qualification': False, 'optimize': sys.flags.optimize,
               'source_sha256': SOURCE_SHA, 'helper_ast_sha256': HELPER_AST_SHA,
               'pathlib_sha256': PATHLIB_SHA, 'harness_sha256': sha(harness_raw),
               'cases': len(records), 'always_active_checks': CHECKS,
               'branch_counts': totals, 'filesystem_audit_events': AUDIT_EVENTS,
               'records': records}
    output_path.write_text(json.dumps(receipt, indent=2, ensure_ascii=True) + '\n')
    print(json.dumps({k: v for k, v in receipt.items() if k != 'records'}, sort_keys=True))


if __name__ == '__main__':
    main()
