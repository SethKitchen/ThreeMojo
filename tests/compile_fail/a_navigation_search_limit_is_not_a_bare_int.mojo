# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A navigation search kind must use its declared type."""

from extensions.carla.navigation_search import NavigationSearchLimit


def check(value: NavigationSearchLimit):
    print(value.is_valid())


def main():
    check(0)
