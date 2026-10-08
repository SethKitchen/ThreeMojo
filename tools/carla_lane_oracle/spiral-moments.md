<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Reproduce the readonly SPIRAL moment coefficients

This stdlib-only Python checker proves **1,408 fixed-count, quadrant-zero ideal
stored-polynomial coefficients and their 2,816 tight binary64 endpoints**. It
reproduces the 22,528-byte readonly payload already used by
`extensions/carla/spiral_moment_table_data.mojo`. It is not a canonical evaluator
or a proof of the actual rounded geometry/error graph, runtime eligibility,
Map integration, generated machine code, or query performance.

## Replay from a clean repository

From the repository root, with Python 3.9 or later:

```sh
python3 -B tools/carla_lane_oracle/spiral_moments.py
python3 -B tools/carla_lane_oracle/spiral_moments.py --check
python3 -B tools/carla_lane_oracle/test_spiral_moments.py -v
python3 -O -B tools/carla_lane_oracle/spiral_moments.py --check
python3 -O -B tools/carla_lane_oracle/test_spiral_moments.py -v
```

Default and `--check` are read-only, including when
`CARLA_LANE_ORACLE_OUTPUT` is set. No packages, network, compiler, native
commands, private snapshots, current working directory, or hidden source-path
environment variables are needed. The script finds the repository relative to
its own tracked location. `--repo-root` explicitly selects another checkout.
The tests use temporary files, but do not write production sources.

Explicit generation writes into a separate output directory:

```sh
python3 -B tools/carla_lane_oracle/spiral_moments.py --generate
python3 -B tools/carla_lane_oracle/spiral_moments.py --generate --output out/moment-review
python3 -B tools/carla_lane_oracle/spiral_moments.py --report
```

The default output directory is `out/carla-lane-oracle`; the existing
`CARLA_LANE_ORACLE_OUTPUT` environment variable overrides it, and `--output`
overrides that. `--generate` emits the canonical `.mojo` data source, packed
big-endian words, all exact fractions, and a JSON report. It can regenerate a
missing/corrupt data file without reading that file, but cannot overwrite the
tracked input data directly. `--report` checks the table and explicitly writes
only the report. `--check --report` is rejected so `--check` always means no
writes. Generation is a review step, not an automatic installation or re-pin.

## Inputs and source binding

The coefficient inputs and selected expression regions come from:

- `extensions/carla/geometry.mojo` (stored GL node and weight arrays)
- `extensions/carla/lane_geometry.mojo` (canonical lane scalar expression)
- `extensions/carla/curve_trig.mojo`
- `extensions/carla/curve_bounds.mojo`
- `extensions/carla/curve_interval.mojo` (complete stored-half dependency closure)
- `extensions/carla/spiral_moment_table_data.mojo` (check mode)

The current source gate also binds the complete canonical accumulation closure:
`curve_sum2`, `spiral_roundoff_proof`, `spiral_domain_proof`,
`spiral_moment_proof`, `spiral_moment_table`, `lane_refinement`, `map` and
`map_builder`, together with the complete `curve_interval`, `curve_bounds`
and `lane_geometry` modules listed above. These are source contracts, not
a mathematical or compiled-runtime qualification of every consumer.

`spiral-moment-pins.json` records all 32 stored binary64 GL/trig array constants,
the five rounded `1 + node` words, four scalar phase/reduction constants, and
ten readable operation-graph regions with SHA-256 values. The regions bind
scalar trig aliases/wrappers, scalar and ideal Horner expressions, the scalar
SPIRAL phase/GL expression, and the ideal SPIRAL/trig branch expressions and
selector, plus the uncertainty constructor used by that selector. Each region includes the source text used to derive the identity;
reviewers need not reverse-engineer an opaque whole-module hash.

The `RoadGeometry` and `Road._plan_point` reference routes are separate from
canonical lane geometry. The scalar SPIRAL and trig-alias pins follow the
private lane adapter used by Road lane centers. They do not bind the public
reference evaluator. `spiral-graph-correspondence.json` retains the historical
authored-to-adapter migration, which changed only names, receiver annotation,
source location, comments and formatting. The later approved Sum2 migration
intentionally changes canonical scalar accumulation and its error graph. It
also adds invocation-local refusal for unsupported arithmetic modes. Canonical
fixed-s `Road.lane_transform` and `Map.compute_transform` coordinates can change.
The ideal polynomial, stored constants, rounded node sums and all 2,816 table
endpoints remain unchanged. The verifier stays fail-closed under optimized
Python. Its mutation controls target the canonical helper and guard closure.

