# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The parts of a meadow: kinds, checks, noise, wind, blades, ground and
boulders."""

from core.buffer_geometry import COLOR, NORMAL, POSITION
from extensions.vegetation.blade import (
    MAX_SEGMENTS,
    Blade,
    BladeMesh,
    blade_colors,
    blade_triangles,
)
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.ground import (
    RIM,
    Canyon,
    Ground,
    cliff_wall,
    no_canyon,
    ridge_ring,
)
from extensions.vegetation.kinds import (
    BEYOND,
    BROADLEAF,
    BUTTERCUP,
    CULLED,
    DRAWN,
    DRY_GRASS,
    GRASS,
    POPPY,
    SEED_HEAD,
    ClusterFate,
    PlantKind,
    require_cluster_fate,
    require_plant_kind,
)
from extensions.vegetation.noise import (
    hash01,
    layered_noise,
    value_noise,
    value_noise3,
)
from extensions.vegetation.rock import boulder
from extensions.vegetation.wind import Wind, still_air
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    METER,
    METER_PER_SECOND,
    PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Frequency,
    Length,
    Velocity,
)


def _blade(kind: PlantKind) -> Blade:
    """Return an upright blade at the origin, 40 centimeters tall."""
    return Blade(
        Vector3(0, 0, 0),
        Angle(0.0, RADIAN),
        Length(0.4, METER),
        Length(0.01, METER),
        Angle(0.0, DEGREE),
        0.5,
        0.5,
        kind,
    )


def test_range_checks_refuse_each_side_and_nan() raises:
    """A number below, above or NaN is refused; one inside passes."""
    require_between(0.5, 0, 1, "inside")
    require_between(0, 0, 1, "low edge")
    require_between(1, 0, 1, "high edge")
    with assert_raises(contains="below"):
        require_between(-0.1, 0, 1, "below")
    with assert_raises(contains="above"):
        require_between(1.1, 0, 1, "above")
    with assert_raises(contains="nan"):
        require_between(nan[DType.float32](), 0, 1, "nan")
    require_count_between(3, 1, 8, "inside")
    with assert_raises(contains="few"):
        require_count_between(0, 1, 8, "few")
    with assert_raises(contains="many"):
        require_count_between(9, 1, 8, "many")


def test_plant_kinds_are_named_and_checked() raises:
    """Each kind has a name; a value no name stands for is refused."""
    assert_equal(GRASS.name(), "grass")
    assert_equal(DRY_GRASS.name(), "dry grass")
    assert_equal(POPPY.name(), "poppy")
    assert_equal(SEED_HEAD.name(), "seed head")
    assert_equal(BROADLEAF.name(), "broad leaf")
    assert_equal(BUTTERCUP.name(), "buttercup")
    assert_equal(PlantKind(6).name(), "unknown")
    assert_true(GRASS.is_valid())
    assert_true(BROADLEAF.is_valid())
    assert_false(PlantKind(-1).is_valid())
    assert_true(BUTTERCUP.is_valid())
    assert_false(PlantKind(6).is_valid())
    require_plant_kind(POPPY)
    with assert_raises(contains="plant kind"):
        require_plant_kind(PlantKind(7))


def test_cluster_fates_are_named_and_checked() raises:
    """Each fate has a name; a value no name stands for is refused."""
    assert_equal(DRAWN.name(), "drawn")
    assert_equal(CULLED.name(), "culled")
    assert_equal(BEYOND.name(), "beyond")
    assert_equal(ClusterFate(-1).name(), "unknown")
    assert_false(ClusterFate(3).is_valid())
    require_cluster_fate(BEYOND)
    with assert_raises(contains="cluster fate"):
        require_cluster_fate(ClusterFate(5))


def test_hash_is_stable_and_in_range() raises:
    """The same arguments give the same number, from zero to one."""
    assert_equal(hash01(3, 4, 5), hash01(3, 4, 5))
    assert_true(hash01(3, 4, 5) != hash01(4, 3, 5))
    assert_true(hash01(3, 4, 5) != hash01(3, 4, 6))
    for i in range(200):
        var h = hash01(i - 100, i * 7, 11)
        assert_true(h >= 0 and h <= 1)


def test_value_noise_meets_the_lattice_and_is_smooth() raises:
    """At a lattice corner the noise is the corner's hash. Between, it is
    continuous: a small step moves it a little."""
    assert_almost_equal(value_noise(2, 5, 1), hash01(2, 5, 1), atol=1e-6)
    assert_almost_equal(value_noise(-3, 0, 1), hash01(-3, 0, 1), atol=1e-6)
    var a = value_noise(2.5, 5.5, 1)
    var b = value_noise(2.501, 5.5, 1)
    assert_true(abs(a - b) < 0.01)
    var layered = layered_noise(0.3, 0.7, 4)
    assert_true(layered >= 0 and layered <= 1)


def test_value_noise_in_space_blends_its_layers() raises:
    """On a whole layer the noise in space is that layer's plane noise.
    Between layers it is smooth, and stays from zero to one."""
    assert_almost_equal(
        value_noise3(2.5, 3, 1.5, 6), value_noise(2.5, 1.5, 6 + 3 * 977)
    )
    assert_almost_equal(
        value_noise3(2.5, -2, 1.5, 6), value_noise(2.5, 1.5, 6 - 2 * 977)
    )
    var a = value_noise3(0.4, 0.5, 0.6, 2)
    var b = value_noise3(0.4, 0.501, 0.6, 2)
    assert_true(abs(a - b) < 0.01)
    assert_true(a >= 0 and a <= 1)


def test_wind_refuses_each_out_of_range_value() raises:
    """Each field outside its range is refused."""
    with assert_raises(contains="heading"):
        _ = Wind(heading=Angle(nan[DType.float32](), RADIAN))
    with assert_raises(contains="lean"):
        _ = Wind(lean=Angle(81.0, DEGREE))
    with assert_raises(contains="calm"):
        _ = Wind(calm=1.5)
    with assert_raises(contains="gust"):
        _ = Wind(gust_length=Length(0.0, METER))
    with assert_raises(contains="travel"):
        _ = Wind(gust_speed=Velocity(-1.0, METER_PER_SECOND))
    with assert_raises(contains="flutter must be from 0 to 30"):
        _ = Wind(flutter=Angle(31.0, DEGREE))
    with assert_raises(contains="wobbles"):
        _ = Wind(flutter_rate=Frequency(21.0, PER_SECOND))
    with assert_raises(contains="loop"):
        _ = Wind(loop=Duration(-1.0, SECOND))
    with assert_raises(contains="sway must be"):
        _ = Wind(sway=Angle(50.0, DEGREE))
    with assert_raises(contains="swings"):
        _ = Wind(sway_rate=Frequency(-1.0, PER_SECOND))
    with assert_raises(contains="crests"):
        _ = Wind(sway_length=Length(0.0, METER))


def test_gusts_travel_downwind_at_their_speed() raises:
    """The gust at a point at time zero is the gust a distance
    `speed * time` downwind at that time."""
    var wind = Wind(heading=Angle(30.0, DEGREE))
    var down = wind.downwind()
    assert_almost_equal(down.length(), 1, atol=1e-6)
    var t = Float32(2)
    var shift = wind.gust_speed.to(METER_PER_SECOND) * t
    for i in range(10):
        var x = Float32(i) * 1.7 - 5
        var z = Float32(i) * -0.9 + 3
        var before = wind.gust(x, z, Duration(0.0, SECOND))
        var after = wind.gust(
            x + down.x * shift, z + down.y * shift, Duration(t, SECOND)
        )
        assert_almost_equal(before, after, atol=1e-4)
        assert_true(before >= 0 and before <= 1)


def test_a_looping_wind_repeats_itself_with_no_jump() raises:
    """A wind with a loop has the same gusts and the same bend a loop
    later, and just before the loop ends it is close to its start. Its
    gusts keep their range in the middle of the loop."""
    var wind = Wind(loop=Duration(2.0, SECOND))
    var lowest = Float32(1)
    var highest = Float32(0)
    for i in range(40):
        var x = Float32(i) * 1.3 - 20
        var z = Float32(i) * -0.7 + 5
        var start = wind.gust(x, z, Duration(0.0, SECOND))
        var again = wind.gust(x, z, Duration(2.0, SECOND))
        var late = wind.gust(x, z, Duration(5.25, SECOND))
        var early = wind.gust(x, z, Duration(1.25, SECOND))
        var end = wind.gust(x, z, Duration(1.999, SECOND))
        assert_almost_equal(start, again, atol=1e-5)
        assert_almost_equal(late, early, atol=1e-4)
        assert_almost_equal(start, end, atol=0.02)
        var middle = wind.gust(x, z, Duration(1.0, SECOND))
        lowest = min(lowest, middle)
        highest = max(highest, middle)
        var bend = wind.tip_bend(x, z, start, 0.3, Duration(0.5, SECOND))
        var later = wind.tip_bend(x, z, start, 0.3, Duration(4.5, SECOND))
        assert_almost_equal(bend.x, later.x, atol=1e-4)
        assert_almost_equal(bend.y, later.y, atol=1e-4)
    assert_true(highest - lowest > 0.5)


def test_a_looping_flutter_wobbles_a_whole_number_of_times() raises:
    """A flutter of 1.6 wobbles a second in a 2 second loop wobbles three
    times a loop. A slower one still wobbles once."""
    var wind = Wind(
        lean=Angle(0.0, DEGREE),
        flutter_rate=Frequency(1.6, PER_SECOND),
        loop=Duration(2.0, SECOND),
        sway=Angle(0.0, DEGREE),
    )
    var slow = Wind(
        lean=Angle(0.0, DEGREE),
        flutter_rate=Frequency(0.1, PER_SECOND),
        loop=Duration(2.0, SECOND),
    )
    var a = slow.tip_bend(1, 2, 0, 0.2, Duration(0.3, SECOND))
    var b = slow.tip_bend(1, 2, 0, 0.2, Duration(2.3, SECOND))
    assert_almost_equal(a.x, b.x, atol=1e-5)
    var along = wind.downwind()
    var peak = wind.tip_bend(0, 0, 0, 0, Duration(0.5 / 3.0, SECOND))
    var wobble = wind.flutter.to(RADIAN)
    assert_almost_equal(peak.x * along.x + peak.y * along.y, wobble, atol=1e-4)


def test_the_sway_rolls_downwind_and_grows_in_a_gust() raises:
    """The sway at a point is the sway a quarter crest downwind a quarter
    swing later. A full gust swings a tip further than calm air does."""
    var wind = Wind(
        heading=Angle(0.0, DEGREE),
        lean=Angle(0.0, DEGREE),
        flutter=Angle(0.0, DEGREE),
        sway_rate=Frequency(1.0, PER_SECOND),
        sway_length=Length(4.0, METER),
    )
    for k in range(6):
        var t = Float32(k) * 0.13
        var here = wind.tip_bend(0, 0, 0.5, 0, Duration(t, SECOND))
        var later = wind.tip_bend(1, 0, 0.5, 0, Duration(t + 0.25, SECOND))
        assert_almost_equal(here.x, later.x, atol=1e-4)
    var widest_calm = Float32(0)
    var widest_gust = Float32(0)
    for k in range(20):
        var time = Duration(Float32(k) * 0.05, SECOND)
        widest_calm = max(widest_calm, abs(wind.tip_bend(0, 0, 0, 0, time).x))
        widest_gust = max(widest_gust, abs(wind.tip_bend(0, 0, 1, 0, time).x))
    assert_true(widest_gust > 3 * widest_calm)


def test_a_tree_sways_a_little_and_slowly() raises:
    """A tree leans downwind by a small share of the grass's lean, more in
    a gust, and rocks once a loop in a 2 second loop. Still air sways
    nothing."""
    var wind = Wind(heading=Angle(0.0, DEGREE), loop=Duration(2.0, SECOND))
    var most = Float32(0)
    var least = Float32(1)
    for k in range(40):
        var lean = wind.tree_sway(
            Float32(k) * 3.1, Float32(k) * -1.7, 0.3, Duration(0.4, SECOND)
        )
        assert_almost_equal(lean.y, 0, atol=1e-7)
        most = max(most, lean.x)
        least = min(least, lean.x)
    assert_true(most < wind.lean.to(RADIAN) * (0.025 + 0.008) + 1e-6)
    assert_true(most > least)
    var a = wind.tree_sway(2, 3, 0.6, Duration(0.25, SECOND))
    var b = wind.tree_sway(2, 3, 0.6, Duration(2.25, SECOND))
    assert_almost_equal(a.x, b.x, atol=1e-6)
    assert_almost_equal(
        still_air().tree_sway(2, 3, 0.6, Duration(0.7, SECOND)).length(), 0
    )


def test_tip_bend_leans_downwind_and_still_air_leans_nothing() raises:
    """A full gust with no sway and no flutter leans the tip by `lean`,
    downwind. Still air bends nothing."""
    var wind = Wind(
        heading=Angle(90.0, DEGREE),
        lean=Angle(20.0, DEGREE),
        calm=0.0,
        flutter=Angle(0.0, DEGREE),
        sway=Angle(0.0, DEGREE),
    )
    var bend = wind.tip_bend(3, 4, 1.0, 0.25, Duration(1.0, SECOND))
    assert_almost_equal(bend.x, 0, atol=1e-6)
    assert_almost_equal(bend.y, Angle(20.0, DEGREE).to(RADIAN), atol=1e-6)
    var calm = still_air().tip_bend(3, 4, 1.0, 0.7, Duration(3.0, SECOND))
    assert_almost_equal(calm.length(), 0, atol=1e-7)


def test_blade_colors_differ_by_kind() raises:
    """Green, dry and poppy blades have their own colors; an unknown kind
    is refused."""
    var green = blade_colors(GRASS, 0.5)
    var dry = blade_colors(DRY_GRASS, 0.5)
    var stem = blade_colors(POPPY, 0.5)
    var stalk = blade_colors(SEED_HEAD, 0.5)
    var leaf = blade_colors(BROADLEAF, 0.5)
    assert_true(leaf.tip.y < green.tip.y)
    assert_true(leaf.tip.y > leaf.root.y)
    assert_true(stalk.tip.x > stem.tip.x)
    assert_true(green.tip.y > green.tip.x)
    assert_true(dry.tip.x > green.tip.x)
    assert_true(stem.tip.y > stem.root.y)
    assert_true(green.tip.y > green.root.y)
    with assert_raises(contains="plant kind"):
        _ = blade_colors(PlantKind(9), 0)


def test_blade_check_refuses_each_bad_field() raises:
    """A blade that cannot be built is refused, field by field."""
    _blade(GRASS).check()
    var b = _blade(GRASS)
    b.root = Vector3(2.0e6, 0, 0)
    with assert_raises(contains="root"):
        b.check()
    b = _blade(GRASS)
    b.root = Vector3(0, 2.0e6, 0)
    with assert_raises(contains="root"):
        b.check()
    b = _blade(GRASS)
    b.root = Vector3(0, 0, 2.0e6)
    with assert_raises(contains="root"):
        b.check()
    b = _blade(GRASS)
    b.facing = Angle(nan[DType.float32](), RADIAN)
    with assert_raises(contains="face"):
        b.check()
    b = _blade(GRASS)
    b.height = Length(6.0, METER)
    with assert_raises(contains="long"):
        b.check()
    b = _blade(GRASS)
    b.width = Length(0.5, METER)
    with assert_raises(contains="wide"):
        b.check()
    b = _blade(GRASS)
    b.curl = Angle(130.0, DEGREE)
    with assert_raises(contains="curl"):
        b.check()
    b = _blade(GRASS)
    b.phase = 2
    with assert_raises(contains="phase"):
        b.check()
    b = _blade(GRASS)
    b.shade = -1
    with assert_raises(contains="shade"):
        b.check()
    b = _blade(GRASS)
    b.kind = PlantKind(6)
    with assert_raises(contains="plant kind"):
        b.check()


def test_a_blade_has_the_counts_its_segments_give() raises:
    """A blade of `n` segments has `2n + 1` vertices and `2n - 1`
    triangles, with every normal of unit length."""
    for segments in range(1, MAX_SEGMENTS + 1):
        var mesh = BladeMesh()
        mesh.reserve(1, segments)
        mesh.add(_blade(GRASS), segments, Vector2(0, 0), 1.0)
        assert_equal(mesh.vertex_count(), 2 * segments + 1)
        assert_equal(mesh.triangle_count(), blade_triangles(segments))
        for v in range(mesh.vertex_count()):
            var n = Vector3(
                mesh.normals[3 * v],
                mesh.normals[3 * v + 1],
                mesh.normals[3 * v + 2],
            )
            assert_almost_equal(n.length(), 1, atol=1e-5)


def test_an_upright_blade_reaches_its_height_and_tapers() raises:
    """With no curl and no wind the tip is straight above the root, and
    the width shrinks toward the tip."""
    var mesh = BladeMesh()
    mesh.add(_blade(GRASS), 4, Vector2(0, 0), 1.0)
    var tip = mesh.vertex_count() - 1
    assert_almost_equal(mesh.positions[3 * tip], 0, atol=1e-6)
    assert_almost_equal(mesh.positions[3 * tip + 1], 0.4, atol=1e-5)
    var root_width = mesh.positions[3] - mesh.positions[0]
    var high_width = mesh.positions[3 * 7] - mesh.positions[3 * 6]
    assert_almost_equal(root_width, 0.01, atol=1e-6)
    assert_true(high_width < root_width * 0.5)


def test_a_bent_blade_keeps_its_length() raises:
    """The wind turns each segment and does not stretch it, so the path
    from root to tip is as long as the blade."""
    var mesh = BladeMesh()
    var blade = _blade(GRASS)
    blade.curl = Angle(40.0, DEGREE)
    mesh.add(blade, 6, Vector2(0.5, 0.3), 1.0)
    var middles = List[Vector3]()
    for k in range(6):
        var a = 6 * k
        middles.append(
            Vector3(
                mesh.positions[a] + mesh.positions[a + 3],
                mesh.positions[a + 1] + mesh.positions[a + 4],
                mesh.positions[a + 2] + mesh.positions[a + 5],
            )
            * 0.5
        )
    middles.append(
        Vector3(mesh.positions[36], mesh.positions[37], mesh.positions[38])
    )
    var length = Float32(0)
    for k in range(6):
        length += (middles[k + 1] - middles[k]).length()
    assert_almost_equal(length, 0.4, atol=1e-4)
    var tip = mesh.vertex_count() - 1
    assert_true(mesh.positions[3 * tip] > 0.05)
    assert_true(mesh.positions[3 * tip + 1] < 0.39)


def test_a_flat_wind_cannot_fold_a_blade_into_the_ground() raises:
    """A bend far past a right angle still leaves every segment rising."""
    var mesh = BladeMesh()
    mesh.add(_blade(GRASS), 3, Vector2(9, 0), 1.0)
    for k in range(1, 3):
        assert_true(
            mesh.positions[3 * (2 * k) + 1]
            > mesh.positions[3 * (2 * k - 2) + 1]
        )


def test_widen_and_glint_change_width_and_tip() raises:
    """A widened blade is wider at the root; a glinting blade has a
    brighter tip and the same root."""
    var plain = BladeMesh()
    plain.add(_blade(GRASS), 2, Vector2(0, 0), 1.0)
    var wide = BladeMesh()
    wide.add(_blade(GRASS), 2, Vector2(0, 0), 3.0, 0.5)
    var plain_width = plain.positions[3] - plain.positions[0]
    var wide_width = wide.positions[3] - wide.positions[0]
    assert_almost_equal(wide_width, plain_width * 3, atol=1e-6)
    var tip = 3 * (plain.vertex_count() - 1)
    assert_almost_equal(
        wide.colors[tip + 1], plain.colors[tip + 1] * 1.5, atol=1e-6
    )
    assert_almost_equal(wide.colors[1], plain.colors[1], atol=1e-6)


def test_a_poppy_carries_a_red_cup() raises:
    """A poppy adds five petals, three vertices and one triangle each,
    red, around its tip."""
    var mesh = BladeMesh()
    mesh.add(_blade(POPPY), 3, Vector2(0, 0), 1.0)
    assert_equal(mesh.vertex_count(), 7 + 15)
    assert_equal(mesh.triangle_count(), 5 + 5)
    var rim = 3 * (mesh.vertex_count() - 1)
    assert_true(mesh.colors[rim] > 10 * mesh.colors[rim + 1])
    assert_true(mesh.positions[rim + 1] > 0.4)


def test_a_buttercup_carries_a_small_yellow_cup() raises:
    """A buttercup is a poppy's stem with a smaller cup of five yellow
    petals."""
    var mesh = BladeMesh()
    mesh.add(_blade(BUTTERCUP), 3, Vector2(0, 0), 1.0)
    assert_equal(mesh.vertex_count(), 7 + 15)
    var rim = 3 * (mesh.vertex_count() - 1)
    assert_true(mesh.colors[rim] > mesh.colors[rim + 1])
    assert_true(mesh.colors[rim + 1] > 20 * mesh.colors[rim + 2])
    var poppy = BladeMesh()
    poppy.add(_blade(POPPY), 3, Vector2(0, 0), 1.0)
    var tip = 3 * 6
    var cup = Float32(0)
    var poppy_cup = Float32(0)
    for v in range(7, 22):
        cup = max(cup, abs(mesh.positions[3 * v] - mesh.positions[tip]))
        poppy_cup = max(
            poppy_cup, abs(poppy.positions[3 * v] - poppy.positions[tip])
        )
    assert_true(cup < poppy_cup)
    var stem = blade_colors(BUTTERCUP, 0.5)
    assert_almost_equal(stem.tip.y, blade_colors(POPPY, 0.5).tip.y)


def test_a_seed_head_tops_its_stalk_with_a_spike() raises:
    """A seed head adds two crossed strips, four vertices and two
    triangles each, above the stalk's tip."""
    var mesh = BladeMesh()
    mesh.add(_blade(SEED_HEAD), 3, Vector2(0, 0), 1.0)
    assert_equal(mesh.vertex_count(), 7 + 8)
    assert_equal(mesh.triangle_count(), 5 + 4)
    var top = 3 * (mesh.vertex_count() - 1)
    assert_almost_equal(mesh.positions[top + 1], 0.4 + 0.075, atol=1e-4)


