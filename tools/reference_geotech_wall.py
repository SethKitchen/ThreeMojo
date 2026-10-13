# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Independent planar-wall statics reference; no ThreeMojo imports.

Regenerate the rows in test_planar_wall_python_reference with this script.
--check confirms that the maintained Mojo expectations are current.

Scope: dry, level backfill, rectangular stem/footing, no key or pipes.
Rankine pressure is integrated as a triangular diagram, surcharge as a
rectangle. Vertical weights are rectangle areas times unit weight.
The reference checks Strength I minimum resultants, eccentricity/sliding,
and Service I tension-free pressure. It does not certify a design or
reproduce the external 23-case engine previously mentioned in the PR.
"""
import argparse
import ast
import math
from pathlib import Path


def reference(height: float, live_height: float) -> tuple[float, ...]:
    """Return input heights and five independently assembled SI results."""
    width, toe, stem, footing = 3.0, 0.6, 0.4, 0.5
    soil, concrete = 18000.0, 24000.0
    phi = math.radians(30)
    ka = (1 - math.sin(phi)) / (1 + math.sin(phi))
    heel = width - toe - stem
    weights = (
        ((height - footing) * stem * concrete, toe + stem / 2, 0.9),
        (width * footing * concrete, width / 2, 0.9),
        (heel * (height - footing) * soil, toe + stem + heel / 2, 1.0),
    )
    earth = ka * soil * height**2 / 2
    live = ka * soil * live_height * height
    vertical = sum(force * factor for force, _, factor in weights)
    resisting = sum(force * arm * factor for force, arm, factor in weights)
    horizontal = 1.5 * earth + 1.75 * live
    overturning = 1.5 * earth * height / 3 + 1.75 * live * height / 2
    eccentricity = width / 2 - (resisting - overturning) / vertical
    sliding = horizontal / (0.8 * vertical * math.tan(phi))
    live_weight = heel * live_height * soil
    service_v = sum(force for force, _, _ in weights) + live_weight
    service_m = sum(force * arm for force, arm, _ in weights)
    service_m += live_weight * (toe + stem + heel / 2)
    service_m -= earth * height / 3 + live * height / 2
    service_e = abs(width / 2 - service_m / service_v)
    effective = service_v / (width - 2 * service_e)
    if service_e <= width / 6:
        peak = service_v / width * (1 + 6 * service_e / width)
    else:
        peak = 2 * service_v / (3 * (width / 2 - service_e))
    return (height, live_height, vertical, horizontal, eccentricity,
            sliding, max(effective, peak))


def rows() -> str:
    """Return deterministic Mojo literals for four dry wall cases."""
    return '\n'.join('        (' + ', '.join(repr(x) for x in reference(h, q)) + '),'
                     for h, q in [(3.0, 0.0), (3.0, 0.6), (4.0, 0.0), (4.0, 0.6)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check:
        source = (Path(__file__).resolve().parents[1] / 'tests/test_geotech_wall.mojo').read_text()
        actual = source.split('# BEGIN PYTHON WALL REFERENCE\n', 1)[1].split('# END PYTHON WALL REFERENCE', 1)[0]
        actual_rows = ast.literal_eval('[' + actual + ']')
        expected_rows = ast.literal_eval('[' + rows() + ']')
        # Preserve the exact cases while allowing libm's last-bit rounding.
        # Absolute tolerances match the native tests, not a relative budget.
        tolerances = (1e-6, 1e-6, 1e-9, 1e-9, 1e-6)
        valid = len(actual_rows) == len(expected_rows)
        for actual_row, expected_row in zip(actual_rows, expected_rows):
            valid = valid and len(actual_row) == 7
            valid = valid and actual_row[:2] == expected_row[:2]
            valid = valid and all(
                math.isclose(a, e, rel_tol=0, abs_tol=tolerance)
                for a, e, tolerance in zip(
                    actual_row[2:], expected_row[2:], tolerances
                )
            )
        if not valid:
            raise SystemExit('Planar wall reference rows are stale')
        print('Four planar wall reference rows match independent Python statics.')
    else:
        print(rows())


if __name__ == '__main__':
    main()
