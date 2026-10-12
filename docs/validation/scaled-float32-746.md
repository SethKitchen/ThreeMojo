# Float32 subnormal successor (#746)

This supplemental source edge admits two exact arithmetic-provider changes: the scaled-product subnormal split and the Apple GPU matrix inverse.
It preserves the earlier historical records and their original owner guards.
Source admission does not grant native qualification or change coverage obligations.

## Exact arithmetic boundary

The sole production endpoint is `math/scaled_products.mojo` from PR746 head `2993af0af137426014a8be73f15eca6fd11325e9`.
Its complete SHA256 is `632438eb32acc53e5d4b10e8aa0ca9049a0fc2c5cd7e3d815039626ff3409c86`.
The predecessor SHA256 is `b504f18cff7df27bff4fbf92fbed7aa4868518f1b1507ea1331540d7e6f0afbb`.
The pure `scaled_float32_contracts.py` leaf seals both complete endpoints and the unique ordered inverse inventory.
The inverse reconstructs every predecessor byte, rather than accepting a replacement hash alone.

A separate whole-source comparison removes the complete exact Float32 branch and its two exact support imports.
The resulting source must equal the complete predecessor.
No Float64 statement, overload, signature, fallback, or remaining import changes.
The compile-time dtype guard excludes the new branch for Float64.
The two new imports provide `std.bit/count_leading_zeros` and `std.memory/bitcast`.

For a nonzero binary32 subnormal, let `n` be its 23-bit significand.
Let `top` be the position of its highest set bit.
Its value is the signed integer `n` times `2^-149`.
The new branch constructs fraction `sign * n / 2^(top + 1)` and returns exponent `old_exponent + top - 148`.
The fraction has magnitude in `[0.5, 1)`, retaining every significand bit.
Recombination gives the original value times `2^old_exponent`; integer bit reads avoid a device floating-point flush.

Zero, normal, and nonfinite Float32 inputs retain the entire prior fallback.
The private `_split` contract accepts finite values.
Pinned `frexp` does not promise nonfinite output classes.
Nonfinite replay therefore compares returned fraction bits and exponent against the exact prior fallback.
It creates no new NaN or infinity contract for `_split`.

## Apple GPU matrix inverse boundary

The second production endpoint is `math/matrix_inverse.mojo`.
Its complete SHA256 is `1bf500ddd641fa30c3f01ee1e17ccc33063b30a5198a01da20f3d340b04b30da`.
The predecessor SHA256 is `34dd50cb00f3efe560ae73b1f0be8d2a399d045e1f9db699ce507b6da6ec09ee`.
The leaf seals two ordered inverse spans that reconstruct every predecessor byte.

`verify_host_inverse_domain` makes a separate whole-source comparison.
It removes the complete Apple-only block and the two support imports, `std.memory/bitcast` and `std.sys.info/is_apple_gpu`.
It then renames `_inverse_exact_cofactors` back to `_inverse_wide`.
The resulting source must equal the complete predecessor.

The new `_inverse_wide` has one statement that chooses a function at compile time.
Off an Apple GPU it chooses `_inverse_exact_cofactors`, which is the predecessor's `_inverse_wide` byte for byte.
So the host and CUDA execute the predecessor's exact cofactors, and no Float64 statement, signature or fallback changes.
On an Apple GPU, which has no Float64, the block's `_inverse_scaled_float32` picks a power of two for each column and each row from the entries' exponents.
It divides each entry by its two powers once, in steps of normal powers, then inverts by Float32 Gauss-Jordan elimination with partial pivoting.
The scaling is exact unless a scaled entry is subnormal, and the final rescaling is exact unless an inverse entry leaves the normal range.
Singularity is decided by a zero pivot, so a matrix within rounding of singular can go either way, unlike the host's exact cofactors.

The pinned native entry `tests/test_matrix_inverse_float32.mojo` compares the two inverses on the host.
It covers extreme scales, row exchanges, singular inputs and nonfinite inputs.
It includes the reviewed counterexamples: `diag(2^127, 1)`, whose row power would be the subnormal `2^-127`, and the mixed matrix `[[1e30, 1e-10], [1e30, 2e-10]]`, whose second column row-first scaling would make subnormal.
`tests/test_gpu.mojo` runs both on the device.
Its exact project import closure contains only:

- `tests/test_matrix_inverse_float32.mojo`
- `math/matrix_inverse.mojo`
- `math/matrix_determinant.mojo`
- `math/__init__.mojo`

The determinant provider and the math package initializer remain byte-identical to the composed source base.
`math/matrix_determinant.mojo` is sealed as a provider input.

## Independent formatting authority

The four formatted CARLA witnesses remain independently admitted by PR744's `witness_format_contracts.py`.
They cover chord endpoints, junction endpoints, speed-parser exceptions, and width overflow.
That separate leaf preserves its exact byte endpoints, inverse spans, and constrained token comparison.
The math leaf neither absorbs those edges nor authorizes additional formatting.
The two PR744 physics-test formatting changes remain base ancestry.

## Native witness and concrete resolver context

The pinned native entry is `tests/test_scaled_products_subnormal.mojo`.
Its exact project import closure contains only:

