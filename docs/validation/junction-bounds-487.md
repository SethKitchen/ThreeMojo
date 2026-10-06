# Junction bounds correction (#487)

## Scope

This change corrects reverse-running junction bounds from CARLA `1360bb9`.
The prior signed ten-step interval omitted curved lane interiors.
The implementation base is `02fc720bd3348bbf4229153674f4d2da1aca114f`.

Bounds now evaluate each eligible lane over its complete section.
They use increasing road s for both traffic directions.
Record boundaries and deterministic endpoints do not depend on lane links.

See [the numerical contract](../wiki/CARLA-maps.md#junction-bounds) for the
1 cm chord target, separate numerical allowances, and wider fallback cases.
The box covers lane centers, not the complete lane surface.

## Independent controls

- Circle equations check the 100 m semicircle for both lane signs and both traffic rules
- Off-grid interior queries check every supported geometry kind and section
- Composite midpoint integration checks the spiral independently of the production quadrature
- Analytic cubic extrema check narrow width, offset and elevation records
- A displaced pair of semicircles checks conflicts near their curved interiors
- An endpoint-only control loses that conflict, reproducing the original defect
- Large road-s cubics, canceled arc radii and unresolved phases check numerical allowances

The tests also cover unlinked sections, changed lane ids, duplicate
connections, record jumps, clamped geometry tails and sampled-table tails.
They cover singular tangent and subdivision-budget fallbacks.
Empty, tiny and zero-length section behavior is deterministic.

## Focused qualification

Use pinned Mojo `1.1.0` (`8189361e`) with telemetry disabled.
Build each suite with warnings as errors.
Run it through the unchanged five-second-per-test runner.

```sh
export MODULAR_TELEMETRY_ENABLED=false
for suite in test_carla_junction_bounds test_carla_map \
    test_carla_mesh_factory test_carla_traffic_manager \
    test_carla_trigger_direction; do
    "$MOJO" build -I . --Werror "tests/$suite.mojo" -o ".cache/bin/$suite"
    python3 tools/run_suite.py --seconds 5 --suite "tests/$suite.mojo" \
        -- ".cache/bin/$suite"
done
```

All 147 tests passed across five focused suites, with no failures or skips.

- Junction bounds: 11 tests
- Map: 53 tests
- Mesh factory: 26 tests
- Traffic manager: 46 tests
- Directional triggers: 11 tests

All four changed Mojo files match formatted scratch copies.
Documentation lint passed for the three changed Markdown files.
Detailed results are in the [validation JSON](junction-bounds-487.json).
The existing numerical test tolerances and workloads are unchanged.
The map suite only changes a stale comment about the old traversal.

## Consumer effects

Corrected bounds admit previously omitted conflict candidates.
Stop and yield check boxes can therefore include more crossing roads.
Mesh-region selection and expanded mesh boxes can also change.
Traffic-manager junction flags still use topology.
The focused traffic-manager and trigger suites retain their existing checks.

## Deferred qualification

Full aggregate checks, full coverage, cross-platform checks and batch report
regeneration remain deferred under the current implementation-first workflow.
Focused passes do not establish those gates.
This change does not close the separate nearest-lane or geometry issues.
