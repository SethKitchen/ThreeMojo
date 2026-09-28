# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sphere at each probe of a grid, from three.js
`examples/jsm/helpers/LightProbeGridHelper.js`.

Each sphere shows what one probe of a `LightProbeGrid` holds: each
point of it is the irradiance of the probe's nine coefficients at the
point's world normal, held at zero or above, three.js's
`getShIrradianceAt( normalWorld, sh ).max( vec3( 0.0 ) )`. It is not
divided by pi, and the grid's intensity is not applied, as three.js's
helper applies neither. The shader is GLSL compiled to a node program,
so both rasterizers draw it.

**What is built.** three.js draws one `InstancedMesh` of spheres
`sphereSize` in radius, sixteen segments each way, and reads each
probe's coefficients from the grid's texture at the instance's texel.
Here there is one sphere geometry for every probe, and one program and
one material for each probe, as each holds its own coefficients.
`LightProbeGridHelper.__init__` adds a node at each probe under
`parent`, and a mesh on each node. `update` writes the coefficients
again after the grid is baked again.
"""

from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from helpers.light_probe import PROBE_VERTEX_SHADER
from lights.light_probe_grid import LightProbeGrid
from materials.glsl import compile_shader_material
from materials.material import MaterialId, shader_material
from materials.nodes import NodeProgramId
from objects.mesh import Mesh
from units.si import Length, METER

# three.js's default `sphereSize`: 0.12 meters.
comptime DEFAULT_GRID_HELPER_SIZE = Length(0.12, METER)
# three.js's `SphereGeometry( sphereSize, 16, 16 )`.
comptime GRID_HELPER_SEGMENTS = 16

# three.js's fragment node, in GLSL: the irradiance at the world normal,
# held at zero or above. The nine coefficients are nine uniforms.
comptime GRID_HELPER_FRAGMENT_SHADER = """
uniform vec3 sh0;
uniform vec3 sh1;
uniform vec3 sh2;
uniform vec3 sh3;
uniform vec3 sh4;
uniform vec3 sh5;
uniform vec3 sh6;
uniform vec3 sh7;
uniform vec3 sh8;

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

    gl_FragColor = vec4( max( shGetIrradianceAt( worldNormal ), vec3( 0.0 ) ), 1.0 );

}
"""


struct LightProbeGridHelper(Movable):
    """A sphere at each probe of a grid, three.js's
    `LightProbeGridHelper`."""

    var geometry: GeometryId
    # One program and one material for each probe, in the grid's order.
    var programs: List[NodeProgramId]
    var materials: List[MaterialId]
    # The node each sphere stands on, in the grid's order.
    var nodes: List[NodeId]

    def __init__(
        out self,
        grid: LightProbeGrid,
        mut scene: Scene,
        mut assets: Assets,
        sphere_size: Length = DEFAULT_GRID_HELPER_SIZE,
        parent: NodeId = NO_PARENT,
    ) raises:
        """Build a sphere for each probe and add it to a scene.

        Args:
            grid: The grid to show.
            scene: The scene to add the nodes and the meshes to.
            assets: Where the geometry, the materials and the programs
                are stored.
            sphere_size: Each sphere's radius, three.js's `sphereSize`. Must
                be positive.
            parent: The node the spheres hang from, or `NO_PARENT` for
                the scene itself. Put it where the grid's box is.

        Raises:
            Error: If the grid is refused by `LightProbeGrid.validate`, or
                `sphere_size` is not positive.
        """
        grid.validate()
        if not sphere_size.to(METER) > 0:
            raise Error("A light probe grid helper needs a positive size")
        self.geometry = assets.geometries.add(
            sphere(sphere_size, GRID_HELPER_SEGMENTS, GRID_HELPER_SEGMENTS)
        )
        self.programs = List[NodeProgramId]()
        self.materials = List[MaterialId]()
        self.nodes = List[NodeId]()
        for index in range(grid.count()):  # pragma: no branch
            var program = assets.programs.add(
                compile_shader_material(
                    String(PROBE_VERTEX_SHADER),
                    String(GRID_HELPER_FRAGMENT_SHADER),
                )
            )
            var material = assets.materials.add(shader_material(program))
            var at = grid.position_of(index)
            var place = Object3D()
            place.set_position(at.x, at.y, at.z)
            var node = scene.add(place^)
            if parent != NO_PARENT:
                scene.add(node, parent=parent)
            scene.add_mesh(Mesh(self.geometry, material, node))
            self.programs.append(program)
            self.materials.append(material)
            self.nodes.append(node)
        self.update(grid, assets)

    def update(self, grid: LightProbeGrid, mut assets: Assets) raises:
        """Write each probe's coefficients into its sphere's program, as
        three.js's `update` points the helper at the grid's texture again.

        Args:
            grid: The grid the helper shows.
            assets: The store the programs are in.

        Raises:
            Error: If the grid is refused by `LightProbeGrid.validate`, it
                holds another number of probes than the helper has
                spheres, or a program is not in `assets`.
        """
        grid.validate()
        if grid.count() != len(self.programs):
            raise Error(
                "A light probe grid helper shows a grid of its own size"
            )
        for index in range(len(self.programs)):  # pragma: no branch
            ref program = assets.programs.get(self.programs[index])
            for term in range(9):  # pragma: no branch
                program.set_uniform(
                    "sh" + String(term), grid.probes[index].coefficient(term)
                )