def test_a_broad_leaf_is_a_low_rosette() raises:
    """A broad-leaf plant is five oval leaves of eight vertices and six
    triangles each, low round its root, whatever its segments. The wind
    moves its tips less than a blade's."""
    var still = BladeMesh()
    still.add(_blade(BROADLEAF), 3, Vector2(0, 0), 1.0)
    assert_equal(still.vertex_count(), 5 * 8)
    assert_equal(still.triangle_count(), 5 * 6)
    var highest = Float32(0)
    for v in range(still.vertex_count()):
        highest = max(highest, still.positions[3 * v + 1])
    assert_true(highest < 0.4 * 0.7)
    var blown = BladeMesh()
    blown.add(_blade(BROADLEAF), 3, Vector2(1, 0), 1.0)
    var moved = blown.positions[3 * 7] - still.positions[3 * 7]
    var blade = BladeMesh()
    blade.add(_blade(GRASS), 3, Vector2(1, 0), 1.0)
    assert_true(moved > 0)
    assert_true(moved < blade.positions[3 * 6])


def test_the_wind_bends_a_blade_most_at_its_tip() raises:
    """Under the wind the root stays put and the tip moves the most."""
    var mesh = BladeMesh()
    mesh.add(_blade(GRASS), 4, Vector2(0.6, 0), 1.0)
    var low = mesh.positions[3 * 2] + mesh.positions[3 * 3]
    var high = mesh.positions[3 * 6] + mesh.positions[3 * 7]
    assert_almost_equal(mesh.positions[0] + mesh.positions[3], 0, atol=1e-6)
    assert_true(high > 4 * low)


