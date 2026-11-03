# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The plan of Wijnendale Castle (Kasteel van Wijnendale, Chateau de
Wynendaele), at Torhout in West Flanders, Belgium.

**What is documented.** The Flemish heritage inventory (record 87491) and
the history of the castle give these facts.

- Robert I of Flanders is thought to have built a wooden castle here between
  1085 and 1095. Count Guy of Dampierre had a stone castle built about
  1276-1278, a round moated castle with eleven half-round towers and a heavy
  gate tower.
- The Cleves family repaired it in the middle of the 15th century. Part of
  the north wing may date from then. It decayed from the 16th century on, and
  French troops blew up part of it in 1690 and damaged it in 1811.
- Josse-Pierre Matthieu bought the domain in 1833 and rebuilt the gate and
  the right wing in 1834-1852. The left wing was rebuilt in 1854-1865.
- In 1877-1878 Joseph-Louis Jules Matthieu had the Brussels architect Felix
  Laureys build the pseudo-medieval gate tower with its crenellations, and
  extend the right wing with a round donjon, which gave the castle its
  Gothic look.
- The castle is a protected monument since 1982. The domain lies at the edge
  of the Wijnendalebos, a forest of about 280 hectares.

**Where the plan comes from.** The inventory gives no dimensions. This plan is
built from open geodata, and the photograph shows only what the data cannot:
the roofs and their style.

- The outline of the building, 99 corners, and the outline of the moat are
  from the Flemish large scale reference map, GRB (feature types GBG and WTZ,
  Belgian Lambert 72). The moat outline is simplified by 0.25 m.
- The heights are from the Digital Height Model of Flanders II, a 1 m raster
  of the surface (DSM) and the terrain (DTM) from an airborne laser scan. The
  water surface is the flat 34.31 m that the scan returns over the moat.
- The towers are circles fitted to the arcs of the surveyed outline. The
  wings and the gate are the bands and the rectangle that best cover it:
  they reproduce 96 percent of the surveyed area.
- What no survey gives is marked `ESTIMATED`: the depth of the moat, the
  thickness of the quay wall, the piers and the arch ring of the bridge,
  and the proportions of the roofs.

The data are open data of Digitaal Vlaanderen. See THIRD-PARTY-NOTICES.md.

