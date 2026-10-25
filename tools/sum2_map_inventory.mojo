# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live Map and map-builder inventories.

The Map file keeps 73 reviewed spans. The map-builder file keeps 67
reviewed spans. Restoring those spans matches the pinned use digests.
"""

from std.pathlib import Path

from tools._python_json import PY_STR, PyJson
from tools.sum2_guard_inventory import _digest


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _MAP_SPANS = 73
comptime _BUILDER_SPANS = 67

comptime _MAP_LIVE_0 = (
    "**Two segment indices.** The map keeps CARLA's heading and length\np"
    "artition in its own R-tree. `closest_waypoint_on_road`, `waypoint` a"
    "nd\nthe sign check at load use it with CARLA's algorithm: the neares"
    "t segment,\nthen a step along the lane to the point's foot. These qu"
    "eries do not use\nthe certified search budget. Input validation, lan"
    "e stepping and canonical\npose evaluation can still raise errors. Th"
    "ey keep CARLA's partition, but\nthey correct one CARLA approximation"
    ". CARLA steps by the plan distance along\nthe segment chord, as if i"
    "t were road s. A lane offset, a lane width or a\ncurve can make the "
    "chord longer or shorter than its road-s span. A sloped\nlane then mi"
    "sses points on its center. This port steps by the foot's plan\nfract"
    "ion of the chord times the chord's road-s span (#302).\n\n**The cert"
    "ified index.** `certified_closest_waypoint_on_road` and\n`certified_"
    "waypoint` use a second index. It starts with CARLA's partition\nand "
    "splits again at record boundaries and until quarter-point\nchord err"
    "ors are at most one millimeter. A required split without an\n"
)

comptime _MAP_OLD_0 = (
    "**Two segment indices.** The map keeps CARLA's heading and length\np"
    "artition in its own R-tree. `closest_waypoint_on_road`, `waypoint` a"
    "nd\nthe sign check at load use it with CARLA's algorithm: the neares"
    "t segment,\nthen a step along the lane to the point's foot. These qu"
    "eries do not use\nthe certified search budget. Input validation, lan"
    "e stepping and canonical\npose evaluation can still raise errors. Th"
    "ey keep CARLA's approximations:\nthe step treats distance along the "
    "segment chord as road s.\n\n**The certified index.** `certified_clos"
    "est_waypoint_on_road` and\n`certified_waypoint` use a second index. "
    "It starts with CARLA's partition\nand splits again at record boundar"
    "ies and until quarter-point\nchord errors are at most one millimeter"
    ". A required split without an\n"
)

comptime _MAP_LIVE_1 = (
    "its incumbent; the API does not promise the first station on that pl"
    "ateau.\n\nThe public `segment_count` and `segment` methods expose th"
    "is accuracy-driven\nindex. Its partition and count can change when t"
    "he geometry requires more\nsubdivision. Lane order and index tie rul"
    "es remain deterministic. The\ncertified queries also correct the cho"
    "rd error of curved lane offsets.\nThey cost more and can raise where"
    " CARLA's query answers, so they are not\nthe default.\n\nThe R-tree,"
    " full-center bounds, and optional sampled-curve box covers belong\nt"
    "o the same construction snapshot. Queries do not update these proofs"
    ".\nAs with the existing index, callers must rebuild the Map after ed"
    "iting its\nsource road records. A cover stores only four complete in"
    "terval boxes; it\n"
)

comptime _MAP_OLD_1 = (
    "its incumbent; the API does not promise the first station on that pl"
    "ateau.\n\nThe public `segment_count` and `segment` methods expose th"
    "is accuracy-driven\nindex. Its partition and count can change when t"
    "he geometry requires more\nsubdivision. Lane order and index tie rul"
    "es remain deterministic. The\ncertified queries correct curved lane "
    "offsets and the treatment of lane\ndistance as road s. They cost mor"
    "e and can raise where CARLA's query\nanswers, so they are not the de"
    "fault.\n\nThe R-tree, full-center bounds, and optional sampled-curve"
    " box covers belong\nto the same construction snapshot. Queries do no"
    "t update these proofs.\nAs with the existing index, callers must reb"
    "uild the Map after editing its\nsource road records. A cover stores "
    "only four complete interval boxes; it\n"
)

comptime _MAP_LIVE_2 = (
    "    _refine_lane_certificate,\n    _continue_lane_certificate,\n)\nf"
    "rom extensions.carla.speed_limits import opendrive_speed, NUMERIC_SP"
    "EED_LIMIT\nfrom extensions.carla.math import (\n    make_unit_vector"
    ",\n    vector_angle,\n)\nfrom extensions.carla.road import Lane, Lan"
    "eKey, LaneSection, Road\nfrom extensions.carla.road_info import (\n"
)

comptime _MAP_OLD_2 = (
    "    _refine_lane_certificate,\n    _continue_lane_certificate,\n)\nf"
    "rom extensions.carla.speed_limits import opendrive_speed, NUMERIC_SP"
    "EED_LIMIT\nfrom extensions.carla.math import (\n    distance_segment"
    "_to_point,\n    make_unit_vector,\n    vector_angle,\n)\nfrom extens"
    "ions.carla.road import Lane, LaneKey, LaneSection, Road\nfrom extens"
    "ions.carla.road_info import (\n"
)

comptime _MAP_LIVE_3 = (
    "    RoadInfoMarkRecord,\n    RoadInfoSignal,\n    SectionId,\n    Si"
    "gnalId,\n    SignalOrientation,\n    _info_at_si as info_at,\n    _i"
    "nfo_index_si as info_index,\n    _infos_in_range_si as infos_in_rang"
    "e,\n    signal_orientation_of,\n)\nfrom extensions.carla.rtree impor"
    "t (\n    SegmentCloudRtree,\n    SegmentElement,\n"
)

comptime _MAP_OLD_3 = (
    "    RoadInfoMarkRecord,\n    RoadInfoSignal,\n    SectionId,\n    Si"
    "gnalId,\n    SignalOrientation,\n    info_at,\n    info_index,\n    "
    "infos_in_range,\n    signal_orientation_of,\n)\nfrom extensions.carl"
    "a.rtree import (\n    SegmentCloudRtree,\n    SegmentElement,\n"
)

comptime _MAP_LIVE_4 = (
    "    _segment_distance2,\n)\nfrom extensions.carla.transform import C"
    "arlaRotation, CarlaTransform\nfrom math.bounds import Box3\nfrom mat"
    "h.vector3 import Vector3\nfrom std.hash import Hasher\nfrom std.math"
    " import ceil, floor, inf, isfinite, sin, sqrt\nfrom std.memory impor"
    "t bitcast\nfrom extensions.carla.quantity_boundary import (\n    _RA"
    "W_SI,\n    _RawSI,\n    _finite_si,\n    _nonnegative_si,\n    _posi"
    "tive_si,\n)\nfrom units.si import DEGREE, Angle, Length, Length64, M"
    "ETER, Velocity64\nfrom units.si import Angle64\n\n# CARLA's `EPSILON"
    "`: waypoints sit this far inside a section's edges.\ncomptime EPSILO"
    "N = 10.0 * 2.220446049250313e-16\n# `std::numeric_limits<double>::ep"
    "silon()`.\ncomptime DOUBLE_EPSILON = 2.220446049250313e-16\n\n\n# --"
    "- waypoint ---------------------------------------------------------"
    "--------\n\n\nstruct Waypoint(Hashable, ImplicitlyCopyable, KeyEleme"
    'nt, Writable):\n    """A place on the road network, `road/element'
    '/Waypoint`."""\n\n    var road_id: RoadId\n    var section_id: Se'
    "ctionId\n    var lane_id: LaneId\n    # Meters along the road, in do"
    "uble; see the module docstring.\n    var s: Float64\n\n    def __ini"
    "t__(\n        out self,\n        road_id: RoadId,\n        section_i"
    "d: SectionId,\n        lane_id: LaneId,\n        s: Length64,\n    )"
    ' raises:\n        """Create a checked typed record without changi'
    "ng scalar storage.\n\n        Args:\n            road_id: Its source"
    " record value.\n            section_id: Its source record value.\n  "
    "          lane_id: Its source record value.\n            s: Its type"
    "d source quantity.\n\n        Returns:\n            A record with un"
    "changed source precision and layout.\n\n        Raises:\n           "
    " Error: If a quantity is not finite or another field is invalid.\n  "
    '      """\n        self = Waypoint.from_si(road_id, section_id, l'
    "ane_id, s.value)\n\n    @staticmethod\n    def from_si(\n        roa"
    "d_id: RoadId, section_id: SectionId, lane_id: LaneId, s: Float64\n  "
    '  ) raises -> Waypoint:\n        """Explicit source-unit compatib'
    "ility adapter. Create the explicit compatibility record.\n\n        "
    "Args:\n            road_id: The road identifier.\n            sectio"
    "n_id: The lane-section identifier.\n            lane_id: The signed "
    "lane identifier.\n            s: The nonnegative station in meters."
    "\n\n        Returns:\n            The new Waypoint record with the s"
    "upplied source fields.\n\n        Raises:\n            Error: If the"
    ' station is nonfinite or negative.\n        """\n        _ = _non'
    "negative_si(s)\n        return Waypoint(_RAW_SI, road_id, section_id"
    ", lane_id, s)\n\n    @staticmethod\n    def _from_si(\n        road_"
    "id: RoadId, section_id: SectionId, lane_id: LaneId, s: Float64\n    "
    ') -> Waypoint:\n        """Explicit source-unit compatibility ada'
    'pter. Create the explicit compatibility record.\n        """\n   '
    "     return Waypoint(_RAW_SI, road_id, section_id, lane_id, s)\n\n  "
    "  def __init__(\n        out self,\n        raw: _RawSI,\n        ro"
    "ad_id: RoadId,\n        section_id: SectionId,\n        lane_id: Lan"
    'eId,\n        s: Float64,\n    ):\n        """Create the explicit'
    ' compatibility record."""\n        self.road_id = road_id\n      '
    "  self.section_id = section_id\n        self.lane_id = lane_id\n    "
    "    self.s = s\n\n    def _bucket(self) -> Float64:\n        return "
    "floor(self.s * 200.0)\n\n    def __eq__(self, other: Self) -> Bool:"
    '\n        """Return True if two waypoints are the same place, as '
    "CARLA's `==`.\n"
)

comptime _MAP_OLD_4 = (
    "    _segment_distance2,\n)\nfrom extensions.carla.transform import C"
    "arlaRotation, CarlaTransform\nfrom math.bounds import Box3\nfrom mat"
    "h.vector3 import Vector3\nfrom std.hashlib import Hasher\nfrom std.m"
    "ath import ceil, floor, inf, isfinite, sin, sqrt\nfrom std.memory im"
    "port bitcast\nfrom units.si import DEGREE, Angle, Length, METER, Vel"
    "ocity64\n\n# CARLA's `EPSILON`: waypoints sit this far inside a sect"
    "ion's edges.\ncomptime EPSILON = 10.0 * 2.220446049250313e-16\n# `st"
    "d::numeric_limits<double>::epsilon()`.\ncomptime DOUBLE_EPSILON = 2."
    "220446049250313e-16\n\n\n# --- waypoint ----------------------------"
    "-------------------------------------\n\n\n@fieldwise_init\nstruct W"
    'aypoint(Hashable, ImplicitlyCopyable, KeyElement, Writable):\n    "'
    '""A place on the road network, `road/element/Waypoint`."""\n\n '
    "   var road_id: RoadId\n    var section_id: SectionId\n    var lane_"
    "id: LaneId\n    # Meters along the road, in double; see the module d"
    "ocstring.\n    var s: Float64\n\n    def _bucket(self) -> Float64:\n"
    "        return floor(self.s * 200.0)\n\n    def __eq__(self, other: "
    'Self) -> Bool:\n        """Return True if two waypoints are the s'
    "ame place, as CARLA's `==`.\n"
)

comptime _MAP_LIVE_5 = (
    '            ", s=",\n            self.s,\n            ")",\n    '
    '    )\n\n    def s_quantity(self) raises -> Length64:\n        ""'
    '"Read the checked typed view of the raw s compatibility field.\n\n '
    "       Returns:\n            The same finite Float64 value with its "
    "unit.\n\n        Raises:\n            Error: If the mutable raw valu"
    'e is not finite.\n        """\n        return Length64(_nonnegati'
    "ve_si(self.s))\n\n\n# --- junctions --------------------------------"
    "--------------------------------\n\n\n@fieldwise_init\n"
)

comptime _MAP_OLD_5 = (
    '            ", s=",\n            self.s,\n            ")",\n    '
    "    )\n\n\n# --- junctions -----------------------------------------"
    "-----------------------\n\n\n@fieldwise_init\n"
)

comptime _MAP_LIVE_6 = (
    "\n    def __init__(\n        out self,\n        road_id: RoadId,\n  "
    "      signal_id: SignalId,\n        s: Length64,\n        t: Length6"
    "4,\n        name: String,\n        dynamic: String,\n        orienta"
    "tion: String,\n        z_offset: Length64,\n        country: String,"
    "\n        type: String,\n        subtype: String,\n        value: Fl"
    "oat64,\n        unit: String,\n        height: Length64,\n        wi"
    "dth: Length64,\n        text: String,\n        h_offset: Angle64,\n "
    "       pitch: Angle64,\n        roll: Angle64,\n        value_presen"
    't: Bool = True,\n    ) raises:\n        """Create a checked typed'
    " record without changing scalar storage.\n\n        Args:\n         "
    "   road_id: Its source record value.\n            signal_id: Its sou"
    "rce record value.\n            s: Its typed source quantity.\n      "
    "      t: Its typed source quantity.\n            name: Its source re"
    "cord value.\n            dynamic: Its source record value.\n        "
    "    orientation: Its source record value.\n            z_offset: Its"
    " typed source quantity.\n            country: Its source record valu"
    "e.\n            type: Its source record value.\n            subtype:"
    " Its source record value.\n            value: Its source record valu"
    "e.\n            unit: Its source record value.\n            height: "
    "Its typed source quantity.\n            width: Its typed source quan"
    "tity.\n            text: Its source record value.\n            h_off"
    "set: Its typed source quantity.\n            pitch: Its typed source"
    " quantity.\n            roll: Its typed source quantity.\n          "
    "  value_present: Its source record value.\n\n        Returns:\n     "
    "       A record with unchanged source precision and layout.\n\n     "
    "   Raises:\n            Error: If a quantity is not finite or anothe"
    'r field is invalid.\n        """\n        self = Signal.from_si('
    "\n            road_id,\n            signal_id,\n            s.value,"
    "\n            t.value,\n            name,\n            dynamic,\n   "
    "         orientation,\n            z_offset.value,\n            coun"
    "try,\n            type,\n            subtype,\n            value,\n "
    "           unit,\n            height.value,\n            width.value"
    ",\n            text,\n            h_offset.value,\n            pitch"
    ".value,\n            roll.value,\n            value_present,\n      "
    "  )\n\n    @staticmethod\n    def from_si(\n        road_id: RoadId,"
    "\n        signal_id: SignalId,\n        s: Float64,\n        t: Floa"
    "t64,\n        name: String,\n        dynamic: String,\n        orien"
    "tation: String,\n        z_offset: Float64,\n        country: String"
    ",\n        type: String,\n        subtype: String,\n        value: F"
    "loat64,\n        unit: String,\n        height: Float64,\n        wi"
    "dth: Float64,\n        text: String,\n        h_offset: Float64,\n  "
    "      pitch: Float64,\n        roll: Float64,\n        value_present"
    ': Bool = True,\n    ) raises -> Signal:\n        """Explicit sour'
    "ce-unit compatibility adapter. Create a signal from a file's `signal"
    "`.\n\n        Args:\n            road_id: The road it stands on.\n  "
    "          signal_id: Its id.\n            s: Meters along the road."
    "\n            t: Meters to the left of the reference line.\n        "
    '    name: Its name.\n            dynamic: "yes" for a signal that '
    'changes, such as a light.\n            orientation: "+", "-" or '
    "anything else for both.\n            z_offset: Meters up from the ro"
    "ad.\n            country: The code of the country whose catalog it i"
    's from.\n            type: Its type in that catalog, such as "206"'
    ".\n            subtype: Its subtype.\n            value: Its value, "
    "such as a speed.\n            unit: The unit of the value.\n        "
    "    height: Its height, in meters.\n            width: Its width, in"
    " meters.\n            text: Its text.\n            h_offset: The tur"
    "n from the road's heading, in radians.\n            pitch: Its pitch"
    ", in radians.\n            roll: Its roll, in radians.\n            "
    "value_present: Whether the file supplied a numeric value.\n\n       "
    " Returns:\n            The new Signal record with the supplied sourc"
    "e fields.\n\n        Raises:\n            Error: If an id is not val"
    'id.\n        """\n        _ = _nonnegative_si(s)\n        _ = _fi'
    "nite_si(t)\n        _ = _finite_si(z_offset)\n        _ = _nonnegati"
    "ve_si(height)\n        _ = _nonnegative_si(width)\n        _ = _fini"
    "te_si(h_offset)\n        _ = _finite_si(pitch)\n        _ = _finite_"
    "si(roll)\n        return Signal(\n            _RAW_SI,\n            "
    "road_id,\n            signal_id,\n            s,\n            t,\n  "
    "          name,\n            dynamic,\n            orientation,\n   "
    "         z_offset,\n            country,\n            type,\n       "
    "     subtype,\n            value,\n            unit,\n            he"
    "ight,\n            width,\n            text,\n            h_offset,"
    "\n            pitch,\n            roll,\n            value_present,"
    "\n        )\n\n    @staticmethod\n    def _from_si(\n        road_id"
    ": RoadId,\n        signal_id: SignalId,\n        s: Float64,\n      "
    "  t: Float64,\n        name: String,\n        dynamic: String,\n    "
    "    orientation: String,\n        z_offset: Float64,\n        countr"
    "y: String,\n        type: String,\n        subtype: String,\n       "
    " value: Float64,\n        unit: String,\n        height: Float64,\n "
    "       width: Float64,\n        text: String,\n        h_offset: Flo"
    "at64,\n        pitch: Float64,\n        roll: Float64,\n        valu"
    'e_present: Bool = True,\n    ) raises -> Signal:\n        """Expl'
    "icit source-unit compatibility adapter. Create a signal from a file'"
    "s `signal`.\n\n        Args:\n            road_id: The road it stand"
    "s on.\n            signal_id: Its id.\n            s: Meters along t"
    "he road.\n            t: Meters to the left of the reference line.\n"
    '            name: Its name.\n            dynamic: "yes" for a sign'
    'al that changes, such as a light.\n            orientation: "+", '
    '"-" or anything else for both.\n            z_offset: Meters up fr'
    "om the road.\n            country: The code of the country whose cat"
    "alog it is from.\n            type: Its type in that catalog, such a"
    's "206".\n            subtype: Its subtype.\n            value: It'
    "s value, such as a speed.\n            unit: The unit of the value."
    "\n            height: Its height, in meters.\n            width: Its"
    " width, in meters.\n            text: Its text.\n            h_offse"
    "t: The turn from the road's heading, in radians.\n            pitch:"
    " Its pitch, in radians.\n            roll: Its roll, in radians.\n  "
    "          value_present: Whether the file supplied a numeric value."
    "\n\n        Raises:\n            Error: If an id is not valid.\n    "
    '    """\n        return Signal(\n            _RAW_SI,\n          '
    "  road_id,\n            signal_id,\n            s,\n            t,\n"
    "            name,\n            dynamic,\n            orientation,\n "
    "           z_offset,\n            country,\n            type,\n     "
    "       subtype,\n            value,\n            unit,\n            "
    "height,\n            width,\n            text,\n            h_offset"
    ",\n            pitch,\n            roll,\n            value_present,"
    "\n        )\n\n    def __init__(\n        out self,\n        raw: _R"
    "awSI,\n        road_id: RoadId,\n        signal_id: SignalId,\n     "
    "   s: Float64,\n        t: Float64,\n        name: String,\n        "
    "dynamic: String,\n        orientation: String,\n"
)

comptime _MAP_OLD_6 = (
    "\n    def __init__(\n        out self,\n        road_id: RoadId,\n  "
    "      signal_id: SignalId,\n        s: Float64,\n        t: Float64,"
    "\n        name: String,\n        dynamic: String,\n        orientati"
    "on: String,\n"
)

comptime _MAP_LIVE_7 = (
    '        value_present: Bool = True,\n    ) raises:\n        """Cr'
    "eate a signal from a file's `signal`.\n\n        Args:\n            "
    "raw: The private raw-storage construction capability.\n            r"
    "oad_id: The road it stands on.\n            signal_id: Its id.\n    "
    "        s: Meters along the road.\n            t: Meters to the left"
    " of the reference line.\n            name: Its name.\n"
)

comptime _MAP_OLD_7 = (
    '        value_present: Bool = True,\n    ) raises:\n        """Cr'
    "eate a signal from a file's `signal`.\n\n        Args:\n            "
    "road_id: The road it stands on.\n            signal_id: Its id.\n   "
    "         s: Meters along the road.\n            t: Meters to the lef"
    "t of the reference line.\n            name: Its name.\n"
)

comptime _MAP_LIVE_8 = (
    '        Returns:\n            Positive for "+", negative for "-"'
    ', both otherwise.\n        """\n        return signal_orientation'
    "_of(self.orientation_text)\n\n    def s_quantity(self) raises -> Len"
    'gth64:\n        """Read the checked typed view of the raw s compa'
    "tibility field.\n\n        Returns:\n            The same finite Flo"
    "at64 value with its unit.\n\n        Raises:\n            Error: If "
    'the mutable raw value is not finite.\n        """\n        return'
    " Length64(_nonnegative_si(self.s))\n\n    def t_quantity(self) raise"
    's -> Length64:\n        """Read the checked typed view of the raw'
    " t compatibility field.\n\n        Returns:\n            The same fi"
    "nite Float64 value with its unit.\n\n        Raises:\n            Er"
    'ror: If the mutable raw value is not finite.\n        """\n      '
    "  return Length64(_finite_si(self.t))\n\n    def z_offset_quantity(s"
    'elf) raises -> Length64:\n        """Read the checked typed view '
    "of the raw z_offset compatibility field.\n\n        Returns:\n      "
    "      The same finite Float64 value with its unit.\n\n        Raises"
    ":\n            Error: If the mutable raw value is not finite.\n     "
    '   """\n        return Length64(_finite_si(self.z_offset))\n\n   '
    ' def height_quantity(self) raises -> Length64:\n        """Read t'
    "he checked typed view of the raw height compatibility field.\n\n    "
    "    Returns:\n            The same finite Float64 value with its uni"
    "t.\n\n        Raises:\n            Error: If the mutable raw value i"
    's not finite.\n        """\n        return Length64(_nonnegative_'
    "si(self.height))\n\n    def width_quantity(self) raises -> Length64:"
    '\n        """Read the checked typed view of the raw width compati'
    "bility field.\n\n        Returns:\n            The same finite Float"
    "64 value with its unit.\n\n        Raises:\n            Error: If th"
    'e mutable raw value is not finite.\n        """\n        return L'
    "ength64(_nonnegative_si(self.width))\n\n    def h_offset_quantity(se"
    'lf) raises -> Angle64:\n        """Read the checked typed view of'
    " the raw h_offset compatibility field.\n\n        Returns:\n        "
    "    The same finite Float64 value with its unit.\n\n        Raises:"
    "\n            Error: If the mutable raw value is not finite.\n      "
    '  """\n        return Angle64(_finite_si(self.h_offset))\n\n    d'
    'ef pitch_quantity(self) raises -> Angle64:\n        """Read the c'
    "hecked typed view of the raw pitch compatibility field.\n\n        R"
    "eturns:\n            The same finite Float64 value with its unit.\n"
    "\n        Raises:\n            Error: If the mutable raw value is no"
    't finite.\n        """\n        return Angle64(_finite_si(self.pi'
    'tch))\n\n    def roll_quantity(self) raises -> Angle64:\n        "'
    '""Read the checked typed view of the raw roll compatibility field.'
    "\n\n        Returns:\n            The same finite Float64 value with"
    " its unit.\n\n        Raises:\n            Error: If the mutable raw"
    ' value is not finite.\n        """\n        return Angle64(_finit'
    'e_si(self.roll))\n\n\nstruct Controller(Copyable, Movable):\n    "'
    '""A group of signals that change together, `road/Controller`.""'
    '"\n\n    var id: ControllerId\n'
)

comptime _MAP_OLD_8 = (
    '        Returns:\n            Positive for "+", negative for "-"'
    ', both otherwise.\n        """\n        return signal_orientation'
    "_of(self.orientation_text)\n\n\nstruct Controller(Copyable, Movable)"
    ':\n    """A group of signals that change together, `road/Controll'
    'er`."""\n\n    var id: ControllerId\n'
)

comptime _MAP_LIVE_9 = (
    "        self.width = 0.0\n        self.heading = 0.0\n        self.p"
    "itch = 0.0\n        self.roll = 0.0\n\n    def s_quantity(self) rais"
    'es -> Length64:\n        """Read the checked typed view of the ra'
    "w s compatibility field.\n\n        Returns:\n            The same f"
    "inite Float64 value with its unit.\n\n        Raises:\n            E"
    'rror: If the mutable raw value is not finite.\n        """\n     '
    "   return Length64(_nonnegative_si(self.s))\n\n    def t_quantity(se"
    'lf) raises -> Length64:\n        """Read the checked typed view o'
    "f the raw t compatibility field.\n\n        Returns:\n            Th"
    "e same finite Float64 value with its unit.\n\n        Raises:\n     "
    '       Error: If the mutable raw value is not finite.\n        ""'
    '"\n        return Length64(_finite_si(self.t))\n\n    def z_offset_'
    'quantity(self) raises -> Length64:\n        """Read the checked t'
    "yped view of the raw z_offset compatibility field.\n\n        Return"
    "s:\n            The same finite Float64 value with its unit.\n\n    "
    "    Raises:\n            Error: If the mutable raw value is not fini"
    'te.\n        """\n        return Length64(_finite_si(self.z_offse'
    "t))\n\n    def valid_length_quantity(self) raises -> Length64:\n    "
    '    """Read the checked typed view of the raw valid_length compat'
    "ibility field.\n\n        Returns:\n            The same finite Floa"
    "t64 value with its unit.\n\n        Raises:\n            Error: If t"
    'he mutable raw value is not finite.\n        """\n        return '
    "Length64(_nonnegative_si(self.valid_length))\n\n    def length_quant"
    'ity(self) raises -> Length64:\n        """Read the checked typed '
    "view of the raw length compatibility field.\n\n        Returns:\n   "
    "         The same finite Float64 value with its unit.\n\n        Rai"
    "ses:\n            Error: If the mutable raw value is not finite.\n  "
    '      """\n        return Length64(_nonnegative_si(self.length))'
    '\n\n    def width_quantity(self) raises -> Length64:\n        """'
    "Read the checked typed view of the raw width compatibility field.\n"
    "\n        Returns:\n            The same finite Float64 value with i"
    "ts unit.\n\n        Raises:\n            Error: If the mutable raw v"
    'alue is not finite.\n        """\n        return Length64(_nonneg'
    "ative_si(self.width))\n\n    def heading_quantity(self) raises -> An"
    'gle64:\n        """Read the checked typed view of the raw heading'
    " compatibility field.\n\n        Returns:\n            The same fini"
    "te Float64 value with its unit.\n\n        Raises:\n            Erro"
    'r: If the mutable raw value is not finite.\n        """\n        '
    "return Angle64(_finite_si(self.heading))\n\n    def pitch_quantity(s"
    'elf) raises -> Angle64:\n        """Read the checked typed view o'
    "f the raw pitch compatibility field.\n\n        Returns:\n          "
    "  The same finite Float64 value with its unit.\n\n        Raises:\n "
    "           Error: If the mutable raw value is not finite.\n        "
    '"""\n        return Angle64(_finite_si(self.pitch))\n\n    def ro'
    'll_quantity(self) raises -> Angle64:\n        """Read the checked'
    " typed view of the raw roll compatibility field.\n\n        Returns:"
    "\n            The same finite Float64 value with its unit.\n\n      "
    "  Raises:\n            Error: If the mutable raw value is not finite"
    '.\n        """\n        return Angle64(_finite_si(self.roll))\n\n'
    "\n# CARLA's `SignalType` catalog: the German StVO numbers OpenDRIVE "
    'uses.\ncomptime SIGNAL_DANGER = "101"\ncomptime SIGNAL_LANES_MERGI'
    'NG = "121"\ncomptime SIGNAL_CAUTION_PEDESTRIAN = "133"\n'
)

comptime _MAP_OLD_9 = (
    "        self.width = 0.0\n        self.heading = 0.0\n        self.p"
    "itch = 0.0\n        self.roll = 0.0\n\n\n# CARLA's `SignalType` cata"
    "log: the German StVO numbers OpenDRIVE uses.\ncomptime SIGNAL_DANGER"
    ' = "101"\ncomptime SIGNAL_LANES_MERGING = "121"\ncomptime SIGNAL'
    '_CAUTION_PEDESTRIAN = "133"\n'
)

