# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A node of a DICOM tree must be a `DicomNode`, not a bare integer."""

from extensions.imaging.dicom import read_dicom_tree


def main() raises:
    var tree = read_dicom_tree("assets/dicom/rtstruct.dcm")
    _ = tree.text(0, 0x00100010)
