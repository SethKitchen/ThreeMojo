# CARLA lane numerics

The lane-center refinement in this branch is experimental. It is not a complete global-nearest or on-road guarantee. Keep [#302](https://github.com/SethKitchen/ThreeMojo/issues/302) and [#485](https://github.com/SethKitchen/ThreeMojo/issues/485) open until the limits below are resolved and the full checks pass.

This page describes the numerical changes to the [CARLA roads](CARLA) port. The upstream reference is LibCarla commit `1360bb9`. The changes are local to CARLA geometry, roads, and lane queries. They do not replace the renderer's math functions.

## Why a local minimum is not enough

A cubic lane offset can give one centerline interval several local distance minima. A single golden-section search can select the wrong one. Small chord error does not make the distance function unimodal.

A retained regression has road length 0.001001 meters and a right lane of width 0.0002 meters. Its lane-offset coefficients are 0.00039575, -6.7925, 18200, and -13000000. The query is `Vector3(Float32(0.0009), Float32(0.0005525), 0)`.

For the stored binary coefficients, independent rational root isolation gives the global LINE minimum near s = 0.000900000002294056. The former search selected s = 0.00043971722812718013 and reported off-road. The continuous chord error is below 1 millimeter. ARC curvature 0.001 and an equal-curvature SPIRAL need separate controls too.

The LINE path now adds stationary-polynomial candidates. Repeated roots and interval endpoints remain candidates. A candidate from a rounded polynomial is a search seed, not a certificate for the final rounded center evaluator.

## Local evaluator and bounds

The draft uses explicit CARLA-only polynomials for sine, cosine, atan, and atan2. Finite sine and cosine phases of magnitude at most 2^20 radians use quadrant reduction. Outside that phase domain, the scalar path keeps a native result clamped to [-1, 1]. Its bound exposes the whole range and no finite derivative certificate.

Value and derivative bounds describe expressions in the stored coefficients. A separate error bound encloses scalar operation rounding. Taylor and convexity lower bounds retain that error. A derivative of the continuous expression does not prove that its rounded values are monotone.

The bounds follow the actual Gauss quadrature and sampled interpolation expressions. A quadrature-count, record, or tangent branch is not assumed smooth. The default pinned compiler build is the target. Unsafe reassociation is outside the current numerical contract.

Geometric agreement with ideal trigonometry is a separate check. It must not be substituted for a bound on the actual evaluator.

## Search, admission, and errors

Non-affine intervals use bounded subdivision. The local search charges its scalar samples and quadrature work before execution. It raises `Error` when its local work or accuracy limit is exhausted. Callers must not treat that error as an off-road result.

The current stopping rule bounds a distance-squared gap. Its provisional spatial term is the smaller of interval span and positive lane width, multiplied by 2^-20. It also includes 64 ULPs of the current squared distance. This is a declared approximation criterion, not an exact-minimum proof or a new lane-width acceptance tolerance.

Candidate admission uses full-curve enclosures separately from the sampled 1-millimeter subdivision target. A sampled chord check is not a conservative full-curve bound. RTree arithmetic and conversion to public `Float32` coordinates need separate allowances. Cached bounds describe the records and endpoints at map build; they do not cover arbitrary later mutation.

Known extreme-coordinate RTree distance and slab defects are tracked in [#589](https://github.com/SethKitchen/ThreeMojo/issues/589). The independent packing correction [#583](https://github.com/SethKitchen/ThreeMojo/issues/583) does not resolve them.

## Current limits

- Repeated tight ARC turns can exhaust the interval-work limit. A numerical error floor cannot be removed by extra subdivision alone.
- A bounded objective gap does not establish the winning road or lane when candidate bounds overlap. Cross-candidate certification remains incomplete.
- The on-road path still needs wide-center, scaled-norm certification for its strict half-width comparison. Public `Float32` transforms can discard available precision. A road origin of 1e9 + 1 and a query of `Float32(1e9)` is a required control. Squaring a very small or large displacement can also underflow or overflow.
- An affine projection with positive distance is not automatically an exact minimum certificate. Coincident zero-distance samples are a different case.
- Whole map-build and query budgets remain [#580](https://github.com/SethKitchen/ThreeMojo/issues/580). Border-only lane support remains [#577](https://github.com/SethKitchen/ThreeMojo/issues/577).

## Validation scope

The focused LINE, interval, curve-bound, and non-LINE acceptance suites are partial controls. They do not replace the full original lane-geometry fixtures. No complete fresh validation result is claimed for this draft.

Before use, the implementation needs the full regression controls, independent evaluator checks, all changed-module coverage, affected CPU consumers, and ordinary-query cost measurements. Existing fixture tolerances, lane widths, and workloads must stay unchanged. Unsupported accuracy must remain explicit.