- `tests/test_scaled_products_subnormal.mojo`
- `math/norm.mojo`
- `math/scaled_products.mojo`
- `math/__init__.mojo`

The public norm provider and math package initializer remain byte-identical to the composed source base.
Standard-library imports remain subject to the existing standard-namespace shadow checks.
The entry's parent determines the `tests/` context, and the established resolver adds the repository root.
The owner physically traverses these imports and requires exact closure equality.
It applies this source-bound native context to root and supplied include-root checks.

This context proves the pinned witness's concrete `tests/` and root interpretation.
It does not certify arbitrary production entrypoints or introduce a global production-entry guarantee.
The arithmetic delta adds no project import, module path, caller, or overload.
Its new standard-library imports retain the conservative existing rejection of project `std` shadows.

The native witness preserves signed Float32 subnormal boundaries, adjacent powers, spread samples, and exponent offsets.
The reference constructs signed `n * 2^-149` directly in Binary64 before calling `frexp`.
It never widens the Float32 subnormal input.
The complete finite Float64 predecessor replay remains, including subnormal rescaling and signed zero.
Both precisions replay signed infinities, quiet NaNs, and signaling NaN payloads against the prior fallback at multiple offsets.

Public nonfinite behavior is tested separately through unchanged `math.norm` helpers in both precisions.
Lengths and normalization cover two, three, and four components, including mixed NaN and infinity inputs.
The witness also checks `reciprocal_normalized3` and the normalized helpers' distinct NaN rules.
These public assertions do not impose private `_split` semantics or change production arithmetic.

## Admission, owners, and receipts

The full-audit owner maps the arithmetic edge only in `unchanged_inputs` and `native_dependency_inputs`.
PR744 independently maps its four witness edges in `native_witnesses` and `native_dependency_inputs`.
Every mapping starts at the exact immutable path and historical hash.
Seed-count and border-parser extend only their existing arithmetic-provider premise.
Construction-boundary extends its precise supplemental fallback and actual-byte receipt while preserving `CONSTRUCTION_BOUNDARY_SOURCE_SHA256` and every original physical read.

The pure math leaf performs no filesystem access and grants no checkout admission.
Owners bind its actual executing source, function defaults, module-code witness, Python controls, this document, and native proof inputs.
Physical reads, import traversal, known-path discovery, resolver checks, ownership checks, operation observations, sticky failures, and final rereads remain enforced.
Receipts identify actual current bytes.
Edge descriptors are not cached verification results.

Established full-audit owners retain their complete dependency inventories, compiled-entry census, whole-source observations, caller checks, and final physical sweeps.
Their protected closure already includes the legitimate `extensions/carla/math.mojo` provider.
The supplementary witness context does not replace or narrow those established guards.
Standalone math admission accepts that legitimate CARLA file without adding it to the seven-file native closure.

Historical seed and construction owners retain their original dependency, caller, and standard-namespace checks.
Their original guards do not promise the current full gate's complete compiled-entry census.
This supplemental edge neither claims to repair nor broaden those historical production-resolution guarantees.
A new production entry beside a local math shadow remains governed by its owner's original checks.

Standalone and pending historical admissions physically observe the narrow proof closure and freshly discover known Mojo paths.
They derive native entry context from the pinned witness rather than classifying every repository source as a compiled entry.
Final checks reread consumed bytes, compare fresh path discovery, recheck scoped resolvers, and verify the executing checker image.
The supplemental native resolver lifetime remains separate from each owner's established resolver state.
Required partial historical roots remain supported without storing repeated whole-repository source images.

The historical `full-audit-cleanup-successor.json`, `seed-count-successor.json`, and `border-parser-successor.json` records remain unchanged.
The construction-boundary source table also remains unchanged.
Any live checker-pin or read-site adjustment must describe the reviewed integrated source without rewriting historical authority.

## Required qualification

This source delivery still requires independent review and fresh runtime qualification on the final integrated source.
Run the new Python controls in clean normal CPython and clean optimized `-O` CPython.
Replay full-audit, seed-count, border-parser, construction-boundary, and shared-helper controls, including current and partial historical roots.
Cover truthful receipts, inverse mutations, unknown endpoints, source-read failures, missing inputs, aliases, shadows, late resolver changes, and caught-error restoration.
Verify that narrow historical math admission does not classify all-source entries or consume unrelated repository source bytes.

Use the pinned compiler and ordinary native-support build route, compiling outside the timed execution window.
Run `tests/test_scaled_products_subnormal.mojo`, `tests/test_matrix_inverse_float32.mojo` and the four PR744 formatted suites through the original five-second runner gate.
Retain junction's native C support fixture and the original FENV checks.
Run the affected existing scaled-product and OpenDRIVE Float64 consumers, then the required CPU and coverage gates.
Do not increase timeouts, remove guards, or substitute earlier candidate results.

Preserve PR744's producer follow-up list and genuinely regenerate both anatomy reports from the final integrated producer source.
Old report digests are not evidence for changed producer inputs.
GPU qualification remains separate and must cover the final combined rasterizer and water source on the target device.
Root owns execution, report regeneration, and final qualification decisions.
No native, Python, coverage, or GPU pass is claimed by this source document.
