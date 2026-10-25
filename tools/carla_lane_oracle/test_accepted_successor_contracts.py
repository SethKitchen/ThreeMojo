# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Import anchor for the consumer-first accepted successor route.

The successor record now runs in Mojo. This module stays so that route can
import the followup contracts before the cleanup gate.
"""
import coverage_followup_contracts as prior

__all__ = ("prior",)
