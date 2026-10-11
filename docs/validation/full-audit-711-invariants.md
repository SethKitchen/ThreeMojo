# Full-audit coverage invariants

These source changes retain the numerical models, explicit work limits and
checked Mojo error paths. The endpoint refusal permutation has the floating-
point observation limit stated below. The source successor record binds the
exact inputs, outputs and reversible source edits.
Native execution and current-source coverage are separate requirements.
This document does not certify a run or waive a reachable coverage outcome.

## Nonnegative stored blend allowance

The two consumers call the concrete `_stored_blend_error` producer with
full or value-only jets. The producer does not read derivative fields.

The producer rejects a nonfinite or reversed ideal interval, a negative or
nonfinite input error, and nonfinite scalar endpoints. Its rejection value
is positive infinity. It then checks each rounded-rate endpoint and scalar
endpoint. Every nonzero checked operand has magnitude from 2^-400 through
2^400. A rounded-rate overflow also takes this rejection path.

Every summand in the final allowance is nonnegative:

- An interval magnitude is the maximum of absolute endpoint values.
- The inherited error has passed the nonnegative input check.
- The complement allowance is zero or the output of `_roundoff`.
- Product and final allowances come from `_roundoff`.
- `_roundoff` returns a positive outward allowance or positive infinity.

The final expression adds products of these quantities. Zero identities
retain an upper endpoint of positive zero. Ordinary outward addition and
multiplication retain a nonnegative upper endpoint. Overflow retains a
positive infinite upper endpoint. An indeterminate interval operation
returns the whole interval, whose upper endpoint is positive infinity.
No path returns a finite negative upper endpoint. Negative zero also
satisfies the removed nonnegative comparison.

The consumers retain the finite check and the unchanged `min` assignment.
They retain the original weighted scalar graph and both ideal enclosure
intersections. The full/value source correspondence remains checked on the
actual source. Tests use the concrete producer, including invalid error
states and exceptional scalar values. They do not inject a negative
producer result.

## Rounded-axis inverse stays finite

Only the optional rounded-axis path loses its finite-seed guard. The
unrestricted axis path retains its overflow fallback.

A successful `_rounded_line_axis_context` establishes the following facts
through `_RoundedBox`, `_rounded_operand`, the checked rounded multiply-add
operations, and the concrete axis selector:

- The station endpoints are finite and their magnitudes are at most 2^400.
- The accepted stored coordinate boxes have magnitudes at most 2^400.
- The selected stored sine or cosine is nonzero. Its magnitude is at least
  2^-400 and at most 2^400.
- The query comes from finite Float32 coordinates. Its magnitude is less
  than 2^128.

The canonical LINE scalar evaluator uses the same no-inline trigonometric
producer. The rounded boxes cover its separate and permitted fused
multiply-add graphs. These premises apply to the actual checked endpoints,
not only to ideal trigonometric values.

Allowing conservative binary64 rounding, the inverse numerator has
magnitude less than 2^402. Division has magnitude less than 2^802. Adding
the low station stays below 2^803. These bounds are well below the binary64
overflow boundary. The retained clamp and exact stored-coordinate test are
unchanged. The renamed `seed_point` temporary avoids a new outer declaration
colliding with the later loop-local `point`; it retains the same value,
Float64 values and moves.

## Strict junction cuts before canonical certification

The section boundary check establishes finite 0 <= a < b on this path.
The equal-endpoint case returns earlier. The list starts with a and b.
For finite insertions, `_insert_break` rejects endpoint and exterior values,
uses an ordered insertion position, and rejects duplicates. This includes
both zero signs. Positive or negative infinity is rejected at the exterior
comparison while the list is ordered. A finite addition that overflows to
infinity cannot become an interior cut.

Public mutable profile records can contain NaN. Such a value is not a
sorted-list premise. Insertion places a NaN before the final finite b and
never removes it. The earlier proposal loop visits every retained start.
At a NaN start, every geometry lookup comparison with that station is
false, so `info_index` returns -1. `_span_box` raises before the canonical
certification loop. Later insertions cannot remove that failure. The first
loop and its existing guard are unchanged.

