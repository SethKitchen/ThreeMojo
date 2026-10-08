# Rounded ARC certificates

A complete rounded-output proof can certify a stored-point minimum on a
constant ARC. It can close exact distance ties that ordinary error bounds
cannot separate. The proof does not change the scalar lane evaluator.

## Supported inputs

The incumbent parameter must equal an endpoint of the original domain.
Interior incumbents stay on the ordinary path without any proof debit.
This initial scope targets endpoint plateaus.

The optional proof supports one zero-heading ARC geometry record. All lane
widths that contribute to the selected center must be constant. The road
must have one constant offset record and one constant elevation record.
Each contributing record must be active at both domain endpoints.

The rounded geometry distance must stay strictly inside its clamp. The
rounded trigonometric selector must select quadrant zero throughout each
proof cell. The sinc calculation must use its polynomial branch. The proof
uses the same stored sine and cosine coefficients as the scalar evaluator.
It does not use ideal trigonometric derivatives.

Every primitive operand must be zero or have magnitude from 2^-400 through
2^400. Every operand box must have one strict sign or be exactly zero.

Each nonzero binary64 operand has a dyadic quantum of at least 2^-452.
Products and fused sums have a quantum of at least 2^-904 and magnitude
below 2^802. Thus these primitives cannot underflow or overflow, including
at the guard boundaries. Outputs must pass the same guard before reuse.
A guarded nonzero reciprocal is also normal and finite.

Unknown support returns control to the existing solver. It does not reject
the map, loosen an error target, or report an off-road result.

## Rounded arithmetic

The private rounded-output box type encloses stored Float64 values. It is
separate from the real-expression interval and derivative types. Rounded
addition and multiplication are monotone at their extrema. Their bounds
therefore use rounded endpoint operations without an extra ULP expansion.
Each multiply-add takes the hull of the fused and separate graphs.

No-inline primitive boundaries protect the separate graph. Arbitrary
fast-math reassociation is outside this arithmetic contract.

For each coordinate box, the proof clamps the query coordinate to that
box. This gives the nearest box corner. The exact wide point predicate
compares this corner with one checked incumbent. A no-smaller corner
proves that the whole cell has no better point. Equality is sufficient.

## Work and failure behavior

Resumption can start a private proof over the original candidate domain.
The proof retains one checked witness and does not change the old cell
cover while it runs. It reserves each box node and reference term before
allocating the corresponding work item. It charges every scalar witness
and midpoint through the existing checked evaluator. A reserved but unused
item remains charged after failure.

No counter resets or extra budgets are used. Depth is measured from the original domain.

Only complete coverage replaces the old certificate with an exact witness
certificate. Unknown arithmetic, an unresolved discrete cell, a depth-limited private
proof, or a better sample leaves the old cover and incumbent intact. Spent
work remains in the cumulative ledger. Node or term exhaustion keeps the
existing explicit exception. The old solver retains its own depth checks.
An equality cell is never removed from an incomplete classification cover.

## Tie behavior

The general search replaces its incumbent only when the exact point order
is strictly negative. The local seed helper uses the same final replacement
rule. The optional proof preserves that incumbent and its parameter, even
when another parameter has the same stored point. Interior plateau
incumbents retain the ordinary strict-improvement policy. It does not promise the
first parameter in a plateau. Cross-segment exact ties still favor the
smaller segment index.

The two retained agent-drive queries have the same exact ARC endpoint
minimum as a competing LINE. An independent rational operation-box proof
covers each ARC domain in 45 boxes at depth 22. This is source proof data,
not native performance evidence. Focused native controls retain the exact
query and parameter words. Full native closure remains required before
adoption.
