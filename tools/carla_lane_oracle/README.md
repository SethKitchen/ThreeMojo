<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Independent town lane controls

Run these controls with Python 3 and mpmath 1.3.0:

    python3 tools/carla_lane_oracle/oracle.py
    python3 tools/carla_lane_oracle/rounding.py
    python3 tools/carla_lane_oracle/poses.py
    python3 tools/carla_lane_oracle/counts.py
    python3 tools/carla_lane_oracle/translated_parameter_resolution.py

The reports go to `out/carla-lane-oracle`. Set `CARLA_LANE_ORACLE_OUTPUT`
to choose another directory. The scripts do not run Mojo or change source.

Reports label earlier measured query outputs as retained observations.
They do not claim a new native run.

The source hashes bind the proofs to the reviewed evaluator and town fixture.
A later evaluator change requires proof review, not a blind hash update.
The road hash starts at the first import, so module commentary can change.
`constants.json` preserves the native-exported binary64 constants as both
hexadecimal values and exact fractions. The source pin checks the quadrature
nodes and weights; rounded `1 + node` values are checked independently.

The canonical scalar graph is now the private `lane_geometry.mojo` adapter
called by Road lane centers. RoadGeometry and Road._plan_point reference
routes remain separate evaluators. Canonical fixed-s lane_transform and
compute_transform positions use the canonical accumulator. `canonical-source-correspondence.json` records the
reviewed authored-to-adapter operation correspondence, retained table/constant
inputs and unchanged oracle arithmetic. Whole-file source binding includes
that canonical module; the Road scope is its actual first import, regardless
of which helper is imported first. Source-pin failures remain explicit under
optimized Python, although the mathematical scripts should still be run with
the documented normal Python commands so their arithmetic assertions execute.

The pose script differentiates the unchanged stored center expression. Main's
finite-input/refusal guards and scale-safe final pose angles have separate
native controls; the source correspondence does not claim byte-identical
public pose arithmetic. The optional roundoff envelope and query shortcuts
also need their own runtime/certificate/budget qualification.

`oracle.py` uses exact rational coefficients and Gauss-Legendre moments.
It checks derivative signs, convexity perturbations and root brackets.
High-precision mpmath values display the roots; they are not substituted
for the exact rational sign checks.

`rounding.py` bounds the full rounded operation graph, including quadrature
count transitions, ARC quadrant and sinc transitions, and permitted FMA
contraction. It distinguishes ideal smooth values from operation error.
It does not assume that rounded evaluation is continuous.

`poses.py` differentiates the stored center expressions and independently
reconstructs the small sampled parabola tables.
`counts.py` derives the gentle-circle and mesh counts and enumerates the
26 town lane groups. The town index total is a retained native observation,
not an independent scalar-count proof.

These controls establish the specific ordinary fixtures described in
`docs/wiki/CARLA-lane-correction-controls.md`. They do not certify arbitrary
maps or replace native suite, coverage or performance gates.

`translated_parameter_resolution.py` needs only the Python standard library.
It proves the exact translated road-s construction limit with integer and
Fraction arithmetic. It also checks the positive nonterminal sampling step
that rounds to unchanged s. Its separate source pin covers the relevant
methods and fixture helper. It does not replace native refusal regressions.

## Runtime source-correspondence migration (2026-10-06)

The portable runtime checks are independent, fail-closed contracts:

    python3 -B tools/carla_lane_oracle/check_sampled_values.py --repo-root .
    python3 -B tools/carla_lane_oracle/spiral_moments.py --repo-root . --check
    python3 -B tools/carla_lane_oracle/check_runtime_support.py --repo-root .

The unchanged `make test-tools` target discovers their maintained test suites.
The new runtime test suite invokes the separate support gate on a passing
candidate before mutating any input. Run the same commands/tests with `-O`
as an additional fail-closed check. They never compile or run Mojo.

### What is proved by source correspondence