This checker does not certify optional roundoff-envelope dispatch, runtime
eligibility and budget guards, or the rounded value/error graph. Those require
their separate source review and native controls; a passing table replay must
not be used as their acceptance result.

Decimal literals are read as exact rational decimals and rounded to binary64
by integer arithmetic. Stored words, including signed zero, must match the
pins. A decimal spelling with the same stored word is accepted. Source blocks
ignore comments/blank lines but retain indentation and operation spelling.
Bodies in the declared canonical dependency closure are bound in full. Other
repository bodies remain outside this gate. The stored-arithmetic dependency
is a complete tokenized module, so every changed helper, import, primitive,
error dependency or qualifier there requires renewed review. Any stored word,
selected expression or top-level routing change likewise requires review; there is intentionally no automatic update-pins mode. These are
scoped source-change detectors, not a Mojo parser, language-semantics proof,
or a guarantee against deliberately editing the proof and all its inputs.

## Reviewed stored-half migration (historical)

The schema-2 source contract added an executed ideal-polynomial correspondence,
not a two-hash refresh. The historical ideal source is retained verbatim in
`spiral-moment-pins.json` and in the appended provenance record. Its SHA-256 is
`270a3cde3b012388ee8fcb6a4ecc59d837d1583f6c406f942ff98fdccd9f5733`.
The reviewed input is composed base
`367d8e03ebc57d69dc7d027279c5ca0f695857b5` plus frozen runtime inventory
`83c3845e325714fbd1db5599735a847954d1492d85b832010e959839024b766c`.
The later unchanged-evaluator goal/lazy composition has inventory
`14cd7ccbf54734b0cf59dc0136eea5c6228ffb4f1a7053cac7910f2ea2775cb4`;
its additional runtime consumers are separate qualification obligations.
That historical stage did not include a compensated scalar evaluator. Its
canonical `_lane_spiral` body, stored constants, coefficient arithmetic, table
bytes and payload words were unchanged. The later schema-3 Sum2 stage below
changes scalar accumulation while retaining the ideal polynomial and table.

At that stage, `ideal_projection.py` compared the two complete selected ideal
function declarations after exactly these transformations:

1. Project exactly five `_stored_half` calls, with ordered arguments
   `step, rate, step, step, rate`, to `argument * Expression.constant(0.5)`
2. Commute exactly two historical `Expression.constant(0.5) * rate` products
   to `rate * Expression.constant(0.5)`
3. Require equality of every remaining AST field, operation, argument, loop,
   type/generic declaration, stored node-sum boundary and result index

The projected graph digest is
`f0f94e038fd4a783b3ed400ffd32801ca0c3bdc54980e2c408d44f50211b9e06`.
Commutation is justified only in the exact real polynomial ring. It does not
claim the old floating-point evaluation order, interval rounding graph,
error graph, compiler contraction, native behavior or eligibility is unchanged.

The helper starts with `value * _JetExpression[derivatives].constant(0.5)`.
Its only subsequent mutation of that result is `result.error`, and every
return is the same result. The projection verifies this property; it does
not itself validate the optimized error bound. `source_contracts.py` also
requires the complete `curve_interval.mojo` token contract from the exact
`stored_arithmetic` path in `runtime-source-pins.json`. This binds the entire
helper, `_JetExpression` constructors and operators, `_Interval` operations,
rounded-value/error operations, tight/directed endpoint routines, residuals,
range tests, roundoff bounds, bitcast and math import routes. It retains every
Mojo qualifier and decorator. Because this module imports only standard
library primitives, there is no unbound repository helper beyond that module
in the new stored-half closure. Standard-library and builtin semantics,
including binary64 rounding, `fma`, `isfinite`, `bitcast`, and compiler behavior,
remain explicit native/toolchain assumptions rather than claims of this check.

The error optimization is provenance-specific. Finite ordered ideal intervals
and finite nonnegative inherited error are required before considering the
fast path. The absolute rounded operand must lie between bitcast exponent
bounds 623 and 1423 (inclusive), corresponding to `2^-400` and `2^400`.
Otherwise the original product error is retained. Within that reviewed
stored-operand domain, halving a binary64 operand is exact; inherited error
is bounded by the outward interval product with one-half. These conditions
are source-bound here. Their mathematical/native justification and approved
call sites beyond this ideal function remain separate review obligations.