def test_add_refuses_bad_segments_widen_and_glint() raises:
    """Segments, widening and glint outside their ranges are refused."""
    var mesh = BladeMesh()
    with assert_raises(contains="segments"):
        mesh.add(_blade(GRASS), 0, Vector2(0, 0), 1.0)
    with assert_raises(contains="segments"):
        mesh.add(_blade(GRASS), MAX_SEGMENTS + 1, Vector2(0, 0), 1.0)
    with assert_raises(contains="widened"):
        mesh.add(_blade(GRASS), 2, Vector2(0, 0), 0.5)
    with assert_raises(contains="glint"):
        mesh.add(_blade(GRASS), 2, Vector2(0, 0), 1.0, 2.5)
    with assert_raises(contains="plant kind"):
        mesh.add(_blade(PlantKind(8)), 2, Vector2(0, 0), 1.0)


def test_a_blade_mesh_bakes_one_geometry() raises:
    """`geometry` hands over positions, normals, colors and the index; an
    empty buffer is refused."""
    var mesh = BladeMesh()
    mesh.add(_blade(GRASS), 2, Vector2(0, 0), 1.0)
    mesh.add(_blade(DRY_GRASS), 2, Vector2(0, 0), 1.0)
    var geometry = mesh^.geometry()
    assert_equal(geometry.vertex_count(), 10)
    assert_equal(len(geometry.index), 18)
    assert_true(geometry.has_attribute(String(NORMAL)))
    assert_true(geometry.has_attribute(String(COLOR)))
    var empty = BladeMesh()
    with assert_raises(contains="no blades"):
        _ = empty^.geometry()