The eight earlier full/value copies still match. The primitive class and its
actual full/value aliases are unchanged. The additional sinc and ARC copies
preserve complete operations, guards, coefficients, result order and error.
The constant-heading projection preserves the returned coefficient enclosures
and zero scalar error; it changes only two derivative constructor fields per
result from zero to whole intervals. Value-only consumers cannot read those
fields. The target now has exactly 17 helpers, with exact ordered imports,
no executable top-level statements, preserved decorators/types/generics,
and no derivative-field/flag reads.

The lane comparison parses complete functions. It accounts for all 23
full-lane statements: 14 setup/record/width statements are retained; exactly
three capture assignments are removed; the complete ARC and LINE branches
move, in order, under `all_geometry`; the proof/capture dispatch is replaced
by the explicitly kind-guarded sampled path; the original trig and final
return remain. The full reference dispatcher has 12 accounted statements:
the three complete non-sampled branches are removed under an explicit
sample-kind guard. The broad SPIRAL wrapper retains the exact full-Jet call
and three `_without_derivatives` conversions. Sampled/broad specializations
are respectively False/True. No arbitrary prefix or tail source cut remains.

`curve_interval` is now a complete independently bound dependency of both
the sampled and moment checkers. This includes `_stored_difference`,
`_stored_half`, `_stored_blend_error`, `_without_derivatives`, primitive
interval/roundoff implementations and their import routing. Token binding
retains every qualifier; sampled AST normalization additionally checks a
qualifier-position signature. Benign commentary and the existing target
redundant-grouping control remain accepted. The previous AST-normalizer
limitation concerning `comptime` therefore no longer silently passes.

### Mathematical evidence and its limits

The stored-half ideal projection proves equality of the exact-real SPIRAL
polynomial, not equality of the floating-point error operation graph. The
scalar evaluator, stored arrays, table, coefficient derivation and its
independent 34 tests remain unchanged. Historical graph provenance is retained.

The maintained Fraction controls derive the shared-rate blend identity
`(a-b)*er + b*ec + ep + eq + ez`, check separate and either-product fused
rounding, and cover endpoint-supported broad intervals with subnormal
interior rates. They also independently test exact supported binary half
scaling, Sterbenz subtraction and inherited-error counterexamples. These
are algebra/premise controls, not an interpreter proving every production
outward interval operation or every call-site provenance condition.

The prior station evidence supplies a restricted stored-constant ARC
argument and independent blend controls. Its older `production-bindings`
receipt is not certification of this later composition. Full helper error
mathematics/call-site provenance, compiler contraction behavior and all
translated/goal/lazy native behavior remain separate review obligations.
Passing source checks cannot substitute for those missing qualifications.

### Separate runtime dependency gates

`source_contracts.py` and `runtime-source-pins.json` bind exact complete module
tokens for six declared groups. The fixed group/path sets reject missing,
extra or redirected dependencies. They have no hash-refresh command.

- Stored arithmetic: full primitive/error/helper module, including qualifiers
- Eligibility: domain proof, original node/quadrant guards, table accessor,
  roundoff envelope, ARC/LINE support contexts, their primitive record/constant
  dependencies, coefficient words and trig source
- Translation: full bound dispatch, proof construction, frozen ARC translation,
  refinement consumer, X/Y signs, infinity error sentinels, zero final query,
  ideal-versus-rounded error validation and original full-domain error use
- Support: map/refinement consumers, lane/junction selection, count bounds,
  two-count joins, accumulation bounds and charged work

These are source-integrity controls of the enumerated modules, not a claim of
transitive whole-repository/compiler validation. Shared external type/runtime
semantics, native safety, performance and full coverage remain separate.
A table-only PASS makes no claim about these runtime-support paths.

Mutation suites freeze the successful pins and then change helper operands,
factors, inherited errors, guards, matched full/value expressions, wrappers,
aliases, derivatives, translation signs/errors, fallback and support/count/work
limits. Positive controls prevent stale-pin or always-rejecting vacuity.
`runtime-correspondence-migration.json` preserves the old reference hashes and
the frozen numerical/composed source identities. Updating source and pins
together is never evidence of correctness.

### Heading-only proof-consumer checkpoint

A later, separately reviewed six-site delta imports `_stored_half` and uses
it in the three proof-consumer heading expressions. Each rate is the identical
stored `_Jet.constant` scalar used by fresh bounds. The ideal `u` expressions
and original quadrant-eligibility phase are unchanged. This restores the fresh
heading's value/derivative/error source graph; it does not authorize replacing
all half products in those modules.

