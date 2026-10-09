# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Fail-closed controls for the exact pair-key successor and historical edge."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import seed_count_contracts as seed
import cache_key_contracts as cache
import lane_order_contracts as order
import source_contracts as source
import sum2_guard_contracts as guard
import optional_runtime_contracts as optional
import check_sampled_values as sampled

ROOT = Path(__file__).resolve().parents[2]


class CacheKeyContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Existing cache-only fixtures intentionally omit unrelated dependencies.
        # Construct their historical Map only after qualifying the real root.
        cls.map_fixture = (ROOT/seed.MODULE).read_bytes()
        if seed.sha(cls.map_fixture.decode()) == seed.SCORE_AFTER_SHA256:
            seed.verify_score(ROOT)
            cls.map_fixture = seed.score_predecessor_source(cls.map_fixture.decode()).encode()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cache-key-successor-')
        self.root = Path(self.temp.name)
        for rel in cache.PROTECTED_INPUTS:
            dst = self.root / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            if rel == seed.MODULE:
                dst.write_bytes(self.map_fixture)
            else:
                shutil.copyfile(ROOT / rel, dst)
        self.record = cache.verify(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def test_exact_reverse_preserves_all_bytes_and_old_pins(self):
        before = cache.predecessor_source(self.root)
        self.assertEqual(before, self.record['before'])
        self.assertEqual(hashlib.sha256(before.encode()).hexdigest(), cache.BEFORE_SHA256)
        self.assertEqual(source.token_sha256(before), cache.BEFORE_TOKEN_SHA256)
        self.assertEqual(source.token_sha256(self.record['after']), cache.AFTER_TOKEN_SHA256)
        self.assertEqual([e['name'] for e in self.record['edits']],
                         ['helper', 'cached_fast', 'cached_expansion'])
        for name, digest in self.record['preserved_records'].items():
            self.assertEqual(hashlib.sha256((self.root / 'tools/carla_lane_oracle' / name).read_bytes()).hexdigest(), digest)

    def test_complete_source_mutations_fail(self):
        path = self.root / cache.MODULE
        before = path.read_text()
        mutations = [
            ('comparison', '](station, scale) == SIMD', '](station, scale) != SIMD'),
            ('missing_scale', '](station, scale)', '](station, station)'),
            ('swapped_words', '](station, scale)', '](scale, station)'),
            ('wrong_type', 'station: UInt64, scale: UInt64', 'station: UInt32, scale: UInt64'),
            ('wrong_width', 'SIMD[DType.uint64, 2]', 'SIMD[DType.uint64, 4]'),
            ('wrong_station', 'cached_fast.value()[0],', 'cached_fast.value()[1],'),
            ('wrong_scale', 'cached_expansion.value()[1],', 'cached_expansion.value()[0],'),
            ('wrong_call_site', 'and _same_cache_key(', 'and wrong_key('),
            ('optional_guard', 'and cached_fast\n', 'and True\n'),
            ('external_guard', 'external_witness\n                        and cached_fast', 'True\n                        and cached_fast'),
            ('memo_lifetime', 'var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]] = None', 'var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]] = saved'),
            ('memo_order', 'cached_fast = (\n                                station_word,\n                                scale_word,', 'cached_fast = (\n                                scale_word,\n                                station_word,'),
            ('ledger', 'certificate.terms += work', 'certificate.terms += 0'),
            ('guard', 'if task[2] >= max_depth:', 'if task[2] > max_depth:'),
            ('unrelated', 'var best = certificate.s', 'var best = low'),
        ]
        for name, old, new in mutations:
            with self.subTest(name=name):
                self.assertIn(old, before)
                path.write_text(before.replace(old, new, 1))
                with self.assertRaises(cache.ContractError):
                    cache.verify(self.root)
                path.write_text(before)
        for extra in (
            '\ndef unexpected():\n    return _same_cache_key(1, 2, 1, 2)\n',
            '\nalias hidden_key = _same_cache_key\n',
            '\ndef _same_cache_key(a: UInt64) -> Bool:\n    return True\n',
            '\nfrom elsewhere import SIMD\n',
        ):
            with self.subTest(extra=extra):
                path.write_text(before + extra)
                with self.assertRaises(cache.ContractError):
                    cache.verify(self.root)
                path.write_text(before)

    def test_inert_comments_and_newlines_preserve_general_gate_compatibility(self):
        path = self.root / cache.MODULE
        adopted = path.read_bytes()
        path.write_bytes(b'# inert cache-key comment\r\n' + adopted.replace(b'\n', b'\r\n'))
        cache.verify(self.root)
        self.assertEqual(cache.predecessor_source(self.root), self.record['before'])
        # The adoption receipt itself still reconstructs exact original bytes.
        with self.assertRaises(cache.ContractError):
            cache.reverse_exact(path.read_text(), self.record)

    def test_missing_and_swapped_components_fail(self):
        names = list(self.record['preserved_records'])
        path = self.root / 'tools/carla_lane_oracle' / names[0]
        saved = path.read_bytes()
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            cache.verify(self.root)
        path.write_bytes((self.root / 'tools/carla_lane_oracle' / names[1]).read_bytes())
        with self.assertRaises(cache.ContractError):
            cache.verify(self.root)
        path.write_bytes(saved)
        migration = self.root / cache.MIGRATION
        migration.write_text(migration.read_text().replace('cached_fast', 'cached_wrong', 1))
        with self.assertRaises(cache.ContractError):
            cache.verify(self.root)

    def test_reverse_requires_exact_complete_delta_set(self):
        for change in ('remove', 'swap', 'wrong_before', 'extra'):
            record = json.loads(json.dumps(self.record))
            if change == 'remove': record['edits'].pop()
            elif change == 'swap': record['edits'][1], record['edits'][2] = record['edits'][2], record['edits'][1]
            elif change == 'wrong_before': record['edits'][1]['before'] = ''
            else: record['edits'].append(record['edits'][1])
            with self.subTest(change=change), self.assertRaises(cache.ContractError):
                cache.reverse_exact(record['after'], record)

    def test_production_inventory_rejects_new_callers_aliases_and_reexports(self):
        path = self.root / 'new_namespace/nested/__init__.mojo'
        path.parent.mkdir(parents=True)
        for text in (
            'from extensions.carla.lane_refinement import _same_cache_key as concealed\n',
            'import extensions.carla.lane_refinement as concealed\n',
            'from extensions.carla.lane_refinement import *\n',
            'def copied() -> Bool:\n    return _same_cache_key(1, 2, 1, 2)\n',
            'def _same_cache_key(a: UInt64) -> Bool:\n    return True\n',
        ):
            with self.subTest(text=text):
                path.write_text(text)
                with self.assertRaisesRegex(cache.ContractError, 'inventory'):
                    cache.verify(self.root)
        path.write_text('# _same_cache_key is an inert comment\n')
        cache.verify(self.root)
        # Existing production inventory entries cannot be dropped either.
        (self.root / 'extensions/carla/lane_box_cover.mojo').unlink()
        with self.assertRaisesRegex(cache.ContractError, 'inventory'):
            cache.verify(self.root)

    def test_no_projection_for_other_paths_or_unknown_lane_changes(self):
        text = 'def unrelated():\n    pass\n'
        self.assertEqual(cache.reviewed_text(self.root, 'other.mojo', text), text)
        with self.assertRaises(cache.ContractError):
            cache.reviewed_text(self.root, cache.MODULE, text)
        path = self.root / cache.MODULE
        path.write_text(path.read_text() + '\ndef unreviewed():\n    pass\n')
        with self.assertRaises(cache.ContractError):
            cache.reviewed_text(self.root, cache.MODULE, path.read_text())

    def test_live_optional_helper_comparison_mutations(self):
        helper = guard.declaration(self.record['after'], '_same_cache_key')
        for old, new in [('==', '!='), ('station, scale)', 'station, station)'),
                         ('other_station, other_scale', 'other_scale, other_station')]:
            modified = helper.replace(old, new, 1)
            node = sampled.unique_function(sampled.syntax_tree(modified), '_same_cache_key')
            original_body = optional.body
            def mocked(root, module, name):
                if (module, name) == ('lane_refinement', '_same_cache_key'):
                    return node
                return original_body(root, module, name)
            with patch.object(optional, 'body', side_effect=mocked):
                with self.assertRaisesRegex(ValueError, 'exact UInt64 pair helper comparison'):
                    optional.verify_semantics(ROOT)

    def test_historical_scalar_memo_mutations_remain_checked(self):
        # The predecessor retains the four original station/scale obligations.
        # Keep those controls in addition to the new actual-helper mutations.
        before = self.record['before']
        original = guard.declaration(before, '_run_lane_search')
        def node(text):
            # Use the same move-token adapter as production semantics.
            class File:
                def read_text(self): return text
            class Root:
                def __truediv__(self, unused): return File()
            return optional.body(Root(), 'lane_refinement', '_run_lane_search')
        fast = optional.FAST_MEMO.replace('_same_cache_key(cached_fast.value()[0], cached_fast.value()[1], station_word, scale_word)', 'cached_fast.value()[0] == station_word and cached_fast.value()[1] == scale_word')
        expansion = optional.EXPANSION_MEMO.replace('_same_cache_key(cached_expansion.value()[0], cached_expansion.value()[1], station_word, scale_word)', 'cached_expansion.value()[0] == station_word and cached_expansion.value()[1] == scale_word')
        with patch.object(optional, 'FAST_MEMO', fast), patch.object(optional, 'EXPANSION_MEMO', expansion):
            optional.verify_fresh_producer(node(original))
            for name in ('cached_fast', 'cached_expansion'):
                for old, new in ((f'{name}.value()[0] == station_word', f'{name}.value()[0] <= station_word'),
                                 (f'{name}.value()[1] == scale_word', 'True')):
                    with self.subTest(old=old), self.assertRaisesRegex(ValueError, 'exact station/scale'):
                        optional.verify_fresh_producer(node(original.replace(old, new, 1)))


class ScoreHelperCacheInventoryTests(unittest.TestCase):
    def test_physical_score_inventory_corresponds_only_after_verification(self):
        text = (ROOT/seed.MODULE).read_bytes().decode()
        if seed.sha(text) != seed.SCORE_AFTER_SHA256:
            self.skipTest('physical source is an earlier reviewed endpoint')
        previous = seed.score_predecessor_source(text)
        self.assertNotEqual(cache.inventory_entry(text), cache.inventory_entry(previous))
        self.assertEqual(cache.inventory(ROOT)[seed.MODULE], cache.inventory_entry(previous))
        with patch.object(seed, 'verify_score', side_effect=ValueError('unqualified score')):
            with self.assertRaisesRegex(ValueError, 'unqualified score'): cache.inventory(ROOT)
        read = Path.read_bytes
        with patch.object(Path, 'read_bytes', lambda path,*a,**k:
                          previous.encode() if path == ROOT/seed.MODULE else read(path,*a,**k)):
            with self.assertRaises(ValueError): cache.inventory(ROOT)


    def test_inventory_comments_preserve_views_but_semantic_tokens_reject(self):
        target = ROOT/seed.MODULE
        physical = target.read_bytes().decode('utf-8')
        if seed.sha(physical) != seed.SCORE_AFTER_SHA256:
            self.skipTest('physical source is an earlier reviewed endpoint')
        previous = seed.score_predecessor_source(physical)
        read = Path.read_text
        for consumer in (cache, order):
            expected = consumer.inventory_entry(previous)
            with self.subTest(consumer=consumer.__name__, view='comments'), patch.object(
                    Path, 'read_text', lambda path,*a,**k:
                    physical+'\n# Benign score view commentary.\n' if path == target else read(path,*a,**k)):
                self.assertEqual(consumer.inventory(ROOT)[seed.MODULE], expected)
            for old, new in (('return (True, score.high)', 'return (True, score.low)'),
                             ('if update[0]:', 'if not update[0]:')):
                self.assertIn(old, physical)
                changed = physical.replace(old, new, 1)
                with self.subTest(consumer=consumer.__name__, mutation=old), patch.object(
                        Path, 'read_text', lambda path,*a,**k:
                        changed if path == target else read(path,*a,**k)):
                    with self.assertRaisesRegex((ValueError, RuntimeError), 'supplied score-helper'):
                        consumer.inventory(ROOT)

    def test_unknown_physical_and_between_read_changes_still_reject(self):
        target = ROOT/seed.MODULE
        physical = target.read_bytes()
        if seed.sha(physical.decode('utf-8')) != seed.SCORE_AFTER_SHA256:
            self.skipTest('physical source is an earlier reviewed endpoint')
        read_bytes, read_text = Path.read_bytes, Path.read_text
        prior = seed.score_predecessor_source(physical.decode('utf-8')).encode('utf-8')
        for consumer in (cache, order):
            for unknown in (prior, physical+b'\n# Unknown physical Map.\n'):
                with self.subTest(consumer=consumer.__name__, physical=seed.sha(unknown.decode())), \
                     patch.object(Path, 'read_bytes', lambda path,*a,**k:
                                  unknown if path == target else read_bytes(path,*a,**k)), \
                     patch.object(Path, 'read_text', lambda path,*a,**k:
                                  physical.decode()+'\n# Benign view.\n' if path == target else read_text(path,*a,**k)):
                    with self.assertRaisesRegex((ValueError, RuntimeError), 'exact physical Map'):
                        consumer.inventory(ROOT)
            changed = False
            real_verify = seed.verify_score
            def verify_then_change(root):
                nonlocal changed
                result = real_verify(root)
                changed = True
                return result
            with self.subTest(consumer=consumer.__name__, phase='after verification'), \
                 patch.object(seed, 'verify_score', side_effect=verify_then_change), \
                 patch.object(Path, 'read_bytes', lambda path,*a,**k:
                              physical+b'\n# Changed during check.\n' if path == target and changed else read_bytes(path,*a,**k)):
                with self.assertRaisesRegex((ValueError, RuntimeError), 'Map changed during score-helper'):
                    consumer.inventory(ROOT)


if __name__ == '__main__':
    unittest.main()
