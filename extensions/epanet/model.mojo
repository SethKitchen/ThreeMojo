# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from types.h of OWA EPANET 2.3.6. Copyright (c) 2023 the EPANET
# contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The objects of a pipe network and the state of the EPANET engine.

Each struct is a struct of `types.h`. The arrays start at index 1, as in
the C code, and index 0 is not used. Lengths are in feet, flows in cubic
feet per second and times in seconds.
"""

from extensions.epanet.kinds import (
    CLOSED,
    ControlType,
    CurveType,
    DDA,
    DemandModel,
    FlowDirection,
    FlowUnits,
    GPM,
    HeadLossType,
    HW,
    JUNCTION,
    LinkType,
    MIX1,
    MixType,
    NodeType,
    NONE,
    PIPE,
    PSI,
    PressureUnits,
    PumpType,
    QualityType,
    SourceType,
    StatusType,
    US,
    UnitSystem,
    CONCEN,
    CONST_HP,
    GENERIC_CURVE,
    LOWLEVEL,
    ZERO_FLOW,
)

# The indices of the unit conversion factors, the FieldType of types.h.
comptime ELEV = 0
comptime DEMAND = 1
comptime HEAD = 2
comptime PRESSURE = 3
comptime QUALITY = 4
comptime LENGTH = 5
comptime DIAM = 6
comptime FLOW = 7
comptime VELOCITY = 8
comptime HEADLOSS = 9
comptime LINKQUAL = 10
comptime STATUS = 11
comptime SETTING = 12
comptime REACTRATE = 13
comptime FRICTION = 14
comptime POWER = 15
comptime TIME = 16
comptime VOLUME = 17
comptime CLOCKTIME = 18
comptime FILLTIME = 19
comptime DRAINTIME = 20
comptime MAXVAR = 21


@fieldwise_init
struct Demand(Copyable, Movable):
    """One demand category of a junction."""

    var base: Float64
    var pat: Int
    var name: String


@fieldwise_init
struct Source(Copyable, Movable):
    """A water quality source at a node."""

    var c0: Float64
    var pat: Int
    var smass: Float64
    var type: SourceType


struct Node(Copyable, Movable):
    """A junction, a reservoir or a tank."""

    var id: String
    var el: Float64
    var demands: List[Demand]
    var has_source: Bool
    var source: Source
    var c0: Float64
    var ke: Float64
    var type: NodeType

    def __init__(out self):
        """Make an empty junction."""
        self.id = String()
        self.el = 0.0
        self.demands = List[Demand]()
        self.has_source = False
        self.source = Source(0.0, 0, 0.0, CONCEN)
        self.c0 = 0.0
        self.ke = 0.0
        self.type = JUNCTION


struct Link(Copyable, Movable):
    """A pipe, a pump or a valve."""

    var id: String
    var n1: Int
    var n2: Int
    var diam: Float64
    var len: Float64
    var kc: Float64
    var km: Float64
    var kb: Float64
    var kw: Float64
    var r: Float64
    var rc: Float64
    var leak_area: Float64
    var leak_expan: Float64
    var type: LinkType
    var init_status: StatusType
    var init_setting: Float64

    def __init__(out self):
        """Make an empty pipe."""
        self.id = String()
        self.n1 = 0
        self.n2 = 0
        self.diam = 0.0
        self.len = 0.0
        self.kc = 0.0
        self.km = 0.0
        self.kb = 0.0
        self.kw = 0.0
        self.r = 0.0
        self.rc = 0.0
        self.leak_area = 0.0
        self.leak_expan = 0.0
        self.type = PIPE
        self.init_status = CLOSED
        self.init_setting = 0.0


struct Tank(Copyable, Movable):
    """A tank, or a reservoir when its area is zero."""

    var node: Int
    var a: Float64
    var hmin: Float64
    var hmax: Float64
    var h0: Float64
    var vmin: Float64
    var vmax: Float64
    var v0: Float64
    var kb: Float64
    var v: Float64
    var c: Float64
    var vq: Float64
    var pat: Int
    var vcurve: Int
    var mix_model: MixType
    var v1frac: Float64
    var can_overflow: Bool

    def __init__(out self):
        """Make an empty reservoir."""
        self.node = 0
        self.a = 0.0
        self.hmin = 0.0
        self.hmax = 0.0
        self.h0 = 0.0
        self.vmin = 0.0
        self.vmax = 0.0
        self.v0 = 0.0
        self.kb = 0.0
        self.v = 0.0
        self.c = 0.0
        self.vq = 0.0
        self.pat = 0
        self.vcurve = 0
        self.mix_model = MIX1
        self.v1frac = 1.0
        self.can_overflow = False


struct Energy(Copyable, Movable):
    """The energy use of a pump."""

    var time_on_line: Float64
    var efficiency: Float64
    var kw_hrs_per_flow: Float64
    var kw_hrs: Float64
    var max_kwatts: Float64
    var total_cost: Float64
    var current_power: Float64
    var current_effic: Float64

    def __init__(out self):
        """Make a record of zero use."""
        self.time_on_line = 0.0
        self.efficiency = 0.0
        self.kw_hrs_per_flow = 0.0
        self.kw_hrs = 0.0
        self.max_kwatts = 0.0
        self.total_cost = 0.0
        self.current_power = 0.0
        self.current_effic = 0.0


struct Pump(Copyable, Movable):
    """The curve and the energy data of a pump link."""

    var link: Int
    var ptype: PumpType
    var q0: Float64
    var qmax: Float64
    var hmax: Float64
    var h0: Float64
    var r: Float64
    var n: Float64
    var hcurve: Int
    var ecurve: Int
    var upat: Int
    var epat: Int
    var ecost: Float64
    var energy: Energy

    def __init__(out self):
        """Make a pump with no curve."""
        self.link = 0
        self.ptype = CONST_HP
        self.q0 = 0.0
        self.qmax = 0.0
        self.hmax = 0.0
        self.h0 = 0.0
        self.r = 0.0
        self.n = 0.0
        self.hcurve = 0
        self.ecurve = 0
        self.upat = 0
        self.epat = 0
        self.ecost = 0.0
        self.energy = Energy()


@fieldwise_init
struct Valve(Copyable, Movable):
    """The link and the loss curve of a valve."""

    var link: Int
    var curve: Int


@fieldwise_init
struct Control(Copyable, Movable):
    """A simple control statement."""

    var link: Int
    var node: Int
    var time: Int
    var grade: Float64
    var setting: Float64
    var status: StatusType
    var type: ControlType
    var is_enabled: Bool


struct Pattern(Copyable, Movable):
    """A time pattern of multipliers."""

    var id: String
    var f: List[Float64]

    def __init__(out self, id: String):
        """Make an empty pattern.

        Args:
            id: The name of the pattern.
        """
        self.id = id
        self.f = List[Float64]()


struct Curve(Copyable, Movable):
    """A data curve of x and y points."""

    var id: String
    var type: CurveType
    var x: List[Float64]
    var y: List[Float64]

    def __init__(out self, id: String):
        """Make an empty generic curve.

        Args:
            id: The name of the curve.
        """
        self.id = id
        self.type = GENERIC_CURVE
        self.x = List[Float64]()
        self.y = List[Float64]()

    def npts(self) -> Int:
        """Return the number of points.

        Returns:
            The length of the x list.
        """
        return len(self.x)


@fieldwise_init
struct Premise(Copyable, Movable):
    """A premise clause of a rule. The codes are those of rules.c."""

    var logop: Int
    var object: Int
    var index: Int
    var variable: Int
    var relop: Int
    var status: Int
    var value: Float64


@fieldwise_init
struct Action(Copyable, Movable):
    """An action clause of a rule."""

    var link: Int
    var status: Int
    var setting: Float64


struct Rule(Copyable, Movable):
    """A rule-based control."""

    var label: String
    var priority: Float64
    var is_enabled: Bool
    var premises: List[Premise]
    var then_actions: List[Action]
    var else_actions: List[Action]

    def __init__(out self, label: String):
        """Make an empty rule.

        Args:
            label: The label of the rule.
        """
        self.label = label
        self.priority = 0.0
        self.is_enabled = True
        self.premises = List[Premise]()
        self.then_actions = List[Action]()
        self.else_actions = List[Action]()


@fieldwise_init
struct AdjItem(Copyable, Movable):
    """An entry of a node's adjacency list: the node across and the link."""

    var node: Int
    var link: Int


