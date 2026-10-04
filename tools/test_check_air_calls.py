# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the AIR call checker against small hand-written modules."""

import unittest

import check_air_calls as air

CALLEE = ('define internal float @run({ ptr, i64, float, i1 } noundef %0, '
          'i64 noundef %1) #1 {\n  ret float 0.0\n}\n')
MATCHED = CALLEE.replace('{ ptr,', '{ ptr addrspace(1),') + (
    'define void @kernel(ptr addrspace(1) noundef %0) {\n'
    '  %3 = call float @run({ ptr addrspace(1), i64, float, i1 } %2, i64 5)\n'
    '  ret void\n}\n')
LOST = CALLEE + (
    'define void @kernel(ptr addrspace(1) noundef %0) {\n'
    '  %3 = call float @run({ ptr addrspace(1), i64, float, i1 } %2, i64 5)\n'
    '  ret void\n}\n')


class AirCallTests(unittest.TestCase):
    def test_matching_calls_pass(self):
        self.assertEqual(air.mismatches(MATCHED), [])

    def test_a_lost_address_space_in_an_aggregate_is_found(self):
        bad = air.mismatches(LOST)
        self.assertEqual(len(bad), 1)
        self.assertEqual(bad[0][0], 'run')
        self.assertIn('argument 0', bad[0][1])

    def test_a_lost_address_space_on_a_pointer_is_found(self):
        module = ('define internal void @load(ptr addrspace(1) noundef %0) {\n'
                  '  ret void\n}\n'
                  'define void @kernel(ptr noundef %0) {\n'
                  '  call void @load(ptr %0)\n  ret void\n}\n')
        self.assertEqual([b[0] for b in air.mismatches(module)], ['load'])

    def test_constants_and_attributes_are_not_types(self):
        module = ('define internal float @scale(float noundef %0, '
                  '{ i64 } noundef %1) {\n  ret float %0\n}\n'
                  'define void @kernel() {\n'
                  '  %1 = call noundef float @scale(float 1.000000e+00, '
                  '{ i64 } { i64 4 })\n  ret void\n}\n')
        self.assertEqual(air.mismatches(module), [])

    def test_return_and_count_mismatches_are_found(self):
        module = ('define internal i32 @f(i64 noundef %0) {\n  ret i32 0\n}\n'
                  'define void @kernel() {\n'
                  '  %1 = call float @f(i64 1)\n'
                  '  %2 = call i32 @f(i64 1, i64 2)\n  ret void\n}\n')
        details = [b[1] for b in air.mismatches(module)]
        self.assertTrue(any('returns float' in d for d in details))
        self.assertTrue(any('2 arguments' in d for d in details))

    def test_kernels_are_found_from_launches(self):
        found = air.kernels(air.ROOT)
        self.assertIn(('render/gpu.mojo', 'rasterize_kernel'), found)


if __name__ == '__main__':
    unittest.main()