def test_ground_refuses_each_out_of_range_value() raises:
    """Each field outside its range is refused."""
    with assert_raises(contains="high"):
        _ = Ground(hill_height=Length(-1.0, METER))
    with assert_raises(contains="hill must be"):
        _ = Ground(hill_length=Length(0.5, METER))
    with assert_raises(contains="climb"):
        _ = Ground(climb=2)
    with assert_raises(contains="patch"):
        _ = Ground(patch_length=Length(0.01, METER))


def test_a_canyon_cuts_a_floor_and_raises_a_plateau() raises:
    """The near side is not cut, the floor is `depth` down, and the far
    plateau is `rise` up. A canyon out of range is refused, and no canyon
    cuts nothing."""
    var canyon = Canyon(
        Length(100.0, METER),
        Length(150.0, METER),
        Length(30.0, METER),
        Length(10.0, METER),
    )
    canyon.check()
    assert_almost_equal(canyon.cut(-50), 0)
    assert_almost_equal(canyon.cut(-125), -30)
    assert_almost_equal(canyon.cut(-200), 10)
    assert_almost_equal(canyon.cut(-100 - RIM * 0.5), -15, atol=1e-4)
    assert_almost_equal(no_canyon().cut(-1500), 0)
    var ground = Ground(hill_height=Length(0.0, METER), canyon=canyon)
    assert_almost_equal(ground.height_at(3, -125), -30)
    assert_almost_equal(ground.hills_at(3, -125), 0)
    with assert_raises(contains="near rim"):
        Canyon(
            Length(-1.0, METER),
            Length(150.0, METER),
            Length(30.0, METER),
            Length(10.0, METER),
        ).check()
    with assert_raises(contains="far rim"):
        Canyon(
            Length(100.0, METER),
            Length(105.0, METER),
            Length(30.0, METER),
            Length(10.0, METER),
        ).check()
    with assert_raises(contains="deep"):
        Canyon(
            Length(100.0, METER),
            Length(150.0, METER),
            Length(-30.0, METER),
            Length(10.0, METER),
        ).check()
    with assert_raises(contains="rise"):
        Canyon(
            Length(100.0, METER),
            Length(150.0, METER),
            Length(30.0, METER),
            Length(2000.0, METER),
        ).check()
    with assert_raises(contains="near rim"):
        _ = Ground(
            canyon=Canyon(
                Length(-5.0, METER),
                Length(150.0, METER),
                Length(30.0, METER),
                Length(10.0, METER),
            )
        )