@fieldwise_init
struct Seg(Copyable, Movable):
    """A volume segment of a pipe or a tank. `prev` 0 means none."""

    var v: Float64
    var c: Float64
    var prev: Int


@fieldwise_init
struct Leakage(Copyable, Movable):
    """The leakage of a node: fixed and variable area flows and coefficients."""

    var qfa: Float64
    var qva: Float64
    var cfa: Float64
    var cva: Float64


struct Network(Copyable, Movable):
    """The objects of a pipe network and their name lookups."""

    var nnodes: Int
    var ntanks: Int
    var njuncs: Int
    var nlinks: Int
    var npipes: Int
    var npumps: Int
    var nvalves: Int
    var ncontrols: Int
    var nrules: Int
    var npats: Int
    var ncurves: Int
    var node: List[Node]
    var link: List[Link]
    var tank: List[Tank]
    var pump: List[Pump]
    var valve: List[Valve]
    var pattern: List[Pattern]
    var curve: List[Curve]
    var control: List[Control]
    var rule: List[Rule]
    var node_index: Dict[String, Int]
    var link_index: Dict[String, Int]
    # Each list holds a node's links in the order they were read. The C
    # lists put each new entry first, so the engine walks these backward.
    var adjlist: List[List[AdjItem]]

    def __init__(out self):
        """Make an empty network."""
        self.nnodes = 0
        self.ntanks = 0
        self.njuncs = 0
        self.nlinks = 0
        self.npipes = 0
        self.npumps = 0
        self.nvalves = 0
        self.ncontrols = 0
        self.nrules = 0
        self.npats = 0
        self.ncurves = 0
        self.node = List[Node]()
        self.link = List[Link]()
        self.tank = List[Tank]()
        self.pump = List[Pump]()
        self.valve = List[Valve]()
        self.pattern = List[Pattern]()
        self.curve = List[Curve]()
        self.control = List[Control]()
        self.rule = List[Rule]()
        self.node_index = Dict[String, Int]()
        self.link_index = Dict[String, Int]()
        self.adjlist = List[List[AdjItem]]()