`heading_correspondence.py`, invoked by the separate runtime-support gate,
compares each complete heading/rate expression to the fresh SPIRAL expression
with only local `k0` expansion and generic-to-full-Jet name specialization.
It separately requires unchanged ideal `u`, exactly one helper call per heading
consumer, and the original eligibility graph. Fixed-pin and semantic controls
reject stale heading halves, changed stored rates, or moving the helper into
ideal `u` or eligibility. Exact before/after hashes and the previous seven
scoped token bindings are retained in the migration provenance. No coefficient
or canonical scalar change is included. This remains a source checkpoint with
separate native/full-coverage/performance gates.


## Canonical Sum2 checkpoint (2026-10-06)

Canonical SPIRAL now sums rounded weighted terms with streaming Sum2. It starts
both state fields at positive zero, applies the six-operation TwoSum residual,
adds that residual to correction, and rounds high plus correction before the
world origin. This intentionally changes canonical scalar positions. It is
not operation-identical to the historical ordinary accumulator. The separate
RoadGeometry and Road._plan_point reference paths are unchanged. Canonical
Road.lane_transform and Map.compute_transform positions can change at fixed s.

The bound is E + (u + gamma_(n-1)^2) M. E bounds the sum of inherited term
errors. M bounds the sum of absolute rounded terms. The positive-zero first
update is exact in real arithmetic. Count one therefore returns E. Zero
magnitude also returns E. The supported proof range is count 1 through 2^30,
finite nonnegative M at most 2^900, and finite nonnegative E. Other ranges
return an unknown bound in production. This does not relax query tolerances.

The source is Ogita, Rump and Oishi, Accurate Sum and Dot Product,
Algorithms 3.1/4.1 and Proposition 4.5:
https://www.tuhh.de/ti3/paper/rump/OgRuOi05.pdf

This proof requires nearest rounding, gradual underflow, materialized rounded
terms, no reassociation, and no intermediate overflow. FTZ/DAZ is unsupported.
`rounding.py` uses an independent exact-rational term-error/magnitude analysis
and the Sum2 theorem. It no longer carries the old flushing allowance into
this proof. Ordinary term and final-origin arithmetic still receive explicit
roundoff propagation. No pointwise improvement over ordinary summation is
claimed.

`sum2_contracts.py` checks the complete reviewed helper, scalar caller,
uniform envelope and envelope eligibility declarations semantically. It
checks direct imports, shadowing, decorators and operation order. Literal
expected declarations are reviewed source contracts, not compiler models.
The ideal bridge admits exactly four M/E declarations, two immutable term
definitions, four outward auxiliary updates and two final scalar-error writes.
It proves that the surviving complete generic function equals the frozen
half-only ideal graph. An auxiliary cannot affect value, derivatives, loops,
branches or another function. All five stored-half calls remain bound.

At the initial Sum2 checkpoint the fifth dependency group bound curve_sum2,
lane_geometry, curve_interval, curve_bounds and spiral_roundoff_proof in full.
The sampled, moment, runtime and canonical oracle gates invoke it. Existing
trig, stored-word, complete sampled-reference and runtime-eligibility checks
retain their separate scopes, including same-word literal spelling controls.

The station's five-test `test_sum2_oracle.py` is preserved as a self-contained
maintained oracle with 100 embedded native term pairs. Additional tests cover
range/count/zero controls and 49 fixed-pin attacks. Each attack is also checked
by the semantic bridge without a digest rejection. The tests use unittest
checks under normal and optimized Python. The new rounding checks are also
explicit under optimized Python. Other legacy algebra scripts retain their
normal-Python arithmetic assertions, so their optimized replay only confirms
execution and source-gate behavior.

`sum2-correspondence-migration.json` preserves prior records and appends the
initial reviewed checkpoint. The later format/doc event records the final source binding.
All 1,408 exact fractions, 2,816 endpoint words and the generated table SHA
63b07b8aa1567ad3e1c8b09a71e5619073e5255b4dc6f733d4ef6bf6b7088c8c remain fixed.
Source checks do not qualify native code generation, public query behavior,
work budgets, coverage or performance. The global anatomy report must be
regenerated from the eventual final source; its old binding is expected stale.


