<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# Remaining engine work

This batch starts from main `8d9b700b753006b120a66d356228716822e442f4`, after [PR #572](https://github.com/SethKitchen/ThreeMojo/pull/572).
The issue inventory was checked on October 4, 2026.
The initial inventory contains 28 issues for this main-backed batch and two animal issues in a separate draft.
Follow-ups #633, #635 and #636 were added after that snapshot.

## Lane queries

Resolve correctness and bounded-work contracts before accepting performance results.
The held implementation in [PR #594](https://github.com/SethKitchen/ThreeMojo/pull/594) still needs qualification against this base.

- [#302](https://github.com/SethKitchen/ThreeMojo/issues/302): index curved lane offsets correctly
- [#485](https://github.com/SethKitchen/ThreeMojo/issues/485): geometric lane heading and pitch implemented; 203 focused tests and exact-center benchmark controls pass, with full batch validation pending
- [#487](https://github.com/SethKitchen/ThreeMojo/issues/487): direction-independent complete-section junction bounds implemented; 147 focused tests pass, with full batch validation pending
- [#577](https://github.com/SethKitchen/ThreeMojo/issues/577): support border-only lane widths and centerlines
- [#580](https://github.com/SethKitchen/ThreeMojo/issues/580): bound subdivision and nearest-query work
- [#604](https://github.com/SethKitchen/ThreeMojo/issues/604): wide stored-center lane ordering implemented; 94 focused tests and independent exact controls pass, with full batch validation pending

## Physics

Keep workloads and numerical contracts fixed when comparing designs.

- [#288](https://github.com/SethKitchen/ThreeMojo/issues/288): benchmark/design decision completed; production snapshot work continues in #633
- [#292](https://github.com/SethKitchen/ThreeMojo/issues/292): bounded opt-in sphere/static-mesh CCD completed; general CCD and acceleration remain separate
- [#633](https://github.com/SethKitchen/ThreeMojo/issues/633): owned frozen physics query snapshots implemented; 39 focused tests, two typed negatives and timing/allocation matrices pass, with full batch validation pending
- [#635](https://github.com/SethKitchen/ThreeMojo/issues/635): extend CCD beyond separated spheres and static meshes
- [#636](https://github.com/SethKitchen/ThreeMojo/issues/636): immutable-mesh CCD acceleration implemented; 79 focused tests and fixed/adverse benchmark controls pass, with full batch validation pending

## Assets and CARLA state

Preserve source attribution, input validation and resource ownership.
Hosting work requires a specified destination and verified source material.

- [#303](https://github.com/SethKitchen/ThreeMojo/issues/303): pinned production asset provenance and exact reproduction implemented; 26 Python and 22 native checks pass, with full batch validation pending
- [#306](https://github.com/SethKitchen/ThreeMojo/issues/306): reclaim destroyed actors' physics and render resources
- [#309](https://github.com/SethKitchen/ThreeMojo/issues/309): complete durable asset hosting and integrity controls
- [#333](https://github.com/SethKitchen/ThreeMojo/issues/333): retain double precision at typed quantity boundaries
- [#336](https://github.com/SethKitchen/ThreeMojo/issues/336): remove texture-set copies without sharing mutable state
- [#505](https://github.com/SethKitchen/ThreeMojo/issues/505): dynamic decode queue implemented; focused checks and benchmarks pass, with full batch validation pending

## Numerical and coverage contracts

Keep existing accuracy and resource limits.
Measure ordinary-case costs as well as boundary correctness.

- [#348](https://github.com/SethKitchen/ThreeMojo/issues/348): scale-safe normalization and remaining norm consumers implemented; 134 focused CPU tests and three Metal kernel compile checks pass, with full batch validation pending
- [#538](https://github.com/SethKitchen/ThreeMojo/issues/538): adaptive exact hull predicates implemented; 120 focused tests and independent exact controls pass, with full batch validation pending
- [#550](https://github.com/SethKitchen/ThreeMojo/issues/550): exact query validation implemented with accepted current performance; full matrix and focused checks pass, with aggregate validation deferred
- [#560](https://github.com/SethKitchen/ThreeMojo/issues/560): preserve arbitrary Boolable behavior in coverage probes

## Three.js features

Check each issue against its stated upstream version and refusal contract.

- [#614](https://github.com/SethKitchen/ThreeMojo/issues/614): bounded unsigned GLSL, texture gradients and finite loops implemented; 580 tests and independent controls pass, with full batch validation pending
- [#615](https://github.com/SethKitchen/ThreeMojo/issues/615): all five missing OpenEXR codecs implemented; 49 tests, four typed negatives and independent fixtures pass, with full batch validation pending
- [#616](https://github.com/SethKitchen/ThreeMojo/issues/616): opaque-scene depth and shared rectangle-volume lighting implemented; 115 focused CPU tests and three SM80 compile controls pass, with full batch validation pending
- [#617](https://github.com/SethKitchen/ThreeMojo/issues/617): all six r180 raw ASTC formats implemented; focused tests and exact Arm reference regeneration pass, with full batch validation pending

## Scene and humanoid work

Keep template estimates distinct from validated physical correspondence.
No full anatomical calibration is claimed by this plan.

- [#297](https://github.com/SethKitchen/ThreeMojo/issues/297): finish the canonical-to-visual fidelity contract
- [#298](https://github.com/SethKitchen/ThreeMojo/issues/298): close the selected strand-hair rendering and simulation gaps
- [#299](https://github.com/SethKitchen/ThreeMojo/issues/299): audio-aligned game faces implemented; 76 focused tests, two typed negatives and bake/load controls pass, with full batch validation pending
- [#300](https://github.com/SethKitchen/ThreeMojo/issues/300): integrate persistent scene water and measure CPU/GPU paths
- [#595](https://github.com/SethKitchen/ThreeMojo/issues/595): classify and resolve sampled canonical anatomy overlaps
- [#596](https://github.com/SethKitchen/ThreeMojo/issues/596): complete executable canonical pair catalog and diagnostics implemented; focused checks and representative evidence pass, with full pair execution deferred to final batch validation

## Separate animal work

[#605](https://github.com/SethKitchen/ThreeMojo/issues/605) and [#620](https://github.com/SethKitchen/ThreeMojo/issues/620) continue in [PR #607](https://github.com/SethKitchen/ThreeMojo/pull/607).
That branch is reviewed separately on its current head.
Its review findings and aggregate/platform checks remain separate merge gates.
Its changes are not part of this main-backed batch.

## Qualification

Land reviewed changes through child PRs into this batch branch.
Keep all existing test workloads, the five-second limit, and the full coverage requirement.
Preserve the CI draft and target-branch policy.

The October 5 stopping point retains the implemented work in this batch.
Further issue implementation is paused for review, CI and the open-PR merge pass.
Run full coverage and aggregate checks on this selected checkpoint.
Clearing draft status does not establish merge readiness.
Regenerate the anatomy report on the final batch source.

Its current source binding is stale after the decode-queue changes.
Building-extension work remains in separate PR #655 for review.
Keep CPU tests, GPU compilation and actual GPU execution as separate evidence.
Each issue remains open until its complete acceptance criteria are verified.

The earlier bounded slices for #297, #303, #309, #348, #550 and #614 are already on main.
The #348, #550, #303 and #614 remainders are implemented in this batch.
The other partial slices remain listed above.
Optional bulk gallery recompression remains excluded.
