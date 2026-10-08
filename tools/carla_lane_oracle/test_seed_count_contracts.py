# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact predecessor, live theorem/debit and dependency mutation controls."""
from contextlib import contextmanager
from copy import deepcopy
import hashlib
from pathlib import Path
import unittest
from unittest.mock import patch

import seed_count_contracts as seed

ROOT = Path(__file__).resolve().parents[2]
MAP = seed.MODULE
BOUNDS = 'extensions/carla/curve_bounds.mojo'
INTERVAL = 'extensions/carla/curve_interval.mojo'


class SeedCountSuccessorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.record = seed.read_record(ROOT)
        cls.after = seed.successor_source(ROOT)
        cls.before = seed.predecessor_source(cls.after, cls.record)

    @contextmanager
    def live_after(self, changes=None):
        values = {MAP: self.after.encode(), **(changes or {})}
        read = Path.read_bytes
        with patch.object(Path, 'read_bytes', lambda p,*a,**k:
                          values[p.relative_to(ROOT).as_posix()]
                          if p.is_relative_to(ROOT) and p.relative_to(ROOT).as_posix() in values
                          else read(p,*a,**k)):
            yield

    def test_exact_relation_and_truthful_actual_state(self):
        self.assertIsNone(seed.verify_source(self.before, self.record))
        edge = seed.verify_source(self.after, self.record)
        self.assertEqual(edge['path'], MAP)
        self.assertEqual(edge['before_sha256'], seed.BEFORE_SHA256)
        self.assertEqual(edge['after_sha256'], seed.AFTER_SHA256)
        actual = seed.sha((ROOT/MAP).read_bytes().decode())
        self.assertIn(actual, {seed.BEFORE_SHA256, seed.AFTER_SHA256})
        self.assertEqual(seed.verify(ROOT), None if actual == seed.BEFORE_SHA256 else edge)
        self.assertEqual(seed.historical_source(ROOT), self.before)

    def test_three_spans_reconstruct_every_historical_byte(self):
        text = self.before
        for edit in seed.checked_edits(self.record):
            self.assertEqual(text.count(edit['before']), 1)
            text = text.replace(edit['before'], edit['after'], 1)
        self.assertEqual(text, self.after)
        self.assertEqual(seed.sha(self.before), seed.BEFORE_SHA256)
        self.assertEqual(seed.sha(self.after), seed.AFTER_SHA256)
        self.assertEqual(len(self.before.splitlines())-len(self.after.splitlines()), 8)
        self.assertNotIn('before_complete_module', self.record)
        self.assertNotIn('after_complete_module', self.record)

    def test_missing_duplicate_reordered_and_modified_inverse_reject(self):
        edits = self.record['edits']
        for values in (edits[:-1], edits+[edits[-1]], list(reversed(edits))):
            record = deepcopy(self.record); record['edits'] = values
            with self.subTest(edits=[x['name'] for x in values]), self.assertRaises(ValueError):
                seed.predecessor_source(self.after, record)
        for index in range(3):
            for side in ('before', 'after'):
                record = deepcopy(self.record)
                record['edits'][index][side] += '\n# unauthorized span\n'
                record['edits'][index][side+'_sha256'] = seed.sha(record['edits'][index][side])
                with self.subTest(index=index, side=side), self.assertRaises(ValueError):
                    seed.predecessor_source(self.after, record)

    def test_record_span_and_endpoint_hashes_reject(self):
        for field in ('before_sha256','after_sha256','before_token_sha256','after_token_sha256'):
            record = deepcopy(self.record); record[field] = '0'*64
            with self.subTest(field=field), self.assertRaises(ValueError):
                seed.verify_source(self.after, record)
        for side in ('before','after'):
            record = deepcopy(self.record); record['edits'][0][side+'_sha256'] = '0'*64
            with self.subTest(side=side), self.assertRaises(ValueError):
                seed.predecessor_source(self.after, record)
        read = Path.read_bytes
        with patch.object(Path,'read_bytes',lambda p,*a,**k:
                          read(p,*a,**k)+b' ' if p == ROOT/seed.MIGRATION else read(p,*a,**k)):
            with self.assertRaisesRegex(ValueError, 'immutable successor record'):
                seed.verify(ROOT)

    def test_unknown_physical_variants_never_gain_a_predecessor(self):
        for text in (self.before+'\n', self.after+'\n',
                     self.before.replace('\n','\r\n'), self.after.replace('\n','\r\n')):
            with self.subTest(digest=seed.sha(text)), self.live_after({MAP:text.encode()}):
                with self.assertRaises(ValueError): seed.verify(ROOT)
                with self.assertRaises(ValueError): seed.historical_source(ROOT)
                with self.assertRaises(ValueError): seed.successor_source(ROOT)

    def test_scoped_declarations_distinguish_owners_and_decorators(self):
        text = 'struct One:\n    def same():\n        return 1\n\nstruct Two:\n    @always_inline\n    def same():\n        return 2\n'
        self.assertIn('return 1', seed.declaration(text,'same',('One',)))
        self.assertIn('@always_inline', seed.declaration(text,'same',('Two',)))
        for owner in ((),('Other',)):
            with self.subTest(owner=owner), self.assertRaises(ValueError):
                seed.declaration(text,'same',owner)
        with self.assertRaises(ValueError):
            seed.declaration(text+'\nstruct One:\n    def same():\n        return 3\n','same',('One',))
        with self.assertRaises(ValueError):
            seed.declaration('struct One:\n    if flag:\n        def same():\n            return 1\n','same',('One',))

    def test_actual_after_graph_and_complete_import_closure(self):
        with self.live_after():
            seed.verify_premises(ROOT,self.record,after=True)
            self.assertEqual(seed.dependency_inventory(ROOT), {MAP,*self.record['unchanged_inputs']})
        self.assertIn('extensions/carla/road.mojo',self.record['unchanged_inputs'])
        self.assertIn('extensions/carla/curve_trig.mojo',self.record['unchanged_inputs'])
        self.assertTrue(any(x['name']=='_uncertain' for x in self.record['premise_declarations']))

    def test_each_historical_record_and_live_dependency_is_exact(self):
        for group in ('historical_records','unchanged_inputs','unchanged_correctness_tests'):
            for name in self.record[group]:
                changed = (ROOT/name).read_bytes()+b'\n# changed\n'
                with self.subTest(group=group,path=name), self.live_after({name:changed}):
                    with self.assertRaisesRegex(ValueError,name): seed.verify(ROOT)

    def test_after_count_suite_is_required_and_mutations_reject(self):
        path = seed.AFTER_TESTS[0]
        with self.live_after({path:(ROOT/path).read_bytes()+b'\n# changed count controls\n'}):
            with self.assertRaisesRegex(ValueError,path): seed.verify(ROOT)
        if seed.sha((ROOT/MAP).read_bytes().decode()) == seed.BEFORE_SHA256:
            # Before-tree fixture construction alone cannot authorize after
            # admission without the reviewed future regression suite.
            if hashlib.sha256((ROOT/path).read_bytes()).hexdigest() != self.record['after_correctness_tests'][path]:
                with self.live_after(), self.assertRaisesRegex(ValueError,path): seed.verify(ROOT)

    def reject_premise(self,path,name,owner,old,new,occurrence=None):
        text = self.after if path == MAP else (ROOT/path).read_bytes().decode()
        declaration = seed.declaration(text,name,owner)
        if occurrence is None:
            self.assertEqual(declaration.count(old),1,(path,name,old))
            occurrence = 0
        else:
            self.assertLess(occurrence,declaration.count(old),(path,name,old))
        at = -1
        for _ in range(occurrence+1): at = declaration.find(old,at+1)
        changed = declaration[:at]+declaration[at:].replace(old,new,1)
        # Replace the unique declaration's token-matching physical block. A
        # method can share its name with another owner; never mutate by name.
        lines=text.splitlines(keepends=True)
        import textwrap
        snippet, first, last = seed._function_span(text,name,owner)
        self.assertEqual(snippet,declaration)
        physical=''.join(lines[first:last])
        self.assertEqual(textwrap.dedent(physical),declaration)
        lines[first:last]=[textwrap.indent(changed,'    '*len(owner)) if owner else changed]
        mutant=''.join(lines)
        with self.live_after({path:mutant.encode()}), self.assertRaisesRegex(ValueError,'live theorem premise'):
            seed.verify_premises(ROOT,self.record,after=True)

    def test_exact_range_and_admitted_station_premises(self):
        cases=[('_seed_exact_interval','not value.is_finite()','False'),
               ('_seed_exact_interval','value.high < value.low','False'),
               ('_seed_exact_interval','value.low > 0.0 or value.high < 0.0','True'),
               ('_seed_reference_domain','_seed_exact_interval(\n        _Interval(low, high)\n    )','True'),
               ('_seed_reference_domain','not _endpoint_in_exact_range(origin)','False'),
               ('_seed_reference_domain','not isfinite(geometry.length)','False'),
               ('_seed_reference_domain','geometry.length <= 0.0','False'),
               ('_seed_reference_domain','not rounded.is_finite()','False'),
               ('_seed_reference_domain','not _seed_exact_interval(d.value)','False'),
               ('_seed_reference_domain','0.0 <= d.error and d.error < 1.0','d.error >= 0.0'),
               ('_seed_reference_domain','0.0 <= d.error and d.error < 1.0','d.error < 1.0'),
               ('_seed_reference_domain','or rounded.low <= 0.0','or False'),
               ('_seed_reference_domain','or rounded.high >= geometry.length','or False'),
               ('_seed_reference_domain','not _endpoint_in_exact_range(k0)','False'),
               ('_seed_reference_domain','not _endpoint_in_exact_range(rate)','False'),
               ('_seed_reference_domain','return _seed_exact_interval(product.value)','return True')]
        for name,old,new in cases:
            with self.subTest(name=name,operation=old): self.reject_premise(MAP,name,(),old,new)

    def test_live_containment_and_actual_debits(self):
        cases=[('_winner_seed_room','or winner_reference <= 0','or False'),
               ('_try_winner_seed','or not isfinite(low)','or False'),
               ('_try_winner_seed','or not isfinite(high)','or False'),
               ('_try_winner_seed','or not isfinite(certificate.s)','or False'),
               ('_try_winner_seed','or certificate.s < low','or False'),
               ('_try_winner_seed','or certificate.s > high','or False'),
               ('_try_winner_seed','band_low + 0.5 * (original_s - band_low)','band_low - 0.5 * (original_s - band_low)'),
               ('_try_winner_seed','original_s + 0.5 * (band_high - original_s)','original_s + 2.0 * (band_high - original_s)'),
               ('_try_winner_seed','var first = bitcast[DType.uint64](support.low)','var first = bitcast[DType.uint64](support.low * 0.5)'),
               ('_try_winner_seed','bitcast[DType.uint64](support.high) - first','bitcast[DType.uint64](support.high * 2.0) - first'),
               ('_try_winner_seed','UInt64(2 * at + 1)','UInt64(2 * at + 2)'),
               ('_try_winner_seed','UInt64(1) << UInt64(level + 1)','UInt64(1) << UInt64(level)'),
               ('_try_winner_seed','work._step(60)','work._step(59)'),
               ('_try_winner_seed','work._step(12)','work._step(11)'),
               ('_try_winner_seed','work.charge(0, point_work, node_cost)','work.charge(0, 0, node_cost)'),
               ('_try_winner_seed','certificate.terms += point_work','certificate.terms += 0'),
               ('_try_winner_seed','var point_work = _reference_work(road, s, s)','var point_work = 0'),
               ('_try_winner_seed','road, section, lane, s, checked_terms, point_work','road, section, lane, s, checked_terms, reference'),
               ('_try_winner_seed','_require_sum2_environment()','pass')]
        for name,old,new in cases:
            with self.subTest(name=name,operation=old): self.reject_premise(MAP,name,(),old,new)

    def test_count_clamp_rate_ceil_and_piece_join_premises(self):
        cases=[('_geometry_distance','return distance','return _Jet.constant(0.0)'),
               ('_spiral_counts','(geometry.curvature_end - k0) / geometry.length','geometry.curvature_end / geometry.length'),
               ('_spiral_counts','not counts.is_finite()','False'),
               ('_spiral_counts','counts.low < 0.0','False'),
               ('_spiral_counts','.absolute()',''),
               ('_spiral_counts','.maximum(_Interval.point(abs(k0)))',''),
               ('_spiral_counts','d.rounded_value() * (_Interval.point(1.0) + reach)','d.rounded_value() + (_Interval.point(1.0) + reach)'),
               ('_spiral_counts','counts.high > 1e9','counts.high > 1e10'),
               ('_spiral_counts','1 + Int(ceil(counts.low))','Int(ceil(counts.low))'),
               ('_spiral_counts','1 + Int(ceil(counts.high))','Int(ceil(counts.high))'),
               ('_reference_work','counts[1] - counts[0] > 1','counts[1] - counts[0] > 2'),
               ('_reference_work','return 5 * counts[0]','return 4 * counts[0]'),
               ('_reference_work','return 5 * (counts[0] + counts[1])','return 5 * counts[1]')]
        for name,old,new in cases:
            with self.subTest(name=name,operation=old): self.reject_premise(BOUNDS,name,(),old,new)

    def test_actual_jet_error_and_derivative_operations_are_bound(self):
        cases=[('constant','return Self(_Interval.point(value), zero, zero, 0.0)','return Self(_Interval.point(value), zero, zero, 1.0)'),
               ('rounded_value','return self.value + _Interval(-self.error, self.error)','return self.value'),
               ('__add__','var inherited = _next_up(self.error + other.error)','var inherited = 0.0'),
               ('__add__','first = self.first + other.first','first = _Interval.whole()'),
               ('__mul__','_Interval.point(self.value.magnitude())','_Interval.point(0.0)'),
               ('__mul__','_Interval.point(other.value.magnitude())','_Interval.point(0.0)'),
               ('__mul__','+ _Interval.point(self.error) * _Interval.point(other.error)','+ _Interval.point(0.0)'),
               ('__mul__','var error = _next_up(inherited + _roundoff(magnitude))','var error = inherited'),
               ('__mul__','error = other.error','error = 0.0'),
               ('__mul__','error = self.error','error = 0.0')]
        for name,old,new in cases:
            with self.subTest(name=name,operation=old): self.reject_premise(INTERVAL,name,('_JetExpression',),old,new)

    def test_directed_endpoints_selector_and_environment_are_bound(self):
        cases=[(INTERVAL,'_endpoint_in_exact_range',(),'0x26F0000000000000','0x16F0000000000000'),
               (INTERVAL,'_endpoint_in_exact_range',(),'0x58F0000000000000','0x68F0000000000000'),
               (INTERVAL,'_directed_endpoint_sum',(),'var residual = (one - first) + (two - second)','var residual = 0.0'),
               (INTERVAL,'_directed_endpoint_product',(),'var residual = fma(one, two, -value)','var residual = 0.0'),
               (INTERVAL,'_residual_bracket',(),'if residual > 0.0:','if residual < 0.0:'),
               ('extensions/carla/road_info.mojo','info_index',(),'records[mid].distance() <= s','records[mid].distance() < s'),
               ('extensions/carla/road_info.mojo','distance',('RoadInfoGeometry',),'return self.s','return self.s + 1.0')]
        for path,name,owner,old,new in cases:
            with self.subTest(path=path,name=name,operation=old): self.reject_premise(path,name,owner,old,new)


    def test_sterbenz_tests_and_exact_error_reset_are_separately_bound(self):
        cases=[('left.low >= right.high * 0.5','left.low >= right.low * 0.5'),
               ('left.high <= right.low * 2.0','left.high <= right.high * 2.0'),
               ('left.low >= bitcast[DType.float64](UInt64(623) << UInt64(52))','True'),
               ('right.low >= bitcast[DType.float64](UInt64(623) << UInt64(52))','True'),
               ('left.high <= bitcast[DType.float64](UInt64(1423) << UInt64(52))','True'),
               ('right.high <= bitcast[DType.float64](UInt64(1423) << UInt64(52))','True'),
               ('one.error == 0.0 and two.error == 0.0','one.error == 0.0 or two.error == 0.0'),
               ('result.error = _next_up(one.error + two.error)','result.error = 0.0'),
               ('result.error = 0.0','result.error = 1.0')]
        for old,new in cases:
            with self.subTest(operation=old): self.reject_premise(INTERVAL,'_stored_difference',(),old,new)

    def test_zero_identity_and_roundoff_paths_are_separately_bound(self):
        cases=[]
        for name in ('__add__','__mul__'):
            for side in ('self','other'):
                cases.append((name,('_JetExpression',),side+'.value.is_point(0.0) and '+side+'.error == 0.0','False'))
        for side in ('self','other'):
            cases.append(('__mul__',('_JetExpression',),side+'.value.is_point(1.0) and '+side+'.error == 0.0','False'))
            cases.append(('__mul__',('_Interval',),side+'.is_point(1.0)','False'))
        cases += [('__mul__',('_Interval',),'self.is_point(0.0) and other.is_finite()','False'),
                  ('__mul__',('_Interval',),'other.is_point(0.0) and self.is_finite()','False'),
                  ('rounded_value',('_JetExpression',),'if self.error == 0.0:','if True:'),
                  ('__add__',('_JetExpression',),'_next_up(inherited + _roundoff(magnitude))','inherited'),
                  ('__add__',('_JetExpression',),'var magnitude = _next_up(value.magnitude() + inherited)','var magnitude = value.magnitude()'),
                  ('_roundoff',(),'if exponent <= 1:','if exponent <= 0:'),
                  ('_roundoff',(),'return _next_up(bitcast[DType.float64](UInt64(1)))','return 0.0')]
        for name,owner,old,new in cases:
            with self.subTest(name=name,operation=old): self.reject_premise(INTERVAL,name,owner,old,new)

    def test_each_actual_debit_and_certificate_write_is_live_and_ordered(self):
        text=seed.declaration(self.after,'_try_winner_seed')
        prefixes=('work._step(', 'work.charge(', 'certificate.nodes +=',
                  'certificate.terms +=', 'certificate.s =', 'certificate.point =',
                  'certificate.upper =')
        lines=text.splitlines(keepends=True)
        indices=[i for i,line in enumerate(lines) if line.lstrip().startswith(prefixes)]
        self.assertEqual(len(indices),18)
        expected=seed.guard._winner_seed_live_observables(text)
        for number,index in enumerate(indices):
            changed=lines[:];changed.pop(index)
            with self.subTest(removed=number):
                self.assertNotEqual(seed.guard._winner_seed_live_observables(''.join(changed)),expected)
        changed_pairs=0
        for one,two in zip(indices,indices[1:]):
            if lines[one] == lines[two]: continue
            changed=lines[:];changed[one],changed[two]=changed[two],changed[one]
            with self.subTest(reordered=(one,two)):
                self.assertNotEqual(seed.guard._winner_seed_live_observables(''.join(changed)),expected)
            changed_pairs += 1
        self.assertGreater(changed_pairs,10)

    def test_count_query_purity_rejects_side_effects_callbacks_and_errors(self):
        anchor='var at = info_index(road.info.geometries, low)'
        for inserted in ('print("side effect")','callback()', 'raise Error("new failure")',
                         'road.info.geometries[0].s = high', '_require_sum2_environment()'):
            with self.subTest(inserted=inserted):
                self.reject_premise(BOUNDS,'_reference_work',(),anchor,inserted+'\n    '+anchor)

    def test_concrete_owning_storage_and_jet_layouts_are_bound(self):
        cases=[('extensions/carla/road.mojo','struct Road(Copyable, Movable):','var info: InformationSet','var info: List[InformationSet]'),
               ('extensions/carla/road_info.mojo','struct RoadInfoGeometry(RoadInfo):','var s: Float64','var s: Float32'),
               ('extensions/carla/curve_interval.mojo','struct _JetExpression[derivatives: Bool]','var error: Float64','var error: Float32')]
        for path,start,old,new in cases:
            text=(ROOT/path).read_bytes().decode();begin=text.index(start);at=text.index(old,begin)
            changed=text[:at]+text[at:].replace(old,new,1)
            with self.subTest(path=path), self.live_after({path:changed.encode()}):
                with self.assertRaisesRegex(ValueError,'owning-storage or declaration routing'):
                    seed.verify_premises(ROOT,self.record,after=True)

    def test_actual_fp_probe_is_fresh_and_materialized(self):
        path='extensions/carla/curve_sum2.mojo'
        cases=[('_require_sum2_environment','if not _sum2_supported_environment():','if False:'),
               ('_sum2_supported_environment','one_slot.unsafe_load[volatile=True]()','one_slot.unsafe_load[volatile=False]()'),
               ('_sum2_supported_environment','half_slot.unsafe_load[volatile=True]()','half_slot.unsafe_load[volatile=False]()'),
               ('_sum2_supported_environment','tiny_slot.unsafe_load[volatile=True]()','tiny_slot.unsafe_load[volatile=False]()')]
        for name,old,new in cases:
            with self.subTest(name=name,operation=old): self.reject_premise(path,name,(),old,new)


    def test_actual_support_clamps_and_every_return_preserve_the_cell(self):
        path='extensions/carla/curve_minimizer_support.mojo'
        cases=[('var result = _Interval(low, high)','var result = _Interval(low - 1.0, high + 1.0)',None),
               ('return _Interval(low, high)','return _Interval(low - 1.0, high + 1.0)',None),
               ('return result','return _Interval(low - 1.0, high + 1.0)',0),
               ('return result','return _Interval(low - 1.0, high + 1.0)',1)]
        for index in range(2):
            cases += [('result.high = min(result.high, limit.high)','result.high = max(result.high, limit.high)',index),
                      ('result.low = max(result.low, limit.low)','result.low = min(result.low, limit.low)',index)]
        for old,new,index in cases:
            with self.subTest(operation=old,index=index):
                self.reject_premise(path,'_minimizer_support',(),old,new,index)
        self.reject_premise(path,'_ordered_finite',(),'value.low <= value.high','True')