comptime _MAP_LIVE_10 = (
    '        The rolling surface plus the bumps.\n    """\n    return '
    "z_pos_in_deformation(x, y) + bump_deformation(x, y)\n\n\n# --- query"
    " results -----------------------------------------------------------"
    '-\n\n\nstruct SignalSearchData(Copyable, Movable):\n    """A sign'
    'al found ahead of a waypoint, `Map::SignalSearchData`."""\n\n    '
    "var signal: RoadInfoSignal\n    # The waypoint where the signal appl"
    "ies.\n    var waypoint: Waypoint\n    # Meters from the search's sta"
    "rt.\n    var accumulated_s: Float64\n\n    def __init__(\n        ou"
    "t self,\n        signal: RoadInfoSignal,\n        waypoint: Waypoint"
    ',\n        accumulated_s: Length64,\n    ) raises:\n        """Cr'
    "eate a checked typed record without changing scalar storage.\n\n    "
    "    Args:\n            signal: Its source record value.\n           "
    " waypoint: Its source record value.\n            accumulated_s: Its "
    "typed source quantity.\n\n        Returns:\n            A record wit"
    "h unchanged source precision and layout.\n\n        Raises:\n       "
    "     Error: If a quantity is not finite or another field is invalid."
    '\n        """\n        self = SignalSearchData.from_si(signal, wa'
    "ypoint, accumulated_s.value)\n\n    @staticmethod\n    def from_si("
    "\n        signal: RoadInfoSignal,\n        waypoint: Waypoint,\n    "
    "    accumulated_s: Float64,\n    ) raises -> SignalSearchData:\n    "
    '    """Explicit source-unit compatibility adapter. Create a resul'
    "t.\n\n        Args:\n            signal: The signal reference found."
    "\n            waypoint: Where it applies.\n            accumulated_s"
    ": How far from the start, in meters.\n\n        Returns:\n          "
    "  The new SignalSearchData record with the supplied source fields.\n"
    "\n        Raises:\n            Error: If the accumulated distance is"
    ' nonfinite or negative.\n        """\n        _ = _nonnegative_si'
    "(accumulated_s)\n        return SignalSearchData(_RAW_SI, signal, wa"
    "ypoint, accumulated_s)\n\n    @staticmethod\n    def _from_si(\n    "
    "    signal: RoadInfoSignal,\n        waypoint: Waypoint,\n        ac"
    'cumulated_s: Float64,\n    ) -> SignalSearchData:\n        """Exp'
    "licit source-unit compatibility adapter. Create a result.\n\n       "
    " Args:\n            signal: The signal reference found.\n           "
    " waypoint: Where it applies.\n            accumulated_s: How far fro"
    'm the start, in meters.\n        """\n        return SignalSearch'
    "Data(_RAW_SI, signal, waypoint, accumulated_s)\n\n    def __init__("
    "\n        out self,\n        raw: _RawSI,\n        signal: RoadInfoS"
    "ignal,\n        waypoint: Waypoint,\n        accumulated_s: Float64,"
    '\n    ):\n        """Create a result.\n\n        Args:\n         '
    "   raw: The private raw-storage construction capability.\n          "
    "  signal: The signal reference found.\n            waypoint: Where i"
    "t applies.\n            accumulated_s: How far from the start, in me"
    'ters."""\n        self.signal = signal.copy()\n        self.waypo'
    "int = waypoint\n        self.accumulated_s = accumulated_s\n\n    de"
    'f accumulated_s_quantity(self) raises -> Length64:\n        """Re'
    "ad the checked typed view of the raw accumulated_s compatibility fie"
    "ld.\n\n        Returns:\n            The same finite Float64 value w"
    "ith its unit.\n\n        Raises:\n            Error: If the mutable "
    'raw value is not finite.\n        """\n        return Length64(_n'
    "onnegative_si(self.accumulated_s))\n\n\nstruct Landmark(Copyable, Mo"
    'vable):\n    """A signal reference seen from a waypoint, `client/'
    "Landmark`.\n\n    `Map.signal(landmark.reference.signal_id)` gives t"
    "he signal's fields.\n"
)

comptime _MAP_OLD_10 = (
    '        The rolling surface plus the bumps.\n    """\n    return '
    "z_pos_in_deformation(x, y) + bump_deformation(x, y)\n\n\n# --- query"
    " results -----------------------------------------------------------"
    '-\n\n\nstruct SignalSearchData(Copyable, Movable):\n    """A sign'
    'al found ahead of a waypoint, `Map::SignalSearchData`."""\n\n    '
    "var signal: RoadInfoSignal\n    # The waypoint where the signal appl"
    "ies.\n    var waypoint: Waypoint\n    # Meters from the search's sta"
    "rt.\n    var accumulated_s: Float64\n\n    def __init__(\n        ou"
    "t self,\n        signal: RoadInfoSignal,\n        waypoint: Waypoint"
    ',\n        accumulated_s: Float64,\n    ):\n        """Create a r'
    "esult.\n\n        Args:\n            signal: The signal reference fo"
    "und.\n            waypoint: Where it applies.\n            accumulat"
    'ed_s: How far from the start, in meters.\n        """\n        se'
    "lf.signal = signal.copy()\n        self.waypoint = waypoint\n       "
    " self.accumulated_s = accumulated_s\n\n\nstruct Landmark(Copyable, M"
    'ovable):\n    """A signal reference seen from a waypoint, `client'
    "/Landmark`.\n\n    `Map.signal(landmark.reference.signal_id)` gives "
    "the signal's fields.\n"
)

comptime _MAP_LIVE_11 = (
    "    # Meters from the search's start.\n    var distance: Float64\n\n"
    "    def __init__(\n        out self,\n        waypoint: Optional[Way"
    "point],\n        reference: RoadInfoSignal,\n        distance: Lengt"
    'h64,\n    ) raises:\n        """Create a checked typed record wit'
    "hout changing scalar storage.\n\n        Args:\n            waypoint"
    ": Its source record value.\n            reference: Its source record"
    " value.\n            distance: Its typed source quantity.\n\n       "
    " Returns:\n            A record with unchanged source precision and "
    "layout.\n\n        Raises:\n            Error: If a quantity is not "
    'finite or another field is invalid.\n        """\n        self = '
    "Landmark.from_si(waypoint, reference, distance.value)\n\n    @static"
    "method\n    def from_si(\n        waypoint: Optional[Waypoint],\n   "
    "     reference: RoadInfoSignal,\n        distance: Float64,\n    ) r"
    'aises -> Landmark:\n        """Explicit source-unit compatibility'
    " adapter. Create a landmark.\n\n        Args:\n            waypoint:"
    " Where it applies, or None.\n            reference: The signal refer"
    "ence.\n            distance: Meters from the search's start.\n\n    "
    "    Returns:\n            The new Landmark record with the supplied "
    "source fields.\n\n        Raises:\n            Error: If the distanc"
    'e is nonfinite or negative.\n        """\n        _ = _nonnegativ'
    "e_si(distance)\n        return Landmark(_RAW_SI, waypoint, reference"
    ", distance)\n\n    @staticmethod\n    def _from_si(\n        waypoin"
    "t: Optional[Waypoint],\n        reference: RoadInfoSignal,\n        "
    'distance: Float64,\n    ) -> Landmark:\n        """Explicit sourc'
    "e-unit compatibility adapter. Create a landmark.\n\n        Args:\n "
    "           waypoint: Where it applies, or None.\n            referen"
    "ce: The signal reference.\n            distance: Meters from the sea"
    'rch\'s start.\n        """\n        return Landmark(_RAW_SI, waypo'
    "int, reference, distance)\n\n    def __init__(\n        out self,\n "
    "       raw: _RawSI,\n        waypoint: Optional[Waypoint],\n        "
    "reference: RoadInfoSignal,\n        distance: Float64,\n    ):\n    "
    '    """Create a landmark.\n\n        Args:\n            raw: The '
    "private raw-storage construction capability.\n            waypoint: "
    "Where it applies, or None.\n            reference: The signal refere"
    'nce.\n            distance: Meters from the search\'s start."""\n '
    "       self.waypoint = waypoint\n        self.reference = reference."
    "copy()\n        self.distance = distance\n\n    def distance_quantit"
    'y(self) raises -> Length64:\n        """Read the checked typed vi'
    "ew of the raw distance compatibility field.\n\n        Returns:\n   "
    "         The same finite Float64 value with its unit.\n\n        Rai"
    "ses:\n            Error: If the mutable raw value is not finite.\n  "
    '      """\n        return Length64(_nonnegative_si(self.distance)'
    ")\n\n\ndef _has_uniform_plan_classification(\n    bounds: Tuple[_Int"
    "erval, _Interval, _Interval],\n    width: Float64,\n    location: Ve"
    "ctor3,\n"
)

comptime _MAP_OLD_11 = (
    "    # Meters from the search's start.\n    var distance: Float64\n\n"
    "    def __init__(\n        out self,\n        waypoint: Optional[Way"
    "point],\n        reference: RoadInfoSignal,\n        distance: Float"
    '64,\n    ):\n        """Create a landmark.\n\n        Args:\n    '
    "        waypoint: Where it applies, or None.\n            reference:"
    " The signal reference.\n            distance: Meters from the search"
    '\'s start.\n        """\n        self.waypoint = waypoint\n       '
    " self.reference = reference.copy()\n        self.distance = distance"
    "\n\n\ndef _has_uniform_plan_classification(\n    bounds: Tuple[_Inte"
    "rval, _Interval, _Interval],\n    width: Float64,\n    location: Vec"
    "tor3,\n"
)

comptime _MAP_LIVE_12 = (
    "    var first: Waypoint\n    var second: Waypoint\n    var bounds: T"
    "uple[_Interval, _Interval, _Interval]\n    # -1 means the optional c"
    "onstruction proof is absent.\n    var cover_index: Int\n    # This s"
    "egment's certified full-curve distance to its stored chord. The\n   "
    " # map's `_curve_deviation` is the maximum over every segment (#685)"
    ".\n    var deviation: Float64\n\n\n@fieldwise_init\nstruct _CarlaSeg"
    "ment(ImplicitlyCopyable):\n    # One piece of CARLA's `Map::CreateRt"
    "ree` partition, before refinement.\n"
)

comptime _MAP_OLD_12 = (
    "    var first: Waypoint\n    var second: Waypoint\n    var bounds: T"
    "uple[_Interval, _Interval, _Interval]\n    # -1 means the optional c"
    "onstruction proof is absent.\n    var cover_index: Int\n\n\n@fieldwi"
    "se_init\nstruct _CarlaSegment(ImplicitlyCopyable):\n    # One piece "
    "of CARLA's `Map::CreateRtree` partition, before refinement.\n"
)

comptime _MAP_LIVE_13 = (
    "    return sqrt(ex * ex + ey * ey)\n\n\ndef segment_distance_2d(\n  "
    "  a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3\n) raises -> Le"
    'ngth64:\n    """Return the checked physical plan distance between'
    " two segments.\n\n    Args:\n        a1: The first segment start in "
    "meters.\n        a2: The first segment end in meters.\n        b1: T"
    "he second segment start in meters.\n        b2: The second segment e"
    "nd in meters.\n\n    Returns:\n        Their minimum plan distance; "
    "z is ignored.\n\n    Raises:\n        Error: If a plan coordinate or"
    ' the result is not finite.\n    """\n    return Length64(segment_'
    "distance_2d_meters(a1, a2, b1, b2))\n\n\ndef segment_distance_2d_met"
    "ers(\n    a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3\n) rais"
    'es -> Float64:\n    """Explicit checked meter adapter for the unc'
    "hanged segment kernel.\n\n    Args:\n        a1: The first segment s"
    "tart.\n        a2: The first segment end.\n        b1: The second se"
    "gment start.\n        b2: The second segment end.\n\n    Returns:\n "
    "       The raw distance in meters.\n\n    Raises:\n        Error: If"
    ' a plan coordinate or result is not finite.\n    """\n    for poi'
    "nt in [a1, a2, b1, b2]:  # pragma: no branch\n        _ = _finite_si"
    "(Float64(point.x))\n        _ = _finite_si(Float64(point.y))\n    re"
    "turn _nonnegative_si(_segment_distance_2d_si(a1, a2, b1, b2))\n\n\nd"
    "ef _segment_distance_2d_si(\n    a1: Vector3, a2: Vector3, b1: Vecto"
    'r3, b2: Vector3\n) -> Float64:\n    """Return the plan distance b'
    "etween two segments, as Boost's.\n\n    Args:\n        a1: The first"
    " segment's start.\n"
)

comptime _MAP_OLD_13 = (
    "    return sqrt(ex * ex + ey * ey)\n\n\ndef segment_distance_2d(\n  "
    "  a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3\n) -> Float64:"
    '\n    """Return the plan distance between two segments, as Boost\''
    "s.\n\n    Args:\n        a1: The first segment's start.\n"
)

comptime _MAP_LIVE_14 = (
    "            _point_segment_2d(bx, by, cx, cy, dx, dy),\n        ),\n"
    "    )\n\n\ndef _chord_station_delta(\n    location: Vector3, start: "
    "Vector3, end: Vector3, span: Float64\n) -> Float64:\n    # The defau"
    "lt query's step along the lane, in road s. CARLA steps by the\n    #"
    " plan distance along the chord (`Math::DistanceSegmentToPoint`). Tha"
    "t\n    # distance is not road s when a lane offset, a lane width or "
    "a curve\n    # changes the lane's plan speed (#302). This uses the f"
    "oot's plan\n    # fraction of the chord times the chord's road-s spa"
    "n instead. Float64\n    # holds the square of any finite Float32 cho"
    "rd. A nonfinite chord gives\n    # NaN, which the callers refuse or "
    "return as before.\n    var dx = Float64(end.x) - Float64(start.x)\n "
    "   var dy = Float64(end.y) - Float64(start.y)\n    var l2 = dx * dx "
    "+ dy * dy\n    if l2 == 0.0:\n        return 0.0\n    var px = Float"
    "64(location.x) - Float64(start.x)\n    var py = Float64(location.y) "
    "- Float64(start.y)\n    var t = (px * dx + py * dy) / l2\n    # Clam"
    "p without min and max, so that a NaN fraction stays NaN.\n    if t <"
    " 0.0:\n        t = 0.0\n    elif t > 1.0:\n        t = 1.0\n    retu"
    "rn t * span\n\n\n# --- the map -------------------------------------"
    "-----------------------------\n\n\ndef _map_locate_with_work(\n    r"
    "oads: List[Road],\n    index: Dict[Int, Int],\n    waypoint: Waypoin"
    "t,\n    mut work: _MapBuildWork,\n) raises -> Tuple[Int, Int, Int]:"
    "\n    # Lookup is metered by identity only. Signed finite stations c"
    "an remain\n    # in private graph/build work until its contextual re"
    "fusal. Public\n    # station guards belong to their checked entry po"
    "ints.\n    work.step()\n    if not waypoint.road_id.is_valid():\n   "
    '     raise Error("Road id is not valid")\n    var found = index.ge'
    "t(waypoint.road_id.value)\n    if not found:\n"
)

comptime _MAP_OLD_14 = (
    "            _point_segment_2d(bx, by, cx, cy, dx, dy),\n        ),\n"
    "    )\n\n\n# --- the map -------------------------------------------"
    "-----------------------\n\n\ndef _map_locate_with_work(\n    roads: "
    "List[Road],\n    index: Dict[Int, Int],\n    waypoint: Waypoint,\n  "
    "  mut work: _MapBuildWork,\n) raises -> Tuple[Int, Int, Int]:\n    w"
    "ork.step()\n    if not waypoint.road_id.is_valid():\n        raise E"
    'rror("Road id is not valid")\n    var found = index.get(waypoint.r'
    "oad_id.value)\n    if not found:\n"
)

comptime _MAP_LIVE_15 = (
    "    if not _seed_exact_interval(\n        _Interval(low, high)\n    "
    ") or not _endpoint_in_exact_range(origin):\n        return False\n  "
    "  var d = _stored_difference(_Jet.variable(low, high), _Jet.constant"
    "(origin))\n    if not _seed_exact_interval(d.value) or not d.error <"
    " 1.0:\n        return False\n    if not isfinite(geometry.length) or"
    " geometry.length <= 0.0:\n        return False\n    var rounded = d."
    "rounded_value()\n    if rounded.low <= 0.0 or rounded.high >= geomet"
    "ry.length:\n        return False\n    var k0 = geometry.curvature_st"
    "art\n    var rate = (geometry.curvature_end - k0) / geometry.length"
    "\n    if not _endpoint_in_exact_range(k0) or not _endpoint_in_exact_"
    "range(rate):\n        return False\n"
)

comptime _MAP_OLD_15 = (
    "    if not _seed_exact_interval(\n        _Interval(low, high)\n    "
    ") or not _endpoint_in_exact_range(origin):\n        return False\n  "
    "  var d = _stored_difference(_Jet.variable(low, high), _Jet.constant"
    "(origin))\n    if not _seed_exact_interval(d.value) or not (\n      "
    "  0.0 <= d.error and d.error < 1.0\n    ):\n        return False\n  "
    "  if not isfinite(geometry.length) or geometry.length <= 0.0:\n     "
    "   return False\n    var rounded = d.rounded_value()\n    if (\n    "
    "    not rounded.is_finite()\n        or rounded.low <= 0.0\n        "
    "or rounded.high >= geometry.length\n    ):\n        return False\n  "
    "  var k0 = geometry.curvature_start\n    var rate = (geometry.curvat"
    "ure_end - k0) / geometry.length\n    if not _endpoint_in_exact_range"
    "(k0) or not _endpoint_in_exact_range(rate):\n        return False\n"
)

comptime _MAP_LIVE_16 = (
    "        proof_nodes < 0\n        or proof_nodes > 5\n        or foll"
    "owup_steps < 0\n        or winner_reference <= 0\n        or target_"
    "reference <= 0\n        or target_cells < 0\n        or target_cells"
    " > 16372\n    ):\n        return False\n    var winner_followup = mi"
    "n(len(winner.cells), 16373) + 12\n    var target_followup = target_c"
    "ells + 12\n    var seed_nodes = proof_nodes + 85\n    if (\n        "
    "winner_followup > winner_cap - winner.nodes\n        or seed_nodes >"
    " winner_cap - winner.nodes - winner_followup\n"
)

comptime _MAP_OLD_16 = (
    "        proof_nodes < 0\n        or proof_nodes > 5\n        or foll"
    "owup_steps < 0\n        or winner_reference <= 0\n        or target_"
    "reference <= 0\n        or len(winner.cells) > 16372\n        or tar"
    "get_cells < 0\n        or target_cells > 16372\n    ):\n        retu"
    "rn False\n    var winner_followup = len(winner.cells) + 12\n    var "
    "target_followup = target_cells + 12\n    var seed_nodes = proof_node"
    "s + 85\n    if (\n        winner_followup > winner_cap - winner.node"
    "s\n        or seed_nodes > winner_cap - winner.nodes - winner_follow"
    "up\n"
)

comptime _MAP_LIVE_17 = (
    "    if winner_reference > winner_terms // winner_units:\n        ret"
    "urn False\n    if target_reference > target_terms // 50:\n        re"
    "turn False\n    var terms_left = work.policy.max_terms - work.terms"
    "\n    terms_left -= winner_units * winner_reference\n    return targ"
    "et_reference <= terms_left // 50\n\n\ndef _winner_seed_update_score("
    "\n    point: Array[Float64, 3],\n    incumbent: Array[Float64, 3],\n"
    "    query: Array[Float64, 3],\n    scale: Float64,\n) raises -> Tupl"
    "e[Bool, Float64]:\n    # Borrowed points; the caller supplies a posi"
    "tive finite scale and an\n    # established FP environment. The seco"
    "nd result is unusable on refusal.\n    if _wide_point_order(point, i"
    "ncumbent, query) < 0:\n        var score = _refinement_square[3](poi"
    "nt, query, scale)\n        if not score.is_finite():\n            re"
    "turn (False, 0.0)\n        return (True, score.high)\n    return (Fa"
    "lse, 0.0)\n\n\ndef _try_winner_seed(\n    road: Road,\n    section: "
    "Int,\n    lane: Int,\n    low: Float64,\n"
)

comptime _MAP_OLD_17 = (
    "    if winner_reference > winner_terms // winner_units:\n        ret"
    "urn False\n    if target_reference > target_terms // 50:\n        re"
    "turn False\n    var terms_left = work.policy.max_terms - work.terms"
    "\n    if winner_reference > terms_left // winner_units:\n        ret"
    "urn False\n    terms_left -= winner_units * winner_reference\n    re"
    "turn target_reference <= terms_left // 50\n\n\ndef _try_winner_seed("
    "\n    road: Road,\n    section: Int,\n    lane: Int,\n    low: Float"
    "64,\n"
)

comptime _MAP_LIVE_18 = (
    "        certificate.scale,\n    )\n    work.charge(1, reference, nod"
    "e_cost)\n    certificate.nodes += 1\n    certificate.terms += refere"
    "nce\n    var center = _expansion_distance_jet(\n        road, sectio"
    "n, lane, original_s, location, certificate.scale\n    )\n    if not "
    "center.first.is_finite():\n        return False\n    if not domain.f"
    "irst.is_finite() or not domain.second.is_finite():\n        # Separa"
    "te admission preserves the two-setup smooth-root path.\n        # Ch"
    "arge every retry before its midpoint/containment/progress work.\n   "
    "     work._step(12)\n        if not _winner_seed_room(\n            "
    "work,\n"
)

comptime _MAP_OLD_18 = (
    "        certificate.scale,\n    )\n    work.charge(1, reference, nod"
    "e_cost)\n    certificate.nodes += 1\n    certificate.terms += refere"
    "nce\n    var center_reference = _reference_work(road, original_s, or"
    "iginal_s)\n    if center_reference <= 0 or center_reference > refere"
    "nce:\n        return False\n    var center = _expansion_distance_jet"
    "(\n        road, section, lane, original_s, location, certificate.sc"
    "ale\n    )\n    if not center.first.is_finite():\n        return Fal"
    "se\n    if not domain.first.is_finite() or not domain.second.is_fini"
    "te():\n        if min(work.max_total_steps, work.policy.max_steps) -"
    " work.steps < 12:\n            return False\n        # Separate admi"
    "ssion preserves the two-setup smooth-root path.\n        # Charge ev"
    "ery retry before its midpoint/containment/progress work.\n        wo"
    "rk._step(12)\n        if not _winner_seed_room(\n            work,\n"
)

comptime _MAP_LIVE_19 = (
    "            work.charge(1, reference, node_cost)\n            certif"
    "icate.nodes += 1\n            certificate.terms += reference\n      "
    "      var narrowed_low = band_low + 0.5 * (original_s - band_low)\n "
    "           var narrowed_high = original_s + 0.5 * (band_high - origi"
    "nal_s)\n            if narrowed_low >= narrowed_high or (\n         "
    "       narrowed_low == band_low and narrowed_high == band_high\n    "
    "        ):\n                return False\n            band_low = nar"
    "rowed_low\n            band_high = narrowed_high\n            domain"
    " = _scaled_point_distance_jet(\n                _lane_jet(road, sect"
    "ion, lane, band_low, band_high),\n                location,\n       "
    "         certificate.scale,\n            )\n    if not domain.first."
    "is_finite() or not domain.second.is_finite():\n        return False"
    "\n    var support = _minimizer_support(\n        domain, center, ori"
    "ginal_s, original_s, band_low, band_high\n    )\n    # Eight complet"
    "e dyadic levels give 255 proposals (possibly repeated\n    # endpoin"
    "ts when the stored-word span is tiny). Integer quotient and\n    # r"
    "emainder interpolation cannot overflow for positive finite words.\n "
    "   var first = bitcast[DType.uint64](support.low)\n    var span = bi"
    "tcast[DType.uint64](support.high) - first\n"
)

comptime _MAP_OLD_19 = (
    "            work.charge(1, reference, node_cost)\n            certif"
    "icate.nodes += 1\n            certificate.terms += reference\n      "
    "      var narrowed_low = band_low + 0.5 * (original_s - band_low)\n "
    "           var narrowed_high = original_s + 0.5 * (band_high - origi"
    "nal_s)\n            if (\n                not isfinite(narrowed_low)"
    "\n                or not isfinite(narrowed_high)\n                or"
    " narrowed_low > original_s\n                or narrowed_high < origi"
    "nal_s\n                or narrowed_low >= narrowed_high\n           "
    "     or (narrowed_low == band_low and narrowed_high == band_high)\n "
    "           ):\n                return False\n            band_low = "
    "narrowed_low\n            band_high = narrowed_high\n            var"
    " retry_reference = _reference_work(road, band_low, band_high)\n     "
    "       if retry_reference <= 0 or retry_reference > reference:\n    "
    "            return False\n            domain = _scaled_point_distanc"
    "e_jet(\n                _lane_jet(road, section, lane, band_low, ban"
    "d_high),\n                location,\n                certificate.sca"
    "le,\n            )\n    if not domain.first.is_finite() or not domai"
    "n.second.is_finite():\n        return False\n    var support = _mini"
    "mizer_support(\n        domain, center, original_s, original_s, band"
    "_low, band_high\n    )\n    if (\n        not support.is_finite()\n "
    "       or support.low <= 0.0\n        or support.high < support.low"
    "\n    ):\n        return False\n    # Eight complete dyadic levels g"
    "ive 255 proposals (possibly repeated\n    # endpoints when the store"
    "d-word span is tiny). Integer quotient and\n    # remainder interpol"
    "ation cannot overflow for positive finite words.\n    var first = bi"
    "tcast[DType.uint64](support.low)\n    var span = bitcast[DType.uint6"
    "4](support.high) - first\n"
)

comptime _MAP_LIVE_20 = (
    "    var improved = False\n    for level in range(8):\n        var de"
    "nominator = UInt64(1) << UInt64(level + 1)\n        var quotient = s"
    "pan // denominator\n        var remainder = span % denominator\n    "
    "    for at in range(1 << level):  # pragma: no branch\n            i"
    "f count % 3 == 0:\n                work.charge(1, 0, node_cost)\n   "
    "             certificate.nodes += 1\n            count += 1\n       "
    "     var numerator = UInt64(2 * at + 1)\n"
)

comptime _MAP_OLD_20 = (
    "    var improved = False\n    for level in range(8):\n        var de"
    "nominator = UInt64(1) << UInt64(level + 1)\n        var quotient = s"
    "pan // denominator\n        var remainder = span % denominator\n    "
    "    for at in range(1 << level):\n            if count % 3 == 0:\n  "
    "              work.charge(1, 0, node_cost)\n                certific"
    "ate.nodes += 1\n            count += 1\n            var numerator = "
    "UInt64(2 * at + 1)\n"
)

comptime _MAP_LIVE_21 = (
    "            )\n            var s = bitcast[DType.float64](word)\n   "
    "         # Debit actual quadrature before entering the unchanged com"
    "piled\n            # scalar wrapper. Failed evaluations retain both "
    "ledgers.\n            var point_work = _reference_work(road, s, s)\n"
    "            work.charge(0, point_work, node_cost)\n            certi"
    "ficate.terms += point_work\n            var checked_terms = 0\n     "
    "       var point = _checked_center(\n                road, section, "
    "lane, s, checked_terms, point_work\n            )\n            var u"
    "pdate = _winner_seed_update_score(\n                point, certifica"
    "te.point, query, certificate.scale\n            )\n            if up"
    "date[0]:\n                certificate.s = s\n                certifi"
    "cate.point = point^\n                certificate.upper = update[1]\n"
    "                improved = True\n    return improved\n\n\ndef _prefl"
    "ight_map_metadata(\n"
)

comptime _MAP_OLD_21 = (
    "            )\n            var s = bitcast[DType.float64](word)\n   "
    "         # Debit actual quadrature before entering the unchanged com"
    "piled\n            # scalar wrapper. Failed evaluations retain both "
    "ledgers.\n            var point_work = _reference_work(road, s, s)\n"
    "            if point_work <= 0 or point_work > reference:\n         "
    "       return improved\n            work.charge(0, point_work, node_"
    "cost)\n            certificate.terms += point_work\n            var "
    "checked_terms = 0\n            var point = _checked_center(\n       "
    "         road, section, lane, s, checked_terms, point_work\n        "
    "    )\n            if _wide_point_order(point, certificate.point, qu"
    "ery) < 0:\n                var score = _refinement_square[3](\n     "
    "               point, query, certificate.scale\n                )\n "
    "               if not score.is_finite():\n                    contin"
    "ue\n                certificate.s = s\n                certificate.p"
    "oint = point^\n                certificate.upper = score.high\n     "
    "           improved = True\n    return improved\n\n\ndef _preflight_"
    "map_metadata(\n"
)

comptime _MAP_LIVE_22 = (
    '            Error: If the map has no such road.\n        """\n   '
    "     return self.roads[self.road_index(id)]\n\n    def _locate(self,"
    " waypoint: Waypoint) raises -> Tuple[Int, Int, Int]:\n        _ = _n"
    "onnegative_si(waypoint.s)\n        var r = self.road_index(waypoint."
    "road_id)\n        var section = self.roads[r].section_index(waypoint"
    ".section_id)\n        var lane = self.roads[r].sections[section].lan"
    "e_index(waypoint.lane_id)\n        if lane < 0:\n            raise E"
    'rror("The section has no lane with that id")\n'
)

comptime _MAP_OLD_22 = (
    '            Error: If the map has no such road.\n        """\n   '
    "     return self.roads[self.road_index(id)]\n\n    def _locate(self,"
    " waypoint: Waypoint) raises -> Tuple[Int, Int, Int]:\n        var r "
    "= self.road_index(waypoint.road_id)\n        var section = self.road"
    "s[r].section_index(waypoint.section_id)\n        var lane = self.roa"
    "ds[r].sections[section].lane_index(waypoint.lane_id)\n        if lan"
    'e < 0:\n            raise Error("The section has no lane with that '
    'id")\n'
)

comptime _MAP_LIVE_23 = (
    '            raise Error("The section has no lane with that id")\n '
    "       return (r, section, lane)\n\n    def _key(self, key: LaneKey)"
    " raises -> Tuple[Int, Int, Int]:\n        return self._locate(\n    "
    "        Waypoint._from_si(key.road_id, key.section_id, key.lane_id, "
    "0.0)\n        )\n\n    def lane(\n        ref self, waypoint: Waypoi"
    "nt\n    ) raises -> ref[origin_of(self.roads[0].sections[0].lanes[0]"
    ")] Lane:\n"
)

comptime _MAP_OLD_23 = (
    '            raise Error("The section has no lane with that id")\n '
    "       return (r, section, lane)\n\n    def _key(self, key: LaneKey)"
    " raises -> Tuple[Int, Int, Int]:\n        return self._locate(\n    "
    "        Waypoint(key.road_id, key.section_id, key.lane_id, 0.0)\n   "
    "     )\n\n    def lane(\n        ref self, waypoint: Waypoint\n    )"
    " raises -> ref[origin_of(self.roads[0].sections[0].lanes[0])] Lane:"
    "\n"
)

comptime _MAP_LIVE_24 = (
    "\n    def _start_of_lane(self, road: Int, section: Int, lane: Int) -"
    "> Float64:\n        # `GetDistanceAtStartOfLane`.\n        ref r = s"
    "elf.roads[road]\n        var s = r.sections[section].s\n        var "
    "inset = min(10.0 * EPSILON, r._section_length_si(section) / 4.0)\n  "
    "      if r.is_positive_direction(r.sections[section].lanes[lane].id)"
    ":\n            return s + inset\n        return s + r._section_lengt"
    "h_si(section) - inset\n\n    def _end_of_lane(self, road: Int, secti"
    "on: Int, lane: Int) -> Float64:\n        # `GetDistanceAtEndOfLane`."
    "\n        ref r = self.roads[road]\n        var s = r.sections[secti"
    "on].s\n        var inset = min(10.0 * EPSILON, r._section_length_si("
    "section) / 4.0)\n        if not r.is_positive_direction(r.sections[s"
    "ection].lanes[lane].id):\n            return s + inset\n        retu"
    "rn s + r._section_length_si(section) - inset\n\n    def compute_tran"
    "sform(self, waypoint: Waypoint) raises -> CarlaTransform:\n        "
    '"""Return where a waypoint is, `Map::ComputeTransform`.\n\n      '
    "  Narrow the same canonical Float64 lane center used by nearest quer"
    "ies.\n"
)

