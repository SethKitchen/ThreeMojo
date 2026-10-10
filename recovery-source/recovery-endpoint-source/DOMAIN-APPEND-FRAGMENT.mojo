def _last_endpoint_refusal_road() raises -> Road:
    var curvature = bitcast[DType.float64](UInt64(13965043853212778490))
    var length = bitcast[DType.float64](UInt64(2022) << UInt64(52))
    var geometry = RoadGeometry(SPIRAL, 0, 0, 0, 0, length)
    geometry.curvature_start = curvature
    geometry.curvature_end = _next_up(curvature)
    var road = Road(RoadId(1), "direct last-end junction helper refusal", 2.0, NO_JUNCTION, RoadId(0), RoadId(0), True)
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0)))
    road.info.geometries.append(RoadInfoGeometry(0.0, geometry^))
    road.info.elevations.append(RoadInfoElevation(0.0, CubicPolynomial(2.0, 1.0, 0.0, 0.0, 0.0)))
    road.info.lane_offsets.append(RoadInfoLaneOffset(0.0, CubicPolynomial.constant(1.0)))
    var validation = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, validation)
    assert_false(validation.exhausted)
    return road^


def _last_endpoint_control(mode: Int32) raises:
    var road = _last_endpoint_refusal_road()
    var low = bitcast[DType.float64](UInt64(4607182418800017407))
    var high = bitcast[DType.float64](UInt64(4607182418800017409))
    # The finite proposal leaves elevation at its public Float32 value3.
    # Its broad XY extent is an ordinary proposal, not an injected Jet.
    var proposal = Box3(Vector3(-2, -2, 3), Vector3(2, 2, 3))
    assert_true(_sum2_supported_environment())
    var original = external_call["sum2_test_set_mode", UInt64](mode)
    try:
        var mask = external_call["sum2_test_control_mask", UInt64]()
        var actual = external_call["sum2_test_get_state", UInt64]()
        var expected = external_call["sum2_test_mode_bits", UInt64](mode)
        assert_equal(actual & mask, expected)
        assert_false(_sum2_supported_environment())
        var terms = _reference_work(road, low, high)
        assert_equal(terms, 5000000005)
        assert_equal(_reference_work(road, low, low), 5000000005)
        assert_equal(_reference_work(road, high, high), -1)
        var point = _lane_value_bound(road, 0, 0, low, high)
        var x = point[0].rounded_value()
        var y = -point[1].rounded_value()
        var z = point[2].rounded_value()
        assert_false(x.is_finite())
        assert_false(y.is_finite())
        assert_true(z.is_finite())
        assert_true(z.low < 3.0 or z.high > 3.0)
        var work = _MapBuildWork(MapBuildBudget(0, 5, terms, 0))
        var result = _monotone_junction_enclosure(road, 0, 0, low, high, terms, proposal, x, y, z, work)
        _same_interval_words(result[0], x)
        _same_interval_words(result[1], y)
        _same_interval_words(result[2], z)
        assert_equal(work.steps, 5)
        assert_equal(work.terms, terms)
        assert_false(work.exhausted)
        var short = _MapBuildWork(MapBuildBudget(0, 5, terms - 1, 0))
        with assert_raises(contains="global term budget"):
            _ = _monotone_junction_enclosure(road, 0, 0, low, high, terms, proposal, x, y, z, short)
        assert_equal(short.steps, 1)
        assert_equal(short.terms, 0)
        assert_true(short.exhausted)
        print("LAST_REFUSAL_LEDGER", mode, work.steps, work.terms, short.steps, short.terms)
    except error:
        external_call["sum2_test_restore_mode", NoneType](original)
        raise error
    external_call["sum2_test_restore_mode", NoneType](original)
    assert_equal(external_call["sum2_test_get_state", UInt64](), original)
    assert_true(_sum2_supported_environment())


def test_real_last_endpoint_refusal_preserves_helper_bounds_and_reservations() raises:
    var modes = external_call["sum2_test_mode_count", Int32]()
    assert_true(modes == 5 or modes == 7)
    if modes == 7:
        _last_endpoint_control(Int32(5))
        _last_endpoint_control(Int32(6))
    else:
        print("LAST_DAZ_CAPABILITY_UNAVAILABLE: fixture exposes Arm modes0..4; first-end FTZ control is a separate maintained test")


