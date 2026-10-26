# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Import anchor for the consumer-first accepted successor route.

The successor record now runs in Mojo. This module stays so that route can
import the followup contracts before the cleanup gate.
"""
import coverage_followup_contracts as prior
import unittest

__all__ = ("prior",)


class AnchorTests(unittest.TestCase):
    """The route reaches the followup contracts through this module."""

    def test_anchor_holds_the_followup_contracts(self):
        self.assertIs(prior, __import__('coverage_followup_contracts'))
        self.assertTrue(callable(prior.verify))