comptime _MAP_OLD_24 = (
    "\n    def _start_of_lane(self, road: Int, section: Int, lane: Int) -"
    "> Float64:\n        # `GetDistanceAtStartOfLane`.\n        ref r = s"
    "elf.roads[road]\n        var s = r.sections[section].s\n        var "
    "inset = min(10.0 * EPSILON, r.section_length(section) / 4.0)\n      "
    "  if r.is_positive_direction(r.sections[section].lanes[lane].id):\n "
    "           return s + inset\n        return s + r.section_length(sec"
    "tion) - inset\n\n    def _end_of_lane(self, road: Int, section: Int,"
    " lane: Int) -> Float64:\n        # `GetDistanceAtEndOfLane`.\n      "
    "  ref r = self.roads[road]\n        var s = r.sections[section].s\n "
    "       var inset = min(10.0 * EPSILON, r.section_length(section) / 4"
    ".0)\n        if not r.is_positive_direction(r.sections[section].lane"
    "s[lane].id):\n            return s + inset\n        return s + r.sec"
    "tion_length(section) - inset\n\n    def compute_transform(self, wayp"
    'oint: Waypoint) raises -> CarlaTransform:\n        """Return wher'
    "e a waypoint is, `Map::ComputeTransform`.\n\n        Narrow the same"
    " canonical Float64 lane center used by nearest queries.\n"
)

comptime _MAP_LIVE_25 = (
    "        Raises:\n            Error: If the lane is not in the map, s"
    " is off the road, or a\n                SPIRAL uses an unsupported f"
    'loating-point mode.\n        """\n        var at = self._locate(w'
    "aypoint)\n        return self.roads[at[0]]._lane_transform_si(at[1],"
    " at[2], waypoint.s)\n\n    def lane_type(self, waypoint: Waypoint) r"
    'aises -> LaneType:\n        """Return a waypoint\'s lane type, `Ma'
    "p::GetLaneType`.\n\n        Args:\n"
)

comptime _MAP_OLD_25 = (
    "        Raises:\n            Error: If the lane is not in the map, s"
    " is off the road, or a\n                SPIRAL uses an unsupported f"
    'loating-point mode.\n        """\n        var at = self._locate(w'
    "aypoint)\n        return self.roads[at[0]].lane_transform(at[1], at["
    "2], waypoint.s)\n\n    def lane_type(self, waypoint: Waypoint) raise"
    's -> LaneType:\n        """Return a waypoint\'s lane type, `Map::G'
    "etLaneType`.\n\n        Args:\n"
)

comptime _MAP_LIVE_26 = (
    "            when the simulation applies them.\n\n        Raises:\n  "
    "          Error: If the waypoint or a mutable speed record is invali"
    'd.\n        """\n        if not isfinite(waypoint.s) or waypoint.'
    's < 0.0:\n            raise Error(\n                "Speed-limit st'
    'ation must be finite and within the road"\n            )\n        v'
    "ar location = self._locate(waypoint)\n        ref road = self.roads["
    "location[0]]\n        # The first check already refuses a nonfinite "
    "or negative\n        # station, and _locate refuses it again. So onl"
    "y the far end\n        # of the road can still refuse the station he"
    "re; the message\n        # names both limits.\n        if waypoint.s"
    ' > road.length:\n            raise Error(\n                "Speed-l'
    'imit station must be finite and within the road"\n            )\n  '
    "      ref lane = road.sections[location[1]].lanes[location[2]]\n    "
    "    var lane_speed = info_at(lane.info.speeds, waypoint.s)\n"
)

comptime _MAP_OLD_26 = (
    "            when the simulation applies them.\n\n        Raises:\n  "
    "          Error: If the waypoint or a mutable speed record is invali"
    'd.\n        """\n        var location = self._locate(waypoint)\n '
    "       ref road = self.roads[location[0]]\n        if (\n           "
    " not isfinite(waypoint.s)\n            or waypoint.s < 0\n          "
    "  or waypoint.s > road.length\n        ):\n            raise Error("
    '\n                "Speed-limit station must be finite and within th'
    'e road"\n            )\n        ref lane = road.sections[location[1'
    "]].lanes[location[2]]\n        var lane_speed = info_at(lane.info.sp"
    "eeds, waypoint.s)\n"
)

comptime _MAP_LIVE_27 = (
    "        var road_speed = info_at(road.info.speeds, waypoint.s)\n    "
    "    if Bool(road_speed):\n            return road_speed.value().limi"
    "t()\n        return None\n\n    def lane_width(self, waypoint: Waypo"
    'int) raises -> Length64:\n        """Return a lane width without '
    "narrowing its Float64 evaluation.\n\n        Args:\n            wayp"
    "oint: The lane and station.\n\n        Returns:\n            The fin"
    "ite lane width in meters.\n\n        Raises:\n            Error: If "
    'the waypoint or the width is invalid.\n        """\n        var w'
    "idth = self.lane_width_meters(waypoint)\n        # lane_width_meters"
    " refuses a nonfinite or negative width.\n        debug_assert(isfini"
    'te(width) and width >= 0.0, "A width is checked")\n        return '
    "Length64(width)\n\n    def lane_width_float32(self, waypoint: Waypoi"
    'nt) raises -> Length:\n        """Return a waypoint\'s lane width,'
    " `Map::GetLaneWidth`.\n\n        Args:\n            waypoint: The wa"
    "ypoint.\n\n"
)

comptime _MAP_OLD_27 = (
    "        var road_speed = info_at(road.info.speeds, waypoint.s)\n    "
    "    if Bool(road_speed):\n            return road_speed.value().limi"
    "t()\n        return None\n\n    def lane_width(self, waypoint: Waypo"
    'int) raises -> Length:\n        """Return a waypoint\'s lane width'
    ", `Map::GetLaneWidth`.\n\n        Args:\n            waypoint: The w"
    "aypoint.\n\n"
)

comptime _MAP_LIVE_28 = (
    "\n        Raises:\n            Error: If the lane is not in the map,"
    " s is past the road's end,\n                or no width record holds"
    ' at s.\n        """\n        var value = Float32(self.lane_width_'
    "meters(waypoint))\n        _ = _nonnegative_si(Float64(value))\n    "
    "    return Length(value, METER)\n\n    def lane_width_meters(self, w"
    'aypoint: Waypoint) raises -> Float64:\n        """Return a waypoi'
    "nt's lane width in double, as CARLA computes it.\n\n        Args:\n"
)

comptime _MAP_OLD_28 = (
    "\n        Raises:\n            Error: If the lane is not in the map,"
    " s is past the road's end,\n                or no width record holds"
    ' at s.\n        """\n        var at = self._locate(waypoint)\n   '
    "     ref road = self.roads[at[0]]\n        if waypoint.s > road.leng"
    'th:\n            raise Error("s is past the end of the road")\n   '
    "     var width = info_at(\n            road.sections[at[1]].lanes[at"
    "[2]].info.widths, waypoint.s\n        )\n        if not Bool(width):"
    '\n            raise Error("The lane has no width record at s")\n  '
    "      return Length(\n            Float32(width.value().polynomial.e"
    "valuate(waypoint.s)), METER\n        )\n\n    def lane_width_meters("
    'self, waypoint: Waypoint) raises -> Float64:\n        """Return a'
    " waypoint's lane width in double, as CARLA computes it.\n\n        A"
    "rgs:\n"
)

comptime _MAP_LIVE_29 = (
    "        var width = info_at(\n            road.sections[at[1]].lanes"
    "[at[2]].info.widths, waypoint.s\n        )\n        if not Bool(widt"
    'h):\n            raise Error("The lane has no width record at s")'
    "\n        return _nonnegative_si(\n            width.value().polynom"
    "ial._evaluate_si(waypoint.s)\n        )\n\n    def junction_id(self,"
    ' road: RoadId) raises -> JuncId:\n        """Return the junction '
    "a road belongs to, `Map::GetJunctionId`.\n\n        Args:\n"
)

comptime _MAP_OLD_29 = (
    "        var width = info_at(\n            road.sections[at[1]].lanes"
    "[at[2]].info.widths, waypoint.s\n        )\n        if not Bool(widt"
    'h):\n            raise Error("The lane has no width record at s")'
    "\n        return width.value().polynomial.evaluate(waypoint.s)\n\n  "
    '  def junction_id(self, road: RoadId) raises -> JuncId:\n        "'
    '""Return the junction a road belongs to, `Map::GetJunctionId`.\n\n'
    "        Args:\n"
)

comptime _MAP_LIVE_30 = (
    "        self, location: Vector3, lane_type: LaneType = LANE_DRIVING"
    '\n    ) raises -> Optional[Waypoint]:\n        """Return the wayp'
    "oint nearest a point, `GetClosestWaypointOnRoad`.\n\n        CARLA f"
    "inds the nearest segment of a lane of the given types, then\n       "
    " steps from the segment's start toward the point's foot. The step is"
    "\n        the foot's plan fraction of the segment times the segment'"
    "s road-s\n        span. CARLA steps by the plan distance itself; tha"
    "t is not road s\n        on a lane with a sloped or curved offset (#"
    "302). The segments are\n        CARLA's heading and length partition"
    ".\n        For the certified nearest center, use\n        `certified"
    "_closest_waypoint_on_road`.\n\n        Args:\n            location: "
    "The point, in CARLA's frame.\n"
)

comptime _MAP_OLD_30 = (
    "        self, location: Vector3, lane_type: LaneType = LANE_DRIVING"
    '\n    ) raises -> Optional[Waypoint]:\n        """Return the wayp'
    "oint nearest a point, `GetClosestWaypointOnRoad`.\n\n        CARLA f"
    "inds the nearest segment of a lane of the given types, then\n       "
    " steps from the segment's start by the distance along it to the\n   "
    "     point's foot. The segments are CARLA's heading and length parti"
    "tion.\n        For the certified nearest center, use\n        `certi"
    "fied_closest_waypoint_on_road`.\n\n        Args:\n            locati"
    "on: The point, in CARLA's frame.\n"
)

comptime _MAP_LIVE_31 = (
    "            location, _LaneTypeFilter(lane_type.value)\n        )\n "
    "       if len(found) == 0:\n            return None\n        ref seg"
    "ment = self._carla_segments[found[0].start_value]\n        var start"
    " = segment.first\n        var end = segment.second\n        var delt"
    "a = _chord_station_delta(\n            location, segment.start, segm"
    "ent.end, abs(end.s - start.s)\n        )\n        var forward = self"
    ".is_positive_direction(start)\n        var final_s = start.s + delta"
    " if forward else start.s - delta\n        var past = final_s >= end."
    "s if forward else final_s <= end.s\n        if past:\n            re"
    "turn end\n        if delta <= 0.0:\n            return start\n      "
    "  # The foot lies inside the segment's lane, so one step stays in it"
    ".\n        return self.next_meters(start, delta)[0]\n\n    def waypo"
    "int(\n        self, location: Vector3, lane_type: LaneType = LANE_DR"
    'IVING\n    ) raises -> Optional[Waypoint]:\n        """Return the'
    " waypoint under a point, `Map::GetWaypoint`.\n"
)

comptime _MAP_OLD_31 = (
    "            location, _LaneTypeFilter(lane_type.value)\n        )\n "
    "       if len(found) == 0:\n            return None\n        ref seg"
    "ment = self._carla_segments[found[0].start_value]\n        var along"
    " = distance_segment_to_point(\n            location, segment.start, "
    "segment.end\n        )\n        var start = segment.first\n        v"
    "ar end = segment.second\n        var delta = Float64(along[0].value)"
    "\n        var forward = self.is_positive_direction(start)\n        v"
    "ar final_s = start.s + delta if forward else start.s - delta\n      "
    "  var past = final_s >= end.s if forward else final_s <= end.s\n    "
    "    if past:\n            return end\n        if delta <= 0.0:\n    "
    "        return start\n        # The foot lies inside the segment's l"
    "ane, so one step stays in it.\n        return self.next(start, delta"
    ")[0]\n\n    def waypoint(\n        self, location: Vector3, lane_typ"
    "e: LaneType = LANE_DRIVING\n    ) raises -> Optional[Waypoint]:\n   "
    '     """Return the waypoint under a point, `Map::GetWaypoint`.\n'
)

comptime _MAP_LIVE_32 = (
    "            if not candidate:\n                break\n            va"
    "r index = candidate.value().start_value\n            ref segment = s"
    "elf._segments[index]\n            if best >= 0:\n                var"
    " key = _segment_distance2(\n                    segment.start, segme"
    "nt.end, location\n                )\n                var lower = _in"
    "dexed_curve_lower(key, self._curve_deviation)\n                if lo"
    "wer > best_radius:\n                    break\n                # The"
    " index orders keys only, so the walk keeps the global\n             "
    "   # stop. This candidate's own deviation can still exclude it.\n   "
    "             if _indexed_curve_lower(key, segment.deviation) > best_"
    "radius:\n                    continue\n                if not _lane_"
    "box_can_improve(\n                    segment.bounds, location, cert"
    "ificates[best].point\n                ):\n                    contin"
    "ue\n                if segment.cover_index >= 0:\n"
)

comptime _MAP_OLD_32 = (
    "            if not candidate:\n                break\n            va"
    "r index = candidate.value().start_value\n            ref segment = s"
    "elf._segments[index]\n            if best >= 0:\n                var"
    " lower = _indexed_curve_lower(\n                    _segment_distanc"
    "e2(segment.start, segment.end, location),\n                    self."
    "_curve_deviation,\n                )\n                if lower > bes"
    "t_radius:\n                    break\n                if not _lane_b"
    "ox_can_improve(\n                    segment.bounds, location, certi"
    "ficates[best].point\n                ):\n                    continu"
    "e\n                if segment.cover_index >= 0:\n"
)

comptime _MAP_LIVE_33 = (
    "            return None\n        # Admission's strict full-domain ex"
    "clusions remain valid\n        # as these retained candidates improv"
    "e their stored incumbents.\n        var requested_gaps = List[Float6"
    "4]()\n        var requested_scales = List[Float64]()\n        for ce"
    "rtificate in certificates:  # pragma: no branch\n            work._s"
    "tep(2)\n            requested_gaps.append(inf[DType.float64]())\n   "
    "         requested_scales.append(certificate.scale)\n        while T"
    "rue:\n            # A resumed candidate can change the best stored s"
    "ample. Recheck\n            # all index-sensitive dominance relation"
    "s after every refinement.\n            for i in range(len(indices)):"
    "  # pragma: no branch\n                work._step()\n               "
    " var order = _wide_point_order(\n                    certificates[i]"
    ".point, certificates[best].point, query\n                )\n        "
    "        if order < 0 or (order == 0 and indices[i] < indices[best]):"
    "\n"
)

comptime _MAP_OLD_33 = (
    "            return None\n        # Admission's strict full-domain ex"
    "clusions remain valid\n        # as these retained candidates improv"
    "e their stored incumbents.\n        var requested_gaps = List[Float6"
    "4]()\n        var requested_scales = List[Float64]()\n        for ce"
    "rtificate in certificates:\n            work._step(2)\n            r"
    "equested_gaps.append(inf[DType.float64]())\n            requested_sc"
    "ales.append(certificate.scale)\n        while True:\n            # A"
    " resumed candidate can change the best stored sample. Recheck\n     "
    "       # all index-sensitive dominance relations after every refinem"
    "ent.\n            for i in range(len(indices)):\n                wor"
    "k._step()\n                var order = _wide_point_order(\n         "
    "           certificates[i].point, certificates[best].point, query\n "
    "               )\n                if order < 0 or (order == 0 and in"
    "dices[i] < indices[best]):\n"
)

comptime _MAP_LIVE_34 = (
    "                    work,\n                )\n                accura"
    "te[best] |= 1\n                waypoints[best].s = certificates[best"
    "].s\n            var target = -1\n            for i in range(len(ind"
    "ices)):  # pragma: no branch\n                work._step()\n        "
    "        if i == best:\n                    continue\n               "
    " if _lane_certificate_dominates(\n                    certificates[b"
    "est],\n"
)

comptime _MAP_OLD_34 = (
    "                    work,\n                )\n                accura"
    "te[best] |= 1\n                waypoints[best].s = certificates[best"
    "].s\n            var target = -1\n            for i in range(len(ind"
    "ices)):\n                work._step()\n                if i == best:"
    "\n                    continue\n                if _lane_certificate"
    "_dominates(\n                    certificates[best],\n"
)

comptime _MAP_LIVE_35 = (
    "                    len(target_road.sections),\n                    "
    "target_lanes,\n                    target_lanes,\n                  "
    "  6,\n                ]\n                for value in metadata:  # p"
    "ragma: no branch\n                    if prefix_valid and value <= p"
    "refix_room - prefix:\n                        prefix += value\n     "
    "               else:\n                        prefix_valid = False\n"
    "                for candidate in certificates:  # pragma: no branch"
    "\n                    work._step()\n                    if (\n      "
    "                  prefix_valid\n                        and len(cand"
    "idate.cells) <= prefix_room - prefix\n                    ):\n      "
    "                  prefix += len(candidate.cells)\n                  "
    "  else:\n                        prefix_valid = False\n             "
    "   for _ in range(4):  # pragma: no branch\n                    if ("
    "\n                        prefix_valid\n                        and "
    "len(certificates[best].cells)\n                        <= prefix_roo"
    "m - prefix\n                    ):\n                        prefix +"
    "= len(certificates[best].cells)\n                    else:\n        "
    "                prefix_valid = False\n                for _ in range"
    "(10):  # pragma: no branch\n                    if (\n              "
    "          prefix_valid\n                        and len(certificates"
    "[target].cells)\n                        <= prefix_room - prefix\n  "
    "                  ):\n"
)

comptime _MAP_OLD_35 = (
    "                    len(target_road.sections),\n                    "
    "target_lanes,\n                    target_lanes,\n                  "
    "  6,\n                ]\n                for value in metadata:\n   "
    "                 if prefix_valid and value <= prefix_room - prefix:"
    "\n                        prefix += value\n                    else:"
    "\n                        prefix_valid = False\n                for "
    "candidate in certificates:\n                    work._step()\n      "
    "              if (\n                        prefix_valid\n          "
    "              and len(candidate.cells) <= prefix_room - prefix\n    "
    "                ):\n                        prefix += len(candidate."
    "cells)\n                    else:\n                        prefix_va"
    "lid = False\n                for _ in range(4):\n                   "
    " if (\n                        prefix_valid\n                       "
    " and len(certificates[best].cells)\n                        <= prefi"
    "x_room - prefix\n                    ):\n                        pre"
    "fix += len(certificates[best].cells)\n                    else:\n   "
    "                     prefix_valid = False\n                for _ in "
    "range(10):\n                    if (\n                        prefix"
    "_valid\n                        and len(certificates[target].cells)"
    "\n                        <= prefix_room - prefix\n                 "
    "   ):\n"
)

comptime _MAP_LIVE_36 = (
    "            or not isfinite(end.s)\n        ):\n            raise Er"
    'ror(\n                "CARLA query segment must stay in one finite '
    'lane section"\n            )\n        var delta = _chord_station_de'
    "lta(\n            location, segment.start, segment.end, abs(end.s - "
    "start.s)\n        )\n        # The default query resolves this metad"
    "ata twice (direction and\n        # next). Reuse the same checked lo"
    "cation and preserve its arithmetic.\n        var at = self._locate_w"
    "ith_work(start, work)\n        ref road = self.roads[at[0]]\n       "
    " work.step(len(road.sections))\n        var length = road._section_l"
    "ength_si(at[1])\n        var section_start = road.sections[at[1]].s"
    "\n        if not isfinite(length) or length < 0.0:\n            rais"
    'e Error("CARLA query lane section has an invalid length")\n       '
    " # A constructed endpoint can round one word beyond its section's\n "
    "       # mathematical boundary. The default query retains that endpo"
    "int.\n"
)

comptime _MAP_OLD_36 = (
    "            or not isfinite(end.s)\n        ):\n            raise Er"
    'ror(\n                "CARLA query segment must stay in one finite '
    'lane section"\n            )\n        var along = distance_segment_'
    "to_point(\n            location, segment.start, segment.end\n       "
    " )\n        var delta = Float64(along[0].value)\n        # The defau"
    "lt query resolves this metadata twice (direction and\n        # next"
    "). Reuse the same checked location and preserve its arithmetic.\n   "
    "     var at = self._locate_with_work(start, work)\n        ref road "
    "= self.roads[at[0]]\n        work.step(len(road.sections))\n        "
    "var length = road.section_length(at[1])\n        var section_start ="
    " road.sections[at[1]].s\n        if not isfinite(length) or length <"
    ' 0.0:\n            raise Error("CARLA query lane section has an inv'
    'alid length")\n        # A constructed endpoint can round one word '
    "beyond its section's\n        # mathematical boundary. The default q"
    "uery retains that endpoint.\n"
)

comptime _MAP_LIVE_37 = (
    "            var key = keys[index]\n            index += 1\n         "
    "   if key.lane_id.value == 0:\n                continue\n           "
    " var target = self._locate_with_work(\n                Waypoint._fro"
    "m_si(\n                    key.road_id, key.section_id, key.lane_id,"
    " 0.0\n                ),\n                work,\n            )\n    "
    "        # _start_of_lane scans once in the positive direction and tw"
    "ice\n            # in reverse; reserve both without changing its ari"
    "thmetic.\n            work.step_product(2, len(self.roads[target[0]]"
    ".sections))\n            var station = self._start_of_lane(target[0]"
    ", target[1], target[2])\n            if not isfinite(station):\n    "
    '            raise Error("CARLA graph successor has a nonfinite stat'
    'ion")\n            work.step()\n            out.append(\n          '
    "      Waypoint._from_si(\n                    key.road_id, key.secti"
    "on_id, key.lane_id, station\n                )\n            )\n     "
    "   return out^\n\n    def _next_with_build_work(\n        self, wayp"
    "oint: Waypoint, distance: Float64, mut work: _MapBuildWork\n"
)

comptime _MAP_OLD_37 = (
    "            var key = keys[index]\n            index += 1\n         "
    "   if key.lane_id.value == 0:\n                continue\n           "
    " var target = self._locate_with_work(\n                Waypoint(key."
    "road_id, key.section_id, key.lane_id, 0.0), work\n            )\n   "
    "         # _start_of_lane scans once in the positive direction and t"
    "wice\n            # in reverse; reserve both without changing its ar"
    "ithmetic.\n            work.step_product(2, len(self.roads[target[0]"
    "].sections))\n            var station = self._start_of_lane(target[0"
    "], target[1], target[2])\n            if not isfinite(station):\n   "
    '             raise Error("CARLA graph successor has a nonfinite sta'
    'tion")\n            work.step()\n            out.append(\n         '
    "       Waypoint(key.road_id, key.section_id, key.lane_id, station)\n"
    "            )\n        return out^\n\n    def _next_with_build_work("
    "\n        self, waypoint: Waypoint, distance: Float64, mut work: _Ma"
    "pBuildWork\n"
)

comptime _MAP_LIVE_38 = (
    "                var at = self._locate_with_work(frame.waypoint, work"
    ")\n                ref road = self.roads[at[0]]\n                var"
    " forward = road.is_positive_direction(frame.waypoint.lane_id)\n     "
    "           var start = road.sections[at[1]].s\n                work."
    "step(len(road.sections))\n                var length = road._section"
    "_length_si(at[1])\n                if not isfinite(start) or not isf"
    "inite(length) or length < 0.0:\n                    raise Error(\n  "
    '                      "CARLA graph lane section has an invalid leng'
    'th"\n                    )\n                var relative = frame.wa'
    "ypoint.s - start\n"
)

comptime _MAP_OLD_38 = (
    "                var at = self._locate_with_work(frame.waypoint, work"
    ")\n                ref road = self.roads[at[0]]\n                var"
    " forward = road.is_positive_direction(frame.waypoint.lane_id)\n     "
    "           var start = road.sections[at[1]].s\n                work."
    "step(len(road.sections))\n                var length = road.section_"
    "length(at[1])\n                if not isfinite(start) or not isfinit"
    "e(length) or length < 0.0:\n                    raise Error(\n      "
    '                  "CARLA graph lane section has an invalid length"'
    "\n                    )\n                var relative = frame.waypoi"
    "nt.s - start\n"
)

comptime _MAP_LIVE_39 = (
    '        if terms < 0:\n            raise Error("Selected lane pose '
    'has unresolved quadrature work")\n        # Two separately checked '
    "debits avoid overflow in twice-the-cost.\n        work.charge(1, ter"
    "ms)\n        work.charge(0, terms)\n        _ = self.roads[at[0]]._l"
    "ane_transform_si(at[1], at[2], waypoint.s)\n\n    def waypoint_xodr("
    "\n        self, road_id: RoadId, lane_id: LaneId, s: Length64\n    )"
    ' raises -> Optional[Waypoint]:\n        """Return the waypoint at'
    " a road, a lane and an s, `GetWaypoint`.\n\n        The station stay"
    "s in Float64; use the explicit Float32 adapter\n        only for a l"
    "egacy CARLA float input.\n\n        Args:\n            road_id: The "
    "road.\n            lane_id: The lane.\n            s: The distance a"
    "long the road.\n"
)

comptime _MAP_OLD_39 = (
    '        if terms < 0:\n            raise Error("Selected lane pose '
    'has unresolved quadrature work")\n        # Two separately checked '
    "debits avoid overflow in twice-the-cost.\n        work.charge(1, ter"
    "ms)\n        work.charge(0, terms)\n        _ = self.roads[at[0]].la"
    "ne_transform(at[1], at[2], waypoint.s)\n\n    def waypoint_xodr(\n  "
    "      self, road_id: RoadId, lane_id: LaneId, s: Length\n    ) raise"
    's -> Optional[Waypoint]:\n        """Return the waypoint at a roa'
    "d, a lane and an s, `GetWaypoint`.\n\n        CARLA takes s as a `fl"
    "oat`, as `Length` holds it.\n\n        Args:\n            road_id: T"
    "he road.\n            lane_id: The lane.\n            s: The distanc"
    "e along the road.\n"
)

comptime _MAP_LIVE_40 = (
    "        if not (road_id.is_valid() and lane_id.is_valid()):\n       "
    '     raise Error("Road id or lane id is not valid")\n        if no'
    "t self.contains_road(road_id):\n            return None\n        ref"
    " road = self.road(road_id)\n        var at = _finite_si(s.value)\n  "
    "      if s.value < 0.0 or at >= road.length:\n            return Non"
    "e\n        for index in road._sections_at_si(at):\n            if ro"
    "ad.sections[index].contains_lane(lane_id):\n                return W"
    "aypoint._from_si(\n                    road_id, road.sections[index]"
    ".id, lane_id, at\n                )\n        return None\n\n    def "
    "waypoint_xodr_float32(\n        self, road_id: RoadId, lane_id: Lane"
    'Id, s: Length\n    ) raises -> Optional[Waypoint]:\n        """Lo'
    "ok up a legacy Float32 station through an explicit adapter.\n\n     "
    "   Args:\n            road_id: The road.\n            lane_id: The l"
    "ane.\n            s: The legacy Float32 station.\n\n        Returns:"
    "\n            The matching waypoint, if present.\n\n        Raises:"
    "\n            Error: If an id or the station is not valid.\n        "
    '"""\n        return self.waypoint_xodr(road_id, lane_id, Length64'
    "(Float64(s.value)))\n\n    # --- walking the network ---------------"
    "-----------------------------------\n\n    def successors(self, wayp"
    'oint: Waypoint) raises -> List[Waypoint]:\n        """Return the '
    "start of each lane a waypoint's lane leads to.\n\n"
)

comptime _MAP_OLD_40 = (
    "        if not (road_id.is_valid() and lane_id.is_valid()):\n       "
    '     raise Error("Road id or lane id is not valid")\n        if no'
    "t self.contains_road(road_id):\n            return None\n        ref"
    " road = self.road(road_id)\n        var at = Float64(s.value)\n     "
    "   if s.value < 0.0 or at >= road.length:\n            return None\n"
    "        for index in road.sections_at(at):\n            if road.sect"
    "ions[index].contains_lane(lane_id):\n                return Waypoint"
    "(road_id, road.sections[index].id, lane_id, at)\n        return None"
    "\n\n    # --- walking the network ----------------------------------"
    "----------------\n\n    def successors(self, waypoint: Waypoint) rai"
    'ses -> List[Waypoint]:\n        """Return the start of each lane '
    "a waypoint's lane leads to.\n\n"
)

comptime _MAP_LIVE_41 = (
    "        for key in self.lane(waypoint).next_lanes:\n            if k"
    "ey.lane_id.value == 0:\n                continue\n            var at"
    " = self._key(key)\n            out.append(\n                Waypoint"
    "._from_si(\n                    key.road_id,\n                    ke"
    "y.section_id,\n                    key.lane_id,\n                   "
    " self._start_of_lane(at[0], at[1], at[2]),\n                )\n"
)

comptime _MAP_OLD_41 = (
    "        for key in self.lane(waypoint).next_lanes:\n            if k"
    "ey.lane_id.value == 0:\n                continue\n            var at"
    " = self._key(key)\n            out.append(\n                Waypoint"
    "(\n                    key.road_id,\n                    key.section"
    "_id,\n                    key.lane_id,\n                    self._st"
    "art_of_lane(at[0], at[1], at[2]),\n                )\n"
)

comptime _MAP_LIVE_42 = (
    "        for key in self.lane(waypoint).prev_lanes:\n            if k"
    "ey.lane_id.value == 0:\n                continue\n            var at"
    " = self._key(key)\n            out.append(\n                Waypoint"
    "._from_si(\n                    key.road_id,\n                    ke"
    "y.section_id,\n                    key.lane_id,\n                   "
    " self._end_of_lane(at[0], at[1], at[2]),\n                )\n       "
    "     )\n        return out^\n\n    def next(\n        self, waypoint"
    ": Waypoint, distance: Length64\n    ) raises -> List[Waypoint]:\n   "
    '     """Return the next result with a Float64 length.\n\n        '
    "Args:\n            waypoint: The start waypoint.\n            distan"
    "ce: The distance or spacing, with its meter unit.\n\n        Returns"
    ":\n            The requested records with unchanged Float64 endpoint"
    " arithmetic.\n\n        Raises:\n            Error: If the distance "
    'or the selected map records are invalid.\n        """\n        re'
    "turn self.next_meters(waypoint, distance.value)\n\n    def next_mete"
    "rs(\n        self, waypoint: Waypoint, distance: Float64\n    ) rais"
    'es -> List[Waypoint]:\n        """Explicit meter compatibility ad'
    "apter. Return the waypoints a distance ahead, `Map::GetNext`.\n\n   "
    "     Ahead is the way the lane runs. Past the lane's end the walk\n "
    "       continues on each successor; where two lanes lead back into e"
    "ach\n        other, CARLA skips the loop. The list puts the longer p"
    "art first,\n        as CARLA's `ConcatVectors`.\n"
)