def test_real_junction_admitted_endpoints_charge_both_traversals() raises:
    var road = _endpoint_refusal_road()
    road.info.geometries[0].geometry.curvature_start = 0.0
    road.info.geometries[0].geometry.curvature_end = 0.0
    var low = Float64(0)
    var high = Float64(0.125)
    var terms = _reference_work(road, low, high)
    var first_terms = _reference_work(road, low, low)
    var last_terms = _reference_work(road, high, high)
    assert_true(terms >= 0)
    assert_true(first_terms >= 0)
    assert_true(last_terms >= 0)
    var point = _lane_value_bound(road, 0, 0, low, high)
    var work = _MapBuildWork(MapBuildBudget(0, 9, terms + first_terms + last_terms, 0))
    var result = _monotone_junction_enclosure(road, 0, 0, low, high, terms, Box3(Vector3(-2, -2, 2), Vector3(2, 2, 2)), point[0].rounded_value(), -point[1].rounded_value(), point[2].rounded_value(), work)
    assert_equal(work.steps, 9)
    assert_equal(work.terms, terms + first_terms + last_terms)
    assert_false(work.exhausted)
    for station in [low, high]:
        var actual = road._lane_center(0, 0, station)
        assert_true(result[0].contains(actual[0]))
        assert_true(result[1].contains(actual[1]))
        assert_true(result[2].contains(actual[2]))
    print("ADMITTED_LEDGER", work.steps, work.terms)


def _chord_endpoint_refusal_road(first_refuses: Bool, last_refuses: Bool) raises -> Road:
    var road = Road(RoadId(1), "bounded endpoint preflight", 4.0, NO_JUNCTION, RoadId(0), RoadId(0), True)
    _ = road.add_section(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0)))
    road.info.elevations.append(RoadInfoElevation(0.0, CubicPolynomial.constant(0.0)))
    road.info.lane_offsets.append(RoadInfoLaneOffset(0.0, CubicPolynomial.constant(1.0)))
    var first = RoadGeometry(SPIRAL if first_refuses else LINE, 0, 0, 0, 0, 2)
    first.curvature_start = 2e9
    first.curvature_end = 2e9
    var last = RoadGeometry(SPIRAL if last_refuses else LINE, 2, 2, 0, 0, 2)
    last.curvature_start = 2e9
    last.curvature_end = 2e9
    road.info.geometries.append(RoadInfoGeometry(0.0, first^))
    road.info.geometries.append(RoadInfoGeometry(2.0, last^))
    var validation = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, validation)
    assert_false(validation.exhausted)
    return road^


def _chord_endpoint_refusal_control(first_refuses: Bool, last_refuses: Bool) raises:
    var road = _chord_endpoint_refusal_road(first_refuses, last_refuses)
    assert_equal(_reference_work(road, 1.0, 3.0), -1)
    assert_equal(_reference_work(road, 1.0, 1.0), -1 if first_refuses else 1)
    assert_equal(_reference_work(road, 3.0, 3.0), -1 if last_refuses else 1)
    # A single original proof node admits the unresolved root and refuses
    # either child before traversal. The standard 2-million-term cap stays.
    var nodes = _ProofNodeWork(1, fail_on_limit=False)
    var captured = _SpiralRootCapture()
    var result = _chord_certificate_capture_with_nodes(road, 0, 0, 1.0, 3.0, Vector3(1, 0, 0), Vector3(3, 0, 0), captured, nodes)
    assert_equal(result[0], inf[DType.float64]())
    for value in [result[1][0], result[1][1], result[1][2]]:
        assert_equal(value.low, -inf[DType.float64]())
        assert_equal(value.high, inf[DType.float64]())
    assert_equal(result[2], 0)
    assert_equal(nodes.used, 1)
    assert_equal(nodes.limit, 1)
    print("CHORD_REFUSAL", first_refuses, last_refuses, result[2], nodes.used)


def test_real_chord_first_endpoint_refusal() raises:
    _chord_endpoint_refusal_control(True, False)


def test_real_chord_last_endpoint_refusal() raises:
    _chord_endpoint_refusal_control(False, True)


def test_real_chord_admitted_endpoints_keep_derivative_fallback() raises:
    _chord_endpoint_refusal_control(False, False)


