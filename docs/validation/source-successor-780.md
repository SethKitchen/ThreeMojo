# PR780 source successor

PR780 retains every historical source pin. A separate exact inverse records
the reviewed source corrections and their qualification tests. This inverse
does not prove arithmetic equivalence or grant a coverage exemption.

## Admission

The owner reads the current physical files. It requires one complete current
cohort, with no historical or mixed endpoint fallback. Each source has exact
before and after byte and token digests. Fixed line edits reconstruct the
complete prior file, including all untouched bytes.

The prior files join the existing PR776 and PR760 pins. The original stage,
source image, typed authority, fixture records, and predecessor archive remain
unchanged. The original pure comparison checks still run on those exact prior
files. The current import closures, resolver checks, caller inventory, owner
checks, and final physical reads still run on current files. Receipts contain
current physical digests.

The new source changes include finite geometry checks, signed extent-product
checks, bounded byte and loader reads, matrix premultiplication, and the
reviewed rendering and sensor corrections. Native tests qualify those changes
separately. The source inverse makes no claim that the new error cases or
corrected output equal the old behavior.

## PR791 sources

PR791 adds or extends five sources in the same table:

- `objects/gaussian_splat.mojo`
- `render/splat_raster.mojo`
- `render/splatrule.mojo`
- `renderers/renderer.mojo`
- `tools/compile_fail_expectations.json`

The scan renderer changes these files. It adds tiled and level-of-detail splat
drawing, and it adds the compile-fail records of the new scan types. The
vegetation extension merges into the same change. Its two compile-fail records,
for `PlantKind` and `ClusterFate`, are in the same expectation edge. Each
source has exact before and after digests, token digests and line edits. The
before digest is the digest on main. For the expectation file that is the PR776
digest. The prior files join the PR776 and PR760 pins in the same way as the
PR780 sources.

The cohort is still complete. A table with some of these sources at the old
digest and some at the new digest is refused. Native tests and full coverage
remain separate requirements.

## Qualification controls

The Python controls require exact forward and inverse reconstruction. They
refuse modified bytes, mixed cohorts, missing files, changed regression tests,
changed inverse data, coordinated digest changes, changed executing code, and
transient source observations. Historical tests keep their original assertions
and run against named exact predecessors. Current-image tests also check the
current physical digests.

The owner source has a separate test-only inverse and physical line map. It
preserves the existing operation-site mutation assertions. This transport does
not supply a production filesystem, observation, owner, or receipt.

Native runtime tests and full coverage remain separate requirements. This
successor does not change a coverage threshold or any proof denominator.

## Local density dependencies

The density proof retains its original 345-input authority, unchanged density
and groom sources, native witnesses, and four theorem rows. Six imported
helpers have a separate exact dependency successor. This local checker accepts
either the complete original cohort or the complete reviewed current cohort;
partial cohorts fail closed. It consumes a digest-checked detached snapshot of
the successor table, rechecks that authority before returning, and records the
actual physical dependency hashes. Its resolver and final-read checks remain
local, without requiring unrelated CARLA source admission.

The dependency reader must match the function compiled from the physical
coverage tool. The checker verifies its code, globals, defaults, and source
freshness before each snapshot. A replaced live reader cannot grant admission.