comptime _MAP_OLD_42 = (
    "        for key in self.lane(waypoint).prev_lanes:\n            if k"
    "ey.lane_id.value == 0:\n                continue\n            var at"
    " = self._key(key)\n            out.append(\n                Waypoint"
    "(\n                    key.road_id,\n                    key.section"
    "_id,\n                    key.lane_id,\n                    self._en"
    "d_of_lane(at[0], at[1], at[2]),\n                )\n            )\n "
    "       return out^\n\n    def next(\n        self, waypoint: Waypoin"
    't, distance: Float64\n    ) raises -> List[Waypoint]:\n        ""'
    '"Return the waypoints a distance ahead, `Map::GetNext`.\n\n        '
    "Ahead is the way the lane runs. Past the lane's end the walk\n      "
    "  continues on each successor; where two lanes lead back into each\n"
    "        other, CARLA skips the loop. The list puts the longer part f"
    "irst,\n        as CARLA's `ConcatVectors`.\n"
)

comptime _MAP_LIVE_43 = (
    '                the map.\n        """\n        return self._step('
    "waypoint, distance, True)\n\n    def previous(\n        self, waypoi"
    "nt: Waypoint, distance: Length64\n    ) raises -> List[Waypoint]:\n "
    '       """Return the previous result with a Float64 length.\n\n  '
    "      Args:\n            waypoint: The start waypoint.\n            "
    "distance: The distance or spacing, with its meter unit.\n\n        R"
    "eturns:\n            The requested records with unchanged Float64 en"
    "dpoint arithmetic.\n\n        Raises:\n            Error: If the dis"
    'tance or the selected map records are invalid.\n        """\n    '
    "    return self.previous_meters(waypoint, distance.value)\n\n    def"
    " previous_meters(\n        self, waypoint: Waypoint, distance: Float"
    '64\n    ) raises -> List[Waypoint]:\n        """Explicit meter co'
    "mpatibility adapter. Return the waypoints a distance behind, `Map::G"
    "etPrevious`.\n\n        Args:\n            waypoint: The start.\n   "
    "         distance: How far behind, in meters. It must be positive.\n"
    "\n"
)

comptime _MAP_OLD_43 = (
    '                the map.\n        """\n        return self._step('
    "waypoint, distance, True)\n\n    def previous(\n        self, waypoi"
    "nt: Waypoint, distance: Float64\n    ) raises -> List[Waypoint]:\n  "
    '      """Return the waypoints a distance behind, `Map::GetPreviou'
    "s`.\n\n        Args:\n            waypoint: The start.\n            "
    "distance: How far behind, in meters. It must be positive.\n\n"
)

comptime _MAP_LIVE_44 = (
    "        return self._step(waypoint, distance, False)\n\n    def _ste"
    "p(\n        self, waypoint: Waypoint, distance: Float64, ahead: Bool"
    "\n    ) raises -> List[Waypoint]:\n        if not isfinite(distance)"
    ' or not (distance > 0.0):\n            raise Error("A step needs a '
    'positive distance")\n        _ = _nonnegative_si(waypoint.s)\n     '
    "   if distance <= EPSILON:\n            return [waypoint]\n        v"
    "ar at = self._locate(waypoint)\n        ref road = self.roads[at[0]]"
    "\n        var positive = road.is_positive_direction(waypoint.lane_id"
    ")\n        var forward = positive if ahead else not positive\n      "
    "  var start = road.sections[at[1]].s\n        var length = road._sec"
    "tion_length_si(at[1])\n        var relative = waypoint.s - start\n  "
    "      var remaining = length - relative if forward else relative\n  "
    "      if distance <= remaining:\n            var result = waypoint\n"
    "            if forward:\n"
)

comptime _MAP_OLD_44 = (
    "        return self._step(waypoint, distance, False)\n\n    def _ste"
    "p(\n        self, waypoint: Waypoint, distance: Float64, ahead: Bool"
    "\n    ) raises -> List[Waypoint]:\n        if not (distance > 0.0):"
    '\n            raise Error("A step needs a positive distance")\n   '
    "     if distance <= EPSILON:\n            return [waypoint]\n       "
    " var at = self._locate(waypoint)\n        ref road = self.roads[at[0"
    "]]\n        var positive = road.is_positive_direction(waypoint.lane_"
    "id)\n        var forward = positive if ahead else not positive\n    "
    "    var start = road.sections[at[1]].s\n        var length = road.se"
    "ction_length(at[1])\n        var relative = waypoint.s - start\n    "
    "    var remaining = length - relative if forward else relative\n    "
    "    if distance <= remaining:\n            var result = waypoint\n  "
    "          if forward:\n"
)

comptime _MAP_LIVE_45 = (
    "            return out\n        return None\n\n    # --- waypoint ge"
    "neration ------------------------------------------------------\n\n "
    "   def generate_waypoints(self, distance: Length64) raises -> List[W"
    'aypoint]:\n        """Return the generate waypoints result with a'
    " Float64 length.\n\n        Args:\n            distance: The distanc"
    "e or spacing, with its meter unit.\n\n        Returns:\n            "
    "The requested records with unchanged Float64 endpoint arithmetic.\n"
    "\n        Raises:\n            Error: If the distance or the selecte"
    'd map records are invalid.\n        """\n        return self.gene'
    "rate_waypoints_meters(distance.value)\n\n    def generate_waypoints_"
    "meters(\n        self, distance: Float64\n    ) raises -> List[Waypo"
    'int]:\n        """Explicit meter compatibility adapter. Return wa'
    "ypoints every `distance` on every driving lane.\n\n        This is `"
    "Map::GenerateWaypoints`: from `EPSILON` along each road,\n        ev"
    "ery `distance` meters, on each driving lane at that s.\n\n        Ar"
    "gs:\n"
)

comptime _MAP_OLD_45 = (
    "            return out\n        return None\n\n    # --- waypoint ge"
    "neration ------------------------------------------------------\n\n "
    "   def generate_waypoints(self, distance: Float64) raises -> List[Wa"
    'ypoint]:\n        """Return waypoints every `distance` on every d'
    "riving lane.\n\n        This is `Map::GenerateWaypoints`: from `EPSI"
    "LON` along each road,\n        every `distance` meters, on each driv"
    "ing lane at that s.\n\n        Args:\n"
)

comptime _MAP_LIVE_46 = (
    "            The waypoints, road by road.\n\n        Raises:\n       "
    '     Error: If the distance is not positive.\n        """\n      '
    "  if not isfinite(distance) or not (distance > 0.0):\n            ra"
    'ise Error("Waypoint spacing must be positive")\n        var out = '
    "List[Waypoint]()\n        for road in self.roads:\n            var s"
    " = EPSILON\n            while s < road.length - EPSILON:\n          "
    "      for index in road._sections_at_si(s):\n                    for"
    " lane in road.sections[index].lanes:\n                        if lan"
    "e.id.value == 0:\n                            continue\n            "
    "            if lane.type.matches(LANE_DRIVING):\n                   "
    "         out.append(\n                                Waypoint._from"
    "_si(\n                                    road.id, road.sections[ind"
    "ex].id, lane.id, s\n                                )\n             "
    "               )\n                var following = s + distance\n    "
    "            if not isfinite(following) or following <= s:\n         "
    '           raise Error(\n                        "Waypoint spacing '
    'cannot advance at this station"\n                    )\n           '
    "     s = following\n        return out^\n\n    def _entries(\n      "
    "  self, road: Road, lane_type: LaneType, mut out: List[Waypoint]\n  "
    "  ):\n        for index in road._sections_at_si(0.0):\n            f"
    "or lane in road.sections[index].lanes:\n                if road.is_p"
    "ositive_direction(lane.id) and lane.type.matches(\n                 "
    "   lane_type\n                ):\n                    out.append(\n "
    "                       Waypoint._from_si(\n                         "
    "   road.id, road.sections[index].id, lane.id, 0.0\n                 "
    "       )\n                    )\n        for index in road._sections"
    "_at_si(road.length):\n            for lane in road.sections[index].l"
    "anes:\n                if not road.is_positive_direction(\n         "
    "           lane.id\n                ) and lane.type.matches(lane_typ"
    "e):\n                    out.append(\n                        Waypoi"
    "nt._from_si(\n                            road.id,\n                "
    "            road.sections[index].id,\n                            la"
    "ne.id,\n                            road.length,\n                  "
    "      )\n"
)

comptime _MAP_OLD_46 = (
    "            The waypoints, road by road.\n\n        Raises:\n       "
    '     Error: If the distance is not positive.\n        """\n      '
    '  if not (distance > 0.0):\n            raise Error("Waypoint spaci'
    'ng must be positive")\n        var out = List[Waypoint]()\n        '
    "for road in self.roads:\n            var s = EPSILON\n            wh"
    "ile s < road.length - EPSILON:\n                for index in road.se"
    "ctions_at(s):\n                    for lane in road.sections[index]."
    "lanes:\n                        if lane.id.value == 0:\n            "
    "                continue\n                        if lane.type.match"
    "es(LANE_DRIVING):\n                            out.append(\n        "
    "                        Waypoint(\n                                 "
    "   road.id, road.sections[index].id, lane.id, s\n                   "
    "             )\n                            )\n                s += "
    "distance\n        return out^\n\n    def _entries(\n        self, ro"
    "ad: Road, lane_type: LaneType, mut out: List[Waypoint]\n    ):\n    "
    "    for index in road.sections_at(0.0):\n            for lane in roa"
    "d.sections[index].lanes:\n                if road.is_positive_direct"
    "ion(lane.id) and lane.type.matches(\n                    lane_type\n"
    "                ):\n                    out.append(\n               "
    "         Waypoint(road.id, road.sections[index].id, lane.id, 0.0)\n "
    "                   )\n        for index in road.sections_at(road.len"
    "gth):\n            for lane in road.sections[index].lanes:\n        "
    "        if not road.is_positive_direction(\n                    lane"
    ".id\n                ) and lane.type.matches(lane_type):\n          "
    "          out.append(\n                        Waypoint(\n          "
    "                  road.id,\n                            road.section"
    "s[index].id,\n                            lane.id,\n                "
    "            road.length,\n                        )\n"
)

comptime _MAP_LIVE_47 = (
    "                    ref lane = section.lanes[ln]\n                  "
    "  if lane.id.value == 0 or not lane.type.matches(\n                 "
    "       LANE_DRIVING\n                    ):\n                       "
    " continue\n                    var w = Waypoint._from_si(\n         "
    "               road.id,\n                        section.id,\n      "
    "                  lane.id,\n                        self._start_of_l"
    "ane(r, sec, ln),\n                    )\n                    var nex"
    "ts = self.successors(w)\n                    if len(nexts) == 0:\n  "
    "                      var last = Waypoint._from_si(\n               "
    "             road.id,\n                            section.id,\n    "
    "                        lane.id,\n                            self._"
    "end_of_lane(r, sec, ln),\n                        )\n"
)

comptime _MAP_OLD_47 = (
    "                    ref lane = section.lanes[ln]\n                  "
    "  if lane.id.value == 0 or not lane.type.matches(\n                 "
    "       LANE_DRIVING\n                    ):\n                       "
    " continue\n                    var w = Waypoint(\n                  "
    "      road.id,\n                        section.id,\n               "
    "         lane.id,\n                        self._start_of_lane(r, se"
    "c, ln),\n                    )\n                    var nexts = self"
    ".successors(w)\n                    if len(nexts) == 0:\n           "
    "             var last = Waypoint(\n                            road."
    "id,\n                            section.id,\n                      "
    "      lane.id,\n                            self._end_of_lane(r, sec"
    ", ln),\n                        )\n"
)

comptime _MAP_LIVE_48 = (
    "                ref section = road.sections[sec]\n                fo"
    "r ln in range(len(section.lanes)):\n                    ref lane = s"
    "ection.lanes[ln]\n                    if lane.id.value == 0 or not l"
    "ane.type.matches(lane_type):\n                        continue\n    "
    "                var start = Waypoint._from_si(\n                    "
    "    road.id,\n                        section.id,\n                 "
    "       lane.id,\n                        self._start_of_lane(r, sec,"
    " ln),\n                    )\n"
)

comptime _MAP_OLD_48 = (
    "                ref section = road.sections[sec]\n                fo"
    "r ln in range(len(section.lanes)):\n                    ref lane = s"
    "ection.lanes[ln]\n                    if lane.id.value == 0 or not l"
    "ane.type.matches(lane_type):\n                        continue\n    "
    "                var start = Waypoint(\n                        road."
    "id,\n                        section.id,\n                        la"
    "ne.id,\n                        self._start_of_lane(r, sec, ln),\n  "
    "                  )\n"
)

comptime _MAP_LIVE_49 = (
    "                    ref lane = section.lanes[ln]\n                  "
    "  if lane.id.value == 0 or not lane.type.matches(lane_type):\n      "
    "                  continue\n                    # Each edge helper c"
    "an scan strict section successors twice.\n                    work.s"
    "tep_product(4, len(road.sections))\n                    var start = "
    "Waypoint._from_si(\n                        road.id,\n              "
    "          section.id,\n                        lane.id,\n           "
    "             self._start_of_lane(r, sec, ln),\n                    )"
    "\n"
)

comptime _MAP_OLD_49 = (
    "                    ref lane = section.lanes[ln]\n                  "
    "  if lane.id.value == 0 or not lane.type.matches(lane_type):\n      "
    "                  continue\n                    # Each edge helper c"
    "an scan strict section successors twice.\n                    work.s"
    "tep_product(4, len(road.sections))\n                    var start = "
    "Waypoint(\n                        road.id,\n                       "
    " section.id,\n                        lane.id,\n                    "
    "    self._start_of_lane(r, sec, ln),\n                    )\n"
)

comptime _MAP_LIVE_50 = (
    "                if self.road(two.first.road_id).junction_id != id:\n"
    "                    continue\n                if one.first.road_id ="
    "= two.first.road_id:\n                    continue\n                "
    "if (\n                    _segment_distance_2d_si(\n                "
    "        one.start, one.end, two.start, two.end\n                    "
    ")\n                    > 2.0\n                ):\n                  "
    "  continue\n                _add_conflict_with_work(\n              "
    "      roads, conflicts, one.first.road_id, two.first.road_id, work\n"
)

comptime _MAP_OLD_50 = (
    "                if self.road(two.first.road_id).junction_id != id:\n"
    "                    continue\n                if one.first.road_id ="
    "= two.first.road_id:\n                    continue\n                "
    "if (\n                    segment_distance_2d(one.start, one.end, tw"
    "o.start, two.end)\n                    > 2.0\n                ):\n  "
    "                  continue\n                _add_conflict_with_work("
    "\n                    roads, conflicts, one.first.road_id, two.first"
    ".road_id, work\n"
)

comptime _MAP_LIVE_51 = (
    "        return (roads^, conflicts^)\n\n    # --- signals and marks -"
    "---------------------------------------------------\n\n    def signa"
    "ls_in_distance(\n        self,\n        waypoint: Waypoint,\n       "
    " distance: Length64,\n        stop_at_junction: Bool = False,\n    )"
    ' raises -> List[SignalSearchData]:\n        """Return the signals'
    " in distance result with a Float64 length.\n\n        Args:\n       "
    "     waypoint: The start waypoint.\n            distance: The distan"
    "ce or spacing, with its meter unit.\n            stop_at_junction: W"
    "hether to stop at a junction.\n\n        Returns:\n            The r"
    "equested records with unchanged Float64 endpoint arithmetic.\n\n    "
    "    Raises:\n            Error: If the distance or the selected map "
    'records are invalid.\n        """\n        return self.signals_in'
    "_distance_meters(\n            waypoint, distance.value, stop_at_jun"
    "ction\n        )\n\n    def signals_in_distance_meters(\n        sel"
    "f,\n        waypoint: Waypoint,\n        distance: Float64,\n       "
    " stop_at_junction: Bool = False,\n    ) raises -> List[SignalSearchD"
    'ata]:\n        """Explicit meter compatibility adapter. Return th'
    "e signals within a distance ahead, `GetSignalsInDistance`.\n\n      "
    "  A signal counts when one of its validities holds the waypoint's\n "
    "       lane. The search follows every successor past the lane's end,"
    " and\n        skips junction roads when `stop_at_junction` is set.\n"
    "\n"
)

comptime _MAP_OLD_51 = (
    "        return (roads^, conflicts^)\n\n    # --- signals and marks -"
    "---------------------------------------------------\n\n    def signa"
    "ls_in_distance(\n        self,\n        waypoint: Waypoint,\n       "
    " distance: Float64,\n        stop_at_junction: Bool = False,\n    ) "
    'raises -> List[SignalSearchData]:\n        """Return the signals '
    "within a distance ahead, `GetSignalsInDistance`.\n\n        A signal"
    " counts when one of its validities holds the waypoint's\n        lan"
    "e. The search follows every successor past the lane's end, and\n    "
    "    skips junction roads when `stop_at_junction` is set.\n\n"
)

comptime _MAP_LIVE_52 = (
    "            its distance from the start.\n\n        Raises:\n       "
    '     Error: If the lane is not in the map.\n        """\n        '
    "if not isfinite(distance) or distance < 0.0:\n            raise Erro"
    'r("Signal distance must be finite and nonnegative")\n        var a'
    "t = self._locate(waypoint)\n        ref road = self.roads[at[0]]\n  "
    "      var forward = road.is_positive_direction(waypoint.lane_id)\n  "
    "      var relative = waypoint.s - road.sections[at[1]].s\n        va"
    "r remaining = (\n            road._section_length_si(at[1]) - relati"
    "ve if forward else relative\n        )\n        var reach = min(dist"
    "ance, remaining)\n        var signed = reach if forward else -reach"
    "\n        var out = List[SignalSearchData]()\n        for signal in "
    "infos_in_range(\n"
)

comptime _MAP_OLD_52 = (
    "            its distance from the start.\n\n        Raises:\n       "
    '     Error: If the lane is not in the map.\n        """\n        '
    "var at = self._locate(waypoint)\n        ref road = self.roads[at[0]"
    "]\n        var forward = road.is_positive_direction(waypoint.lane_id"
    ")\n        var relative = waypoint.s - road.sections[at[1]].s\n     "
    "   var remaining = (\n            road.section_length(at[1]) - relat"
    "ive if forward else relative\n        )\n        var reach = min(dis"
    "tance, remaining)\n        var signed = reach if forward else -reach"
    "\n        var out = List[SignalSearchData]()\n        for signal in "
    "infos_in_range(\n"
)

comptime _MAP_LIVE_53 = (
    "                    valid = True\n                    break\n       "
    "     if not valid:\n                continue\n            if to_sign"
    "al == 0.0:\n                out.append(\n                    SignalS"
    "earchData._from_si(signal, waypoint, to_signal)\n                )\n"
    "            else:\n                out.append(\n                    "
    "SignalSearchData._from_si(\n                        signal,\n       "
    "                 self.next_meters(waypoint, to_signal)[0],\n        "
    "                to_signal,\n                    )\n                )"
    "\n        if distance <= remaining:\n            return out^\n      "
    "  for candidate in self.successors(waypoint):\n"
)

comptime _MAP_OLD_53 = (
    "                    valid = True\n                    break\n       "
    "     if not valid:\n                continue\n            if to_sign"
    "al == 0.0:\n                out.append(SignalSearchData(signal, wayp"
    "oint, to_signal))\n            else:\n                out.append(\n "
    "                   SignalSearchData(\n                        signal"
    ", self.next(waypoint, to_signal)[0], to_signal\n                    "
    ")\n                )\n        if distance <= remaining:\n           "
    " return out^\n        for candidate in self.successors(waypoint):\n"
)

comptime _MAP_LIVE_54 = (
    "            var s = next_road.sections[c[1]].s\n            var star"
    "t = candidate\n            if next_road.is_positive_direction(candid"
    "ate.lane_id):\n                start.s = s\n            else:\n     "
    "           start.s = s + next_road._section_length_si(c[1])\n       "
    "     var found = self.signals_in_distance_meters(\n                s"
    "tart, distance - remaining, stop_at_junction\n            )\n       "
    "     for i in range(len(found)):\n                found[i].accumulat"
    "ed_s += remaining\n            out = _concat_signals(out^, found^)\n"
)

comptime _MAP_OLD_54 = (
    "            var s = next_road.sections[c[1]].s\n            var star"
    "t = candidate\n            if next_road.is_positive_direction(candid"
    "ate.lane_id):\n                start.s = s\n            else:\n     "
    "           start.s = s + next_road.section_length(c[1])\n           "
    " var found = self.signals_in_distance(\n                start, dista"
    "nce - remaining, stop_at_junction\n            )\n            for i "
    "in range(len(found)):\n                found[i].accumulated_s += rem"
    "aining\n            out = _concat_signals(out^, found^)\n"
)

comptime _MAP_LIVE_55 = (
    "        if to_right:\n            mark = marks_b[1].copy() if a_off "
    "else marks_a[0].copy()\n        else:\n            mark = marks_b[0]"
    ".copy() if a_off else marks_a[1].copy()\n        if Bool(mark):\n   "
    "         out.append(LaneMarking._from_si(mark.value()))\n        ret"
    "urn out^\n\n    def all_crosswalk_zones(self) raises -> List[Vector3"
    ']:\n        """Return the corners of every crosswalk, `GetAllCros'
    "swalkZones`.\n\n"
)

comptime _MAP_OLD_55 = (
    "        if to_right:\n            mark = marks_b[1].copy() if a_off "
    "else marks_a[0].copy()\n        else:\n            mark = marks_b[0]"
    ".copy() if a_off else marks_a[1].copy()\n        if Bool(mark):\n   "
    "         out.append(LaneMarking(mark.value()))\n        return out^"
    "\n\n    def all_crosswalk_zones(self) raises -> List[Vector3]:\n    "
    '    """Return the corners of every crosswalk, `GetAllCrosswalkZon'
    "es`.\n\n"
)

comptime _MAP_LIVE_56 = (
    "                        Angle(0.0, DEGREE),\n                       "
    " Angle(0.0, DEGREE),\n                        Angle(0.0, DEGREE),\n "
    "                   ),\n                )\n                for index "
    "in road._sections_at_si(crosswalk.s):\n                    var lane "
    "= road.sections[index].lane_index(LaneId(0))\n                    if"
    " lane >= 0:\n                        base = road._lane_transform_si("
    "index, lane, crosswalk.s)\n                var heading = Float32(cro"
    "sswalk.heading) * _TO_DEGREES\n                var pivot = base\n   "
    "             pivot.rotation.yaw -= heading\n                pivot.ro"
    "tation.yaw -= 90.0\n                var moved = pivot.transform_poin"
    "t(\n"
)

comptime _MAP_OLD_56 = (
    "                        Angle(0.0, DEGREE),\n                       "
    " Angle(0.0, DEGREE),\n                        Angle(0.0, DEGREE),\n "
    "                   ),\n                )\n                for index "
    "in road.sections_at(crosswalk.s):\n                    var lane = ro"
    "ad.sections[index].lane_index(LaneId(0))\n                    if lan"
    "e >= 0:\n                        base = road.lane_transform(index, l"
    "ane, crosswalk.s)\n                var heading = Float32(crosswalk.h"
    "eading) * _TO_DEGREES\n                var pivot = base\n           "
    "     pivot.rotation.yaw -= heading\n                pivot.rotation.y"
    "aw -= 90.0\n                var moved = pivot.transform_point(\n"
)

comptime _MAP_LIVE_57 = (
    "        return out^\n\n    # --- client-side helpers ---------------"
    "-------------------------------------\n\n    def next_until_lane_end"
    "(\n        self, waypoint: Waypoint, distance: Length64\n    ) raise"
    's -> List[Waypoint]:\n        """Return the next until lane end r'
    "esult with a Float64 length.\n\n        Args:\n            waypoint:"
    " The start waypoint.\n            distance: The distance or spacing,"
    " with its meter unit.\n\n        Returns:\n            The requested"
    " records with unchanged Float64 endpoint arithmetic.\n\n        Rais"
    "es:\n            Error: If the distance or the selected map records "
    'are invalid.\n        """\n        return self.next_until_lane_en'
    "d_meters(waypoint, distance.value)\n\n    def next_until_lane_end_me"
    "ters(\n        self, waypoint: Waypoint, distance: Float64\n    ) ra"
    'ises -> List[Waypoint]:\n        """Explicit meter compatibility '
    "adapter. Return waypoints every `distance` to the lane's end.\n\n   "
    "     This is the client's `Waypoint::GetNextUntilLaneEnd`: steps whi"
    "le\n        exactly one lane lies ahead on the same road, then appen"
    "ds the\n        reachable lane endpoint. It never samples a differen"
    "t road.\n\n"
)

comptime _MAP_OLD_57 = (
    "        return out^\n\n    # --- client-side helpers ---------------"
    "-------------------------------------\n\n    def next_until_lane_end"
    "(\n        self, waypoint: Waypoint, distance: Float64\n    ) raises"
    ' -> List[Waypoint]:\n        """Return waypoints every `distance`'
    " to the lane's end.\n\n        This is the client's `Waypoint::GetNe"
    "xtUntilLaneEnd`: steps while\n        exactly one lane lies ahead on"
    " the same road, then appends the\n        reachable lane endpoint. I"
    "t never samples a different road.\n\n"
)

comptime _MAP_LIVE_58 = (
    '                EPSILON, or a step cannot advance.\n        """\n'
    "        return self._until_end(waypoint, distance, True)\n\n    def "
    "previous_until_lane_start(\n        self, waypoint: Waypoint, distan"
    'ce: Length64\n    ) raises -> List[Waypoint]:\n        """Return '
    "the previous until lane start result with a Float64 length.\n\n     "
    "   Args:\n            waypoint: The start waypoint.\n            dis"
    "tance: The distance or spacing, with its meter unit.\n\n        Retu"
    "rns:\n            The requested records with unchanged Float64 endpo"
    "int arithmetic.\n\n        Raises:\n            Error: If the distan"
    'ce or the selected map records are invalid.\n        """\n       '
    " return self.previous_until_lane_start_meters(waypoint, distance.val"
    "ue)\n\n    def previous_until_lane_start_meters(\n        self, wayp"
    "oint: Waypoint, distance: Float64\n    ) raises -> List[Waypoint]:\n"
    '        """Explicit meter compatibility adapter. Return waypoints'
    " every `distance` back to the lane's start.\n\n        This corrects"
    " the client's `Waypoint::GetPreviousUntilLaneStart`:\n        the la"
    "st step measures what is left in the requested backward\n        dir"
    "ection and stays on the starting road.\n\n"
)

comptime _MAP_OLD_58 = (
    '                EPSILON, or a step cannot advance.\n        """\n'
    "        return self._until_end(waypoint, distance, True)\n\n    def "
    "previous_until_lane_start(\n        self, waypoint: Waypoint, distan"
    'ce: Float64\n    ) raises -> List[Waypoint]:\n        """Return w'
    "aypoints every `distance` back to the lane's start.\n\n        This "
    "corrects the client's `Waypoint::GetPreviousUntilLaneStart`:\n      "
    "  the last step measures what is left in the requested backward\n   "
    "     direction and stays on the starting road.\n\n"
)

comptime _MAP_LIVE_59 = (
    "    def _until_end(\n        self, waypoint: Waypoint, distance: Flo"
    "at64, ahead: Bool\n    ) raises -> List[Waypoint]:\n        if not i"
    "sfinite(distance) or distance <= EPSILON:\n            raise Error("
    '"Lane traversal needs a finite spacing above EPSILON")\n        if'
    " not isfinite(waypoint.s) or waypoint.s < 0.0:\n            raise Er"
    'ror("Waypoint is outside its lane section")\n        var initial ='
    " self._locate(waypoint)\n        ref road = self.roads[initial[0]]\n"
    "        var section_start = road.sections[initial[1]].s\n        var"
    " section_end = section_start + road._section_length_si(initial[1])\n"
    "        var s = waypoint.s\n        if s < section_start or s > sect"
    'ion_end:  # s is finite (see above).\n            raise Error("Wayp'
    'oint is outside its lane section")\n        var forward = road.is_p'
    "ositive_direction(waypoint.lane_id) == ahead\n        # Locate the r"
    "eachable end before sampling. Never walk through a\n        # differ"
    "ent road just to discover that a large interval overshoots.\n       "
    " var end = waypoint\n"
)

comptime _MAP_OLD_59 = (
    "    def _until_end(\n        self, waypoint: Waypoint, distance: Flo"
    "at64, ahead: Bool\n    ) raises -> List[Waypoint]:\n        if not i"
    "sfinite(distance) or distance <= EPSILON:\n            raise Error("
    '"Lane traversal needs a finite spacing above EPSILON")\n        va'
    "r initial = self._locate(waypoint)\n        ref road = self.roads[in"
    "itial[0]]\n        var section_start = road.sections[initial[1]].s\n"
    "        var section_end = section_start + road.section_length(initia"
    "l[1])\n        var s = waypoint.s\n        if not isfinite(s) or s <"
    ' section_start or s > section_end:\n            raise Error("Waypoi'
    'nt is outside its lane section")\n        var forward = road.is_pos'
    "itive_direction(waypoint.lane_id) == ahead\n        # Locate the rea"
    "chable end before sampling. Never walk through a\n        # differen"
    "t road just to discover that a large interval overshoots.\n        v"
    "ar end = waypoint\n"
)

comptime _MAP_LIVE_60 = (
    "            .copy() if self.road(waypoint.road_id)\n            .is_"
    "rht else marks[1]\n            .copy()\n        )\n        if Bool(m"
    "ark):\n            return LaneMarking._from_si(mark.value())\n      "
    "  return None\n\n    def left_lane_marking(\n        self, waypoint:"
    " Waypoint\n    ) raises -> Optional[LaneMarking]:\n"
)

comptime _MAP_OLD_60 = (
    "            .copy() if self.road(waypoint.road_id)\n            .is_"
    "rht else marks[1]\n            .copy()\n        )\n        if Bool(m"
    "ark):\n            return LaneMarking(mark.value())\n        return "
    "None\n\n    def left_lane_marking(\n        self, waypoint: Waypoint"
    "\n    ) raises -> Optional[LaneMarking]:\n"
)

comptime _MAP_LIVE_61 = (
    "            .copy() if self.road(waypoint.road_id)\n            .is_"
    "rht else marks[0]\n            .copy()\n        )\n        if Bool(m"
    "ark):\n            return LaneMarking._from_si(mark.value())\n      "
    "  return None\n\n    def lane_change(self, waypoint: Waypoint) raise"
    's -> LaneChange:\n        """Return where a vehicle may change la'
    "nes, `Waypoint::GetLaneChange`.\n\n"
)

