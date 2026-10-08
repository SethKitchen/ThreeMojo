# Spatial map resource budgets

`MapBuildBudget` and `MapQueryBudget` (in `extensions.carla.map_search`) are typed, finite, nonnegative policies. Existing calls use the defaults below. Zero forbids that resource; it does not mean unlimited. Constructors validate their inputs, and each operation revalidates the public fields to reject later negative mutation.

## Construction

Pass `budget=` to `Map`, `MapBuilder.build`, `load_opendrive`, or `load_opendrive_file`.

| Limit | Default | Meaning |
| --- | ---: | --- |
| `max_segments` | 262144 | Emitted lane index entries |
| `max_steps` | 4194304 | Cumulative admitted construction operations, including sampling/boundary work, unresolved proof cells, builder record/link scans, conservative sorting reservations, junction certification/conflict work, and sign-query work |
| `max_terms` | 67108864 | Cumulative logical quadrature/evaluator/proof units |
| `max_records` | 1048576 | Source roads, sections, lanes, metadata records and nested samples/links |

Admission precedes sampling, subdivision, bounded queue growth, source-boundary allocation, and segment insertion. Checked subtraction and division avoid overflowing a counter or an intermediate sorting reservation. Optional proof attempts retain their spent work. A ledger latches its own refused reservations; lower refinement failures propagate without returning a map or winner.

The original per-segment chord/cover/proof allowance remains 2000000 terms. Construction requires this much remaining headroom before starting that group, then charges its actual consumption. Consequently a smaller policy can refuse even if an eventual simple proof would have used fewer terms. This conservative compatibility rule prevents global exhaustion from silently changing a proof to its old local unknown-box fallback.

Original local subdivision/accuracy limits remain in effect.

A single builder ledger continues through input preflight, lane linking, sorting, the Map index, junction bounds, conflict pairs and repeated sign-localization queries. Sorting reserves its worst-case comparison count. Source record admission happens before builder mutation. A later failure can consume a builder, as a move-based construction operation, but no partial public Map is returned.

The XML document and the input Road/record containers already exist before building. These policies do not cap XML parsing, input-file size, allocator bytes or exact RSS. They count logical work/storage units. Border records count as source storage; this does not implement or certify the separate unsupported border-only geometry contract.

There is no persistent validation cache that survives public record mutation. As before, changing source road records invalidates an existing Map index snapshot.

## Nearest-lane queries

Pass `budget=` to `certified_closest_waypoint_on_road` or `certified_waypoint`.

The default `closest_waypoint_on_road` and `waypoint` run CARLA's query on CARLA's own segment partition. They take no budget. They perform one R-tree search followed by lane stepping. Input validation, lane stepping and canonical pose evaluation can still raise errors.

| Limit | Default | Meaning |
| --- | ---: | --- |
| `max_candidates` | 4096 | Retained/refined lane candidates |
| `max_nodes` | 1048576 | Cumulative refinement, resumption, strict-classification and selected-pose nodes |
| `max_terms` | 67108864 | Cumulative logical evaluator/quadrature units |
| `max_index_pops` | 1048576 | Spatial index heap pops, including rejected lane types |
| `max_queue_entries` | 262144 | Resident spatial heap entries |
| `max_steps` | 4194304 | Cumulative lookup, profile, heap and candidate/cell bookkeeping units |

`max_steps` is an optional sixth constructor argument; the existing five positional arguments retain their meanings. The R-tree uses one retained frontier and its original distance/tie key order. It no longer repeatedly allocates growing nearest-neighbor prefixes. Admission and strict exclusion are unchanged.

The original 16384-node and 2000000-term **per-candidate** caps and all accuracy/depth limits still apply; raising a global policy never relaxes them.

The same operation ledger covers initial refinement, every resume, the selected public pose, and strict lane membership. Pose validation charges both scalar traversals before evaluating the selected Road transform. It refuses an invalid selected pose rather than substituting another lane.

A builder's sign checks use CARLA's segment query, as `CheckSignalsOnRoads` does. Each check admits its actual R-tree pushes and pops, selected road/section/lane lookups, and strict-successor section scan before performing them. The same-section step preserves the default query's arithmetic.

A short rounded remainder uses an explicit continuation stack for the successor graph. It preserves successor order, immediate return-cycle exclusion and longer-list-first result concatenation. Every frame, key, metadata scan, comparison and result-copy allowance is admitted before that work; longer or zero-progress cycles exhaust the shared construction budget. These calls use the remaining construction-step balance, without imposing certified-query candidate or refinement limits. Spent heap work is retained and the construction ledger remains exhausted after a refused admission.

Exhaustion raises `Error`. `None` still means no eligible lane, or a fully established strict outside result. No partial winner is returned. With sufficient budgets, the geometry algorithm and exact segment-index tie ordering are preserved.

