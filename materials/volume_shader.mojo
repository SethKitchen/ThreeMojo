# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's `VolumeRenderShader1`, `examples/jsm/shaders/VolumeShader.js`:
a `ShaderMaterial` that marches a ray through a 3D texture of intensities
and colors it through a colormap, compiled by the GLSL subset.

Draw it on the back faces of a box that spans the volume, as three.js's
`webgl2_materials_texture3d` example does: a `BoxGeometry` of the volume's
size, moved so that its local coordinates run from -0.5 to the size minus
0.5 on each axis, with a `BACK_SIDE` material. Set `u_data` to the 3D
texture, `u_cmdata` to the colormap, `u_size` to the volume's size in
texels, `u_clim` to the intensities the colormap spans, `u_renderstyle` to
`VOLUME_MIP` or `VOLUME_ISO`, and `u_renderthreshold` to the surface an
ISO render finds.

The source is three.js's but for four things the subset asks:

- The vertex shader hands on the world position. The fragment shader takes
  it and the camera into the box's own space by `u_world_to_local`, the
  inverse of the box's world matrix, where three.js inverts the
  model-view matrix per vertex. Set it when the box moves; it is the
  identity by default.
- The ray starts at the camera, not at the near plane: the two agree for
  a camera outside the volume.
- A ray takes at most `VOLUME_STEPS` steps, where three.js takes 887. A
  loop is unrolled, and a step is one texel, so a volume of up to that
  many texels across is marched whole.
- An ISO render finds the first step past the threshold in the march and
  refines and lights it once after, where three.js does both in the loop
  and leaves it. The steps and the colors are the same.
