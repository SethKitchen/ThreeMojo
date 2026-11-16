# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A predicted model colored by its pLDDT confidence.

    mojo run -I . examples/predicted.mojo [out/predicted.png]

The page is Molecular structures. A predicted structure holds the pLDDT
of each residue in its B-factor column. This model is synthetic: the
peptide builder places 38 residues, a tail, a helix, a loop, a strand
and a tail, and each residue gets the pLDDT that a prediction often
gives such a part. The helix is very high, the strand confident, the
loop low, and the tails very low, as a disordered end often is.

The top panel is the ribbon, and the bottom panel the excluded surface,
both colored in the four bands of the AlphaFold Protein Structure
Database: dark blue, light blue, yellow and orange. The program prints
the mean pLDDT and the residues in each band.

This is a picture of a synthetic model, for teaching. A pLDDT is a
prediction's own confidence, not a measurement.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.coloring import color_surface
from extensions.molecule.confidence import confidence_summary
from extensions.molecule.ids import (
    BY_CONFIDENCE,
    COIL,
    COLOR_BY_CONFIDENCE,
    HELIX,
    ModelId,
    ResidueId,
    STRAND,
    SecondaryKind,
)
from extensions.molecule.peptide import build_peptide
from extensions.molecule.ribbon import ribbon_geometry
from extensions.molecule.structure import SQUARE_ANGSTROM
from extensions.molecule.surface import excluded_surface
from extensions.sdf.vector import V3, cross, dot, normalize, rotate_about, v3
from materials.material import Material, PHONG
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.math import acos, max, min, pi, tan
from std.pathlib import Path
from tools._example_output import (
    blit,
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
)
from units.si import Angle, Area64, DEGREE, Length, Length64, METER, RADIAN

comptime DEFAULT_OUTPUT = "out/predicted.png"
comptime WIDTH = 840
comptime HEIGHT = 260
# One angstrom of the molecule is this many meters of the scene.
comptime SCENE_PER_ANGSTROM = 0.1


# A tail, a helix, a loop, a strand and a tail.
comptime SEQUENCE = "MSDSGPEELLKKAEELLKKAEELGNGKTYKVEVTGSEK"


def _kinds() -> List[SecondaryKind]:
    """Return the kind of each residue."""
    var spec: List[Tuple[SecondaryKind, Int]] = [
        (COIL, 5),
        (HELIX, 18),
        (COIL, 3),
        (STRAND, 7),
        (COIL, 5),
    ]
    var out = List[SecondaryKind]()
    for part in spec:
        for _ in range(part[1]):
            out.append(part[0])
    return out^


def _plddt() -> List[Float64]:
    """Return the pLDDT of each residue, as a prediction often gives it."""
    return [
        # The tail: very low, then low.
        32,
        38,
        44,
        49,
        56,
        # The helix: very high.
        91,
        94,
        95,
        96,
        97,
        97,
        96,
        97,
        98,
        97,
        96,
        97,
        96,
        95,
        96,
        94,
        92,
        88,
        # The loop: low.
        66,
        58,
        64,
        # The strand: confident.
        78,
        84,
        87,
        88,
        86,
        82,
        75,
        # The tail: very low.
        52,
        41,
        33,
        27,
        21,
    ]


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var kinds = _kinds()
    var plddt = _plddt()
    var sequence = String(SEQUENCE)
    var peptide = build_peptide(sequence, kinds)
    # A predicted file gives every atom of a residue its pLDDT.
    for r in range(len(peptide.residues)):
        var first = peptide.residues[r].first_atom
        for a in range(first, first + peptide.residues[r].atom_count):
            peptide.atoms[a].b_factor = Area64(plddt[r], SQUARE_ANGSTROM)
    var ribbon = ribbon_geometry(peptide, ModelId(0), BY_CONFIDENCE, 8, 16)
    var surface = excluded_surface(
        peptide, ModelId(0), Length64(1.4, ANGSTROM), Length64(0.35, ANGSTROM)
    )
    color_surface(surface, peptide, ModelId(0), COLOR_BY_CONFIDENCE)
    var summary = confidence_summary(peptide, ModelId(0))
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
        var r = rotate_about(atom.position - middle, axis, turn)
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
    print(summary.residues, "residues, mean pLDDT", summary.mean)
    print(
        "Very high:",
        summary.very_high,
        "confident:",
        summary.confident,
        "low:",
        summary.low,
        "very low:",
        summary.very_low,
    )
    print("Wrote", destination)
