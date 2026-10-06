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

The only production-source inputs are the relevant tracked portions of:

- `extensions/carla/geometry.mojo` (stored GL node and weight arrays)
- `extensions/carla/lane_geometry.mojo` (canonical lane scalar expression)
- `extensions/carla/curve_trig.mojo`
- `extensions/carla/curve_bounds.mojo`
- `extensions/carla/spiral_moment_table_data.mojo` (check mode)

`spiral-moment-pins.json` records all 32 stored binary64 GL/trig array constants,
the five rounded `1 + node` words, four scalar phase/reduction constants, and
nine readable operation-graph regions with SHA-256 values. The regions bind
scalar trig aliases/wrappers, scalar and ideal Horner expressions, the scalar
SPIRAL phase/GL expression, and the ideal SPIRAL/trig branch expressions and
selector. Each region includes the source text used to derive the identity;
reviewers need not reverse-engineer an opaque whole-module hash.

The main-line reference/fixed-s geometry and canonical lane geometry are
separate operation graphs. The scalar SPIRAL and trig-alias pins follow the
private lane adapter used by Road lane centers. They do not bind the public
reference evaluator. `spiral-graph-correspondence.json` records the reviewed
migration from the authored receiver method to that helper: only receiver and
function names, receiver type annotation, source location, comments and
formatting changed. All operation grouping, literal words, rounded node sums
and 2816 table endpoints are preserved. The verifier remains fail-closed under
optimized Python. Its mutation controls target the canonical helper.

This checker does not certify optional roundoff-envelope dispatch, runtime
eligibility and budget guards, or the rounded value/error graph. Those require
their separate source review and native controls; a passing table replay must
not be used as their acceptance result.

Decimal literals are read as exact rational decimals and rounded to binary64
by integer arithmetic. Stored words, including signed zero, must match the
pins. A decimal spelling with the same stored word is accepted. Source blocks
ignore comments/blank lines but retain indentation and operation spelling.
Unrelated module changes do not trigger a blind whole-file re-pin. Any stored
word or selected expression change requires mathematical review and renewed
controls; there is intentionally no automatic update-pins mode. These are
scoped source-change detectors, not a Mojo parser, language-semantics proof,
or a guarantee against deliberately editing the proof and all its inputs.

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
