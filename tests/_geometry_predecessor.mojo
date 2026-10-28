# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Restore the reviewed geometry predecessor from the live file."""

from std.pathlib import Path

from tools._sha256 import sha256_hex


comptime _GEOMETRY = "extensions/carla/geometry.mojo"
"""The live geometry file."""
comptime _LIVE_SHA256 = (
    "94c59e3951b4137461c3f0f2d4c897e81b7a4dcb21d793feb0e4c8f8fa34cf4a"
)
"""The file digest of the live geometry module."""
comptime _RESTORED_SHA256 = (
    "eb55cc639bb840e2cef06cdb6ad5b76a5b2af880c74813590585ec180092a45c"
)
"""The file digest after the reviewed line edits are removed."""


def _split(text: String) -> List[String]:
    """Split `text` into lines that keep their newlines.

    Args:
        text: The source.

    Returns:
        Each line, including an unfinished last line.
    """
    var lines = List[String]()
    if text.byte_length() == 0:
        return lines^
    var rest = text
    while True:
        var at = rest.find("\n")
        if at < 0:
            lines.append(rest)
            return lines^
        var line = String(rest[byte = : at + 1])
        var tail = String(rest[byte = at + 1 :])
        lines.append(line)
        rest = tail


def _join(lines: List[String]) -> String:
    """Join lines that already carry their separators.

    Args:
        lines: The lines.

    Returns:
        The source.
    """
    var text = String()
    for line in lines:
        text += line
    return text


