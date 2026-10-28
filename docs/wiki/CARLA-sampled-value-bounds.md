<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Derivative-free sampled cover bounds

Sampled lane covers need value/error enclosures, not derivatives. The private
`lane_value_bounds.mojo` path evaluates the same POLY3/PARAM_POLY3 expression
with `_ValueJet`. Direct full-Jet APIs remain available for comparison. Four
closed quarter domains, shared endpoints, work debits, finite admission and
optional failure behavior are unchanged.

## Proof scope

For the reviewed `_JetExpression` primitives, constants and variables give the
same value intervals and zero scalar error. Negation, addition, subtraction,
multiplication, division and `rounded_value()` compute value/error using only
operand value/error fields. Derivative calculations populate separate fields;
omitting them does not change those operations. Derivative-free fields stay
whole and are never a derivative proof. The square-root primitive is excluded
because its zero shortcut inspects derivative fields.

The sampled graph retains every sample-index, clamp, finite, sign, reduction
and signed-axis guard. Stored constants and shared trig/Horner expressions do
not change. Its conditioned blend keeps the original weighted scalar-error
expression and the algebraically equal local ideal-value expression, with the
same value intersection. Only the unused derivative intersections disappear.
Lane record, width, offset and elevation traversal and final center expressions
retain their original operation grouping.

The native equivalence test checks all value/error/rounded-bound words on
1,940 Town quarter domains and all 24 interval endpoint words in each of 485
covers. It also covers scales, signed-zero/atan branches, budgets and optional
missing-record failure. Finite controls supplement the source argument; they
do not establish arbitrary-domain correctness by sampling. Original cover,
Town and sampled-axis suites also pass on the experimental source.

## Measured scope and remaining regression

A matched portable x86-64-v3, default-O3, Werror, single-thread experiment used
one warmup and eight balanced comparisons with 144 consumed route queries per
run. Median construction was 48.552 ms versus 60.097 ms for the prior qualified
lane candidate; the median paired ratio was 0.79375, a 20.6% reduction. All 36
returned station, center, certificate and work-counter records were identical.

Queries measured 5.419 ms versus 5.807 ms, but unchanged query work means this
is not evidence of an algorithmic query reduction. Against main in the same
window, median paired slowdowns were still 32.46x construction and 38.71x query.
This remains a substantial performance regression. The experiment does not
claim final composed-source, full-suite, coverage or general performance
acceptance; those gates remain separate.
