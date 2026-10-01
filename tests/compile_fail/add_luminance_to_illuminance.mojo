# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

from units.photometry import Illuminance, Luminance, LUX, NIT


def main():
    var invalid = Luminance(20, NIT) + Illuminance(30, LUX)
    print(invalid)