comptime _MAP_OLD_61 = (
    "            .copy() if self.road(waypoint.road_id)\n            .is_"
    "rht else marks[0]\n            .copy()\n        )\n        if Bool(m"
    "ark):\n            return LaneMarking(mark.value())\n        return "
    "None\n\n    def lane_change(self, waypoint: Waypoint) raises -> Lane"
    'Change:\n        """Return where a vehicle may change lanes, `Way'
    "point::GetLaneChange`.\n\n"
)

comptime _MAP_LIVE_62 = (
    "        if beside < 0:\n            c_left = _swap(c_left)\n        "
    "return (c_right & CHANGE_RIGHT) | (c_left & CHANGE_LEFT)\n\n    def "
    "landmarks_in_distance(\n        self,\n        waypoint: Waypoint,\n"
    "        distance: Length64,\n        stop_at_junction: Bool = False,"
    '\n    ) raises -> List[Landmark]:\n        """Return the landmark'
    "s in distance result with a Float64 length.\n\n        Args:\n      "
    "      waypoint: The start waypoint.\n            distance: The dista"
    "nce or spacing, with its meter unit.\n            stop_at_junction: "
    "Whether to stop at a junction.\n\n        Returns:\n            The "
    "requested records with unchanged Float64 endpoint arithmetic.\n\n   "
    "     Raises:\n            Error: If the distance or the selected map"
    ' records are invalid.\n        """\n        return self.landmarks'
    "_in_distance_meters(\n            waypoint, distance.value, stop_at_"
    "junction\n        )\n\n    def landmarks_in_distance_meters(\n      "
    "  self,\n        waypoint: Waypoint,\n        distance: Float64,\n  "
    "      stop_at_junction: Bool = False,\n    ) raises -> List[Landmark"
    ']:\n        """Explicit meter compatibility adapter. Return the l'
    "andmarks ahead, `GetAllLandmarksInDistance`.\n\n        Each signal "
    "reference comes once, at its first find.\n\n        Args:\n         "
    "   waypoint: The start.\n"
)

comptime _MAP_OLD_62 = (
    "        if beside < 0:\n            c_left = _swap(c_left)\n        "
    "return (c_right & CHANGE_RIGHT) | (c_left & CHANGE_LEFT)\n\n    def "
    "landmarks_in_distance(\n        self,\n        waypoint: Waypoint,\n"
    "        distance: Float64,\n        stop_at_junction: Bool = False,"
    '\n    ) raises -> List[Landmark]:\n        """Return the landmark'
    "s ahead, `GetAllLandmarksInDistance`.\n\n        Each signal referen"
    "ce comes once, at its first find.\n\n        Args:\n            wayp"
    "oint: The start.\n"
)

comptime _MAP_LIVE_63 = (
    "\n        Raises:\n            Error: If the lane is not in the map."
    '\n        """\n        var out = List[Landmark]()\n        for da'
    "ta in self.signals_in_distance_meters(\n            waypoint, distan"
    "ce, stop_at_junction\n        ):\n            var seen = False\n    "
    "        for landmark in out:\n                if _same_reference(lan"
    "dmark.reference, data.signal):\n                    seen = True\n   "
    "         if seen:\n                continue\n            out.append("
    "\n                Landmark._from_si(\n                    data.waypo"
    "int, data.signal, data.accumulated_s\n                )\n           "
    " )\n        return out^\n\n    def landmarks_of_type_in_distance(\n "
    "       self,\n        waypoint: Waypoint,\n        distance: Length6"
    "4,\n        type: String,\n        stop_at_junction: Bool = False,\n"
    '    ) raises -> List[Landmark]:\n        """Return the landmarks '
    "of type in distance result with a Float64 length.\n\n        Args:\n"
    "            waypoint: The start waypoint.\n            distance: The"
    " distance or spacing, with its meter unit.\n            type: The si"
    "gnal type to keep.\n            stop_at_junction: Whether to stop at"
    " a junction.\n\n        Returns:\n            The requested records "
    "with unchanged Float64 endpoint arithmetic.\n\n        Raises:\n    "
    "        Error: If the distance or the selected map records are inval"
    'id.\n        """\n        return self.landmarks_of_type_in_distan'
    "ce_meters(\n            waypoint, distance.value, type, stop_at_junc"
    "tion\n        )\n\n    def landmarks_of_type_in_distance_meters(\n  "
    "      self,\n        waypoint: Waypoint,\n        distance: Float64,"
    "\n        type: String,\n        stop_at_junction: Bool = False,\n  "
    '  ) raises -> List[Landmark]:\n        """Explicit meter compatib'
    "ility adapter. Return the landmarks of one type ahead.\n\n        Th"
    "is is `GetLandmarksOfTypeInDistance`. CARLA checks for repeats\n    "
    "    but never records one, so a reference found twice comes twice.\n"
    "\n        Args:\n"
)

comptime _MAP_OLD_63 = (
    "\n        Raises:\n            Error: If the lane is not in the map."
    '\n        """\n        var out = List[Landmark]()\n        for da'
    "ta in self.signals_in_distance(\n            waypoint, distance, sto"
    "p_at_junction\n        ):\n            var seen = False\n           "
    " for landmark in out:\n                if _same_reference(landmark.r"
    "eference, data.signal):\n                    seen = True\n          "
    "  if seen:\n                continue\n            out.append(Landmar"
    "k(data.waypoint, data.signal, data.accumulated_s))\n        return o"
    "ut^\n\n    def landmarks_of_type_in_distance(\n        self,\n      "
    "  waypoint: Waypoint,\n        distance: Float64,\n        type: Str"
    "ing,\n        stop_at_junction: Bool = False,\n    ) raises -> List["
    'Landmark]:\n        """Return the landmarks of one type ahead.\n'
    "\n        This is `GetLandmarksOfTypeInDistance`. CARLA checks for r"
    "epeats\n        but never records one, so a reference found twice co"
    "mes twice.\n\n        Args:\n"
)

comptime _MAP_LIVE_64 = (
    "\n        Raises:\n            Error: If the lane is not in the map "
    'or a signal is missing.\n        """\n        var out = List[Land'
    "mark]()\n        for data in self.signals_in_distance_meters(\n     "
    "       waypoint, distance, stop_at_junction\n        ):\n           "
    " if self.signal(data.signal.signal_id).type == type:\n              "
    "  out.append(\n                    Landmark._from_si(\n             "
    "           data.waypoint, data.signal, data.accumulated_s\n         "
    "           )\n                )\n        return out^\n\n    def all_"
    'landmarks(self) -> List[Landmark]:\n        """Return every signa'
    "l reference as a landmark, `GetAllLandmarks`.\n"
)

comptime _MAP_OLD_64 = (
    "\n        Raises:\n            Error: If the lane is not in the map "
    'or a signal is missing.\n        """\n        var out = List[Land'
    "mark]()\n        for data in self.signals_in_distance(\n            "
    "waypoint, distance, stop_at_junction\n        ):\n            if sel"
    "f.signal(data.signal.signal_id).type == type:\n                out.a"
    "ppend(\n                    Landmark(data.waypoint, data.signal, dat"
    "a.accumulated_s)\n                )\n        return out^\n\n    def "
    'all_landmarks(self) -> List[Landmark]:\n        """Return every s'
    "ignal reference as a landmark, `GetAllLandmarks`.\n"
)

comptime _MAP_LIVE_65 = (
    "        Returns:\n            The landmarks, with no waypoint and di"
    'stance 0.\n        """\n        var out = List[Landmark]()\n     '
    "   for reference in self.all_signal_references():\n            out.a"
    "ppend(Landmark._from_si(None, reference, 0.0))\n        return out^"
    "\n\n    def landmarks_from_id(self, id: SignalId) raises -> List[Lan"
    'dmark]:\n        """Return the references to one signal, `GetLand'
    "marksFromId`.\n\n"
)

comptime _MAP_OLD_65 = (
    "        Returns:\n            The landmarks, with no waypoint and di"
    'stance 0.\n        """\n        var out = List[Landmark]()\n     '
    "   for reference in self.all_signal_references():\n            out.a"
    "ppend(Landmark(None, reference, 0.0))\n        return out^\n\n    de"
    "f landmarks_from_id(self, id: SignalId) raises -> List[Landmark]:\n "
    '       """Return the references to one signal, `GetLandmarksFromI'
    "d`.\n\n"
)

comptime _MAP_LIVE_66 = (
    '        if not id.is_valid():\n            raise Error("Signal id i'
    's not valid")\n        var out = List[Landmark]()\n        for refe'
    "rence in self.all_signal_references():\n            if reference.sig"
    "nal_id == id:\n                out.append(Landmark._from_si(None, re"
    "ference, 0.0))\n        return out^\n\n    def all_landmarks_of_type"
    '(self, type: String) raises -> List[Landmark]:\n        """Return'
    " the references to signals of one type.\n\n"
)

comptime _MAP_OLD_66 = (
    '        if not id.is_valid():\n            raise Error("Signal id i'
    's not valid")\n        var out = List[Landmark]()\n        for refe'
    "rence in self.all_signal_references():\n            if reference.sig"
    "nal_id == id:\n                out.append(Landmark(None, reference, "
    "0.0))\n        return out^\n\n    def all_landmarks_of_type(self, ty"
    'pe: String) raises -> List[Landmark]:\n        """Return the refe'
    "rences to signals of one type.\n\n"
)

comptime _MAP_LIVE_67 = (
    "            Error: If a reference names a signal the map lacks.\n   "
    '     """\n        var out = List[Landmark]()\n        for referen'
    "ce in self.all_signal_references():\n            if self.signal(refe"
    "rence.signal_id).type == type:\n                out.append(Landmark."
    "_from_si(None, reference, 0.0))\n        return out^\n\n    def land"
    "mark_group(self, landmark: Landmark) raises -> List[Landmark]:\n    "
    '    """Return the landmarks of the signals that share a controlle'
    "r.\n\n"
)

comptime _MAP_OLD_67 = (
    "            Error: If a reference names a signal the map lacks.\n   "
    '     """\n        var out = List[Landmark]()\n        for referen'
    "ce in self.all_signal_references():\n            if self.signal(refe"
    "rence.signal_id).type == type:\n                out.append(Landmark("
    "None, reference, 0.0))\n        return out^\n\n    def landmark_grou"
    'p(self, landmark: Landmark) raises -> List[Landmark]:\n        ""'
    '"Return the landmarks of the signals that share a controller.\n\n'
)

comptime _MAP_LIVE_68 = (
    '            raise Error("A step needs a positive distance")\n     '
    "   if distance <= EPSILON:\n            return waypoint\n        var"
    " at = self._build_locate(waypoint)\n        self._construction_work."
    "step(len(self.roads[at[0]].sections))\n        var length = self.roa"
    "ds[at[0]]._section_length_si(at[1])\n        var start = self.roads["
    "at[0]].sections[at[1]].s\n        var forward = self.roads[at[0]].is"
    "_positive_direction(waypoint.lane_id)\n        var relative = waypoi"
    "nt.s - start\n        var remaining = length - relative if forward e"
    "lse relative\n        if distance > remaining:\n"
)

comptime _MAP_OLD_68 = (
    '            raise Error("A step needs a positive distance")\n     '
    "   if distance <= EPSILON:\n            return waypoint\n        var"
    " at = self._build_locate(waypoint)\n        self._construction_work."
    "step(len(self.roads[at[0]].sections))\n        var length = self.roa"
    "ds[at[0]].section_length(at[1])\n        var start = self.roads[at[0"
    "]].sections[at[1]].s\n        var forward = self.roads[at[0]].is_pos"
    "itive_direction(waypoint.lane_id)\n        var relative = waypoint.s"
    " - start\n        var remaining = length - relative if forward else "
    "relative\n        if distance > remaining:\n"
)

comptime _MAP_LIVE_69 = (
    '        if terms < 0:\n            raise Error("Map construction ca'
    'nnot resolve pose quadrature work")\n        self._construction_wor'
    "k.step()\n        self._construction_work.term(terms)\n        self."
    "_construction_work.term(terms)\n        return self.roads[at[0]]._la"
    "ne_transform_si(at[1], at[2], waypoint.s)\n\n    def _reserve_build_"
    "point(\n        mut self, road: Int, section: Int, s: Float64\n    )"
    " raises:\n        _reserve_lane_scalars(\n"
)

comptime _MAP_OLD_69 = (
    '        if terms < 0:\n            raise Error("Map construction ca'
    'nnot resolve pose quadrature work")\n        self._construction_wor'
    "k.step()\n        self._construction_work.term(terms)\n        self."
    "_construction_work.term(terms)\n        return self.roads[at[0]].lan"
    "e_transform(at[1], at[2], waypoint.s)\n\n    def _reserve_build_poin"
    "t(\n        mut self, road: Int, section: Int, s: Float64\n    ) rai"
    "ses:\n        _reserve_lane_scalars(\n"
)

comptime _MAP_LIVE_70 = (
    "                b.location,\n                first,\n               "
    " second,\n                certificate[1],\n                cover_ind"
    "ex,\n                certificate[0],\n            )\n        )\n    "
    "    self._curve_deviation = max(self._curve_deviation, certificate[0"
    "])\n        self._endpoint_scale = max(\n            self._endpoint_"
    "scale,\n"
)

comptime _MAP_OLD_70 = (
    "                b.location,\n                first,\n               "
    " second,\n                certificate[1],\n                cover_ind"
    "ex,\n            )\n        )\n        self._curve_deviation = max(s"
    "elf._curve_deviation, certificate[0])\n        self._endpoint_scale "
    "= max(\n            self._endpoint_scale,\n"
)

comptime _MAP_LIVE_71 = (
    "                        continue\n                    self._construc"
    "tion_work.step_product(\n                        2, len(self.roads[r"
    "].sections)\n                    )\n                    starts.appen"
    "d(\n                        Waypoint._from_si(\n                    "
    "        self.roads[r].id,\n                            section.id,\n"
    "                            section.lanes[ln].id,\n                 "
    "           self._start_of_lane(r, sec, ln),\n                       "
    " )\n"
)

comptime _MAP_OLD_71 = (
    "                        continue\n                    self._construc"
    "tion_work.step_product(\n                        2, len(self.roads[r"
    "].sections)\n                    )\n                    starts.appen"
    "d(\n                        Waypoint(\n                            s"
    "elf.roads[r].id,\n                            section.id,\n         "
    "                   section.lanes[ln].id,\n                          "
    "  self._start_of_lane(r, sec, ln),\n                        )\n"
)

comptime _MAP_LIVE_72 = (
    "            var at = self._build_locate(start)\n            var curr"
    "ent = start\n            var current_t = self._build_transform(curre"
    "nt)\n            var lane_start = self.roads[at[0]].sections[at[1]]."
    "s\n            self._construction_work.step(len(self.roads[at[0]].se"
    "ctions))\n            var lane_end = lane_start + self.roads[at[0]]."
    "_section_length_si(\n                at[1]\n            )\n         "
    "   var positive = self.roads[at[0]].is_positive_direction(\n        "
    "        start.lane_id\n            )\n            _reserve_straightn"
    "ess(\n                self.roads[at[0]], at[1], self._construction_w"
    "ork\n"
)

comptime _MAP_OLD_72 = (
    "            var at = self._build_locate(start)\n            var curr"
    "ent = start\n            var current_t = self._build_transform(curre"
    "nt)\n            var lane_start = self.roads[at[0]].sections[at[1]]."
    "s\n            self._construction_work.step(len(self.roads[at[0]].se"
    "ctions))\n            var lane_end = lane_start + self.roads[at[0]]."
    "section_length(at[1])\n            var positive = self.roads[at[0]]."
    "is_positive_direction(\n                start.lane_id\n            )"
    "\n            _reserve_straightness(\n                self.roads[at["
    "0]], at[1], self._construction_work\n"
)

comptime _BUILDER_LIVE_0 = (
    "    LINE,\n    NORMALIZED,\n    RoadGeometry,\n    with_arc_si as wi"
    "th_arc,\n    with_param_poly3_from_coefficients as with_param_poly3,"
    "\n    NormalizedCubic,\n    with_poly3_si as with_poly3,\n    with_s"
    "piral_si as with_spiral,\n)\nfrom extensions.carla.map import (\n   "
    " Connection,\n"
)

comptime _BUILDER_OLD_0 = (
    "    LINE,\n    NORMALIZED,\n    RoadGeometry,\n    with_arc,\n    wi"
    "th_param_poly3,\n    with_poly3,\n    with_spiral,\n)\nfrom extensio"
    "ns.carla.map import (\n    Connection,\n"
)

comptime _BUILDER_LIVE_1 = (
    "from extensions.carla.transform import CarlaRotation, CarlaTransform"
    "\nfrom math.bounds import Box3\nfrom math.vector3 import Vector3\nfr"
    "om units.si import (\n    DEGREE,\n    Angle,\n    Length,\n    METE"
    "R,\n    Length64,\n    Angle64,\n    InverseLength64,\n    InverseAr"
    "ea64,\n    Velocity64,\n)\nfrom extensions.carla.quantity_boundary i"
    "mport (\n    _finite_si,\n    _nonnegative_si,\n    _positive_si,\n)"
    "\n\ncomptime _FLOAT_MAX = Float32(3.4028234663852886e38)\ncomptime _"
    "TO_DEGREES = Float32(180.0) / Float32(3.14159265358979323846)\n"
)

comptime _BUILDER_OLD_1 = (
    "from extensions.carla.transform import CarlaRotation, CarlaTransform"
    "\nfrom math.bounds import Box3\nfrom math.vector3 import Vector3\nfr"
    "om units.si import DEGREE, Angle, Length, METER\n\ncomptime _FLOAT_M"
    "AX = Float32(3.4028234663852886e38)\ncomptime _TO_DEGREES = Float32("
    "180.0) / Float32(3.14159265358979323846)\n"
)

comptime _BUILDER_LIVE_2 = (
    "    # --- roads and lanes ------------------------------------------"
    "------------\n\n    def add_road(\n        mut self,\n        id: Ro"
    "adId,\n        name: String,\n        length: Length64,\n        jun"
    "ction_id: JuncId,\n        predecessor: RoadId,\n        successor: "
    'RoadId,\n        is_rht: Bool,\n    ) raises -> Int:\n        """'
    "Checked typed boundary. Add a road, `AddRoad`. A second road with th"
    "e same id resets the\n        first's fields, as CARLA's `emplace` a"
    "nd assignments do.\n\n        Args:\n            id: The road's id."
    "\n            name: Its name.\n            length: Its length, in me"
    "ters.\n            junction_id: Its junction, or `NO_JUNCTION`.\n   "
    "         predecessor: The road or junction before it, 0 for none.\n "
    "           successor: The road or junction after it, 0 for none.\n  "
    "          is_rht: True if traffic keeps to the right.\n\n        Ret"
    "urns:\n            The road's index in `roads`.\n\n        Raises:\n"
    '            Error: If an id is not valid.\n        """\n        r'
    "eturn self.add_road_si(\n            id, name, length.value, junctio"
    "n_id, predecessor, successor, is_rht\n        )\n\n    def add_road_"
    "si(\n        mut self,\n        id: RoadId,\n        name: String,\n"
)

comptime _BUILDER_OLD_2 = (
    "    # --- roads and lanes ------------------------------------------"
    "------------\n\n    def add_road(\n        mut self,\n        id: Ro"
    "adId,\n        name: String,\n"
)

comptime _BUILDER_LIVE_3 = (
    "        successor: RoadId,\n        is_rht: Bool,\n    ) raises -> I"
    'nt:\n        """Explicit source-unit compatibility adapter. Add a'
    " road, `AddRoad`. A second road with the same id resets the\n       "
    " first's fields, as CARLA's `emplace` and assignments do.\n\n       "
    " Args:\n"
)

comptime _BUILDER_OLD_3 = (
    "        successor: RoadId,\n        is_rht: Bool,\n    ) raises -> I"
    'nt:\n        """Add a road, `AddRoad`. A second road with the sam'
    "e id resets the\n        first's fields, as CARLA's `emplace` and as"
    "signments do.\n\n        Args:\n"
)

comptime _BUILDER_LIVE_4 = (
    "        Raises:\n            Error: If an id is not valid.\n        "
    '"""\n        _ = _positive_si(length)\n\n        var road = Road.'
    "_from_si(\n            id, name, length, junction_id, predecessor, s"
    "uccessor, is_rht\n        )\n        for i in range(len(self.roads))"
    ":\n"
)

comptime _BUILDER_OLD_4 = (
    "        Raises:\n            Error: If an id is not valid.\n        "
    '"""\n        var road = Road(\n            id, name, length, junc'
    "tion_id, predecessor, successor, is_rht\n        )\n        for i in"
    " range(len(self.roads)):\n"
)

comptime _BUILDER_LIVE_5 = (
    '        raise Error("The builder has no road with that id")\n\n   '
    " def add_road_section(\n        mut self, road: Int, id: SectionId, "
    's: Length64\n    ) raises -> Int:\n        """Checked typed bound'
    "ary. Add a lane section, `AddRoadSection`.\n\n        Args:\n       "
    "     road: The road's index.\n            id: The section's id.\n   "
    "         s: Where it starts, in meters.\n\n        Returns:\n       "
    "     The section's index in the road.\n\n        Raises:\n          "
    '  Error: If the id is not valid.\n        """\n        return sel'
    "f.add_road_section_si(road, id, s.value)\n\n    def add_road_section"
    "_si(\n        mut self, road: Int, id: SectionId, s: Float64\n    ) "
    'raises -> Int:\n        """Explicit source-unit compatibility ada'
    "pter. Add a lane section, `AddRoadSection`.\n\n        Args:\n      "
    "      road: The road's index.\n"
)

comptime _BUILDER_OLD_5 = (
    '        raise Error("The builder has no road with that id")\n\n   '
    " def add_road_section(\n        mut self, road: Int, id: SectionId, "
    's: Float64\n    ) raises -> Int:\n        """Add a lane section, '
    "`AddRoadSection`.\n\n        Args:\n            road: The road's ind"
    "ex.\n"
)

comptime _BUILDER_LIVE_6 = (
    "        Raises:\n            Error: If the id is not valid.\n       "
    ' """\n        _ = _nonnegative_si(s)\n\n        return self.roads'
    "[road]._add_section_si(id, s)\n\n    def add_road_section_lane(\n   "
    "     mut self,\n"
)

comptime _BUILDER_OLD_6 = (
    "        Raises:\n            Error: If the id is not valid.\n       "
    ' """\n        return self.roads[road].add_section(id, s)\n\n    d'
    "ef add_road_section_lane(\n        mut self,\n"
)

comptime _BUILDER_LIVE_7 = (
    "        return LaneKey(self.roads[road].id, s.id, lane_id)\n\n    de"
    "f lane(\n        self, road_id: RoadId, lane_id: LaneId, s: Length64"
    '\n    ) raises -> Tuple[Int, Int, Int]:\n        """Checked typed'
    " boundary. Return the lane with an id at s, `MapBuilder::GetLane`.\n"
    "\n        Args:\n            road_id: The road.\n            lane_id"
    ": The lane.\n            s: A distance along the road, in meters.\n"
    "\n        Returns:\n            The road's index, the section's inde"
    "x and the lane's index.\n\n        Raises:\n            Error: If th"
    'ere is no such road or lane.\n        """\n        return self.la'
    "ne_si(road_id, lane_id, s.value)\n\n    def lane_si(\n        self, "
    "road_id: RoadId, lane_id: LaneId, s: Float64\n    ) raises -> Tuple["
    'Int, Int, Int]:\n        """Explicit source-unit compatibility ad'
    "apter. Return the lane with an id at s, `MapBuilder::GetLane`.\n\n  "
    "      Args:\n            road_id: The road.\n"
)

comptime _BUILDER_OLD_7 = (
    "        return LaneKey(self.roads[road].id, s.id, lane_id)\n\n    de"
    "f lane(\n        self, road_id: RoadId, lane_id: LaneId, s: Float64"
    '\n    ) raises -> Tuple[Int, Int, Int]:\n        """Return the la'
    "ne with an id at s, `MapBuilder::GetLane`.\n\n        Args:\n       "
    "     road_id: The road.\n"
)

comptime _BUILDER_LIVE_8 = (
    "        Raises:\n            Error: If there is no such road or lane"
    '.\n        """\n        _ = _nonnegative_si(s)\n\n        var r ='
    " self.road_index(road_id)\n        var found = self.roads[r]._lane_b"
    "y_distance_si(s, lane_id)\n        return (r, found[0], found[1])\n"
    "\n    # --- lane records -------------------------------------------"
    "--------------\n\n    def create_lane_width(\n        mut self,\n   "
    "     lane: Tuple[Int, Int, Int],\n        s: Length64,\n        a: L"
    "ength64,\n        b: Float64,\n        c: InverseLength64,\n        "
    'd: InverseArea64,\n    ) raises:\n        """Checked typed bounda'
    "ry. Add a width record, `CreateLaneWidth`.\n\n        Args:\n       "
    "     lane: The lane, from `lane`.\n            s: Where the record s"
    "tarts, in meters along the road.\n            a: The width at s, in "
    "meters.\n            b: Its rate of change.\n            c: The quad"
    "ratic term, per meter.\n            d: The cubic term, per square me"
    "ter.\n\n        Raises:\n            Error: If the station is nonfin"
    "ite or negative, or any polynomial\n                coefficient is n"
    'onfinite.\n        """\n        self.create_lane_width_si(lane, s'
    ".value, a.value, b, c.value, d.value)\n\n    def create_lane_width_s"
    "i(\n        mut self,\n        lane: Tuple[Int, Int, Int],\n        "
    "s: Float64,\n"
)

comptime _BUILDER_OLD_8 = (
    "        Raises:\n            Error: If there is no such road or lane"
    '.\n        """\n        var r = self.road_index(road_id)\n       '
    " var found = self.roads[r].lane_by_distance(s, lane_id)\n        ret"
    "urn (r, found[0], found[1])\n\n    # --- lane records --------------"
    "-------------------------------------------\n\n    def create_lane_w"
    "idth(\n        mut self,\n        lane: Tuple[Int, Int, Int],\n     "
    "   s: Float64,\n"
)

comptime _BUILDER_LIVE_9 = (
    "        b: Float64,\n        c: Float64,\n        d: Float64,\n    )"
    ' raises:\n        """Explicit source-unit compatibility adapter. '
    "Add a width record, `CreateLaneWidth`.\n\n        Args:\n           "
    " lane: The lane, from `lane`.\n"
)

comptime _BUILDER_OLD_9 = (
    "        b: Float64,\n        c: Float64,\n        d: Float64,\n    )"
    ':\n        """Add a width record, `CreateLaneWidth`.\n\n        A'
    "rgs:\n            lane: The lane, from `lane`.\n"
)

comptime _BUILDER_LIVE_10 = (
    "            b: Its rate of change.\n            c: The quadratic ter"
    "m, per meter.\n            d: The cubic term, per square meter.\n\n "
    "       Raises:\n            Error: If the station is nonfinite or ne"
    "gative, or any polynomial\n                coefficient is nonfinite."
    '\n        """\n        _ = _nonnegative_si(s)\n        _ = _finit'
    "e_si(a)\n        _ = _finite_si(c)\n        _ = _finite_si(d)\n\n   "
    "     self._lane(lane).info.widths.append(\n            RoadInfoLaneW"
    "idth._from_si(\n                s, CubicPolynomial.from_coefficients"
    "(a, b, c, d, s)\n            )\n        )\n\n    def create_lane_bor"
    "der(\n        mut self,\n        lane: Tuple[Int, Int, Int],\n      "
    "  s: Length64,\n        a: Length64,\n        b: Float64,\n        c"
    ": InverseLength64,\n        d: InverseArea64,\n    ) raises:\n      "
    '  """Checked typed boundary. Add a border record, `CreateLaneBord'
    "er`.\n\n        Args:\n            lane: The lane.\n            s: W"
    "here the record starts, in meters along the road.\n            a: Th"
    "e border's offset at s, in meters.\n            b: Its rate of chang"
    "e.\n            c: The quadratic term, per meter.\n            d: Th"
    "e cubic term, per square meter.\n\n        Raises:\n            Erro"
    "r: If the station is nonfinite or negative, or any polynomial\n     "
    '           coefficient is nonfinite.\n        """\n        self.c'
    "reate_lane_border_si(lane, s.value, a.value, b, c.value, d.value)\n"
    "\n    def create_lane_border_si(\n        mut self,\n        lane: T"
    "uple[Int, Int, Int],\n        s: Float64,\n"
)

comptime _BUILDER_OLD_10 = (
    "            b: Its rate of change.\n            c: The quadratic ter"
    "m, per meter.\n            d: The cubic term, per square meter.\n   "
    '     """\n        self._lane(lane).info.widths.append(\n         '
    "   RoadInfoLaneWidth(s, CubicPolynomial(a, b, c, d, s))\n        )\n"
    "\n    def create_lane_border(\n        mut self,\n        lane: Tupl"
    "e[Int, Int, Int],\n        s: Float64,\n"
)

comptime _BUILDER_LIVE_11 = (
    "        b: Float64,\n        c: Float64,\n        d: Float64,\n    )"
    ' raises:\n        """Explicit source-unit compatibility adapter. '
    "Add a border record, `CreateLaneBorder`.\n\n        Args:\n         "
    "   lane: The lane.\n"
)

comptime _BUILDER_OLD_11 = (
    "        b: Float64,\n        c: Float64,\n        d: Float64,\n    )"
    ':\n        """Add a border record, `CreateLaneBorder`.\n\n       '
    " Args:\n            lane: The lane.\n"
)

