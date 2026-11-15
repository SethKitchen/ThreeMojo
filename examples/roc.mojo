# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ROC curves of two markers, and DeLong's comparison of their AUC.

    mojo run -I . examples/roc.mojo [out/roc.png]

The page is Diagnostic tests. The data are 150 synthetic patients of
`assets/roc/markers.txt`, 60 of them diseased, with two markers each.

The blue curve is marker A and the red curve is marker B. The gray
diagonal is a test no better than chance. The program prints the AUC of
each marker with its 95 percent interval, DeLong's test of the
difference, and the threshold of marker A with the largest Youden index.
"""

from extensions.clinical.roc import RocCurve, compare_roc, roc_curve, roc_image
from extensions.imaging.transfer import Rgba
from render.png import encode
from std.pathlib import Path
from tools._example_output import example_destination

comptime DEFAULT_OUTPUT = "out/roc.png"


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var a = List[Float64]()
    var b = List[Float64]()
    var sick = List[Bool]()
    var text = open("assets/roc/markers.txt", "r").read()
    for line in text.splitlines():
        var words = String(line).split(" ")
        sick.append(String(words[0]) == "1")
        a.append(atof(String(words[1])))
        b.append(atof(String(words[2])))
    var curves = List[RocCurve]()
    curves.append(roc_curve(a, sick))
    curves.append(roc_curve(b, sick))
    var image = roc_image(
        curves, [Rgba(0.15, 0.4, 0.85, 1), Rgba(0.85, 0.2, 0.2, 1)], 480
    )
    Path(destination).write_bytes(encode(image))
    var names: List[String] = ["A", "B"]
    for c in range(2):
        var band = curves[c].interval()
        print(
            "Marker",
            names[c],
            ": AUC",
            curves[c].auc,
            "with a 95 percent interval of",
            band[0],
            "to",
            band[1],
        )
    var test = compare_roc(a, b, sick)
    print(
        "DeLong: B less A",
        test.difference,
        "z",
        test.z,
        "p",
        test.p_value,
    )
    var cut = curves[0].youden()
    print(
        "Marker A at",
        cut[0],
        "or more: sensitivity",
        cut[1],
        "specificity",
        cut[2],
    )
    print("Wrote", destination)
