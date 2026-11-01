# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Diamond and graphite, read from CIF text, turning side by side.

    mojo run -I . examples/crystal.mojo [path.png]

The page is Process chemistry. Both crystals are pure carbon. `read_cif`
expands each from its symmetry operations: diamond from the face-centered
translations on a basis of two atoms, graphite from the 24 operations of
P6_3/mmc. `bonds` joins the atoms 1.3 to 1.6 angstroms apart. Diamond's
bonds go out in four directions, so it is hard. Graphite's lie in flat
sheets, 3.35 angstroms apart with no bond between them, so the sheets
slide and graphite is soft.
"""

from std.math import acos, sqrt
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.chemistry.crystal import Crystal, bonds, read_cif
from extensions.chemistry.quantities import ANGSTROM
from extensions.visual.overlay import CENTER, Overlay
from geometries.cylinder import cylinder
from geometries.sphere import sphere
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from tools._chemistry_figure import FONT, MUTED, TEXT
from tools._example_output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
    write_frames,
)
from units.si import Angle, DEGREE, Length, Length64, METER, RADIAN

comptime DEFAULT_OUTPUT = "out/crystal.png"
comptime WIDTH = 400
comptime HEIGHT = 260
comptime FRAMES = 36
comptime DELAY_MS = 70
# Meters of scene per angstrom.
comptime SCALE = 0.2

comptime DIAMOND = """data_diamond
_cell_length_a 3.5668
_cell_length_b 3.5668
_cell_length_c 3.5668
_cell_angle_alpha 90
_cell_angle_beta 90
_cell_angle_gamma 90
loop_
_symmetry_equiv_pos_as_xyz
x,y,z
x,y+1/2,z+1/2
x+1/2,y,z+1/2
x+1/2,y+1/2,z
loop_
_atom_site_label
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
C1 0 0 0
C2 0.25 0.25 0.25
"""

comptime GRAPHITE = """data_graphite
_cell_length_a 2.464
_cell_length_b 2.464
_cell_length_c 6.711
_cell_angle_alpha 90
_cell_angle_beta 90
_cell_angle_gamma 120
loop_
_space_group_symop_operation_xyz
x,y,z
-y,x-y,z
-x+y,-x,z
-x,-y,z+1/2
y,-x+y,z+1/2
x-y,x,z+1/2
y,x,-z
x-y,-y,-z
-x,-x+y,-z
-y,-x,-z+1/2
-x+y,y,-z+1/2
x,x-y,-z+1/2
-x,-y,-z
y,-x+y,-z
x-y,x,-z
x,y,-z+1/2
-y,x-y,-z+1/2
-x+y,-x,-z+1/2
-y,-x,z
-x+y,y,z
x,x-y,z
y,x,z+1/2
x-y,-y,z+1/2
-x,-x+y,z+1/2
loop_
_atom_site_label
_atom_site_fract_x
_atom_site_fract_y
_atom_site_fract_z
C1 0 0 0.25
C2 0.333333 0.666667 0.25
"""


def _point(x: Length64, y: Length64, z: Length64) -> Vector3:
    """Return a crystal point in the scene, with the c axis up."""
    return Vector3(
        Float32(x.to(ANGSTROM) * SCALE),
        Float32(z.to(ANGSTROM) * SCALE),
        Float32(y.to(ANGSTROM) * SCALE),
    )


def _build(
    mut scene: Scene,
    mut assets: Assets,
    crystal: Crystal,
    cells: Int,
    layers: Int,
    x: Float32,
    atom_color: Color,
) raises -> NodeId:
    """Add a block of a crystal's atoms and bonds; return its pivot."""
    var atoms = crystal.block(cells, cells, layers)
    var links = bonds(atoms, Length64(1.3, ANGSTROM), Length64(1.6, ANGSTROM))
    var ball = assets.geometries.add(sphere(Length(0.075, METER), 16, 12))
    var rod = assets.geometries.add(
        cylinder(
            Length(0.022, METER), Length(0.022, METER), Length(1, METER), 8
        )
    )
    var atom_material = assets.materials.add(Material(atom_color))
    var bond_material = assets.materials.add(Material(Color(200, 200, 205)))
    var pivot_object = Object3D()
    pivot_object.set_position(x, 0, 0)
    var pivot = scene.add(pivot_object^)
    # The block's center goes on the pivot.
    var center = Vector3(0, 0, 0)
    var points = List[Vector3]()
    for atom in atoms:
        var p = _point(atom.x, atom.y, atom.z)
        center = center + p
        points.append(p)
    var count = Float32(len(points))
    center = Vector3(center.x / count, center.y / count, center.z / count)
    for p in points:
        var node = Object3D()
        node.set_position(p.x - center.x, p.y - center.y, p.z - center.z)
        scene.add_mesh(Mesh(ball, atom_material, scene.attach(node^, pivot)))
    for link in links:
        var a = points[link.first]
        var b = points[link.second]
        var d = b - a
        var length = d.length()
        var node = Object3D()
        node.set_position(
            (a.x + b.x) / 2 - center.x,
            (a.y + b.y) / 2 - center.y,
            (a.z + b.z) / 2 - center.z,
        )
        node.set_scale(1, length, 1)
        # Turn the rod from the y axis onto the bond.
        var axis = Vector3(d.z, 0, -d.x)
        var side = axis.length()
        if side > 1e-6:
            axis = Vector3(axis.x / side, 0, axis.z / side)
            var angle = acos(Float64(d.y / length))
            node.set_rotation_from_axis_angle(
                axis, Angle(Float32(angle), RADIAN)
            )
        scene.add_mesh(Mesh(rod, bond_material, scene.attach(node^, pivot)))
    return pivot


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))
    var assets = Assets()
    var scene = Scene()
    var diamond = read_cif(DIAMOND)
    var graphite = read_cif(GRAPHITE)
    var left = _build(scene, assets, diamond, 1, 1, -0.62, Color(150, 205, 240))
    var right = _build(
        scene, assets, graphite, 2, 1, 0.66, Color(120, 120, 128)
    )
    fill_and_key(
        scene,
        1.5,
        2.5,
        3.0,
        Color(255, 255, 255),
        0.5,
        Color(255, 250, 240),
        2.2,
    )
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0, 1.5, 3.2),
        Vector3(0, 0, 0),
        field_of_view=Angle(36.0, DEGREE),
    )
    var font = Overlay.from_ttf(FONT)
    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    var density_d = diamond.density().value / 1000
    var density_g = graphite.density().value / 1000
    for _ in range(FRAMES):
        scene.node(left).rotate_y(step)
        scene.node(right).rotate_y(step)
        scene.update()
        var frame = renderer.render(scene, assets, camera)
        font.text(frame, "Diamond", WIDTH * 0.27, 24, 13, TEXT, CENTER)
        font.text(frame, "Graphite", WIDTH * 0.75, 24, 13, TEXT, CENTER)
        font.text(
            frame,
            String(round(density_d * 100) / 100, " g/cm3"),
            WIDTH * 0.27,
            HEIGHT - 12,
            10,
            MUTED,
            CENTER,
        )
        font.text(
            frame,
            String(round(density_g * 100) / 100, " g/cm3"),
            WIDTH * 0.75,
            HEIGHT - 12,
            10,
            MUTED,
            CENTER,
        )
        frames.append(frame^)
    write_frames(frames, destination, DELAY_MS, FRAMES)
