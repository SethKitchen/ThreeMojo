# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact physical-image and public successor controls."""
import ast
import copy
import io
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

import full_audit_cleanup_contracts as owner
import pr760_arithmetic_stage as stage

ROOT = Path(__file__).resolve().parents[2]


class ClosedPhysicalImageControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='pr760-physical-')
        cls.root = Path(cls.temporary.name)/'source'
        cls.root.mkdir()
        data = json.loads((ROOT/owner.PR760_IMAGE).read_bytes())
        paths = set(data['inputs']) | set(owner.CHECKER_PATHS) | set(owner.DEPENDENCY_TOOL_SHA256)
        paths |= {owner.PR760_IMAGE, owner.PR760_OWNER_PREDECESSOR, owner.MIGRATION}
        # Include every preserved qualification input used by the public gate,
        # not only the private candidate's narrower native image.
        cls.qualification_bindings = owner.proof_bindings(ROOT)
        paths.update(cls.qualification_bindings)
        paths |= {p.as_posix() for p in owner._sibling('cache_key').input_paths(ROOT)
                  if p.suffix == '.mojo'}
        for path in paths:
            target = cls.root/path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT/path, target)
        for path, digest in cls.qualification_bindings.items():
            if (ROOT/path).is_file():
                if hashlib.sha256((cls.root/path).read_bytes()).hexdigest() != digest:
                    raise AssertionError('qualification fixture copy differs: ' + path)
        cls.data = data
        cls.accepted = owner._pr760_candidate_bindings(cls.root)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    @contextmanager
    def changed(self, path, raw):
        target = self.root/path
        before = target.read_bytes()
        try:
            target.write_bytes(raw)
            yield
        finally:
            target.write_bytes(before)

    def test_current_complete_image_retains_physical_digests(self):
        self.assertFalse(self.accepted['public_admission'])
        self.assertEqual(self.accepted['image'], 'pr760-closed-candidate')
        self.assertEqual({name:len(paths) for name,paths in self.accepted['closures'].items()},
                         {'PRODUCTION_CLOSURE':77, 'NATIVE_CLOSURE':105,
                          'TYPED_PRODUCTION_CLOSURE':369, 'TYPED_NATIVE_CLOSURE':769,
                          'EXAMPLE_CLOSURE':333})
        for path, expected in self.data['inputs'].items():
            self.assertEqual(self.accepted['bindings'][path], expected)
        for path in owner.CHECKER_PATHS:
            self.assertEqual(self.accepted['bindings'][path], hashlib.sha256((self.root/path).read_bytes()).hexdigest())
        xml = 'loaders/xml.mojo'
        edge = self.accepted['shared_edges'][xml]
        self.assertEqual(edge['before_sha256'], owner.shared_helpers.BEFORE_SHA256[xml])
        self.assertEqual(edge['after_sha256'], hashlib.sha256((self.root/xml).read_bytes()).hexdigest())
        self.assertNotEqual(edge['after_sha256'], owner.shared_helpers.AFTER_SHA256[xml])

    def test_public_gate_admits_only_the_complete_current_image(self):
        owner.verify(self.root, exact=True)
        for path in ('examples/carla.mojo', 'math/norm.mojo', 'render/apng.mojo', 'generators/utils.mojo'):
            with self.subTest(path=path), self.changed(path, self.accepted['predecessors'][path].encode()):
                with self.assertRaises(owner.ContractError):
                    owner.verify(self.root, exact=True)

    def test_public_projection_and_composed_provenance_keep_physical_edges(self):
        import source_contracts
        for path in ('math/norm.mojo', 'loaders/xml.mojo', 'examples/carla.mojo'):
            raw = (self.root/path).read_bytes()
            prior = source_contracts.historical_bytes(self.root, path, raw)
            expected = owner.typed_boundary.historical_source(path, self.accepted['predecessors'][path])
            self.assertEqual(prior.decode(), expected)
            self.assertEqual((self.root/path).read_bytes(), raw)
        for leaf in (owner.shared_helpers, owner.scaled_float32):
            bindings = {p: owner.sha((self.root/p).read_bytes()) for p in leaf.SOURCE_PATHS}
            edges = owner._pr760_composed_edges(leaf, bindings)
            for path, edge in edges.items():
                self.assertEqual(edge['after_sha256'], bindings[path])
                self.assertEqual(owner.provenance_after_sha256(edge), leaf.AFTER_SHA256[path])
                if path not in stage.CARLA_REGISTRY_PATHS:
                    continue
                for key, value in (('provenance_after_sha256', '0'*64),
                                   ('after_sha256', leaf.AFTER_SHA256[path]),
                                   ('after_token_sha256', '0'*64),
                                   ('before_sha256', '0'*64),
                                   ('path', 'unregistered.mojo')):
                    bad = {**edge, key:value}
                    with self.subTest(path=path,key=key), self.assertRaises(owner.ContractError):
                        owner.provenance_after_sha256(bad)
                old = leaf.edges((path,))[path]
                self.assertEqual(owner.provenance_after_sha256(old), old['after_sha256'])
                with self.assertRaises(owner.ContractError):
                    owner.provenance_after_sha256({**old, 'provenance_after_sha256':old['after_sha256']})
        raw = b'not a registered source'
        self.assertIs(source_contracts.historical_bytes(self.root, 'unregistered.mojo', raw), raw)
        self.assertIs(source_contracts.historical_bytes(self.root,
            'extensions/humanoid/skeleton/head/hair/density.mojo', raw), raw)
        with patch.object(source_contracts, 'historical_text', lambda *args,**kwargs: 'forged'):
            with self.assertRaises(owner.ContractError):
                owner.verify(self.root, exact=True)

    def test_bulk_public_projection_uses_one_complete_physical_image(self):
        paths = ('math/norm.mojo', 'loaders/xml.mojo', 'examples/carla.mojo')
        texts = {path: (self.root/path).read_text() for path in paths}
        expected = {path: owner.typed_boundary.historical_source(path,
                    self.accepted['predecessors'][path]) for path in paths}
        self.assertEqual(owner.reviewed_sources(self.root, texts), expected)
        with self.changed('examples/carla.mojo', self.accepted['predecessors']['examples/carla.mojo'].encode()):
            with self.assertRaises(owner.ContractError):
                owner.reviewed_sources(self.root, texts)
        for path in paths:
            mixed = {**texts, path: self.accepted['predecessors'][path]}
            with self.subTest(path=path), self.assertRaises(owner.ContractError):
                owner.reviewed_sources(self.root, mixed)

    def test_historical_minimal_helper_roots_and_current_partial_refusal(self):
        leaf = owner.scaled_float32
        with tempfile.TemporaryDirectory(prefix='pr760-legacy-') as directory:
            root = Path(directory)
            expected = {**leaf.PACKAGE_INPUTS, **leaf.PROVIDER_INPUTS, **leaf.TESTS,
                        **leaf.AFTER_SHA256, leaf.LEAF:owner.DEPENDENCY_TOOL_SHA256[leaf.LEAF]}
            for path, digest in expected.items():
                raw = ((self.accepted['predecessors'][path]).encode()
                       if path in self.accepted['predecessors'] else (self.root/path).read_bytes())
                if path == 'tools/carla_lane_oracle/test_scaled_float32_contracts.py':
                    raw = owner.qualification_predecessor_bytes(path, raw)
                self.assertEqual(owner.sha(raw), digest)
                target = root/path; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(raw)
            result = owner.scaled_float32_proof_bindings(root)
            self.assertEqual({p:result[p] for p in leaf.SOURCE_PATHS}, leaf.AFTER_SHA256)
            target = leaf.SOURCE_PATHS[0]
            (root/target).write_bytes((self.root/target).read_bytes())
            with self.assertRaises((owner.ContractError,OSError)):
                owner.scaled_float32_proof_bindings(root)
            for path in stage.EXAMPLE_PATHS[:1]:
                (root/path).parent.mkdir(parents=True,exist_ok=True)
                (root/path).write_bytes((self.root/path).read_bytes())
            with self.assertRaises((owner.ContractError,OSError)):
                owner.scaled_float32_proof_bindings(root)
            for path in stage.EXAMPLE_PATHS[1:]:
                (root/path).write_bytes((self.root/path).read_bytes())
            with self.assertRaises((owner.ContractError,OSError)):
                owner.scaled_float32_proof_bindings(root)

    def test_qualification_witnesses_keep_exact_physical_and_historical_images(self):
        rows = self.data['qualification_successors']
        paths = {
            'tools/test_conditioned_coverage_loops.py',
            'tools/carla_lane_oracle/test_common758_current_successor.py',
            'tools/carla_lane_oracle/test_typed_boundary_contracts.py',
            'tools/carla_lane_oracle/test_shared_helper_contracts.py',
            'tools/carla_lane_oracle/test_scaled_float32_contracts.py',
        }
        self.assertEqual(set(rows), paths)
        for path, row in rows.items():
            raw = (self.root/path).read_bytes()
            old = (self.root/row['predecessor_archive']).read_bytes()
            self.assertEqual(owner.sha(raw), row['after_sha256'])
            self.assertEqual(owner.sha(old), row['before_sha256'])
            self.assertEqual(owner.qualification_predecessor_bytes(path, raw), old)
            self.assertEqual(owner.qualification_predecessor_bytes(path, old), old)
            with self.subTest(path=path), self.changed(path, old):
                with self.assertRaises(owner.ContractError):
                    owner.verify(self.root, exact=True)
            with self.assertRaises(owner.ContractError):
                owner.qualification_predecessor_bytes(path, raw+b'\n')
        path = next(iter(rows))
        archive = rows[path]['predecessor_archive']
        with self.changed(archive, (self.root/archive).read_bytes()+b'\n'):
            with self.assertRaises(owner.ContractError):
                owner.verify(self.root, exact=True)
        target = self.root/archive
        moved = target.with_suffix('.missing')
        target.rename(moved)
        try:
            with self.assertRaises(owner.ContractError):
                owner.verify(self.root, exact=True)
        finally:
            moved.rename(target)
        with self.assertRaises(owner.ContractError):
            owner.qualification_predecessor_bytes('tools/unregistered.py', b'pass\n')
        owner.verify(self.root, exact=True)

    def test_qualification_inverse_literals_and_builtin_inputs_are_authenticated(self):
        path = 'tools/test_conditioned_coverage_loops.py'
        raw = (self.root/path).read_bytes()
        class Bytes(bytes):
            pass
        for value in (Bytes(raw), raw.decode('utf-8')):
            with self.assertRaises(owner.ContractError):
                owner.qualification_predecessor_bytes(path, value)
        function = owner.qualification_predecessor_bytes
        original = function.__code__
        constants = list(original.co_consts)
        index = next(index for index, value in enumerate(constants)
                     if type(value) is tuple and len(value) == 3
                     and type(value[0]) is str and len(value[0]) == 64)
        before, after, edits = constants[index]
        start, stop, old, new = edits[0]
        constants[index] = (before, after, ((start, stop, old, (*new, '# changed span\n')), *edits[1:]))
        try:
            function.__code__ = original.replace(co_consts=tuple(constants))
            with self.assertRaisesRegex(owner.ContractError, 'executing function changed'):
                owner._pr760_candidate_bindings(self.root)
        finally:
            function.__code__ = original
        owner._pr760_candidate_bindings(self.root)

    def test_mutation_after_candidate_before_publication_is_refused(self):
        original = Path.read_bytes
        watched = self.root/'core/ordinal.mojo'
        before = watched.read_bytes()
        added = self.root/'examples/pr760_late_entry.mojo'
        for kind in ('bytes','path','entry'):
            changed = False
            def read(path):
                nonlocal changed
                frame = sys._getframe(1)
                while frame is not None and not (frame.f_code is owner.verify.__code__
                        and frame.f_globals is vars(owner)):
                    frame = frame.f_back
                if (not changed and frame is not None and frame.f_locals.get('pr760')
                        and path == self.root/'math/scaled_products.mojo'):
                    changed = True
                    if kind == 'bytes': watched.write_bytes(before+b'\n')
                    elif kind == 'path': added.write_text('# late source\n')
                    else: watched.write_bytes(before+b'\ndef main():\n    pass\n')
                return original(path)
            try:
                with patch.object(Path, 'read_bytes', read), self.assertRaises(owner.ContractError):
                    owner.verify(self.root,exact=True)
                self.assertTrue(changed)
            finally:
                watched.write_bytes(before)
                if added.exists(): added.unlink()
        owner.verify(self.root,exact=True)

    def test_old_or_mixed_source_refused(self):
        for path in ('examples/carla.mojo', 'math/norm.mojo', 'render/apng.mojo', 'generators/utils.mojo'):
            with self.subTest(path=path), self.changed(path, self.accepted['predecessors'][path].encode()):
                with self.assertRaises(owner.ContractError):
                    owner._pr760_candidate_bindings(self.root)

    def test_provider_and_manifest_mutations_refused(self):
        for path in ('core/ordinal.mojo', 'units/measure.mojo', owner.PR760_IMAGE,
                     owner.PR760_OWNER_PREDECESSOR):
            with self.subTest(path=path), self.changed(path, (self.root/path).read_bytes()+b'\n'):
                with self.assertRaises(owner.ContractError):
                    owner._pr760_candidate_bindings(self.root)

    def test_missing_or_alternate_helper_refused(self):
        target = self.root/'math/polyline.mojo'
        moved = target.with_suffix('.missing')
        target.rename(moved)
        try:
            with self.assertRaises(owner.ContractError):
                owner._pr760_candidate_bindings(self.root)
        finally:
            moved.rename(target)
        alternate = target.with_suffix('.py')
        alternate.write_text('# competing module\n')
        try:
            with self.assertRaises(owner.ContractError):
                owner._pr760_candidate_bindings(self.root)
        finally:
            alternate.unlink()

    def test_projected_snapshot_and_wrong_owner_refused(self):
        path='loaders/xml.mojo'
        with self.assertRaises(owner.ContractError):
            owner._pr760_candidate_bindings(self.root,
                _snapshots={path:self.accepted['predecessors'][path].encode()})
        with self.assertRaises(owner.ContractError):
            owner._pr760_candidate_bindings(self.root, _operation=object())
        alias=self.root.parent/'alias'
        alias.symlink_to(self.root, target_is_directory=True)
        try:
            with self.assertRaises(owner.ContractError):
                owner._pr760_candidate_bindings(alias)
        finally:
            alias.unlink()

    def test_late_physical_change_fails_and_fresh_restoration_rechecks(self):
        target=self.root/'math/norm.mojo';before=target.read_bytes()
        read=Path.read_bytes;count=0
        def changing(path):
            nonlocal count
            result=read(path)
            if path == target:
                count += 1
                if count == 3:
                    target.write_bytes(before+b'\n')
            return result
        try:
            with patch.object(Path, 'read_bytes', changing):
                with self.assertRaises(owner.ContractError):
                    owner._pr760_candidate_bindings(self.root)
            self.assertGreaterEqual(count, 3)
        finally:
            target.write_bytes(before)
        restored=owner._pr760_candidate_bindings(self.root)
        self.assertEqual(restored['bindings'][target.relative_to(self.root).as_posix()],
                         hashlib.sha256(before).hexdigest())

    def test_coordinated_digest_and_selector_replacement_refused(self):
        edges=copy.deepcopy(stage.EDGES)
        edges['math/norm.mojo']['after_sha256']='0'*64
        payload={name:edges if name=='EDGES' else getattr(stage,name) for name in stage.DATA_NAMES}
        digest=hashlib.sha256(json.dumps(payload,sort_keys=True,separators=(',', ':')).encode()).hexdigest()
        with patch.object(stage,'EDGES',edges),patch.object(stage,'DATA_SHA256',digest):
            with self.assertRaises(owner.ContractError):
                owner._pr760_candidate_bindings(self.root)
        changed=(self.root/owner.PR760_IMAGE).read_bytes()+b'\n'
        with self.changed(owner.PR760_IMAGE,changed),patch.object(owner,'PR760_IMAGE_SHA256',hashlib.sha256(changed).hexdigest()):
            with self.assertRaises(owner.ContractError):
                owner._pr760_candidate_bindings(self.root)
        for name in ('PR760_IMAGE','PR760_STAGE_SHA256','PR760_OWNER_PREDECESSOR'):
            with patch.object(owner,name,'unreviewed'),self.assertRaises(owner.ContractError):
                owner._pr760_candidate_bindings(self.root)

    def test_caller_specific_projected_bytes_and_open_stream_refused(self):
        target=self.root/'math/norm.mojo'
        projected=self.accepted['predecessors']['math/norm.mojo'].encode()
        read=Path.read_bytes
        opened=Path.open
        for mode in ('read_bytes','open'):
            seen=[]
            def intercept(path,*args,**kwargs):
                frame=sys._getframe(1)
                while frame is not None:
                    if frame.f_code is owner.dependency_inventory.__code__:
                        break
                    frame=frame.f_back
                if path==target and frame is not None:
                    seen.append(path)
                    return projected if mode=='read_bytes' else io.BytesIO(projected)
                return (read if mode=='read_bytes' else opened)(path,*args,**kwargs)
            with self.subTest(mode=mode),patch.object(Path,mode,intercept):
                with self.assertRaises(owner.ContractError):
                    owner._pr760_candidate_bindings(self.root)
            self.assertTrue(seen)

    def test_scoped_example_namespaces_keep_default_and_exact_shadow_guards(self):
        paths=set().union(*self.accepted['closures'].values())
        entries=owner.read_record(self.root)['entry_directories']
        lookup=owner._render_lookup_args(paths,entries)
        lookup['math_entries']=frozenset(('.',*entries,'tests'))
        inert=self.root/'assets/carla/tools'
        inert.mkdir(parents=True,exist_ok=True)
        self.assertFalse(owner.resolver_unshadowed(self.root,paths,**lookup))
        lookup['example_entries']=lookup['math_entries']
        self.assertTrue(owner.resolver_unshadowed(self.root,paths,**lookup))
        for family in ('examples','tools','generators'):
            for name in (family+'.mojo',family.upper()+'.mojo',family+'.mojopkg',family+'/__init__.mojo'):
                path=self.root/'examples'/name
                self.assertFalse(path.exists())
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_text('# competing lookup surface\n')
                try:
                    with self.subTest(name=name):
                        self.assertFalse(owner.resolver_unshadowed(self.root,paths,**lookup))
                finally:
                    path.unlink()
                    if '/' in name:
                        path.parent.rmdir()
        inert=self.root/'assets/carla/tools'
        inert.mkdir(parents=True,exist_ok=True)
        self.assertTrue(owner.resolver_unshadowed(self.root,paths,**lookup))
        entry=inert.parent/'new_entry.mojo'
        entry.write_text('def main():\n    pass\n')
        try:
            with self.assertRaises(owner.ContractError):
                owner._pr760_candidate_bindings(self.root)
        finally:
            entry.unlink()

    def test_real_runtime_owner_failure_is_sticky_and_closed_owner_cannot_reuse(self):
        import check_runtime_support as runtime
        read=Path.read_text
        captured=[]
        entering=False
        def intercept(path,*args,**kwargs):
            nonlocal entering
            if not entering:
                frame=sys._getframe(1)
                while frame is not None:
                    if frame.f_globals is vars(runtime) and frame.f_locals.get('_operation') is not None:
                        operation=frame.f_locals['_operation']
                        entering=True
                        captured.append(operation)
                        accepted=owner._pr760_candidate_bindings(self.root,_operation=operation)
                        self.assertFalse(accepted['public_admission'])
                        with self.assertRaises(owner.ContractError):
                            owner._pr760_candidate_bindings(self.root.parent,_operation=operation)
                        self.assertTrue(operation._failed)
                        with self.assertRaises(owner.ContractError):
                            owner._pr760_candidate_bindings(self.root,_operation=operation)
                        raise owner.ContractError('test closes the refused real runtime invocation')
                    frame=frame.f_back
            return read(path,*args,**kwargs)
        with patch.object(Path,'read_text',intercept),self.assertRaises((ValueError,OSError)):
            runtime.verify(self.root)
        self.assertEqual(len(captured),1)
        self.assertEqual(captured[0]._state,'closed')
        with self.assertRaises(owner.ContractError):
            owner._pr760_candidate_bindings(self.root,_operation=captured[0])

    def test_executing_leaf_function_and_data_replacements_refused(self):
        with patch.object(stage, '_predecessor_source', lambda *args: ''):
            with self.assertRaises(owner.ContractError):
                owner._pr760_candidate_bindings(self.root)
        with patch.object(stage, 'DATA_SHA256', '0'*64):
            with self.assertRaises(owner.ContractError):
                owner._pr760_candidate_bindings(self.root)


if __name__ == '__main__':
    unittest.main()