Complete top-level routing/declaration token records bind caller, trig, stored
GL geometry and canonical scalar imports, aliases, signatures, decorators, function inventory,
ordering and other top-level statements. Separately word-checked constant
right-hand sides are represented by their names in this routing contract only
after validating the complete actual top-level logical declaration. Each array
RHS must be exactly the checked bracketed literal; each scalar RHS must be
exactly the checked `Float64` literal constructor. Each element/argument is one
decimal NUMBER token, optionally preceded by one unary sign. Conditional
alternatives, concatenation/indexing, executable suffixes, adjacent number/name
tokens and empty array elements are rejected. Alternate decimal spellings with
the same stored words, whitespace and comments remain accepted. Declarations
quoted inside a docstring cannot substitute for the live declaration.
Missing, additional, redirected or shadowing declarations/imports fail closed.
Fixed hard-coded path/key sets and block sentinels cannot be redirected by a
pin edit. Starts/ends must be unique and top-level, correctly ordered, and
correspond to actual top-level declaration/import/decorator token starts outside
strings, comments and indented bodies, and include relevant decorators.
`_curve_sincos` now explicitly includes its
`@no_inline` decorator. Historical provenance is appended, never rewritten.

The 34 existing tests remain, with only fixture dependencies and the equivalent
formatter-aware ideal-node mutation target adapted. Additional fixed-pin
controls mutate helper factors/operands/inherited error, both exponent bounds
and comparisons, every fallback class, dependency primitives/imports/qualifiers,
caller placement/arguments, pre-rounded nodes, scalar operand order, routing,
block boundaries and pin keys/paths. Review-driven controls also cover array
and scalar docstring decoys, full-RHS alternatives, GL shadow/import routes,
function-sentinel decoys and malformed adjacent literal tokens. Each negative checks its intended
rejection and nonzero CLI result; unchanged and benign-comment/equal-word
controls pass. Both normal and optimized Python run the same tests. Neither
these source controls nor the exact coefficient replay substitutes for the
separate runtime support/translated-consumer source gate, native tests,
coverage, whole-query station accuracy, termination or performance.

## Reviewed canonical Sum2 migration

The current schema-3 contract includes the compensated canonical SPIRAL graph.
`sum2-correspondence-migration.json` preserves each earlier binding and records
the reviewed transitions. It never describes the new accumulator as
operation-identical to ordinary summation.

The ideal projection first requires the exact invocation-local environment
check. Its refusal branch returns unknown value/derivative intervals and
infinite error. On the supported branch, it accounts for exactly four M/E
state declarations, two immutable term definitions, four outward updates and
two scalar-error writes. It inlines only those two terms and removes only
those reviewed auxiliary/error statements. Restricted uses and fixed statement
placement prevent a value/derivative mutation, loop change or auxiliary escape.
The retained function then passes the historical five-half/two-commutation
comparison above. Its complete projected AST digest remains unchanged.

`sum2_contracts.py` separately binds the original six-operation TwoSum
recurrence and correction update. It proves that `_sum2_error_checked` retains
the initial arithmetic leaf after its function rename. The error formula is
E + (u + gamma_(n-1)^2) M, where E bounds inherited term error and M bounds the
sum of absolute rounded terms. Its count and magnitude guards remain required.
`rounding.py` independently propagates this bound for the finite town controls.
Nearest rounding, gradual underflow, materialized terms, no reassociation and
no intermediate overflow are required. FTZ/DAZ is unsupported.

The full helper and 16 actual caller declarations have a separate lexical
contract in `sum2-guard-pins.json`. It retains every unsafe_offset and volatile
keyword-subscript operation. It checks exact enclosing method ownership,
decorators, class-level bindings and helper import/use routing. No keyword
subscript is erased to make it look like Python syntax. The wrapper controls
exercise both explicitly injected predicate outcomes; they do not execute
native volatile probes or qualify machine-code behavior.

Frozen FullJet and half-only references are retained. Stored coefficients,
1,408 fractions, 2,816 endpoint words, heading and derivative algebra remain
unchanged. Runtime/codegen, whole-query behavior, work limits, coverage and
performance remain separate obligations even when every portable gate passes.

## Exact identity

Assume the existing caller has established a single fixed count `n` in 1..64,
zero stored heading and initial curvature, an eligible unclamped domain, and
quadrant zero for every original GL node. The existing runtime guards remain
mandatory and are not certified by this coefficient checker.

Let `r` be the already-stored Float64 curvature rate, treated as a fixed exact
constant here. Let `q[i]` be the correctly rounded nearest-even Float64 result
of `1.0 + stored_node[i]`. In exact arithmetic, set

```text
beta       = r/2
alpha[p,i] = (p + q[i]/2)/n
M[k,n]     = sum(p=0..n-1, i=0..4) w[i]*alpha[p,i]^(2*k)/(2*n)
u          = beta*d^2
X(d)       = d   * sum(j=0..10) COS[j]*M[2*j,n]   *(u^2)^j
Y(d)       = d*u * sum(j=0..10) SIN[j]*M[2*j+1,n] *(u^2)^j
```

