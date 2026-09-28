# TSL functions

Four modules give three.js's TSL function library as functions on a `NodeGraph`. Each function builds nodes that [Node materials](Node-materials) already has. So both rasterizers run it with the one interpreter, and no function adds an instruction to the bytecode.

| Module | three.js |
|---|---|
| `materials/tsl_utils.mojo` | `src/nodes/utils`: triplanar mapping, sprite sheets, oscillators, `remapClamp`, `rotate`, `equirectUV`, `matcapUV` and the normal packings |
| `materials/tsl_noise.mojo` | `triNoise3D`, and `examples/jsm/tsl`: `curlNoise`, `voronoiNoise` and `RNoise` |
| `materials/tsl_bits.mojo` | `src/nodes/math`: `hash`, the bitcasts, the bit counts, the float packings and the packed 4x8 integers |
| `materials/tsl_helpers.mojo` | `examples/jsm/tsl/utils`: `Raymarching`, `SoftParticles` and `SpecularHelpers` |

## Use one

Each function takes the graph first, then three.js's inputs as nodes. It returns a `NodeRef`, as a `NodeGraph` method does.

```mojo
from materials.tsl_noise import voronoi2d
from materials.tsl_utils import osc_sine, triplanar_texture

var graph = NodeGraph()
var map = graph.texture_uniform("map", texture)
var cells = voronoi2d(graph, graph.mul(graph.uv(), graph.float(4)), graph.time())
var ground = triplanar_texture(graph, map, scale=graph.float(2))
var pulse = osc_sine(graph)
graph.set_output(
    COLOR_NODE,
    graph.mul(graph.swizzle(ground, "rgb"), graph.mix(cells, graph.float(1), pulse)),
)
```

An input that three.js gives a default is an `Optional` here. `None` reads three.js's default, for example `time` or `uv()`. Each function refuses a node of the wrong type when you build it, with three.js's name of the function in the error.

## Utilities

| Function | three.js | What it gives |
|---|---|---|
| `triplanar_textures(g, x, y, z, scale, position, normal)` | `triplanarTextures` | Three textures read along the three axes, blended by the normal. `y` and `z` are `x` if none. |
| `triplanar_texture(...)` | `triplanarTexture` | The same function. |
| `spritesheet_uv(g, count, uv, frame)` | `spritesheetUV` | The coordinate of one frame of a sheet of `count.x` by `count.y` frames, from the top left. |
| `osc_sine`, `osc_square`, `osc_triangle`, `osc_sawtooth` | `oscSine` and the rest | A wave from zero to one with a period of one. `t` is `time` if none. |
| `remap_clamp(g, x, in_low, in_high, out_low, out_high)` | `remapClamp` | `NodeGraph.remap`, held inside the second range. |
| `rotate(g, position, rotation, order)` | `rotate` | A `vec2` turned by a `float`, or a `vec3` turned by a `vec3` of angles in an `EulerOrder`. |
| `equirect_uv(g, direction)` | `equirectUV` | Where a direction lands on an equirectangular map. |
| `equirect_direction(g, uv)` | `equirectDirection` | The direction of an equirectangular coordinate. |
| `position_world_direction(g)` | `positionWorldDirection` | The unit direction from the camera to the fragment. |
| `matcap_uv(g)` | `matcapUV` | Where the view normal reads a matcap. |
| `pack_normal_to_rgb`, `unpack_rgb_to_normal`, `unpack_normal` | `packNormalToRGB` and the rest | A normal as a color, and back. |

`rotate` multiplies the three axes' matrices in the order, first on the left, as three.js's `RotateNode` does. `XYZ` is the default. An order that does not name three different axes is refused.

## Noise

| Function | three.js | What it gives |
|---|---|---|
| `tri_noise_3d(g, position, speed, time)` | `triNoise3D` | Four octaves of triangle waves, each warped by the last. |
| `snoise(g, v)`, `snoise_vec3(g, x)` | `snoise`, `snoiseVec3` | Simplex noise of a `vec3`, and three of moved points. |
| `curl_noise(g, p)` | `curlNoise` | The curl of `snoise_vec3`, by central differences. |
| `permute(g, x)` | `permute` | `mod(x * x * 34 + x, 289)` of a `vec4`. |
| `hash2d`, `hash3d` | `hash2d`, `hash3d` | The sine hashes of `voronoiNoise.js`. |
| `voronoi2d(g, p, time)`, `voronoi3d(g, p, time)` | `voronoi2d`, `voronoi3d` | The squared distance to the nearest moving point of the cells around `p`. |
| `analytic_noise(g, uv, sample_index, resolution, seed)` | the function of `bindAnalyticNoise` | Four numbers of a low-discrepancy sequence that tiles the screen every 32 pixels. |