### Actual-declaration correction

The standalone semantic Sum2 check selects the unique actual top-level parsed
functions for both the ideal caller and stored-half helper. It never selects
those functions with a raw source regex. Six additional regression tests cover
frozen function decoys inside docstrings, legal declaration whitespace, helper
decorators, redirected imports and rebinding. The earlier complete token gate
already rejected the decoy attack; this correction makes the independent
semantic path reject it too. Its old checkpoint and failure reproduction remain
in the migration history. The oracle subtree now contains 223 tests.


## Invocation-local arithmetic-mode guard checkpoint

Guarded source manifest v2 has SHA256
98933650efb2cad39d62a4fe1ddc18c35331cd79dac3fb8b021284148f6b6109.
This is the retained semantic checkpoint. The final formatting and public
documentation lineage is bound by the schema-2 guard contract and appended
migration event.

The production guard uses three volatile UInt64 loads, two nearest-even tie
probes and a gradual-underflow residual probe. It does not change the thread's
FP mode or cache success. It can set sticky exception flags. The canonical
sum starts only after a live check. Fresh expression bounds return unknown
fields on refusal. Cached proof reuse is checked in the current invocation
before record/profile selection. Optional construction and moment expansion
paths decline. Public build/query/refinement entry points raise on refusal.

`_sum2_error` checks the live predicate before delegating to
`_sum2_error_checked`. The latter preserves the initial reviewed arithmetic
leaf exactly after its function rename. Its direct generic-expression caller
performs the same invocation-local check before accumulation. The private
cached `_spiral_proof_branch` relies on the bound `_lane_jet_model_proof` caller
precondition; it is not a standalone checked entry.

`sum2_guard_contracts.py` binds the entire helper token graph and 16 complete
caller declarations in nine consumer modules. It selects actual lexical
function spans, not raw text sentinels. The complete unsafe_offset and volatile
keyword-subscript operations stay present. They are not converted into an
ordinary Python subscript or erased. Import/declaration routing and every use
of protected helpers are checked. The canonical dependency group now covers
all ten changed production modules plus curve_interval.

The ideal projection is conditional on the exact successful fresh check. Its
complete false branch returns unknown value/derivative intervals and infinite
error. The sampled no-proof specialization removes only the exact cached-proof
refusal branch, whose proof condition is false for that route. Its remaining
23-statement construction, original copies and full-Jet SPIRAL bridge remain
checked.

Two tests execute the actual reviewed wrapper ASTs with explicit alternating
false/true predicate outcomes. Refusal cannot call the arithmetic leaf, and a
success forwards all three arguments unchanged. These are injected-predicate
controls, not native execution of volatile loads or FP-state changes. The 47
new environment tests include 39 fixed-pin plus separate token/semantic
mutations, barrier/alias controls and strict schema checks. The oracle subtree
contains 272 tests. The additional binding regressions cover both import forms,
local function/class declarations, wildcard imports and rebinding.

The translated construction model remains conditional on guard success.
`_create_segments` differs only by the leading check. The lane dispatcher
adds only its raises qualifier and refusal documentation. Removal of those
exact deltas reproduces each historical method's bytes. No construction
arithmetic was silently repinned.

Full native FP-state behavior, materialization and optimizer realization remain
separate gates. These source tests do not turn a source-name, volatile token or
no-inline decorator into evidence of actual compiled execution.


The guarded method contracts also retain exact enclosing ownership and all
preceding decorators. Their routing check includes class-level methods, fields
and aliases. Additional source-only regressions reject method relocation,
decorator changes and a class-level entry rebind. Complete module pins already
rejected those changes; these controls strengthen the separate lexical check.


### Final formatted and documented source

