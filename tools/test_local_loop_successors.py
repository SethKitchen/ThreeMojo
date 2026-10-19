# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact local successors through compiler-free modeled producer receipts."""
from pathlib import Path
import sys
import io
import unittest
from unittest.mock import patch

import coverage_loop_proofs as loops
import test_coverage_loop_proofs as fixtures
import test_conditioned_coverage_loops as pending
from carla_lane_oracle import full_audit_cleanup_contracts as audit

ROOT = Path(__file__).resolve().parents[1]
CAP = 'renderers/renderer'
HAIR = 'extensions/humanoid/skeleton/head/hair/strands'


class LocalSuccessorReceiptTests(unittest.TestCase):
    traced = pending.GeneratedReceiptPendingControls.traced
    assert_closed = pending.GeneratedReceiptPendingControls.assert_closed
    derive = pending.GeneratedReceiptPendingControls.derive
    first_constant = pending.GeneratedReceiptPendingControls.first_constant

    def setUp(self):
        self.audit = audit
        self.fixture = fixtures.ProofBindingTests('test_escaped_source_identity_is_rejected')
        self.addCleanup(self.fixture.doCleanups)
        self.fixture.setUp()
        stage = self.fixture.root/'coverage/build'
        stage.parent.mkdir(exist_ok=True)
        self.fixture.build.rename(stage)
        self.fixture.build = stage
        self.fixture.receipt = stage/'loop-proofs.json'
        for name in (*loops.STRAND_CAP_SOURCES, HAIR + '.mojo'):
            target = self.fixture.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT/name).read_bytes())
        for name in ('module.mojo', 'module.mojo.cov-origin'):
            (self.fixture.build/name).unlink()
        self.fixture.source.unlink()
        for module in (CAP, HAIR):
            target = self.fixture.build/(module + '.mojo')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('compiler-free modeled instrumented local successor\n')
        self.manifest = ''.join(f'B {module} {line}\n' for module, lines in (
            (CAP, (3757, 3886, 4046, 4047, 4048, 4049, 4050)),
            (HAIR, (221, 225, 229, 231, 235, 236))) for line in lines).encode()
        (self.fixture.build/'manifest.txt').write_bytes(self.manifest)
        self.regenerate()

    def regenerate(self):
        names = [CAP + '.mojo', HAIR + '.mojo']
        loops.begin_generation(self.fixture.root, self.fixture.build,
                               'Mojo fixture', '-Werror', sources=names)
        fixtures.model_generation(self.fixture.root, self.fixture.build, names=names)

    def test_exact_receipt_masks_only_three_false_edges(self):
        with self.traced() as (counts, owners):
            receipt = self.derive()
        self.assertEqual(dict(counts), {})
        self.assert_closed(owners, False)
        self.assertEqual({(p['module'], p['line']) for p in receipt['proofs']},
                         {(CAP, 4049), (HAIR, 229), (HAIR, 235)})
        masked = loops.masked_manifest(self.manifest, {'receipt': receipt, 'sha256': loops.sha256(loops.canonical(receipt))}).decode()
        for module, line in ((CAP, 4049), (HAIR, 229), (HAIR, 235)):
            self.assertIn(f'R {module} {line} T ', masked)
            self.assertNotIn(f'B {module} {line}\n', masked)
        for module, line in ((CAP, 3757), (CAP, 3886), (CAP, 4046), (CAP, 4047), (CAP, 4048), (CAP, 4050),
                             (HAIR, 221), (HAIR, 225), (HAIR, 231), (HAIR, 236)):
            self.assertIn(f'B {module} {line}\n', masked)
        self.assertEqual(receipt['denominator']['proven_impossible'], 3)

    def test_projected_producer_bytes_cannot_escape_in_real_receipt(self):
        target = self.fixture.root/'objects/line_segments2.mojo'
        reviewed = target.read_bytes()
        changed = reviewed.replace(b'MIN_CAP_STEPS = 2', b'MIN_CAP_STEPS = 0')
        self.assertNotEqual(changed, reviewed)
        target.write_bytes(changed)
        self.regenerate()
        read = Path.open
        visits = []
        def projected(path, *args, **kwargs):
            frame = sys._getframe(1)
            in_cap = False
            while frame:
                in_cap |= frame.f_code is loops.strand_cap_loops.__code__
                frame = frame.f_back
            if path == target and in_cap:
                visits.append(True)
                return io.BytesIO(reviewed)
            return read(path, *args, **kwargs)
        with patch.object(Path, 'open', projected), self.traced() as (_, owners):
            with self.assertRaises(ValueError):
                receipt = self.derive()
                self.assertIn((CAP, 4049),
                              {(p['module'], p['line']) for p in receipt['proofs']})
        self.assertTrue(visits)
        self.assertEqual(target.read_bytes(), changed)
        self.assert_closed(owners, True)

    def test_foreign_include_and_public_owner_failures_are_sticky(self):
        for fault in ('root', 'include', 'public'):
            def misuse(owner):
                try:
                    if fault == 'public':
                        loops.reviewed_nonempty_loops(self.fixture.root, CAP,
                            include_roots=(self.fixture.build,), _operation=owner)
                    else:
                        loops.strand_cap_loops(
                            self.fixture.root/'foreign' if fault == 'root' else self.fixture.root,
                            include_roots=(self.fixture.build/'foreign',) if fault == 'include'
                                          else (self.fixture.build,), _operation=owner)
                except ValueError:
                    pass
                self.assertTrue(owner._failed)
            fired, callback = self.first_constant(misuse)
            with self.subTest(fault=fault), self.traced(callback) as (_, owners):
                with self.assertRaises(ValueError):
                    self.derive()
            self.assertEqual(fired, [True])
            self.assert_closed(owners, True)

    def test_closed_owner_cannot_be_reused(self):
        with self.traced() as (_, owners):
            self.derive()
        self.assert_closed(owners, False)
        with self.assertRaises(ValueError):
            loops.strand_cap_loops(self.fixture.root,
                include_roots=(self.fixture.build,), _operation=owners[0])
        self.assertEqual(loops.reviewed_nonempty_loops(self.fixture.root, HAIR,
            include_roots=(self.fixture.build,), _operation=owners[0]), {})

    def test_projected_physical_text_rejects_even_when_disk_is_restored(self):
        for module, before, after in ((CAP, 'range(1, steps + 1)', 'range(1, steps)'),
                                       (HAIR, 'range(2)', 'range(0)')):
            target = self.fixture.root/(module + '.mojo')
            raw, read, fired = target.read_bytes(), Path.read_text, []
            def changed(path, *args, **kwargs):
                if path == target and not fired:
                    fired.append(True)
                    target.write_bytes(raw.replace(before.encode(), after.encode()))
                    try:
                        return read(path, *args, **kwargs)
                    finally:
                        target.write_bytes(raw)
                return read(path, *args, **kwargs)
            with self.subTest(module=module), patch.object(Path, 'read_text', changed), self.traced() as (_, owners):
                with self.assertRaisesRegex(ValueError, 'consumed text differs'):
                    self.derive()
            self.assertEqual(fired, [True])
            self.assertEqual(target.read_bytes(), raw)
            self.assert_closed(owners, True)

    def test_transient_stream_mutation_is_sticky_after_restoration(self):
        target = self.fixture.root/'objects/line_segments2.mojo'
        raw, read, fired = target.read_bytes(), Path.open, []
        def changed(path, *args, **kwargs):
            frame = sys._getframe(1)
            in_cap = False
            while frame:
                in_cap |= frame.f_code is loops.strand_cap_loops.__code__
                frame = frame.f_back
            if path == target and in_cap and not fired:
                fired.append(True)
                mutant = raw.replace(b'MIN_CAP_STEPS = 2', b'MIN_CAP_STEPS = 0')
                target.write_bytes(mutant)
                try:
                    with read(path, *args, **kwargs) as stream:
                        consumed = stream.read()
                finally:
                    target.write_bytes(raw)
                return io.BytesIO(consumed)
            return read(path, *args, **kwargs)
        with patch.object(Path, 'open', changed), self.traced() as (_, owners):
            with self.assertRaises(ValueError):
                self.derive()
        self.assertEqual(fired, [True])
        self.assertEqual(target.read_bytes(), raw)
        self.assert_closed(owners, True)

    def test_include_shadow_added_after_rows_refuses_receipt(self):
        target = self.fixture.build/'std.mojopkg'
        fired = []
        def callback(frame, event, value, owners):
            if (not fired and event == 'return'
                    and frame.f_code is loops.strand_cap_loops.__code__):
                fired.append(True)
                target.write_bytes(b'unreviewed lookup shadow')
        try:
            with self.traced(callback) as (_, owners):
                with self.assertRaises(ValueError):
                    self.derive()
            self.assertEqual(fired, [True])
            self.assert_closed(owners, True)
        finally:
            target.unlink(missing_ok=True)


if __name__ == '__main__':
    unittest.main()
