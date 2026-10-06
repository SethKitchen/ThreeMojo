# Continuous collision validation for issue 292

The opt-in sphere/static-mesh mode resolves the reported tunneling case within a checked support boundary. It does not provide general moving-body CCD.

The [public contract](../wiki/Continuous-collision.md) defines accepted shapes, motion, precision, event order and rollback. The default discrete mode keeps its prior behavior.

## Revision and toolchain

The integration base is `c9b2aaab7643f3314bc87f0d9e21990f4aa21527`, the qualified static-index benchmark child in draft 632. This candidate preserves that child's files and production behavior. The report concerns the new CCD source hashes in [the machine-readable record](continuous-collision-292.json).

Local verification used Linux x86-64, Mojo 1.1.0 and MAX 26.6.0. Builds used `--Werror`. Every Mojo invocation disabled telemetry. Native suites retained the five-second runner limit. Tests and reference tolerances were not reduced.

These local results are focused qualification. They are not a repository-wide pass, a macOS result or an exact-head CI result. The integrator must run the affected aggregate on the final combined tree.

## Acceptance evidence

| Requirement | Evidence |
|---|---|
| Prevent the reported crossing | Radius 0.1 m, z 0.15 m, velocity -30 m/s and step 0.01 s stop at z 0.1 m. The unchanged discrete control reaches -0.15 m. |
| Vary radius, speed and step | A 144-case plane family covers four radii, four speeds, three steps and three restitution values. |
| Edge, vertex and grazing behavior | Analytic circle-section controls cover edges and vertices. Exact tangency and a just-outside path produce no impulse. |
| Independent numerical reference | Twenty-three native hit cases use a separate 70-digit Decimal geometric-distance oracle. They include six faces, fifteen edges and two vertices. |
| Multiple impacts | A sphere makes four elastic rebounds in one step. A smaller impact budget fails atomically. |
| Slow and initial contacts | Front-side stationary, slow and overlap cases retain discrete output. Fast speculative contacts wait until the actual surface crossing. |
| One-sided geometry | Initial backface overlap and both travel directions remain uncaptured in CCD mode. |
| No new energy source | Native friction, restitution and spin-transfer controls bound total kinetic energy. The source response uses a dissipative static-contact impulse. |
| Angular timing | A late friction impulse creates spin only for the remaining time. Orientation follows the existing approximate quaternion update per segment. |
| Modes and ghosts | Disabled bodies, re-entry and dynamic/kinematic/static changes have tests. Unsupported colliding configurations raise errors. |
| Deterministic events | Repeated runs and equal-time body/triangle ties have fixed-order assertions. |
| Failure and numeric limits | Tests cover full mutable-state restoration, raycast-visible dirty-state rollback, invalid modes, overflow, unresolved scales and thin triangles. |
| Work and performance bounds | The fixed benchmarks below report complete step costs, ray batches and the brute-force complexity boundary. |

The separate reference generator is `tools/physics_ccd_reference.py`. It searches the convex nearest-triangle distance over time, then bisects the first radius crossing. It does not use the sweep's root formula. Seed 292 produces the saved entering-hit fixtures. The native assertions use a 1e-12 absolute hit-fraction tolerance.

Reproduce the reference data with:

```sh
python tools/physics_ccd_reference.py --check docs/validation/continuous-collision-292-reference.json
```

Independent review also examined random oblique plastic contacts and isolated friction impulses. Those Python controls supplement the native tests. They do not replace compiled execution or establish a universal mathematical proof.

## Focused coverage

The native CCD suite passed 20 of 20 tests. Seven instrumented suites measured the complete `ccd` and `world` modules. No source exclusion or denominator reduction was introduced.

| Module | Lines | Branch outcomes | MC/DC |
|---|---:|---:|---:|
| `extensions/physics/ccd.mojo` | 78/78 | 56/56 | 12/12 |
| `extensions/physics/world.mojo` | 615/615 | 394/394 | 69/69 |
| Total measured items | | | 1224/1224 |

The instrumented suites were `test_physics_ccd`, `test_carla_physics_world`, `test_carla_physics_regressions`, `test_physics_modes`, `test_physics_rotation`, `test_physics_api_guard` and `test_shared_physics`. Their test-result logs and timing limits were checked. The new typed-mode compile-fail fixture passed with its reviewed diagnostic. These full-module figures do not claim full-repository coverage.

## Final local integration checks

The integrator's original CCD run passed 782 tests in 47 direct-consumer suites. Its preserved source and binary hashes were checked before the formatter-only change described below. This was a direct production-import check. The official selector requests 499 CPU suites for CCD and 500 after the TM cleanup test is added. Those complete aggregates have not run here.