comptime _BUILDER_LIVE_12 = (
    "            b: Its rate of change.\n            c: The quadratic ter"
    "m, per meter.\n            d: The cubic term, per square meter.\n\n "
    "       Raises:\n            Error: If the station is nonfinite or ne"
    "gative, or any polynomial\n                coefficient is nonfinite."
    '\n        """\n        _ = _nonnegative_si(s)\n        _ = _finit'
    "e_si(a)\n        _ = _finite_si(c)\n        _ = _finite_si(d)\n\n   "
    "     self._lane(lane).info.borders.append(\n            RoadInfoLane"
    "Border._from_si(\n                s, CubicPolynomial.from_coefficien"
    "ts(a, b, c, d, s)\n            )\n        )\n\n    def create_lane_b"
    "order_opendrive(\n        mut self,\n        lane: Tuple[Int, Int, I"
    "nt],\n        s: Float64,\n        a: Float64,\n        b: Float64,"
    "\n        c: Float64,\n        d: Float64,\n    ) raises:\n        "
    '"""Retain a finite border polynomial from explicit OpenDRIVE unit'
    "s.\n\n        A source record can begin before its lane section. Its"
    " signed origin\n        is retained; the parser clips derived width "
    "pieces to the section.\n        The typed construction route keeps i"
    "ts nonnegative station contract.\n\n        Args:\n            lane:"
    " The destination lane.\n            s: The signed source polynomial "
    "origin, in meters along the road.\n            a: The signed border "
    "offset at the origin, in meters.\n            b: The dimensionless l"
    "inear coefficient.\n            c: The quadratic coefficient, per me"
    "ter.\n            d: The cubic coefficient, per square meter.\n\n   "
    "     Raises:\n            Error: If the origin or any coefficient is"
    ' nonfinite.\n        """\n        _ = _finite_si(s)\n        var '
    "polynomial = CubicPolynomial.from_coefficients(a, b, c, d, s)\n     "
    "   self._lane(lane).info.borders.append(\n            RoadInfoLaneBo"
    "rder._from_si(s, polynomial)\n        )\n\n    def create_lane_heigh"
    "t(\n        mut self,\n        lane: Tuple[Int, Int, Int],\n        "
    "s: Length64,\n        inner: Length64,\n        outer: Length64,\n  "
    '  ) raises:\n        """Checked typed boundary. Add a height reco'
    "rd, `CreateLaneHeight`.\n\n        Args:\n            lane: The lane"
    ".\n            s: Where the record starts, in meters along the road."
    "\n            inner: The lift at the inner edge, in meters.\n       "
    "     outer: The lift at the outer edge, in meters.\n\n        Raises"
    ":\n            Error: If the station is nonfinite or negative, or ei"
    'ther height\n                is nonfinite.\n        """\n        '
    "self.create_lane_height_si(lane, s.value, inner.value, outer.value)"
    "\n\n    def create_lane_height_si(\n        mut self,\n        lane:"
    " Tuple[Int, Int, Int],\n        s: Float64,\n        inner: Float64,"
    '\n        outer: Float64,\n    ) raises:\n        """Explicit sou'
    "rce-unit compatibility adapter. Add a height record, `CreateLaneHeig"
    "ht`.\n\n        Args:\n            lane: The lane.\n            s: W"
    "here the record starts, in meters along the road.\n            inner"
    ": The lift at the inner edge, in meters.\n            outer: The lif"
    "t at the outer edge, in meters.\n\n        Raises:\n            Erro"
    "r: If the station is nonfinite or negative, or either height\n      "
    '          is nonfinite.\n        """\n        _ = _nonnegative_si'
    "(s)\n        _ = _finite_si(inner)\n        _ = _finite_si(outer)\n"
    "\n        self._lane(lane).info.heights.append(\n            RoadInf"
    "oLaneHeight._from_si(s, inner, outer)\n        )\n\n    def create_l"
    "ane_material(\n        mut self,\n        lane: Tuple[Int, Int, Int]"
    ",\n        s: Length64,\n        surface: String,\n        friction:"
    ' Float64,\n        roughness: Float64,\n    ) raises:\n        ""'
    '"Checked typed boundary. Add a material record, `CreateLaneMaterial'
    "`.\n\n        Args:\n            lane: The lane.\n            s: Whe"
    "re the record starts, in meters along the road.\n            surface"
    ": The surface's name.\n            friction: Its friction coefficien"
    "t.\n            roughness: Its roughness.\n\n        Raises:\n      "
    '      Error: If the station is nonfinite or negative.\n        ""'
    '"\n        self.create_lane_material_si(\n            lane, s.value'
    ", surface, friction, roughness\n        )\n\n    def create_lane_mat"
    "erial_si(\n        mut self,\n        lane: Tuple[Int, Int, Int],\n "
    "       s: Float64,\n        surface: String,\n        friction: Floa"
    't64,\n        roughness: Float64,\n    ) raises:\n        """Expl'
    "icit source-unit compatibility adapter. Add a material record, `Crea"
    "teLaneMaterial`.\n\n        Args:\n            lane: The lane.\n"
)

comptime _BUILDER_OLD_12 = (
    "            b: Its rate of change.\n            c: The quadratic ter"
    "m, per meter.\n            d: The cubic term, per square meter.\n   "
    '     """\n        self._lane(lane).info.borders.append(\n        '
    "    RoadInfoLaneBorder(s, CubicPolynomial(a, b, c, d, s))\n        )"
    "\n\n    def create_lane_height(\n        mut self,\n        lane: Tu"
    "ple[Int, Int, Int],\n        s: Float64,\n        inner: Float64,\n "
    '       outer: Float64,\n    ):\n        """Add a height record, `'
    "CreateLaneHeight`.\n\n        Args:\n            lane: The lane.\n  "
    "          s: Where the record starts, in meters along the road.\n   "
    "         inner: The lift at the inner edge, in meters.\n            "
    'outer: The lift at the outer edge, in meters.\n        """\n     '
    "   self._lane(lane).info.heights.append(\n            RoadInfoLaneHe"
    "ight(s, inner, outer)\n        )\n\n    def create_lane_material(\n "
    "       mut self,\n        lane: Tuple[Int, Int, Int],\n        s: Fl"
    "oat64,\n        surface: String,\n        friction: Float64,\n      "
    '  roughness: Float64,\n    ):\n        """Add a material record, '
    "`CreateLaneMaterial`.\n\n        Args:\n            lane: The lane."
    "\n"
)

comptime _BUILDER_LIVE_13 = (
    "            surface: The surface's name.\n            friction: Its "
    "friction coefficient.\n            roughness: Its roughness.\n\n    "
    "    Raises:\n            Error: If the station is nonfinite or negat"
    'ive.\n        """\n        _ = _nonnegative_si(s)\n\n        self'
    "._lane(lane).info.materials.append(\n            RoadInfoLaneMateria"
    "l._from_si(s, surface, friction, roughness)\n        )\n\n    def cr"
    "eate_lane_rule(\n        mut self, lane: Tuple[Int, Int, Int], s: Le"
    'ngth64, value: String\n    ) raises:\n        """Checked typed bo'
    "undary. Add a rule record, `CreateLaneRule`.\n\n        Args:\n     "
    "       lane: The lane.\n            s: Where the record starts, in m"
    "eters along the road.\n            value: The rule's text.\n\n      "
    "  Raises:\n            Error: If the station is nonfinite or negativ"
    'e.\n        """\n        self.create_lane_rule_si(lane, s.value, '
    "value)\n\n    def create_lane_rule_si(\n        mut self, lane: Tupl"
    "e[Int, Int, Int], s: Float64, value: String\n    ) raises:\n        "
    '"""Explicit source-unit compatibility adapter. Add a rule record,'
    " `CreateLaneRule`.\n\n        Args:\n            lane: The lane.\n  "
    "          s: Where the record starts, in meters along the road.\n   "
    "         value: The rule's text.\n\n        Raises:\n            Err"
    'or: If the station is nonfinite or negative.\n        """\n      '
    "  _ = _nonnegative_si(s)\n\n        self._lane(lane).info.rules.appe"
    "nd(RoadInfoLaneRule._from_si(s, value))\n\n    def create_lane_visib"
    "ility(\n        mut self,\n        lane: Tuple[Int, Int, Int],\n    "
    "    s: Length64,\n        forward: Length64,\n        back: Length64"
    ",\n        left: Length64,\n        right: Length64,\n    ) raises:"
    '\n        """Checked typed boundary. Add a visibility record, `Cr'
    "eateLaneVisibility`.\n\n        Args:\n            lane: The lane.\n"
    "            s: Where the record starts, in meters along the road.\n "
    "           forward: Meters of sight forward.\n            back: Mete"
    "rs of sight back.\n            left: Meters of sight left.\n        "
    "    right: Meters of sight right.\n\n        Raises:\n            Er"
    "ror: If the station or any sight distance is nonfinite or\n         "
    '       negative.\n        """\n        self.create_lane_visibilit'
    "y_si(\n            lane, s.value, forward.value, back.value, left.va"
    "lue, right.value\n        )\n\n    def create_lane_visibility_si(\n "
    "       mut self,\n        lane: Tuple[Int, Int, Int],\n        s: Fl"
    "oat64,\n"
)

comptime _BUILDER_OLD_13 = (
    "            surface: The surface's name.\n            friction: Its "
    "friction coefficient.\n            roughness: Its roughness.\n      "
    '  """\n        self._lane(lane).info.materials.append(\n         '
    "   RoadInfoLaneMaterial(s, surface, friction, roughness)\n        )"
    "\n\n    def create_lane_rule(\n        mut self, lane: Tuple[Int, In"
    't, Int], s: Float64, value: String\n    ):\n        """Add a rule'
    " record, `CreateLaneRule`.\n\n        Args:\n            lane: The l"
    "ane.\n            s: Where the record starts, in meters along the ro"
    'ad.\n            value: The rule\'s text.\n        """\n        se'
    "lf._lane(lane).info.rules.append(RoadInfoLaneRule(s, value))\n\n    "
    "def create_lane_visibility(\n        mut self,\n        lane: Tuple["
    "Int, Int, Int],\n        s: Float64,\n"
)

comptime _BUILDER_LIVE_14 = (
    "        back: Float64,\n        left: Float64,\n        right: Float"
    '64,\n    ) raises:\n        """Explicit source-unit compatibility'
    " adapter. Add a visibility record, `CreateLaneVisibility`.\n\n      "
    "  Args:\n            lane: The lane.\n"
)

comptime _BUILDER_OLD_14 = (
    "        back: Float64,\n        left: Float64,\n        right: Float"
    '64,\n    ):\n        """Add a visibility record, `CreateLaneVisib'
    "ility`.\n\n        Args:\n            lane: The lane.\n"
)

comptime _BUILDER_LIVE_15 = (
    "            back: Meters of sight back.\n            left: Meters of"
    " sight left.\n            right: Meters of sight right.\n\n        R"
    "aises:\n            Error: If the station or any sight distance is n"
    'onfinite or\n                negative.\n        """\n        _ = '
    "_nonnegative_si(s)\n        _ = _nonnegative_si(forward)\n        _ "
    "= _nonnegative_si(back)\n        _ = _nonnegative_si(left)\n        "
    "_ = _nonnegative_si(right)\n\n        self._lane(lane).info.visibili"
    "ties.append(\n            RoadInfoLaneVisibility._from_si(s, forward"
    ", back, left, right)\n        )\n\n    def create_lane_access(\n    "
    "    mut self, lane: Tuple[Int, Int, Int], s: Length64, restriction: "
    'String\n    ) raises:\n        """Checked typed boundary. Add an '
    "access record, `CreateLaneAccess`.\n\n        Args:\n            lan"
    "e: The lane.\n            s: Where the record starts, in meters alon"
    "g the road.\n            restriction: Who may use the lane.\n\n     "
    "   Raises:\n            Error: If the station is nonfinite or negati"
    've.\n        """\n        self.create_lane_access_si(lane, s.valu'
    "e, restriction)\n\n    def create_lane_access_si(\n        mut self,"
    " lane: Tuple[Int, Int, Int], s: Float64, restriction: String\n    ) "
    'raises:\n        """Explicit source-unit compatibility adapter. A'
    "dd an access record, `CreateLaneAccess`.\n\n        Args:\n         "
    "   lane: The lane.\n            s: Where the record starts, in meter"
    "s along the road.\n            restriction: Who may use the lane.\n"
    "\n        Raises:\n            Error: If the station is nonfinite or"
    ' negative.\n        """\n        _ = _nonnegative_si(s)\n\n      '
    "  self._lane(lane).info.accesses.append(\n            RoadInfoLaneAc"
    "cess._from_si(s, restriction)\n        )\n\n    def create_lane_spee"
    "d(\n        mut self,\n        lane: Tuple[Int, Int, Int],\n        "
    's: Length64,\n        max: Velocity64,\n    ) raises:\n        ""'
    '"Add a checked lane speed from a quantity.\n\n        Args:\n      '
    "      lane: The lane.\n            s: Where the record starts, in me"
    "ters along the road.\n            max: The finite nonnegative speed "
    "quantity.\n\n        Raises:\n            Error: If the station or s"
    'peed is nonfinite or negative.\n        """\n        self.create_'
    'lane_speed_opendrive(lane, s.value, max.value, "m/s")\n\n    def c'
    "reate_lane_speed_opendrive(\n        mut self,\n        lane: Tuple["
    "Int, Int, Int],\n        s: Float64,\n        max: Float64,\n       "
    ' unit: String = "",\n    ) raises:\n        """Explicit source-'
    "unit compatibility adapter. Add a numeric lane speed without droppin"
    "g its source unit.\n\n        Args:\n            lane: The lane.\n"
)

comptime _BUILDER_OLD_15 = (
    "            back: Meters of sight back.\n            left: Meters of"
    ' sight left.\n            right: Meters of sight right.\n        "'
    '""\n        self._lane(lane).info.visibilities.append(\n          '
    "  RoadInfoLaneVisibility(s, forward, back, left, right)\n        )\n"
    "\n    def create_lane_access(\n        mut self, lane: Tuple[Int, In"
    't, Int], s: Float64, restriction: String\n    ):\n        """Add '
    "an access record, `CreateLaneAccess`.\n\n        Args:\n            "
    "lane: The lane.\n            s: Where the record starts, in meters a"
    "long the road.\n            restriction: Who may use the lane.\n    "
    '    """\n        self._lane(lane).info.accesses.append(\n        '
    "    RoadInfoLaneAccess(s, restriction)\n        )\n\n    def create_"
    "lane_speed(\n        mut self,\n        lane: Tuple[Int, Int, Int],"
    "\n        s: Float64,\n        max: Float64,\n        unit: String ="
    ' "",\n    ) raises:\n        """Add a numeric lane speed withou'
    "t dropping its source unit.\n\n        Args:\n            lane: The "
    "lane.\n"
)

comptime _BUILDER_LIVE_16 = (
    "        Raises:\n            Error: If the source number or unit is "
    'invalid.\n        """\n        _ = _nonnegative_si(s)\n\n        '
    'var record = RoadInfoSpeed._from_si(s, max, "Town", unit)\n       '
    " self._lane(lane).info.speeds.append(record^)\n\n    def create_lane"
    "_speed_opendrive(\n        mut self,\n        lane: Tuple[Int, Int, "
    "Int],\n        s: Float64,\n        max: String,\n        unit: Stri"
    'ng,\n    ) raises:\n        """Explicit source-unit compatibility'
    " adapter. Add a numeric lane speed directly from OpenDRIVE text.\n\n"
    "        Args:\n            lane: The lane.\n"
)

comptime _BUILDER_OLD_16 = (
    "        Raises:\n            Error: If the source number or unit is "
    'invalid.\n        """\n        var record = RoadInfoSpeed(s, max,'
    ' "Town", unit)\n        self._lane(lane).info.speeds.append(record'
    "^)\n\n    def create_lane_speed(\n        mut self,\n        lane: T"
    "uple[Int, Int, Int],\n        s: Float64,\n        max: String,\n   "
    '     unit: String,\n    ) raises:\n        """Add a numeric lane '
    "speed directly from OpenDRIVE text.\n\n        Args:\n            la"
    "ne: The lane.\n"
)

comptime _BUILDER_LIVE_17 = (
    "        Raises:\n            Error: If the source number or unit is "
    'invalid.\n        """\n        _ = _nonnegative_si(s)\n\n        '
    'var record = RoadInfoSpeed.from_opendrive(s, max, "Town", unit, Fa'
    "lse)\n        self._lane(lane).info.speeds.append(record^)\n\n    de"
    "f create_road_mark(\n        mut self,\n        lane: Tuple[Int, Int"
    ", Int],\n        road_mark_id: Int,\n        s: Length64,\n        t"
    "ype: String,\n        weight: String,\n        color: String,\n     "
    "   material: String,\n        width: Length64,\n        lane_change:"
    " String,\n        height: Length64,\n        type_name: String,\n   "
    "     type_width: Length64,\n        is_rht: Bool,\n    ) raises:\n  "
    '      """Checked typed boundary. Add a road mark, `CreateRoadMark'
    "`.\n\n        Args:\n            lane: The lane.\n            road_m"
    "ark_id: The mark's index within the lane.\n            s: Where the "
    "mark starts, in meters along the road.\n            type: The mark's"
    ' type, such as "broken".\n            weight: Its weight.\n       '
    "     color: Its color.\n            material: Its material.\n       "
    "     width: The paint's width, in meters.\n            lane_change: "
    '"increase", "decrease", "none", or anything else\n            '
    "    for both.\n            height: The paint's height, in meters.\n "
    "           type_name: The name of the mark's `type` child.\n        "
    "    type_width: The width of the mark's `type` child.\n            i"
    "s_rht: The traffic rule of the lane's road.\n\n        Raises:\n    "
    "        Error: If the station, width, height, or type width is nonfi"
    'nite\n                or negative.\n        """\n        self.cre'
    "ate_road_mark_si(\n            lane,\n            road_mark_id,\n   "
    "         s.value,\n            type,\n            weight,\n         "
    "   color,\n            material,\n            width.value,\n        "
    "    lane_change,\n            height.value,\n            type_name,"
    "\n            type_width.value,\n            is_rht,\n        )\n\n "
    "   def create_road_mark_si(\n        mut self,\n        lane: Tuple["
    "Int, Int, Int],\n        road_mark_id: Int,\n"
)

comptime _BUILDER_OLD_17 = (
    "        Raises:\n            Error: If the source number or unit is "
    'invalid.\n        """\n        var record = RoadInfoSpeed.from_op'
    'endrive(s, max, "Town", unit, False)\n        self._lane(lane).inf'
    "o.speeds.append(record^)\n\n    def create_road_mark(\n        mut s"
    "elf,\n        lane: Tuple[Int, Int, Int],\n        road_mark_id: Int"
    ",\n"
)

comptime _BUILDER_LIVE_18 = (
    "        type_name: String,\n        type_width: Float64,\n        is"
    '_rht: Bool,\n    ) raises:\n        """Explicit source-unit compa'
    "tibility adapter. Add a road mark, `CreateRoadMark`.\n\n        Args"
    ":\n            lane: The lane.\n"
)

comptime _BUILDER_OLD_18 = (
    "        type_name: String,\n        type_width: Float64,\n        is"
    '_rht: Bool,\n    ):\n        """Add a road mark, `CreateRoadMark`'
    ".\n\n        Args:\n            lane: The lane.\n"
)

comptime _BUILDER_LIVE_19 = (
    "            type_name: The name of the mark's `type` child.\n       "
    "     type_width: The width of the mark's `type` child.\n            "
    "is_rht: The traffic rule of the lane's road.\n\n        Raises:\n   "
    "         Error: If the station, width, height, or type width is nonf"
    'inite\n                or negative.\n        """\n        _ = _no'
    "nnegative_si(s)\n        _ = _nonnegative_si(width)\n        _ = _no"
    "nnegative_si(height)\n        _ = _nonnegative_si(type_width)\n\n   "
    "     self._lane(lane).info.marks.append(\n            RoadInfoMarkRe"
    "cord._from_si(\n                s,\n                road_mark_id,\n "
    "               type,\n"
)

comptime _BUILDER_OLD_19 = (
    "            type_name: The name of the mark's `type` child.\n       "
    "     type_width: The width of the mark's `type` child.\n            "
    'is_rht: The traffic rule of the lane\'s road.\n        """\n      '
    "  self._lane(lane).info.marks.append(\n            RoadInfoMarkRecor"
    "d(\n                s,\n                road_mark_id,\n             "
    "   type,\n"
)

comptime _BUILDER_LIVE_20 = (
    "        )\n\n    def create_road_mark_type_line(\n        mut self,"
    "\n        lane: Tuple[Int, Int, Int],\n        road_mark_id: Int,\n "
    "       length: Length64,\n        space: Length64,\n        t_offset"
    ": Length64,\n        s: Length64,\n        rule: String,\n        wi"
    'dth: Length64,\n    ) raises:\n        """Checked typed boundary.'
    " Add a line to a road mark's type, `CreateRoadMarkTypeLine`.\n\n    "
    "    The line joins the first mark of the lane with the same id. With"
    "\n        no such mark it is dropped, as in CARLA.\n\n        Args:"
    "\n            lane: The lane.\n            road_mark_id: The mark's "
    "index within the lane.\n            length: Meters of paint.\n      "
    "      space: Meters of gap.\n            t_offset: The sideways offs"
    "et, in meters.\n            s: Where the line starts, in meters alon"
    "g the road.\n            rule: The line's rule.\n            width: "
    "The line's width, in meters.\n\n        Raises:\n            Error: "
    "If a dimensional value is nonfinite, or the station,\n              "
    '  painted length, gap, or width is negative.\n        """\n      '
    "  self.create_road_mark_type_line_si(\n            lane,\n          "
    "  road_mark_id,\n            length.value,\n            space.value,"
    "\n            t_offset.value,\n            s.value,\n            rul"
    "e,\n            width.value,\n        )\n\n    def create_road_mark_"
    "type_line_si(\n        mut self,\n        lane: Tuple[Int, Int, Int]"
    ",\n        road_mark_id: Int,\n"
)

comptime _BUILDER_OLD_20 = (
    "        )\n\n    def create_road_mark_type_line(\n        mut self,"
    "\n        lane: Tuple[Int, Int, Int],\n        road_mark_id: Int,\n"
)

comptime _BUILDER_LIVE_21 = (
    "        s: Float64,\n        rule: String,\n        width: Float64,"
    '\n    ) raises:\n        """Explicit source-unit compatibility ad'
    "apter. Add a line to a road mark's type, `CreateRoadMarkTypeLine`.\n"
    "\n        The line joins the first mark of the lane with the same id"
    ". With\n        no such mark it is dropped, as in CARLA.\n"
)

comptime _BUILDER_OLD_21 = (
    "        s: Float64,\n        rule: String,\n        width: Float64,"
    '\n    ):\n        """Add a line to a road mark\'s type, `CreateRoa'
    "dMarkTypeLine`.\n\n        The line joins the first mark of the lane"
    " with the same id. With\n        no such mark it is dropped, as in C"
    "ARLA.\n"
)

comptime _BUILDER_LIVE_22 = (
    "            s: Where the line starts, in meters along the road.\n   "
    "         rule: The line's rule.\n            width: The line's width"
    ", in meters.\n\n        Raises:\n            Error: If a dimensional"
    " value is nonfinite, or the station,\n                painted length"
    ', gap, or width is negative.\n        """\n        _ = _nonnegati'
    "ve_si(length)\n        _ = _nonnegative_si(space)\n        _ = _fini"
    "te_si(t_offset)\n        _ = _nonnegative_si(s)\n        _ = _nonneg"
    "ative_si(width)\n\n        ref marks = self._lane(lane).info.marks\n"
    "        for i in range(len(marks)):\n            if marks[i].road_ma"
    "rk_id == road_mark_id:\n                marks[i].lines.append(\n    "
    "                RoadInfoMarkTypeLine._from_si(\n                    "
    "    s, road_mark_id, length, space, t_offset, rule, width\n         "
    "           )\n                )\n"
)

comptime _BUILDER_OLD_22 = (
    "            s: Where the line starts, in meters along the road.\n   "
    "         rule: The line's rule.\n            width: The line's width"
    ', in meters.\n        """\n        ref marks = self._lane(lane).i'
    "nfo.marks\n        for i in range(len(marks)):\n            if marks"
    "[i].road_mark_id == road_mark_id:\n                marks[i].lines.ap"
    "pend(\n                    RoadInfoMarkTypeLine(\n                  "
    "      s, road_mark_id, length, space, t_offset, rule, width\n       "
    "             )\n                )\n"
)

comptime _BUILDER_LIVE_23 = (
    "    # --- road records ---------------------------------------------"
    "------------\n\n    def add_road_elevation_profile(\n        mut sel"
    "f,\n        road: Int,\n        s: Length64,\n        a: Length64,\n"
    "        b: Float64,\n        c: InverseLength64,\n        d: Inverse"
    'Area64,\n    ) raises:\n        """Checked typed boundary. Add an'
    " elevation record, `AddRoadElevationProfile`.\n\n        Args:\n    "
    "        road: The road's index.\n            s: Where the record sta"
    "rts, in meters.\n            a: The height at s, in meters.\n       "
    "     b: The slope.\n            c: The quadratic term, per meter.\n "
    "           d: The cubic term, per square meter.\n\n        Raises:\n"
    "            Error: If the station is nonfinite or negative, or any p"
    'olynomial\n                coefficient is nonfinite.\n        """'
    "\n        self.add_road_elevation_profile_si(\n            road, s.v"
    "alue, a.value, b, c.value, d.value\n        )\n\n    def add_road_el"
    "evation_profile_si(\n        mut self,\n        road: Int,\n        "
    "s: Float64,\n"
)

comptime _BUILDER_OLD_23 = (
    "    # --- road records ---------------------------------------------"
    "------------\n\n    def add_road_elevation_profile(\n        mut sel"
    "f,\n        road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_LIVE_24 = (
    "        b: Float64,\n        c: Float64,\n        d: Float64,\n    )"
    ' raises:\n        """Explicit source-unit compatibility adapter. '
    "Add an elevation record, `AddRoadElevationProfile`.\n\n        Args:"
    "\n            road: The road's index.\n"
)

comptime _BUILDER_OLD_24 = (
    "        b: Float64,\n        c: Float64,\n        d: Float64,\n    )"
    ':\n        """Add an elevation record, `AddRoadElevationProfile`.'
    "\n\n        Args:\n            road: The road's index.\n"
)

comptime _BUILDER_LIVE_25 = (
    "            b: The slope.\n            c: The quadratic term, per me"
    "ter.\n            d: The cubic term, per square meter.\n\n        Ra"
    "ises:\n            Error: If the station is nonfinite or negative, o"
    "r any polynomial\n                coefficient is nonfinite.\n       "
    ' """\n        _ = _nonnegative_si(s)\n        _ = _finite_si(a)\n'
    "        _ = _finite_si(c)\n        _ = _finite_si(d)\n\n        self"
    ".roads[road].info.elevations.append(\n            RoadInfoElevation."
    "_from_si(\n                s, CubicPolynomial.from_coefficients(a, b"
    ", c, d, s)\n            )\n        )\n\n    def create_section_offse"
    "t(\n        mut self,\n        road: Int,\n        s: Length64,\n   "
    "     a: Length64,\n        b: Float64,\n        c: InverseLength64,"
    '\n        d: InverseArea64,\n    ) raises:\n        """Checked ty'
    "ped boundary. Add a lane offset record, `CreateSectionOffset`.\n\n  "
    "      Args:\n            road: The road's index.\n            s: Whe"
    "re the record starts, in meters.\n            a: The offset at s, in"
    " meters. Plus is to the left.\n            b: Its rate of change.\n "
    "           c: The quadratic term, per meter.\n            d: The cub"
    "ic term, per square meter.\n\n        Raises:\n            Error: If"
    " the station is nonfinite or negative, or any polynomial\n          "
    '      coefficient is nonfinite.\n        """\n        self.create'
    "_section_offset_si(\n            road, s.value, a.value, b, c.value,"
    " d.value\n        )\n\n    def create_section_offset_si(\n        mu"
    "t self,\n        road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_OLD_25 = (
    "            b: The slope.\n            c: The quadratic term, per me"
    'ter.\n            d: The cubic term, per square meter.\n        ""'
    '"\n        self.roads[road].info.elevations.append(\n            Ro'
    "adInfoElevation(s, CubicPolynomial(a, b, c, d, s))\n        )\n\n   "
    " def create_section_offset(\n        mut self,\n        road: Int,\n"
    "        s: Float64,\n"
)

comptime _BUILDER_LIVE_26 = (
    "        b: Float64,\n        c: Float64,\n        d: Float64,\n    )"
    ' raises:\n        """Explicit source-unit compatibility adapter. '
    "Add a lane offset record, `CreateSectionOffset`.\n\n        Args:\n "
    "           road: The road's index.\n"
)

comptime _BUILDER_OLD_26 = (
    "        b: Float64,\n        c: Float64,\n        d: Float64,\n    )"
    ':\n        """Add a lane offset record, `CreateSectionOffset`.\n'
    "\n        Args:\n            road: The road's index.\n"
)

comptime _BUILDER_LIVE_27 = (
    "            b: Its rate of change.\n            c: The quadratic ter"
    "m, per meter.\n            d: The cubic term, per square meter.\n\n "
    "       Raises:\n            Error: If the station is nonfinite or ne"
    "gative, or any polynomial\n                coefficient is nonfinite."
    '\n        """\n        _ = _nonnegative_si(s)\n        _ = _finit'
    "e_si(a)\n        _ = _finite_si(c)\n        _ = _finite_si(d)\n\n   "
    "     self.roads[road].info.lane_offsets.append(\n            RoadInf"
    "oLaneOffset._from_si(\n                s, CubicPolynomial.from_coeff"
    "icients(a, b, c, d, s)\n            )\n        )\n\n    def create_r"
    "oad_speed(\n        mut self,\n        road: Int,\n        s: Length"
    "64,\n        type: String,\n        max: Velocity64,\n    ) raises:"
    '\n        """Add a checked road speed from a quantity.\n\n       '
    " Args:\n            road: The road's index.\n            s: Where th"
    "e record starts, in meters.\n            type: The road type; the co"
    "mpatibility record type stays Town.\n            max: The finite non"
    "negative speed quantity.\n\n        Raises:\n            Error: If t"
    'he station or speed is nonfinite or negative.\n        """\n     '
    "   self.create_road_speed_opendrive(road, s.value, type, max.value, "
    '"m/s")\n\n    def create_road_speed_opendrive(\n        mut self,'
    "\n        road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_OLD_27 = (
    "            b: Its rate of change.\n            c: The quadratic ter"
    "m, per meter.\n            d: The cubic term, per square meter.\n   "
    '     """\n        self.roads[road].info.lane_offsets.append(\n   '
    "         RoadInfoLaneOffset(s, CubicPolynomial(a, b, c, d, s))\n    "
    "    )\n\n    def create_road_speed(\n        mut self,\n        road"
    ": Int,\n        s: Float64,\n"
)

comptime _BUILDER_LIVE_28 = (
    "        max: Float64,\n        unit: String,\n    ) raises:\n       "
    ' """Explicit source-unit compatibility adapter. Add a numeric roa'
    "d speed without dropping its unit.\n\n        Args:\n            roa"
    "d: The road's index.\n"
)

comptime _BUILDER_OLD_28 = (
    "        max: Float64,\n        unit: String,\n    ) raises:\n       "
    ' """Add a numeric road speed without dropping its unit.\n\n      '
    "  Args:\n            road: The road's index.\n"
)

comptime _BUILDER_LIVE_29 = (
    "        Raises:\n            Error: If the number or unit is invalid"
    '.\n        """\n        _ = _nonnegative_si(s)\n\n        _ = typ'
    'e\n        var record = RoadInfoSpeed._from_si(s, max, "Town", uni'
    "t)\n        self.roads[road].info.speeds.append(record^)\n\n    def "
    "create_road_speed_opendrive(\n        mut self,\n        road: Int,"
    "\n        s: Float64,\n"
)

