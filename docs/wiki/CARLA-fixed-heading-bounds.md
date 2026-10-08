<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Fixed LINE heading bounds

A LINE's stored geometry heading does not change with road s.
Its reference direction and lateral-offset direction use that fixed heading.
The lane width and lane-center tangent can still change.

The bounds use an explicit fixed-heading helper for these two call sites.
They do not infer constant provenance from a singleton interval or from
zero sampled derivatives. The generic variable-heading path stays unchanged.

## A fixed coefficient with an uncertain value

The existing trigonometric bounds enclose every permitted scalar result,
including fused and unfused arithmetic and possible quadrant branches.
For a fixed input, each compiled call site supplies one fixed Float64
coefficient within that range. Its derivatives with respect to s are zero.
The helper stores this uncertainty in the coefficient's value interval.
Outer coordinate operations retain their own scalar-rounding error bounds.

Different call sites can select different allowed coefficients. Both the
full-domain and translated expansion models enclose those fixed choices.
Lost correlation can widen the result; it does not justify a tighter bound.
Unsupported or nonfinite phases retain the generic unknown derivatives.

This helper does not claim that arbitrary rounded functions are continuous
or monotone. A variable singleton is still an expansion point. Even
heading plus t cubed has zero first and second derivatives at t=0 without
being a constant function. Such inputs keep the generic uncertain branch.

## The ordinary diagonal control

The world-signals fixture has a LINE at origin (55,-10), with stored
heading pi/4, lane width 3.5, zero lane offset and zero elevation.
The query is exactly (55.25,5,3) in CARLA coordinates.

Conservative selector arithmetic includes both adjacent quadrants. The old
branch union therefore discarded derivative information in every spatial
cell, although the heading itself did not vary. Subdivision could not
remove that artificial loss of information.

Independent stored-polynomial and rounding bounds give normalized distance
curvature close to 0.125. Their enclosure gap is at most 4.53e-14,
below the unchanged accuracy allowance of about 7.25e-13.
No node, quadrature, depth, accuracy or test limit changes.

Controls retain the exact failing input. They also cover neighboring
headings, negative headings, finite phase boundaries, unsupported phases,
variable singleton headings, and a near-constant nonzero derivative.
A separate h=0.1 control encloses both one-ULP-separated cosine results
from fused and unfused Horner evaluation.

This correction changes numerical proof information, not scalar positions
or public pose evaluation. Other lane refinement, admission, coverage and
performance requirements remain separate qualification gates.