The final combined CCD and bounded TM cleanup source passed 206 native tests in nine suites. They include every direct consumer of the two changed TM modules and the focused CCD suite. Thirteen fresh instrumented suites passed 248 tests. The four complete measured modules reached 2,238/2,238 obligations: 1,224 CCD/world and 1,014 TM/parameters. The manifest is exactly the union of the earlier obligations after the formatter's one-line shift. No new exclusion or denominator reduction was made.

The formatter-corrected CCD tree also passed all 381 negative fixtures, 41 negative-harness tests, the 23 reproduced Decimal references and three changed-module doc builds. Final combined checks repeat the negative fixtures that import the changed TM modules and the typed CCD fixture. All builds use warnings as errors and retain the five-second per-test gates. These are local Linux results; full aggregate, exact-head CI, macOS and GPU qualification remain separate.

The TM work is a bounded actor-settings cleanup. Issue 306 stays open because whole-world retained-memory and tick-cost plateaus are not established.

## Repeated performance measurements

`bench/physics_ccd_bench.mojo` uses three fixed workloads. Each row has one warmup step and twenty measured steps. Each measured step also has a separate fixed ray batch. The sphere positions and velocities reset between steps. All candidate and baseline rows use the same geometry, probes, rays and repeat counts.

The baseline source is the exact integration base. Its benchmark uses only the existing discrete mode. Three paired baseline/candidate runs were made without overlapping this lane's compilation or reference generation. The container still has shared scheduling noise. [All paired rows](continuous-collision-292-timings.csv) are retained.

The benchmark source hashes were reconciled after the run against the retained pre-format candidate. No contemporaneous source-and-binary build manifest was found. Final integration only split one error-message string in `ccd.mojo` into adjacent literals to pass the pinned formatter. The message text is unchanged. The timings were not rerun or relabelled as measurements from a byte-identical final build. The machine-readable record preserves both the reported pre-format hashes and the final integration hashes.

The table uses the median of three per-run means. The worst step is the maximum over all three candidate runs.

| Workload | Triangles / spheres / rays | Base discrete step | Candidate discrete step | CCD step | CCD worst step |
|---|---:|---:|---:|---:|---:|
| Vehicle probe | 2048 / 1 / 64 | 0.001747 ms | 0.001676 ms | 0.139520 ms | 0.385271 ms |
| Separated fleet | 8192 / 32 / 256 | 0.107920 ms | 0.106179 ms | 10.132395 ms | 15.568542 ms |
| Sensor scale | 32768 / 16 / 2048 | 0.174738 ms | 0.186274 ms | 19.112528 ms | 35.638261 ms |

CCD step costs are approximately 83, 95 and 103 times their candidate discrete controls. The median CCD ray batches are 0.082058, 1.335778 and 24.281157 ms. Every ray checksum matches its control. These rays avoid probe geometry, so the expected surface distances are the same.

The larger CCD scenes do not fit a 10 ms step budget. The sensor ray batch adds further cost. These are synthetic spheres at vehicle/sensor-scale workloads. They are not calibrated vehicle dynamics, a validated fleet or a real-time capacity claim. Small changes between the two discrete builds are within the observed scheduling variation. They do not establish a speedup or a regression threshold.

The implementation scans all static triangles for each sweep. With B spheres, T triangles and limit I, sweep work is O(B T (I + 1)). Domain checks add O(B T + B²). The default I is 16. No impact can silently discard the rest of the step. Exhaustion restores state and raises an error.

A future static query index can reduce this cost. It must preserve ownership, mutation rules, front-side predicates and deterministic event order. The current work does not claim that optimization.

## Remaining support boundary

Convex, box, capsule, rotating-offset, kinematic-collider, moving-mesh and moving-pair CCD remain unsupported. The mode rejects those requests rather than falling back. Generalizing those cases is separate implementation and validation work.

The precision checks intentionally reject some finite inputs. Float64 intermediates do not make arbitrary Float32 scenes reliable. Read the radius, coordinate, travel and triangle-conditioning limits in the public contract. The retained initial contact solver and external force update are not a global energy-conservation proof.

General shape and moving-pair support is tracked in [issue 635](https://github.com/SethKitchen/ThreeMojo/issues/635). Conservative triangle candidates and CCD cost reduction are tracked in [issue 636](https://github.com/SethKitchen/ThreeMojo/issues/636). The primitive snapshot ownership design in [issue 633](https://github.com/SethKitchen/ThreeMojo/issues/633) remains separate.