comptime _BUILDER_OLD_29 = (
    "        Raises:\n            Error: If the number or unit is invalid"
    '.\n        """\n        _ = type\n        var record = RoadInfoSp'
    'eed(s, max, "Town", unit)\n        self.roads[road].info.speeds.ap'
    "pend(record^)\n\n    def create_road_speed(\n        mut self,\n    "
    "    road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_LIVE_30 = (
    "        max: String,\n        unit: String,\n    ) raises:\n        "
    '"""Explicit source-unit compatibility adapter. Add a numeric, unr'
    "estricted, undefined or absent road speed.\n\n        Args:\n       "
    "     road: The road's index.\n"
)

comptime _BUILDER_OLD_30 = (
    "        max: String,\n        unit: String,\n    ) raises:\n        "
    '"""Add a numeric, unrestricted, undefined or absent road speed.\n'
    "\n        Args:\n            road: The road's index.\n"
)

comptime _BUILDER_LIVE_31 = (
    "        Raises:\n            Error: If a numeric limit or source uni"
    't is invalid.\n        """\n        _ = _nonnegative_si(s)\n\n   '
    "     _ = type\n        var record = RoadInfoSpeed.from_opendrive(s, "
    'max, "Town", unit, True)\n        self.roads[road].info.speeds.app'
    "end(record^)\n\n    def add_road_object_crosswalk(\n        mut self"
    ",\n        road: Int,\n        name: String,\n        s: Length64,\n"
    "        t: Length64,\n        z_offset: Length64,\n        heading: "
    "Angle64,\n        pitch: Angle64,\n        roll: Angle64,\n        o"
    "rientation: String,\n        width: Length64,\n        length: Lengt"
    "h64,\n        points: List[CrosswalkPoint],\n    ) raises:\n        "
    '"""Checked typed boundary. Add a crosswalk, `AddRoadObjectCrosswa'
    "lk`.\n\n        Args:\n            road: The road's index.\n        "
    "    name: The object's name.\n            s: Where it sits, in meter"
    "s along the road.\n            t: Meters to the left of the referenc"
    "e line.\n            z_offset: Meters up.\n            heading: Its "
    "heading, in radians.\n            pitch: Its pitch, in radians.\n   "
    "         roll: Its roll, in radians.\n            orientation: Its o"
    "rientation text.\n            width: Its width, in meters.\n        "
    "    length: Its length, in meters.\n            points: Its outline'"
    "s corners.\n\n        Raises:\n            Error: If a dimensional v"
    "alue or corner coordinate is nonfinite,\n                or the stat"
    'ion, width, or length is negative.\n        """\n        self.add'
    "_road_object_crosswalk_si(\n            road,\n            name,\n  "
    "          s.value,\n            t.value,\n            z_offset.value"
    ",\n            heading.value,\n            pitch.value,\n           "
    " roll.value,\n            orientation,\n            width.value,\n  "
    "          length.value,\n            points,\n        )\n\n    def a"
    "dd_road_object_crosswalk_si(\n        mut self,\n        road: Int,"
    "\n        name: String,\n"
)

comptime _BUILDER_OLD_31 = (
    "        Raises:\n            Error: If a numeric limit or source uni"
    't is invalid.\n        """\n        _ = type\n        var record '
    '= RoadInfoSpeed.from_opendrive(s, max, "Town", unit, True)\n      '
    "  self.roads[road].info.speeds.append(record^)\n\n    def add_road_o"
    "bject_crosswalk(\n        mut self,\n        road: Int,\n        nam"
    "e: String,\n"
)

comptime _BUILDER_LIVE_32 = (
    "        width: Float64,\n        length: Float64,\n        points: L"
    'ist[CrosswalkPoint],\n    ) raises:\n        """Explicit source-u'
    "nit compatibility adapter. Add a crosswalk, `AddRoadObjectCrosswalk`"
    ".\n\n        Args:\n            road: The road's index.\n"
)

comptime _BUILDER_OLD_32 = (
    "        width: Float64,\n        length: Float64,\n        points: L"
    'ist[CrosswalkPoint],\n    ):\n        """Add a crosswalk, `AddRoa'
    "dObjectCrosswalk`.\n\n        Args:\n            road: The road's in"
    "dex.\n"
)

comptime _BUILDER_LIVE_33 = (
    "            width: Its width, in meters.\n            length: Its le"
    "ngth, in meters.\n            points: Its outline's corners.\n\n    "
    "    Raises:\n            Error: If a dimensional value or corner coo"
    "rdinate is nonfinite,\n                or the station, width, or len"
    'gth is negative.\n        """\n        _ = _nonnegative_si(s)\n  '
    "      _ = _finite_si(t)\n        _ = _finite_si(z_offset)\n        _"
    " = _finite_si(heading)\n        _ = _finite_si(pitch)\n        _ = _"
    "finite_si(roll)\n        _ = _nonnegative_si(width)\n        _ = _no"
    "nnegative_si(length)\n\n        for point in points:\n            _ "
    "= _finite_si(point.u)\n            _ = _finite_si(point.v)\n        "
    "    _ = _finite_si(point.z)\n        self.roads[road].info.crosswalk"
    "s.append(\n            RoadInfoCrosswalk._from_si(\n                "
    "s,\n                name,\n                t,\n"
)

comptime _BUILDER_OLD_33 = (
    "            width: Its width, in meters.\n            length: Its le"
    "ngth, in meters.\n            points: Its outline's corners.\n      "
    '  """\n        self.roads[road].info.crosswalks.append(\n        '
    "    RoadInfoCrosswalk(\n                s,\n                name,\n "
    "               t,\n"
)

comptime _BUILDER_LIVE_34 = (
    "\n    def _geometry(mut self, road: Int, var geometry: RoadGeometry)"
    ":\n        var s = geometry.s\n        self.roads[road].info.geometr"
    "ies.append(\n            RoadInfoGeometry._from_si(s, geometry)\n   "
    "     )\n\n    def _base(\n        self,\n"
)

comptime _BUILDER_OLD_34 = (
    "\n    def _geometry(mut self, road: Int, var geometry: RoadGeometry)"
    ":\n        var s = geometry.s\n        self.roads[road].info.geometr"
    "ies.append(RoadInfoGeometry(s, geometry^))\n\n    def _base(\n      "
    "  self,\n"
)

comptime _BUILDER_LIVE_35 = (
    "        length: Float64,\n    ) raises -> RoadGeometry:\n        # C"
    "ARLA keeps the start point as a `float` `Location`.\n        return "
    "RoadGeometry.from_meters(\n            LINE,\n            s,\n      "
    "      Float64(Float32(x)),\n"
)

comptime _BUILDER_OLD_35 = (
    "        length: Float64,\n    ) raises -> RoadGeometry:\n        # C"
    "ARLA keeps the start point as a `float` `Location`.\n        return "
    "RoadGeometry(\n            LINE,\n            s,\n            Float6"
    "4(Float32(x)),\n"
)

comptime _BUILDER_LIVE_36 = (
    "        )\n\n    def add_road_geometry_line(\n        mut self,\n   "
    "     road: Int,\n        s: Length64,\n        x: Length64,\n       "
    " y: Length64,\n        heading: Angle64,\n        length: Length64,"
    '\n    ) raises:\n        """Checked typed boundary. Add a straigh'
    "t geometry, `AddRoadGeometryLine`.\n\n        Args:\n            roa"
    "d: The road's index.\n            s: Where it starts, in meters.\n  "
    "          x: Start east, in meters.\n            y: Start north, in "
    "meters.\n            heading: Its heading, in radians.\n            "
    "length: Its length, in meters.\n\n        Raises:\n            Error"
    ': If s is negative or the length is not positive.\n        """\n '
    "       self.add_road_geometry_line_si(\n            road, s.value, x"
    ".value, y.value, heading.value, length.value\n        )\n\n    def a"
    "dd_road_geometry_line_si(\n        mut self,\n        road: Int,\n  "
    "      s: Float64,\n"
)

comptime _BUILDER_OLD_36 = (
    "        )\n\n    def add_road_geometry_line(\n        mut self,\n   "
    "     road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_LIVE_37 = (
    "        heading: Float64,\n        length: Float64,\n    ) raises:\n"
    '        """Explicit source-unit compatibility adapter. Add a stra'
    "ight geometry, `AddRoadGeometryLine`.\n\n        Args:\n            "
    "road: The road's index.\n"
)

comptime _BUILDER_OLD_37 = (
    "        heading: Float64,\n        length: Float64,\n    ) raises:\n"
    '        """Add a straight geometry, `AddRoadGeometryLine`.\n\n   '
    "     Args:\n            road: The road's index.\n"
)

comptime _BUILDER_LIVE_38 = (
    "        Raises:\n            Error: If s is negative or the length i"
    's not positive.\n        """\n        _ = _nonnegative_si(s)\n   '
    "     _ = _finite_si(x)\n        _ = _finite_si(y)\n        _ = _fini"
    "te_si(heading)\n        _ = _positive_si(length)\n\n        self._ge"
    "ometry(road, self._base(s, x, y, heading, length))\n\n    def add_ro"
    "ad_geometry_arc(\n        mut self,\n        road: Int,\n        s: "
    "Length64,\n        x: Length64,\n        y: Length64,\n        headi"
    "ng: Angle64,\n        length: Length64,\n        curvature: InverseL"
    'ength64,\n    ) raises:\n        """Checked typed boundary. Add a'
    "n arc, `AddRoadGeometryArc`.\n\n        Args:\n            road: The"
    " road's index.\n            s: Where it starts, in meters.\n        "
    "    x: Start east, in meters.\n            y: Start north, in meters"
    ".\n            heading: Its start heading, in radians.\n            "
    "length: Its length, in meters.\n            curvature: One over the "
    "radius, per meter.\n\n        Raises:\n            Error: If s is ne"
    "gative, the length is not positive, or the\n                curvatur"
    'e is zero.\n        """\n        self.add_road_geometry_arc_si(\n'
    "            road,\n            s.value,\n            x.value,\n     "
    "       y.value,\n            heading.value,\n            length.valu"
    "e,\n            curvature.value,\n        )\n\n    def add_road_geom"
    "etry_arc_si(\n        mut self,\n        road: Int,\n        s: Floa"
    "t64,\n"
)

comptime _BUILDER_OLD_38 = (
    "        Raises:\n            Error: If s is negative or the length i"
    's not positive.\n        """\n        self._geometry(road, self._'
    "base(s, x, y, heading, length))\n\n    def add_road_geometry_arc(\n "
    "       mut self,\n        road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_LIVE_39 = (
    "        length: Float64,\n        curvature: Float64,\n    ) raises:"
    '\n        """Explicit source-unit compatibility adapter. Add an a'
    "rc, `AddRoadGeometryArc`.\n\n        Args:\n            road: The ro"
    "ad's index.\n"
)

comptime _BUILDER_OLD_39 = (
    "        length: Float64,\n        curvature: Float64,\n    ) raises:"
    '\n        """Add an arc, `AddRoadGeometryArc`.\n\n        Args:\n'
    "            road: The road's index.\n"
)

comptime _BUILDER_LIVE_40 = (
    "            Error: If s is negative, the length is not positive, or "
    'the\n                curvature is zero.\n        """\n        _ ='
    " _nonnegative_si(s)\n        _ = _finite_si(x)\n        _ = _finite_"
    "si(y)\n        _ = _finite_si(heading)\n        _ = _positive_si(len"
    "gth)\n        _ = _finite_si(curvature)\n\n        self._geometry(\n"
    "            road, with_arc(self._base(s, x, y, heading, length), cur"
    "vature)\n        )\n\n    def add_road_geometry_spiral(\n        mut"
    " self,\n        road: Int,\n        s: Length64,\n        x: Length6"
    "4,\n        y: Length64,\n        heading: Angle64,\n        length:"
    " Length64,\n        curvature_start: InverseLength64,\n        curva"
    'ture_end: InverseLength64,\n    ) raises:\n        """Checked typ'
    "ed boundary. Add a clothoid, `AddRoadGeometrySpiral`.\n\n        Arg"
    "s:\n            road: The road's index.\n            s: Where it sta"
    "rts, in meters.\n            x: Start east, in meters.\n            "
    "y: Start north, in meters.\n            heading: Its start heading, "
    "in radians.\n            length: Its length, in meters.\n           "
    " curvature_start: The curvature at the start, per meter.\n          "
    "  curvature_end: The curvature at the end, per meter.\n\n        Rai"
    "ses:\n            Error: If s is negative or the length is not posit"
    'ive.\n        """\n        self.add_road_geometry_spiral_si(\n   '
    "         road,\n            s.value,\n            x.value,\n        "
    "    y.value,\n            heading.value,\n            length.value,"
    "\n            curvature_start.value,\n            curvature_end.valu"
    "e,\n        )\n\n    def add_road_geometry_spiral_si(\n        mut s"
    "elf,\n        road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_OLD_40 = (
    "            Error: If s is negative, the length is not positive, or "
    'the\n                curvature is zero.\n        """\n        sel'
    "f._geometry(\n            road, with_arc(self._base(s, x, y, heading"
    ", length), curvature)\n        )\n\n    def add_road_geometry_spiral"
    "(\n        mut self,\n        road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_LIVE_41 = (
    "        curvature_start: Float64,\n        curvature_end: Float64,\n"
    '    ) raises:\n        """Explicit source-unit compatibility adap'
    "ter. Add a clothoid, `AddRoadGeometrySpiral`.\n\n        Args:\n    "
    "        road: The road's index.\n"
)

comptime _BUILDER_OLD_41 = (
    "        curvature_start: Float64,\n        curvature_end: Float64,\n"
    '    ) raises:\n        """Add a clothoid, `AddRoadGeometrySpiral`'
    ".\n\n        Args:\n            road: The road's index.\n"
)

comptime _BUILDER_LIVE_42 = (
    "        Raises:\n            Error: If s is negative or the length i"
    's not positive.\n        """\n        _ = _nonnegative_si(s)\n   '
    "     _ = _finite_si(x)\n        _ = _finite_si(y)\n        _ = _fini"
    "te_si(heading)\n        _ = _positive_si(length)\n        _ = _finit"
    "e_si(curvature_start)\n        _ = _finite_si(curvature_end)\n\n    "
    "    self._geometry(\n            road,\n            with_spiral(\n"
)

comptime _BUILDER_OLD_42 = (
    "        Raises:\n            Error: If s is negative or the length i"
    's not positive.\n        """\n        self._geometry(\n          '
    "  road,\n            with_spiral(\n"
)

comptime _BUILDER_LIVE_43 = (
    "        )\n\n    def add_road_geometry_poly3(\n        mut self,\n  "
    "      road: Int,\n        s: Length64,\n        x: Length64,\n      "
    "  y: Length64,\n        heading: Angle64,\n        length: Length64,"
    "\n        a: Length64,\n        b: Float64,\n        c: InverseLengt"
    'h64,\n        d: InverseArea64,\n    ) raises:\n        """Checke'
    "d typed boundary. Add a cubic v(u), `AddRoadGeometryPoly3`.\n\n     "
    "   Args:\n            road: The road's index.\n            s: Where "
    "it starts, in meters.\n            x: Start east, in meters.\n      "
    "      y: Start north, in meters.\n            heading: The direction"
    " of plus u, in radians.\n            length: Its length, in meters."
    "\n            a: The constant term of v, in meters.\n            b: "
    "The linear term.\n            c: The quadratic term, per meter.\n   "
    "         d: The cubic term, per square meter.\n\n        Raises:\n  "
    "          Error: If s is negative or the length is not positive.\n  "
    '      """\n        self.add_road_geometry_poly3_si(\n            '
    "road,\n            s.value,\n            x.value,\n            y.val"
    "ue,\n            heading.value,\n            length.value,\n        "
    "    a.value,\n            b,\n            c.value,\n            d.va"
    "lue,\n        )\n\n    def add_road_geometry_poly3_si(\n        mut "
    "self,\n        road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_OLD_43 = (
    "        )\n\n    def add_road_geometry_poly3(\n        mut self,\n  "
    "      road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_LIVE_44 = (
    '        c: Float64,\n        d: Float64,\n    ) raises:\n        "'
    '""Explicit source-unit compatibility adapter. Add a cubic v(u), `A'
    "ddRoadGeometryPoly3`.\n\n        Args:\n            road: The road's"
    " index.\n"
)

comptime _BUILDER_OLD_44 = (
    '        c: Float64,\n        d: Float64,\n    ) raises:\n        "'
    '""Add a cubic v(u), `AddRoadGeometryPoly3`.\n\n        Args:\n    '
    "        road: The road's index.\n"
)

comptime _BUILDER_LIVE_45 = (
    "        Raises:\n            Error: If s is negative or the length i"
    's not positive.\n        """\n        _ = _nonnegative_si(s)\n   '
    "     _ = _finite_si(x)\n        _ = _finite_si(y)\n        _ = _fini"
    "te_si(heading)\n        _ = _positive_si(length)\n        _ = _finit"
    "e_si(a)\n        _ = _finite_si(c)\n        _ = _finite_si(d)\n\n   "
    "     self._geometry(\n            road, with_poly3(self._base(s, x, "
    "y, heading, length), a, b, c, d)\n        )\n\n    def add_road_geom"
    "etry_param_poly3(\n        mut self,\n        road: Int,\n        s:"
    " Length64,\n        x: Length64,\n        y: Length64,\n        head"
    "ing: Angle64,\n        length: Length64,\n        u: CubicPolynomial"
    ',\n        v: CubicPolynomial,\n    ) raises:\n        """Checked'
    " typed boundary. Add a parametric cubic, `AddRoadGeometryParamPoly3`"
    ".\n\n        Args:\n            road: The road's index.\n           "
    " s: Where it starts, in meters.\n            x: Start east, in meter"
    "s.\n            y: Start north, in meters.\n            heading: The"
    " direction of plus u, in radians.\n            length: Its length, i"
    "n meters.\n            u: The cubic u(p).\n            v: The cubic "
    "v(p).\n\n        Raises:\n            Error: If s is negative, the l"
    "ength is not positive, or the\n                curve does not move."
    '\n        """\n        self.add_road_geometry_param_poly3_si(\n  '
    "          road,\n            s.value,\n            x.value,\n       "
    "     y.value,\n            heading.value,\n            length.value,"
    '\n            u,\n            v,\n            "arcLength",\n      '
    "  )\n\n    def add_road_geometry_param_poly3_normalized(\n        mu"
    "t self,\n        road: Int,\n        s: Length64,\n        x: Length"
    "64,\n        y: Length64,\n        heading: Angle64,\n        length"
    ": Length64,\n        u: NormalizedCubic,\n        v: NormalizedCubic"
    ',\n    ) raises:\n        """Add a normalized cubic with all-leng'
    "th coefficients.\n\n        Args:\n            road: The road index."
    "\n            s: The start station.\n            x: The start east c"
    "oordinate.\n            y: The start north coordinate.\n            "
    "heading: The heading.\n            length: The positive curve length"
    ".\n            u: The u polynomial of dimensionless p.\n            "
    "v: The v polynomial of dimensionless p.\n\n        Raises:\n        "
    "    Error: If a value is invalid or the curve does not move.\n      "
    '  """\n        self.add_road_geometry_param_poly3_si(\n          '
    "  road,\n            s.value,\n            x.value,\n            y.v"
    "alue,\n            heading.value,\n            length.value,\n      "
    "      u._coefficients(),\n            v._coefficients(),\n          "
    '  "normalized",\n        )\n\n    def add_road_geometry_param_poly'
    "3_si(\n        mut self,\n        road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_OLD_45 = (
    "        Raises:\n            Error: If s is negative or the length i"
    's not positive.\n        """\n        self._geometry(\n          '
    "  road, with_poly3(self._base(s, x, y, heading, length), a, b, c, d)"
    "\n        )\n\n    def add_road_geometry_param_poly3(\n        mut s"
    "elf,\n        road: Int,\n        s: Float64,\n"
)

comptime _BUILDER_LIVE_46 = (
    "        v: CubicPolynomial,\n        p_range: String,\n    ) raises:"
    '\n        """Explicit source-unit compatibility adapter. Add a pa'
    "rametric cubic, `AddRoadGeometryParamPoly3`.\n\n        Args:\n     "
    "       road: The road's index.\n"
)

comptime _BUILDER_OLD_46 = (
    "        v: CubicPolynomial,\n        p_range: String,\n    ) raises:"
    '\n        """Add a parametric cubic, `AddRoadGeometryParamPoly3`.'
    "\n\n        Args:\n            road: The road's index.\n"
)

comptime _BUILDER_LIVE_47 = (
    "            length: Its length, in meters.\n            u: The cubic"
    ' u(p).\n            v: The cubic v(p).\n            p_range: "arcLe'
    'ngth", "normalized", or the omitted-source default "".\n\n     '
    "   Raises:\n            Error: If s is negative, the length is not p"
    'ositive, or the\n                curve does not move.\n        ""'
    '"\n        _ = _nonnegative_si(s)\n        _ = _finite_si(x)\n     '
    "   _ = _finite_si(y)\n        _ = _finite_si(heading)\n        _ = _"
    'positive_si(length)\n\n        if p_range != "arcLength" and p_ran'
    'ge != "normalized" and p_range != "":\n            raise Error('
    '"paramPoly3 range must be arcLength or normalized")\n        var p'
    ' = ARC_LENGTH if p_range == "arcLength" else NORMALIZED\n        s'
    "elf._geometry(\n            road,\n"
)

comptime _BUILDER_OLD_47 = (
    "            length: Its length, in meters.\n            u: The cubic"
    ' u(p).\n            v: The cubic v(p).\n            p_range: "arcLe'
    'ngth", or anything else for a normalized p.\n\n        Raises:\n   '
    "         Error: If s is negative, the length is not positive, or the"
    '\n                curve does not move.\n        """\n        var '
    'p = ARC_LENGTH if p_range == "arcLength" else NORMALIZED\n        '
    "self._geometry(\n            road,\n"
)

comptime _BUILDER_LIVE_48 = (
    "    # --- signals --------------------------------------------------"
    "------------\n\n    def add_signal(\n        mut self,\n        road"
    ": Int,\n        signal_id: SignalId,\n        s: Length64,\n        "
    "t: Length64,\n        name: String,\n        dynamic: String,\n     "
    "   orientation: String,\n        z_offset: Length64,\n        countr"
    "y: String,\n        type: String,\n        subtype: String,\n       "
    " value: Float64,\n        unit: String,\n        height: Length64,\n"
    "        width: Length64,\n        text: String,\n        h_offset: A"
    "ngle64,\n        pitch: Angle64,\n        roll: Angle64,\n        va"
    "lue_present: Bool = True,\n    ) raises -> SignalReferenceHandle:\n "
    '       """Checked typed boundary. Add a signal and a reference to'
    " it on its road, `AddSignal`.\n\n        Args:\n            road: Th"
    "e road's index.\n            signal_id: Its id. A later signal with "
    "the same id replaces\n                this one.\n            s: Mete"
    "rs along the road.\n            t: Meters to the left of the referen"
    'ce line.\n            name: Its name.\n            dynamic: "yes" '
    'for a signal that changes.\n            orientation: "+", "-" or'
    " anything else for both.\n            z_offset: Meters up from the r"
    "oad.\n            country: Its catalog's country.\n            type:"
    " Its type.\n            subtype: Its subtype.\n            value: It"
    "s value.\n            unit: The value's unit.\n            height: I"
    "ts height, in meters.\n            width: Its width, in meters.\n   "
    "         text: Its text.\n            h_offset: The turn from the ro"
    "ad's heading, in radians.\n            pitch: Its pitch, in radians."
    "\n            roll: Its roll, in radians.\n            value_present"
    ": Whether the source supplied a numeric value.\n\n        Returns:\n"
    "            The reference's handle.\n\n        Raises:\n            "
    'Error: If the id is not valid or s is negative.\n        """\n   '
    "     return self.add_signal_si(\n            road,\n            sign"
    "al_id,\n            s.value,\n            t.value,\n            name"
    ",\n            dynamic,\n            orientation,\n            z_off"
    "set.value,\n            country,\n            type,\n            sub"
    "type,\n            value,\n            unit,\n            height.val"
    "ue,\n            width.value,\n            text,\n            h_offs"
    "et.value,\n            pitch.value,\n            roll.value,\n      "
    "      value_present,\n        )\n\n    def add_signal_si(\n        m"
    "ut self,\n        road: Int,\n        signal_id: SignalId,\n"
)

comptime _BUILDER_OLD_48 = (
    "    # --- signals --------------------------------------------------"
    "------------\n\n    def add_signal(\n        mut self,\n        road"
    ": Int,\n        signal_id: SignalId,\n"
)

comptime _BUILDER_LIVE_49 = (
    "        roll: Float64,\n        value_present: Bool = True,\n    ) r"
    'aises -> SignalReferenceHandle:\n        """Explicit source-unit '
    "compatibility adapter. Add a signal and a reference to it on its roa"
    "d, `AddSignal`.\n\n        Args:\n            road: The road's index"
    ".\n"
)

comptime _BUILDER_OLD_49 = (
    "        roll: Float64,\n        value_present: Bool = True,\n    ) r"
    'aises -> SignalReferenceHandle:\n        """Add a signal and a re'
    "ference to it on its road, `AddSignal`.\n\n        Args:\n          "
    "  road: The road's index.\n"
)

comptime _BUILDER_LIVE_50 = (
    "        Raises:\n            Error: If the id is not valid or s is n"
    'egative.\n        """\n        _ = _nonnegative_si(s)\n        _ '
    "= _finite_si(t)\n        _ = _finite_si(z_offset)\n        _ = _nonn"
    "egative_si(height)\n        _ = _nonnegative_si(width)\n        _ = "
    "_finite_si(h_offset)\n        _ = _finite_si(pitch)\n        _ = _fi"
    "nite_si(roll)\n\n        var signal = Signal._from_si(\n            "
    "self.roads[road].id,\n            signal_id,\n            s,\n"
)

comptime _BUILDER_OLD_50 = (
    "        Raises:\n            Error: If the id is not valid or s is n"
    'egative.\n        """\n        var signal = Signal(\n            '
    "self.roads[road].id,\n            signal_id,\n            s,\n"
)

comptime _BUILDER_LIVE_51 = (
    "                replaced = True\n        if not replaced:\n         "
    "   self.signals.append(signal^)\n        return self.add_signal_refe"
    "rence_si(road, signal_id, s, t, orientation)\n\n    def _signal_inde"
    "x(self, signal_id: SignalId) raises -> Int:\n        for i in range("
    "len(self.signals)):\n"
)

comptime _BUILDER_OLD_51 = (
    "                replaced = True\n        if not replaced:\n         "
    "   self.signals.append(signal^)\n        return self.add_signal_refe"
    "rence(road, signal_id, s, t, orientation)\n\n    def _signal_index(s"
    "elf, signal_id: SignalId) raises -> Int:\n        for i in range(len"
    "(self.signals)):\n"
)

comptime _BUILDER_LIVE_52 = (
    '        raise Error("The builder has no signal with that id")\n\n '
    "   def add_signal_position_inertial(\n        mut self,\n        sig"
    "nal_id: SignalId,\n        x: Length64,\n        y: Length64,\n     "
    "   z: Length64,\n        heading: Angle64,\n        pitch: Angle64,"
    '\n        roll: Angle64,\n    ) raises:\n        """Checked typed'
    " boundary. Place a signal at a point, `AddSignalPositionInertial`.\n"
    "\n        Args:\n            signal_id: The signal.\n            x: "
    "East, in meters.\n            y: North, in meters.\n            z: U"
    "p, in meters.\n            heading: Its heading, in radians.\n      "
    "      pitch: Its pitch, in radians.\n            roll: Its roll, in "
    "radians.\n\n        Raises:\n            Error: If no signal has the"
    ' id.\n        """\n        self.add_signal_position_inertial_si('
    "\n            signal_id,\n            x.value,\n            y.value,"
    "\n            z.value,\n            heading.value,\n            pitc"
    "h.value,\n            roll.value,\n        )\n\n    def add_signal_p"
    "osition_inertial_si(\n        mut self,\n        signal_id: SignalId"
    ",\n        x: Float64,\n"
)

comptime _BUILDER_OLD_52 = (
    '        raise Error("The builder has no signal with that id")\n\n '
    "   def add_signal_position_inertial(\n        mut self,\n        sig"
    "nal_id: SignalId,\n        x: Float64,\n"
)

comptime _BUILDER_LIVE_53 = (
    "        pitch: Float64,\n        roll: Float64,\n    ) raises:\n    "
    '    """Explicit source-unit compatibility adapter. Place a signal'
    " at a point, `AddSignalPositionInertial`.\n\n        Args:\n        "
    "    signal_id: The signal.\n"
)

comptime _BUILDER_OLD_53 = (
    "        pitch: Float64,\n        roll: Float64,\n    ) raises:\n    "
    '    """Place a signal at a point, `AddSignalPositionInertial`.\n'
    "\n        Args:\n            signal_id: The signal.\n"
)

comptime _BUILDER_LIVE_54 = (
    "        Raises:\n            Error: If no signal has the id.\n      "
    '  """\n        _ = _finite_si(x)\n        _ = _finite_si(y)\n    '
    "    _ = _finite_si(z)\n        _ = _finite_si(heading)\n        _ = "
    "_finite_si(pitch)\n        _ = _finite_si(roll)\n\n        ref signa"
    "l = self.signals[self._signal_index(signal_id)]\n        var transfo"
    "rm = CarlaTransform(\n            Length(Float32(x), METER),\n      "
    "      Length(Float32(-y), METER),\n            Length(Float32(z), ME"
    "TER),\n"
)

comptime _BUILDER_OLD_54 = (
    "        Raises:\n            Error: If no signal has the id.\n      "
    '  """\n        ref signal = self.signals[self._signal_index(signa'
    "l_id)]\n        signal.using_inertial_position = True\n        signa"
    "l.transform = CarlaTransform(\n            Length(Float32(x), METER)"
    ",\n            Length(Float32(-y), METER),\n            Length(Float"
    "32(z), METER),\n"
)