The final native-input freeze has SHA256
eb64ab48aa4e09ea5c064a8ad7c7801bb7c04fdf5a14c7f61494ba8186930aef.
The reviewed format manifest and public-doc receipt are recorded separately.
An independent comparison retains exact keyword-subscript operands, move and
qualifier positions. The four public documentation changes alter actual
Raises docstrings only. Every other token, including operational strings,
remains unchanged. Source bindings have been refreshed only after these
checks. Native execution, coverage and performance evidence stays separate.

### Optional runtime dependency migration

`optional-runtime-migration.json` records the selected eight-file source
manifest, previous pin hashes, proof-packet hashes and each changed dependency.
The canonical Sum2 helper, table pins, primitive graph and historical reference
and shared-function graph constants stay unchanged. The reference checker
removes only the verified default-false `require_reuse` parameter and its exact
unknown-result branch. The moment routing check removes that same parameter.

The optional runtime dependency group covers all five new modules and their
producer/caller dependencies. `optional_runtime_contracts.py` separately checks
fresh guards, standalone model ownership and scale, the same ideal/error/witness pairing,
stored dispatch predicates and indices, deferred splitting, original budget
reservations and the complete grouped-count debit. The checked error edge is
raw grouped envelope to private origin error to the checked Sum2 leaf. The raw
entry checks the environment on each invocation. Grouped reconstruction must
use `require_reuse=True` to prohibit an unreserved GL fallback.

The guard checker binds 29 complete caller declarations in 14 modules. Its
additional global production sweep records all actual protected helper and
source-module uses. The sweep binds import/declaration routing and protected
NAME-token ordinals. The complete caller and dependency contracts bind the
function operations. New direct, aliased, wildcard and module imports need
review, including imports in new namespaces and package initializers. The
sweep excludes test, example, bench, tool, asset and coverage-tool namespaces.
It is a static source-integrity gate, not a general dynamic-call analysis.

Mutation fixtures select actual function spans and match executable tokens.
They accept formatter wrapping and trailing call commas. Formatter changes to
production bindings still require an explicit reviewed rebind and rerun.
Source checks do not establish native floating-point behavior, mathematical
soundness, coverage, performance or final CI success. Native checks and final
report generation use the final production and test inventory separately.


The historical immediate-followup and cached-closure successors are retained
in the migration records. The standalone model module retains complete source, fresh invocation guards
on construction/restriction, owner/scale/error checks, and exact/one-short
integer admission controls for `_objective_followup_room` and
`_objective_recheck_room`. These model helpers are no longer called by the
production solver.

Stored dispatch with one or two cuts still admits `3*c+2` nodes and `16*c`
terms, then charges the original one setup node and `8*c` probe terms. Grouped
work still requires two remaining nodes before its optional one-node attempt.
These bounds reserve immediate children and mandatory rechecks. They do not
promise completion of every remaining search under arbitrary custom budgets.

### Containing-objective-model reuse removal (2026-10-07)

The active solver no longer imports, retains, captures or restricts a
containing objective model. A retained ancestor's wider error floor could
make ordinary continuation exhaust default budgets. The original reference
work debit now immediately precedes the current cell's full producer. The
standalone objective-model module and its tests remain, as do the exact
station/scale expansion memo, all node fees, work/depth caps and other solver
operations. The map change is commentary only; its complete token pins stay
unchanged.

`containing-model-removal-migration.json` records the exact two-file freeze,
formatter receipt, former pin hashes, three-node AST removal projection,
four changed lane-refinement dependency bindings, and the single changed
complete caller/routing/inventory entry. It retains all twelve removed
caller-only mutations verbatim and the prior semantic block as historical
evidence. Existing migration histories are preserved with successor links.

Replacement semantic controls reject objective-model imports, aliases,
re-exports and consumers anywhere in production, including new namespaces
and package initializers. They require the original prepaid fresh cell
producer, reject stale-domain substitution and early cached closure, and
retain both complete exact station/scale expansion memo paths. Comments and
docstrings cannot manufacture a consumer. The full model helper dependency
and all 29 complete guard caller declarations remain bound. No checker can
refresh pins automatically.

These controls establish source integrity and the reviewed scheduling removal,
not native behavior, coverage, performance or final CI qualification. Separate
runtime diagnostics still have 19 default driving cohort failures; removing
this optimization does not establish default-budget success for every query.
