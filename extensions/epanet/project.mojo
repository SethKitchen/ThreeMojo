# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from epanet.c and errors.dat of OWA EPANET 2.3.6. Copyright (c)
# 2023 the EPANET contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""An EPANET project: read a network, run its hydraulics and its quality.

`EpanetProject` follows the toolkit functions of EPANET 2.3. Open the
hydraulic solver, then call `run_hydraulics` and `next_hydraulics` in a
loop until the step is zero. Then do the same for the water quality.

```mojo
var p = EpanetProject(text)
p.open_hydraulics()
p.init_hydraulics(save=True)
while True:
    var t = p.run_hydraulics()
    var head = p.head(NodeIndex(1))
    if p.next_hydraulics().value == 0.0:
        break
```

The typed results are in SI units. `node_value` and `link_value` give a
value in the units of the input file, as `EN_getnodevalue` and
`EN_getlinkvalue` do.
"""

from extensions.epanet.api import link_value, node_value
from extensions.epanet.cmath import mul
from extensions.epanet.hydraul import inithyd, nexthyd, openhyd, runhyd
from extensions.epanet.input import error_text
from extensions.epanet.kinds import (
    CLOSED,
    LinkIndex,
    LinkProperty,
    M3_PER_FT3,
    NodeIndex,
    NodeProperty,
    QualityType,
)
from extensions.epanet.lookup import findlink, findnode
from extensions.epanet.model import Project
from extensions.epanet.prepare import openproject
from extensions.epanet.quality import initqual, nextqual, openqual, runqual
from units.si import (
    CUBIC_METER_PER_SECOND,
    Duration64,
    FOOT64,
    Length64,
    SECOND,
    VolumeFlowRate64,
)


def _check(code: Int, errors: List[String]) raises:
    """Raise an error for a nonzero EPANET error code."""
    if code == 0:
        return
    var message = String("EPANET error ", code, ": ", error_text(code))
    for e in errors:
        message += "\n" + e
    raise Error(message)


struct EpanetProject(Movable):
    """A pipe network read from an EPANET input file, and its solvers."""

    var pr: Project

    def __init__(out self, text: String) raises:
        """Read a network from the text of an EPANET input file.

        Args:
            text: The text of an input file (`.inp`).

        Raises:
            Error: The text has an error. The message lists each line
                with an error, as EPANET reports them.
        """
        self.pr = Project()
        openproject(self.pr, text)

    def node_count(self) -> Int:
        """Return the number of nodes.

        Returns:
            The number of junctions, reservoirs and tanks.
        """
        return self.pr.net.nnodes

    def link_count(self) -> Int:
        """Return the number of links.

        Returns:
            The number of pipes, pumps and valves.
        """
        return self.pr.net.nlinks

    def node_index(self, id: String) raises -> NodeIndex:
        """Return the index of a node.

        Args:
            id: The ID label of the node.

        Returns:
            The index of the node.

        Raises:
            Error: No node has the ID.
        """
        var i = findnode(self.pr.net, id)
        if i == 0:
            raise Error("EPANET error 203: undefined node")
        return NodeIndex(i)

    def link_index(self, id: String) raises -> LinkIndex:
        """Return the index of a link.

        Args:
            id: The ID label of the link.

        Returns:
            The index of the link.

        Raises:
            Error: No link has the ID.
        """
        var i = findlink(self.pr.net, id)
        if i == 0:
            raise Error("EPANET error 204: undefined link")
        return LinkIndex(i)

    def _node(self, node: NodeIndex) raises -> Int:
        """Return the index of a node after a check of its range."""
        if not node.is_valid() or node.value > self.pr.net.nnodes:
            raise Error("EPANET error 203: undefined node")
        return node.value

    def _link(self, link: LinkIndex) raises -> Int:
        """Return the index of a link after a check of its range."""
        if not link.is_valid() or link.value > self.pr.net.nlinks:
            raise Error("EPANET error 204: undefined link")
        return link.value

    def node_id(self, node: NodeIndex) raises -> String:
        """Return the ID label of a node.

        Args:
            node: The node.

        Returns:
            The ID label.

        Raises:
            Error: The index is out of range.
        """
        return self.pr.net.node[self._node(node)].id

    def link_id(self, link: LinkIndex) raises -> String:
        """Return the ID label of a link.

        Args:
            link: The link.

        Returns:
            The ID label.

        Raises:
            Error: The index is out of range.
        """
        return self.pr.net.link[self._link(link)].id

    def duration(self) -> Duration64:
        """Return the duration of the simulation.

        Returns:
            The duration.
        """
        return Duration64(Float64(self.pr.times.dur), SECOND)

    def report_step(self) -> Duration64:
        """Return the time between two reports.

        Returns:
            The report time step.
        """
        return Duration64(Float64(self.pr.times.rstep), SECOND)

    def quality_type(self) -> QualityType:
        """Return the kind of water quality analysis.

        Returns:
            `NONE`, `CHEM`, `AGE` or `TRACE`.
        """
        return self.pr.qual.qualflag

    def open_hydraulics(mut self) raises:
        """Make the hydraulic solver, as `EN_openH` does.

        Raises:
            Error: The network cannot be solved, for example because a
                node has no links.
        """
        var errors = List[String]()
        _check(openhyd(self.pr, errors), errors)

    def init_hydraulics(mut self, save: Bool, init_flows: Bool = False) raises:
        """Set the starting state of the hydraulics, as `EN_initH` does.

        Args:
            save: Whether to save the results for a later water quality
                run.
            init_flows: Whether to set each starting flow again, and not
                keep the flows of the last run.

        Raises:
            Error: The hydraulic solver is not open.
        """
        if not self.pr.hyd.open_hflag:
            _check(103, List[String]())
        inithyd(self.pr, 1 if init_flows else 0, save)

    def run_hydraulics(mut self) raises -> Duration64:
        """Solve the hydraulics at the current time, as `EN_runH` does.

        Returns:
            The current time of the simulation.

        Raises:
            Error: The solver is not open, or the equations have no
                solution.
        """
        if not self.pr.hyd.open_hflag:
            _check(103, List[String]())
        var t = 0
        _check(runhyd(self.pr, t), List[String]())
        return Duration64(Float64(t), SECOND)

    def next_hydraulics(mut self) raises -> Duration64:
        """Move to the next hydraulic event, as `EN_nextH` does.

        Returns:
            The time step to the next event. It is zero at the end.

        Raises:
            Error: The hydraulic solver is not open.
        """
        if not self.pr.hyd.open_hflag:
            _check(103, List[String]())
        var step = 0
        _ = nexthyd(self.pr, step)
        return Duration64(Float64(step), SECOND)

    def close_hydraulics(mut self):
        """Close the hydraulic solver, as `EN_closeH` does.

        A water quality run after this reads the saved hydraulics.
        """
        self.pr.hyd.open_hflag = False

    def open_quality(mut self) raises:
        """Make the water quality solver, as `EN_openQ` does.

        While the hydraulic solver is open, the water quality uses its
        current state, one step at a time. After `close_hydraulics`, it
        reads the hydraulics that `init_hydraulics(save=True)` saved.

        Raises:
            Error: No hydraulics were saved and the hydraulic solver is
                closed.
        """
        _check(openqual(self.pr), List[String]())

    def init_quality(mut self) raises:
        """Set the starting state of the water quality, as `EN_initQ` does.

        Raises:
            Error: The water quality solver is not open.
        """
        if not self.pr.qual.open_qflag:
            _check(105, List[String]())
        initqual(self.pr)

    def run_quality(mut self) raises -> Duration64:
        """Load the hydraulics of the current time, as `EN_runQ` does.

        Returns:
            The current time of the simulation.

        Raises:
            Error: The solver is not open, or the saved hydraulics end.
        """
        if not self.pr.qual.open_qflag:
            _check(105, List[String]())
        var t = 0
        _check(runqual(self.pr, t), List[String]())
        return Duration64(Float64(t), SECOND)

    def next_quality(mut self) raises -> Duration64:
        """Move the water quality to the next hydraulic step.

        This is `EN_nextQ`.

        Returns:
            The time step. It is zero at the end.

        Raises:
            Error: The water quality solver is not open.
        """
        if not self.pr.qual.open_qflag:
            _check(105, List[String]())
        var step = 0
        _ = nextqual(self.pr, step)
        return Duration64(Float64(step), SECOND)

    def close_quality(mut self):
        """Close the water quality solver, as `EN_closeQ` does."""
        self.pr.qual.open_qflag = False

    def head(self, node: NodeIndex) raises -> Length64:
        """Return the hydraulic head of a node.

        Args:
            node: The node.

        Returns:
            The head.

        Raises:
            Error: The index is out of range.
        """
        return Length64(self.pr.hyd.node_head[self._node(node)], FOOT64)

    def pressure_head(self, node: NodeIndex) raises -> Length64:
        """Return the pressure of a node as a height of water.

        Args:
            node: The node.

        Returns:
            The head less the elevation.

        Raises:
            Error: The index is out of range.
        """
        var i = self._node(node)
        return Length64(
            self.pr.hyd.node_head[i] - self.pr.net.node[i].el, FOOT64
        )

    def demand(self, node: NodeIndex) raises -> VolumeFlowRate64:
        """Return the outflow of a node.

        A tank that fills and a reservoir that takes water have a positive
        demand.

        Args:
            node: The node.

        Returns:
            The demand.

        Raises:
            Error: The index is out of range.
        """
        var q = self.pr.hyd.node_demand[self._node(node)]
        return VolumeFlowRate64(mul(q, M3_CFS), CUBIC_METER_PER_SECOND)

    def flow(self, link: LinkIndex) raises -> VolumeFlowRate64:
        """Return the flow of a link, from its start node to its end node.

        Args:
            link: The link.

        Returns:
            The flow. It is zero for a closed link.

        Raises:
            Error: The index is out of range.
        """
        var k = self._link(link)
        var q = 0.0
        if self.pr.hyd.link_status[k].value > CLOSED.value:
            q = self.pr.hyd.link_flow[k]
        return VolumeFlowRate64(mul(q, M3_CFS), CUBIC_METER_PER_SECOND)

    def node_value(self, node: NodeIndex, prop: NodeProperty) raises -> Float64:
        """Return a result of a node, as `EN_getnodevalue` does.

        Args:
            node: The node.
            prop: `EN_DEMAND`, `EN_HEAD`, `EN_PRESSURE` or `EN_QUALITY`.

        Returns:
            The value in the units of the input file.

        Raises:
            Error: The index or the property is not valid.
        """
        return node_value(self.pr, self._node(node), prop)

    def link_value(self, link: LinkIndex, prop: LinkProperty) raises -> Float64:
        """Return a result of a link, as `EN_getlinkvalue` does.

        Args:
            link: The link.
            prop: `EN_FLOW`, `EN_STATUS`, `EN_SETTING`, `EN_ENERGY` or
                `EN_LINKQUAL`.

        Returns:
            The value in the units of the input file.

        Raises:
            Error: The index or the property is not valid.
        """
        return link_value(self.pr, self._link(link), prop)


# The exact number of cubic meters in a cubic foot.
comptime M3_CFS = 0.028316846592
