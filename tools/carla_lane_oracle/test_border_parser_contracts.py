# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Retain both exact parser states and reject altered successor authority."""
from copy import deepcopy
import hashlib
from pathlib import Path
import unittest
from unittest.mock import patch

import border_parser_contracts as border

ROOT = Path(__file__).resolve().parents[2]


class BorderParserSuccessorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.record = border.read_record(ROOT)
        cls.after = border.successor_source(ROOT)
        cls.before = border.predecessor_source(cls.after, cls.record)

    def test_both_exact_source_relations_and_actual_root(self):
        self.assertIsNone(border.verify_source(self.before, self.record))
        edge = border.verify_source(self.after, self.record)
        self.assertEqual(edge['path'], border.MODULE)
        self.assertEqual(edge['before_sha256'], border.BEFORE_SHA256)
        self.assertEqual(edge['after_sha256'], border.AFTER_SHA256)
        result = border.verify(ROOT)
        current = border.sha((ROOT/border.MODULE).read_text())
        self.assertIn(current, (border.BEFORE_SHA256, border.AFTER_SHA256))
        self.assertEqual(result, edge if current == border.AFTER_SHA256 else None)

    def test_forward_fixture_and_exact_inverse_preserve_whole_predecessor(self):
        self.assertEqual(border.sha(self.before), border.BEFORE_SHA256)
        self.assertEqual(border.sha(self.after), border.AFTER_SHA256)
        self.assertEqual(tuple(x['name'] for x in self.record['edits']), border.EDIT_NAMES)
        value = self.before
        for edit in self.record['edits']:
            self.assertEqual(value.count(edit['before']), 1)
            value = value.replace(edit['before'], edit['after'], 1)
        self.assertEqual(value, self.after)
        self.assertNotIn('before_complete_module', self.record)
        self.assertNotIn('after_complete_module', self.record)

    def test_missing_duplicate_reordered_and_extra_inverse_spans_reject(self):
        cases = [self.record['edits'][:-1],
                 self.record['edits'] + [self.record['edits'][-1]],
                 list(reversed(self.record['edits']))]
        for edits in cases:
            record = deepcopy(self.record); record['edits'] = edits
            with self.subTest(names=[x['name'] for x in edits]), self.assertRaises(ValueError):
                border.predecessor_source(self.after, record)

    def test_changed_inverse_anchors_and_resealed_spans_reject(self):
        for index in range(len(self.record['edits'])):
            for side in ('before', 'after'):
                record = deepcopy(self.record)
                edit = record['edits'][index]
                edit[side] += '\n# changed inverse span\n'
                # Even consistent local span hashes cannot authorize a new edge.
                edit[side+'_sha256'] = border.sha(edit[side])
                with self.subTest(index=index, side=side), self.assertRaises(ValueError):
                    border.predecessor_source(self.after, record)

    def test_span_hashes_and_endpoint_hashes_cannot_change(self):
        for field in ('before_sha256', 'after_sha256',
                      'before_token_sha256', 'after_token_sha256'):
            record = deepcopy(self.record); record[field] = '0'*64
            with self.subTest(field=field), self.assertRaises(ValueError):
                border.verify_source(self.after, record)
        for side in ('before', 'after'):
            record = deepcopy(self.record); record['edits'][0][side+'_sha256'] = '0'*64
            with self.subTest(side=side), self.assertRaises(ValueError):
                border.predecessor_source(self.after, record)

    def test_unknown_parser_variants_never_activate_an_edge(self):
        for value in (self.before+'\n', self.after+'\n', self.after.replace(
                'from std.math import copysign, isfinite, sqrt',
                'from std.math import copysign, sqrt')):
            with self.subTest(digest=border.sha(value)), self.assertRaises(ValueError):
                border.verify_source(value, self.record)

    def test_physical_line_endings_are_not_normalized_into_an_accepted_source(self):
        read = Path.read_bytes; target = ROOT/border.MODULE
        for text in (self.before, self.after):
            changed = text.replace('\n', '\r\n').encode()
            with self.subTest(state=border.sha(text)), patch.object(Path,'read_bytes',
                    lambda p,*a,**k:changed if p==target else read(p,*a,**k)):
                with self.assertRaises(ValueError): border.verify(ROOT)
                with self.assertRaises(ValueError): border.successor_source(ROOT)

    def test_actual_finite_precedence_and_builder_operations_are_bound(self):
        cases = [
            ('not isfinite(cubic.a)', 'False'),
            ('or not isfinite(length)', 'or False'),
            ('if len(doc.children(node, "width")) > 0:', 'if False:'),
            ('if with_width:', 'if False:'),
            ('if not offset_free:', 'if False:'),
            ('if _lowest(width, stop - starts[k]) < -1.0e-9:',
             'if _lowest(width, stop - starts[k]) < -1.0:'),
            ('lane, piece.start, piece.a, piece.b, piece.c, piece.d',
             'lane, piece.start, piece.a, 0.0, 0.0, 0.0'),
            ('if len(widths) == 0 and from_borders == 0:', 'if len(widths) == 0:'),
            ('var derived = _border_widths(doc, group, s, end, offset_free)',
             'var derived = List[_Cubic]()'),
            ('return builder.build(budget)', 'return Map()'),
        ]
        for old, new in cases:
            self.assertEqual(self.after.count(old), 1, old)
            changed = self.after.replace(old, new, 1)
            with self.subTest(operation=old), self.assertRaises(ValueError):
                # Exercise declaration contracts independently of whole-file pins.
                border.verify_declarations(changed, self.record, True)

    def test_old_passes_xml_adapter_and_load_order_remain_bound(self):
        cases = [('    _roads(doc, builder)\n    _junctions(doc, builder)',
                  '    _junctions(doc, builder)\n    _roads(doc, builder)'),
                 ('struct _Doc(Movable):', 'struct _Doc(Copyable):')]
        for old, new in cases:
            self.assertEqual(self.after.count(old), 1)
            with self.subTest(operation=old), self.assertRaises(ValueError):
                border.verify_declarations(self.after.replace(old,new,1), self.record, True)

    def test_every_historical_record_is_still_exact(self):
        read = Path.read_bytes
        for name in self.record['historical_records']:
            target = ROOT/name
            with self.subTest(path=name), patch.object(Path, 'read_bytes',
                    lambda p,*a,**k: read(p,*a,**k)+b' ' if p == target else read(p,*a,**k)):
                with self.assertRaises(ValueError): border.verify(ROOT)

    def test_immutable_record_cannot_authorize_new_sources(self):
        read = Path.read_bytes; target = ROOT/border.MIGRATION
        with patch.object(Path,'read_bytes',lambda p,*a,**k:
                          read(p,*a,**k)+b' ' if p==target else read(p,*a,**k)):
            with self.assertRaisesRegex(ValueError,'immutable successor record'):
                border.verify(ROOT)

    def test_consumer_math_xml_speed_and_builder_mutations_reject(self):
        paths = ['extensions/carla/road.mojo', 'extensions/carla/road_info.mojo',
                 'extensions/carla/map.mojo', 'extensions/carla/map_builder.mojo',
                 'extensions/carla/map_validation.mojo', 'extensions/carla/lane_geometry.mojo',
                 'math/scaled_products.mojo', 'loaders/xml.mojo',
                 'extensions/carla/speed_limits.mojo']
        read = Path.read_bytes
        for name in paths:
            self.assertIn(name,self.record['unchanged_inputs'])
            target=ROOT/name
            with self.subTest(path=name), patch.object(Path,'read_bytes',lambda p,*a,**k:
                    read(p,*a,**k)+b'\n' if p==target else read(p,*a,**k)):
                with self.assertRaises(ValueError): border.verify(ROOT)

    def test_old_width_and_speed_regressions_cannot_be_replaced(self):
        read=Path.read_bytes
        for name in border.UNCHANGED_TESTS:
            target=ROOT/name
            with self.subTest(path=name), patch.object(Path,'read_bytes',lambda p,*a,**k:
                    read(p,*a,**k)+b'\n' if p==target else read(p,*a,**k)):
                with self.assertRaises(ValueError): border.verify(ROOT)

    def test_after_requires_its_reviewed_regression_suite(self):
        # On the before-source infrastructure PR this suite does not yet exist.
        # Only the source-relation helper above accepts an after fixture alone.
        read=Path.read_bytes; is_file=Path.is_file; target=ROOT/border.MODULE
        tests={ROOT/name for name in border.TESTS}
        with patch.object(Path,'read_bytes',lambda p,*a,**k:
                          self.after.encode() if p==target else read(p,*a,**k)), \
             patch.object(Path,'is_file',lambda p:False if p in tests else is_file(p)):
            with self.assertRaisesRegex(ValueError,'regression suite missing or changed'):
                border.verify(ROOT)


if __name__ == '__main__':
    unittest.main()
