# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A grass field in clusters: its parameters, culling, levels of detail
and the blades each cluster grows."""

from cameras.perspective_camera import PerspectiveCamera
from extensions.vegetation.field import (
    FieldParameters,
    FieldStats,
    GrassField,
    LodBand,
    cluster_triangles,
    default_bands,
    no_stats,
)
from extensions.vegetation.ground import Ground
from extensions.vegetation.kinds import (
    BEYOND,
    BROADLEAF,
    CULLED,
    DRAWN,
    DRY_GRASS,
    GRASS,
    POPPY,
    SEED_HEAD,
)
from extensions.vegetation.wind import Wind, still_air
from math.frustum import Frustum
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length


def _small() -> FieldParameters:
    """Return a field 16 meters across in clusters of 4, thin enough to
    grow fast."""
    var p = FieldParameters()
    p.span = Length(16.0, METER)
    p.cluster_size = Length(4.0, METER)
    p.density = 10
    p.tuft_blades = 4
    p.bands = [
        LodBand(Length(10.0, METER), 1.0, 3),
        LodBand(Length(30.0, METER), 0.001, 1),
    ]
    return p^


def _view(eye: Vector3, target: Vector3) raises -> Frustum:
    """Return what a camera at `eye` looking at `target` sees."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.5, Length(0.1, METER), Length(500.0, METER)
    )
    camera.place(eye, target)
    var view = camera.view_matrix()
    var clip = camera.projection_matrix()
    clip.multiply(view)
    return Frustum.from_camera(
        clip, view, camera.near_distance(), camera.far_distance()
    )


def _refused(var p: FieldParameters, text: String) raises:
    """Assert that the parameters are refused with `text`."""
    with assert_raises(contains=text):
        p.check()


def test_the_default_field_is_accepted() raises:
    """The default meadow and its four levels pass their checks."""
    var p = FieldParameters()
    p.check()
    assert_equal(len(p.bands), 4)
    assert_equal(p.clusters_across(), 30)
    for index in range(len(default_bands())):
        default_bands()[index].check()


def test_each_field_parameter_is_refused_out_of_range() raises:
    """Each field parameter outside its range is refused."""
    var p = _small()
    p.span = Length(0.5, METER)
    _refused(p^, "field must be")
    p = _small()
    p.cluster_size = Length(20.0, METER)
    _refused(p^, "cluster must be")
    p = _small()
    p.span = Length(1.0e4, METER)
    p.cluster_size = Length(0.25, METER)
    _refused(p^, "1,048,576")
    p = _small()
    p.density = 0
    _refused(p^, "blades a square meter")
    p = _small()
    p.tuft_blades = 0
    _refused(p^, "tuft must have")
    p = _small()
    p.tuft_radius = Length(2.0, METER)
    _refused(p^, "tuft must spread")
    p = _small()
    p.height = Length(3.0, METER)
    _refused(p^, "tall")
    p = _small()
    p.height_spread = 1
    _refused(p^, "spread must be")
    p = _small()
    p.width = Length(0.2, METER)
    _refused(p^, "wide")
    p = _small()
    p.curl = Angle(80.0, DEGREE)
    _refused(p^, "curl")
    p = _small()
    p.dry_share = 2
    _refused(p^, "dry share")
    p = _small()
    p.poppy_share = -1
    _refused(p^, "poppy share")
    p = _small()
    p.seed_share = 2
    _refused(p^, "seed share")


def test_the_levels_are_checked_one_by_one_and_in_order() raises:
    """A field needs from one to sixteen levels. Each must be in range,
    reach further than the one before, and keep no more."""
    var p = _small()
    p.bands = List[LodBand]()
    _refused(p^, "levels")
    p = _small()
    for _ in range(16):
        p.bands.append(LodBand(Length(50.0, METER), 0.001, 1))
    _refused(p^, "levels")
    p = _small()
    p.bands[1].reach = Length(2.0e5, METER)
    _refused(p^, "reach from 0")
    p = _small()
    p.bands[1].keep = 0
    _refused(p^, "keep from")
    p = _small()
    p.bands[1].segments = 9
    _refused(p^, "segments")
    p = _small()
    p.bands[1].reach = Length(10.0, METER)
    _refused(p^, "reach further")
    p = _small()
    p.bands[1].keep = 1.0
    p.bands[0].keep = 0.5
    _refused(p^, "keep no more")


