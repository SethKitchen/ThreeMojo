# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sphere at each probe of a grid, from three.js
`examples/jsm/helpers/LightProbeGridHelper.js`.

Each sphere shows what one probe of a `LightProbeGrid` holds, as
`helpers.light_probe.LightProbeHelper` shows one light probe: each point
of it is `1 / pi` times the irradiance of the probe's nine coefficients
in the point's world normal, times the grid's intensity. The shader is
the same GLSL, compiled to a node program, so both rasterizers draw it.

**What is built.** One sphere geometry for every probe, and one program
and one material for each probe, as each holds its own coefficients.
`LightProbeGridHelper.__init__` adds a node at each probe under
`parent`, and a mesh on each node. `update` writes the coefficients
again after the grid is baked again.
"""

from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from helpers.light_probe import (
    PROBE_FRAGMENT_SHADER,
    PROBE_HELPER_HEIGHT_SEGMENTS,
    PROBE_HELPER_WIDTH_SEGMENTS,
    PROBE_VERTEX_SHADER,
)
from lights.light_probe_grid import LightProbeGrid
from materials.glsl import compile_shader_material
from materials.material import MaterialId, shader_material
from materials.nodes import NodeProgramId
from objects.mesh import Mesh
from units.si import Length, METER

# The radius of each sphere by default: a tenth of a meter, small beside
# the space between the probes of most grids.
comptime DEFAULT_GRID_HELPER_SIZE = Length(0.1, METER)


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
        size: Length = DEFAULT_GRID_HELPER_SIZE,
        parent: NodeId = NO_PARENT,
    ) raises:
        """Build a sphere for each probe and add it to a scene.

        Args:
            grid: The grid to show.
            scene: The scene to add the nodes and the meshes to.
            assets: Where the geometry, the materials and the programs
                are stored.
            size: Each sphere's radius. Must be positive.
            parent: The node the spheres hang from, or `NO_PARENT` for
                the scene itself. Put it where the grid's box is.

        Raises:
            Error: If the grid is refused by `LightProbeGrid.validate`, or
                `size` is not positive.
        """
        grid.validate()
        if not size.to(METER) > 0:
            raise Error("A light probe grid helper needs a positive size")
        self.geometry = assets.geometries.add(
            sphere(
                size, PROBE_HELPER_WIDTH_SEGMENTS, PROBE_HELPER_HEIGHT_SEGMENTS
            )
        )
        self.programs = List[NodeProgramId]()
        self.materials = List[MaterialId]()
        self.nodes = List[NodeId]()
        for index in range(grid.count()):  # pragma: no branch
            var program = assets.programs.add(
                compile_shader_material(
                    String(PROBE_VERTEX_SHADER), String(PROBE_FRAGMENT_SHADER)
                )
            )
            var material = assets.materials.add(shader_material(program))
            var at = grid.position(index)
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
        """Write each probe's coefficients and the grid's intensity into
        its sphere's program.

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
            program.set_uniform("intensity", grid.intensity)