"""

from materials.glsl import compile_shader_material
from materials.nodes import NodeProgram
from math.matrix4 import Matrix4
from math.vector2 import Vector2


# The most steps a ray takes through the volume, one texel each.
comptime VOLUME_STEPS = 96
# `u_renderstyle`'s two values: the brightest texel along the ray, and the
# first surface past the threshold, lit.
comptime VOLUME_MIP = 0
comptime VOLUME_ISO = 1

# The vertex shader: the world position, for the fragment to march from.
comptime VOLUME_RENDER_VERTEX = """
varying vec3 v_world;
void main() {
    v_world = (modelMatrix * vec4(position, 1.0)).xyz;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
"""

# The fragment shader: three.js's, but for the changes the module lists.
comptime VOLUME_RENDER_FRAGMENT = """
uniform vec3 u_size;
uniform int u_renderstyle;
uniform float u_renderthreshold;
uniform vec2 u_clim;
uniform sampler3D u_data;
uniform sampler2D u_cmdata;
uniform mat4 u_world_to_local;

varying vec3 v_world;

const int REFINEMENT_STEPS = 4;
const float relative_step_size = 1.0;
const vec4 ambient_color = vec4(0.2, 0.4, 0.2, 1.0);
const vec4 diffuse_color = vec4(0.8, 0.2, 0.2, 1.0);
const vec4 specular_color = vec4(1.0, 1.0, 1.0, 1.0);
const float shininess = 40.0;

float sample1(vec3 texcoords) {
    return texture(u_data, texcoords.xyz).r;
}

vec4 apply_colormap(float val) {
    val = (val - u_clim[0]) / (u_clim[1] - u_clim[0]);
    return texture(u_cmdata, vec2(val, 0.5));
}

vec4 add_lighting(float val, vec3 loc, vec3 step, vec3 view_ray) {
    vec3 V = normalize(view_ray);
    vec3 N;
    float val1;
    float val2;
    val1 = sample1(loc + vec3(-step[0], 0.0, 0.0));
    val2 = sample1(loc + vec3(+step[0], 0.0, 0.0));
    N[0] = val1 - val2;
    val = max(max(val1, val2), val);
    val1 = sample1(loc + vec3(0.0, -step[1], 0.0));
    val2 = sample1(loc + vec3(0.0, +step[1], 0.0));
    N[1] = val1 - val2;
    val = max(max(val1, val2), val);
    val1 = sample1(loc + vec3(0.0, 0.0, -step[2]));
    val2 = sample1(loc + vec3(0.0, 0.0, +step[2]));
    N[2] = val1 - val2;
    val = max(max(val1, val2), val);
    float gm = length(N);
    N = normalize(N);
    float Nselect = dot(N, V) > 0.0 ? 1.0 : 0.0;
    N = (2.0 * Nselect - 1.0) * N;
    vec4 ambient = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 diffuse = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 specular = vec4(0.0, 0.0, 0.0, 0.0);
    vec3 L = normalize(view_ray);
    float lightEnabled = length(L) > 0.0 ? 1.0 : 0.0;
    L = normalize(L + (1.0 - lightEnabled));
    float lambertTerm = clamp(dot(N, L), 0.0, 1.0);
    vec3 H = normalize(L + V);
    float specularTerm = pow(max(dot(H, N), 0.0), shininess);
    float mask1 = lightEnabled;
    ambient += mask1 * ambient_color;
    diffuse += mask1 * lambertTerm;
    specular += mask1 * specularTerm * specular_color;
    vec4 color = apply_colormap(val);
    vec4 final_color = color * (ambient + diffuse) + specular;
    final_color.a = color.a;
    return final_color;
}

vec4 cast_mip(vec3 start_loc, vec3 step, int nsteps) {
    float max_val = -1e6;
    int max_i = 100;
    vec3 loc = start_loc;
    for (int iter = 0; iter < VOLUME_STEPS; iter++) {
        if (iter >= nsteps) break;
        float val = sample1(loc);
        if (val > max_val) {
            max_val = val;
            max_i = iter;
        }
        loc += step;
    }
    vec3 iloc = start_loc + step * (float(max_i) - 0.5);
    vec3 istep = step / float(REFINEMENT_STEPS);
    for (int i = 0; i < REFINEMENT_STEPS; i++) {
        max_val = max(max_val, sample1(iloc));
        iloc += istep;
    }
    return apply_colormap(max_val);
}

vec4 cast_iso(vec3 start_loc, vec3 step, int nsteps, vec3 view_ray) {
    float low_threshold = u_renderthreshold - 0.02 * (u_clim[1] - u_clim[0]);
    int hit = -1;
    vec3 loc = start_loc;
    for (int iter = 0; iter < VOLUME_STEPS; iter++) {
        if (iter >= nsteps) break;
        if (sample1(loc) > low_threshold) {
            hit = iter;
            break;
        }
        loc += step;
    }
    if (hit < 0) return vec4(0.0);
    vec3 iloc = loc - 0.5 * step;
    vec3 istep = step / float(REFINEMENT_STEPS);
    vec4 color = vec4(0.0);
    bool found = false;
    for (int i = 0; i < REFINEMENT_STEPS; i++) {
        float val = sample1(iloc);
        if (!found && val > u_renderthreshold) {
            color = add_lighting(val, iloc, step, view_ray);
            found = true;
        }
        iloc += istep;
    }
    return color;
}

void main() {
    vec3 position = (u_world_to_local * vec4(v_world, 1.0)).xyz;
    vec3 eye = (u_world_to_local * vec4(cameraPosition, 1.0)).xyz;
    vec3 view_ray = normalize(position - eye);
    float distance = -length(position - eye);
    distance = max(distance, min((-0.5 - position.x) / view_ray.x,
                                 (u_size.x - 0.5 - position.x) / view_ray.x));
    distance = max(distance, min((-0.5 - position.y) / view_ray.y,
                                 (u_size.y - 0.5 - position.y) / view_ray.y));
    distance = max(distance, min((-0.5 - position.z) / view_ray.z,
                                 (u_size.z - 0.5 - position.z) / view_ray.z));
    vec3 front = position + view_ray * distance;
    int nsteps = int(-distance / relative_step_size + 0.5);
    if (nsteps < 1) discard;
    vec3 step = ((position - front) / u_size) / float(nsteps);
    vec3 start_loc = front / u_size;
    vec4 color = u_renderstyle == 0
        ? cast_mip(start_loc, step, nsteps)
        : cast_iso(start_loc, step, nsteps, view_ray);
    if (color.a < 0.05) discard;
    gl_FragColor = color;
}
"""


def volume_render_shader() raises -> NodeProgram:
    """Return three.js's `VolumeRenderShader1` as a node program, with its
    uniforms at three.js's defaults: an MIP render, a threshold of 0.5, an
    intensity range of zero to one, and `u_world_to_local` the identity.
    Set `u_data`, `u_cmdata` and `u_size` before it draws.

    Returns:
        The program, for a `BACK_SIDE` `shader_material` on a box that spans
        the volume.

    Raises:
        Error: Never: the source is inside the subset.
    """
    var program = compile_shader_material(
        VOLUME_RENDER_VERTEX,
        VOLUME_RENDER_FRAGMENT,
        ["VOLUME_STEPS " + String(VOLUME_STEPS)],
    )
    program.set_uniform("u_renderthreshold", Float32(0.5))
    program.set_uniform("u_clim", Vector2(0, 1))
    program.set_uniform("u_world_to_local", Matrix4())
    return program^