def test_a_thinner_level_widens_its_blades() raises:
    """A level that keeps every blade widens nothing; one that keeps a
    tenth widens by ten to the 0.7."""
    assert_almost_equal(LodBand(Length(1.0, METER), 1.0, 2).widen(), 1)
    assert_almost_equal(
        LodBand(Length(1.0, METER), 0.1, 2).widen(), 5.0118723, atol=1e-4
    )


def test_a_field_lays_out_its_clusters_and_bounds() raises:
    """Sixteen meters in clusters of four is sixteen clusters. Each holds
    its share of the blades, and its bound holds every blade it grows."""
    var field = GrassField(_small(), Ground())
    assert_equal(len(field.clusters), 16)
    assert_equal(field.clusters[0].blades, 160)
    assert_equal(field.clusters[0].tufts, 40)
    assert_equal(field.full_blades(), 16 * 160)
    assert_almost_equal(field.clusters[0].corner_x, -8)
    assert_almost_equal(field.clusters[5].corner_z, -4)
    for index in range(len(field.clusters)):
        var bound = field.clusters[index].bound()
        for blade in range(field.clusters[index].blades):
            var grown = field.grow(index, blade)
            if grown:
                assert_true(bound.contains_point(grown.value().root))


def test_ground_that_fails_its_check_is_refused() raises:
    """A ground changed after it was made is checked again."""
    var ground = Ground()
    ground.climb = 5
    with assert_raises(contains="climb"):
        _ = GrassField(_small(), ground)


def test_a_level_holds_a_distance_or_none() raises:
    """The first level whose reach holds the distance is picked, and none
    past the last reach."""
    var field = GrassField(_small(), Ground())
    assert_equal(field.band_for(Length(3.0, METER)).value(), 0)
    assert_equal(field.band_for(Length(20.0, METER)).value(), 1)
    assert_false(field.band_for(Length(31.0, METER)))


def test_choose_draws_culls_or_leaves_each_cluster() raises:
    """From the middle of the field looking toward -z, the clusters in
    front are drawn and those behind are culled. From far away every
    cluster is beyond."""
    var field = GrassField(_small(), Ground())
    var eye = Vector3(0, 1.5, 0)
    var frustum = _view(eye, Vector3(0, 1.0, -10))
    var front = field.choose(1, eye, frustum)
    assert_true(front.fate == DRAWN)
    assert_equal(front.band, 0)
    # The cluster at the back corner, behind the camera.
    var back = field.choose(
        15,
        Vector3(-6, 1.5, -6),
        _view(Vector3(-6, 1.5, -6), Vector3(-6, 1.0, -20)),
    )
    assert_true(back.fate == CULLED)
    var away = Vector3(0, 1.5, 200)
    var far = field.select(away, _view(away, Vector3(0, 0, 0)))
    assert_equal(len(far), 16)
    for index in range(len(far)):
        assert_true(far[index].fate == BEYOND)
    with assert_raises(contains="no cluster"):
        _ = field.choose(-1, eye, frustum)
    with assert_raises(contains="no cluster"):
        _ = field.choose(16, eye, frustum)


def test_kept_is_a_rounded_share_of_the_stream() raises:
    """The full level keeps every blade, and a level that keeps almost
    none still keeps one. A cluster or level that is not there is
    refused."""
    var field = GrassField(_small(), Ground())
    assert_equal(field.kept(0, 0), 160)
    assert_equal(field.kept(0, 1), 1)
    with assert_raises(contains="no cluster"):
        _ = field.kept(-1, 0)
    with assert_raises(contains="no cluster"):
        _ = field.kept(16, 0)
    with assert_raises(contains="no level"):
        _ = field.kept(0, -1)
    with assert_raises(contains="no level"):
        _ = field.kept(0, 2)


