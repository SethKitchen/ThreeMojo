# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""A digest of every field of a lane certificate, for pinning solver output."""

from extensions.carla.lane_refinement import _LaneCertificate
from std.memory import bitcast
from tools._sha256 import sha256_hex


def _word(value: Float64) -> String:
    return hex(bitcast[DType.uint64](value))


def certificate_digest(certificate: _LaneCertificate) -> String:
    """Return the SHA-256 of every field of `certificate`, bit for bit.

    Args:
        certificate: The certificate.

    Returns:
        The digest as lowercase hex.
    """
    var text = String(
        _word(certificate.s),
        " ",
        _word(certificate.scale),
        " ",
        _word(certificate.lower),
        " ",
        _word(certificate.upper),
        " ",
        certificate.nodes,
        " ",
        certificate.terms,
        " ",
        certificate.exact_witness,
    )
    for axis in range(3):
        text += " " + _word(certificate.point[axis])
    for cell in certificate.cells:
        text += String(
            " ",
            _word(cell.low),
            ",",
            _word(cell.high),
            ",",
            _word(cell.lower),
            ",",
            _word(cell.scale),
            ",",
            cell.depth,
        )
    return sha256_hex(text.as_bytes())