def _load_edits(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill the reviewed geometry line edits, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1351)
    stops.append(1810)
    befores.append("")
    starts.append(1349)
    stops.append(1350)
    befores.append("")
    starts.append(1336)
    stops.append(1344)
    befores.append(
        "        var total = last.s + sqrt(du * du + dv * dv)\n      "
        "  last = _Sample(pu, pv, total, u.tangent(p), v.tangent(p))"
        "\n"
    )
    starts.append(1328)
    stops.append(1334)
    befores.append(
        "        p += delta_p\n        var pu = u.evaluate(p)\n      "
        "  var pv = v.evaluate(p)\n"
    )
    starts.append(1320)
    stops.append(1325)
    befores.append(
        "        u.evaluate(0.0), v.evaluate(0.0), 0.0, u.tangent(0.0"
        "), v.tangent(0.0)\n"
    )
    starts.append(1309)
    stops.append(1315)
    befores.append("    var intervals = max(Int(base.length / 0.5), 5)\n")
    starts.append(1306)
    stops.append(1308)
    befores.append("    base.u_poly = u\n    base.v_poly = v\n")
    starts.append(1294)
    stops.append(1305)
    befores.append("")
    starts.append(1289)
    stops.append(1292)
    befores.append("")
    starts.append(1281)
    stops.append(1282)
    befores.append("")
    starts.append(1272)
    stops.append(1273)
    befores.append("")
    starts.append(1267)
    stops.append(1268)
    befores.append("def with_param_poly3(\n")
    starts.append(1258)
    stops.append(1264)
    befores.append(
        "    return with_param_poly3(\n        RoadGeometry(PARAM_POL"
        "Y3, s, x, y, heading, length), u, v, p_range\n"
    )
    starts.append(1249)
    stops.append(1250)
    befores.append("")
    starts.append(1233)
    stops.append(1234)
    befores.append("")
    starts.append(1224)
    stops.append(1225)
    befores.append("def param_poly3(\n")
    starts.append(1220)
    stops.append(1221)
    befores.append("")
    starts.append(1212)
    stops.append(1219)
    befores.append(
        "        total += sqrt(du * du + dv * dv)\n        last = _Sa"
        "mple(u, v, total, 1.0, base.u_poly.tangent(u))\n"
    )
    starts.append(1201)
    stops.append(1210)
    befores.append(
        "    while total < base.length + delta_u:\n        u += delta"
        "_u\n        var v = base.u_poly.evaluate(u)\n"
    )
    starts.append(1194)
    stops.append(1199)
    befores.append(
        "        0.0, base.u_poly.evaluate(0.0), 0.0, 1.0, base.u_pol"
        "y.tangent(0.0)\n"
    )
    starts.append(1188)
    stops.append(1189)
    befores.append("    base.u_poly = CubicPolynomial(a, b, c, d, 0.0)\n")
    starts.append(1179)
    stops.append(1187)
    befores.append("")
    starts.append(1173)
    stops.append(1178)
    befores.append("")
    starts.append(1169)
    stops.append(1170)
    befores.append("")
    starts.append(1153)
    stops.append(1161)
    befores.append(
        "def with_poly3(\n    var base: RoadGeometry, a: Float64, b: "
        "Float64, c: Float64, d: Float64\n) -> RoadGeometry:\n"
    )
    starts.append(1143)
    stops.append(1151)
    befores.append(
        "    return with_poly3(RoadGeometry(POLY3, s, x, y, heading, "
        "length), a, b, c, d)\n"
    )
    starts.append(1135)
    stops.append(1136)
    befores.append("")
    starts.append(1119)
    stops.append(1120)
    befores.append("")
    starts.append(1109)
    stops.append(1110)
    befores.append("def poly3(\n")
    starts.append(1099)
    stops.append(1103)
    befores.append("")
    starts.append(1094)
    stops.append(1098)
    befores.append("")
    starts.append(1084)
    stops.append(1085)
    befores.append(") -> RoadGeometry:\n")
    starts.append(1082)
    stops.append(1083)
    befores.append("def with_spiral(\n")
    starts.append(1075)
    stops.append(1077)
    befores.append(
        "    return with_spiral(\n        RoadGeometry(SPIRAL, s, x, "
        "y, heading, length),\n"
    )
    starts.append(1038)
    stops.append(1041)
    befores.append("")
    starts.append(1023)
    stops.append(1026)
    befores.append(
        "def with_arc(var base: RoadGeometry, curvature: Float64) rai"
        "ses -> RoadGeometry:\n"
    )
    starts.append(1017)
    stops.append(1020)
    befores.append(
        "    return with_arc(\n        RoadGeometry(ARC, s, x, y, hea"
        "ding, length), Float64(curvature.value)\n"
    )
    starts.append(989)
    stops.append(990)
    befores.append("    return RoadGeometry(LINE, s, x, y, heading, length)\n")
    starts.append(875)
    stops.append(952)
    befores.append("")
    starts.append(869)
    stops.append(870)
    befores.append("        return DirectedPoint(\n")
    starts.append(782)
    stops.append(787)
    befores.append("")
    starts.append(746)
    stops.append(747)
    befores.append("        return DirectedPoint(\n")
    starts.append(727)
    stops.append(728)
    befores.append("        return DirectedPoint(x, y, 0.0, tangent)\n")
    starts.append(701)
    stops.append(702)
    befores.append("            var end = self.pos_at(self.length)\n")
    starts.append(646)
    stops.append(685)
    befores.append(
        "    def distance_to(self, point: Vector3) -> Tuple[Float32, "
        "Float32]:\n"
    )
    starts.append(634)
    stops.append(635)
    befores.append("            return DirectedPoint(\n")
    starts.append(554)
    stops.append(623)
    befores.append("    def pos_at(self, dist: Float64) -> DirectedPoint:\n")
    starts.append(553)
    stops.append(553)
    befores.append(
        '        """\n        return self.pos_at(Float64(dist.value))\n'
    )
    starts.append(549)
    stops.append(550)
    befores.append("")
    starts.append(533)
    stops.append(544)
    befores.append(
        "    def pos_from_dist(self, dist: Length) -> DirectedPoint:\n"
    )
    starts.append(532)
    stops.append(532)
    befores.append('        """\n        return self.s + self.length\n')
    starts.append(481)
    stops.append(528)
    befores.append("    def end_s(self) -> Float64:\n")
    starts.append(477)
    stops.append(479)
    befores.append(
        "        self.u_poly = CubicPolynomial.constant(0.0)\n       "
        " self.v_poly = CubicPolynomial.constant(0.0)\n"
    )
    starts.append(468)
    stops.append(469)
    befores.append("")
    starts.append(457)
    stops.append(462)
    befores.append("")
    starts.append(445)
    stops.append(446)
    befores.append("")
    starts.append(431)
    stops.append(432)
    befores.append("")
    starts.append(420)
    stops.append(421)
    befores.append("        self = RoadGeometry(\n")
    starts.append(412)
    stops.append(416)
    befores.append("")
    starts.append(401)
    stops.append(402)
    befores.append("    ) raises:\n")
    starts.append(333)
    stops.append(395)
    befores.append("")
    starts.append(326)
    stops.append(329)
    befores.append(
        "    # A poly3 uses `u_poly` as v(u). A paramPoly3 uses both."
        "\n    var u_poly: CubicPolynomial\n    var v_poly: CubicPoly"
        "nomial\n"
    )
    starts.append(256)
    stops.append(300)
    befores.append("")
    starts.append(238)
    stops.append(239)
    befores.append("        return Angle(Float32(self.tangent), RADIAN)\n")
    starts.append(234)
    stops.append(237)
    befores.append("")
    starts.append(220)
    stops.append(230)
    befores.append("    def heading(self) -> Angle:\n")
    starts.append(219)
    stops.append(219)
    befores.append(
        '        """\n        var t = Float64(offset.value)\n     '
        "   self.x += t * sin(self.tangent)\n        self.y -= t * co"
        "s(self.tangent)\n"
    )
    starts.append(214)
    stops.append(215)
    befores.append("    def apply_lateral_offset(mut self, offset: Length):\n")
    starts.append(207)
    stops.append(208)
    befores.append('            pitch: The elevation slope.\n        """\n')
    starts.append(202)
    stops.append(203)
    befores.append("")
    starts.append(116)
    stops.append(193)
    befores.append("")
    starts.append(54)
    stops.append(56)
    befores.append("")
    starts.append(51)
    stops.append(53)
    befores.append("")
    starts.append(36)
    stops.append(43)
    befores.append("")


def restored_geometry() raises -> String:
    """Return the reviewed geometry predecessor.

    Returns:
        The live file with the reviewed line edits removed.

    Raises:
        Error: The live file or the restored module changed.
    """
    var live = Path(_GEOMETRY).read_text()
    if sha256_hex(live.as_bytes()) != _LIVE_SHA256:
        raise Error("reviewed geometry predecessor changed")
    var lines = _split(live)
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _load_edits(starts, stops, befores)
    for index in range(len(starts)):
        var start = starts[index]
        var stop = stops[index]
        var before = _split(befores[index])
        var next = List[String]()
        for slot in range(start):
            next.append(lines[slot])
        for line in before:
            next.append(line)
        for slot in range(stop, len(lines)):
            next.append(lines[slot])
        lines = next^
    var restored = _join(lines)
    if sha256_hex(restored.as_bytes()) != _RESTORED_SHA256:
        raise Error("reviewed geometry predecessor changed")
    return restored
