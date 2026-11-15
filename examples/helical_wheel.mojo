# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The helical wheels of two antimicrobial peptides, with their hydrophobic
moments.

    mojo run -I . examples/helical_wheel.mojo [out/helical-wheel.png]

The page is Molecular structures. The left wheel is magainin 2, a peptide
from the skin of the African clawed frog that kills bacteria. The right
wheel is a designed peptide of leucine and lysine, `(LKKLLKL)3`. Each
residue sits 100 degrees past the one before it, as in an alpha helix,
and the residues spiral out by one disc for each full turn.

Orange discs are hydrophobic and blue discs hydrophilic, on the scale of
Eisenberg. The arrow points along the hydrophobic moment, and its length
is the moment times the outer radius. Both peptides have a hydrophobic
face and a charged face, which lets them lie in a membrane. The designed
peptide has the larger moment.

This is a picture for teaching. It does not predict the activity of a
peptide.
"""

from extensions.molecule.amphipathic import (
    helical_wheel,
    hydrophobic_moment,
    sequence_hydrophobicity,
)
from extensions.village.hud import Rgb, TextStyle, draw_styled, styled_width
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.pathlib import Path
from tools._example_output import blit, example_destination
from units.si import Angle64, DEGREE64

comptime DEFAULT_OUTPUT = "out/helical-wheel.png"
comptime SIDE = 480


def _wheel(mut sheet: Framebuffer, sequence: String, left: Int) raises:
    """Draw the wheel of a sequence on a sheet, with each residue's letter."""
    var values = sequence_hydrophobicity(sequence)
    var turn = Angle64(100.0, DEGREE64)
    var wheel = helical_wheel(values, turn, SIDE)
    var size = Float32(wheel.radius * 0.95)
    var style = TextStyle(size, Rgb(30, 30, 34), 1.0, 0, 0, 0, 0)
    var at = 0
    for code in sequence.codepoint_slices():
        var letter = String(code)
        draw_styled(
            wheel.image,
            Float32(wheel.xs[at]) - styled_width(letter, size) / 2,
            Float32(wheel.ys[at]) - size / 2,
            letter,
            style,
        )
        at += 1
    var moment = hydrophobic_moment(values, turn)
    print(
        sequence,
        ": mean",
        moment.mean,
        "moment",
        moment.moment,
        "toward",
        moment.direction.to(DEGREE64),
        "degrees",
    )
    blit(sheet, wheel.image, left, 0)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var sheet = Framebuffer(2 * SIDE + 16, SIDE, Color(255, 255, 255))
    _wheel(sheet, "GIGKFLHSAKKFGKAFVGEIMNS", 0)
    _wheel(sheet, "LKKLLKLLKKLLKLLKKLLKL", SIDE + 16)
    Path(destination).write_bytes(encode(sheet))
    print("Wrote", destination)