This is the algebraic distribution of the **stored** GL/trig polynomials,
not ideal sine/cosine, fitted quadrature, or Fresnel integration. At quadrant
zero, both range-reduction products are zero. With `t = alpha*d`, the literal
phase is `t*(beta*t)`. The cosine terms have bivariate powers
`d^(4*j+1)*beta^(2*j)`; sine terms have
`d^(4*j+3)*beta^(2*j+1)`. Therefore no terms beyond the 11 coefficients per
side are dropped; the station degrees are exactly 41 and 43.

In particular:

```text
M[0,n] = sum(stored weights)/2
       = 36028797018963971/36028797018963968
       = 1 + 3*2^-55
```

It must never be normalized to 1. The stored `1 + node` rounding must occur
before any moment arithmetic. It is not generally the exact rational sum of
1 and the stored node.

The implementation accumulates exact unscaled prefix sums
`S[k,n] = sum(p<n,i) w[i]*(p+q[i]/2)^(2*k)`, then divides by
`2*n^(2*k+1)`. This shares algebraic work between counts without changing the
formula. All arithmetic is Python `Fraction`/integer arithmetic. The tests
independently distribute the literal expressions in a sparse bivariate
polynomial ring for all 64 counts, comparing every coefficient exactly;
they do not call the moment implementation for that derivation.

## Endpoint proof and byte contract

For positive exact fraction `x`, integer comparisons find `e=floor(log2(x))`.
The local binary64 spacing is `2^max(e-52,-1074)`. Exact integer division
finds the greatest representable value at or below `x`. The upper endpoint is
either that same word (when exact) or the next word. Negative bounds reverse
the positive pair; exact zero is represented as `[-0,+0]`.

For every generated coefficient, the checker decodes the words to exact
fractions and verifies:

```text
low <= exact <= high
next_up(low) > exact
next_down(high) < exact
```

These prove greatest-below/least-above minimality, allowing equality at the
endpoint. Nearest-even rounding of source literals and `1 + node` is selected
by exact distances and the even significand bit. Tests cover normal/subnormal
binade boundaries, ties, both signs, signed zero, and rejection of nonfinite
or overflowing values. A separate host `float`/`nextafter` route checks every
one of the 2,816 table words; it is not used to generate them.

The source format is fully canonical, including the generated header, count
labels, uppercase hex words, ordering and final newline. Each array element
has its own line, as in the retained Mojo formatter output. Check mode rejects
changed words, missing/extra words, incorrect shapes, malformed declarations,
additional executable source, and same-word noncanonical formatting. It does
not claim byte identity when only words match.

Canonical data-source SHA-256:
`63b07b8aa1567ad3e1c8b09a71e5619073e5255b4dc6f733d4ef6bf6b7088c8c`

Packed big-endian payload SHA-256:
`72f5e5d09a6f4091e1a537aa89bf80493a427576b5ff86619830721edbc5f446`

## Provenance and qualification limits

`spiral-moment-provenance.json` records the prior artifacts by content hash;
those historical artifacts are not needed for replay. The portable replay
was checked against all 1,408 exact fractions and all
2,816 endpoints of the prior qualified readonly-table artifact. The table
payload hash above is also frozen independently in the Python tests. The
initial portable data migration changed only its comment header. The later
formatter-layout migration puts each low and high word on its own line.
It changes only whitespace inside the declaration and preserves all 2,816
words in the same order. The generated source matches the retained formatter
output byte for byte. The provenance file keeps both migrations. No existing
native numerical fixture is regenerated or relaxed.

The prior standalone table qualification reports 107 focused native tests
passing in each of default and contraction-off modes. A pinned accessor probe
observed 22,528 bytes of readonly data and two scalar loads rather than a table
copy. Those are retained prior observations, not new native results from this
checker, and do not certify later callers or whole-map performance.

The earlier count-22 fixture with station 19, length 20 and end curvature .1
has mixed quadrants and must still be rejected by the quadrant-zero shortcut.
Exact coefficient identity alone does not make that station eligible. The
separately retained eligible count-22 control and original rejection fixture
must both remain unchanged.

This proof does not replace stored-rate/step/node/phase rounding error,
permitted FMA analysis, clamp/count/quadrant guards, original full-domain
scalar error, heading/offset/elevation/translation arithmetic, interval-jet
roundoff, witness selection, query work budgets, fallback behavior, index
ownership, or native correctness/coverage/performance gates. It grants no new
finite scalar-error certificate to an expansion helper. Python success is
only the fixed polynomial identity, input-source binding and endpoint replay
claimed above.
