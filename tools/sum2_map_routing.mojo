# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live Map routing.

23 reviewed routing spans keep the live declarations. Restoring those
spans matches the pinned routing. A moved span or a changed declaration
is refused.
"""

from std.pathlib import Path

from tools._python_json import PY_STR, PyJson
from tools.sum2_guard_callers import _routing


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _MAP = "extensions/carla/map.mojo"
comptime _MESSAGE = "Sum2 guard import/declaration routing changed: map"

comptime _LEFT_0 = (
    '[[],[[3,"\\"\\"\\"CARLA\'s `road/Map`: the road network and every'
    " question a car asks it.\\n\\nA `Map` holds the roads, the junctions"
    ", the signals and the signal\\ncontrollers of one OpenDRIVE file. A "
    "`Waypoint` is a place on it: a road,\\na lane section, a lane and a "
    "distance s along the road. The map answers\\nwhere a waypoint is (`c"
    "ompute_transform`), what lies ahead of it (`next`,\\n`successors`), "
    "beside it (`right`, `left`) and on it (`mark_record`,\\n`signals_in_"
    "distance`), and which waypoint is nearest a point\\n(`closest_waypoi"
    "nt_on_road`, `waypoint`).\\n\\n**Two segment indices.** The map keep"
    "s CARLA's heading and length\\npartition in its own R-tree. `closest"
    "_waypoint_on_road`, `waypoint` and\\nthe sign check at load use it w"
    "ith CARLA's algorithm: the nearest segment,\\nthen a step along the "
    "lane to the point's foot. These queries do not use\\nthe certified s"
    "earch budget. Input validation, lane stepping and canonical\\npose e"
    "valuation can still raise errors. They keep CARLA's partition, but\\"
    "nthey correct one CARLA approximation. CARLA steps by the plan dista"
    "nce along\\nthe segment chord, as if it were road s. A lane offset, "
    "a lane width or a\\ncurve can make the chord longer or shorter than "
    "its road-s span. A sloped\\nlane then misses points on its center. T"
    "his port steps by the foot's plan\\nfraction of the chord times the "
    "chord's road-s span (#302).\\n\\n**The certified index.** `certified"
    "_closest_waypoint_on_road` and\\n`certified_waypoint` use a second i"
    "ndex. It starts with CARLA's partition\\nand splits again at record "
    "boundaries and until quarter-point\\nchord errors are at most one mi"
    "llimeter. A required split without an\\ninterior Float64 road-s valu"
    "e raises a resolution error. A positive\\nnonterminal index step mus"
    "t also advance in lane order. The line and its\\nstored-point minima"
    " can still be representable. This sampled target is not\\nan unsampl"
    "ed error bound. A separate full-center enclosure and the R-tree's\\n"
    "bounded distance key control candidate admission. An unknown bound k"
    "eeps\\nthe candidate. Each remaining candidate exports a bounded min"
    "imum-distance\\ncertificate. Overlapping candidates resume with thei"
    "r remaining work budget.\\nSelection requires proved dominance; unre"
    "solved work raises an accuracy\\nerror. Approximate witnesses requir"
    "e strict classification agreement across\\nall possible minimizing c"
    "ells. An exact witness uses its proved minimizer.\\nClassification u"
    "ses the Float64 center before public location narrowing.\\n\\nCertif"
    "ied queries minimize three-dimensional distance to the stored canoni"
    "cal\\nFloat64 lane center over the indexed station domains. Station "
    "s is the road\\nreference parameter, not lane chord length. Public `"
    "compute_transform` narrows\\nthat same center. Road reference and fi"
    "xed-s helpers describe separate geometry.\\nSegment indices resolve "
    "exact distance ties. A rounded station plateau keeps\\nits incumbent"
    "; the API does not promise the first station on that plateau.\\n\\nT"
    "he public `segment_count` and `segment` methods expose this accuracy"
    "-driven\\nindex. Its partition and count can change when the geometr"
    "y requires more\\nsubdivision. Lane order and index tie rules remain"
    " deterministic. The\\ncertified queries also correct the chord error"
    " of curved lane offsets.\\nThey cost more and can raise where CARLA'"
    "s query answers, so they are not\\nthe default.\\n\\nThe R-tree, ful"
    "l-center bounds, and optional sampled-curve box covers belong\\nto t"
    "he same construction snapshot. Queries do not update these proofs.\\"
    "nAs with the existing index, callers must rebuild the Map after edit"
    "ing its\\nsource road records. A cover stores only four complete int"
    "erval boxes; it\\ndoes not copy geometry or change the public segmen"
    "t partition.\\n\\n**Order.** CARLA keeps roads, junctions and signal"
    "s in hash maps and\\nwalks them in hash order. This port walks them "
    "in order of id, so a list\\nsuch as `generate_waypoints` holds the s"
    "ame waypoints in a fixed order.\\n\\n**Waypoints keep s in double.**"
    " CARLA steps a waypoint 10 `DBL_EPSILON`\\noff a section's edge, whi"
    "ch a `Float32` cannot hold, so `Waypoint.s` is a\\n`Float64` in mete"
    "rs. Two waypoints are equal when their road, section and\\nlane matc"
    "h and s agrees to 5 millimeters, as CARLA's hash.\\n\\nThe methods t"
    "hat CARLA's client `Map`, `Waypoint` and `Landmark` add on\\ntop, su"
    "ch as `next_until_lane_end`, `lane_change` and `landmark_group`,\\na"
    "re here as well.\\n\\nSource: CARLA 1360bb9, `LibCarla/source/carla/"
    "road/Map.cpp`,\\n`road/Junction.h`, `road/Signal.h`, `road/SignalTyp"
    "e.cpp`,\\n`road/Controller.h`, `road/Object.h`, `road/Deformation.h`"
    ",\\n`road/element/Waypoint.cpp`, `road/element/LaneCrossingCalculato"
    "r.cpp`,\\nand `client/Map.cpp`, `client/Waypoint.cpp`, `client/Landm"
    'ark.h`.\\n\\"\\"\\""]]]'
)

comptime _RIGHT_0 = (
    '[[],[[3,"\\"\\"\\"CARLA\'s `road/Map`: the road network and every'
    " question a car asks it.\\n\\nA `Map` holds the roads, the junctions"
    ", the signals and the signal\\ncontrollers of one OpenDRIVE file. A "
    "`Waypoint` is a place on it: a road,\\na lane section, a lane and a "
    "distance s along the road. The map answers\\nwhere a waypoint is (`c"
    "ompute_transform`), what lies ahead of it (`next`,\\n`successors`), "
    "beside it (`right`, `left`) and on it (`mark_record`,\\n`signals_in_"
    "distance`), and which waypoint is nearest a point\\n(`closest_waypoi"
    "nt_on_road`, `waypoint`).\\n\\n**Two segment indices.** The map keep"
    "s CARLA's heading and length\\npartition in its own R-tree. `closest"
    "_waypoint_on_road`, `waypoint` and\\nthe sign check at load use it w"
    "ith CARLA's algorithm: the nearest segment,\\nthen a step along the "
    "lane to the point's foot. These queries do not use\\nthe certified s"
    "earch budget. Input validation, lane stepping and canonical\\npose e"
    "valuation can still raise errors. They keep CARLA's approximations:"
    "\\nthe step treats distance along the segment chord as road s.\\n\\n"
    "**The certified index.** `certified_closest_waypoint_on_road` and\\n"
    "`certified_waypoint` use a second index. It starts with CARLA's part"
    "ition\\nand splits again at record boundaries and until quarter-poin"
    "t\\nchord errors are at most one millimeter. A required split withou"
    "t an\\ninterior Float64 road-s value raises a resolution error. A po"
    "sitive\\nnonterminal index step must also advance in lane order. The"
    " line and its\\nstored-point minima can still be representable. This"
    " sampled target is not\\nan unsampled error bound. A separate full-c"
    "enter enclosure and the R-tree's\\nbounded distance key control cand"
    "idate admission. An unknown bound keeps\\nthe candidate. Each remain"
    "ing candidate exports a bounded minimum-distance\\ncertificate. Over"
    "lapping candidates resume with their remaining work budget.\\nSelect"
    "ion requires proved dominance; unresolved work raises an accuracy\\n"
    "error. Approximate witnesses require strict classification agreement"
    " across\\nall possible minimizing cells. An exact witness uses its p"
    "roved minimizer.\\nClassification uses the Float64 center before pub"
    "lic location narrowing.\\n\\nCertified queries minimize three-dimens"
    "ional distance to the stored canonical\\nFloat64 lane center over th"
    "e indexed station domains. Station s is the road\\nreference paramet"
    "er, not lane chord length. Public `compute_transform` narrows\\nthat"
    " same center. Road reference and fixed-s helpers describe separate g"
    "eometry.\\nSegment indices resolve exact distance ties. A rounded st"
    "ation plateau keeps\\nits incumbent; the API does not promise the fi"
    "rst station on that plateau.\\n\\nThe public `segment_count` and `se"
    "gment` methods expose this accuracy-driven\\nindex. Its partition an"
    "d count can change when the geometry requires more\\nsubdivision. La"
    "ne order and index tie rules remain deterministic. The\\ncertified q"
    "ueries correct curved lane offsets and the treatment of lane\\ndista"
    "nce as road s. They cost more and can raise where CARLA's query\\nan"
    "swers, so they are not the default.\\n\\nThe R-tree, full-center bou"
    "nds, and optional sampled-curve box covers belong\\nto the same cons"
    "truction snapshot. Queries do not update these proofs.\\nAs with the"
    " existing index, callers must rebuild the Map after editing its\\nso"
    "urce road records. A cover stores only four complete interval boxes;"
    " it\\ndoes not copy geometry or change the public segment partition."
    "\\n\\n**Order.** CARLA keeps roads, junctions and signals in hash ma"
    "ps and\\nwalks them in hash order. This port walks them in order of "
    "id, so a list\\nsuch as `generate_waypoints` holds the same waypoint"
    "s in a fixed order.\\n\\n**Waypoints keep s in double.** CARLA steps"
    " a waypoint 10 `DBL_EPSILON`\\noff a section's edge, which a `Float3"
    "2` cannot hold, so `Waypoint.s` is a\\n`Float64` in meters. Two wayp"
    "oints are equal when their road, section and\\nlane match and s agre"
    "es to 5 millimeters, as CARLA's hash.\\n\\nThe methods that CARLA's "
    "client `Map`, `Waypoint` and `Landmark` add on\\ntop, such as `next_"
    "until_lane_end`, `lane_change` and `landmark_group`,\\nare here as w"
    "ell.\\n\\nSource: CARLA 1360bb9, `LibCarla/source/carla/road/Map.cpp"
    "`,\\n`road/Junction.h`, `road/Signal.h`, `road/SignalType.cpp`,\\n`r"
    "oad/Controller.h`, `road/Object.h`, `road/Deformation.h`,\\n`road/el"
    "ement/Waypoint.cpp`, `road/element/LaneCrossingCalculator.cpp`,\\nan"
    "d `client/Map.cpp`, `client/Waypoint.cpp`, `client/Landmark.h`.\\n\\"
    '"\\"\\""]]]'
)

comptime _LEFT_1 = (
    ',[[],[[1,"from"],[1,"extensions"],[55,"."],[1,"carla"],[55,'
    '"."],[1,"math"],[1,"import"],[55,"("],[1,"make_unit_vector'
    '"],[55,","],[1,"vector_angle"],[55,","],[55,")"]]]'
)

comptime _RIGHT_1 = (
    ',[[],[[1,"from"],[1,"extensions"],[55,"."],[1,"carla"],[55,'
    '"."],[1,"math"],[1,"import"],[55,"("],[1,"distance_segment_'
    'to_point"],[55,","],[1,"make_unit_vector"],[55,","],[1,"vect'
    'or_angle"],[55,","],[55,")"]]]'
)

comptime _LEFT_2 = (
    ',[[],[[1,"from"],[1,"extensions"],[55,"."],[1,"carla"],[55,'
    '"."],[1,"road_info"],[1,"import"],[55,"("],[1,"CHANGE_BOTH'
    '"],[55,","],[1,"CHANGE_LEFT"],[55,","],[1,"CHANGE_RIGHT"],['
    '55,","],[1,"ConId"],[55,","],[1,"ControllerId"],[55,","],['
    '1,"JuncId"],[55,","],[1,"LANE_BIDIRECTIONAL"],[55,","],[1,"'
    'LANE_BIKING"],[55,","],[1,"LANE_DRIVING"],[55,","],[1,"LANE_'
    'PARKING"],[55,","],[1,"LaneChange"],[55,","],[1,"LaneId"],['
    '55,","],[1,"LaneMarking"],[55,","],[1,"LaneType"],[55,","]'
    ',[1,"LaneValidity"],[55,","],[1,"RoadId"],[55,","],[1,"Road'
    'InfoMarkRecord"],[55,","],[1,"RoadInfoSignal"],[55,","],[1,"'
    'SectionId"],[55,","],[1,"SignalId"],[55,","],[1,"SignalOrien'
    'tation"],[55,","],[1,"_info_at_si"],[1,"as"],[1,"info_at"],'
    '[55,","],[1,"_info_index_si"],[1,"as"],[1,"info_index"],[55,'
    '","],[1,"_infos_in_range_si"],[1,"as"],[1,"infos_in_range"],'
    '[55,","],[1,"signal_orientation_of"],[55,","],[55,")"]]]'
)

comptime _RIGHT_2 = (
    ',[[],[[1,"from"],[1,"extensions"],[55,"."],[1,"carla"],[55,'
    '"."],[1,"road_info"],[1,"import"],[55,"("],[1,"CHANGE_BOTH'
    '"],[55,","],[1,"CHANGE_LEFT"],[55,","],[1,"CHANGE_RIGHT"],['
    '55,","],[1,"ConId"],[55,","],[1,"ControllerId"],[55,","],['
    '1,"JuncId"],[55,","],[1,"LANE_BIDIRECTIONAL"],[55,","],[1,"'
    'LANE_BIKING"],[55,","],[1,"LANE_DRIVING"],[55,","],[1,"LANE_'
    'PARKING"],[55,","],[1,"LaneChange"],[55,","],[1,"LaneId"],['
    '55,","],[1,"LaneMarking"],[55,","],[1,"LaneType"],[55,","]'
    ',[1,"LaneValidity"],[55,","],[1,"RoadId"],[55,","],[1,"Road'
    'InfoMarkRecord"],[55,","],[1,"RoadInfoSignal"],[55,","],[1,"'
    'SectionId"],[55,","],[1,"SignalId"],[55,","],[1,"SignalOrien'
    'tation"],[55,","],[1,"info_at"],[55,","],[1,"info_index"],['
    '55,","],[1,"infos_in_range"],[55,","],[1,"signal_orientation_'
    'of"],[55,","],[55,")"]]]'
)

comptime _LEFT_3 = (
    ',[[],[[1,"from"],[1,"std"],[55,"."],[1,"hash"],[1,"import"],[1,"Hasher"]]]'
)

comptime _RIGHT_3 = (
    ',[[],[[1,"from"],[1,"std"],[55,"."],[1,"hashlib"],[1,"impor'
    't"],[1,"Hasher"]]]'
)

comptime _LEFT_4 = (
    ',[[],[[1,"from"],[1,"extensions"],[55,"."],[1,"carla"],[55,'
    '"."],[1,"quantity_boundary"],[1,"import"],[55,"("],[1,"_RAW'
    '_SI"],[55,","],[1,"_RawSI"],[55,","],[1,"_finite_si"],[55,'
    '","],[1,"_nonnegative_si"],[55,","],[1,"_positive_si"],[55,'
    '","],[55,")"]]],[[],[[1,"from"],[1,"units"],[55,"."],[1,"'
    'si"],[1,"import"],[1,"DEGREE"],[55,","],[1,"Angle"],[55,",'
    '"],[1,"Length"],[55,","],[1,"Length64"],[55,","],[1,"METER'
    '"],[55,","],[1,"Velocity64"]]],[[],[[1,"from"],[1,"units"],'
    '[55,"."],[1,"si"],[1,"import"],[1,"Angle64"]]]'
)

comptime _RIGHT_4 = (
    ',[[],[[1,"from"],[1,"units"],[55,"."],[1,"si"],[1,"import"'
    '],[1,"DEGREE"],[55,","],[1,"Angle"],[55,","],[1,"Length"],'
    '[55,","],[1,"METER"],[55,","],[1,"Velocity64"]]]'
)

comptime _LEFT_5 = (
    ',[[],[[1,"comptime"],[1,"DOUBLE_EPSILON"],[55,"="],[2,"2.2204'
    '46049250313e-16"]]]'
)

comptime _RIGHT_5 = (
    ',[[],[[1,"comptime"],[1,"DOUBLE_EPSILON"],[55,"="],[2,"2.2204'
    '46049250313e-16"]]],[[],[[55,"@"],[1,"fieldwise_init"]]]'
)

comptime _LEFT_6 = (
    ',[[["struct","Waypoint"]],[[1,"def"],[1,"__init__"],[55,"('
    '"],[1,"out"],[1,"self"],[55,","],[1,"road_id"],[55,":"],['
    '1,"RoadId"],[55,","],[1,"section_id"],[55,":"],[1,"SectionI'
    'd"],[55,","],[1,"lane_id"],[55,":"],[1,"LaneId"],[55,","]'
    ',[1,"s"],[55,":"],[1,"Length64"],[55,","],[55,")"],[1,"ra'
    'ises"],[55,":"]]],[[["struct","Waypoint"]],[[55,"@"],[1,"s'
    'taticmethod"]]],[[["struct","Waypoint"]],[[1,"def"],[1,"from'
    '_si"],[55,"("],[1,"road_id"],[55,":"],[1,"RoadId"],[55,",'
    '"],[1,"section_id"],[55,":"],[1,"SectionId"],[55,","],[1,"'
    'lane_id"],[55,":"],[1,"LaneId"],[55,","],[1,"s"],[55,":"]'
    ',[1,"Float64"],[55,")"],[1,"raises"],[55,"->"],[1,"Waypoint'
    '"],[55,":"]]],[[["struct","Waypoint"]],[[55,"@"],[1,"stati'
    'cmethod"]]],[[["struct","Waypoint"]],[[1,"def"],[1,"_from_si'
    '"],[55,"("],[1,"road_id"],[55,":"],[1,"RoadId"],[55,","],'
    '[1,"section_id"],[55,":"],[1,"SectionId"],[55,","],[1,"lane'
    '_id"],[55,":"],[1,"LaneId"],[55,","],[1,"s"],[55,":"],[1,'
    '"Float64"],[55,")"],[55,"->"],[1,"Waypoint"],[55,":"]]],[['
    '["struct","Waypoint"]],[[1,"def"],[1,"__init__"],[55,"("],'
    '[1,"out"],[1,"self"],[55,","],[1,"raw"],[55,":"],[1,"_Raw'
    'SI"],[55,","],[1,"road_id"],[55,":"],[1,"RoadId"],[55,","'
    '],[1,"section_id"],[55,":"],[1,"SectionId"],[55,","],[1,"la'
    'ne_id"],[55,":"],[1,"LaneId"],[55,","],[1,"s"],[55,":"],['
    '1,"Float64"],[55,","],[55,")"],[55,":"]]]'
)

comptime _RIGHT_6 = ""

comptime _LEFT_7 = (
    ',[[["struct","Waypoint"]],[[1,"def"],[1,"s_quantity"],[55,"'
    '("],[1,"self"],[55,")"],[1,"raises"],[55,"->"],[1,"Length6'
    '4"],[55,":"]]]'
)

comptime _RIGHT_7 = ""

comptime _LEFT_8 = (
    ',[[["struct","Signal"]],[[1,"def"],[1,"__init__"],[55,"("]'
    ',[1,"out"],[1,"self"],[55,","],[1,"road_id"],[55,":"],[1,'
    '"RoadId"],[55,","],[1,"signal_id"],[55,":"],[1,"SignalId"]'
    ',[55,","],[1,"s"],[55,":"],[1,"Length64"],[55,","],[1,"t'
    '"],[55,":"],[1,"Length64"],[55,","],[1,"name"],[55,":"],['
    '1,"String"],[55,","],[1,"dynamic"],[55,":"],[1,"String"],['
    '55,","],[1,"orientation"],[55,":"],[1,"String"],[55,","],['
    '1,"z_offset"],[55,":"],[1,"Length64"],[55,","],[1,"country'
    '"],[55,":"],[1,"String"],[55,","],[1,"type"],[55,":"],[1,'
    '"String"],[55,","],[1,"subtype"],[55,":"],[1,"String"],[55'
    ',","],[1,"value"],[55,":"],[1,"Float64"],[55,","],[1,"uni'
    't"],[55,":"],[1,"String"],[55,","],[1,"height"],[55,":"],'
    '[1,"Length64"],[55,","],[1,"width"],[55,":"],[1,"Length64"'
    '],[55,","],[1,"text"],[55,":"],[1,"String"],[55,","],[1,"'
    'h_offset"],[55,":"],[1,"Angle64"],[55,","],[1,"pitch"],[55,'
    '":"],[1,"Angle64"],[55,","],[1,"roll"],[55,":"],[1,"Angle'
    '64"],[55,","],[1,"value_present"],[55,":"],[1,"Bool"],[55,'
    '"="],[1,"True"],[55,","],[55,")"],[1,"raises"],[55,":"]]'
    '],[[["struct","Signal"]],[[55,"@"],[1,"staticmethod"]]],[[['
    '"struct","Signal"]],[[1,"def"],[1,"from_si"],[55,"("],[1,'
    '"road_id"],[55,":"],[1,"RoadId"],[55,","],[1,"signal_id"],'
    '[55,":"],[1,"SignalId"],[55,","],[1,"s"],[55,":"],[1,"Flo'
    'at64"],[55,","],[1,"t"],[55,":"],[1,"Float64"],[55,","],['
    '1,"name"],[55,":"],[1,"String"],[55,","],[1,"dynamic"],[55'
    ',":"],[1,"String"],[55,","],[1,"orientation"],[55,":"],[1,'
    '"String"],[55,","],[1,"z_offset"],[55,":"],[1,"Float64"],['
    '55,","],[1,"country"],[55,":"],[1,"String"],[55,","],[1,"'
    'type"],[55,":"],[1,"String"],[55,","],[1,"subtype"],[55,":'
    '"],[1,"String"],[55,","],[1,"value"],[55,":"],[1,"Float64'
    '"],[55,","],[1,"unit"],[55,":"],[1,"String"],[55,","],[1,'
    '"height"],[55,":"],[1,"Float64"],[55,","],[1,"width"],[55,'
    '":"],[1,"Float64"],[55,","],[1,"text"],[55,":"],[1,"Strin'
    'g"],[55,","],[1,"h_offset"],[55,":"],[1,"Float64"],[55,",'
    '"],[1,"pitch"],[55,":"],[1,"Float64"],[55,","],[1,"roll"]'
    ',[55,":"],[1,"Float64"],[55,","],[1,"value_present"],[55,":'
    '"],[1,"Bool"],[55,"="],[1,"True"],[55,","],[55,")"],[1,"'
    'raises"],[55,"->"],[1,"Signal"],[55,":"]]],[[["struct","Si'
    'gnal"]],[[55,"@"],[1,"staticmethod"]]],[[["struct","Signal"'
    ']],[[1,"def"],[1,"_from_si"],[55,"("],[1,"road_id"],[55,":'
    '"],[1,"RoadId"],[55,","],[1,"signal_id"],[55,":"],[1,"Sign'
    'alId"],[55,","],[1,"s"],[55,":"],[1,"Float64"],[55,","],['
    '1,"t"],[55,":"],[1,"Float64"],[55,","],[1,"name"],[55,":'
    '"],[1,"String"],[55,","],[1,"dynamic"],[55,":"],[1,"String'
    '"],[55,","],[1,"orientation"],[55,":"],[1,"String"],[55,",'
    '"],[1,"z_offset"],[55,":"],[1,"Float64"],[55,","],[1,"coun'
    'try"],[55,":"],[1,"String"],[55,","],[1,"type"],[55,":"],'
    '[1,"String"],[55,","],[1,"subtype"],[55,":"],[1,"String"],'
    '[55,","],[1,"value"],[55,":"],[1,"Float64"],[55,","],[1,"'
    'unit"],[55,":"],[1,"String"],[55,","],[1,"height"],[55,":'
    '"],[1,"Float64"],[55,","],[1,"width"],[55,":"],[1,"Float64'
    '"],[55,","],[1,"text"],[55,":"],[1,"String"],[55,","],[1,'
    '"h_offset"],[55,":"],[1,"Float64"],[55,","],[1,"pitch"],[5'
    '5,":"],[1,"Float64"],[55,","],[1,"roll"],[55,":"],[1,"Flo'
    'at64"],[55,","],[1,"value_present"],[55,":"],[1,"Bool"],[55'
    ',"="],[1,"True"],[55,","],[55,")"],[1,"raises"],[55,"->"'
    '],[1,"Signal"],[55,":"]]],[[["struct","Signal"]],[[1,"def"'
    '],[1,"__init__"],[55,"("],[1,"out"],[1,"self"],[55,","],[1'
    ',"raw"],[55,":"],[1,"_RawSI"],[55,","],[1,"road_id"],[55,'
    '":"],[1,"RoadId"],[55,","],[1,"signal_id"],[55,":"],[1,"S'
    'ignalId"],[55,","],[1,"s"],[55,":"],[1,"Float64"],[55,","'
    '],[1,"t"],[55,":"],[1,"Float64"],[55,","],[1,"name"],[55,'
    '":"],[1,"String"],[55,","],[1,"dynamic"],[55,":"],[1,"Str'
    'ing"],[55,","],[1,"orientation"],[55,":"],[1,"String"],[55,'
    '","],[1,"z_offset"],[55,":"],[1,"Float64"],[55,","],[1,"c'
    'ountry"],[55,":"],[1,"String"],[55,","],[1,"type"],[55,":'
    '"],[1,"String"],[55,","],[1,"subtype"],[55,":"],[1,"String'
    '"],[55,","],[1,"value"],[55,":"],[1,"Float64"],[55,","],['
    '1,"unit"],[55,":"],[1,"String"],[55,","],[1,"height"],[55,'
    '":"],[1,"Float64"],[55,","],[1,"width"],[55,":"],[1,"Floa'
    't64"],[55,","],[1,"text"],[55,":"],[1,"String"],[55,","],'
    '[1,"h_offset"],[55,":"],[1,"Float64"],[55,","],[1,"pitch"]'
    ',[55,":"],[1,"Float64"],[55,","],[1,"roll"],[55,":"],[1,"'
    'Float64"],[55,","],[1,"value_present"],[55,":"],[1,"Bool"],'
    '[55,"="],[1,"True"],[55,","],[55,")"],[1,"raises"],[55,":'
    '"]]]'
)

comptime _RIGHT_8 = (
    ',[[["struct","Signal"]],[[1,"def"],[1,"__init__"],[55,"("]'
    ',[1,"out"],[1,"self"],[55,","],[1,"road_id"],[55,":"],[1,'
    '"RoadId"],[55,","],[1,"signal_id"],[55,":"],[1,"SignalId"]'
    ',[55,","],[1,"s"],[55,":"],[1,"Float64"],[55,","],[1,"t"'
    '],[55,":"],[1,"Float64"],[55,","],[1,"name"],[55,":"],[1,'
    '"String"],[55,","],[1,"dynamic"],[55,":"],[1,"String"],[55'
    ',","],[1,"orientation"],[55,":"],[1,"String"],[55,","],[1,'
    '"z_offset"],[55,":"],[1,"Float64"],[55,","],[1,"country"],'
    '[55,":"],[1,"String"],[55,","],[1,"type"],[55,":"],[1,"St'
    'ring"],[55,","],[1,"subtype"],[55,":"],[1,"String"],[55,",'
    '"],[1,"value"],[55,":"],[1,"Float64"],[55,","],[1,"unit"]'
    ',[55,":"],[1,"String"],[55,","],[1,"height"],[55,":"],[1,'
    '"Float64"],[55,","],[1,"width"],[55,":"],[1,"Float64"],[55'
    ',","],[1,"text"],[55,":"],[1,"String"],[55,","],[1,"h_off'
    'set"],[55,":"],[1,"Float64"],[55,","],[1,"pitch"],[55,":"'
    '],[1,"Float64"],[55,","],[1,"roll"],[55,":"],[1,"Float64"]'
    ',[55,","],[1,"value_present"],[55,":"],[1,"Bool"],[55,"="]'
    ',[1,"True"],[55,","],[55,")"],[1,"raises"],[55,":"]]]'
)

comptime _LEFT_9 = (
    ',[[["struct","Signal"]],[[1,"def"],[1,"s_quantity"],[55,"('
    '"],[1,"self"],[55,")"],[1,"raises"],[55,"->"],[1,"Length64'
    '"],[55,":"]]],[[["struct","Signal"]],[[1,"def"],[1,"t_quan'
    'tity"],[55,"("],[1,"self"],[55,")"],[1,"raises"],[55,"->"'
    '],[1,"Length64"],[55,":"]]],[[["struct","Signal"]],[[1,"def'
    '"],[1,"z_offset_quantity"],[55,"("],[1,"self"],[55,")"],[1,'
    '"raises"],[55,"->"],[1,"Length64"],[55,":"]]],[[["struct",'
    '"Signal"]],[[1,"def"],[1,"height_quantity"],[55,"("],[1,"se'
    'lf"],[55,")"],[1,"raises"],[55,"->"],[1,"Length64"],[55,":'
    '"]]],[[["struct","Signal"]],[[1,"def"],[1,"width_quantity"]'
    ',[55,"("],[1,"self"],[55,")"],[1,"raises"],[55,"->"],[1,"'
    'Length64"],[55,":"]]],[[["struct","Signal"]],[[1,"def"],[1,'
    '"h_offset_quantity"],[55,"("],[1,"self"],[55,")"],[1,"raise'
    's"],[55,"->"],[1,"Angle64"],[55,":"]]],[[["struct","Signal'
    '"]],[[1,"def"],[1,"pitch_quantity"],[55,"("],[1,"self"],[55'
    ',")"],[1,"raises"],[55,"->"],[1,"Angle64"],[55,":"]]],[[['
    '"struct","Signal"]],[[1,"def"],[1,"roll_quantity"],[55,"("'
    '],[1,"self"],[55,")"],[1,"raises"],[55,"->"],[1,"Angle64"]'
    ',[55,":"]]]'
)

comptime _RIGHT_9 = ""

comptime _LEFT_10 = (
    ',[[["struct","RoadObject"]],[[1,"def"],[1,"s_quantity"],[55,'
    '"("],[1,"self"],[55,")"],[1,"raises"],[55,"->"],[1,"Lengt'
    'h64"],[55,":"]]],[[["struct","RoadObject"]],[[1,"def"],[1,'
    '"t_quantity"],[55,"("],[1,"self"],[55,")"],[1,"raises"],[5'
    '5,"->"],[1,"Length64"],[55,":"]]],[[["struct","RoadObject"'
    ']],[[1,"def"],[1,"z_offset_quantity"],[55,"("],[1,"self"],[5'
    '5,")"],[1,"raises"],[55,"->"],[1,"Length64"],[55,":"]]],[['
    '["struct","RoadObject"]],[[1,"def"],[1,"valid_length_quantity'
    '"],[55,"("],[1,"self"],[55,")"],[1,"raises"],[55,"->"],[1'
    ',"Length64"],[55,":"]]],[[["struct","RoadObject"]],[[1,"def'
    '"],[1,"length_quantity"],[55,"("],[1,"self"],[55,")"],[1,"'
    'raises"],[55,"->"],[1,"Length64"],[55,":"]]],[[["struct","'
    'RoadObject"]],[[1,"def"],[1,"width_quantity"],[55,"("],[1,"s'
    'elf"],[55,")"],[1,"raises"],[55,"->"],[1,"Length64"],[55,"'
    ':"]]],[[["struct","RoadObject"]],[[1,"def"],[1,"heading_quan'
    'tity"],[55,"("],[1,"self"],[55,")"],[1,"raises"],[55,"->"'
    '],[1,"Angle64"],[55,":"]]],[[["struct","RoadObject"]],[[1,"'
    'def"],[1,"pitch_quantity"],[55,"("],[1,"self"],[55,")"],[1,'
    '"raises"],[55,"->"],[1,"Angle64"],[55,":"]]],[[["struct",'
    '"RoadObject"]],[[1,"def"],[1,"roll_quantity"],[55,"("],[1,"'
    'self"],[55,")"],[1,"raises"],[55,"->"],[1,"Angle64"],[55,"'
    ':"]]]'
)

comptime _RIGHT_10 = ""

comptime _LEFT_11 = (
    ',[[["struct","SignalSearchData"]],[[1,"def"],[1,"__init__"],'
    '[55,"("],[1,"out"],[1,"self"],[55,","],[1,"signal"],[55,"'
    ':"],[1,"RoadInfoSignal"],[55,","],[1,"waypoint"],[55,":"],['
    '1,"Waypoint"],[55,","],[1,"accumulated_s"],[55,":"],[1,"Len'
    'gth64"],[55,","],[55,")"],[1,"raises"],[55,":"]]],[[["stru'
    'ct","SignalSearchData"]],[[55,"@"],[1,"staticmethod"]]],[[["'
    'struct","SignalSearchData"]],[[1,"def"],[1,"from_si"],[55,"('
    '"],[1,"signal"],[55,":"],[1,"RoadInfoSignal"],[55,","],[1,'
    '"waypoint"],[55,":"],[1,"Waypoint"],[55,","],[1,"accumulate'
    'd_s"],[55,":"],[1,"Float64"],[55,","],[55,")"],[1,"raises'
    '"],[55,"->"],[1,"SignalSearchData"],[55,":"]]],[[["struct",'
    '"SignalSearchData"]],[[55,"@"],[1,"staticmethod"]]],[[["struc'
    't","SignalSearchData"]],[[1,"def"],[1,"_from_si"],[55,"("],'
    '[1,"signal"],[55,":"],[1,"RoadInfoSignal"],[55,","],[1,"way'
    'point"],[55,":"],[1,"Waypoint"],[55,","],[1,"accumulated_s"'
    '],[55,":"],[1,"Float64"],[55,","],[55,")"],[55,"->"],[1,"'
    'SignalSearchData"],[55,":"]]],[[["struct","SignalSearchData"]'
    '],[[1,"def"],[1,"__init__"],[55,"("],[1,"out"],[1,"self"],'
    '[55,","],[1,"raw"],[55,":"],[1,"_RawSI"],[55,","],[1,"sig'
    'nal"],[55,":"],[1,"RoadInfoSignal"],[55,","],[1,"waypoint"]'
    ',[55,":"],[1,"Waypoint"],[55,","],[1,"accumulated_s"],[55,"'
    ':"],[1,"Float64"],[55,","],[55,")"],[55,":"]]],[[["struct'
    '","SignalSearchData"]],[[1,"def"],[1,"accumulated_s_quantity"'
    '],[55,"("],[1,"self"],[55,")"],[1,"raises"],[55,"->"],[1,'
    '"Length64"],[55,":"]]]'
)

comptime _RIGHT_11 = (
    ',[[["struct","SignalSearchData"]],[[1,"def"],[1,"__init__"],'
    '[55,"("],[1,"out"],[1,"self"],[55,","],[1,"signal"],[55,"'
    ':"],[1,"RoadInfoSignal"],[55,","],[1,"waypoint"],[55,":"],['
    '1,"Waypoint"],[55,","],[1,"accumulated_s"],[55,":"],[1,"Flo'
    'at64"],[55,","],[55,")"],[55,":"]]]'
)

comptime _LEFT_12 = (
    ',[[["struct","Landmark"]],[[1,"def"],[1,"__init__"],[55,"('
    '"],[1,"out"],[1,"self"],[55,","],[1,"waypoint"],[55,":"],'
    '[1,"Optional"],[55,"["],[1,"Waypoint"],[55,"]"],[55,","],['
    '1,"reference"],[55,":"],[1,"RoadInfoSignal"],[55,","],[1,"d'
    'istance"],[55,":"],[1,"Length64"],[55,","],[55,")"],[1,"ra'
    'ises"],[55,":"]]],[[["struct","Landmark"]],[[55,"@"],[1,"s'
    'taticmethod"]]],[[["struct","Landmark"]],[[1,"def"],[1,"from'
    '_si"],[55,"("],[1,"waypoint"],[55,":"],[1,"Optional"],[55,'
    '"["],[1,"Waypoint"],[55,"]"],[55,","],[1,"reference"],[55,'
    '":"],[1,"RoadInfoSignal"],[55,","],[1,"distance"],[55,":"]'
    ',[1,"Float64"],[55,","],[55,")"],[1,"raises"],[55,"->"],[1'
    ',"Landmark"],[55,":"]]],[[["struct","Landmark"]],[[55,"@"]'
    ',[1,"staticmethod"]]],[[["struct","Landmark"]],[[1,"def"],[1'
    ',"_from_si"],[55,"("],[1,"waypoint"],[55,":"],[1,"Optional'
    '"],[55,"["],[1,"Waypoint"],[55,"]"],[55,","],[1,"reference'
    '"],[55,":"],[1,"RoadInfoSignal"],[55,","],[1,"distance"],[5'
    '5,":"],[1,"Float64"],[55,","],[55,")"],[55,"->"],[1,"Land'
    'mark"],[55,":"]]],[[["struct","Landmark"]],[[1,"def"],[1,"'
    '__init__"],[55,"("],[1,"out"],[1,"self"],[55,","],[1,"raw'
    '"],[55,":"],[1,"_RawSI"],[55,","],[1,"waypoint"],[55,":"]'
    ',[1,"Optional"],[55,"["],[1,"Waypoint"],[55,"]"],[55,","],'
    '[1,"reference"],[55,":"],[1,"RoadInfoSignal"],[55,","],[1,"'
    'distance"],[55,":"],[1,"Float64"],[55,","],[55,")"],[55,":'
    '"]]],[[["struct","Landmark"]],[[1,"def"],[1,"distance_quanti'
    'ty"],[55,"("],[1,"self"],[55,")"],[1,"raises"],[55,"->"],'
    '[1,"Length64"],[55,":"]]]'
)

comptime _RIGHT_12 = (
    ',[[["struct","Landmark"]],[[1,"def"],[1,"__init__"],[55,"('
    '"],[1,"out"],[1,"self"],[55,","],[1,"waypoint"],[55,":"],'
    '[1,"Optional"],[55,"["],[1,"Waypoint"],[55,"]"],[55,","],['
    '1,"reference"],[55,":"],[1,"RoadInfoSignal"],[55,","],[1,"d'
    'istance"],[55,":"],[1,"Float64"],[55,","],[55,")"],[55,":'
    '"]]]'
)

comptime _LEFT_13 = (
    ',[[["struct","_Segment"]],[[1,"var"],[1,"deviation"],[55,":'
    '"],[1,"Float64"]]]'
)

comptime _RIGHT_13 = ""

comptime _LEFT_14 = (
    ',[[],[[1,"def"],[1,"segment_distance_2d"],[55,"("],[1,"a1"],'
    '[55,":"],[1,"Vector3"],[55,","],[1,"a2"],[55,":"],[1,"Vec'
    'tor3"],[55,","],[1,"b1"],[55,":"],[1,"Vector3"],[55,","],'
    '[1,"b2"],[55,":"],[1,"Vector3"],[55,")"],[1,"raises"],[55,'
    '"->"],[1,"Length64"],[55,":"]]],[[],[[1,"def"],[1,"segment_'
    'distance_2d_meters"],[55,"("],[1,"a1"],[55,":"],[1,"Vector3'
    '"],[55,","],[1,"a2"],[55,":"],[1,"Vector3"],[55,","],[1,'
    '"b1"],[55,":"],[1,"Vector3"],[55,","],[1,"b2"],[55,":"],'
    '[1,"Vector3"],[55,")"],[1,"raises"],[55,"->"],[1,"Float64"'
    '],[55,":"]]],[[],[[1,"def"],[1,"_segment_distance_2d_si"],[55,'
    '"("],[1,"a1"],[55,":"],[1,"Vector3"],[55,","],[1,"a2"],['
    '55,":"],[1,"Vector3"],[55,","],[1,"b1"],[55,":"],[1,"Vect'
    'or3"],[55,","],[1,"b2"],[55,":"],[1,"Vector3"],[55,")"],['
    '55,"->"],[1,"Float64"],[55,":"]]],[[],[[1,"def"],[1,"_chord'
    '_station_delta"],[55,"("],[1,"location"],[55,":"],[1,"Vector'
    '3"],[55,","],[1,"start"],[55,":"],[1,"Vector3"],[55,","],'
    '[1,"end"],[55,":"],[1,"Vector3"],[55,","],[1,"span"],[55,'
    '":"],[1,"Float64"],[55,")"],[55,"->"],[1,"Float64"],[55,"'
    ':"]]]'
)

comptime _RIGHT_14 = (
    ',[[],[[1,"def"],[1,"segment_distance_2d"],[55,"("],[1,"a1"],'
    '[55,":"],[1,"Vector3"],[55,","],[1,"a2"],[55,":"],[1,"Vec'
    'tor3"],[55,","],[1,"b1"],[55,":"],[1,"Vector3"],[55,","],'
    '[1,"b2"],[55,":"],[1,"Vector3"],[55,")"],[55,"->"],[1,"Fl'
    'oat64"],[55,":"]]]'
)

comptime _LEFT_15 = (
    ',[[],[[1,"def"],[1,"_winner_seed_update_score"],[55,"("],[1,"'
    'point"],[55,":"],[1,"Array"],[55,"["],[1,"Float64"],[55,",'
    '"],[2,"3"],[55,"]"],[55,","],[1,"incumbent"],[55,":"],[1,'
    '"Array"],[55,"["],[1,"Float64"],[55,","],[2,"3"],[55,"]"'
    '],[55,","],[1,"query"],[55,":"],[1,"Array"],[55,"["],[1,"'
    'Float64"],[55,","],[2,"3"],[55,"]"],[55,","],[1,"scale"],'
    '[55,":"],[1,"Float64"],[55,","],[55,")"],[1,"raises"],[55,'
    '"->"],[1,"Tuple"],[55,"["],[1,"Bool"],[55,","],[1,"Float6'
    '4"],[55,"]"],[55,":"]]]'
)

comptime _RIGHT_15 = ""

comptime _LEFT_16 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"lane_width"],[55,"("],'
    '[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"Waypoint"]'
    ',[55,")"],[1,"raises"],[55,"->"],[1,"Length64"],[55,":"]]]'
    ',[[["struct","Map"]],[[1,"def"],[1,"lane_width_float32"],[55'
    ',"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"Way'
    'point"],[55,")"],[1,"raises"],[55,"->"],[1,"Length"],[55,"'
    ':"]]]'
)

comptime _RIGHT_16 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"lane_width"],[55,"("],'
    '[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"Waypoint"]'
    ',[55,")"],[1,"raises"],[55,"->"],[1,"Length"],[55,":"]]]'
)

comptime _LEFT_17 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"waypoint_xodr"],[55,"('
    '"],[1,"self"],[55,","],[1,"road_id"],[55,":"],[1,"RoadId"'
    '],[55,","],[1,"lane_id"],[55,":"],[1,"LaneId"],[55,","],[1'
    ',"s"],[55,":"],[1,"Length64"],[55,")"],[1,"raises"],[55,"'
    '->"],[1,"Optional"],[55,"["],[1,"Waypoint"],[55,"]"],[55,"'
    ':"]]],[[["struct","Map"]],[[1,"def"],[1,"waypoint_xodr_float'
    '32"],[55,"("],[1,"self"],[55,","],[1,"road_id"],[55,":"],'
    '[1,"RoadId"],[55,","],[1,"lane_id"],[55,":"],[1,"LaneId"],'
    '[55,","],[1,"s"],[55,":"],[1,"Length"],[55,")"],[1,"raise'
    's"],[55,"->"],[1,"Optional"],[55,"["],[1,"Waypoint"],[55,"'
    ']"],[55,":"]]]'
)

comptime _RIGHT_17 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"waypoint_xodr"],[55,"('
    '"],[1,"self"],[55,","],[1,"road_id"],[55,":"],[1,"RoadId"'
    '],[55,","],[1,"lane_id"],[55,":"],[1,"LaneId"],[55,","],[1'
    ',"s"],[55,":"],[1,"Length"],[55,")"],[1,"raises"],[55,"->'
    '"],[1,"Optional"],[55,"["],[1,"Waypoint"],[55,"]"],[55,":'
    '"]]]'
)

comptime _LEFT_18 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"next"],[55,"("],[1,"s'
    'elf"],[55,","],[1,"waypoint"],[55,":"],[1,"Waypoint"],[55,'
    '","],[1,"distance"],[55,":"],[1,"Length64"],[55,")"],[1,"'
    'raises"],[55,"->"],[1,"List"],[55,"["],[1,"Waypoint"],[55,'
    '"]"],[55,":"]]],[[["struct","Map"]],[[1,"def"],[1,"next_m'
    'eters"],[55,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":'
    '"],[1,"Waypoint"],[55,","],[1,"distance"],[55,":"],[1,"Flo'
    'at64"],[55,")"],[1,"raises"],[55,"->"],[1,"List"],[55,"["'
    '],[1,"Waypoint"],[55,"]"],[55,":"]]],[[["struct","Map"]],['
    '[1,"def"],[1,"previous"],[55,"("],[1,"self"],[55,","],[1,'
    '"waypoint"],[55,":"],[1,"Waypoint"],[55,","],[1,"distance"'
    '],[55,":"],[1,"Length64"],[55,")"],[1,"raises"],[55,"->"],'
    '[1,"List"],[55,"["],[1,"Waypoint"],[55,"]"],[55,":"]]],[[['
    '"struct","Map"]],[[1,"def"],[1,"previous_meters"],[55,"("]'
    ',[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"Waypoint"'
    '],[55,","],[1,"distance"],[55,":"],[1,"Float64"],[55,")"],'
    '[1,"raises"],[55,"->"],[1,"List"],[55,"["],[1,"Waypoint"],'
    '[55,"]"],[55,":"]]]'
)

comptime _RIGHT_18 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"next"],[55,"("],[1,"s'
    'elf"],[55,","],[1,"waypoint"],[55,":"],[1,"Waypoint"],[55,'
    '","],[1,"distance"],[55,":"],[1,"Float64"],[55,")"],[1,"r'
    'aises"],[55,"->"],[1,"List"],[55,"["],[1,"Waypoint"],[55,"'
    ']"],[55,":"]]],[[["struct","Map"]],[[1,"def"],[1,"previous'
    '"],[55,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],['
    '1,"Waypoint"],[55,","],[1,"distance"],[55,":"],[1,"Float64'
    '"],[55,")"],[1,"raises"],[55,"->"],[1,"List"],[55,"["],[1'
    ',"Waypoint"],[55,"]"],[55,":"]]]'
)

comptime _LEFT_19 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"generate_waypoints"],[55'
    ',"("],[1,"self"],[55,","],[1,"distance"],[55,":"],[1,"Len'
    'gth64"],[55,")"],[1,"raises"],[55,"->"],[1,"List"],[55,"['
    '"],[1,"Waypoint"],[55,"]"],[55,":"]]],[[["struct","Map"]]'
    ',[[1,"def"],[1,"generate_waypoints_meters"],[55,"("],[1,"self'
    '"],[55,","],[1,"distance"],[55,":"],[1,"Float64"],[55,")"'
    '],[1,"raises"],[55,"->"],[1,"List"],[55,"["],[1,"Waypoint"'
    '],[55,"]"],[55,":"]]]'
)

comptime _RIGHT_19 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"generate_waypoints"],[55'
    ',"("],[1,"self"],[55,","],[1,"distance"],[55,":"],[1,"Flo'
    'at64"],[55,")"],[1,"raises"],[55,"->"],[1,"List"],[55,"["'
    '],[1,"Waypoint"],[55,"]"],[55,":"]]]'
)

comptime _LEFT_20 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"signals_in_distance"],[5'
    '5,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"Wa'
    'ypoint"],[55,","],[1,"distance"],[55,":"],[1,"Length64"],[5'
    '5,","],[1,"stop_at_junction"],[55,":"],[1,"Bool"],[55,"="]'
    ',[1,"False"],[55,","],[55,")"],[1,"raises"],[55,"->"],[1,'
    '"List"],[55,"["],[1,"SignalSearchData"],[55,"]"],[55,":"]]'
    '],[[["struct","Map"]],[[1,"def"],[1,"signals_in_distance_mete'
    'rs"],[55,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"]'
    ',[1,"Waypoint"],[55,","],[1,"distance"],[55,":"],[1,"Float6'
    '4"],[55,","],[1,"stop_at_junction"],[55,":"],[1,"Bool"],[55'
    ',"="],[1,"False"],[55,","],[55,")"],[1,"raises"],[55,"->'
    '"],[1,"List"],[55,"["],[1,"SignalSearchData"],[55,"]"],[55,'
    '":"]]]'
)

comptime _RIGHT_20 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"signals_in_distance"],[5'
    '5,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"Wa'
    'ypoint"],[55,","],[1,"distance"],[55,":"],[1,"Float64"],[55'
    ',","],[1,"stop_at_junction"],[55,":"],[1,"Bool"],[55,"="],'
    '[1,"False"],[55,","],[55,")"],[1,"raises"],[55,"->"],[1,"'
    'List"],[55,"["],[1,"SignalSearchData"],[55,"]"],[55,":"]]]'
)

comptime _LEFT_21 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"next_until_lane_end"],[5'
    '5,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"Wa'
    'ypoint"],[55,","],[1,"distance"],[55,":"],[1,"Length64"],[5'
    '5,")"],[1,"raises"],[55,"->"],[1,"List"],[55,"["],[1,"Way'
    'point"],[55,"]"],[55,":"]]],[[["struct","Map"]],[[1,"def"'
    '],[1,"next_until_lane_end_meters"],[55,"("],[1,"self"],[55,",'
    '"],[1,"waypoint"],[55,":"],[1,"Waypoint"],[55,","],[1,"dis'
    'tance"],[55,":"],[1,"Float64"],[55,")"],[1,"raises"],[55,"'
    '->"],[1,"List"],[55,"["],[1,"Waypoint"],[55,"]"],[55,":"]'
    ']],[[["struct","Map"]],[[1,"def"],[1,"previous_until_lane_sta'
    'rt"],[55,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"]'
    ',[1,"Waypoint"],[55,","],[1,"distance"],[55,":"],[1,"Length'
    '64"],[55,")"],[1,"raises"],[55,"->"],[1,"List"],[55,"["],'
    '[1,"Waypoint"],[55,"]"],[55,":"]]],[[["struct","Map"]],[[1'
    ',"def"],[1,"previous_until_lane_start_meters"],[55,"("],[1,"s'
    'elf"],[55,","],[1,"waypoint"],[55,":"],[1,"Waypoint"],[55,'
    '","],[1,"distance"],[55,":"],[1,"Float64"],[55,")"],[1,"r'
    'aises"],[55,"->"],[1,"List"],[55,"["],[1,"Waypoint"],[55,"'
    ']"],[55,":"]]]'
)

comptime _RIGHT_21 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"next_until_lane_end"],[5'
    '5,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"Wa'
    'ypoint"],[55,","],[1,"distance"],[55,":"],[1,"Float64"],[55'
    ',")"],[1,"raises"],[55,"->"],[1,"List"],[55,"["],[1,"Wayp'
    'oint"],[55,"]"],[55,":"]]],[[["struct","Map"]],[[1,"def"]'
    ',[1,"previous_until_lane_start"],[55,"("],[1,"self"],[55,","'
    '],[1,"waypoint"],[55,":"],[1,"Waypoint"],[55,","],[1,"dista'
    'nce"],[55,":"],[1,"Float64"],[55,")"],[1,"raises"],[55,"->'
    '"],[1,"List"],[55,"["],[1,"Waypoint"],[55,"]"],[55,":"]]]'
)

comptime _LEFT_22 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"landmarks_in_distance"],'
    '[55,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"'
    'Waypoint"],[55,","],[1,"distance"],[55,":"],[1,"Length64"],'
    '[55,","],[1,"stop_at_junction"],[55,":"],[1,"Bool"],[55,"='
    '"],[1,"False"],[55,","],[55,")"],[1,"raises"],[55,"->"],['
    '1,"List"],[55,"["],[1,"Landmark"],[55,"]"],[55,":"]]],[[['
    '"struct","Map"]],[[1,"def"],[1,"landmarks_in_distance_meters'
    '"],[55,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],['
    '1,"Waypoint"],[55,","],[1,"distance"],[55,":"],[1,"Float64'
    '"],[55,","],[1,"stop_at_junction"],[55,":"],[1,"Bool"],[55,'
    '"="],[1,"False"],[55,","],[55,")"],[1,"raises"],[55,"->"'
    '],[1,"List"],[55,"["],[1,"Landmark"],[55,"]"],[55,":"]]],['
    '[["struct","Map"]],[[1,"def"],[1,"landmarks_of_type_in_distan'
    'ce"],[55,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"]'
    ',[1,"Waypoint"],[55,","],[1,"distance"],[55,":"],[1,"Length'
    '64"],[55,","],[1,"type"],[55,":"],[1,"String"],[55,","],['
    '1,"stop_at_junction"],[55,":"],[1,"Bool"],[55,"="],[1,"Fals'
    'e"],[55,","],[55,")"],[1,"raises"],[55,"->"],[1,"List"],['
    '55,"["],[1,"Landmark"],[55,"]"],[55,":"]]],[[["struct","M'
    'ap"]],[[1,"def"],[1,"landmarks_of_type_in_distance_meters"],[55'
    ',"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"Way'
    'point"],[55,","],[1,"distance"],[55,":"],[1,"Float64"],[55,'
    '","],[1,"type"],[55,":"],[1,"String"],[55,","],[1,"stop_a'
    't_junction"],[55,":"],[1,"Bool"],[55,"="],[1,"False"],[55,'
    '","],[55,")"],[1,"raises"],[55,"->"],[1,"List"],[55,"["]'
    ',[1,"Landmark"],[55,"]"],[55,":"]]]'
)

comptime _RIGHT_22 = (
    ',[[["struct","Map"]],[[1,"def"],[1,"landmarks_in_distance"],'
    '[55,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,"'
    'Waypoint"],[55,","],[1,"distance"],[55,":"],[1,"Float64"],['
    '55,","],[1,"stop_at_junction"],[55,":"],[1,"Bool"],[55,"="'
    '],[1,"False"],[55,","],[55,")"],[1,"raises"],[55,"->"],[1,'
    '"List"],[55,"["],[1,"Landmark"],[55,"]"],[55,":"]]],[[["s'
    'truct","Map"]],[[1,"def"],[1,"landmarks_of_type_in_distance"]'
    ',[55,"("],[1,"self"],[55,","],[1,"waypoint"],[55,":"],[1,'
    '"Waypoint"],[55,","],[1,"distance"],[55,":"],[1,"Float64"]'
    ',[55,","],[1,"type"],[55,":"],[1,"String"],[55,","],[1,"s'
    'top_at_junction"],[55,":"],[1,"Bool"],[55,"="],[1,"False"],'
    '[55,","],[55,")"],[1,"raises"],[55,"->"],[1,"List"],[55,"'
    '["],[1,"Landmark"],[55,"]"],[55,":"]]]'
)


def _fail(message: String) raises:
    """Raise a Map routing error.

    Args:
        message: The failure text.

    Raises:
        Error: The live Map routing changed.
    """
    raise Error(message)


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


def _left(index: Int) -> String:
    """Return one live routing span.

    Args:
        index: The span number.

    Returns:
        The live routing text.
    """
    if index == 0:
        return _LEFT_0
    if index == 1:
        return _LEFT_1
    if index == 2:
        return _LEFT_2
    if index == 3:
        return _LEFT_3
    if index == 4:
        return _LEFT_4
    if index == 5:
        return _LEFT_5
    if index == 6:
        return _LEFT_6
    if index == 7:
        return _LEFT_7
    if index == 8:
        return _LEFT_8
    if index == 9:
        return _LEFT_9
    if index == 10:
        return _LEFT_10
    if index == 11:
        return _LEFT_11
    if index == 12:
        return _LEFT_12
    if index == 13:
        return _LEFT_13
    if index == 14:
        return _LEFT_14
    if index == 15:
        return _LEFT_15
    if index == 16:
        return _LEFT_16
    if index == 17:
        return _LEFT_17
    if index == 18:
        return _LEFT_18
    if index == 19:
        return _LEFT_19
    if index == 20:
        return _LEFT_20
    if index == 21:
        return _LEFT_21
    return _LEFT_22


def _right(index: Int) -> String:
    """Return one pinned routing span.

    Args:
        index: The span number.

    Returns:
        The pinned routing text.
    """
    if index == 0:
        return _RIGHT_0
    if index == 1:
        return _RIGHT_1
    if index == 2:
        return _RIGHT_2
    if index == 3:
        return _RIGHT_3
    if index == 4:
        return _RIGHT_4
    if index == 5:
        return _RIGHT_5
    if index == 6:
        return _RIGHT_6
    if index == 7:
        return _RIGHT_7
    if index == 8:
        return _RIGHT_8
    if index == 9:
        return _RIGHT_9
    if index == 10:
        return _RIGHT_10
    if index == 11:
        return _RIGHT_11
    if index == 12:
        return _RIGHT_12
    if index == 13:
        return _RIGHT_13
    if index == 14:
        return _RIGHT_14
    if index == 15:
        return _RIGHT_15
    if index == 16:
        return _RIGHT_16
    if index == 17:
        return _RIGHT_17
    if index == 18:
        return _RIGHT_18
    if index == 19:
        return _RIGHT_19
    if index == 20:
        return _RIGHT_20
    if index == 21:
        return _RIGHT_21
    return _RIGHT_22


def sum2_map_routing(root: String) raises:
    """Require the live Map routing.

    Args:
        root: The repository root.

    Raises:
        Error: A reviewed span or the pinned routing changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var callers = doc.at(doc.root, "callers")
    var record = doc.at(callers, "map")
    var routing = doc.at(record, "routing")
    if doc.kind(routing) != PY_STR:
        _fail(_MESSAGE)
    var current = _routing(Path(base + "/" + _MAP).read_text())
    var index = 0
    while index < 23:
        var left = _left(index)
        if _count(current, left) != 1:
            _fail(_MESSAGE)
        current = current.replace(left, _right(index))
        index += 1
    if current != doc.text(routing):
        _fail(_MESSAGE)
