# GLSL source extension validation

The extension preserves exact 32-bit integer values and adds explicit 2D texture gradients. It keeps bounded loop compilation and explicit resource failures. This is a documented GLSL subset, not full GLSL parity.

## Reference contract

The upstream baseline is three.js r180 and GLSL ES 3.00. The independent reference runs `#version 300 es` shaders through Mesa GLES. It does not import ThreeMojo.

- 87 unsigned cases cover boundaries at 2 ** 24, 2 ** 31 and 2 ** 32 - 1
- 35 loop cases cover body and condition counts, jumps, runtime bounds and nested growth
- 28 gradient cases cover mip selection, wraps, filters, coordinate transforms and runtime uniforms
- Exact integer readback uses RGBA32UI and UInt32 words
- Gradient comparisons retain an absolute tolerance of 0.000002

The recorded maximum gradient error is 3.86e-9. Captured shader sources, uniforms and expected output words are in [the reference fixtures](../fixtures/glsl614/README.md).

## Integer execution and storage

Distinct integer value types carry UInt32 payload bits through graph storage and registers. Integer arithmetic never treats those payloads as numeric floats. Joins, swizzles, selections, variables, arrays, structures and function boundaries retain all bits.

The signed path preserves unsigned-to-signed round trips. Explicit float conversions can round. Known invalid conversions and shift counts fail during compilation. Undefined runtime conversion, divide and shift cases have bounded documented results.

Unsigned uniforms use `set_uniform_uint`. The original float setter retains its prior overloads. Three-component unsigned uniforms take three `UInt32` arguments because the pinned compiler cannot lower SIMD width three.

Integer programs use exact `codeBits` JSON words. The reader keeps legacy float `code` support. Only checked integer payload spans permit nonfinite-shaped bit patterns. Control words, float data, matrix data and sampler metadata remain checked.

## Loop and texture limits

Finite `while` and `do` fixtures retain their exact results at 63, 64, 65, 128 and 256 bodies. Another 19 independent GLES controls check logical and conditional call effects. Skipped `out` and `inout` writes and discards are gated before loop-exit proofs. Exhausted or unproved exits fail before a renderer receives a program. Graph, instruction, register and anisotropic-tap limits remain unchanged.

`textureGrad` accepts `sampler2D` and three `vec2` values. Both rasterizers use the same footprint arithmetic. Nonfinite constant gradients fail compilation. Invalid runtime coordinates or gradients return transparent black before sampling.

The original rotated 16:1 footprint test failed identically on the baseline and initial candidate. Minor-axis cancellation produced level 0.00000550343 instead of zero. The shared correction preserves the original workload and 0.000001 tolerance.

The minor axis now uses a compensated determinant divided by the major axis. Extreme products retain separate exponents. Round footprints keep identical axes and one tap. The [55 independent controls](../fixtures/glsl614/footprint_axes.json) use 100-digit arithmetic on exact Float32 inputs.

## Qualification scope

The 19 focused native suites pass 580 tests. They use Mojo 1.1.0, `--Werror`, and the existing five-second per-test runner. They include independent references and existing GLSL, node, texture, computation, serialization and loader workloads. No existing tolerance or workload was reduced.

GPU-specific tests check exact payload transport, explicit-gradient rendering and nonfinite inputs. Their CUDA-targeted `sm_80` build passes with `--Werror` on MAX 26.6.0. The integer interpreter and raster kernel also emit Metal 4 IR successfully. Device execution is blocked by missing `libnvidia-ml.so.1` in this environment. Compilation alone does not establish device parity. Full repository aggregates, coverage and physical-device qualification remain separate end-of-batch checks.