A TSL `Loop` with a fixed count is a loop in Mojo that builds the body each time through. So the Voronoi noise and `triNoise3D` open no `Loop` block. `snoise_vec3` keeps three.js's order of operations: its first and third components scale the point before the noise, and its second scales the noise.

`assets/tsl/tsl_reference.py` transcribes these functions in 32-bit floats. The tests check the values that it gives.

## Integers and bits

A node's value is a float. A float holds a whole number exactly only up to 2 ** 24, and a `uint` of three.js holds 32 bits. So `materials/tsl_bits.mojo` holds a 32-bit word as a `NodeWord`: a `vec2` node of its low 16 bits and its high 16 bits.

| Function | three.js |
|---|---|
| `word(g, x)`, `word_constant(g, value)` | `uint(x)`, a `uint` constant |
| `word_to_uint(g, w)`, `word_to_int(g, w)` | `toFloat()` of a `uint` and of an `int` |
| `word_add`, `word_mul`, `word_bit_and`, `word_bit_or`, `word_bit_xor` | `add`, `mul`, `bitAnd`, `bitOr`, `bitXor` of two `uint`s |
| `word_shift_left(g, w, count)`, `word_shift_right(g, w, count)` | `shiftLeft`, `shiftRight` of a `uint` |
| `hash(g, seed)` | `hash` |
| `float_bits_to_uint`, `float_bits_to_int`, `uint_bits_to_float`, `int_bits_to_float` | the bitcasts of `BitcastNode` |
| `count_one_bits`, `count_leading_zeros`, `count_trailing_zeros` | `countOneBits` and the rest |
| `exp2_whole(g, e)` | none: 2 ** `e`, exact, for a whole `e` from -126 to 127 |

Each operation on a word works on the halves. A product cuts one word into bytes first, so each partial product is less than 2 ** 24. A shift reads the low five bits of its count, as a GPU does. So a word is exact on both backends, and `hash` gives three.js's bits.

The bit counts read a `float` or a vector of whole numbers, each a 32-bit two's complement integer. They count each half and add the two counts.

## Packing

| Function | three.js |
|---|---|
| `pack_snorm_2x16`, `pack_unorm_2x16`, `pack_half_2x16` | `packSnorm2x16`, `packUnorm2x16`, `packHalf2x16` |
| `pack_snorm_4x8`, `pack_unorm_4x8` | `packSnorm4x8`, `packUnorm4x8` |
| `unpack_snorm_2x16`, `unpack_unorm_2x16`, `unpack_half_2x16`, `unpack_snorm_4x8`, `unpack_unorm_4x8` | the `unpack` functions of the same names |
| `pack4x_u8`, `pack4x_i8`, `pack4x_u8_clamp`, `pack4x_i8_clamp` | `pack4xU8` and the rest |
| `unpack4x_u8`, `unpack4x_i8`, `dot4_u8_packed`, `dot4_i8_packed` | `unpack4xU8` and the rest |

A pack gives a `NodeWord`, and an unpack reads one. The first component goes in the lowest bits. A fixed-point pack rounds a half to the even whole number. A half-precision pack rounds to the nearest half, a tie to the even one. A magnitude from 65520 packs as infinity.

## Raymarching

`RaymarchingBox(g, steps, world_to_local)` opens a loop that marches a ray from the camera through the box from -0.5 to 0.5 of its space. `Raymarch.End(g)` moves the ray one step on and closes the loop. The code between the two is the body of three.js's callback. This example sums a 3D texture, `volume`, along the ray.

