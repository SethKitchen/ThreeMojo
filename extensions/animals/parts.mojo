# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The surface parts an animal is meshed in.

`BODY` is the skin. `JAW` is the lower jaw, a surface of its own so the
mouth can open. `HORN` holds horns and antlers. `TEETH` holds tusks,
fangs and teeth. `TONGUE` is the tongue. `APPENDAGE` holds an udder, a
beard or a rattle. `HOOF` holds hooves. `EYEBALL` holds the eyes. `EAR`
holds ears meshed apart. `LIMB` holds legs meshed apart, as a spider's.
`TAIL` holds a tail meshed apart. `WATTLE` holds a comb, wattles and
earlobes.
"""

from extensions.sdf.ids import SurfacePart

comptime BODY = SurfacePart(0)
comptime JAW = SurfacePart(1)
comptime HORN = SurfacePart(2)
comptime TEETH = SurfacePart(3)
comptime TONGUE = SurfacePart(4)
comptime APPENDAGE = SurfacePart(5)
comptime HOOF = SurfacePart(6)
comptime EYEBALL = SurfacePart(7)
comptime EAR = SurfacePart(8)
comptime LIMB = SurfacePart(9)
comptime TAIL = SurfacePart(10)
comptime WATTLE = SurfacePart(11)
