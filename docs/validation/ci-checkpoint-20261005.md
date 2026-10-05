# Selected checkpoint qualification

The October 5 checkpoint contains 18 issue implementations. Remaining issue work is paused for review and CI. Clearing draft status is not merge qualification.

## Focused CI repairs

The material optimizer key now includes the volume scene-depth switch. Ten optimizer tests pass, including a switch-and-restore distinction control. Materials with different depth behavior cannot share that key.

The audio-face example has a separate GLB Make target. Its prerequisites use the existing import and quoted-asset graph. The dependency test verifies the real face asset and code inputs.

The fixture manifest records both exact EXR comparison versions, 0.180.0 and 0.186.0. It pins all 132 consumed hex inputs and comparison outputs. Upstream differences and exceptions retain their original classifications. No fixture bytes changed.

The related Python checks pass: 26 build-tool tests, six example-input tests and two fixture-manifest tests. The two earlier audio-face formatting corrections preserve executable tokens.

## Scoped compiler workaround

The first fresh anatomy-probe build failed with a Mojo compiler SIGSEGV. The original failure is retained.

A reviewed extraction moves two raising assertions into a helper called inside every original loop iteration. It matches the test-only approach in [548dffef](https://github.com/SethKitchen/ThreeMojo/commit/548dffef304847138198e7f115adb240e2772403).

All four accounting controls pass. Every original assertion, tolerance and loop remains. No animal feature, coverage schedule or budget change was imported. The successful changed-source build establishes this checked result, not an upstream root cause or universal compiler fix.

## Full canonical pair report

The fresh source-bound report executes all 8,911 selected-side lower-limb catalog pairs. It includes 465 legacy pairs and 8,446 additional diagnostic rows. No catalog pair is intentionally omitted.

The report uses the original 20, 10 and 5 mm grids and the unchanged five-second process limits. Pinned Mojo 1.1.0 builds use warnings as errors and one compiler thread.

The fresh build and full report completed in 70.84 seconds. All 19 anatomy and source-binding Python checks pass.

- Source digest: `9eb16609226cd8c81aa6793fdd7e18e77e8a7f92b1efae4b5f8905916da15ed1`
- Report SHA-256: `4efd08e035a2dc7929baffc4c7f33c192a9b84181a12dbdbf73cfeaf101005ac`
- Scope: template estimate for the recorded 1.8288 m, male, right-side, untoned specification
- Geometry findings: 367, compared with 36 in the previous narrow report

The expanded findings remain open diagnostic work under #595. Full pair execution does not repair geometry or establish anatomical, clinical or engineering validity. Whole-body, dynamic and visual correspondence remain outside this report's evaluated scope.

## Remaining gates

Full project coverage, aggregate/platform CI and external-PR review remain required. Later source changes require a new source-bound report. No test limit, coverage threshold or workload was reduced.
