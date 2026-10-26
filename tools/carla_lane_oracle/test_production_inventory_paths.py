# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Import anchor for the consumer-first cleanup route.

The path census now runs in Mojo. This module stays so that route can
import the cache, lane-order, and guard contracts before the cleanup gate.
"""
import cache_key_contracts as cache
import lane_order_contracts as order
import sum2_guard_contracts as guard
import unittest

__all__ = ("cache", "order", "guard")


class AnchorTests(unittest.TestCase):
    """The route reaches the three contracts through this module."""

    def test_anchor_holds_the_three_contracts(self):
        for name, module in (('cache_key_contracts', cache),
                             ('lane_order_contracts', order),
                             ('sum2_guard_contracts', guard)):
            with self.subTest(module=name):
                self.assertIs(module, __import__(name))
                self.assertTrue(callable(module.verify))