```mojo
var box_to_local = box_world
box_to_local.invert()
var to_local = graph.uniform("toLocal", box_to_local)
var density = graph.Var(graph.float(0))
var march = RaymarchingBox(graph, 64, to_local)
var here = graph.get(march.position_ray)
var sample = graph.swizzle(graph.texture_3d(volume, graph.add(here, graph.float(0.5))), "r")
graph.assign(density, graph.add(graph.get(density), graph.mul(sample, march.step_size)))
march.End(graph)
graph.set_output(OPACITY_NODE, graph.saturate(graph.get(density)))
```

A fragment whose ray misses the box is thrown away. The ray starts where it enters the box, or at the camera inside it. A step is the shortest of `1 / abs(direction)` over `steps`.

The bytecode has no jumps, so the loop runs `raymarch_count(steps)` times: `ceil(sqrt(3) * steps) + 1`. That is enough for the diagonal of the box at the shortest step. A `Break` stops the loop where the ray leaves the box, where three.js's loop ends. A count past `MAX_LOOP_COUNT` is refused.

## Soft particles

`soft_particles(g, viewport_depth, near, far, opacity, distance, contrast)` fades a particle where it nears the scene behind it. The gap is the particle's view `z` less the scene's, over `distance`. `contrast_curve` makes the gap an S curve, and the opacity multiplies it.

The scene's depth is a node that you give, from zero at the near plane to one at the far plane. `perspective_depth_to_view_z` takes it to the view `z`. `near`, `far` and `distance` are `Length`s. A camera that is not `0 < near < far`, and a distance that is not above zero, are refused.

## Specular helpers

| Function | three.js |
|---|---|
| `sample_ggx_vndf(g, v, ax, ay, r1, r2)` | `SampleGGXVNDF`, the bounded visible normals of Eto and Tokuyoshi |
| `d_gtr(g, roughness, n_dot_h, k)` | `D_GTR` |
| `smith_g(g, n_dot_x, alpha)`, `geometry_term(g, n_dot_l, n_dot_v, alpha)` | `SmithG`, `GeometryTerm` |
| `ggx_vndf_pdf(g, n_dot_h, n_dot_v, roughness)` | `GGXVNDFPdf` |
| `f_schlick(g, f0, theta)` | `F_Schlick` of `SpecularHelpers.js` |
| `get_specular_dominant_factor(g, n_dot_v, roughness)` | `getSpecularDominantFactor` |
| `ggx_reflection_sample(g, n, v, roughness, metalness, albedo, xi)` | `ggxReflectionSample` |
| `equirect_uv_to_dir(g, uv)`, `equirect_dir_pdf(g, direction)` | `equirectUvToDir`, `equirectDirPdf` |
| `mis_power_heuristic(g, pdf_a, pdf_b)` | `misPowerHeuristic` |

`ggx_reflection_sample` gives a `GgxReflectionSample` of six nodes, three.js's struct: `reflect_dir`, `sample_weight`, `pdf`, `n_dot_v`, `alpha` and `f0`. `ENV_RAY_LENGTH` and `ENV_RAY_LENGTH_THRESHOLD` are `Length`s.

## Where this port differs

- `triplanar_textures` reads the world position and normal by default. three.js reads the local ones, and a fragment here has no local position. For a mesh at the origin, the two are the same.
- `RaymarchingBox` takes the inverse of the box's world matrix as a node. three.js reads the model matrix and the local position, which a fragment here does not have.
- `soft_particles` reads the scene's depth from a node that you give. three.js reads `viewportDepthTexture()`.
- A vector of words is a list of `NodeWord`s. A bitcast, a bit count and a pack of a vector work one component at a time.
- A bitcast of a float and a half-precision pack flush a subnormal to zero, as a GPU that flushes subnormals does. A NaN gives no fixed word.
- `word` and `hash` wrap a negative number up by 2 ** 32, as `NodeGraph.unsigned` does. WGSL holds it at zero.
- `normalize` leaves a zero vector at zero. So `ggx_reflection_sample` takes its second frame for a normal along `z`, where a GPU gives NaN.

## What is not ported

- `viewportDepthTexture()`: the renderer keeps no depth of the opaque scene for a node to read. Give `soft_particles` the depth as a node.
- The general `bitcast(value, type)` of a vector. Use the four named bitcasts on each component.
- `bayer16` and `bayerDither` of `Bayer.js`. They are not in the issue.