def test_a_cliff_wall_faces_the_camera_from_floor_to_plateau() raises:
    """The wall has a vertex at each corner of its grid. It runs from the
    floor to just above the plateau, stands in front of the far rim, and
    is mossy at its top. A canyon with no wall, and a size out of range,
    are refused."""
    var ground = Ground(
        hill_height=Length(0.0, METER),
        canyon=Canyon(
            Length(100.0, METER),
            Length(150.0, METER),
            Length(30.0, METER),
            Length(10.0, METER),
        ),
    )
    var wall = cliff_wall(ground, Length(40.0, METER), 8, 4, 2)
    assert_equal(wall.vertex_count(), 9 * 5)
    assert_equal(len(wall.index), 8 * 4 * 6)
    ref p = wall.attribute_view(String(POSITION))
    ref c = wall.attribute_view(String(COLOR))
    assert_almost_equal(p.vector3(0).y, -30, atol=1e-4)
    assert_almost_equal(p.vector3(0).x, -20, atol=1e-4)
    assert_true(p.vector3(44).y > 10 and p.vector3(44).y < 12.2)
    for v in range(45):
        assert_true(p.vector3(v).z > -150 + RIM)
    assert_true(c.vector3(44).y > c.vector3(44).x)
    with assert_raises(contains="no wall"):
        _ = cliff_wall(Ground(), Length(40.0, METER), 8, 4, 2)
    with assert_raises(contains="wide"):
        _ = cliff_wall(ground, Length(0.5, METER), 8, 4, 2)
    with assert_raises(contains="columns"):
        _ = cliff_wall(ground, Length(40.0, METER), 1, 4, 2)
    with assert_raises(contains="rows"):
        _ = cliff_wall(ground, Length(40.0, METER), 8, 1, 2)


