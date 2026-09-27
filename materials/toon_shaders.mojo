# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's toon shaders, `examples/jsm/shaders/ToonShader.js`: four
`ShaderMaterial`s, compiled by the GLSL subset from their own source.

`ToonShader1` shades in two tones and rims the edge the camera sees past.
`ToonShader2` darkens by bands of light. `ToonShaderHatching` draws lines
where the light is low, and `ToonShaderDotted` draws dots. Each light is
one direction and one color, which the program's uniforms hold.

The source is three.js's, but for `#include <colorspace_fragment>`: the
renderer writes a program's color to its sRGB target itself. A uniform
set from a `Color` is decoded from sRGB, as three.js's color management
decodes it.
"""

from materials.glsl import compile_shader_material
from materials.nodes import NodeProgram
from math.vector3 import Vector3
from render.framebuffer import Color


# `ToonShader1`'s vertex shader.
comptime TOON_SHADER_1_VERTEX = """
varying vec3 vNormal;
varying vec3 vRefract;
void main() {
    vec4 worldPosition = modelMatrix * vec4( position, 1.0 );
    vec4 mvPosition = modelViewMatrix * vec4( position, 1.0 );
    vec3 worldNormal = normalize ( mat3( modelMatrix[0].xyz, modelMatrix[1].xyz, modelMatrix[2].xyz ) * normal );
    vNormal = normalize( normalMatrix * normal );
    vec3 I = worldPosition.xyz - cameraPosition;
    vRefract = refract( normalize( I ), worldNormal, 1.02 );
    gl_Position = projectionMatrix * mvPosition;
}
"""

# `ToonShader1`'s fragment shader.
comptime TOON_SHADER_1_FRAGMENT = """
uniform vec3 uBaseColor;
uniform vec3 uDirLightPos;
uniform vec3 uDirLightColor;
uniform vec3 uAmbientLightColor;
varying vec3 vNormal;
varying vec3 vRefract;
void main() {
    float directionalLightWeighting = max( dot( normalize( vNormal ), uDirLightPos ), 0.0);
    vec3 lightWeighting = uAmbientLightColor + uDirLightColor * directionalLightWeighting;
    float intensity = smoothstep( - 0.5, 1.0, pow( length(lightWeighting), 20.0 ) );
    intensity += length(lightWeighting) * 0.2;
    float cameraWeighting = dot( normalize( vNormal ), vRefract );
    intensity += pow( 1.0 - length( cameraWeighting ), 6.0 );
    intensity = intensity * 0.2 + 0.3;
    if ( intensity < 0.50 ) {
        gl_FragColor = vec4( 2.0 * intensity * uBaseColor, 1.0 );
    } else {
        gl_FragColor = vec4( 1.0 - 2.0 * ( 1.0 - intensity ) * ( 1.0 - uBaseColor ), 1.0 );
    }
}
"""

# The vertex shader `ToonShader2`, `ToonShaderHatching` and
# `ToonShaderDotted` share: the normal in view space.
comptime TOON_NORMAL_VERTEX = """
varying vec3 vNormal;
void main() {
    gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );
    vNormal = normalize( normalMatrix * normal );
}
"""

# `ToonShader2`'s fragment shader.
comptime TOON_SHADER_2_FRAGMENT = """
uniform vec3 uBaseColor;
uniform vec3 uLineColor1;
uniform vec3 uLineColor2;
uniform vec3 uLineColor3;
uniform vec3 uLineColor4;
uniform vec3 uDirLightPos;
uniform vec3 uDirLightColor;
uniform vec3 uAmbientLightColor;
varying vec3 vNormal;
void main() {
    float camera = max( dot( normalize( vNormal ), vec3( 0.0, 0.0, 1.0 ) ), 0.4);
    float light = max( dot( normalize( vNormal ), uDirLightPos ), 0.0);
    gl_FragColor = vec4( uBaseColor, 1.0 );
    if ( length(uAmbientLightColor + uDirLightColor * light) < 1.00 ) {
        gl_FragColor *= vec4( uLineColor1, 1.0 );
    }
    if ( length(uAmbientLightColor + uDirLightColor * camera) < 0.50 ) {
        gl_FragColor *= vec4( uLineColor2, 1.0 );
    }
}
"""

# `ToonShaderHatching`'s fragment shader.
comptime TOON_SHADER_HATCHING_FRAGMENT = """
uniform vec3 uBaseColor;
uniform vec3 uLineColor1;
uniform vec3 uLineColor2;
uniform vec3 uLineColor3;
uniform vec3 uLineColor4;
uniform vec3 uDirLightPos;
uniform vec3 uDirLightColor;
uniform vec3 uAmbientLightColor;
varying vec3 vNormal;
void main() {
    float directionalLightWeighting = max( dot( normalize(vNormal), uDirLightPos ), 0.0);
    vec3 lightWeighting = uAmbientLightColor + uDirLightColor * directionalLightWeighting;
    gl_FragColor = vec4( uBaseColor, 1.0 );
    if ( length(lightWeighting) < 1.00 ) {
        if ( mod(gl_FragCoord.x + gl_FragCoord.y, 10.0) == 0.0) {
            gl_FragColor = vec4( uLineColor1, 1.0 );
        }
    }
    if ( length(lightWeighting) < 0.75 ) {
        if (mod(gl_FragCoord.x - gl_FragCoord.y, 10.0) == 0.0) {
            gl_FragColor = vec4( uLineColor2, 1.0 );
        }
    }
    if ( length(lightWeighting) < 0.50 ) {
        if (mod(gl_FragCoord.x + gl_FragCoord.y - 5.0, 10.0) == 0.0) {
            gl_FragColor = vec4( uLineColor3, 1.0 );
        }
    }
    if ( length(lightWeighting) < 0.3465 ) {
        if (mod(gl_FragCoord.x - gl_FragCoord.y - 5.0, 10.0) == 0.0) {
            gl_FragColor = vec4( uLineColor4, 1.0 );
        }
    }
}
"""

# `ToonShaderDotted`'s fragment shader.
comptime TOON_SHADER_DOTTED_FRAGMENT = """
uniform vec3 uBaseColor;
uniform vec3 uLineColor1;
uniform vec3 uLineColor2;
uniform vec3 uLineColor3;
uniform vec3 uLineColor4;
uniform vec3 uDirLightPos;
uniform vec3 uDirLightColor;
uniform vec3 uAmbientLightColor;
varying vec3 vNormal;
void main() {
    float directionalLightWeighting = max( dot( normalize(vNormal), uDirLightPos ), 0.0);
    vec3 lightWeighting = uAmbientLightColor + uDirLightColor * directionalLightWeighting;
    gl_FragColor = vec4( uBaseColor, 1.0 );
    if ( length(lightWeighting) < 1.00 ) {
        if ( ( mod(gl_FragCoord.x, 4.001) + mod(gl_FragCoord.y, 4.0) ) > 6.00 ) {
            gl_FragColor = vec4( uLineColor1, 1.0 );
        }
    }
    if ( length(lightWeighting) < 0.50 ) {
        if ( ( mod(gl_FragCoord.x + 2.0, 4.001) + mod(gl_FragCoord.y + 2.0, 4.0) ) > 6.00 ) {
            gl_FragColor = vec4( uLineColor1, 1.0 );
        }
    }
}
"""


def _lit(mut program: NodeProgram, base: Color) raises:
    """Set the uniforms every toon shader has to three.js's defaults: a
    light along no direction yet, light gray, a near-black ambient, and a
    base color."""
    program.set_uniform("uDirLightPos", Vector3(0, 0, 0))
    program.set_uniform("uDirLightColor", Color(0xEE, 0xEE, 0xEE))
    program.set_uniform("uAmbientLightColor", Color(0x05, 0x05, 0x05))
    program.set_uniform("uBaseColor", base)


def toon_shader_1() raises -> NodeProgram:
    """Return `ToonShader1`'s program, with three.js's default uniforms: a
    white base, a light gray light and a near-black ambient. Set
    `uDirLightPos` to the light's direction in view space.

    Returns:
        The program; give its id to `shader_material`.

    Raises:
        Error: Never: the source is in the subset.
    """
    var program = compile_shader_material(
        TOON_SHADER_1_VERTEX, TOON_SHADER_1_FRAGMENT
    )
    _lit(program, Color(0xFF, 0xFF, 0xFF))
    return program^


def toon_shader_2() raises -> NodeProgram:
    """Return `ToonShader2`'s program, with three.js's default uniforms: a
    light gray base, a gray first line color and black ones after it.

    Returns:
        The program; give its id to `shader_material`.

    Raises:
        Error: Never: the source is in the subset.
    """
    var program = compile_shader_material(
        TOON_NORMAL_VERTEX, TOON_SHADER_2_FRAGMENT
    )
    _lit(program, Color(0xEE, 0xEE, 0xEE))
    program.set_uniform("uLineColor1", Color(0x80, 0x80, 0x80))
    return program^


def toon_shader_hatching() raises -> NodeProgram:
    """Return `ToonShaderHatching`'s program, with three.js's default
    uniforms: a white base and black lines.

    Returns:
        The program; give its id to `shader_material`.

    Raises:
        Error: Never: the source is in the subset.
    """
    var program = compile_shader_material(
        TOON_NORMAL_VERTEX, TOON_SHADER_HATCHING_FRAGMENT
    )
    _lit(program, Color(0xFF, 0xFF, 0xFF))
    return program^


def toon_shader_dotted() raises -> NodeProgram:
    """Return `ToonShaderDotted`'s program, with three.js's default
    uniforms: a white base and black dots.

    Returns:
        The program; give its id to `shader_material`.

    Raises:
        Error: Never: the source is in the subset.
    """
    var program = compile_shader_material(
        TOON_NORMAL_VERTEX, TOON_SHADER_DOTTED_FRAGMENT
    )
    _lit(program, Color(0xFF, 0xFF, 0xFF))
    return program^
