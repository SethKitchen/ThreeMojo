# Scale-safe norm consumers

Finite nonzero vectors must keep their direction when a squared norm does
not fit in the scalar type. A length can be infinity only when the length
itself does not fit. Zero and nonfinite inputs have separate rules.

This audit completes [#348](https://github.com/SethKitchen/ThreeMojo/issues/348).
The reference is three.js r180 unless a module names another pinned source.
The range corrections below intentionally differ from direct sum-of-squares
arithmetic in that reference. Ordinary inputs keep their original arithmetic
where practical. The tests retain ordinary reference fixtures and use exact
axis, symmetry, and scale ratios as independent extreme-range oracles.

## Shared arithmetic

`math.norm` contains the Float32 and Float64 scalar length and normalization
functions. A finite nonzero direction does not use an unrepresentable length
as its divisor. It divides by its largest component first.

`reciprocal_normalized3` preserves reciprocal-multiply rounding for ordinary
inputs. `normalized_difference2` and `normalized_difference3` also handle
finite endpoint differences that overflow: they halve endpoints before
subtraction. `normalized_cross3` keeps separate product mantissas and
exponents when a Float64 cross product exceeds its range. It does not scale
away a small component before that component forms a significant product.

`math.triangle_normal.normal_or_zero` uses the existing exact stored-Float32
coordinate expansion when a direct cross cannot certify its direction.
`polygon_normal` preserves ordinary Newell sums and uses original-coordinate
product expansions for range-limited or cancelling sums. Zero area remains zero.

`math.scaled_products` keeps FMA product pieces with separate exponents.
Its Float32 path runs on the device. Its Float64 path supports native-double
normal products and area weights without narrowing or early product rounding.

## Changed consumers

| Consumer | Range-sensitive operation and treatment |
|---|---|
| `math.vector3` | Projection on an arbitrary axis and normalized matrix products use a wide fallback before products. Plain dot products, raw crosses, and squared lengths keep their documented range limits. |
| `core.buffer_attribute`, `core.buffer_geometry` | Normalized transforms, area-weighted normals, and tangents preserve finite directions. Wide fallbacks start from original coordinates and UVs. Morph normals use their base normal's shared scale; they are not normalized independently. |
| `core.raycaster` | Geometric face normals use the shared triangle helper. The projected-segment parameter widens its squared-length fallback. |
| `core.gaussian_splat_utils` | A finite quaternion normalizes before covariance construction. A zero quaternion still means identity. |
| `geometries.edges`, `geometries.utils`, `geometries.parametric`, `geometries.surface_sampler` | Unit face normals retain original coordinates until the safe cross is computed. Degenerate normals remain zero. |
| `geometries.loft`, `geometries.torus` | Cap normals and physical-scale knot frames avoid overflow in products before normalization. |
| `geometries.mikktspace` | Lengths and unit tangents use shared norms. Extreme edge and UV products widen before multiplication. Nonzero subnormals participate in frame construction. Thin-corner angle weights use original-coordinate crosses when a cosine rounds to one. Invalid faces retain the existing default-frame behavior. |
| `geometries.simplify`, `geometries.convex_object_breaker` | Vector and tangent normalizers use shared scalar helpers. Simplification edge lengths use the shared length. |
| `geometries.polyhedron` | Latitude uses a scale-safe horizontal length. |
| `geometries.sculptor`, `geometries.sculptor_tools`, `geometries.sculptor_mesh`, `geometries.sculptor_utils` | Native Float64 direction and length helpers use shared norms. The intentional zero-normal fallback to +x remains explicit. Range-limited stored face areas are reconstructed before drawing or normal-dependent tools use them. Stored squared brush radii keep their squared-value contract. |
| `loaders.gltf`, `loaders.object_loader`, `loaders.model_nodes` | Matrix axes use shared lengths and `Matrix4.decompose`. Tiny axes are not flat. Mirror signs survive determinant range loss. Nonfinite entries and unrepresentable output scales are refused before node mutation. |
| `loaders.ldraw` | Axis lengths, unit directions, and face normals are scale-safe. Rotation extraction reads normalized axes. |
| `loaders.svg`, `loaders.svg_shapes`, `loaders.svg_path` | Signed vector angles, stroke directions and lengths, transform-axis lengths, and the symmetric eigensolver use scale-safe arithmetic. Ordinary stroke reciprocal rounding remains unchanged. |
| `loaders.vrml`, `loaders.vrml_geometry` | Parsed Float64 rotation axes, vector angles, and face normals use safe directions. |
| `loaders.amf`, `loaders.usd_geometry`, `loaders.lwo` | Normalization occurs before an unnormalized finite area is lost to Float32 storage. AMF's positive unit conversion does not change a normal's direction. |
| `loaders.fbx`, `loaders.ply` | Polygon normals and area checks widen products before a finite small face can appear to have no area. PLY retains the existing relative convexity tolerance. |
| `loaders.nrrd` | Native Float64 spacing-vector lengths use the shared length. The volume transform still has its separate Float32 storage contract. |
| `objects.line`, `objects.reflector_for_ssr` | Projected line directions and Fresnel direction components use safe normalization. A zero projected conditional-line edge still produces NaNs, as its previous GLSL-style operation did. |
| `controls.arcball_controls`, `controls.transform_controls`, `controls.trackball_controls` | Vector-angle helpers use `Vector3.angle_to`. Scalar cursor and direction lengths use shared norms. |
| `lights.lighting`, `render.gpu` | The shared `light_vector` keeps physical distance separate from a directional divisor. Ordinary shading keeps dot-then-divide order on both backends. Finite endpoint differences can have an infinite distance and a valid unit direction. |
| `lights.projector_light`, `lights.light_probe_grid`, `lights.sun_light`, `lights.csm` | Distance and radius calculations use lengths rather than an overflowing squared intermediate. Sun directions validate finite components and true zero separately. |
| `render.rasterizer`, `render.texture` | Tangent frames share one scale across both frame axes. Texture footprints scale before Gram products. Mip levels use log space when texel lengths do not fit in Float32. |
| `render.cube_texture`, `render.packing` | Equirectangular directions and packed radial distances use safe norms. |
| `renderers.renderer`, `renderers.projector`, `renderers.svg_renderer` | Triangle, transformed-normal, direction, and edge-expansion consumers use the shared helpers. |
| `postprocessing.effects`, `postprocessing.shaders`, `postprocessing.filter_nodes`, `postprocessing.display_nodes`, `postprocessing.screen_space`, `postprocessing.ssgi`, `postprocessing.taau`, `postprocessing.traa` | Unbounded distance, derivative, and motion-vector norms use shared lengths. |

## Reviewed arithmetic kept unchanged

The audit includes scalar `sqrt`, reciprocal square roots, direct
sum-of-squares helpers, normalization calls, angle denominators, and
cross-product construction before those calls. These expressions are not
blind replacements of every square root.

| Group | Reason to keep the arithmetic |
|---|---|
| `geometries.edge_split`, `geometries.surface_sampler` area, `geometries.capsule`, `geometries.extrude` edge lengths | Finite stored Float32 coordinates are widened before subtraction and multiplication. Their two- and four-factor products fit in Float64, including the smallest Float32 subnormals. |
| `geometries.rounded_box`, `geometries.teapot` | Norms operate on the bounded unit-box construction or fixed control-patch derivatives, before the physical size is applied. |
| `geometries.cylinder` | Its existing fallback already forms a safe direction from widened height and radius difference before an overflowing slope is used. |
| `loaders.lwo._normalize`, final USD stored-normal normalization | Operands are widened Float32 components. The range-sensitive pre-storage area accumulators are corrected separately. |
| `objects.gaussian_splat` bounds and column lengths | The existing widened Float32 products and outward-rounding proof remain intact. Ellipsoid intersection roots are discriminants, not vector normalizers. |
| `objects.marching_cubes`, `render.flakes_texture`, `postprocessing.gtao` noise | Directions and lengths come from a bounded grid or bounded random construction. |
| `loaders.draco_attributes`, `loaders.meshopt`, `loaders.spz` | The relevant norm operands are bounded integer or packed-unit-vector reconstructions. Integer square roots and codec-specific rounding remain unchanged. |
| `renderers.projector` frustum rows | Rows come from widened Float32 view and projection matrix products. Their norms fit in Float64. Their plane constants must keep the same divisor. |
| `math.obb`, `math.box_extent`, `math.matrix4` stretch bounds, existing ray and collision helpers | Existing wide arithmetic or certified finite bounds already protect these norms. Raw squared-distance return values are not changed into lengths. |
| `math.quaternion`, `math.vector4` rotation formulas; curve frames; light probe sampling; BRDF, refraction, and random-direction formulas | Operands are unit directions, unit quaternions, bounded sampling values, or documented trigonometric expressions. |
| `render.splatrule`, image/color statistics, `loaders.collada`, SVG arc solving, control-ray quadratics | Covariance roots, variance, attenuation inversion, and quadratic discriminants have distinct contracts. Replacing only a square root would not correct a prior determinant, product, or subtraction. |
| Shader graph `sqrt` and inverse-square-root nodes | These are user-requested arithmetic operations, not a library normalization policy. |

The audit does not promise arbitrary-range matrix inversion, polygon topology,
transformed point storage, covariance construction, or raw dot and cross
outputs. Those operations keep their own documented contracts. Building
extensions and CARLA quantity-boundary migration are outside this change.

## Zero and nonfinite inputs

- Vector normalizers keep a true zero vector zero
- Zero quaternions keep the identity rule
- Vector angles keep the right-angle rule when either direction is zero
- Conditional-line zero edges retain their previous NaN result
- MikkTSpace keeps its default frame for invalid faces
- Scalar helper NaN and infinity rules remain explicit in `math.norm`
- The Float64 reciprocal helper retains direct IEEE nonfinite arithmetic
- Loader matrix decomposition refuses nonfinite values and unrepresentable scales

`Vector2.angle()` returns zero for two positive zeros. Signed zeros follow
`atan2`; two negative zero components return a half turn. This documentation
correction is already present in the vector API and [Math](Math).

## Verification

`tests/test_norm.mojo` and `tests/test_norm_consumers.mojo` cover the original
shared helpers and the first consumer group. The focused
`tests/test_remaining_norm_consumers.mojo` covers the remaining groups.
It checks all Float32 binary exponents, subnormals, extreme component ratios,
original coordinate cancellation, and zero and nonfinite rules.
It also checks public geometry, loader, lighting, and texture paths.
It uses exact axes, known diagonal lengths, orthogonal directions, and
scale-invariant expected results.

`tests/test_norm_review_regressions.mojo` contains the independent-review
counterexamples. It checks cancelling original coordinates, mixed-exponent
products, subnormal rounding, native Float64 areas, and zero/nonfinite
compatibility. Ordinary Sculptor normal fixtures are included.

`tests/test_gpu.mojo` includes a device regression for shared frames, light
directions, and mip levels across extreme products. The test compares CPU and
device values with independent unit-direction expectations.

Compatibility checks retain the existing ordinary-range fixture tolerances.
A targeted Metal compile checks changed device-reachable arithmetic. It is
not an actual device parity result. Full aggregate checks, complete coverage,
and actual-device parity remain separate release gates.
