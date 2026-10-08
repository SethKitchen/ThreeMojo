# Lane-query starting parameters

The indexed chord can give a bounded SPIRAL search an initial parameter guess.
It does not certify the nearest point or exclude any curve interval.
The canonical wide evaluator checks the guess. The existing global bounds
and accuracy checks still cover the actual curve.

The seed calculation widens each stored Float32 coordinate before subtraction.
It projects the query onto the three-dimensional chord and clamps the ratio.
It maps that ratio to the closed road-parameter interval in either direction.
A collapsed chord or unsupported arithmetic uses the original midpoint.
The map still rejects nonfinite public queries before searching.

Finite Float32 coordinates have magnitude below 2^128.
Coordinate gaps have magnitude below 2^129.
A nonzero gap has magnitude at least 2^-149.
Thus a nonzero chord's Float64 squared length cannot underflow or overflow.
The three-term dot products also fit Float64.
A final parameter-arithmetic check retains the midpoint if interpolation overflows.

The seed is a heuristic. A curved or nonconvex lane can have a different minimum.
No straight-line or rounded-monotonicity assumption removes its possible minima.
Every actual center evaluation retains the existing work debit.
Spatial tolerances, error bounds, depth and work limits remain unchanged.
An unresolved search still raises its explicit error.

Changing a starting guess can change an approximate returned parameter.
Strict point improvement remains the within-search replacement rule.
It does not promise the first parameter on a rounded plateau.
Proved cross-segment distance ties still favor the existing segment index.

The projected guess is restricted to one active SPIRAL record and one
constant positive width record. The existing full-center box must prove
that every station has the same strict plan-width classification.
The predicate normalizes before squaring and uses outward arithmetic.
Unknown bounds, boundary crossings and nonpositive or varying widths keep
the original midpoint. This gate does not change classification itself.

ARC keeps the original starting guess and endpoint-proof eligibility.
No station is discarded because an ideal derivative or chord is monotone.
The scalar evaluator, candidate ordering and certifying search are unchanged.
A changed witness can affect work, so established successes and explicit
failure controls remain validation gates. No work-counter reset is allowed.

Exact distance ties can retain different stations across solver versions.
The segment tie rule and strict lane-width test do not change.
A different search path can use a different amount of bounded work.
Known supported queries and explicit limit failures remain required controls.
No search retries with reset counters or larger limits.
