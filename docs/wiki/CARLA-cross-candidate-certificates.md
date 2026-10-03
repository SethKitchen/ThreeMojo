# CARLA cross-candidate certificates

## Draft scope

The lane query holds selection until it has a minimum-distance certificate.
It remains part of held [#594](https://github.com/SethKitchen/ThreeMojo/pull/594).
It admits candidates with the separate index and full-curve bounds.
A cached full rounded-center box can exclude a segment after an incumbent exists.
The box lower bound must exceed that stored point's upper bound.

This strict exclusion preserves index ties and remains valid after an incumbent improvement.
Unknown boxes retain their candidate.
The query must be finite, including when the map has no matching segment.
The former unbounded-error index stopping rule is not used.
The integrated [index admission layer](CARLA-index-admission) uses the corrected
R-tree contract from [#589](https://github.com/SethKitchen/ThreeMojo/issues/589).

## Candidate certificate

A certificate contains a stored incumbent point and its road parameter.
It contains lower and upper squared-distance bounds in power-of-two normalized units.
It records whether the incumbent is an exact minimizing witness.
It also retains possible-minimizer cells and the consumed node and quadrature counters.

The general refiner retains tolerance-closed cells.
It retains the evaluated endpoints when no interior Float64 parameter exists.
It removes a cell only when its lower bound exceeds the incumbent upper bound.
A scale change rebases lower bounds downward and upper bounds upward.
The target remains the exact real distance between stored evaluator points.
The parameter domain remains the existing Float64 domain.

## Segment selection

A candidate must dominate every competitor.
Its upper bound must not exceed a later-index competitor's lower bound.
Its upper bound must be strictly less than an earlier-index competitor's lower bound.
Two exact minimum witnesses use the existing exact point-distance predicate.
Exact ties retain the earlier segment index.
An unresolved overlap raises an error.

Overlapping candidates resume only their retained cells within the original cumulative limits.
A few nearby probes cannot certify a global minimum.

## Strict waypoint classification

An exact minimum witness uses the existing exact point-width predicate.
The selected parameter follows the refiner's deterministic witness order.
This is a statement about the returned waypoint.
It does not claim the same width or classification at every tied parameter.

A distance-gap-only result must prove the same classification for the returned sample and every retained possible-minimizer cell.
Each cell bounds the rounded center and width expressions.
It bounds the sign of four times the plan squared distance minus the width squared.
Width bounds are computed before curve quadrature.

An exact minimizing point has plan squared distance no greater than the certificate's three-dimensional upper bound.
This gives an upper sign bound restricted to possible minimizing points.
A negative upper sign bound and positive width can prove inside without curve quadrature.
This bound must not be used as a bound for every non-minimizing point in the cell.

The fallback intersects its full-cell sign bound with this minimizing-set bound.
An empty intersection proves that the cell contains no exact minimizing point.
An inside result also requires positive width throughout the cell.

A nonpositive width is outside.
A zero sign is outside because the test is strict.
An unresolved sign, unresolved record branch, or disagreement raises an error.
Scalar three-dimensional distance bounds cannot replace these cell checks.

## Exact axis specialization

The integrated axis helper covers a heading-zero LINE with constant width, offset, and elevation records.
Its stored x evaluator is monotone.
It accepts an inverse seed only after the stored x value equals the query x value.
Otherwise it bisects ordered nonnegative Float64 parameters to an adjacent bracket.
It uses exact point order for the two final values.

It exports its consumed counters.
Other straight geometries still require the general certificate.

## Work and release gates

The limits remain 16,384 nodes, 2,000,000 quadrature terms, and depth 96.
Classification continues the selected candidate's counters.
Each retained cell consumes its existing node charge before a width-only decision.
A width-only decision consumes no curve quadrature terms because it evaluates no curve quadrature.
All actual curve work retains its existing term charge.

The general distance tolerance is unchanged.
Exhaustion raises an error and cannot produce an off-road answer.
Candidate admission has no new map-wide work bound.

The focused controls cover bound overlap, equality order, scale rebasing, exact extreme-scale comparisons, retained cells, strict boundaries, and counter exhaustion.
They also cover nonfinite queries on an empty map.
The original controls retain cached-box exclusion and unknown-box admission checks.
Native compilation, native controls, coverage, consumer checks, and ordinary-query cost remain release gates.
Focused native controls do not replace the full final release gates.


## Bounded candidate resumption

Fresh search and resumed search use the same interval solver.
A resumed search receives the original segment domain, a requested squared-distance gap, and its positive power-of-two scale.
Its allowance is the smaller of the existing spatial-and-rounding target and a downward-rebased requested gap.
This cannot widen the original tolerance.

The certificate retains the incumbent, cell lower bounds, parameter depths, and consumed node and quadrature counters.
Only retained cells can reopen.
Old strict exclusions remain valid after an incumbent improvement.
A resumed interval keeps its old depth.
An evaluated terminal point keeps its bound and depth.

Only complete terminal-point coverage can establish an exact witness without the separate exact specializations.
A tolerance-closed interval cannot establish exactness.

Consumed counters and improved incumbents are stored immediately.
On an error, the old cell cover and old-scale bounds remain conservative.
A retry cannot reset spent work or lose the only cover of possible minimizers.
The caller must retain the same road snapshot, lane, query, and original segment domain.

Map resumption starts after the unchanged index admission pass.
It chooses a non-exact overlapping candidate and tightens its requested gap.
It rechecks the stored-point order and index-sensitive dominance after each resume.
A scale change rebases the previous request downward before further tightening.
The loop uses the original per-candidate work caps and adds no extra budget.
A work or numerical limit still raises instead of selecting an unproved lane.


## Stored evaluator graph

The checked center evaluator has a no-inline boundary.
This uses one compiled scalar graph for query and refinement witnesses.
Exact comparisons do not mix separate call-site FMA contractions.
Interval bounds still cover permitted contraction inside that graph.
Construction conversion bounds remain separate from stored-center distance comparisons.
The runtime cost of this boundary remains a performance gate.
