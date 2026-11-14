# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An ideal peptide drawn as a cartoon ribbon and as its accessible surface.

    mojo run -I . examples/molecule.mojo [out/molecule.png]

The page is Molecular structures. The peptide builder places the backbone
of 30 residues: a helix, a loop and a strand. The top panel is the
ribbon, colored by secondary structure. The bottom panel is the van der
Waals surface, colored by element. The program prints the solvent accessible area for a water
probe of 1.4 angstroms. Ideal torsions do not fold a chain, so the
strands do not pair.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import (
    BY_STRUCTURE,
    COIL,
    HELIX,
    ModelId,
    ResidueId,
    STRAND,
    SecondaryKind,
)
from extensions.sdf.vector import V3, cross, distance, dot, normalize, v3
from std.math import acos, cos, max, min, pi, sin, tan
from extensions.molecule.peptide import build_peptide
from extensions.molecule.ribbon import ribbon_geometry
from extensions.molecule.surface import accessible_areas, molecular_surface
from materials.material import Material, PHONG
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.pathlib import Path
from tools._example_output import (
    blit,
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
)
from units.si import Angle, DEGREE, Length, Length64, METER, RADIAN

comptime DEFAULT_OUTPUT = "out/molecule.png"
comptime WIDTH = 840
comptime HEIGHT = 260
# One angstrom of the molecule is this many meters of the scene.
comptime SCENE_PER_ANGSTROM = 0.1


def _kinds() -> List[SecondaryKind]:
    """Return a helix, a loop and a strand."""
    var spec: List[Tuple[SecondaryKind, Int]] = [
        (COIL, 1),
        (HELIX, 18),
        (COIL, 3),
        (STRAND, 7),
        (COIL, 1),
    ]
    var out = List[SecondaryKind]()
    for part in spec:
        for _ in range(part[1]):
            out.append(part[0])
    return out^


def _turned(p: V3, axis: V3, angle: Float64) -> V3:
    """Return `p` turned about a unit axis by Rodrigues' formula."""
    var c = cos(angle)
    return p * c + cross(axis, p) * sin(angle) + axis * (dot(axis, p) * (1 - c))


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var sequence = "SPEELLKKAEELLKKAEEGNGKTYKVEVTG"
    var kinds = _kinds()
    var peptide = build_peptide(String(sequence[byte = 0 : len(kinds)]), kinds)
    var ribbon = ribbon_geometry(peptide, ModelId(0), BY_STRUCTURE, 8, 16)
    var probe = Length64(1.4, ANGSTROM)
    var surface = molecular_surface(
        peptide, ModelId(0), Length64(0.0, ANGSTROM), Length64(0.4, ANGSTROM)
    )
    var areas = accessible_areas(peptide, ModelId(0), probe, 300)
    var total = 0.0
    for area in areas:
        total += area.value
    var square_angstrom = Length64(1.0, ANGSTROM).value ** 2
    var bounds = peptide.bounds(ModelId(0))
    var middle = (bounds[0] + bounds[1]) * 0.5
    var scale = Float32(SCENE_PER_ANGSTROM / Length64(1.0, ANGSTROM).value)
    # Turn the line from the first CA to the last onto x, so the chain
    # lies across the panel.
    var first = peptide.atoms[
        peptide.find_atom(ResidueId(0), "CA").value
    ].position
    var last_residue = ResidueId(len(peptide.residues) - 1)
    var last = peptide.atoms[
        peptide.find_atom(last_residue, "CA").value
    ].position
    var run = normalize(last - first)
    var axis = normalize(cross(run, v3(1, 0, 0)))
    var turn = acos(dot(run, v3(1, 0, 0)))
    # Frame the turned atoms: the box around them, and their depth.
    var low = v3(1, 1, 1)
    var high = v3(-1, -1, -1)
    for atom in peptide.atoms:
        var r = _turned(atom.position - middle, axis, turn)
        low = v3(min(low.x, r.x), min(low.y, r.y), min(low.z, r.z))
        high = v3(max(high.x, r.x), max(high.y, r.y), max(high.z, r.z))
    var shift = (low + high) * 0.5
    var aspect = Float64(WIDTH) / Float64(HEIGHT)
    var vertical = tan(18.0 * pi / 180.0)
    var margin = 2.5 * Length64(1.0, ANGSTROM).value
    var fit = max(
        ((high.x - low.x) / 2 + margin) / (vertical * aspect),
        ((high.y - low.y) / 2 + margin) / vertical,
    )
    var eye_distance = Float32((fit + high.z - shift.z) * Float64(scale))
    var sheet = Framebuffer(
        WIDTH, 2 * HEIGHT, List[UInt8](length=2 * WIDTH * HEIGHT * 4, fill=0)
    )
    for side in range(2):
        var renderer = gallery_renderer(WIDTH, HEIGHT, Color(14, 16, 24))
        var assets = Assets()
        var scene = Scene()
        var mesh_id = assets.geometries.add(ribbon.clone())
        if side == 1:
            mesh_id = assets.geometries.add(surface.clone())
        var material = assets.materials.add(
            Material(
                Color(255, 255, 255),
                kind=PHONG,
                vertex_colors=True,
                specular=Color(60, 60, 60),
                shininess=30,
            )
        )
        var pivot = Object3D()
        pivot.set_rotation_from_axis_angle(
            Vector3(Float32(axis.x), Float32(axis.y), Float32(axis.z)),
            Angle(Float32(turn), RADIAN),
        )
        pivot.set_position(
            -Float32(shift.x) * scale, -Float32(shift.y) * scale, 0
        )
        var parent = scene.add(pivot^)
        var node = Object3D()
        node.set_scale(scale, scale, scale)
        node.set_position(
            -Float32(middle.x) * scale,
            -Float32(middle.y) * scale,
            -Float32(middle.z) * scale,
        )
        scene.add_mesh(Mesh(mesh_id, material, scene.attach(node^, parent)))
        fill_and_key(
            scene,
            2.0,
            3.0,
            4.0,
            Color(255, 255, 255),
            0.6,
            Color(255, 250, 240),
            2.4,
        )
        scene.update()
        var camera = gallery_camera(
            WIDTH,
            HEIGHT,
            Vector3(0, 0, eye_distance),
            Vector3(0, 0, 0),
            field_of_view=Angle(36.0, DEGREE),
            far=Length(4 * eye_distance, METER),
        )
        var frame = renderer.render(scene, assets, camera)
        blit(sheet, frame, 0, side * HEIGHT)
    Path(destination).write_bytes(encode(sheet))
    print(len(peptide.residues), "residues,", len(peptide.atoms), "atoms")
    print("Accessible area:", total / square_angstrom, "square angstroms")
    print("Wrote", destination)
