# Reviewed integration checkpoint, October 5, 2026

This checkpoint preserves the authored building work in [#655](https://github.com/SethKitchen/ThreeMojo/pull/655), merged animal work in [#607](https://github.com/SethKitchen/ThreeMojo/pull/607), and the 18 implemented issues in [#632](https://github.com/SethKitchen/ThreeMojo/pull/632). It adds their reviewed corrections without rewriting the parent histories. Remaining issue work is paused; [#594](https://github.com/SethKitchen/ThreeMojo/pull/594) remains held.

## Current source and report

The preceding integration incorporates main's [#669](https://github.com/SethKitchen/ThreeMojo/pull/669) changes through a history-preserving merge. That integration's parents are the prior #632 head `c9908aca01bc9299c9e7b3a0f5d61eba9dcad417` and main `77b38aeb00c8a877be0f44d5b75daf0ddd1600b3`.

The current source contains 2,217 bound inputs. Its digest is:

`b0aca4b04f79fed6528182e470ce72bcfc77be52033f31406a23862e0ac0551a`

The fresh [anatomy report](anatomy-template-report.json) has SHA-256:

`5bc0bf47a672c933a409f7929c01c6152fef9f4c9a6caa8b7fd1c7d20f240020`

The pinned Mojo 1.1.0 (`8189361e`) build and full report completed in 61.61 seconds. All 8,911 catalog pairs were checked, with zero omitted and 8,446 additional diagnostic rows.

**The report still contains 367 unallowlisted sampled-overlap findings.** All diagnostic content is unchanged from the prior report; only build provenance changed. Completing the checks does not establish anatomical validity. The findings remain tracked in [#595](https://github.com/SethKitchen/ThreeMojo/issues/595). Visual and rig mapping remains in [#297](https://github.com/SethKitchen/ThreeMojo/issues/297). Sampled fields do not prove clearance or engineering or clinical validity.

## Composed formatting and compiler diagnostics

The Linux and Apple lint jobs on `5d9dbe20` both identified one formatting difference in `render/texture.mojo`. The repair moves only the closing delimiter of the `_scaled_footprint` docstring. Its words, imports and executable bytes are unchanged. The canonical repository formatter check passes all 2,106 selected files, and the texture API check passes. All 65 Mojo files changed during composition were also checked; the other 64 are unchanged.

The prior [d15 Linux CPU job](https://github.com/SethKitchen/ThreeMojo/actions/runs/37365729726/job/111950286919) reached its original two-hour limit despite one compiler thread. It records 83 build starts and 79 build/run completions. Four builds remain unfinished: `test_audit_regressions`, `test_carla_physics_bodies`, `test_exact_predicates` and `test_geometry_tools`. The single-thread adjustment did not resolve those stalls. Their cause is not established.

This update adds opt-in Linux CPU compiler diagnostics. Every 60 seconds, it samples bounded metadata for the owned compiler and its best-effort descendants: CPU time, approximate RSS, thread states and wait channels. Readable cgroup OOM counters are shared context, not compiler-specific attribution. Process discovery can race or be truncated; unavailable fields are reported explicitly.

The helper does not capture command lines, process environments, memory contents, stacks or unrelated processes. It does not change privileges, compiler flags, outer suite parallelism, workloads or time limits. Catchable cancellation and compiler exit status are preserved. The diagnostics are disabled outside the explicit Linux CPU opt-in.

The composed recipe passes a bounded real-compiler smoke and all nine exact-predicate tests under the original five-second gate. It emits a live startup sample and successful compiler/build/run exit records. That compile completes before the first 60-second interval, so this smoke does not measure periodic behavior during a long stall. Mock lifecycle/procfs controls cover those collection paths. No hosted-stall fix is claimed.

The full tool suite exposed two mock-repository inventories missing the new helper. Both now include it, and the existing cache-invalidation assertion covers it. No assertion is removed. The complete 342-tool/48-CARLA suites pass with opt-in both disabled and enabled.

The Apple lint job on `17037be` passes formatting, then exposes a fake-cgroup assertion comparing a canonical path with its symlink spelling. The fixture now compares canonical paths, preserving the production mapper. A new Linux-runnable symlink control repeats both the subtree mapping and shared OOM-counter delta assertions. The old assertion fails on that control; the corrected 23 telemetry tests pass. The complete 343-tool/48-CARLA suites pass with opt-in both disabled and enabled. Production code, all 2,217 report inputs and the report bytes are unchanged. Fresh hosted qualification remains required.

The report snapshot binds Mojo sources, report logic and provenance inventory. The additional Makefile/Python/YAML tooling is separately bound by the committed tree and exact file hashes. The docstring change required the full report refresh above; all 367 diagnostic findings remain unchanged.

The preceding 5d9 MAX/no-GPU job compiles the GPU entries, passes 47 host-side cases and checks all 37 actual Metal AIR modules. It performs no GPU device execution. These results remain bound to that prior head; fresh exact-head CI must qualify this update.

## Compiler target discriminator

The preceding `94cff7b` run passes all eight captures and the strict full-repository coverage aggregate: 873 modules, 153,783 lines, 73,572 branch/condition outcomes and 9,474 MC/DC checks, all hit=total. Its total is 236,829/236,829. The GPU-host gate passes compilation, 47 host-side cases and 37 actual AIR modules. Apple lint also passes formatting, 343 tool tests, 48 CARLA controls and all 442 negative fixtures. These are exact results for that preceding head, not transferred checks for this diagnostic update.

That run's Linux lint and three CPU shards reach their unchanged two-hour job limits. The CPU logs contain twelve unfinished compilers with sustained runnable single-thread CPU use and increasing resident memory. Shared OOM counters do not record an event. This observation does not identify a compiler phase or root cause. Lint has no equivalent process samples; its quiet build/doc phase is incomplete, and the exact unfinished source names are unavailable.

The Linux CPU jobs now collect the pinned compiler version, launcher/driver hashes and effective target fields before compilation. The metadata-only target query has finite output and time bounds and performs no source compilation. Unavailable diagnostics are explicit. A small per-shard, per-attempt artifact retains only that bounded JSON for one day, so it can be inspected before the CPU job completes. No environment dump or unrelated process data is collected.

Compiler targets, flags, cache settings, suite concurrency, workloads, job limits and acceptance gates are unchanged. The Linux procfs-specific fixture is gated to that platform; portable timeout and output controls remain enabled. All 356 tool tests and 48 CARLA controls pass in both normal and telemetry-enabled configurations, including the exact artifact path/name/order policy controls. All 2,217 report inputs and report bytes remain identical. Fresh exact-head CI is required, and the diagnostic change is not a claimed stall fix.

## Main conflict resolution

The SDF union retains coordinate lookup and the owner self-copy guard from main. It preserves deterministic lowest-block fallback ownership and both authored test additions. All 36 tests pass. Fresh coverage on that exact mesher source covers 569/569 obligations.

The animal union preserves the new fin, muscle and translated-point tests. It keeps per-component inertia validation instead of a center-dependent tolerance that could admit an impossible tensor. A genuine local-cancellation control and an explicit counterexample cover the distinction. The resolved union passes 100 tests across nine suites, five API checks and 139 documentation files.

## Coverage and CI follow-ups

The coverage additions contain asserted boundary and reference controls. Reviewed redundant checks are simplified. Nonempty-loop annotations follow the repository's documented unreachable-outcome policy, with individual proofs and explicit denominator accounting. These exclusions are not counted as newly exercised paths. Existing thresholds, test workloads, assertions and time limits remain unchanged.

- Math/core/geometry: four changed modules and unchanged Sculptor have complete fresh source-matching coverage. Ten other scoped modules have source-identical diagnostic evidence.
- Loaders and texture formats: five changed modules cover 4,713/4,713 fresh obligations. Eight unchanged modules retain verified diagnostic evidence.
- Renderer: six changed modules cover 11,752/11,752 fresh obligations across 35 captures. The packet also passes 134 compatibility tests and adds 57 controls.
- Extensions: the earlier 33 controls remain. Additional scalar and bounded FIN controls support the complete fresh mass-module measurement below.

The diagnostic evidence reconstructs scoped manifests from immutable source and tool bytes, then checks the original missing diagnostics exactly. It is not a substitute for final integrated-head CI. The composed doc-only edits retain renderer executable bytes, but their shifted source locations still require fresh hosted measurement.

On the preceding d15 integration, all seven repaired API checks, all 37 actual Metal AIR modules and all 442 negative fixtures passed. Those receipts remain bound to that source. After the current report regeneration, all 342 Python tool tests and all 48 CARLA controls pass twice: normal configuration and telemetry opt-in. Source-binding checks are included. Fresh exact-head CI remains required.

The prior [c990 CI run](https://github.com/SethKitchen/ThreeMojo/actions/runs/37340945189) passes the unchanged full LOD test in 1.583080 seconds on Linux and 1.027728 seconds on Apple Silicon. Its Linux CPU jobs later time out during other builds. Those inferred stalled import closures are unchanged from successful earlier runs.

Linux CPU compilation now uses one compiler thread while preserving outer suite parallelism. Immediate build/run progress records preserve captured diagnostics and exit propagation. Five mock controls, CI-policy tests and a nine-test native recipe witness pass. This is a bounded scheduling correction; the timeout cause is not proven. Fresh hosted validation remains required.

**Strict full-repository coverage and exact-head aggregate/platform CI are still open.** GPU device execution and Apple linker/device parity were not run. This update does not merge #632 into main. #594 remains held.

## Final mass validation follow-up

This follow-up is based on the published `d15bb7f225c497e625a930a49aba5757b396003e` source. The exact three-file patch has SHA-256:

`0cb9522df36f129eb9c593250435224e3535782e48401ac9ae92de373c40a5c9`

It removes a proven-impossible upper-index operand and centralizes six finite predicates through shared checked helpers. The negative-index check and local asynchronous refusal handling remain. Independent source and lowered-code review confirms all seven checks remain. Explicit inlining retains the ordinary worker's stack and allocation layout.

Fresh captures from nine included suites, containing 50 tests, cover all 485 mass-module obligations: 265 lines, 182 branch/condition outcomes and 38 MC/DC checks. No historical or remapped hits are used. The qualification-only coarse control is excluded from that complete report. All 51 native cases, including the supplemental control, pass the original five-second limit; the slowest is 151.91 ms. The mass API documentation check also passes.

The denominator moves from 507 to 501 after the reviewed impossible-operand simplification, then to 485 after shared finite validation and the local refusal protocol. No new coverage exclusions or threshold changes are introduced. This is explicit source refactoring, not a claim that the old missing outcomes were exercised.

Complete source obligations do not establish every call-site-specific exceptional geometry path. Safe scalar controls exercise the shared validators. Bounded constructor tests assert ordinary/refusal behavior, and every retained worker call site is hit. Final full-repository CI remains necessary.

The initial centralization prototype regressed local timing by 11.4%; that result is retained. After the reviewed inlining change, the ratio of medians is 1.002670, or +0.27%, relative to published d15 validation. Four measured pairs are faster and four are slower. The median paired ratio is 1.029831. This supports approximate local parity, not a universal speedup or zero-overhead claim. Rare refusal trace/error/unwind cost remains.

The d15 workflow passed Apple CPU suites 2/2 and coverage capture 6/8. Thirteen other jobs failed to acquire hosted runners and never ran code. These prior results are historical, not qualification of this follow-up. Its new exact-head workflow must complete all required checks.

## Review corrections

- CARLA junction endpoints respect the stored road/section bounds. Promoting an observed vehicle preserves its incoming collision locks. The exact original regressions fail on the old implementations and pass with the fixes.
- Snapshot hit distance is a `Length`. Explicit sphere-radius-square rounding removes the reproduced native/instrumented mismatch and fixes exact stored tangents. All 15 validation tests pass under instrumentation. The 517 captured public cases remain byte-identical to the prior native baseline. Seventeen private scalar samples change within one ULP; legacy overflow NaNs remain documented limitations.
- The existing tessellated-floor ghost-contact behavior is reproduced and documented. Its topology correction remains in [#635](https://github.com/SethKitchen/ThreeMojo/issues/635).
- Metal kernel discovery fails closed. Actual emitted AIR checks the output matrix/flag address-space contract. Raw ASTC admission checks the DFD model, with documented returns and malformed-input controls.
- SVG rounding, stored LDraw normals, integer-only constant folding and exactly collapsed rectangle lights have focused regressions. Existing fixtures, tolerances, shader instruction/register caps and render workloads are unchanged.
- The animal review follow-ups correct validation, shared meshing, inertia and reference/calibration contracts after #607 merged. Fourteen safe controls passed. Ordinary sampler results match, with variable observed overhead: medians were 283 ms before and 469 ms after in three paired runs. No no-overhead claim is made.
- Building repairs preserve all 141 authored paths. All 26 repair files match their qualified versions. The building qualification passed 293 ordinary tests in 21 suites; all 11 repaired modules have 100% targeted coverage. This is scoped evidence, not full-repository coverage or structural-design certification.

## LOD performance

A minimal preflight rejects an impossible positive facial budget below 128 before constructing geometry. Spec/detail validation precedence and no-mutation behavior are retained. The original complete LOD workload, including both accepted budgets and the rejected request, is unchanged.

Four balanced measured runs passed the existing five-second gate at 2.803–3.123 seconds, with a 3.017-second median. The old implementation took 3.682–7.221 seconds, with a 5.247-second median and two of four runs over the gate. These local results provide headroom; hosted timing remains a separate check. The rejected mouth-cache experiment is not included.

### Further repair after hosted timing failures

The preflight still took 5.94 seconds in [run 37327561821](https://github.com/SethKitchen/ThreeMojo/actions/runs/37327561821/job/111822068983) and 5.87 seconds in [run 37330440961](https://github.com/SethKitchen/ThreeMojo/actions/runs/37330440961/job/111831843819). Functional assertions passed; the unchanged five-second gate failed.

The follow-up removes temporary copies of validated packed face arrays and uses their known packed mouth-target layout. It also replaces the scalar-indexed 128-lane SIMD traversal stack with an equal-capacity Int32 array. There is no retained cache or pointer. Validation, ownership, triangle order, traversal, geometry and test workloads remain unchanged.

All 52 focused native cases passed across 12 suites. New controls compare complete face arrays and all 39 mouth targets bitwise. The stack control explicitly reaches 128 pending nodes and compares the complete returned query tuple with the original SIMD path. Both new suites are discovered; the production coverage inventory remains 886 modules.

One warmup per variant and four balanced measured rounds used the original complete LOD test. Baseline median was 3.066649 seconds, packed-copy-only median 2.600157 seconds, and combined median 2.356132 seconds. The combined range was 2.308479–2.539037 seconds, a 23.17% local median reduction. All 15 runs passed locally; the local baseline also passed, so these results do not establish hosted success. No retry selection, test split, workload reduction or gate change is included.

The follow-up also passed pinned formatting, documentation lint for all 139 files, and all 318 Python tool tests with inherited MAKEFLAGS. At that checkpoint, a fresh full report bound the LOD source changes. Its diagnostic content and 367 findings were unchanged. Hosted LOD timing has since passed as recorded above; current aggregate checks and full coverage remain required.

## Earlier composed checks

- Pinned formatting check passed for all changed Mojo files
- Documentation lint passed all 139 files
- All 318 Python tool tests passed
- Valid compiler control and both newly shared-unit-sensitive negative fixtures passed with unchanged exact diagnostics; the 442-record manifest is preserved
- All 47 shared-unit tests passed with the unchanged five-second gate
- All 37 actual production Metal AIR modules passed direct-call type checks
- The dedicated new rectangle-parity entry compiled for SM80 with warnings as errors

The GPU entry was compiled only. GPU device execution and Apple linker/device parity were not run. Focused native and targeted coverage results do not replace the final exact-head aggregate/platform CI and full repository coverage.

Main's eight coverage groups, 9,000-second capture budget and 170-minute job timeout are preserved. Existing per-test limits, coverage thresholds and protocol tests are unchanged. Older six-group runs produced billions of redundant probe records and timed out. The c990 run completed all eight capture groups but failed strict coverage on 57 modules. The additions above address those measured gaps, with the remaining extension limits stated explicitly. No new shared probe-cache implementation or gate waiver is included.

Parallel decode early-stop work is tracked in [#668](https://github.com/SethKitchen/ThreeMojo/issues/668). Per-frame facial correspondence validation keeps the mutable-geometry contract; broader ownership/versioning remains in [#306](https://github.com/SethKitchen/ThreeMojo/issues/306).