struct Parser(Copyable, Movable):
    """The state of the input file reader."""

    var def_pat_id: String
    var max_nodes: Int
    var max_links: Int
    var max_juncs: Int
    var max_pipes: Int
    var max_tanks: Int
    var max_pumps: Int
    var max_valves: Int
    var max_controls: Int
    var max_rules: Int
    var max_pats: Int
    var max_curves: Int
    var units_flag: UnitSystem
    var flow_flag: FlowUnits
    var press_flag: PressureUnits
    var prev_pat: Int
    var prev_curve: Int
    var tok: List[String]
    var line_number: Int

    def __init__(out self):
        """Make a reader with no counts."""
        self.def_pat_id = String()
        self.max_nodes = 0
        self.max_links = 0
        self.max_juncs = 0
        self.max_pipes = 0
        self.max_tanks = 0
        self.max_pumps = 0
        self.max_valves = 0
        self.max_controls = 0
        self.max_rules = 0
        self.max_pats = 0
        self.max_curves = 0
        self.units_flag = US
        self.flow_flag = GPM
        self.press_flag = PSI
        self.prev_pat = 0
        self.prev_curve = 0
        self.tok = List[String]()
        self.line_number = 0


struct Times(Copyable, Movable):
    """The time steps and the clocks of a run, in seconds."""

    var tstart: Int
    var hstep: Int
    var pstep: Int
    var pstart: Int
    var rstep: Int
    var rstart: Int
    var rtime: Int
    var htime: Int
    var hydstep: Int
    var qstep: Int
    var qtime: Int
    var rulestep: Int
    var dur: Int

    def __init__(out self):
        """Make zero clocks."""
        self.tstart = 0
        self.hstep = 0
        self.pstep = 0
        self.pstart = 0
        self.rstep = 0
        self.rstart = 0
        self.rtime = 0
        self.htime = 0
        self.hydstep = 0
        self.qstep = 0
        self.qtime = 0
        self.rulestep = 0
        self.dur = 0


struct Smatrix(Copyable, Movable):
    """The sparse matrix of the hydraulic equations."""

    var aii: List[Float64]
    var aij: List[Float64]
    var f: List[Float64]
    var temp: List[Float64]
    var ncoeffs: Int
    var order: List[Int]
    var row: List[Int]
    var ndx: List[Int]
    var xlnz: List[Int]
    var nzsub: List[Int]
    var lnz: List[Int]
    var link: List[Int]
    var first: List[Int]

    def __init__(out self):
        """Make an empty matrix."""
        self.aii = List[Float64]()
        self.aij = List[Float64]()
        self.f = List[Float64]()
        self.temp = List[Float64]()
        self.ncoeffs = 0
        self.order = List[Int]()
        self.row = List[Int]()
        self.ndx = List[Int]()
        self.xlnz = List[Int]()
        self.nzsub = List[Int]()
        self.lnz = List[Int]()
        self.link = List[Int]()
        self.first = List[Int]()