Reaching the second loop therefore establishes distinct sorted finite cuts
with the retained final endpoint b. Each `end` is strictly greater than
`start`. Removing that outer comparison leaves both endpoint adjustments
unchanged. The inner `start <= end` check remains necessary for adjacent
representable stations, including the smallest positive subnormal.

## Finite-width admission before local seed evaluation

The local-seed admission retains all three predicates. It checks finite
`hi - lo` before positive second derivative and stationary-point inclusion.
This is an explicit interpolation-domain admission check. It does not make
the old trailing condition's missing False observation reachable.

All three expressions are pure and do not change work counters. Their
conjunction selects the same local-seed branch in either order. Every path
that reaches this admission already called `_midpoint(lo, hi)`, which
computed the same `hi - lo`. The new order therefore introduces no first
overflow operation on this path. The subtraction result is used only as a
finite-domain admission predicate in this change.

The internal search helper accepts finite negative lower stations. Finite
opposite-sign endpoints can have an infinite difference. The current width
control uses a real, preflight-admitted LINE Road, finite endpoints near
-1e308 and 1e308, a checked incumbent and an unknown enclosure from actual
producers. It runs one pending cell with depth zero and six term units.
It does not claim that a public nonnegative station query reaches this input.
No derivative model or certificate is fabricated to force a condition value.
A finite-width neighbor and ordinary local-seed controls remain separate
coverage requirements.

## Post-local natural exclusion

The earlier general `natural > best_upper` exclusion remains. After a
local seed attempt, only two cases are possible:

1. The seed did not improve. The stored point, power-of-two scale, and
   deterministic natural-bound expression are unchanged from the admitted
   values. The repeated exclusion is false.
2. The seed improved. `_local_seed` returns one of its actual checked
   in-cell scalar points. Its interpolation was admitted only for finite
   width. Golden-section updates retain stations in the closed cell under
   binary64 rounding, including endpoint collapse. The full point-domain
   enclosure therefore bounds that stored point's exact distance. Its
   natural lower endpoint cannot exceed the retained upward witness bound.

The production witness bound is `_refinement_square`, including its tighter
error-free-residual upper endpoint. The control compares against that
actual bound. It does not substitute the looser original square. The
original work debits, scale refresh, goal checks, and derivative refresh
remain in the same order.

## Endpoint-count refusals remain required

An admitted whole-span count does not imply that a clamped singleton count
is admitted. The clamp can replace an ideal-plus-error representation with
an error-zero uncertain interval. The junction first/last endpoint guards,
chord first/last endpoint guards and selected-center guard remain executable.
A finite search without a counterexample cannot justify removing a guard.

The junction tests call the actual helper with preflight-valid Road records.
They obtain incoming bounds from the maintained lane-bound producer and
compute the complete-cell work in the same arithmetic state. They reserve
5,000,000,005 term units and five steps without executing that many scalar
nodes. An unsupported-state SPIRAL enclosure becomes unknown before
quadrature; a finite elevation still requires monotone enclosure.

The first-endpoint control uses the existing test-only flush-to-zero state.
The last-only control uses x86 denormals-are-zero, alone or with flush-to-zero.
The C fixture restores the saved state on normal return and error. Platforms
without those states do not establish the same witness. The first-refusal,
last-only-refusal and both-admitted cases remain separate obligations.
A one-term-short budget checks the unchanged exhaustion ledger.

These are direct-helper controls. The outer junction section caller has a
narrower nonnegative station domain, and public Map entry points reject
unsupported arithmetic states. No ordinary public-path reachability follows
from these helper controls. The finite proposal box is a target to enclose;
it is not an injected proof or derivative jet.

## Chord endpoint admission before derivative refusal

Let D mean that the derivative is finite. Let E mean that both endpoint
counts are nonnegative. Both refusal blocks return the same stored
(natural, box, spent) tuple. The earlier source returns that tuple for not D,
then for not E. The current source checks not E, then not D. Both proceed
to the unchanged scalar budget gate exactly when D and E hold.