## Optional SPIRAL witness proposals

An optional seed pass can run after an earlier competitor resumption, possibly under another provisional winner. Both the current winner and unresolved competitor need SPIRAL owners. Each complete owner interval must retain one checked exact-range distance recipe.

The attempt prepays 60 fixed eligibility units. Its admission preserves room for saved-cell rechecks, 12 further nodes and 50 root-reference units on each side. These reserves cover the immediate continuation prefix. Later work can still exhaust custom budgets.

A root attempt and at most three narrowed-domain attempts share the original owner reference-work bound. Every optional node and scalar evaluation is charged before execution. Eight dyadic levels propose 255 stored station words through the unchanged scalar evaluator.

Only a strict exact stored-point improvement replaces the incumbent. The caller then rescans the retained candidates and revalidates ordinary winner accuracy before dominance and pose selection. Original owner labels, cells, lower bounds, index ties, tolerances and work/depth caps remain in force.

## Junction scalar-graph composition

The historical analytic junction box is a proposal, including its wide singular/excessive-subdivision fallback. Each complete record span must then be enclosed by the actual canonical lane-expression interval graph. Fully contained cells close immediately; only unresolved or boundary cells split. Every pop and term debit occurs before work.

Finite unresolved boundary enclosures at depth 24 are unioned outward, never replaced with a sampled chord. A nonfinite unresolved enclosure refuses. Adjacent Float64 station cells use their only two representable stations. Both endpoints of every record/sample span are handled separately from its open Float64 interior; singleton and zero-width cells evaluate once.

Ill-conditioned elevation bounds can be intersected with an outward centered expansion of the same stored global cubic coefficients. The original canonical Horner roundoff error is retained. This does not replace scalar evaluation. A future local-coordinate polynomial representation requires a fresh audit.

This proves coverage of stored Float64 road stations and public Float32 lane-center positions. Additional outward boundary enclosures can widen the analytical proposal. The historical 1 cm chord target remains distinct from numerical allowances and resource bounds.

## Reproducible controls

`tests/test_carla_map_budget.mojo` exercises zero/one limits, mutation/overflow, cumulative work, many short records, curved width/high turn, candidate/tie ordering, heap admission, strict boundaries and whole-builder postprocessing. `tests/test_carla_construction_proof_nodes.mojo` specifically covers unresolved quadrature domains, which consume nodes even when they consume no terms.

Build and run `bench/carla_map_budget_bench.mojo` for modest duplicate-lane inputs of 1, 16, 20, 64 and 256 roads. It prints actual work counters, peak logical frontier entries, deterministic winner and elapsed times. Run the executable under `/usr/bin/time -v` for process peak RSS. Timings and RSS are measurements, not a city-scale guarantee.



## Logical step reservations

A step is a documented logical operation or a conservative reservation, not a CPU instruction or nanosecond. Linear searches reserve their maximum visited entries **before** calling the helper. Ordered lane collection separately reserves `N + N*(N-1)/2` for each invocation, with checked product arithmetic. Section-start/end helpers reserve every potential strict-successor scan; equal-start sections still use the original first-strictly-greater boundary rule.

Construction's same-section stepping preserves the public scalar arithmetic and refuses to enter graph recursion.

For a section with `L` lanes, a scalar center reserves two lane-profile passes and a pose reserves four. The chord/cover group reserves `10*L` fixed profile units, with `1+6*L` per admitted fallback proof cell. These are conservative upper bounds; original local proof-node limits still apply.

A continuous-query refinement node reserves `100*L+20` step units. The width11 inventory covers up to three edge centers, 42 local-seed centers, an initial center on the first node and three lane Jets. Their total is `98*L`, conservatively rounded to `100*L`. It also covers 16 bounded node/cell-bookkeeping units and four single-lane accuracy-width lookup units.

Accuracy checks read the selected lane’s width through binary `info_at`; they do not scan all `L` lanes. One such machine-word-bounded binary record lookup is one logical lookup unit. The four units cover the natural, fast and fallback checks. Additional solver centers/Jets or unbounded helper work require a fresh inventory; this is not an instruction-count or time bound.

Eligibility scans, identifier lookups, retained-cell validation/copies, candidate comparisons and heap operations are charged separately before work. This is distinct from the actual refinement-node counter and the quadrature/proof-term counter. A tighter step policy can therefore refuse while those other counters still have headroom.

`tests/test_carla_map_nested_work.mojo` includes the independently identified quadratic-lane-ordering and many-short-section witnesses, using modest inputs and low limits. It verifies refusal before those helpers run, separate predecessor/successor reservations, equal-start sections, unchanged same-section arithmetic, and the sixth query policy's exact boundary and mutation/overflow behavior.
