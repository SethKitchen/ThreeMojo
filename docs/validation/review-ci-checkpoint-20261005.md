# Reviewed integration checkpoint, October 5, 2026

This checkpoint preserves the authored building work in [#655](https://github.com/SethKitchen/ThreeMojo/pull/655), merged animal work in [#607](https://github.com/SethKitchen/ThreeMojo/pull/607), and the 18 implemented issues in [#632](https://github.com/SethKitchen/ThreeMojo/pull/632). It adds their reviewed corrections without rewriting the parent histories. Remaining issue work is paused; [#594](https://github.com/SethKitchen/ThreeMojo/pull/594) remains held.

## Source and report

The final production source contains 2,191 bound inputs. Its digest is:

`769bd271faa906d4eadc97f5f9c19778767b7fa11cf3788a951de1fdb85e9bbe`

The fresh [anatomy report](anatomy-template-report.json) has SHA-256:

`2ae45667c08e33e4944d609e848cfd0704d96511d8e9f1096c04e303040c6f76`

The pinned Mojo 1.1.0 (`8189361e`) build and full report completed in 92.33 seconds. All 8,911 catalog pairs were checked, with zero omitted and 8,446 additional diagnostic rows. All 23 report and binding tests passed.

**The report still contains 367 unallowlisted sampled-overlap findings.** That set is unchanged from the prior report. Completing the checks does not establish anatomical validity. The findings remain tracked in [#595](https://github.com/SethKitchen/ThreeMojo/issues/595); visual and rig mapping remains in [#297](https://github.com/SethKitchen/ThreeMojo/issues/297). Sampled fields do not prove clearance or engineering or clinical validity.

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

## Final composed checks

- Pinned formatting check passed for all changed Mojo files
- Documentation lint passed all 139 files
- All 318 Python tool tests passed
- Valid compiler control and both newly shared-unit-sensitive negative fixtures passed with unchanged exact diagnostics; the 442-record manifest is preserved
- All 47 shared-unit tests passed with the unchanged five-second gate
- All 37 actual production Metal AIR modules passed direct-call type checks
- The dedicated new rectangle-parity entry compiled for SM80 with warnings as errors

The GPU entry was compiled only. GPU device execution and Apple linker/device parity were not run. Focused native and targeted coverage results do not replace the final exact-head aggregate/platform CI and full repository coverage.

Main's eight coverage groups, 9,000-second capture budget and 170-minute job timeout are preserved. Existing per-test limits, coverage thresholds and protocol tests are unchanged. Older six-group runs produced billions of redundant probe records and timed out; the final workload must still be measured. No new shared probe-cache implementation or gate waiver is included.

Parallel decode early-stop work is tracked in [#668](https://github.com/SethKitchen/ThreeMojo/issues/668). Per-frame facial correspondence validation keeps the mutable-geometry contract; broader ownership/versioning remains in [#306](https://github.com/SethKitchen/ThreeMojo/issues/306).
