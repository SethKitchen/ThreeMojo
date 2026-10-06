# GLSL3 reference fixtures

These fixtures contain 150 independent Mesa GLES3 results. There are 87 unsigned integer cases, 35 loop cases and 28 explicit-gradient cases. The reference does not import or execute ThreeMojo.

## Reproduce

Use Python 3 and a system `libEGL.so.1` with software GLES3 support. No Python package is required. Run from the repository root:

```sh
python3 tools/reference_glsl614.py --verify docs/fixtures/glsl614/fixtures.json
python3 tools/reference_glsl614.py --output out/glsl614-reference
```

The process requests a surfaceless software context. The capture used Mesa 25.0.7, llvmpipe LLVM 19.1.7, an OpenGL ES 3.2 context and shaders with `#version 300 es`. The JSON stores the complete source, uniforms, texture recipe, analytical expectations, observed values and provenance.

Unsigned results are read through an RGBA32UI framebuffer as four exact UInt32 values. Python uses arbitrary-precision integers and explicit modulo 2 ** 32 arithmetic for the independent expectations. No unsigned answer passes through a float. The TSV files also record the exact little-endian output bytes.

Gradient shaders sample an authored 16-by-8 RGBA16F texture with five mip levels. Texel `(x, y)` at level `l` is `((l + 1) / 8, x / 16, y / 8, 1)`. The reference records the filter and wrap modes for each case. Analytical sampling uses the supplied float32 gradients.

The fixed absolute tolerance is 0.000002. The captured maximum error is 3.86e-9. Other conforming drivers can differ in permitted LOD and filter precision.

## Native checks

`tests/test_glsl614_reference_uint_loops.mojo` adapts the reference bodies to the float color output supported by ThreeMojo. It compares all four exact integer lanes before converting the final boolean to color. It keeps the original uniform inputs and fragment-coordinate context. Exact unsigned updates use `set_uniform_uint`; float, signed and bool inputs keep the existing setter. `tests/test_glsl614_reference_refusals.mojo` checks explicit resource refusals for ten runtime-bound loops and one nested loop. A refusal is distinct from a truncated result.

`tests/test_texture_grad.mojo` checks the 28 gradient references against the real texture sampler. GPU tests are separate. Software GLES results do not establish MAX GPU parity, and a GPU compile does not establish physical-device execution.

The source contract is the [GLSL ES 3.00 specification](https://registry.khronos.org/OpenGL/specs/es/3.0/GLSL_ES_Specification_3.00.pdf), especially sections 5.4, 5.9, 6.3 and 8.8. The upstream comparison is three.js r180, which sends GLSL source to the graphics driver. These cases do not establish full GLSL parity.

## Footprint correction controls

`footprint_axes.json` records 55 singular-value controls for exact Float32 inputs. A separate 100-digit Decimal calculation gives each major and minor axis. Verify the captured values with:

```sh
python3 tools/reference_texture_axes.py docs/fixtures/glsl614/footprint_axes.json
```

The native `test_texture_axes` suite also checks round footprints. Equal axes must keep one tap, including after axis swaps and extreme scaling.

## Conditional call effects

`short_circuit.json` adds 19 exact GLES3 controls for calls in logical and conditional expressions. They cover constants, runtime flags, unsigned wrap and final loop conditions through 256 bodies. Verify them with:

```sh
python3 tools/reference_glsl614.py --verify docs/fixtures/glsl614/short_circuit.json
```

The native `test_glsl_short_circuit` suite compares 18 outputs and checks one explicit resource refusal. Its last `do` case takes 257 bodies to reach counter value 256. The controls include the final-condition case that previously incremented a counter from 65 to 66.
