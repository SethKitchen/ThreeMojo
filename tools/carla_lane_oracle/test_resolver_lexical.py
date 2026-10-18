# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Bounded differential controls for resolver-only lexical acceleration.

The historical reference is frozen from candidate-v6's resolver_unshadowed,
with only its function name changed. The current unoptimized reference adds
only PR760's reviewed consumed-coordinate suffix guard (9ed7e659). Both rebind
globals to the deployed checker to share unchanged helpers and real filesystem
operations. The historical reference still checks every unchanged case.
All checks remain active under python -O; no repository-wide census is run.
"""
from contextlib import ExitStack
import os
from pathlib import Path, PosixPath
import tempfile
import types
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as cleanup


def _baseline_resolver_unshadowed(root, paths):
    """Refuse alternate qualified-module and namespace lookup surfaces.

    Every reviewed import begins at a protected top-level namespace. Guard
    those namespace names conservatively everywhere, including every compiled
    entry directory, repository root and supplied include root. Imported-module
    directories are not Mojo lookup roots. An unrelated leaf basename elsewhere
    cannot shadow a qualified import and is not itself a namespace competitor.
    Exact consumed module/prefix coordinates still reject case, alternate
    suffix/package and symlink changes. Only three exact regular wiki files are
    inert. Include roots receive structural checks only: maintained generation
    origins and source/staged manifests bind instrumented coverage bytes.
    """
    root = Path(root)
    if not root.is_dir() or not _root_unaliased(root):
        return False
    allowed = set(paths)
    stems = {str(Path(p).with_suffix('')).casefold() for p in allowed}
    canonical_prefixes = {str(parent) for p in allowed for parent in Path(p).parents if str(parent) != '.'}
    prefixes = {prefix.casefold() for prefix in canonical_prefixes}
    top = {Path(p).parts[0].casefold() for p in allowed} | {'std'}
    inert = {'docs/wiki/Math.md', 'docs/wiki/Units.md', 'docs/wiki/Extensions.md'}
    try:
        for folder, directories, files in os.walk(root, followlinks=False):
            relative_dir = _relative_path(Path(folder), root).as_posix()
            directories[:] = [name for name in directories if name not in SKIP
                              and (Path(relative_dir) / name).as_posix() != 'coverage/build']
            for name in directories + files:
                path = Path(folder) / name
                relative = _relative_path(path, root).as_posix()
                folded = relative.casefold()
                stem = str(Path(relative).with_suffix('')).casefold()
                # Namespace roots remain protected at every actual lookup root.
                scoped_name = name.split('.')[0].casefold()
                relevant = (folded in stems or folded in prefixes or stem in stems
                            or stem in prefixes or scoped_name in top
                            or (name == '__init__.mojo' and relative_dir.casefold() in prefixes))
                if not relevant:
                    continue
                if relative in inert and not path.is_symlink() and path.is_file():
                    continue
                if path.is_symlink():
                    return False
                if path.is_dir():
                    if relative not in canonical_prefixes:
                        return False
                    continue
                if relative not in allowed or not path.is_file():
                    return False
        return True
    except OSError:
        return False


def _successor_resolver_unshadowed(root, paths):
    """Refuse alternate qualified-module and namespace lookup surfaces.

    Every reviewed import begins at a protected top-level namespace. Guard
    those namespace names conservatively everywhere, including every compiled
    entry directory, repository root and supplied include root. Imported-module
    directories are not Mojo lookup roots. An unrelated leaf basename elsewhere
    cannot shadow a qualified import and is not itself a namespace competitor.
    Exact consumed module/prefix coordinates still reject case, alternate
    suffix/package and symlink changes. Only three exact regular wiki files are
    inert. Include roots receive structural checks only: maintained generation
    origins and source/staged manifests bind instrumented coverage bytes.
    """
    root = Path(root)
    if not root.is_dir() or not _root_unaliased(root):
        return False
    allowed = set(paths)
    coordinates = {path.casefold() for path in allowed}
    stems = {str(Path(p).with_suffix('')).casefold() for p in allowed}
    canonical_prefixes = {str(parent) for p in allowed for parent in Path(p).parents if str(parent) != '.'}
    prefixes = {prefix.casefold() for prefix in canonical_prefixes}
    top = {Path(p).parts[0].casefold() for p in allowed} | {'std'}
    inert = {'docs/wiki/Math.md', 'docs/wiki/Units.md', 'docs/wiki/Extensions.md'}
    try:
        for folder, directories, files in os.walk(root, followlinks=False):
            relative_dir = _relative_path(Path(folder), root).as_posix()
            directories[:] = [name for name in directories if name not in SKIP
                              and (Path(relative_dir) / name).as_posix() != 'coverage/build']
            for name in directories + files:
                path = Path(folder) / name
                relative = _relative_path(path, root).as_posix()
                folded = relative.casefold()
                stem = str(Path(relative).with_suffix('')).casefold()
                # Namespace roots remain protected at every actual lookup root.
                scoped_name = name.split('.')[0].casefold()
                # PR760 deliberately refuses suffixes appended to consumed
                # coordinates, including origin sidecars unless allowlisted.
                coordinate_suffix = any(
                    (relative[:-len(name)] + name[:index]).casefold() in coordinates
                    for index, character in enumerate(name) if character == '.')
                relevant = (coordinate_suffix or folded in stems or folded in prefixes or stem in stems
                            or stem in prefixes or scoped_name in top
                            or (name == '__init__.mojo' and relative_dir.casefold() in prefixes))
                if not relevant:
                    continue
                if relative in inert and not path.is_symlink() and path.is_file():
                    continue
                if path.is_symlink():
                    return False
                if path.is_dir():
                    if relative not in canonical_prefixes:
                        return False
                    continue
                if relative not in allowed or not path.is_file():
                    return False
        return True
    except OSError:
        return False


# Rebinding shares only the unchanged dependencies, never the tested resolver.
HISTORICAL = types.FunctionType(_baseline_resolver_unshadowed.__code__, vars(cleanup))
BASELINE = types.FunctionType(_successor_resolver_unshadowed.__code__, vars(cleanup))
ALLOWED = ('math/vector.mojo', 'units/value.mojo', 'extensions/carla/curve.mojo')
PATH_PROBES = ('is_symlink', 'is_dir', 'is_file', 'stat', 'lstat')


class ResolverLexicalTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='resolver-lexical-')
        self.addCleanup(temporary.cleanup)
        # Some platforms expose their temporary directory through an alias.
        self.root = Path(temporary.name).resolve()

    def write(self, relative, root=None):
        path = (self.root if root is None else root) / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('# resolver fixture\n', encoding='utf-8')
        return path

    def fixture(self, label):
        root = self.root / label
        root.mkdir()
        return root

    @staticmethod
    def _value(value):
        if isinstance(value, Path):
            return ('path', str(value))
        if type(value) is str:
            return ('str', value)
        # A stable repr on the protocol fixtures avoids calling __fspath__ here.
        return (type(value).__name__, repr(value))

    def observe(self, function, *, root=None, paths=ALLOWED, walk=None,
                fault=None, root_factory=None):
        events, batches, lexical = [], [], []
        original_walk = os.walk
        original_relative = cleanup._relative_path
        original_path_probes = {name: getattr(Path, name) for name in PATH_PROBES}
        original_os_probes = {name: getattr(os, name)
                              for name in ('stat', 'lstat', 'scandir')}

        def record(kind, target, args, kwargs):
            event = (kind, self._value(target), tuple(map(self._value, args)),
                     tuple((key, self._value(value)) for key, value in sorted(kwargs.items())))
            events.append(event)
            if fault is not None and kind == fault[0] and str(target) == str(fault[1]):
                raise fault[2]('injected ' + kind)

        def path_probe(name, original):
            def probe(target, *args, **kwargs):
                record('Path.' + name, target, args, kwargs)
                return original(target, *args, **kwargs)
            return probe

        def os_probe(name, original):
            def probe(target, *args, **kwargs):
                record('os.' + name, target, args, kwargs)
                return original(target, *args, **kwargs)
            return probe

        def walking(target, *args, **kwargs):
            record('walk', target, args, kwargs)
            source = (original_walk(target, *args, **kwargs) if walk is None
                      else walk(target, events))
            for folder, directories, files in source:
                events.append(('yield', self._value(folder),
                               tuple(map(self._value, directories)),
                               tuple(map(self._value, files))))
                batches.append(directories)
                yield folder, directories, files
            events.append(('walk-exhausted',))

        def relative(path, base):
            lexical.append((str(path), str(base)))
            return original_relative(path, base)

        with ExitStack() as stack:
            for name, original in original_path_probes.items():
                stack.enter_context(patch.object(Path, name, path_probe(name, original)))
            for name, original in original_os_probes.items():
                stack.enter_context(patch.object(os, name, os_probe(name, original)))
            stack.enter_context(patch.object(os, 'walk', walking))
            stack.enter_context(patch.object(cleanup, '_relative_path', relative))
            supplied = self.root if root is None else root
            try:
                if root_factory is not None:
                    supplied = root_factory(supplied, events)
                outcome = ('return', function(supplied, paths))
            except Exception as error:
                outcome = ('raise', type(error), error.args)
            # Also observe the caller's in-place pruning on early return/error.
            events.extend(('pruned', index, tuple(map(self._value, names)))
                          for index, names in enumerate(batches))
        return outcome, events, lexical

    def equivalent(self, expected=None, *, historical=True, **kwargs):
        reference = self.observe(BASELINE, **kwargs)
        if historical:
            self.assertEqual(reference[:2], self.observe(HISTORICAL, **kwargs)[:2])
        actual = self.observe(cleanup.resolver_unshadowed, **kwargs)
        self.assertEqual(actual[:2], reference[:2])
        if expected is not None:
            self.assertEqual(actual[0], ('return', expected))
        return reference, actual

    @staticmethod
    def rows(*rows):
        def walk(root, events):
            for folder, directories, files in rows:
                yield folder, list(directories), list(files)
        return walk

    def test_regular_inputs_and_exact_relevant_probe_order(self):
        for relative in ALLOWED:
            self.write(relative)
        self.write('ordinary/nested/noise.txt')
        _, actual = self.equivalent(True)
        direct = [(event[0], event[1][1]) for event in actual[1]
                  if event[0] in ('Path.is_symlink', 'Path.is_dir', 'Path.is_file')]
        for relative in ALLOWED:
            target = str(self.root / relative)
            self.assertEqual([kind for kind, path in direct if path == target],
                             ['Path.is_symlink', 'Path.is_dir', 'Path.is_file'])
        self.assertFalse(any(path.endswith('/noise.txt') for _, path in direct))
        self.assertEqual(sum(event[0] == 'walk' for event in actual[1]), 1)
        self.assertTrue(any(event[0] == 'os.scandir' for event in actual[1]))

    def test_case_suffix_package_and_namespace_competitors(self):
        cases = (
            ('Math.mojo', 'file'), ('std.mojo', 'file'),
            ('unrelated/math.mojo', 'file'), ('math/Vector.mojo', 'file'),
            ('MATH/vector.mojo', 'file'), ('math/vector.mojopkg', 'file'),
            ('math/vector.so', 'file'), ('math/__init__.mojo', 'file'),
            ('extensions/carla.mojo', 'file'), ('math/vector', 'directory'),
            ('unrelated/extensions', 'directory'),
        )
        for index, (relative, kind) in enumerate(cases):
            with self.subTest(relative=relative, kind=kind):
                root = self.fixture('competitor-' + str(index))
                if kind == 'directory':
                    (root / relative).mkdir(parents=True)
                else:
                    self.write(relative, root)
                self.equivalent(False, root=root)

    def test_exact_inert_wiki_files_keep_two_probe_short_circuit(self):
        for name in ('Math', 'Units', 'Extensions'):
            self.write('docs/wiki/' + name + '.md')
        _, actual = self.equivalent(True)
        for name in ('Math', 'Units', 'Extensions'):
            path = str(self.root / ('docs/wiki/' + name + '.md'))
            probes = [event[0] for event in actual[1]
                      if event[0] in ('Path.is_symlink', 'Path.is_dir', 'Path.is_file')
                      and event[1][1] == path]
            self.assertEqual(probes, ['Path.is_symlink', 'Path.is_file'])
        self.write('docs/wiki/Math.txt')
        self.equivalent(False)

    def test_relevant_symlinks_and_root_aliases_are_refused(self):
        target = self.write('ordinary/target.txt')
        for index, (relative, destination, directory) in enumerate((
                ('math/vector.mojo', target, False),
                ('math/vector.mojo', self.root / 'missing', False),
                ('math', target.parent, True),
                ('docs/wiki/Math.md', target, False))):
            with self.subTest(relative=relative, destination=destination):
                root = self.fixture('link-' + str(index))
                link = root / relative
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(destination, target_is_directory=directory)
                self.equivalent(False, root=root)
        alias = self.root / 'aliased-root'
        alias.symlink_to(target.parent, target_is_directory=True)
        _, actual = self.equivalent(False, root=alias)
        self.assertFalse(any(event[0] == 'walk' for event in actual[1]))

    def test_irrelevant_links_do_not_add_probe_or_traversal(self):
        target = self.write('ordinary/target.txt')
        (self.root / 'irrelevant-link.txt').symlink_to(target)
        (self.root / 'unrelated-link').symlink_to(target.parent, target_is_directory=True)
        _, actual = self.equivalent(True)
        probes = [event for event in actual[1] if event[0].startswith('Path.')]
        self.assertFalse(any('irrelevant-link' in event[1][1] for event in probes))
        scans = [event[1][1] for event in actual[1] if event[0] == 'os.scandir']
        self.assertNotIn(str(self.root / 'unrelated-link'), scans)

    def test_walk_pruning_is_unchanged_and_visible(self):
        for directory in sorted(cleanup.SKIP):
            self.write(directory + '/math.mojo')
        self.write('coverage/build/math.mojo')
        self.write('coverage/kept/noise.txt')
        _, actual = self.equivalent(True)
        scans = [event[1][1] for event in actual[1] if event[0] == 'os.scandir']
        for directory in cleanup.SKIP:
            self.assertNotIn(str(self.root / directory), scans)
        self.assertNotIn(str(self.root / 'coverage/build'), scans)
        self.assertIn(str(self.root / 'coverage/kept'), scans)
        self.assertTrue(any(event[0] == 'pruned' for event in actual[1]))

    def test_late_competitor_is_seen_after_success_and_removal(self):
        self.write('math/vector.mojo')
        self.equivalent(True)
        competitor = self.write('math/vector.mojopkg')
        self.equivalent(False)
        competitor.unlink()
        self.equivalent(True)

    def test_dot_multiple_suffix_case_and_unicode_physical_names(self):
        names = ('.a', '.a.b', '..foo', '...foo', 'foo.', 'foo..',
                 'foo...bar', '..foo.bar', '...', '....', '.mojo',
                 'vector.mojo.py', 'VECTOR.MOJO', 'Straße.mojo',
                 'STRASSE.mojo', 'σχήμα.mojo', 'ΣΧΉΜΑ.mojo', 'Kelvin.txt')
        for index, name in enumerate(names):
            with self.subTest(name=name):
                root = self.fixture('name-' + str(index))
                self.write('math/' + name, root)
                self.equivalent(root=root, historical=name != 'vector.mojo.py')
        root = self.fixture('unicode-allowed')
        self.write('Straße/σχήμα.mojo', root)
        self.equivalent(True, root=root, paths=('Straße/σχήμα.mojo',))
        root = self.fixture('unicode-alias')
        self.write('STRASSE/σχήμα.mojo', root)
        self.equivalent(False, root=root, paths=('Straße/σχήμα.mojo',))

    def test_consumed_coordinate_suffix_successor_preserves_exact_probes(self):
        # This is an intentional security-contract successor, not a lexical
        # optimization difference. Keep the old outcome visible and compare
        # the complete new filesystem trace against the unoptimized reference.
        for index, relative in enumerate((
                'math/vector.mojo.py', 'math/vector.mojo.origin.json',
                'math/VECTOR.MOJO.py', 'math/vector.mojo..py',
                'units/value.mojo.origin', 'extensions/carla/curve.mojo.py')):
            for kind in ('file', 'directory', 'symlink'):
                with self.subTest(relative=relative, kind=kind):
                    root = self.fixture('suffix-' + str(index) + '-' + kind)
                    target = root / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if kind == 'file':
                        self.write(relative, root)
                    elif kind == 'directory':
                        target.mkdir()
                    else:
                        target.symlink_to(root / 'missing')
                    self.assertEqual(self.observe(HISTORICAL, root=root)[0],
                                     ('return', True))
                    _, actual = self.equivalent(False, root=root, historical=False)
                    probes = [event[0] for event in actual[1]
                              if event[0] in ('Path.is_symlink', 'Path.is_dir', 'Path.is_file')
                              and event[1][1] == str(target)]
                    self.assertEqual(probes, ['Path.is_symlink'] if kind == 'symlink'
                                     else ['Path.is_symlink', 'Path.is_dir'])

    def test_coordinate_sidecar_requires_exact_allowlisting(self):
        relative = 'math/vector.mojo.origin.json'
        self.write(relative)
        self.equivalent(True, paths=(*ALLOWED, relative))
        self.equivalent(False, historical=False)
        # Similar names at unrelated coordinates are still irrelevant.
        root = self.fixture('unrelated-suffix')
        self.write('ordinary/vector.mojo.origin.json', root)
        self.write('math/vectors.mojo.origin.json', root)
        self.equivalent(True, root=root)

    def test_root_dot_and_relative_root_forms(self):
        for root in ('.', Path('.'), Path('/'), os.path.relpath(self.root)):
            with self.subTest(root=root):
                def walk(base, events):
                    yield str(base), [], ['unrelated.txt']
                reference, actual = self.equivalent(True, root=root, walk=walk)
                # These non-canonical walk folders must use the old lexical path.
                self.assertEqual(actual[2], reference[2])

    def test_dot_and_multiple_suffix_consumed_coordinates(self):
        # Matching coordinates force the suffix result to affect admission;
        # unrelated dotted noise alone could miss a broken relevance decision.
        names = ('.a', '.a.b', '..foo', '...foo', 'foo.', 'foo..',
                 'foo...bar', '..foo.bar', '...', 'vector.mojo.py')
        for index, name in enumerate(names):
            with self.subTest(name=name):
                root = self.fixture('consumed-' + str(index))
                relative = 'math/' + name
                target = self.write(relative, root)
                _, actual = self.equivalent(root=root, paths=(relative,))
                if actual[0] == ('return', True):
                    self.assertTrue(any(event[0] == 'Path.is_file'
                                        and event[1][1] == str(target)
                                        for event in actual[1]))

    def test_nondirectory_roots_stop_before_walking(self):
        file_root = self.write('plain-file')
        for root in (file_root, self.root / 'missing-root'):
            with self.subTest(root=root):
                _, actual = self.equivalent(False, root=root)
                self.assertFalse(any(event[0] == 'walk' for event in actual[1]))

    def test_mocked_noncanonical_folders_and_outside_roots(self):
        folders = (str(self.root) + '/', str(self.root) + '//child',
                   str(self.root) + '/./child', str(self.root) + '/a/../child',
                   '/' + str(self.root), str(self.root.parent / 'outside'),
                   Path(self.root), None, b'/bytes-folder')
        for folder in folders:
            with self.subTest(folder=folder):
                reference, actual = self.equivalent(
                    walk=self.rows((folder, [], ['unrelated.txt'])))
                self.assertEqual(actual[2], reference[2])

    def test_mocked_exotic_names_preserve_errors_and_fallback(self):
        names = ('', '.', '..', '../math', './noise.txt', 'nested/noise.txt',
                 '/absolute', '//absolute', 'foo.', 'foo..', '...',
                 None, 7, b'bytes.txt', Path('pathlike.txt'))
        for name in names:
            for directory in (False, True):
                with self.subTest(name=name, directory=directory):
                    reference, actual = self.equivalent(walk=self.rows((
                        str(self.root), [name] if directory else [],
                        [] if directory else [name])))
                    self.assertEqual(actual[2], reference[2])

    def test_str_subclass_and_pathlike_protocol_order(self):
        def make_text(value, events):
            class Text(str):
                def split(self, *args, **kwargs):
                    events.append(('text.split', str(self), args))
                    return super().split(*args, **kwargs)
                def rfind(self, *args, **kwargs):
                    events.append(('text.rfind', str(self), args))
                    return super().rfind(*args, **kwargs)
                def startswith(self, *args, **kwargs):
                    events.append(('text.startswith', str(self), args))
                    return super().startswith(*args, **kwargs)
                def endswith(self, *args, **kwargs):
                    events.append(('text.endswith', str(self), args))
                    return super().endswith(*args, **kwargs)
            return Text(value)

        def make_pathlike(value, events):
            class PathLike:
                def __fspath__(self):
                    events.append(('fspath', value))
                    return value
                def __repr__(self):
                    return 'PathLike(' + repr(value) + ')'
            return PathLike()

        for factory in (make_text, make_pathlike):
            for position in ('root', 'folder', 'file', 'directory'):
                with self.subTest(factory=factory.__name__, position=position):
                    def walk(root, events):
                        folder = factory(str(root), events) if position == 'folder' else str(root)
                        name = factory('ordinary.txt', events)
                        yield folder, [name] if position == 'directory' else [], (
                            [name] if position == 'file' else ['unrelated.txt'])
                    root_factory = (lambda root, events: factory(str(root), events)) if position == 'root' else None
                    self.equivalent(walk=walk, root_factory=root_factory)

    def test_mocked_walk_preserves_yield_and_pruning_order(self):
        walk = self.rows(
            (str(self.root), ['ordinary', '.git', 'coverage'], ['noise.txt']),
            (str(self.root / 'ordinary'), [], ['other.txt']),
            (str(self.root / 'coverage'), ['build', 'kept'], []),
            (str(self.root / 'coverage/kept'), [], ['last.txt']))
        _, actual = self.equivalent(True, walk=walk)
        pruned = [event[2] for event in actual[1] if event[0] == 'pruned']
        self.assertEqual(pruned[0], (('str', 'ordinary'), ('str', 'coverage')))
        self.assertEqual(pruned[2], (('str', 'kept'),))
        self.assertEqual(sum(event[0] == 'yield' for event in actual[1]), 4)

    def test_str_subclass_exception_keeps_lexical_failure_position(self):
        for error in (OSError, ValueError):
            with self.subTest(error=error):
                def walk(root, events):
                    class Name(str):
                        def split(self, *args, **kwargs):
                            events.append(('name.split.failure', args))
                            raise error('name protocol failure')
                    yield str(root), [], [Name('ordinary.txt')]
                _, actual = self.equivalent(walk=walk)
                expected = (('return', False) if error is OSError else
                            ('raise', error, ('name protocol failure',)))
                self.assertEqual(actual[0], expected)

    def test_probe_failure_scope_and_exception_order(self):
        target = self.write('math/vector.mojo')
        cases = (('Path.is_dir', self.root, True),
                 ('Path.is_symlink', self.root, True),
                 ('Path.is_symlink', target, False),
                 ('Path.is_dir', target, False),
                 ('Path.is_file', target, False),
                 ('os.scandir', self.root, False))
        for kind, path, outside_try in cases:
            for error in (OSError, ValueError):
                with self.subTest(kind=kind, path=path, error=error):
                    _, actual = self.equivalent(fault=(kind, path, error))
                    if error is OSError and kind == 'os.scandir':
                        # Preserve os.walk's existing default onerror behavior.
                        self.assertEqual(actual[0], ('return', True))
                    elif error is OSError and not outside_try:
                        self.assertEqual(actual[0], ('return', False))
                    else:
                        self.assertEqual(actual[0], ('raise', error, ('injected ' + kind,)))

    def test_walk_open_and_iteration_exceptions_are_not_reordered(self):
        for error in (OSError, ValueError, RuntimeError):
            for after_yield in (False, True):
                with self.subTest(error=error, after_yield=after_yield):
                    def walk(root, events):
                        events.append(('walk-before-failure',))
                        if after_yield:
                            yield str(root), [], ['noise.txt']
                        raise error('walk failure')
                    _, actual = self.equivalent(walk=walk)
                    expected = (('return', False) if error is OSError
                                else ('raise', error, ('walk failure',)))
                    self.assertEqual(actual[0], expected)

    def test_builtin_posix_fast_path_is_observable_without_hiding_probes(self):
        target = self.write('math/vector.mojo')
        for index in range(8):
            self.write('ordinary/noise' + str(index) + '.txt')
        reference, actual = self.equivalent(True)
        root = Path(self.root)
        supported = (os.name == 'posix' and type(root) is PosixPath
                     and type(getattr(root, '_raw_paths', None)) is list
                     and all(type(part) is str for part in root._raw_paths)
                     and all(part not in ('', '.', '..')
                             for part in str(root).split('/')[1:]))
        if supported:
            yields = sum(event[0] == 'yield' for event in actual[1])
            self.assertEqual(len(actual[2]), yields)
            self.assertGreater(len(reference[2]), len(actual[2]))
        else:
            self.assertEqual(actual[2], reference[2])
        self.assertTrue(any(event[0] == 'Path.is_file'
                            and event[1][1] == str(target) for event in actual[1]))
        target.unlink()
        self.write('math/vector.mojopkg')
        reference, actual = self.equivalent(False)
        if supported:
            self.assertLess(len(actual[2]), len(reference[2]))


if __name__ == '__main__':
    unittest.main()