def test_ground_heights_climb_and_masks_stay_in_range() raises:
    """Level hills climb by `climb` toward -z. Each mask is from zero to
    one, the grass is short in some places and full height in others, and
    a normal is of unit length."""
    var flat = Ground(hill_height=Length(0.0, METER), climb=0.1)
    assert_almost_equal(flat.height_at(3, -10), 1.0, atol=1e-5)
    assert_almost_equal(flat.normal_at(0, 0).length(), 1, atol=1e-5)
    assert_almost_equal(flat.normal_at(0, 0).z, 0.0995037, atol=1e-4)
    var ground = Ground()
    var bare = False
    var thick = False
    var short = False
    var high = False
    for i in range(400):
        var x = Float32(i % 20) * 2.3 - 20
        var z = Float32(i // 20) * 2.9 - 25
        var cover = ground.cover(x, z)
        var dry = ground.dryness(x, z)
        var bloom = ground.bloom(x, z)
        var tall = ground.tallness(x, z)
        var weeds = ground.weeds(x, z)
        assert_true(cover >= 0 and cover <= 1)
        assert_true(dry >= 0 and dry <= 1)
        assert_true(bloom >= 0 and bloom <= 1)
        assert_true(tall >= 0 and tall <= 1)
        assert_true(weeds >= 0.35 and weeds <= 1)
        bare = bare or cover < 0.5
        thick = thick or cover == 1
        short = short or tall == 0
        high = high or tall == 1
        var far = ground.far_color(x, z)
        assert_true(far.x >= 0 and far.y >= 0 and far.z >= 0)
    assert_true(bare)
    assert_true(thick)
    assert_true(short)
    assert_true(high)


def test_ground_mesh_spaces_rows_closer_in_the_middle() raises:
    """A ground of four cells across has 25 vertices and 32 triangles.
    The rows near the middle are closer than those at the edge."""
    var ground = Ground()
    var mesh = ground.mesh(Length(40.0, METER), 4, 1, 2)
    assert_equal(mesh.vertex_count(), 25)
    assert_equal(len(mesh.index), 96)
    assert_true(mesh.has_attribute(String(COLOR)))
    ref p = mesh.attribute_view(String(POSITION))
    assert_almost_equal(p.vector3(0).x, -19, atol=1e-4)
    assert_almost_equal(p.vector3(2).x, 1, atol=1e-4)
    assert_almost_equal(p.vector3(3).x, 6, atol=1e-4)
    assert_almost_equal(p.vector3(4).x, 21, atol=1e-4)
    assert_almost_equal(p.vector3(12).z, 2, atol=1e-4)
    assert_almost_equal(
        p.vector3(7).y, ground.height_at(p.vector3(7).x, p.vector3(7).z)
    )
    with assert_raises(contains="across"):
        _ = ground.mesh(Length(0.5, METER), 4, 0, 0)
    with assert_raises(contains="cells"):
        _ = ground.mesh(Length(10.0, METER), 1, 0, 0)
    with assert_raises(contains="even"):
        _ = ground.mesh(Length(10.0, METER), 5, 0, 0)


def test_a_ridge_ring_closes_and_rises() raises:
    """A ring of eight columns has nine rows a column and closes with no
    seam: its first and last columns meet. Its feet are on the ground."""
    var ring = ridge_ring(
        Length(100.0, METER),
        Length(50.0, METER),
        Length(30.0, METER),
        8,
        3,
    )
    assert_equal(ring.vertex_count(), 81)
    assert_equal(len(ring.index), 8 * 8 * 6)
    ref p = ring.attribute_view(String(POSITION))
    assert_almost_equal(p.vector3(4).y, p.vector3(76).y, atol=1e-3)
    assert_almost_equal(p.vector3(0).y, 0, atol=1e-6)
    assert_almost_equal(p.vector3(8).y, 0, atol=1e-4)
    assert_almost_equal(p.vector3(8).x, 150, atol=1e-3)
    var highest = Float32(0)
    for v in range(81):
        highest = max(highest, p.vector3(v).y)
    assert_true(highest > 0 and highest <= 30 * 1.3)
    with assert_raises(contains="away"):
        _ = ridge_ring(
            Length(1.0, METER), Length(5.0, METER), Length(1.0, METER), 8, 0
        )
    with assert_raises(contains="deep"):
        _ = ridge_ring(
            Length(20.0, METER), Length(0.1, METER), Length(1.0, METER), 8, 0
        )
    with assert_raises(contains="high"):
        _ = ridge_ring(
            Length(20.0, METER), Length(5.0, METER), Length(-1.0, METER), 8, 0
        )
    with assert_raises(contains="columns"):
        _ = ridge_ring(
            Length(20.0, METER), Length(5.0, METER), Length(1.0, METER), 4, 0
        )


def test_a_boulder_sits_on_the_ground_with_moss_on_top() raises:
    """A boulder's lowest point is at zero and it is no wider than its
    roughened radius. A face that looks up is greener than one that
    looks down."""
    var rock = boulder(Length(1.0, METER), 2, 4)
    assert_false(rock.is_indexed())
    ref p = rock.attribute_view(String(POSITION))
    ref n = rock.attribute_view(String(NORMAL))
    ref c = rock.attribute_view(String(COLOR))
    var low = Float32(10)
    var up_green = Float32(0)
    var down_green = Float32(0)
    for v in range(p.count()):
        low = min(low, p.vector3(v).y)
        assert_true(sqrt(p.vector3(v).x ** 2 + p.vector3(v).z ** 2) < 1.6)
        var color = c.vector3(v)
        if n.vector3(v).y > 0.9:
            up_green = max(up_green, color.y / color.x)
        if n.vector3(v).y < -0.5:
            down_green = max(down_green, color.y / color.x)
    assert_almost_equal(low, 0, atol=1e-5)
    assert_true(up_green > down_green)
    with assert_raises(contains="across"):
        _ = boulder(Length(0.001, METER), 2, 0)
    with assert_raises(contains="detail"):
        _ = boulder(Length(1.0, METER), 6, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