comptime _BUILDER_LIVE_55 = (
    "                Angle(Float32(roll) * _TO_DEGREES, DEGREE),\n       "
    "     ),\n        )\n        _ = _finite_si(Float64(transform.locatio"
    "n.x))\n        _ = _finite_si(Float64(transform.location.y))\n      "
    "  _ = _finite_si(Float64(transform.location.z))\n        _ = _finite"
    "_si(Float64(transform.rotation.pitch))\n        _ = _finite_si(Float"
    "64(transform.rotation.yaw))\n        _ = _finite_si(Float64(transfor"
    "m.rotation.roll))\n        signal.transform = transform\n        sig"
    "nal.using_inertial_position = True\n\n    def add_signal_position_ro"
    "ad(\n        mut self,\n        signal_id: SignalId,\n        road_i"
    "d: RoadId,\n        s: Length64,\n        t: Length64,\n        z_of"
    "fset: Length64,\n        h_offset: Angle64,\n        pitch: Angle64,"
    '\n        roll: Angle64,\n    ) raises:\n        """Checked typed'
    " boundary. Move a signal to another place on a road, `AddSignalPosit"
    "ionRoad`.\n\n        Args:\n            signal_id: The signal.\n    "
    "        road_id: The road.\n            s: Meters along it.\n       "
    "     t: Meters to the left of its reference line.\n            z_off"
    "set: Meters up.\n            h_offset: The turn from the road's head"
    "ing, in radians.\n            pitch: Its pitch, in radians.\n       "
    "     roll: Its roll, in radians.\n\n        Raises:\n            Err"
    "or: If no signal has the id, or the road id is not valid.\n        "
    '"""\n        self.add_signal_position_road_si(\n            signa'
    "l_id,\n            road_id,\n            s.value,\n            t.val"
    "ue,\n            z_offset.value,\n            h_offset.value,\n     "
    "       pitch.value,\n            roll.value,\n        )\n\n    def a"
    "dd_signal_position_road_si(\n        mut self,\n        signal_id: S"
    "ignalId,\n        road_id: RoadId,\n"
)

comptime _BUILDER_OLD_55 = (
    "                Angle(Float32(roll) * _TO_DEGREES, DEGREE),\n       "
    "     ),\n        )\n\n    def add_signal_position_road(\n        mut"
    " self,\n        signal_id: SignalId,\n        road_id: RoadId,\n"
)

comptime _BUILDER_LIVE_56 = (
    "        pitch: Float64,\n        roll: Float64,\n    ) raises:\n    "
    '    """Explicit source-unit compatibility adapter. Move a signal '
    "to another place on a road, `AddSignalPositionRoad`.\n\n        Args"
    ":\n            signal_id: The signal.\n"
)

comptime _BUILDER_OLD_56 = (
    "        pitch: Float64,\n        roll: Float64,\n    ) raises:\n    "
    '    """Move a signal to another place on a road, `AddSignalPositi'
    "onRoad`.\n\n        Args:\n            signal_id: The signal.\n"
)

comptime _BUILDER_LIVE_57 = (
    "        Raises:\n            Error: If no signal has the id, or the "
    'road id is not valid.\n        """\n        _ = _nonnegative_si(s'
    ")\n        _ = _finite_si(t)\n        _ = _finite_si(z_offset)\n    "
    "    _ = _finite_si(h_offset)\n        _ = _finite_si(pitch)\n       "
    " _ = _finite_si(roll)\n\n        if not road_id.is_valid():\n       "
    '     raise Error("Road id is not valid")\n        ref signal = sel'
    "f.signals[self._signal_index(signal_id)]\n"
)

comptime _BUILDER_OLD_57 = (
    "        Raises:\n            Error: If no signal has the id, or the "
    'road id is not valid.\n        """\n        if not road_id.is_val'
    'id():\n            raise Error("Road id is not valid")\n        re'
    "f signal = self.signals[self._signal_index(signal_id)]\n"
)

comptime _BUILDER_LIVE_58 = (
    "        signal.roll = roll\n\n    def add_signal_reference(\n       "
    " mut self,\n        road: Int,\n        signal_id: SignalId,\n      "
    "  s: Length64,\n        t: Length64,\n        orientation: String,\n"
    '    ) raises -> SignalReferenceHandle:\n        """Checked typed '
    "boundary. Add a reference to a signal, `AddSignalReference`.\n\n    "
    "    CARLA clamps s to 10 micrometers short of the road's end.\n\n   "
    "     Args:\n            road: The road's index.\n            signal_"
    "id: The signal.\n            s: Meters along the road. It must not b"
    "e negative.\n            t: Meters to the left of the reference line"
    '.\n            orientation: "+", "-" or anything else for both.'
    "\n\n        Returns:\n            The reference's handle.\n\n       "
    " Raises:\n            Error: If s is negative or the id is not valid"
    '.\n        """\n        return self.add_signal_reference_si(\n   '
    "         road, signal_id, s.value, t.value, orientation\n        )\n"
    "\n    def add_signal_reference_si(\n        mut self,\n        road:"
    " Int,\n        signal_id: SignalId,\n"
)

comptime _BUILDER_OLD_58 = (
    "        signal.roll = roll\n\n    def add_signal_reference(\n       "
    " mut self,\n        road: Int,\n        signal_id: SignalId,\n"
)

comptime _BUILDER_LIVE_59 = (
    "        t: Float64,\n        orientation: String,\n    ) raises -> S"
    'ignalReferenceHandle:\n        """Explicit source-unit compatibil'
    "ity adapter. Add a reference to a signal, `AddSignalReference`.\n\n "
    "       CARLA clamps s to 10 micrometers short of the road's end.\n\n"
)

comptime _BUILDER_OLD_59 = (
    "        t: Float64,\n        orientation: String,\n    ) raises -> S"
    'ignalReferenceHandle:\n        """Add a reference to a signal, `A'
    "ddSignalReference`.\n\n        CARLA clamps s to 10 micrometers shor"
    "t of the road's end.\n\n"
)

comptime _BUILDER_LIVE_60 = (
    "        Raises:\n            Error: If s is negative or the id is no"
    't valid.\n        """\n        _ = _nonnegative_si(s)\n        _ '
    "= _finite_si(t)\n\n        # _nonnegative_si above already refuses s"
    ' < 0.\n        debug_assert(s >= 0.0, "A signal reference cannot si'
    't before s = 0")\n        if not signal_id.is_valid():\n           '
    ' raise Error("Signal id is not valid")\n        ref r = self.roads'
    "[road]\n        var fixed = min(max(s, 0.0), r.length - 0.00001)\n  "
    "      r.info.signals.append(\n            RoadInfoSignal._from_si(\n"
    "                signal_id, r.id, fixed, t, orientation, List[LaneVal"
    "idity]()\n            )\n        )\n"
)

comptime _BUILDER_OLD_60 = (
    "        Raises:\n            Error: If s is negative or the id is no"
    't valid.\n        """\n        if s < 0.0:\n            raise Err'
    'or("A signal reference cannot sit before s = 0")\n        if not s'
    'ignal_id.is_valid():\n            raise Error("Signal id is not val'
    'id")\n        ref r = self.roads[road]\n        var fixed = min(max'
    "(s, 0.0), r.length - 0.00001)\n        r.info.signals.append(\n     "
    "       RoadInfoSignal(\n                signal_id, r.id, fixed, t, o"
    "rientation, List[LaneValidity]()\n            )\n        )\n"
)

comptime _BUILDER_LIVE_61 = (
    "            ref road = self.roads[found.value()]\n            if roa"
    "d_id == road.predecessor:\n                _reserve_lanes_at(road, s"
    "elf._build_work)\n                for pair in road._lanes_at_si(0.0)"
    ":\n                    self._build_work.step()\n                    "
    "ref lane = road.sections[pair[0]].lanes[pair[1]]\n                  "
    "  if lane_id == lane.predecessor:\n                        out.appen"
    "d((road.id, lane.id))\n            if road_id == road.successor:\n  "
    "              _reserve_lanes_at(road, self._build_work)\n           "
    "     for pair in road._lanes_at_si(road.length):\n                  "
    "  self._build_work.step()\n                    ref lane = road.secti"
    "ons[pair[0]].lanes[pair[1]]\n                    if lane_id == lane."
    "successor:\n"
)

comptime _BUILDER_OLD_61 = (
    "            ref road = self.roads[found.value()]\n            if roa"
    "d_id == road.predecessor:\n                _reserve_lanes_at(road, s"
    "elf._build_work)\n                for pair in road.lanes_at(0.0):\n "
    "                   self._build_work.step()\n                    ref "
    "lane = road.sections[pair[0]].lanes[pair[1]]\n                    if"
    " lane_id == lane.predecessor:\n                        out.append((r"
    "oad.id, lane.id))\n            if road_id == road.successor:\n      "
    "          _reserve_lanes_at(road, self._build_work)\n               "
    " for pair in road.lanes_at(road.length):\n                    self._"
    "build_work.step()\n                    ref lane = road.sections[pair"
    "[0]].lanes[pair[1]]\n                    if lane_id == lane.successo"
    "r:\n"
)

comptime _BUILDER_LIVE_62 = (
    "                    inside = True\n        if inside:\n            i"
    "f linked:\n                var found = r._next_lane_si(\n           "
    "         s, next\n                ) if positive else r._prev_lane_si"
    "(s, next)\n                if Bool(found):\n                    var "
    "f = found.value()\n                    out.append(LaneKey(r.id, r.se"
    "ctions[f[0]].id, next))\n"
)

comptime _BUILDER_OLD_62 = (
    "                    inside = True\n        if inside:\n            i"
    "f linked:\n                var found = r.next_lane(s, next) if posit"
    "ive else r.prev_lane(\n                    s, next\n                "
    ")\n                if Bool(found):\n                    var f = foun"
    "d.value()\n                    out.append(LaneKey(r.id, r.sections[f"
    "[0]].id, next))\n"
)

comptime _BUILDER_LIVE_63 = (
    '                "Signal construction cannot resolve reference quadr'
    'ature work"\n            )\n        self._build_work.term(terms)\n '
    "       var point = self.roads[found.value()]._directed_point_no_lane"
    "_offset_si(\n            signal.s\n        )\n        point.apply_la"
    "teral_offset(Length(Float32(-signal.t), METER))\n"
)

comptime _BUILDER_OLD_63 = (
    '                "Signal construction cannot resolve reference quadr'
    'ature work"\n            )\n        self._build_work.term(terms)\n '
    "       var point = self.roads[found.value()].directed_point_no_lane_"
    "offset(\n            signal.s\n        )\n        point.apply_latera"
    "l_offset(Length(Float32(-signal.t), METER))\n"
)

comptime _BUILDER_LIVE_64 = (
    "                _reserve_road_scan(\n                    self.roads["
    "r], self._build_work, section_passes=2\n                )\n         "
    "       for pair in self.roads[r]._lanes_by_distance_si(s):\n        "
    "            self._build_work.step()\n                    lanes.appen"
    "d(\n                        self.roads[r].sections[pair[0]].lanes[pa"
    "ir[1]].id\n"
)

comptime _BUILDER_OLD_64 = (
    "                _reserve_road_scan(\n                    self.roads["
    "r], self._build_work, section_passes=2\n                )\n         "
    "       for pair in self.roads[r].lanes_by_distance(s):\n            "
    "        self._build_work.step()\n                    lanes.append(\n"
    "                        self.roads[r].sections[pair[0]].lanes[pair[1"
    "]].id\n"
)

comptime _BUILDER_LIVE_65 = (
    "    work.step()\n    work.term(terms)\n    work.term(terms)\n    ret"
    "urn map.roads[at[0]]._lane_transform_si(at[1], at[2], waypoint.s)\n"
    "\n\ndef _signal_lane_width(\n"
)

comptime _BUILDER_OLD_65 = (
    "    work.step()\n    work.term(terms)\n    work.term(terms)\n    ret"
    "urn map.roads[at[0]].lane_transform(at[1], at[2], waypoint.s)\n\n\nd"
    "ef _signal_lane_width(\n"
)

comptime _BUILDER_LIVE_66 = (
    ") raises -> Float64:\n    var at = map._locate_with_work(waypoint, w"
    "ork)\n    work.step(len(map.roads[at[0]].sections[at[1]].lanes[at[2]"
    "].info.widths))\n    return map.roads[at[0]]._lane_width_si(at[1], a"
    "t[2], waypoint.s)\n\n\ndef _signal_lane_type(\n"
)

comptime _BUILDER_OLD_66 = (
    ") raises -> Float64:\n    var at = map._locate_with_work(waypoint, w"
    "ork)\n    work.step(len(map.roads[at[0]].sections[at[1]].lanes[at[2]"
    "].info.widths))\n    return map.roads[at[0]].lane_width(at[1], at[2]"
    ", waypoint.s)\n\n\ndef _signal_lane_type(\n"
)


def _map_live(index: Int) -> String:
    """Return one live Map span.

    Args:
        index: The span number.

    Returns:
        The span text.
    """
    if index == 0:
        return _MAP_LIVE_0
    if index == 1:
        return _MAP_LIVE_1
    if index == 2:
        return _MAP_LIVE_2
    if index == 3:
        return _MAP_LIVE_3
    if index == 4:
        return _MAP_LIVE_4
    if index == 5:
        return _MAP_LIVE_5
    if index == 6:
        return _MAP_LIVE_6
    if index == 7:
        return _MAP_LIVE_7
    if index == 8:
        return _MAP_LIVE_8
    if index == 9:
        return _MAP_LIVE_9
    if index == 10:
        return _MAP_LIVE_10
    if index == 11:
        return _MAP_LIVE_11
    if index == 12:
        return _MAP_LIVE_12
    if index == 13:
        return _MAP_LIVE_13
    if index == 14:
        return _MAP_LIVE_14
    if index == 15:
        return _MAP_LIVE_15
    if index == 16:
        return _MAP_LIVE_16
    if index == 17:
        return _MAP_LIVE_17
    if index == 18:
        return _MAP_LIVE_18
    if index == 19:
        return _MAP_LIVE_19
    if index == 20:
        return _MAP_LIVE_20
    if index == 21:
        return _MAP_LIVE_21
    if index == 22:
        return _MAP_LIVE_22
    if index == 23:
        return _MAP_LIVE_23
    if index == 24:
        return _MAP_LIVE_24
    if index == 25:
        return _MAP_LIVE_25
    if index == 26:
        return _MAP_LIVE_26
    if index == 27:
        return _MAP_LIVE_27
    if index == 28:
        return _MAP_LIVE_28
    if index == 29:
        return _MAP_LIVE_29
    if index == 30:
        return _MAP_LIVE_30
    if index == 31:
        return _MAP_LIVE_31
    if index == 32:
        return _MAP_LIVE_32
    if index == 33:
        return _MAP_LIVE_33
    if index == 34:
        return _MAP_LIVE_34
    if index == 35:
        return _MAP_LIVE_35
    if index == 36:
        return _MAP_LIVE_36
    if index == 37:
        return _MAP_LIVE_37
    if index == 38:
        return _MAP_LIVE_38
    if index == 39:
        return _MAP_LIVE_39
    if index == 40:
        return _MAP_LIVE_40
    if index == 41:
        return _MAP_LIVE_41
    if index == 42:
        return _MAP_LIVE_42
    if index == 43:
        return _MAP_LIVE_43
    if index == 44:
        return _MAP_LIVE_44
    if index == 45:
        return _MAP_LIVE_45
    if index == 46:
        return _MAP_LIVE_46
    if index == 47:
        return _MAP_LIVE_47
    if index == 48:
        return _MAP_LIVE_48
    if index == 49:
        return _MAP_LIVE_49
    if index == 50:
        return _MAP_LIVE_50
    if index == 51:
        return _MAP_LIVE_51
    if index == 52:
        return _MAP_LIVE_52
    if index == 53:
        return _MAP_LIVE_53
    if index == 54:
        return _MAP_LIVE_54
    if index == 55:
        return _MAP_LIVE_55
    if index == 56:
        return _MAP_LIVE_56
    if index == 57:
        return _MAP_LIVE_57
    if index == 58:
        return _MAP_LIVE_58
    if index == 59:
        return _MAP_LIVE_59
    if index == 60:
        return _MAP_LIVE_60
    if index == 61:
        return _MAP_LIVE_61
    if index == 62:
        return _MAP_LIVE_62
    if index == 63:
        return _MAP_LIVE_63
    if index == 64:
        return _MAP_LIVE_64
    if index == 65:
        return _MAP_LIVE_65
    if index == 66:
        return _MAP_LIVE_66
    if index == 67:
        return _MAP_LIVE_67
    if index == 68:
        return _MAP_LIVE_68
    if index == 69:
        return _MAP_LIVE_69
    if index == 70:
        return _MAP_LIVE_70
    if index == 71:
        return _MAP_LIVE_71
    return _MAP_LIVE_72


def _map_old(index: Int) -> String:
    """Return one pinned Map span.

    Args:
        index: The span number.

    Returns:
        The span text.
    """
    if index == 0:
        return _MAP_OLD_0
    if index == 1:
        return _MAP_OLD_1
    if index == 2:
        return _MAP_OLD_2
    if index == 3:
        return _MAP_OLD_3
    if index == 4:
        return _MAP_OLD_4
    if index == 5:
        return _MAP_OLD_5
    if index == 6:
        return _MAP_OLD_6
    if index == 7:
        return _MAP_OLD_7
    if index == 8:
        return _MAP_OLD_8
    if index == 9:
        return _MAP_OLD_9
    if index == 10:
        return _MAP_OLD_10
    if index == 11:
        return _MAP_OLD_11
    if index == 12:
        return _MAP_OLD_12
    if index == 13:
        return _MAP_OLD_13
    if index == 14:
        return _MAP_OLD_14
    if index == 15:
        return _MAP_OLD_15
    if index == 16:
        return _MAP_OLD_16
    if index == 17:
        return _MAP_OLD_17
    if index == 18:
        return _MAP_OLD_18
    if index == 19:
        return _MAP_OLD_19
    if index == 20:
        return _MAP_OLD_20
    if index == 21:
        return _MAP_OLD_21
    if index == 22:
        return _MAP_OLD_22
    if index == 23:
        return _MAP_OLD_23
    if index == 24:
        return _MAP_OLD_24
    if index == 25:
        return _MAP_OLD_25
    if index == 26:
        return _MAP_OLD_26
    if index == 27:
        return _MAP_OLD_27
    if index == 28:
        return _MAP_OLD_28
    if index == 29:
        return _MAP_OLD_29
    if index == 30:
        return _MAP_OLD_30
    if index == 31:
        return _MAP_OLD_31
    if index == 32:
        return _MAP_OLD_32
    if index == 33:
        return _MAP_OLD_33
    if index == 34:
        return _MAP_OLD_34
    if index == 35:
        return _MAP_OLD_35
    if index == 36:
        return _MAP_OLD_36
    if index == 37:
        return _MAP_OLD_37
    if index == 38:
        return _MAP_OLD_38
    if index == 39:
        return _MAP_OLD_39
    if index == 40:
        return _MAP_OLD_40
    if index == 41:
        return _MAP_OLD_41
    if index == 42:
        return _MAP_OLD_42
    if index == 43:
        return _MAP_OLD_43
    if index == 44:
        return _MAP_OLD_44
    if index == 45:
        return _MAP_OLD_45
    if index == 46:
        return _MAP_OLD_46
    if index == 47:
        return _MAP_OLD_47
    if index == 48:
        return _MAP_OLD_48
    if index == 49:
        return _MAP_OLD_49
    if index == 50:
        return _MAP_OLD_50
    if index == 51:
        return _MAP_OLD_51
    if index == 52:
        return _MAP_OLD_52
    if index == 53:
        return _MAP_OLD_53
    if index == 54:
        return _MAP_OLD_54
    if index == 55:
        return _MAP_OLD_55
    if index == 56:
        return _MAP_OLD_56
    if index == 57:
        return _MAP_OLD_57
    if index == 58:
        return _MAP_OLD_58
    if index == 59:
        return _MAP_OLD_59
    if index == 60:
        return _MAP_OLD_60
    if index == 61:
        return _MAP_OLD_61
    if index == 62:
        return _MAP_OLD_62
    if index == 63:
        return _MAP_OLD_63
    if index == 64:
        return _MAP_OLD_64
    if index == 65:
        return _MAP_OLD_65
    if index == 66:
        return _MAP_OLD_66
    if index == 67:
        return _MAP_OLD_67
    if index == 68:
        return _MAP_OLD_68
    if index == 69:
        return _MAP_OLD_69
    if index == 70:
        return _MAP_OLD_70
    if index == 71:
        return _MAP_OLD_71
    return _MAP_OLD_72


def _builder_live(index: Int) -> String:
    """Return one live map-builder span.

    Args:
        index: The span number.

    Returns:
        The span text.
    """
    if index == 0:
        return _BUILDER_LIVE_0
    if index == 1:
        return _BUILDER_LIVE_1
    if index == 2:
        return _BUILDER_LIVE_2
    if index == 3:
        return _BUILDER_LIVE_3
    if index == 4:
        return _BUILDER_LIVE_4
    if index == 5:
        return _BUILDER_LIVE_5
    if index == 6:
        return _BUILDER_LIVE_6
    if index == 7:
        return _BUILDER_LIVE_7
    if index == 8:
        return _BUILDER_LIVE_8
    if index == 9:
        return _BUILDER_LIVE_9
    if index == 10:
        return _BUILDER_LIVE_10
    if index == 11:
        return _BUILDER_LIVE_11
    if index == 12:
        return _BUILDER_LIVE_12
    if index == 13:
        return _BUILDER_LIVE_13
    if index == 14:
        return _BUILDER_LIVE_14
    if index == 15:
        return _BUILDER_LIVE_15
    if index == 16:
        return _BUILDER_LIVE_16
    if index == 17:
        return _BUILDER_LIVE_17
    if index == 18:
        return _BUILDER_LIVE_18
    if index == 19:
        return _BUILDER_LIVE_19
    if index == 20:
        return _BUILDER_LIVE_20
    if index == 21:
        return _BUILDER_LIVE_21
    if index == 22:
        return _BUILDER_LIVE_22
    if index == 23:
        return _BUILDER_LIVE_23
    if index == 24:
        return _BUILDER_LIVE_24
    if index == 25:
        return _BUILDER_LIVE_25
    if index == 26:
        return _BUILDER_LIVE_26
    if index == 27:
        return _BUILDER_LIVE_27
    if index == 28:
        return _BUILDER_LIVE_28
    if index == 29:
        return _BUILDER_LIVE_29
    if index == 30:
        return _BUILDER_LIVE_30
    if index == 31:
        return _BUILDER_LIVE_31
    if index == 32:
        return _BUILDER_LIVE_32
    if index == 33:
        return _BUILDER_LIVE_33
    if index == 34:
        return _BUILDER_LIVE_34
    if index == 35:
        return _BUILDER_LIVE_35
    if index == 36:
        return _BUILDER_LIVE_36
    if index == 37:
        return _BUILDER_LIVE_37
    if index == 38:
        return _BUILDER_LIVE_38
    if index == 39:
        return _BUILDER_LIVE_39
    if index == 40:
        return _BUILDER_LIVE_40
    if index == 41:
        return _BUILDER_LIVE_41
    if index == 42:
        return _BUILDER_LIVE_42
    if index == 43:
        return _BUILDER_LIVE_43
    if index == 44:
        return _BUILDER_LIVE_44
    if index == 45:
        return _BUILDER_LIVE_45
    if index == 46:
        return _BUILDER_LIVE_46
    if index == 47:
        return _BUILDER_LIVE_47
    if index == 48:
        return _BUILDER_LIVE_48
    if index == 49:
        return _BUILDER_LIVE_49
    if index == 50:
        return _BUILDER_LIVE_50
    if index == 51:
        return _BUILDER_LIVE_51
    if index == 52:
        return _BUILDER_LIVE_52
    if index == 53:
        return _BUILDER_LIVE_53
    if index == 54:
        return _BUILDER_LIVE_54
    if index == 55:
        return _BUILDER_LIVE_55
    if index == 56:
        return _BUILDER_LIVE_56
    if index == 57:
        return _BUILDER_LIVE_57
    if index == 58:
        return _BUILDER_LIVE_58
    if index == 59:
        return _BUILDER_LIVE_59
    if index == 60:
        return _BUILDER_LIVE_60
    if index == 61:
        return _BUILDER_LIVE_61
    if index == 62:
        return _BUILDER_LIVE_62
    if index == 63:
        return _BUILDER_LIVE_63
    if index == 64:
        return _BUILDER_LIVE_64
    if index == 65:
        return _BUILDER_LIVE_65
    return _BUILDER_LIVE_66


def _builder_old(index: Int) -> String:
    """Return one pinned map-builder span.

    Args:
        index: The span number.

    Returns:
        The span text.
    """
    if index == 0:
        return _BUILDER_OLD_0
    if index == 1:
        return _BUILDER_OLD_1
    if index == 2:
        return _BUILDER_OLD_2
    if index == 3:
        return _BUILDER_OLD_3
    if index == 4:
        return _BUILDER_OLD_4
    if index == 5:
        return _BUILDER_OLD_5
    if index == 6:
        return _BUILDER_OLD_6
    if index == 7:
        return _BUILDER_OLD_7
    if index == 8:
        return _BUILDER_OLD_8
    if index == 9:
        return _BUILDER_OLD_9
    if index == 10:
        return _BUILDER_OLD_10
    if index == 11:
        return _BUILDER_OLD_11
    if index == 12:
        return _BUILDER_OLD_12
    if index == 13:
        return _BUILDER_OLD_13
    if index == 14:
        return _BUILDER_OLD_14
    if index == 15:
        return _BUILDER_OLD_15
    if index == 16:
        return _BUILDER_OLD_16
    if index == 17:
        return _BUILDER_OLD_17
    if index == 18:
        return _BUILDER_OLD_18
    if index == 19:
        return _BUILDER_OLD_19
    if index == 20:
        return _BUILDER_OLD_20
    if index == 21:
        return _BUILDER_OLD_21
    if index == 22:
        return _BUILDER_OLD_22
    if index == 23:
        return _BUILDER_OLD_23
    if index == 24:
        return _BUILDER_OLD_24
    if index == 25:
        return _BUILDER_OLD_25
    if index == 26:
        return _BUILDER_OLD_26
    if index == 27:
        return _BUILDER_OLD_27
    if index == 28:
        return _BUILDER_OLD_28
    if index == 29:
        return _BUILDER_OLD_29
    if index == 30:
        return _BUILDER_OLD_30
    if index == 31:
        return _BUILDER_OLD_31
    if index == 32:
        return _BUILDER_OLD_32
    if index == 33:
        return _BUILDER_OLD_33
    if index == 34:
        return _BUILDER_OLD_34
    if index == 35:
        return _BUILDER_OLD_35
    if index == 36:
        return _BUILDER_OLD_36
    if index == 37:
        return _BUILDER_OLD_37
    if index == 38:
        return _BUILDER_OLD_38
    if index == 39:
        return _BUILDER_OLD_39
    if index == 40:
        return _BUILDER_OLD_40
    if index == 41:
        return _BUILDER_OLD_41
    if index == 42:
        return _BUILDER_OLD_42
    if index == 43:
        return _BUILDER_OLD_43
    if index == 44:
        return _BUILDER_OLD_44
    if index == 45:
        return _BUILDER_OLD_45
    if index == 46:
        return _BUILDER_OLD_46
    if index == 47:
        return _BUILDER_OLD_47
    if index == 48:
        return _BUILDER_OLD_48
    if index == 49:
        return _BUILDER_OLD_49
    if index == 50:
        return _BUILDER_OLD_50
    if index == 51:
        return _BUILDER_OLD_51
    if index == 52:
        return _BUILDER_OLD_52
    if index == 53:
        return _BUILDER_OLD_53
    if index == 54:
        return _BUILDER_OLD_54
    if index == 55:
        return _BUILDER_OLD_55
    if index == 56:
        return _BUILDER_OLD_56
    if index == 57:
        return _BUILDER_OLD_57
    if index == 58:
        return _BUILDER_OLD_58
    if index == 59:
        return _BUILDER_OLD_59
    if index == 60:
        return _BUILDER_OLD_60
    if index == 61:
        return _BUILDER_OLD_61
    if index == 62:
        return _BUILDER_OLD_62
    if index == 63:
        return _BUILDER_OLD_63
    if index == 64:
        return _BUILDER_OLD_64
    if index == 65:
        return _BUILDER_OLD_65
    return _BUILDER_OLD_66


def _fail(message: String) raises:
    """Raise a Map-inventory error.

    Args:
        message: The failure text.

    Raises:
        Error: A live Map inventory changed.
    """
    raise Error(message)


def _message(module: String) -> String:
    """Return the inventory failure for `module`.

    Args:
        module: The caller module.

    Returns:
        The failure text.
    """
    return "global protected-helper use/import inventory changed: " + module


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs in `text`.

    Args:
        text: The source.
        needle: The exact byte sequence.

    Returns:
        The number of non-overlapping matches.
    """
    var count = 0
    var offset = 0
    var size = text.byte_length()
    var step = needle.byte_length()
    while offset < size:
        var rest = String(text[byte=offset:])
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        offset += at + step
    return count


def _apply_map(source: String) raises -> String:
    """Restore the reviewed Map spans.

    Args:
        source: The live Map module.

    Returns:
        The restored source.

    Raises:
        Error: A reviewed span moved.
    """
    var current = source
    var index = 0
    while index < _MAP_SPANS:
        var span = _map_live(index)
        if _count(current, span) != 1:
            _fail(_message("map"))
        current = current.replace(span, _map_old(index))
        index += 1
    return current


def _apply_builder(source: String) raises -> String:
    """Restore the reviewed map-builder spans.

    Args:
        source: The live map-builder module.

    Returns:
        The restored source.

    Raises:
        Error: A reviewed span moved.
    """
    var current = source
    var index = 0
    while index < _BUILDER_SPANS:
        var span = _builder_live(index)
        if _count(current, span) != 1:
            _fail(_message("map_builder"))
        current = current.replace(span, _builder_old(index))
        index += 1
    return current


def _check(base: String, doc: PyJson, module: String, builder: Bool) raises:
    """Require one restored module to keep its pinned use digest.

    Args:
        base: The repository root.
        doc: The pin document.
        module: The caller module.
        builder: True for the map-builder spans.

    Raises:
        Error: The pin or the restored digest changed.
    """
    var path = "extensions/carla/" + module + ".mojo"
    var inventory = doc.at(doc.root, "protected_inventory")
    var pinned = doc.at(inventory, path)
    if doc.kind(pinned) != PY_STR:
        _fail(_message(module))
    var source = Path(base + "/" + path).read_text()
    if builder:
        var restored = _apply_builder(source)
        if _digest(restored) != doc.text(pinned):
            _fail(_message(module))
    else:
        var restored = _apply_map(source)
        if _digest(restored) != doc.text(pinned):
            _fail(_message(module))


def sum2_map_inventory(root: String) raises:
    """Require the live Map and map-builder inventories.

    Args:
        root: The repository root.

    Raises:
        Error: A reviewed span or a pinned use digest changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    _check(base, doc, "map", False)
    _check(base, doc, "map_builder", True)
