# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Mutations preserve selector logic, context graph, and both predecessor seals."""
from pathlib import Path
import unittest
from unittest.mock import patch
import rounded_line_selector_contracts as contract

ROOT=Path(__file__).resolve().parents[2]


class RoundedLineSelectorContracts(unittest.TestCase):
    def test_exact_positive(self):
        contract.verify(ROOT)

    def test_graph_and_name_mutations(self):
        cases=[
            ('curve_rounded_line','@always_inline\ndef _select_rounded_line_axis','def _select_rounded_line_axis'),
            ('curve_rounded_line','def _select_rounded_line_axis(', 'def _renamed_rounded_line_selector('),
            ('curve_rounded_line','def _rounded_line_axis_context(', 'def _renamed_rounded_line_context('),
            ('curve_rounded_line','from extensions.carla.curve_trig import _curve_cos, _curve_sin','from shadow_trig import _curve_cos, _curve_sin'),
            ('curve_rounded_line','if y.low == y.high and cosine != 0.0:','if x.low == x.high and cosine != 0.0:'),
            ('curve_rounded_line','cosine != 0.0','True'),
            ('curve_rounded_line','sine != 0.0','True'),
            ('curve_rounded_line','return _RoundedLineAxis(0, cosine)','return _RoundedLineAxis(1, cosine)'),
            ('curve_rounded_line','return _RoundedLineAxis(1, -sine)','return _RoundedLineAxis(1, sine)'),
            ('curve_rounded_line','_select_rounded_line_axis(x, y, cosine.low, sine.low)','_select_rounded_line_axis(x, y, sine.low, cosine.low)'),
            ('curve_rounded_line','if not (x.known and y.known):','if False:'),
            ('curve_rounded_line','from extensions.carla.curve_rounded_arc import (','from fake_box import ('),
            ('curve_rounded_line','var cosine = _RoundedBox.point(_curve_cos(record.geometry.heading))','var cosine = _RoundedBox.point(0.0)'),
            ('curve_rounded_line','x = _rounded_madd(offset, sine, x)','x = offset * sine + x'),
            ('curve_rounded_arc','return Self.bounds(value, value)','return Self.bounds(value, value + 1.0)'),
            ('curve_trig','if abs(value) > _PHASE_LIMIT:','if True:'),
            ('lane_refinement','terms += 1\n    var context = _rounded_line_axis_context','terms += 0\n    var context = _rounded_line_axis_context'),
            ('lane_refinement','from extensions.carla.curve_sum2 import _require_sum2_environment','from fake_math import _require_sum2_environment'),
            ('curve_sum2','def _sum2_supported_environment()','def _unchecked_environment()'),
        ]
        read=Path.read_text
        for name,before,after in cases:
            path=ROOT/('extensions/carla/'+name+'.mojo')
            original=read(path)
            with self.subTest(module=name,before=before):
                self.assertIn(before,original)
                changed=original.replace(before,after)
                with patch.object(Path,'read_text',lambda p,*a,**k:changed if p==path else read(p,*a,**k)):
                    with self.assertRaises((ValueError,RuntimeError)):
                        contract.verify_premises(ROOT)

    def test_reference_mutation(self):
        path=ROOT/'tests/test_carla_rounded_line_selector.mojo'
        read=Path.read_text
        original=read(path)
        changed=original.replace('cosine.low != 0.0','True')
        self.assertNotEqual(original,changed)
        with patch.object(Path,'read_text',lambda p,*a,**k:changed if p==path else read(p,*a,**k)):
            with self.assertRaises((ValueError,RuntimeError)):
                contract.verify_premises(ROOT)

    def test_both_record_seals_reject_edits(self):
        read=Path.read_bytes
        for name in [contract.MIGRATION,contract.prior.MIGRATION]:
            path=ROOT/name
            with patch.object(Path,'read_bytes',lambda p,*a,**k:read(p,*a,**k)+b' ' if p==path else read(p,*a,**k)):
                with self.assertRaises(ValueError):
                    contract.verify(ROOT)


if __name__=='__main__':
    unittest.main()