Points are meters east and north of the origin, which is the Belgian Lambert
72 point (58200, 197300) m. Elevations are meters above TAW, the Belgian
datum.
"""

from extensions.castle.kinds import CONE, ESTIMATED, FLAT, MEASURED, SURVEYED
from extensions.castle.plan import (
    Bridge,
    CastlePlan,
    Gate,
    Moat,
    Point,
    QuayWall,
    Tower,
    Wing,
    point,
    points,
)
from units.si import Angle64, DEGREE64, Length64

# The latitude and longitude of the castle, WGS 84, in degrees.
comptime LATITUDE_DEGREES = 51.078925
comptime LONGITUDE_DEGREES = 3.059483
# The Belgian Lambert 72 coordinates of the origin of the plan, in meters.
comptime ORIGIN_EAST = 58200.0
comptime ORIGIN_NORTH = 197300.0

# The elevation of the water of the moat, from the laser scan (TAW).
comptime WATER_LEVEL = 34.31
# The elevation of the ground of the island and its courtyard (TAW).
comptime ISLAND_LEVEL = 37.9
# The elevation of the ground outside the moat, on average (TAW).
comptime GROUND_LEVEL = 36.6
# The depth of the water. No survey of the bed exists, so it is a guess.
comptime MOAT_DEPTH = 1.5
# The rise of a spire over the radius of its tower: a guess from the
# photograph.
comptime CONE_RISE_OVER_RADIUS = 2.4


def latitude() -> Angle64:
    """Return the latitude of the castle.

    Returns:
        51.078925 degrees north.
    """
    return Angle64(LATITUDE_DEGREES, DEGREE64)


def longitude() -> Angle64:
    """Return the longitude of the castle.

    Returns:
        3.059483 degrees east.
    """
    return Angle64(LONGITUDE_DEGREES, DEGREE64)


def surveyed_footprint() raises -> List[Point]:
    """Return the outline of the building from the survey.

    Returns:
        The 99 corners of the main building, counterclockwise, in meters
        east and north of the origin of the plan.

    Raises:
        Error: Never, for the table that is built in.
    """
    return points(
        [
            32.10,
            71.64,
            31.89,
            72.96,
            30.76,
            73.78,
            29.36,
            73.58,
            28.46,
            72.53,
            28.52,
            72.09,
            15.89,
            70.95,
            15.48,
            71.28,
            15.03,
            71.53,
            14.54,
            71.72,
            14.02,
            71.83,
            13.50,
            71.86,
            12.98,
            71.81,
            12.47,
            71.68,
            11.99,
            71.47,
            11.55,
            71.20,
            11.15,
            70.85,
            10.81,
            70.46,
            10.53,
            70.01,
            10.33,
            69.53,
            10.20,
            69.03,
            10.15,
            68.50,
            10.17,
            67.98,
            10.28,
            67.47,
            10.47,
            66.98,
            10.72,
            66.52,
            11.05,
            66.11,
            11.43,
            65.76,
            11.86,
            65.46,
            12.33,
            65.23,
            12.83,
            65.08,
            13.35,
            65.01,
            13.87,
            65.01,
            14.39,
            65.10,
            14.89,
            65.26,
            15.08,
            65.35,
            16.69,
            63.31,
            17.64,
            61.74,
            16.50,
            60.42,
            16.81,
            58.66,
            18.14,
            57.63,
            19.90,
            57.81,
            20.46,
            58.59,
            28.01,
            59.55,
            35.19,
            56.05,
            41.54,
            47.24,
            36.43,
            33.49,
            31.46,
            29.76,
            29.82,
            29.75,
            28.42,
            30.66,
            26.76,
            30.40,
            25.68,
            29.05,
            25.92,
            27.80,
            25.02,
            25.88,
            25.87,
            19.45,
            24.74,
            18.17,
            24.91,
            16.21,
            26.41,
            15.00,
            28.32,
            15.27,
            29.59,
            16.63,
            29.44,
            18.19,
            33.83,
            18.59,
            33.80,
            17.99,
            34.89,
            16.85,
            36.37,
            16.73,
            37.47,
            17.81,
            37.56,
            19.29,
            37.19,
            19.66,
            45.71,
            25.89,
            47.17,
            24.75,
            48.56,
            25.38,
            49.22,
            26.70,
            48.80,
            28.18,
            48.13,
            28.45,
            49.68,
            32.21,
            52.94,
            30.53,
            54.11,
            29.96,
            55.47,
            30.55,
            56.11,
            31.67,
            57.39,
            34.11,
            59.76,
            38.59,
            61.82,
            42.51,
            62.50,
            43.77,
            62.06,
            45.15,
            60.80,
            45.82,
            57.03,
            47.85,
            55.71,
            48.52,
            54.37,
            48.18,
            54.01,
            47.50,
            53.50,
            47.54,
            52.68,
            53.58,
            52.69,
            55.11,
            51.62,
            55.91,
            50.68,
            55.84,
            44.51,
            64.76,
            44.88,
            66.28,
            44.02,
            67.52,
            42.81,
            67.69,
            41.96,
            67.16,
        ]
    )


def moat_outline() raises -> List[Point]:
    """Return the outline of the water of the moat from the survey.

    Returns:
        The corners of the water, counterclockwise, simplified by 0.25 m.
        The bridge, the island's quay and the castle's own walls cut the
        water, so the outline is one polygon with the island out of it.

    Raises:
        Error: Never, for the table that is built in.
    """
    return points(
        [
            74.97,
            74.86,
            70.44,
            79.79,
            66.87,
            82.97,
            60.11,
            88.15,
            55.30,
            91.29,
            47.28,
            95.10,
            35.52,
            98.69,
            27.22,
            99.75,
            18.80,
            98.75,
            8.92,
            95.91,
            -0.01,
            91.29,
            -9.91,
            84.35,
            -13.46,
            81.29,
            -16.36,
            78.08,
            -20.34,
            72.33,
            -23.35,
            66.99,
            -26.04,
            60.74,
            -27.48,
            56.21,
            -28.43,
            51.60,
            -28.82,
            46.98,
            -28.63,
            41.08,
            -27.89,
            34.93,
            -25.34,
            25.72,
            -20.33,
            14.95,
            -17.10,
            10.63,
            -13.10,
            6.21,
            -8.05,
            1.85,
            -2.78,
            -1.85,
            1.20,
            -4.06,
            8.95,
            -7.48,
            21.55,
            -11.13,
            24.70,
            -11.65,
            29.26,
            -11.69,
            35.05,
            -11.36,
            39.01,
            -10.70,
            49.77,
            -7.10,
            59.33,
            -1.80,
            66.07,
            3.02,
            79.04,
            13.66,
            83.50,
            18.69,
            83.04,
            20.77,
            81.33,
            21.77,
            80.58,
            20.94,
            79.36,
            20.98,
            78.64,
            21.97,
            79.06,
            23.22,
            75.05,
            25.31,
            74.23,
            24.26,
            73.00,
            24.30,
            72.27,
            25.29,
            72.59,
            26.47,
            68.61,
            28.69,
            67.81,
            27.83,
            66.73,
            27.93,
            66.10,
            28.81,
            66.37,
            29.86,
            62.37,
            31.97,
            61.61,
            30.99,
            60.36,
            30.97,
            59.60,
            31.82,
            59.69,
            32.95,
            57.39,
            34.11,
            55.47,
            30.55,
            54.11,
            29.96,
            49.68,
            32.21,
            48.13,
            28.45,
            48.80,
            28.18,
            49.22,
            26.70,
            48.56,
            25.38,
            47.17,
            24.75,
            45.71,
            25.89,
            37.19,
            19.66,
            37.56,
            19.29,
            37.47,
            17.81,
            36.37,
            16.73,
            34.89,
            16.85,
            33.80,
            17.99,
            33.83,
            18.59,
            29.44,
            18.19,
            29.59,
            16.63,
            28.32,
            15.27,
            26.41,
            15.00,
            24.91,
            16.21,
            24.74,
            18.17,
            21.53,
            17.95,
            9.94,
            23.46,
            8.74,
            22.26,
            7.22,
            22.77,
            6.87,
            24.13,
            7.71,
            25.21,
            1.31,
            33.85,
            -0.19,
            33.44,
            -1.37,
            34.45,
            -1.13,
            36.08,
            0.31,
            36.71,
            -0.81,
            47.22,
            -2.31,
            47.57,
            -2.83,
            49.12,
            -1.86,
            50.31,
            -0.28,
            50.14,
            3.66,
            60.44,
            2.71,
            61.45,
            2.90,
            62.73,
            4.11,
            63.42,
            5.41,
            62.81,
            10.72,
            66.52,
            10.20,
            69.03,
            11.55,
            71.20,
            13.50,
            71.86,
            15.89,
            70.95,
            28.52,
            72.09,
            28.46,
            72.53,
            29.36,
            73.58,
            30.76,
            73.78,
            31.89,
            72.96,
            32.10,
            71.64,
            41.96,
            67.16,
            42.81,
            67.69,
            44.02,
            67.52,
            44.88,
            66.28,
            44.51,
            64.76,
            50.68,
            55.84,
            51.62,
            55.91,
            52.69,
            55.11,
            53.50,
            47.54,
            55.71,
            48.52,
            62.06,
            45.15,
            62.50,
            43.77,
            59.76,
            38.59,
            62.14,
            37.35,
            63.11,
            39.13,
            64.58,
            39.35,
            65.36,
            38.42,
            65.08,
            37.23,
            69.03,
            35.10,
            69.75,
            36.08,
            70.95,
            36.10,
            71.72,
            35.05,
            71.32,
            33.90,
            75.38,
            31.74,
            76.11,
            32.70,
            77.32,
            32.71,
            78.07,
            31.65,
            77.67,
            30.51,
            81.80,
            28.31,
            82.49,
            29.17,
            83.68,
            29.18,
            84.41,
            28.23,
            84.09,
            27.08,
            85.75,
            26.23,
            87.09,
            26.30,
            88.49,
            27.71,
            90.79,
            35.78,
            91.30,
            41.96,
            90.62,
            47.16,
            88.61,
            53.23,
            85.73,
            59.19,
            80.13,
            68.15,
        ]
    )


def _cone_tower(
    name: String, east: Float64, north: Float64, radius: Float64, top: Float64
) -> Tower:
    """Return a tower with a spire, from the elevation of its tip."""
    var rise = CONE_RISE_OVER_RADIUS * radius
    return Tower(
        name,
        point(east, north),
        Length64(radius),
        Length64(WATER_LEVEL),
        Length64(top - rise - WATER_LEVEL),
        CONE,
        Length64(rise),
        MEASURED,
    )


def _flat_tower(
    name: String,
    east: Float64,
    north: Float64,
    radius: Float64,
    top: Float64,
    parapet: Float64,
) -> Tower:
    """Return a tower with a flat top, from the elevation of its parapet."""
    return Tower(
        name,
        point(east, north),
        Length64(radius),
        Length64(WATER_LEVEL),
        Length64(top - parapet - WATER_LEVEL),
        FLAT,
        Length64(parapet),
        MEASURED,
    )


def wijnendale_plan() raises -> CastlePlan:
    """Return the plan of Wijnendale Castle.

    Returns:
        The plan: the donjon and seven turrets, the north and the south
        wing, the gate tower, the low wall of the courtyard with its four
        towers, the moat and the bridge. It is consistent: `check` passes.

    Raises:
        Error: Never, for the tables that are built in.
    """
    var towers = List[Tower]()
    towers.append(_flat_tower("Donjon", 13.57, 68.43, 3.43, 63.59, 1.2))
    towers.append(_cone_tower("North turret", 30.30, 72.02, 1.84, 52.80))
    towers.append(_cone_tower("Courtyard turret", 18.67, 59.77, 2.22, 55.53))
    towers.append(_cone_tower("Inner south turret", 27.92, 28.56, 2.20, 55.34))
    towers.append(
        _flat_tower("South-west tower", 27.13, 17.36, 2.48, 55.21, 1.0)
    )
    towers.append(_cone_tower("South turret", 35.71, 18.55, 1.92, 51.01))
    towers.append(_cone_tower("South-east turret", 47.36, 26.76, 1.91, 53.35))
    towers.append(_cone_tower("North-east turret", 43.20, 65.95, 1.76, 52.31))
    towers.append(_flat_tower("Quay tower 1", 8.3, 23.8, 1.45, 39.2, 0.0))
    towers.append(_flat_tower("Quay tower 2", -0.1, 35.0, 1.45, 39.2, 0.0))
    towers.append(_flat_tower("Quay tower 3", -1.2, 48.9, 1.45, 39.2, 0.0))
    towers.append(_flat_tower("Quay tower 4", 3.9, 61.9, 1.45, 39.2, 0.0))

    var wings = List[Wing]()
    wings.append(
        Wing(
            "North wing",
            points([16.4, 64.7, 29.6, 65.9, 39.1, 61.6, 53.4, 40.8]),
            Length64(12.6),
            Length64(WATER_LEVEL),
            Length64(45.9 - WATER_LEVEL),
            Length64(51.4 - WATER_LEVEL),
            MEASURED,
        )
    )
    wings.append(
        Wing(
            "South wing",
            points([46.8, 45.5, 40.4, 28.3, 26.2, 21.5]),
            Length64(11.1),
            Length64(WATER_LEVEL),
            Length64(46.4 - WATER_LEVEL),
            Length64(50.4 - WATER_LEVEL),
            MEASURED,
        )
    )

    var gate = Gate(
        "Gate tower",
        point(52.7, 40.4),
        Length64(17.2),
        Length64(14.1),
        Angle64(62.2, DEGREE64),
        Length64(WATER_LEVEL),
        Length64(51.5 - WATER_LEVEL),
        Length64(1.0),
        MEASURED,
    )

    var quay = QuayWall(
        "Courtyard wall",
        points(
            [
                24.74,
                18.17,
                21.53,
                17.95,
                9.94,
                23.46,
                1.31,
                33.85,
                -0.81,
                47.22,
                3.66,
                60.44,
                10.72,
                66.52,
            ]
        ),
        Length64(0.9),
        Length64(WATER_LEVEL - MOAT_DEPTH),
        Length64(38.6),
        ESTIMATED,
    )

    var moat = Moat(
        "Moat",
        moat_outline(),
        Length64(WATER_LEVEL),
        Length64(MOAT_DEPTH),
        SURVEYED,
    )

    var bridge = Bridge(
        "Bridge",
        point(62.47, 35.16),
        Angle64(-27.9, DEGREE64),
        3,
        Length64(7.19),
        Length64(9.3),
        Length64(2.0),
        Length64(37.5),
        Length64(0.6),
        ESTIMATED,
    )

    return CastlePlan(
        String("Wijnendale Castle"),
        Length64(ISLAND_LEVEL),
        Length64(GROUND_LEVEL),
        surveyed_footprint(),
        towers^,
        wings^,
        gate^,
        quay^,
        moat^,
        bridge^,
    )
