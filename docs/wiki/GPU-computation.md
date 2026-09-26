# GPU computation

`render/computation.mojo` steps float images with GLSL fragment shaders. It is three.js's `GPUComputationRenderer` from `examples/jsm/misc/`. A simulation keeps its state in the images, for example the positions and velocities of a flock, and runs one step a frame.

```mojo
var computation = GPUComputationRenderer(64, 64)
var position = computation.add_variable("position", MOVE, start^)
var velocity = computation.add_variable("velocity", STEER, computation.create_texture())
computation.set_variable_dependencies(position, [position, velocity])
computation.set_variable_dependencies(velocity, [position, velocity])
computation.init()
# For each frame:
computation.compute()
var map = assets.textures.add(computation.current_texture(position))
```

## Variables

A variable is an image of `size_x` by `size_y` texels, four floats for each texel, and the shader that computes its next state. `add_variable(name, shader, initial)` adds one and returns its place. `create_texture()` returns an image of zeros for a start.

`set_variable_dependencies(variable, dependencies)` says which images the shader reads. A variable that reads its own last image lists itself. `init()` declares a `sampler2D` for each dependency, named after it, and defines `resolution` as the image size. Then it compiles each shader with the [GLSL subset](Node-materials).

Set a shader's other uniforms on `programs[variable]` after `init`, for example `programs[velocity].set_uniform("delta", 0.016)`.

## A shader

A shader finds its texel as three.js's shaders do, and writes `gl_FragColor`:

```glsl
void main() {
    vec2 uv = gl_FragCoord.xy / resolution.xy;
    vec4 p = texture2D( position, uv );
    vec4 v = texture2D( velocity, uv );
    gl_FragColor = vec4( p.xyz + v.xyz * 0.016, p.w );
}
```

All four numbers are kept as they are. They are not clamped and not premultiplied. A read gets the texel that its coordinate falls in, as three.js's `NearestFilter` does. The variable's `wrap_s` and `wrap_t` say what a coordinate past an edge reads. They are `CLAMP` unless set. A texel that the shader throws away with `discard` keeps its value.

## A step

`compute()` runs each variable's shader once, at every texel. Each variable reads the images as they were before the step. So a variable that runs after another in the same step reads the other's old image, as in three.js.

`current_image(variable)` returns an image now. `alternate_image(variable)` returns the image before the last step. The images lie row by row from the bottom, so texel (x, y) starts at `(y * size_x + x) * 4`. `current_texture(variable)` returns a float texture for a material to read.

## On the GPU

`GpuComputation.compute(computation)` in `render/gpu.mojo` runs a step on the device, one launch for each variable. The host and the device run the same function at each texel, `compute_texel`, so the images agree to the float. `tests/test_gpu.mojo` checks this.

## Where this port differs

- The images are float lists. three.js keeps them in render targets.
- Only `FloatType` and `NearestFilter` are ported. `setDataType` and a linear filter are not.
- `init` raises when a shader is refused. three.js returns an error string for a missing dependency. Here a dependency that is not a variable raises in `set_variable_dependencies`.
- `gl_FragCoord.w` is one. three.js's is one over the clip-space `w`, which is also one on its full-screen quad.