@fieldwise_init
struct FlowBalance(Copyable, Movable):
    """The flow balance of a run."""

    var total_inflow: Float64
    var total_outflow: Float64
    var consumer_demand: Float64
    var emitter_demand: Float64
    var leakage_demand: Float64
    var deficit_demand: Float64
    var storage_demand: Float64
    var ratio: Float64


def zero_flow_balance() -> FlowBalance:
    """Return a flow balance of zeros.

    Returns:
        A `FlowBalance` with every term zero.
    """
    return FlowBalance(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)


struct Hydraul(Copyable, Movable):
    """The state and the options of the hydraulic solver."""

    var node_head: List[Float64]
    var node_demand: List[Float64]
    var full_demand: List[Float64]
    var demand_flow: List[Float64]
    var emitter_flow: List[Float64]
    var leakage_flow: List[Float64]
    var link_flow: List[Float64]
    var link_setting: List[Float64]
    var htol: Float64
    var qtol: Float64
    var rqtol: Float64
    var hexp: Float64
    var qexp: Float64
    var pexp: Float64
    var pmin: Float64
    var preq: Float64
    var dmult: Float64
    var hacc: Float64
    var flow_change_limit: Float64
    var head_error_limit: Float64
    var damp_limit: Float64
    var viscos: Float64
    var sp_grav: Float64
    var epump: Float64
    var dsystem: Float64
    var ecost: Float64
    var dcost: Float64
    var emax: Float64
    var relative_error: Float64
    var max_head_error: Float64
    var max_flow_change: Float64
    var demand_reduction: Float64
    var leakage_loss: Float64
    var relax_factor: Float64
    var p: List[Float64]
    var y: List[Float64]
    var xflow: List[Float64]
    var def_pat: Int
    var epat: Int
    var demand_model: DemandModel
    var formflag: HeadLossType
    var emit_back_flag: Bool
    var iterations: Int
    var max_iter: Int
    var extra_iter: Int
    var check_freq: Int
    var max_check: Int
    var open_hflag: Bool
    var halt_flag: Bool
    var deficient_nodes: Int
    var has_leakage: Bool
    var leakage: List[Leakage]
    var link_status: List[StatusType]
    var old_status: List[StatusType]
    var flow_balance: FlowBalance
    var sm: Smatrix

    def __init__(out self):
        """Make a solver with no arrays."""
        self.node_head = List[Float64]()
        self.node_demand = List[Float64]()
        self.full_demand = List[Float64]()
        self.demand_flow = List[Float64]()
        self.emitter_flow = List[Float64]()
        self.leakage_flow = List[Float64]()
        self.link_flow = List[Float64]()
        self.link_setting = List[Float64]()
        self.htol = 0.0
        self.qtol = 0.0
        self.rqtol = 0.0
        self.hexp = 0.0
        self.qexp = 0.0
        self.pexp = 0.0
        self.pmin = 0.0
        self.preq = 0.0
        self.dmult = 0.0
        self.hacc = 0.0
        self.flow_change_limit = 0.0
        self.head_error_limit = 0.0
        self.damp_limit = 0.0
        self.viscos = 0.0
        self.sp_grav = 0.0
        self.epump = 0.0
        self.dsystem = 0.0
        self.ecost = 0.0
        self.dcost = 0.0
        self.emax = 0.0
        self.relative_error = 0.0
        self.max_head_error = 0.0
        self.max_flow_change = 0.0
        self.demand_reduction = 0.0
        self.leakage_loss = 0.0
        self.relax_factor = 1.0
        self.p = List[Float64]()
        self.y = List[Float64]()
        self.xflow = List[Float64]()
        self.def_pat = 0
        self.epat = 0
        self.demand_model = DDA
        self.formflag = HW
        self.emit_back_flag = True
        self.iterations = 0
        self.max_iter = 0
        self.extra_iter = 0
        self.check_freq = 0
        self.max_check = 0
        self.open_hflag = False
        self.halt_flag = False
        self.deficient_nodes = 0
        self.has_leakage = False
        self.leakage = List[Leakage]()
        self.link_status = List[StatusType]()
        self.old_status = List[StatusType]()
        self.flow_balance = zero_flow_balance()
        self.sm = Smatrix()


