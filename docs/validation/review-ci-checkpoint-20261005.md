# Reviewed integration checkpoint, October 5, 2026

This checkpoint preserves the authored building work in [#655](https://github.com/SethKitchen/ThreeMojo/pull/655), merged animal work in [#607](https://github.com/SethKitchen/ThreeMojo/pull/607), and the 18 implemented issues in [#632](https://github.com/SethKitchen/ThreeMojo/pull/632). It adds their reviewed corrections without rewriting the parent histories. Remaining issue work is paused; [#594](https://github.com/SethKitchen/ThreeMojo/pull/594) remains held.

## Current source and report

The update incorporates main's [#669](https://github.com/SethKitchen/ThreeMojo/pull/669) changes through a history-preserving merge. Its parents are the prior #632 head `c9908aca01bc9299c9e7b3a0f5d61eba9dcad417` and main `77b38aeb00c8a877be0f44d5b75daf0ddd1600b3`.

The source contains 2,215 bound inputs. Its digest is:

`7da9ab9c510810d311a4ef8a0f0aa513c8e6d3180269cfd1a5124b2c728757b2`

The fresh [anatomy report](anatomy-template-report.json) has SHA-256:

`c0c01eb11731ebf3dd9a35327cf22f631944e14fba057acc055453d8fdfb45b5`

The pinned Mojo 1.1.0 (`8189361e`) build and full report completed in 66.67 seconds. All 8,911 catalog pairs were checked, with zero omitted and 8,446 additional diagnostic rows.

**The report still contains 367 unallowlisted sampled-overlap findings.** All diagnostic content is unchanged from the prior report; only build provenance changed. Completing the checks does not establish anatomical validity. The findings remain tracked in [#595](https://github.com/SethKitchen/ThreeMojo/issues/595). Visual and rig mapping remains in [#297](https://github.com/SethKitchen/ThreeMojo/issues/297). Sampled fields do not prove clearance or engineering or clinical validity.

## Main conflict resolution

The SDF union retains coordinate lookup and the owner self-copy guard from main. It preserves deterministic lowest-block fallback ownership and both authored test additions. All 36 tests pass. Fresh coverage on that exact mesher source covers 569/569 obligations.

The animal union preserves the new fin, muscle and translated-point tests. It keeps per-component inertia validation instead of a center-dependent tolerance that could admit an impossible tensor. A genuine local-cancellation control and an explicit counterexample cover the distinction. The resolved union passes 100 tests across nine suites, five API checks and 139 documentation files.

## Coverage and CI follow-ups

The coverage additions contain asserted boundary and reference controls. Reviewed redundant checks are simplified. Nonempty-loop annotations follow the repository's documented unreachable-outcome policy, with individual proofs and explicit denominator accounting. These exclusions are not counted as newly exercised paths. Existing thresholds, test workloads, assertions and time limits remain unchanged.

- Math/core/geometry: four changed modules and unchanged Sculptor have complete fresh source-matching coverage. Ten other scoped modules have source-identical diagnostic evidence.
- Loaders and texture formats: five changed modules cover 4,713/4,713 fresh obligations. Eight unchanged modules retain verified diagnostic evidence.
- Renderer: six changed modules cover 11,752/11,752 fresh obligations across 35 captures. The packet also passes 134 compatibility tests and adds 57 controls.
- Extensions: 33 new controls are included. Six animal mass-worker refusal paths remain unhit. Full module coverage is not established.

The diagnostic evidence reconstructs scoped manifests from immutable source and tool bytes, then checks the original missing diagnostics exactly. It is not a substitute for final integrated-head CI. The composed doc-only edits retain renderer executable bytes, but their shifted source locations still require fresh hosted measurement.

On this composed source, all seven repaired API-documentation checks pass. All 37 actual Metal AIR modules pass direct-call type checks. All 442 negative fixtures produce the expected source rejections with unchanged diagnostics and the original 120-second per-case limit. After report regeneration, all 319 Python tool tests, including source binding, and all 48 CARLA Python controls pass.

The prior [c990 CI run](https://github.com/SethKitchen/ThreeMojo/actions/runs/37340945189) passes the unchanged full LOD test in 1.583080 seconds on Linux and 1.027728 seconds on Apple Silicon. Its Linux CPU jobs later time out during other builds. Those inferred stalled import closures are unchanged from successful earlier runs.

Linux CPU compilation now uses one compiler thread while preserving outer suite parallelism. Immediate build/run progress records preserve captured diagnostics and exit propagation. Five mock controls, CI-policy tests and a nine-test native recipe witness pass. This is a bounded scheduling correction; the timeout cause is not proven. Fresh hosted validation remains required.

**Strict full-repository coverage, exact-head aggregate/platform CI and the remaining mass-worker gaps are still open.** GPU device execution and Apple linker/device parity were not run. This update does not merge #632 into main. #594 remains held.

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
