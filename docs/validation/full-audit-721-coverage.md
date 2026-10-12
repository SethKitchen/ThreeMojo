# CARLA full-audit coverage record (#721)

This record measures the five CARLA modules that failed the full audit in [issue 721](https://github.com/SethKitchen/ThreeMojo/issues/721). Every suite that can reach them ran under instrumentation. All five modules are at 100 percent for lines, branches and MC/DC. No threshold, exclusion or hash-only repin was used.

This is a scoped local measurement, not a hosted full audit. The hosted manual CI run remains the full audit of every module.

## Method

The measured set is the union of two selections:

- The five #721 modules: `speed_limits`, `lane_value_bounds`, `curve_bounds`, `junction_bounds` and `lane_refinement` in `extensions/carla/`.
- The scoped coverage selection of this branch from `python3 tools/ci_scope.py plan --base origin/main`: `map.mojo` and the 45 production modules that consume it.

The suite list is every test suite that can reach a measured module through the import graph, as `tools/ci_scope.py` computes it: 190 suites. A `MAKEFILES` selection file overrides `COVERED` and `CPU_TESTS`, as `tools/ci_scope.py run` does. The run used the repository targets:

```sh
make -B coverage AFFECTED= MAKEFILES=<selection> COV_BUDGET=200000 JOBS=3
```

The machine was a shared 4-vCPU Intel Xeon VM with a 15 GB memory limit. The capture was resumed twice with `make coverage-capture` for unfinished suites. The first restart followed a two-hour session limit. The second ran two render suites stopped by the memory limit. Each capture is complete for its suite, and `make coverage-report` checked a capture and its receipt for all 190 suites.

## Results

| Module | Lines | Branches | MC/DC | Proven impossible loop outcomes |
|---|---:|---:|---:|---:|
| `speed_limits` | 61/61 | 97/97 | 25/25 | 1 |
| `lane_value_bounds` | 212/212 | 204/204 | 46/46 | 0 |
| `curve_bounds` | 354/354 | 261/261 | 58/58 | 1 |
| `junction_bounds` | 317/317 | 235/235 | 63/63 | 1 |
| `lane_refinement` | 904/904 | 756/756 | 134/134 | 6 |
| `map` | 1581/1581 | 1001/1001 | 165/165 | 11 |

All 51 measured modules are at 100 percent. The total is 27,451 of 27,451 required outcomes. 27 loop outcomes are proven impossible by the reviewed loop proofs; each keeps its True outcome required, and each True outcome was hit. The `map` rows include the per-segment skip of issue #685 and its seven-edge Map proof chain.

## Obligations and witnesses

The obligations of issue #721 were closed by the source changes and witness tests that `docs/validation/full-audit-711-invariants.md` describes. This run confirms that each of them is now hit:

- `speed_limits`: the parse-failure line after the syntax check (`tests/test_carla_speed_parser_exceptions.mojo`).
- `lane_value_bounds` and `curve_bounds`: the nonnegative stored blend allowance.
- `junction_bounds`: the endpoint refusals after full-cell admission (`tests/test_carla_junction_endpoint_refusals.mojo`) and the strict cut order.
- `lane_refinement`: the finite-width admission, the post-local natural exclusion, the center refusal (`tests/test_carla_lane_center_bound_phase.mojo`) and the chord endpoint refusals (`tests/test_carla_chord_endpoint_refusals.mojo`).

The loop proofs that cover these modules keep their historical review hashes. They admit the current sources only through the reviewed full-audit cleanup edge in `tools/carla_lane_oracle/full_audit_cleanup_contracts.py`. That edge binds the exact before and after bytes, the inverse spans and the bound tests.

## Platforms

Coverage captures run only on Linux x86-64. The last-endpoint junction refusal needs x86 denormals-are-zero. On the macOS arm64 runner, the same suite runs the first-endpoint control and prints `LAST_DAZ_CAPABILITY_UNAVAILABLE`. It claims no last-endpoint witness. No coverage result depends on it. See [Coverage tool](https://github.com/SethKitchen/ThreeMojo/wiki/Coverage-tool#platform-specific-witnesses).

## Limits

- The capture used the branch's Mojo sources. Its proof tooling was an earlier revision of this branch with operation-scoped result reuse, which was later withdrawn. The Mojo sources, suites and loop-proof rows are the same; a hosted run on the final revision must still confirm the receipts.
- The 30 and 45 second Python probe timeouts and the macOS CPU shard time limit are separate from coverage. This record does not address them.
