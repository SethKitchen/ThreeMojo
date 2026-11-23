# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""EPANET input files, read as pipe networks.

An EPANET `.inp` file is text in sections. A line `[NAME]` starts a
section, and a semicolon starts a comment. `parse_inp` reads the sections
that fix a steady flow: junctions, reservoirs, tanks, pipes, pumps,
curves, patterns and options. It gives a `PipeNetwork` and the name of
each node and link.

The flow unit of the `UNITS` option fixes every other unit. With a US
flow unit a length is in feet, a diameter is in inches and a
Darcy-Weisbach roughness is in thousandths of a foot. With an SI flow
unit they are in meters, millimeters and millimeters.

A section that can change a steady result and that this port cannot honor
raises an error when it holds a line: valves, initial status, controls,
rules, emitters and extra demands. The other sections, such as
coordinates and reports, are passed over.

The format is that of Rossman, "EPANET 2 Users Manual",
EPA/600/R-00/057, 2000, appendix C. EPANET is in the public domain, and
the code here is original.
"""

from std.collections import Dict
from std.pathlib import Path
from loaders.text_number import file_line
from math.finite import require_finite
from extensions.hydraulics.headloss import (
    Roughness,
    chezy_manning,
    darcy_weisbach,
    hazen_williams,
)
from extensions.hydraulics.kinds import (
    CHEZY_MANNING,
    DARCY_WEISBACH,
    HAZEN_WILLIAMS,
    HeadLossFormula,
    KinematicViscosity64,
    LinkId,
    NodeId,
)
from extensions.hydraulics.network import PipeNetwork, WATER_VISCOSITY
from extensions.hydraulics.solve import SolveOptions
from units.si import Length64, VolumeFlowRate64

# One foot and one inch, in meters.
comptime _FOOT = 0.3048
comptime _INCH = 0.0254


struct InpNetwork(Movable):
    """The network of an EPANET input file."""

    var network: PipeNetwork
    # The lines of the title section, joined by spaces.
    var title: String
    # The name of each node and of each link, in capitals.
    var node_names: List[String]
    var link_names: List[String]
    # The accuracy and the trials of the file, or 0.001 and 40.
    var options: SolveOptions
    var _nodes: Dict[String, Int]
    var _links: Dict[String, Int]

    def __init__(out self) raises:
        """Create an empty network. `parse_inp` fills it.

        Raises:
            Error: Never.
        """
        self.network = PipeNetwork()
        self.title = String("")
        self.node_names = List[String]()
        self.link_names = List[String]()
        self.options = SolveOptions(0.001, 40)
        self._nodes = Dict[String, Int]()
        self._links = Dict[String, Int]()

    def node(self, name: String) raises -> NodeId:
        """Return the node of a name.

        Args:
            name: The name in the file. Its case does not matter.

        Returns:
            The node.

        Raises:
            Error: If the file has no node of that name.
        """
        var index = self._nodes.get(name.upper(), -1)
        if index < 0:
            raise Error("The file has no node ", name)
        return NodeId(index)

    def link(self, name: String) raises -> LinkId:
        """Return the link of a name.

        Args:
            name: The name in the file. Its case does not matter.

        Returns:
            The link.

        Raises:
            Error: If the file has no link of that name.
        """
        var index = self._links.get(name.upper(), -1)
        if index < 0:
            raise Error("The file has no link ", name)
        return LinkId(index)


@fieldwise_init
struct _Line(Copyable, Movable):
    """The words of one data line, in capitals, and its line number."""

    var words: List[String]
    var number: Int


def _number(word: String, what: String, line: Int) raises -> Float64:
    """Return a word as a finite number."""
    var value: Float64
    try:
        value = atof(word)
    except:
        raise Error(file_line("inp", line), what, " is not a number")
    require_finite(value, file_line("inp", line) + what + " must be finite")
    return value


def flow_unit(name: String) raises -> Float64:
    """Return the cubic meters per second in one EPANET flow unit.

    Args:
        name: `CFS`, `GPM`, `MGD`, `IMGD`, `AFD`, `LPS`, `LPM`, `MLD`,
            `CMH` or `CMD`, in capitals.

    Returns:
        The factor.

    Raises:
        Error: If the name is not one of the ten units.
    """
    var names = [
        "CFS",
        "GPM",
        "MGD",
        "IMGD",
        "AFD",
        "LPS",
        "LPM",
        "MLD",
        "CMH",
        "CMD",
    ]
    # A cubic foot is 0.3048³ m³, a US gallon 3.785411784 L, an imperial
    # gallon 4.54609 L and an acre-foot 43560 ft³.
    var factors = [
        0.028316846592,
        3.785411784e-3 / 60,
        3.785411784e3 / 86400,
        4.54609e3 / 86400,
        43560 * 0.028316846592 / 86400,
        1e-3,
        1e-3 / 60,
        1e3 / 86400,
        1.0 / 3600,
        1.0 / 86400,
    ]
    for i in range(10):
        if name == names[i]:
            return factors[i]
    raise Error("The flow unit ", name, " is not an EPANET unit")


def parse_inp(text: String) raises -> InpNetwork:
    """Return the network in the text of an EPANET input file.

    Args:
        text: The whole file.

    Returns:
        The network, the names of its nodes and links, and the solver
        options of the file.

    Raises:
        Error: If a line is before the first section, a line is short or
            malformed, a name repeats or is not defined, a unit or a
            formula is not known, a pump has no head curve of one point,
            a pipe is closed or has a check valve, or a section that
            this port cannot honor holds a line. The message names the
            line where it can.
    """
    var sections = Dict[String, List[_Line]]()
    var current = String("")
    var title = String("")
    var lines = text.split("\n")
    for i in range(len(lines)):  # pragma: no branch
        # The text before the first semicolon is not a comment.
        var line = String(String(lines[i]).split(";")[0].strip())
        if line.byte_length() == 0:
            continue
        if line.startswith("["):
            current = line.upper()
            if current not in sections:
                sections[current] = List[_Line]()
            continue
        if current == "":
            raise Error(file_line("inp", i + 1), "a line is before a section")
        if current == "[TITLE]":
            if title.byte_length() > 0:
                title += " "
            title += line
            continue
        var parts = line.upper().split()
        var words = List[String](capacity=len(parts))
        for k in range(len(parts)):  # pragma: no branch
            words.append(String(parts[k]))
        sections[current].append(_Line(words^, i + 1))
    var unsupported = [
        "[VALVES]",
        "[STATUS]",
        "[CONTROLS]",
        "[RULES]",
        "[EMITTERS]",
        "[DEMANDS]",
    ]
    for k in range(6):
        if unsupported[k] in sections and len(sections[unsupported[k]]) > 0:
            raise Error(
                file_line("inp", sections[unsupported[k]][0].number),
                "the section ",
                unsupported[k],
                " is not supported",
            )
    var out = InpNetwork()
    out.title = title
    # The options: the units, the formula, the viscosity and the demand
    # multiplier.
    var flow = flow_unit("GPM")
    var metric = False
    var formula = HAZEN_WILLIAMS
    var multiplier = Float64(1)
    var default_pattern = String("1")
    var accuracy = Float64(0.001)
    var trials = 40
    var options = _section(sections, "[OPTIONS]")
    for k in range(len(options)):
        ref words = options[k].words
        var at = options[k].number
        if len(words) < 2:
            raise Error(file_line("inp", at), "an option needs a value")
        var last = words[len(words) - 1]
        if words[0] == "UNITS":
            flow = flow_unit(last)
            metric = (
                last == "LPS"
                or last == "LPM"
                or last == "MLD"
                or last == "CMH"
                or last == "CMD"
            )
        elif words[0] == "HEADLOSS":
            if last == "H-W":
                formula = HAZEN_WILLIAMS
            elif last == "D-W":
                formula = DARCY_WEISBACH
            elif last == "C-M":
                formula = CHEZY_MANNING
            else:
                raise Error(
                    file_line("inp", at),
                    "the head loss formula must be H-W, D-W or C-M",
                )
        elif words[0] == "VISCOSITY":
            var relative = _number(last, "A viscosity", at)
            out.network.set_viscosity(
                KinematicViscosity64(relative * WATER_VISCOSITY)
            )
        elif words[0] == "DEMAND":
            multiplier = _number(last, "A demand multiplier", at)
        elif words[0] == "PATTERN":
            default_pattern = last
        elif words[0] == "ACCURACY":
            accuracy = _number(last, "An accuracy", at)
        elif words[0] == "TRIALS":
            trials = Int(_number(last, "A trial count", at))
    out.options = SolveOptions(accuracy, trials)
    var length_unit = _FOOT
    var diameter_unit = _INCH
    var rough_unit = _FOOT / 1000
    if metric:
        length_unit = 1
        diameter_unit = 0.001
        rough_unit = 0.001
    # The first multiplier of each pattern.
    var patterns = Dict[String, Float64]()
    var pattern_lines = _section(sections, "[PATTERNS]")
    for k in range(len(pattern_lines)):
        ref words = pattern_lines[k].words
        if len(words) < 2:
            raise Error(
                file_line("inp", pattern_lines[k].number),
                "a pattern needs a name and a multiplier",
            )
        if words[0] not in patterns:
            patterns[words[0]] = _number(
                words[1], "A multiplier", pattern_lines[k].number
            )
    # The first point of each curve, and how many points it has.
    var curve_flow = Dict[String, Float64]()
    var curve_head = Dict[String, Float64]()
    var curve_points = Dict[String, Int]()
    var curve_lines = _section(sections, "[CURVES]")
    for k in range(len(curve_lines)):
        ref words = curve_lines[k].words
        var at = curve_lines[k].number
        if len(words) < 3:
            raise Error(
                file_line("inp", at), "a curve needs a name, an x and a y"
            )
        if words[0] not in curve_points:
            curve_points[words[0]] = 0
            curve_flow[words[0]] = _number(words[1], "A curve x", at)
            curve_head[words[0]] = _number(words[2], "A curve y", at)
        curve_points[words[0]] += 1
    var junctions = _section(sections, "[JUNCTIONS]")
    for k in range(len(junctions)):
        ref words = junctions[k].words
        var at = junctions[k].number
        if len(words) < 2:
            raise Error(
                file_line("inp", at), "a junction needs a name and an elevation"
            )
        var demand = Float64(0)
        if len(words) > 2:
            demand = _number(words[2], "A demand", at)
        var pattern = default_pattern
        if len(words) > 3:
            pattern = words[3]
            if pattern not in patterns:
                raise Error(
                    file_line("inp", at), "the file has no pattern ", pattern
                )
        demand *= multiplier * patterns.get(pattern, 1.0)
        var id = out.network.add_junction(
            Length64(_number(words[1], "An elevation", at) * length_unit),
            VolumeFlowRate64(demand * flow),
        )
        _name_node(out, words[0], id.value, at)
    var reservoirs = _section(sections, "[RESERVOIRS]")
    for k in range(len(reservoirs)):
        ref words = reservoirs[k].words
        var at = reservoirs[k].number
        if len(words) < 2:
            raise Error(
                file_line("inp", at), "a reservoir needs a name and a head"
            )
        var id = out.network.add_reservoir(
            Length64(_number(words[1], "A head", at) * length_unit)
        )
        _name_node(out, words[0], id.value, at)
    var tanks = _section(sections, "[TANKS]")
    for k in range(len(tanks)):
        ref words = tanks[k].words
        var at = tanks[k].number
        if len(words) < 3:
            raise Error(
                file_line("inp", at),
                "a tank needs a name, an elevation and a first level",
            )
        var head = _number(words[1], "An elevation", at) + _number(
            words[2], "A level", at
        )
        var id = out.network.add_reservoir(Length64(head * length_unit))
        _name_node(out, words[0], id.value, at)
    var pipes = _section(sections, "[PIPES]")
    for k in range(len(pipes)):
        ref words = pipes[k].words
        var at = pipes[k].number
        if len(words) < 6:
            raise Error(
                file_line("inp", at),
                (
                    "a pipe needs a name, two nodes, a length, a diameter and"
                    " a roughness"
                ),
            )
        var minor = Float64(0)
        if len(words) > 6:
            minor = _number(words[6], "A minor loss", at)
        if len(words) > 7 and words[7] != "OPEN":
            raise Error(
                file_line("inp", at),
                (
                    "a pipe must be OPEN. A closed pipe and a check valve are"
                    " not supported."
                ),
            )
        var value = _number(words[5], "A roughness", at)
        var rough = _roughness(formula, value, rough_unit)
        var id = out.network.add_pipe(
            _end(out, words[1], at),
            _end(out, words[2], at),
            Length64(_number(words[3], "A length", at) * length_unit),
            Length64(_number(words[4], "A diameter", at) * diameter_unit),
            rough,
            minor,
        )
        _name_link(out, words[0], id.value, at)
    var pumps = _section(sections, "[PUMPS]")
    for k in range(len(pumps)):
        ref words = pumps[k].words
        var at = pumps[k].number
        if len(words) < 5 or words[3] != "HEAD":
            raise Error(
                file_line("inp", at),
                "a pump needs a name, two nodes, HEAD and a curve",
            )
        if curve_points.get(words[4], 0) != 1:
            raise Error(
                file_line("inp", at),
                "a pump needs a head curve of one point",
            )
        var id = out.network.add_pump(
            _end(out, words[1], at),
            _end(out, words[2], at),
            VolumeFlowRate64(curve_flow[words[4]] * flow),
            Length64(curve_head[words[4]] * length_unit),
        )
        _name_link(out, words[0], id.value, at)
    return out^


def _section(
    sections: Dict[String, List[_Line]], name: String
) raises -> List[_Line]:
    """Return the data lines of a section, or none if the file lacks it."""
    if name not in sections:
        return List[_Line]()
    return sections[name].copy()


def _roughness(
    formula: HeadLossFormula, value: Float64, rough_unit: Float64
) -> Roughness:
    """Return the roughness of a pipe for the formula of the file."""
    if formula == HAZEN_WILLIAMS:
        return hazen_williams(value)
    if formula == CHEZY_MANNING:
        return chezy_manning(value)
    return darcy_weisbach(Length64(value * rough_unit))


def _name_node(
    mut built: InpNetwork, name: String, index: Int, line: Int
) raises:
    """Record the name of a new node."""
    if name in built._nodes:
        raise Error(file_line("inp", line), "the node ", name, " repeats")
    built._nodes[name] = index
    built.node_names.append(name)


def _name_link(
    mut built: InpNetwork, name: String, index: Int, line: Int
) raises:
    """Record the name of a new link."""
    if name in built._links:
        raise Error(file_line("inp", line), "the link ", name, " repeats")
    built._links[name] = index
    built.link_names.append(name)


def _end(built: InpNetwork, name: String, line: Int) raises -> NodeId:
    """Return the node at an end of a link."""
    var index = built._nodes.get(name, -1)
    if index < 0:
        raise Error(file_line("inp", line), "the file has no node ", name)
    return NodeId(index)


def read_inp(path: String) raises -> InpNetwork:
    """Return the network in an EPANET input file.

    Args:
        path: The file.

    Returns:
        The network, the names of its nodes and links, and the solver
        options of the file.

    Raises:
        Error: If the file cannot be read, or `parse_inp` refuses it.
    """
    return parse_inp(Path(path).read_text())
