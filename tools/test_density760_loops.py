# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Bounded density successors through the real modeled receipt boundary."""
from pathlib import Path
import io
import json
import sys
import unittest
from unittest.mock import patch

import coverage_loop_proofs as loops
import test_coverage_loop_proofs as fixtures
import test_conditioned_coverage_loops as pending
from carla_lane_oracle import full_audit_cleanup_contracts as audit
from carla_lane_oracle import pr760_arithmetic_stage as stage

ROOT = Path(__file__).resolve().parents[1]
DENSITY = loops.DENSITY_SOURCE.removesuffix('.mojo')
STRANDS = 'extensions/humanoid/skeleton/head/hair/strands'


class Density760ReceiptTests(unittest.TestCase):
    traced = pending.GeneratedReceiptPendingControls.traced
    assert_closed = pending.GeneratedReceiptPendingControls.assert_closed
    derive = pending.GeneratedReceiptPendingControls.derive
    first_constant = pending.GeneratedReceiptPendingControls.first_constant

    def setUp(self):
        self.audit = audit
        self.fixture = fixtures.ProofBindingTests('test_escaped_source_identity_is_rejected')
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.setUp()
        build = self.fixture.root/'coverage/build'
        build.parent.mkdir(exist_ok=True)
        self.fixture.build.rename(build)
        self.fixture.build = build
        self.fixture.receipt = build/'loop-proofs.json'
        for name in (*loops.DENSITY760_INPUTS, STRANDS + '.mojo'):
            target = self.fixture.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT/name).read_bytes())
        for name in ('module.mojo', 'module.mojo.cov-origin'):
            (build/name).unlink()
        self.fixture.source.unlink()
        for module in (DENSITY, STRANDS):
            target = build/(module + '.mojo')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('compiler-free modeled density successor\n')
        self.manifest = ''.join(f'B {module} {line}\n' for module, rows in (
            (DENSITY, (100, 101, 131, 137, 138, 149, 167, 168, 178, 223, 245)),
            (STRANDS, (225, 229, 235))) for line in rows).encode()
        (build/'manifest.txt').write_bytes(self.manifest)
        self.regenerate()

    def regenerate(self):
        names = [DENSITY + '.mojo', STRANDS + '.mojo']
        loops.begin_generation(self.fixture.root, self.fixture.build,
                               'Mojo fixture', '-Werror', sources=names)
        fixtures.model_generation(self.fixture.root, self.fixture.build, names=names)

    def test_four_local_masks_keep_upload_empty_branch_and_runtime_true(self):
        with self.traced() as (_, owners):
            receipt = self.derive()
        self.assert_closed(owners, False)
        rows = {(p['module'], p['line']) for p in receipt['proofs']}
        self.assertEqual(rows, {(DENSITY, n) for n in (131, 167, 178, 245)}
                         | {(STRANDS, 229), (STRANDS, 235)})
        masked = loops.masked_manifest(self.manifest, {'receipt': receipt,
            'sha256': loops.sha256(loops.canonical(receipt))}).decode()
        self.assertIn(f'B {STRANDS} 225\n', masked)
        for n in (131, 167, 178, 245):
            self.assertIn(f'R {DENSITY} {n} T ', masked)
        self.assertEqual(receipt['denominator']['proven_impossible'], 6)

    def test_origins_are_include_only_exact_files_and_receipt_authenticated(self):
        root, build = self.fixture.root, self.fixture.build
        name = DENSITY + '.mojo.cov-origin'
        source = root/name
        origin = build/name
        raw = origin.read_bytes()
        expected = {131, 167, 178, 245}
        self.assertEqual(set(loops.density760_loops(root, include_roots=(build,))), expected)
        source.write_bytes(raw)
        try:
            for includes in ((), (build,), (root,), (root, build)):
                with self.subTest(source_sidecar=True, includes=includes):
                    self.assertEqual(loops.density760_loops(root, include_roots=includes), {})
        finally:
            source.unlink()
        for suffix in ('.extra', '.extra.more', '.cov-origin'):
            extra = build/(name + suffix)
            extra.write_bytes(raw)
            try:
                with self.subTest(extra=suffix):
                    self.assertEqual(loops.density760_loops(root, include_roots=(build,)), {})
            finally:
                extra.unlink()
        origin.unlink()
        try:
            origin.mkdir()
            self.assertEqual(loops.density760_loops(root, include_roots=(build,)), {})
            origin.rmdir()
            origin.symlink_to(root/(DENSITY + '.mojo'))
            self.assertEqual(loops.density760_loops(root, include_roots=(build,)), {})
        finally:
            if origin.is_symlink():
                origin.unlink()
            elif origin.is_dir():
                origin.rmdir()
            origin.write_bytes(raw)
        for fault in ('malformed', 'missing', 'extra'):
            extra = build/'unregistered.mojo.cov-origin'
            try:
                if fault == 'malformed':
                    origin.write_bytes(raw+b'corrupt')
                elif fault == 'missing':
                    origin.unlink()
                else:
                    extra.write_bytes(raw)
                with self.subTest(receipt_origin=fault), self.assertRaises(ValueError):
                    self.derive()
            finally:
                extra.unlink(missing_ok=True)
                origin.write_bytes(raw)
        self.assertEqual(set(loops.density760_loops(root, include_roots=(build,))), expected)
        receipt = self.derive()
        self.assertEqual(len([row for row in receipt['proofs'] if row['module'] == DENSITY]), 4)

    def test_standalone_historical_pairs_retain_exact_old_rows(self):
        density = self.fixture.root/loops.DENSITY_SOURCE
        groom_name = 'extensions/humanoid/skeleton/head/hair/groom.mojo'
        groom = self.fixture.root/groom_name
        density.write_text(stage.predecessor_source(loops.DENSITY_SOURCE, density.read_text()))
        groom.write_text(stage.predecessor_source(groom_name, groom.read_text()))
        self.assertEqual(set(loops.reviewed_nonempty_loops(self.fixture.root, DENSITY)),
                         {101, 138, 149, 223})
        before = loops.reviewed_density_source(self.fixture.root, successor=False)
        density.write_text(before)
        self.assertEqual(set(loops.reviewed_nonempty_loops(self.fixture.root, DENSITY)),
                         {100, 137})
        self.assertEqual(loops.repaired_density_loops(self.fixture.root), {})

    def test_mixed_groom_endpoint_and_changed_guard_withhold_density(self):
        groom = 'extensions/humanoid/skeleton/head/hair/groom.mojo'
        for path, convert in (
            (groom, lambda text: stage.predecessor_source(groom, text)),
            (loops.DENSITY_SOURCE, lambda text: text.replace('return 1\n', 'return 0\n')),
            ('math/finite.mojo', lambda text: text + '\n# changed provider\n')):
            target = self.fixture.root/path
            before = target.read_text()
            target.write_text(convert(before))
            self.regenerate()
            receipt = self.derive()
            self.assertFalse(any(p['module'] == DENSITY for p in receipt['proofs']))
            target.write_text(before)
            self.regenerate()

    def test_projected_provider_read_is_rejected_in_same_receipt(self):
        target = self.fixture.root/'math/finite.mojo'
        reviewed = target.read_bytes()
        target.write_bytes(reviewed + b'\n# different physical provider\n')
        self.regenerate()
        original = Path.read_bytes
        visits = []
        def projected(path):
            frame = sys._getframe(1)
            while frame:
                if frame.f_code is loops.density760_loops.__code__ and path == target:
                    visits.append(True)
                    return reviewed
                frame = frame.f_back
            return original(path)
        with patch.object(Path, 'read_bytes', projected), self.traced() as (_, owners):
            with self.assertRaises(ValueError):
                self.derive()
        self.assertTrue(visits)
        self.assert_closed(owners, True)

    def test_historical_hash_projection_cannot_emit_old_density_rows(self):
        target = self.fixture.root/loops.DENSITY_SOURCE
        historical = stage.predecessor_source(loops.DENSITY_SOURCE,
                                               target.read_text()).encode()
        self.assertEqual(loops.sha256(historical), loops.DENSITY_AFTER_SHA256)
        original = Path.open
        visits = []
        def projected(path, *args, **kwargs):
            frame = sys._getframe(1)
            while frame:
                if frame.f_code is loops.repaired_density_loops.__code__ and path == target:
                    visits.append(True)
                    return io.BytesIO(historical)
                frame = frame.f_back
            return original(path, *args, **kwargs)
        with patch.object(Path, 'open', projected), self.traced() as (_, owners):
            with self.assertRaises(ValueError):
                receipt = self.derive()
                self.assertIn((DENSITY, 149),
                    {(p['module'], p['line']) for p in receipt['proofs']})
        self.assertTrue(visits)
        self.assert_closed(owners, True)

    def test_live_inverse_function_and_defaults_cannot_be_substituted(self):
        original = stage.predecessor_source
        for replacement in (lambda path, text: text, lambda path, text, extra=None: original(path, text)):
            with patch.object(stage, 'predecessor_source', replacement), self.traced() as (_, owners):
                with self.assertRaises(ValueError):
                    self.derive()
            self.assert_closed(owners, True)

        # Replacing both a mutable table and its public digest must not let
        # unauthenticated provenance data pass the physical receipt boundary.
        changed = dict(stage.REGISTRY_INPUT_SHA256)
        changed[next(iter(changed))] = '0' * 64
        with patch.object(stage, 'REGISTRY_INPUT_SHA256', changed):
            payload = {name: getattr(stage, name) for name in stage.DATA_NAMES}
            replacement_digest = loops.sha256(json.dumps(
                payload, sort_keys=True, separators=(',', ':')).encode())
            with patch.object(stage, 'DATA_SHA256', replacement_digest), self.traced() as (_, owners):
                with self.assertRaises(ValueError):
                    self.derive()
            self.assert_closed(owners, True)
        # Restoration permits a fresh owner; it cannot revive the failed one.
        with self.traced() as (_, owners):
            receipt = self.derive()
        self.assert_closed(owners, False)
        self.assertEqual(len([p for p in receipt['proofs'] if p['module'] == DENSITY]), 4)

    def test_foreign_closed_and_changed_include_owner_rejected(self):
        for fault in ('root', 'include', 'public'):
            def misuse(owner):
                try:
                    operation = loops.reviewed_nonempty_loops if fault == 'public' else loops.density760_loops
                    positional = (self.fixture.root, DENSITY) if fault == 'public' else (self.fixture.root/'foreign' if fault == 'root' else self.fixture.root,)
                    operation(*positional,
                        include_roots=(self.fixture.build/'foreign',) if fault == 'include'
                            else (self.fixture.build,), _operation=owner)
                except ValueError:
                    pass
                self.assertTrue(owner._failed)
            fired, callback = self.first_constant(misuse)
            with self.traced(callback) as (_, owners):
                with self.assertRaises(ValueError):
                    self.derive()
            self.assertEqual(fired, [True])
            self.assert_closed(owners, True)
        with self.traced() as (_, owners):
            self.derive()
        with self.assertRaises(ValueError):
            loops.density760_loops(self.fixture.root, include_roots=(self.fixture.build,),
                                   _operation=owners[0])

    def test_mutation_restoration_after_consumed_read_is_sticky(self):
        target = self.fixture.root/'math/finite.mojo'
        raw = target.read_bytes()
        visits = []
        def mutate(frame, event, value, owners):
            if (not visits and event == 'return'
                    and frame.f_code is loops._density760_stage_identity.__code__):
                visits.append(True)
                target.write_bytes(raw + b'\n# transient\n')
                try:
                    loops._coverage_observe_bytes(self.fixture.root, 'math/finite.mojo',
                        target.read_bytes(), _operation=owners[0])
                except ValueError:
                    pass
                target.write_bytes(raw)
        with self.traced(mutate) as (_, owners):
            with self.assertRaises(ValueError):
                self.derive()
        self.assertEqual(target.read_bytes(), raw)
        self.assertEqual(visits, [True])
        self.assert_closed(owners, True)


if __name__ == '__main__':
    unittest.main()