@fieldwise_init
struct MassBalance(Copyable, Movable):
    """The mass balance of a water quality run."""

    var initial: Float64
    var inflow: Float64
    var outflow: Float64
    var reacted: Float64
    var final: Float64
    var ratio: Float64
    var seg_count: Int


struct Quality(Copyable, Movable):
    """The state and the options of the water quality solver."""

    var qualflag: QualityType
    var open_qflag: Bool
    var reactflag: Bool
    var trace_node: Int
    var sorted_nodes: List[Int]
    var chem_name: String
    var chem_units: String
    var ctol: Float64
    var diffus: Float64
    var wbulk: Float64
    var wwall: Float64
    var wtank: Float64
    var wsource: Float64
    var rfactor: Float64
    var sc: Float64
    var bucf: Float64
    var tucf: Float64
    var bulk_order: Float64
    var wall_order: Float64
    var tank_order: Float64
    var kbulk: Float64
    var kwall: Float64
    var climit: Float64
    var source_qual: Float64
    var node_qual: List[Float64]
    var pipe_rate_coeff: List[Float64]
    # The segment pool. Entry 0 stands for a null segment.
    var seg: List[Seg]
    var free_seg: Int
    var first_seg: List[Int]
    var last_seg: List[Int]
    var flow_dir: List[FlowDirection]
    var mass_balance: MassBalance

    def __init__(out self):
        """Make a solver with no analysis."""
        self.qualflag = NONE
        self.open_qflag = False
        self.reactflag = False
        self.trace_node = 0
        self.sorted_nodes = List[Int]()
        self.chem_name = String()
        self.chem_units = String()
        self.ctol = 0.0
        self.diffus = 0.0
        self.wbulk = 0.0
        self.wwall = 0.0
        self.wtank = 0.0
        self.wsource = 0.0
        self.rfactor = 0.0
        self.sc = 0.0
        self.bucf = 1.0
        self.tucf = 1.0
        self.bulk_order = 0.0
        self.wall_order = 0.0
        self.tank_order = 0.0
        self.kbulk = 0.0
        self.kwall = 0.0
        self.climit = 0.0
        self.source_qual = 0.0
        self.node_qual = List[Float64]()
        self.pipe_rate_coeff = List[Float64]()
        self.seg = List[Seg]()
        self.free_seg = 0
        self.first_seg = List[Int]()
        self.last_seg = List[Int]()
        self.flow_dir = List[FlowDirection]()
        self.mass_balance = MassBalance(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0)


struct RulesState(Copyable, Movable):
    """The state of the rule reader and of the rule evaluation."""

    var rule_state: Int
    var errcode: Int
    var time1: Int

    def __init__(out self):
        """Make a rule reader that waits for a rule."""
        self.rule_state = 6
        self.errcode = 0
        self.time1 = 0


struct SavedHydraulics(Copyable, Movable):
    """One hydraulic step as `savehyd` writes it to the hydraulics file."""

    var time: Int
    var demand: List[Float32]
    var head: List[Float32]
    var flow: List[Float32]
    var status: List[Float32]
    var setting: List[Float32]
    var step: Int

    def __init__(out self, time: Int):
        """Make an empty record.

        Args:
            time: The time of the step, in seconds.
        """
        self.time = time
        self.demand = List[Float32]()
        self.head = List[Float32]()
        self.flow = List[Float32]()
        self.status = List[Float32]()
        self.setting = List[Float32]()
        self.step = 0


struct Project(Movable):
    """A network and the state of its simulation, as in the C Project."""

    var net: Network
    var parser: Parser
    var times: Times
    var rules: RulesState
    var hyd: Hydraul
    var qual: Quality
    var ucf: List[Float64]
    var openflag: Bool
    var warnflag: Int
    var title: List[String]
    var saveflag: Bool
    var save_hflag: Bool
    # The hydraulic results that the quality solver reads, one entry for
    # each hydraulic step, rounded to single precision as in the binary
    # hydraulics file of EPANET.
    var hyd_file: List[SavedHydraulics]
    var hyd_file_pos: Int

    def __init__(out self):
        """Make an empty project."""
        self.net = Network()
        self.parser = Parser()
        self.times = Times()
        self.rules = RulesState()
        self.hyd = Hydraul()
        self.qual = Quality()
        self.ucf = List[Float64](length=MAXVAR, fill=1.0)
        self.openflag = False
        self.warnflag = 0
        self.title = List[String]()
        self.saveflag = False
        self.save_hflag = False
        self.hyd_file = List[SavedHydraulics]()
        self.hyd_file_pos = 0
