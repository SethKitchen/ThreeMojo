# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sphere that shows the light a probe holds, from three.js
`examples/jsm/helpers/LightProbeHelper.js`.

Each point of the sphere shows what a matte white surface facing that way
would catch from the probe alone: `1 / pi` times the irradiance of the
probe's nine coefficients in the point's world normal, times the probe's
intensity. No other light reaches it.

**The shader is three.js's.** three.js draws the helper with a
`ShaderMaterial`. Here the same GLSL is compiled by
`materials.glsl.compile_shader_material` to a node program, which both
rasterizers run per fragment. Two spellings change and nothing else. The
subset has no arrays, so the uniform `sh[9]` is nine uniforms `sh0` to
`sh8`. It has no `mat4` parameter, so `inverseTransformDirection` is
written out where it is called. three.js ends with `linearToOutputTexel`.
Here a fragment's color is linear light, and the frame is encoded once when
it is resolved; see `renderers.renderer`.

**Where it stands.** three.js copies the probe's `position` onto the
helper and scales it by `size` before every frame. A probe here has no
node, so the helper is a mesh the caller puts on a node where the probe
is. The sphere is built with a radius of `size`, which is three.js's unit
sphere scaled by it. A sphere's normal at a point is the direction of that
point from its center, whichever way its node is turned, so the node's
rotation does not change what the helper shows.

**What is kept up to date.** three.js reads the probe's coefficients by
reference, and its intensity before every frame. Here `update` writes both
into the program again; call it after the probe changes.
"""

from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId
from geometries.sphere import sphere
from lights.light import LIGHT_PROBE, Light
from materials.glsl import compile_shader_material
from materials.material import MaterialId, shader_material
from materials.nodes import NodeProgramId
from objects.mesh import Mesh
from units.si import Length, METER

# three.js's default size: a sphere of one unit.
comptime DEFAULT_PROBE_HELPER_SIZE = Length(1.0, METER)
# three.js's `SphereGeometry( 1, 32, 16 )`.
comptime PROBE_HELPER_WIDTH_SEGMENTS = 32
comptime PROBE_HELPER_HEIGHT_SEGMENTS = 16

# three.js's vertex shader, as it is.
comptime PROBE_VERTEX_SHADER = """
varying vec3 vNormal;

void main() {

    vNormal = normalize( normalMatrix * normal );

    gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );

}
"""

# three.js's fragment shader, with `sh[ 9 ]` as nine uniforms and
# `inverseTransformDirection` written out where it is called.
comptime PROBE_FRAGMENT_SHADER = """
#define RECIPROCAL_PI 0.318309886

uniform vec3 sh0;
uniform vec3 sh1;
uniform vec3 sh2;
uniform vec3 sh3;
uniform vec3 sh4;
uniform vec3 sh5;
uniform vec3 sh6;
uniform vec3 sh7;
uniform vec3 sh8;

uniform float intensity;

varying vec3 vNormal;

vec3 shGetIrradianceAt( in vec3 normal ) {

    float x = normal.x, y = normal.y, z = normal.z;

    vec3 result = sh0 * 0.886227;

    result += sh1 * 2.0 * 0.511664 * y;
    result += sh2 * 2.0 * 0.511664 * z;
    result += sh3 * 2.0 * 0.511664 * x;

    result += sh4 * 2.0 * 0.429043 * x * y;
    result += sh5 * 2.0 * 0.429043 * y * z;
    result += sh6 * ( 0.743125 * z * z - 0.247708 );
    result += sh7 * 2.0 * 0.429043 * x * z;
    result += sh8 * 0.429043 * ( x * x - y * y );
    return result;

}

void main() {

    vec3 normal = normalize( vNormal );

    vec3 worldNormal = normalize( ( vec4( normal, 0.0 ) * viewMatrix ).xyz );

    vec3 irradiance = shGetIrradianceAt( worldNormal );

    vec3 outgoingLight = RECIPROCAL_PI * irradiance * intensity;

    gl_FragColor = vec4( outgoingLight, 1.0 );

}
"""


def _check_probe(light: Light) raises:
    """Refuse a light that is not a light probe, or that its kind refuses."""
    if not light.kind.is_valid() or light.kind != LIGHT_PROBE:
        raise Error("A light probe helper needs a light probe")
    light.validate()


struct LightProbeHelper(ImplicitlyCopyable):
    """A light probe's sphere: its geometry, its material and the program
    the material runs, all in one `Assets`. three.js: `LightProbeHelper`.
    """

    var geometry: GeometryId
    var material: MaterialId
    # The compiled shader, whose uniforms `update` writes.
    var program: NodeProgramId

    def __init__(
        out self,
        light: Light,
        mut assets: Assets,
        size: Length = DEFAULT_PROBE_HELPER_SIZE,
    ) raises:
        """Build the sphere for a light probe and store its parts.

        Args:
            light: A light probe.
            assets: Where the geometry, the material and the program are
                stored.
            size: The sphere's radius, three.js's `size`. Must be positive.

        Raises:
            Error: If the light is not a light probe or is refused by
                `Light.validate`, or `size` is not positive.
        """
        _check_probe(light)
        if size.to(METER) <= 0:
            raise Error("A light probe helper needs a positive size")
        self.geometry = assets.geometries.add(
            sphere(
                size, PROBE_HELPER_WIDTH_SEGMENTS, PROBE_HELPER_HEIGHT_SEGMENTS
            )
        )
        self.program = assets.programs.add(
            compile_shader_material(
                String(PROBE_VERTEX_SHADER), String(PROBE_FRAGMENT_SHADER)
            )
        )
        self.material = assets.materials.add(shader_material(self.program))
        self.update(light, assets)

    def update(self, light: Light, mut assets: Assets) raises:
        """Write the probe's coefficients and intensity into the program,
        as three.js's `onBeforeRender` does.

        Args:
            light: The light probe the helper shows.
            assets: The store the helper's program is in.

        Raises:
            Error: If the light is not a light probe or is refused by
                `Light.validate`, or the program is not in `assets`.
        """
        _check_probe(light)
        ref program = assets.programs.get(self.program)
        for index in range(9):  # pragma: no branch
            program.set_uniform(
                "sh" + String(index), light.sh.coefficient(index)
            )
        program.set_uniform("intensity", light.intensity)

    def mesh(self, node: NodeId) raises -> Mesh:
        """Return the mesh that draws the helper on a node.

        Args:
            node: A node where the probe is, three.js's `position`.

        Returns:
            The mesh, for `Scene.add_mesh`.

        Raises:
            Error: If `node` is negative.
        """
        return Mesh(self.geometry, self.material, node)