def test_the_stream_grows_each_kind_and_skips_bare_tufts() raises:
    """With every tuft a poppy's chance, half the blades dry, some stalks
    and every tuft a weed's chance, the stream grows every kind, and skips
    some tufts where the ground is bare. Some tufts are laid over, more
    curled than any standing tuft. The same blade grows the same way
    twice."""
    var p = _small()
    p.span = Length(60.0, METER)
    p.tuft_blades = 1
    p.poppy_share = 1
    p.dry_share = 0.5
    p.seed_share = 0.3
    p.broadleaf_share = 1
    var standing = p.curl.to(DEGREE) * 1.55 * 1.3
    var field = GrassField(p^, Ground())
    var kinds = List[Int](length=5, fill=0)
    var skipped = 0
    var thick_stems = 0
    var lodged = 0
    for index in range(len(field.clusters)):
        for blade in range(field.clusters[index].blades):
            var grown = field.grow(index, blade)
            if not grown:
                skipped += 1
                continue
            ref b = grown.value()
            b.check()
            kinds[b.kind.value] += 1
            if b.kind == POPPY and abs(b.width.to(METER) - 0.003) > 1e-6:
                thick_stems += 1
            if b.kind == GRASS and b.curl.to(DEGREE) > standing:
                lodged += 1
    assert_true(lodged > 0)
    assert_true(kinds[BROADLEAF.value] > 0)
    assert_true(kinds[GRASS.value] > 0)
    assert_true(kinds[DRY_GRASS.value] > 0)
    assert_true(kinds[POPPY.value] > 0)
    assert_true(kinds[SEED_HEAD.value] > 0)
    assert_true(skipped > 0)
    assert_equal(thick_stems, 0)
    var again = field.grow(3, 7)
    var once = field.grow(3, 7)
    assert_true(again.value().root == once.value().root)
    with assert_raises(contains="no cluster"):
        _ = field.grow(-1, 0)
    with assert_raises(contains="no cluster"):
        _ = field.grow(len(field.clusters), 0)
    with assert_raises(contains="negative"):
        _ = field.grow(0, -1)


def test_build_bakes_a_level_and_a_thin_level_is_lighter() raises:
    """A cluster built at the full level has three segments a blade; at
    the thin level it has one triangle a blade, far fewer. The wind moves
    the tips and not the roots."""
    var field = GrassField(_small(), Ground())
    var full = field.build(5, 0, still_air(), Duration(0.0, SECOND))
    var triangles = cluster_triangles(full.value())
    assert_true(triangles >= 5 * 100)
    var windy = field.build(5, 0, Wind(), Duration(1.0, SECOND))
    assert_equal(cluster_triangles(windy.value()), triangles)
    var thin = Optional[Int](None)
    for index in range(len(field.clusters)):
        var built = field.build(index, 1, still_air(), Duration(0.0, SECOND))
        if built:
            thin = cluster_triangles(built.value())
    assert_true(thin.value() <= 1 + 5)


def test_a_level_whose_blades_are_all_bare_builds_nothing() raises:
    """Where the one blade a thin level keeps does not grow, the level
    builds no geometry."""
    var field = GrassField(_small(), Ground(seed=11))
    var empty = 0
    for index in range(len(field.clusters)):
        if not field.grow(index, 0):
            var built = field.build(
                index, 1, still_air(), Duration(0.0, SECOND)
            )
            assert_false(built)
            empty += 1
    assert_true(empty > 0)


def test_stats_tally_each_fate() raises:
    """Each fate is counted where it belongs."""
    var stats = no_stats()
    stats.tally(DRAWN)
    stats.tally(CULLED)
    stats.tally(CULLED)
    stats.tally(BEYOND)
    assert_equal(stats.clusters, 4)
    assert_equal(stats.drawn, 1)
    assert_equal(stats.culled, 2)
    assert_equal(stats.beyond, 1)
    assert_equal(stats.empty, 0)
    assert_equal(stats.blades, 0)
    assert_equal(stats.triangles, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