Both count calls are pure preflight operations. They do not traverse scalar
quadrature, allocate, mutate counters or raise a Mojo Error. Their index and
integer-conversion guards precede the relevant operations. The permutation
therefore preserves the returned bounds, captured proof data, explicit
node/term ledgers and Mojo Errors. It does not move a scalar evaluation past
an admission check. The fixed source inverse checks the complete intact
blocks, surrounding declaration and unchanged return payload.

The extra count arithmetic can set IEEE sticky exception flags on a path
that previously returned earlier. The arithmetic-control capability check
does not observe those flags. Equal sticky flags or behavior with externally
enabled floating-point traps are not part of this equivalence claim.

Three preflight-valid Road controls cover first refusal, last-only refusal
and both admitted. A bounded coarse-box attempt refuses a child before
scalar traversal. The original default term budget remains unchanged.
Malformed/nonfinite Road diagnostics are separate robustness controls and
do not extend the supported preflight domain.

## Optional center-bound phase and search traversal

The numerical proposal producer is separate from search traversal.
_LaneExpansionContext owns one search invocation's section, lane, root,
query, proof, frozen producer, external witness and two optional caches.
_LaneBoundPolicy carries the already-computed incumbent upper bound, scale,
tolerance and goal for one cell. No context survives a search invocation.
Exact station/scale cache words retain their original owner and query.

_try_lane_center_bound receives the already-paid whole-cell enclosure, which
can be unknown, and the actual incumbent. It retains the selected center,
count guard, reservation order, frozen/ordinary producers, cache updates,
exception propagation and direct mutable node/term counters. A refused
center returns None before reservation or cache changes. An admitted but
inconclusive attempt can return None after consuming work or updating a
cache. Neither case silently restores consumed work.

The producer's named discard, close and support-contract proposals contain
the original lower and support values. The caller retains traversal state.
It discards the same cell, stores the same closed interval, or applies the
same depth guard and enqueues the same contracted support. The nine early
exits retain their predicates, order, alternatives and payloads. The
fallthrough retains the original subdivision path.

The source checker compares the numerical phase as scoped lexical
statements. Nineteen fixed root substitutions retain exact occurrence
counts, token types, statement depth, operand order and member ownership.
A substitution cannot begin after a dot. The nine exits have individually
bound predicate, alternative, lower, support and depth fields. Complete
context, policy, proposal and caller declarations are also bound.

Only four fixed formatter correspondences are permitted: the adjacent
quadrature-error string literals, parentheses around one derivative guard,
and trailing commas at the frozen and ordinary expansion calls. There is
no general punctuation, string, identifier or return normalization.
The comparison reduces 79 old and 73 new phase statements to the same
72-statement representation. Five exact inverse spans restore the complete
pre-extraction source before the earlier four lane inverses run.

The center refusal control uses a real Road with an unknown whole-cell
producer, an inexpensive LINE incumbent, an admitted whole count of
5,000,000,005 and the actual refused selected-center count. It reserves the
whole work honestly; it does not execute SPIRAL quadrature. Its direct phase
call checks unchanged node/term words and empty caches after refusal.
Other controls check ordinary close, inconclusion with a consumed debit,
cache reuse, admission errors and grouped errors after a consumed debit.

This helper witness does not establish reachability through the old complete
search traversal. Source preservation and observable native comparisons are
separate evidence. Neither is a claim that all internal execution traces or
all possible input values have been enumerated. No midpoint fallback or
resource-policy change is introduced.

## Source admission and coverage requirements

Public historical records remain immutable. New authority binds explicit
before/after endpoints, unique inverse spans, unchanged producer inputs,
historical records, real dependency and caller inventories, native sources
and the current resolver/checker inputs. Historical consumers can compare
only a named predecessor after the complete current source is admitted.
Exact-byte consumers retain byte checks. Token-based consumers retain their
existing lexical equivalence, including exact string-token spelling.

Every inherited loop proof retains its reachable True requirement. Unknown
source or resolver variants retain both branch outcomes. The checker is not
a coverage waiver, and passing a helper suite does not establish complete
line, branch, condition or MC/DC coverage. Qualification requires the full
maintained obligation set on one frozen source and generation identity,
the unchanged test and watchdog limits, a genuine combined anatomy report,
and the exact integration-head CI result.
