# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA world: the blueprint library, actor attributes and the weather.

The expected numbers come from outside this port:

- The wildcard results, and the `atoi` and `atof` results, are glibc's
  `fnmatch`, `atoi` and `atof`, called from Python through `ctypes`.
- The attribute lists of the sensor blueprints were read out of CARLA's
  `ActorBlueprintFunctionLibrary.cpp` by a regular-expression script.
- The fisheye coefficients are CARLA's Kannala-Brandt defaults printed
  with C's `%f` and the trailing zeros cut, as CARLA prints them.
- The weather presets are the table in CARLA's `WeatherParameters.cpp`.
"""

from extensions.carla.blueprint import (
    AGE_ADULT,
    AGE_CHILD,
    ATTRIBUTE_BOOL,
    ATTRIBUTE_FLOAT,
    ATTRIBUTE_INT,
    ATTRIBUTE_RGB_COLOR,
    ATTRIBUTE_STRING,
    ATTRIBUTE_VECTOR,
    ActorAttribute,
    ActorAttributeType,
    ActorAttributeValue,
    ActorBlueprint,
    BlueprintLibrary,
    GENDER_FEMALE,
    GENDER_OTHER,
    PedestrianAge,
    PedestrianGender,
    PedestrianParameters,
    VehicleParameters,
    catalog_colors,
    default_blueprint_library,
    make_camera_definition,
    make_generic_definition,
    make_lidar_definition,
    make_pedestrian_definition,
    make_vehicle_definition,
    pedestrian_catalog,
    read_float,
    read_int,
    vehicle_catalog,
    wildcard_match,
)
from extensions.carla.weather import (
    WeatherParameters,
    weather_preset,
    weather_preset_names,
)
from render.framebuffer import Color
from std.math import inf, isnan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, Angle, Length


# --- text ---------------------------------------------------------------------


def test_attribute_types_are_checked() raises:
    for t in [
        ATTRIBUTE_BOOL,
        ATTRIBUTE_INT,
        ATTRIBUTE_FLOAT,
        ATTRIBUTE_STRING,
        ATTRIBUTE_RGB_COLOR,
        ATTRIBUTE_VECTOR,
    ]:
        assert_true(t.is_valid())
    assert_false(ActorAttributeType(-1).is_valid())
    assert_false(ActorAttributeType(6).is_valid())
    with assert_raises(contains="type is not valid"):
        _ = ActorAttribute("x", ActorAttributeType(9), ["1"])
    with assert_raises(contains="type is not valid"):
        _ = ActorAttribute.fixed("x", ActorAttributeType(-2), "1")


def test_wildcard_matches_as_fnmatch() raises:
    # (text, pattern, glibc's answer).
    var cases: List[Tuple[String, String, Bool]] = [
        ("sensor.camera.rgb", "*camera*", True),
        ("abc", "a[!b]c", False),
        ("abc", "a[a-c]c", True),
        ("abc", "a[^b]c", False),
        ("a]c", "a[]]c", True),
        ("a-c", "a[a-]c", True),
        ("abc", "a?c", True),
        ("ac", "a?c", False),
        ("a*c", "a\\*c", True),
        ("abc", "a\\*c", False),
        ("abc", "a\\", False),
        ("a\\", "a\\", False),
        ("abc", "a[bc", False),
        ("a[bc", "a[bc", True),
        ("vehicle.lincoln.mkz", "vehicle.*", True),
        ("vehicle.lincoln.mkz", "*.mkz", True),
        ("sensor", "*", True),
        ("", "*", True),
        ("", "?", False),
        ("abc", "*b*c", True),
        ("abcbc", "*bc", True),
        ("abd", "*bc", False),
        ("aXbXc", "a*b*c", True),
        ("a", "[!a]", False),
        ("b", "[a-a]", False),
        ("b", "[!a]", True),
        ("abc", "abc", True),
        ("abc", "abd", False),
        ("abc", "ab", False),
        ("ab", "abc", False),
        ("x", "[", False),
        ("[", "[", True),
        ("a", "[!]", False),
        ("b", "[abc]", True),
        ("a", "[b-d]", False),
    ]
    for c in cases:
        assert_equal(wildcard_match(c[0], c[1]), c[2], c[0] + " ~ " + c[1])


def test_read_int_as_atoi() raises:
    var cases: List[Tuple[String, Int]] = [
        ("3.5f", 3),
        ("", 0),
        ("  -12.25e1x", -12),
        (" +7", 7),
        (".5", 0),
        ("-", 0),
        ("abc", 0),
        ("\t\n42abc", 42),
        ("-17", -17),
        ("99999999999", 1215752191),
        ("-99999999999", -1215752191),
        ("+-3", 0),
        ("2147483648", -2147483648),
        # strtol saturates at 2^63 - 1 and at -2^63; the low 32 bits of
        # those are -1 and 0.
        ("99999999999999999999", -1),
        ("-99999999999999999999", 0),
    ]
    for c in cases:
        assert_equal(read_int(c[0]), c[1], c[0])


def test_read_float_as_atof() raises:
    var cases: List[Tuple[String, Float64]] = [
        ("3.5f", 3.5),
        ("", 0.0),
        ("  -12.25e1x", -122.5),
        (" +7", 7.0),
        (".5", 0.5),
        ("5.", 5.0),
        ("1e", 1.0),
        ("1e+", 1.0),
        ("2e-1", 0.2),
        ("2E+1tail", 20.0),
        ("-", 0.0),
        ("abc", 0.0),
        ("  42abc", 42.0),
        ("-17", -17.0),
        ("1e39", 1.0e39),
        ("0x10", 0.0),
    ]
    for c in cases:
        assert_equal(read_float(c[0]), c[1], c[0])
    assert_equal(read_float("INF"), inf[DType.float64]())
    assert_equal(read_float("-inFinity"), -inf[DType.float64]())
    assert_true(isnan(read_float("nan")))


# --- attributes -------------------------------------------------------------


def test_attribute_starts_at_its_first_value() raises:
    var fov = ActorAttribute("fov", ATTRIBUTE_FLOAT, ["90.0", "110.0"])
    assert_equal(fov.value, "90.0")
    assert_true(fov.is_modifiable)
    assert_false(fov.restrict_to_recommended)
    assert_equal(fov.as_float(), 90)
    var empty = ActorAttribute("mass", ATTRIBUTE_FLOAT, List[String]())
    assert_equal(empty.value, "")
    assert_equal(empty.as_float(), 0)
    var mode = ActorAttribute("mode", ATTRIBUTE_STRING, ["a", "b"], True)
    assert_true(mode.restrict_to_recommended)
    assert_equal(mode.as_string(), "a")


def test_attribute_reads_each_type() raises:
    assert_true(ActorAttribute("b", ATTRIBUTE_BOOL, ["TRUE"]).as_bool())
    assert_false(ActorAttribute("b", ATTRIBUTE_BOOL, ["False"]).as_bool())
    assert_equal(ActorAttribute("i", ATTRIBUTE_INT, [" 42x"]).as_int(), 42)
    var c = ActorAttribute("c", ATTRIBUTE_RGB_COLOR, ["255, 128,0"]).as_color()
    assert_equal(Int(c.r), 255)
    assert_equal(Int(c.g), 128)
    assert_equal(Int(c.b), 0)
    # A negative channel wraps as a cast to an unsigned byte.
    var wrapped = ActorAttribute("c", ATTRIBUTE_RGB_COLOR, ["-1,0,1"])
    assert_equal(Int(wrapped.as_color().r), 255)
    assert_equal(Int(wrapped.as_color().b), 1)


def test_attribute_refuses_a_bad_value() raises:
    with assert_raises(contains="invalid bool: yes"):
        _ = ActorAttribute("b", ATTRIBUTE_BOOL, ["yes"])
    with assert_raises(contains="float overflow"):
        _ = ActorAttribute("f", ATTRIBUTE_FLOAT, ["1e39"])
    with assert_raises(contains="float overflow"):
        _ = ActorAttribute("f", ATTRIBUTE_FLOAT, ["-1e39"])
    with assert_raises(contains="3 channels"):
        _ = ActorAttribute("c", ATTRIBUTE_RGB_COLOR, ["1,2"])
    with assert_raises(contains="integer overflow in color channel"):
        _ = ActorAttribute("c", ATTRIBUTE_RGB_COLOR, ["256,0,0"])
    with assert_raises(contains="v: invalid value type"):
        _ = ActorAttribute("v", ATTRIBUTE_VECTOR, ["1,2,3"])


def test_attribute_refuses_a_bad_cast() raises:
    var i = ActorAttribute("i", ATTRIBUTE_INT, ["1"])
    var s = ActorAttribute("s", ATTRIBUTE_STRING, ["x"])
    with assert_raises(contains="cannot convert to Bool"):
        _ = i.as_bool()
    with assert_raises(contains="cannot convert to Float"):
        _ = i.as_float()
    with assert_raises(contains="cannot convert to RGBColor"):
        _ = i.as_color()
    with assert_raises(contains="cannot convert to String"):
        _ = i.as_string()
    with assert_raises(contains="i: bad attribute cast"):
        _ = ActorAttributeValue("i", ATTRIBUTE_STRING, "1").as_int()
    with assert_raises(contains="cannot convert to Int"):
        _ = s.as_int()


def test_attribute_set() raises:
    var b = ActorAttribute("b", ATTRIBUTE_BOOL, ["true"])
    b.set("FALSE")
    assert_equal(b.value, "false")
    var f = ActorAttribute("f", ATTRIBUTE_FLOAT, ["1.0"])
    f.set("2.5")
    assert_equal(f.as_float(), 2.5)
    with assert_raises(contains="b: invalid bool: maybe"):
        b.set("maybe")
    # CARLA keeps the text it refused.
    assert_equal(b.value, "maybe")
    var fixed = ActorAttribute.fixed("wheels", ATTRIBUTE_INT, "4")
    assert_false(fixed.is_modifiable)
    assert_equal(len(fixed.recommended_values), 0)
    with assert_raises(contains="wheels: read-only attribute"):
        fixed.set("6")
    with assert_raises(contains="invalid bool"):
        _ = ActorAttribute.fixed("b", ATTRIBUTE_BOOL, "on")


def test_attribute_compares_and_prints() raises:
    var a = ActorAttribute("fov", ATTRIBUTE_FLOAT, ["90.0"])
    var b = ActorAttribute.fixed("other", ATTRIBUTE_FLOAT, "90.0")
    var c = ActorAttribute("fov", ATTRIBUTE_STRING, ["90.0"])
    var d = ActorAttribute("fov", ATTRIBUTE_FLOAT, ["91.0"])
    assert_true(a == b)
    assert_false(a == c)
    assert_false(a == d)
    assert_equal(String(a), "ActorAttribute(id=fov,type=2,value=90.0)")
    assert_true(a.is_recommended("90.0"))
    assert_false(a.is_recommended("45.0"))
    assert_true(b.is_recommended("anything"))
    var v = a.to_value()
    assert_equal(v.id, "fov")
    assert_equal(v.value, "90.0")


# --- blueprints -------------------------------------------------------------


def _blueprint(id: String, tags: String) raises -> ActorBlueprint:
    return ActorBlueprint(
        id,
        tags,
        [
            ActorAttribute("role_name", ATTRIBUTE_STRING, ["default"]),
            ActorAttribute("speed", ATTRIBUTE_FLOAT, ["1.0", "2.0"]),
            ActorAttribute.fixed("kind", ATTRIBUTE_STRING, "car"),
        ],
    )


def test_blueprint_tags_and_attributes() raises:
    var b = _blueprint("vehicle.test.one", "vehicle,test,one,test")
    assert_equal(len(b.tags), 3)
    assert_true(b.contains_tag("test"))
    assert_false(b.contains_tag("tes"))
    assert_true(b.match_tags("vehicle.*"))
    assert_true(b.match_tags("t?st"))
    assert_false(b.match_tags("walker*"))
    assert_true(b.contains_attribute("speed"))
    assert_false(b.contains_attribute("color"))
    assert_equal(b.attribute("speed").value, "1.0")
    b.set_attribute("speed", "2.0")
    assert_equal(b.attribute("speed").as_float(), 2)
    with assert_raises(contains="attribute 'color' not found"):
        _ = b.attribute("color")
    with assert_raises(contains="attribute 'color' not found"):
        b.set_attribute("color", "1,2,3")
    with assert_raises(contains="read-only"):
        b.set_attribute("kind", "bus")
    assert_equal(b.size(), 3)
    var d = b.description()
    assert_equal(len(d), 3)
    assert_equal(d[1].value, "2.0")
    assert_equal(
        String(b),
        "ActorBlueprint(id=vehicle.test.one,tags=[vehicle, test, one])",
    )


def test_library_sorts_filters_and_finds() raises:
    var library = BlueprintLibrary(
        [
            _blueprint("walker.b", "walker,b"),
            _blueprint("vehicle.a", "vehicle,a"),
            _blueprint("walker.b", "walker,repeat"),
            _blueprint("static.c", "static,c"),
        ]
    )
    assert_equal(library.size(), 3)
    var ids = library.ids()
    assert_equal(ids[0], "static.c")
    assert_equal(ids[1], "vehicle.a")
    assert_equal(ids[2], "walker.b")
    # The first of two blueprints with one id stays.
    assert_equal(library.at("walker.b").tags[1], "b")
    assert_equal(library.filter("*a*").size(), 3)
    assert_equal(library.filter("*.a").size(), 1)
    assert_equal(library.filter("[sv]*").size(), 2)
    assert_equal(library.filter("nothing").size(), 0)
    assert_true(Bool(library.find("vehicle.a")))
    assert_false(Bool(library.find("vehicle.z")))
    assert_equal(library.at(0).id, "static.c")
    with assert_raises(contains="blueprint 'vehicle.z' not found"):
        _ = library.at("vehicle.z")
    with assert_raises(contains="index out of range"):
        _ = library.at(3)
    with assert_raises(contains="index out of range"):
        _ = library.at(-1)


def test_empty_blueprint_and_library() raises:
    var bare = ActorBlueprint("x.y", "x,y", List[ActorAttribute]())
    assert_false(bare.contains_attribute("role_name"))
    assert_equal(len(bare.description()), 0)
    var library = BlueprintLibrary(List[ActorBlueprint]())
    assert_equal(library.size(), 0)
    assert_equal(library.filter("*").size(), 0)
    assert_equal(library.filter_by_attribute("a", "b").size(), 0)
    assert_false(Bool(library.find("x.y")))
    assert_equal(len(library.ids()), 0)


def test_library_filters_by_attribute() raises:
    var plain = ActorBlueprint(
        "static.plain",
        "static",
        [ActorAttribute.fixed("kind", ATTRIBUTE_STRING, "car")],
    )
    var library = BlueprintLibrary(
        [_blueprint("vehicle.a", "vehicle"), plain^, _blueprint("x.b", "x")]
    )
    # A recommended value counts, whatever the value now is.
    assert_equal(library.filter_by_attribute("speed", "2.0").size(), 2)
    assert_equal(library.filter_by_attribute("speed", "3.0").size(), 0)
    # With no recommended values, the value counts.
    assert_equal(library.filter_by_attribute("kind", "car").size(), 3)
    assert_equal(library.filter_by_attribute("kind", "bus").size(), 0)
    assert_equal(library.filter_by_attribute("color", "1,1,1").size(), 0)


# --- the definitions --------------------------------------------------------


def _check_attributes(
    b: ActorBlueprint, expected: List[Tuple[String, Int, String]]
) raises:
    """Check the attributes after the role and ROS names, in order."""
    assert_equal(b.size(), len(expected) + 2, b.id)
    assert_equal(b.attributes[0].id, "role_name")
    assert_equal(b.attributes[1].id, "ros_name")
    assert_equal(b.attributes[1].value, b.id)
    for i in range(len(expected)):
        ref a = b.attributes[i + 2]
        assert_equal(a.id, expected[i][0], b.id)
        assert_equal(a.type.value, expected[i][1], a.id)
        assert_equal(a.value, expected[i][2], a.id)


comptime B = 0
comptime I = 1
comptime F = 2
comptime S = 3


def test_default_library() raises:
    var library = default_blueprint_library()
    # 22 sensors, 12 vehicles, 37 pedestrians and four others.
    assert_equal(library.size(), 75)
    assert_equal(library.filter("sensor.*").size(), 22)
    assert_equal(library.filter("vehicle.*").size(), 12)
    assert_equal(library.filter("walker.*").size(), 37)
    assert_equal(library.at(0).id, "controller.ai.walker")
    assert_equal(library.at(0).uid, 1)
    assert_equal(library.at(74).uid, 75)
    for id in [
        "static.trigger.friction",
        "static.prop.mesh",
        "util.actor.empty",
        "sensor.camera.rgb_fisheye",
        "sensor.lidar.hss_lidar",
        "sensor.other.v2x_custom",
    ]:
        assert_true(Bool(library.find(id)), id)


def test_rgb_camera_definition() raises:
    var b = default_blueprint_library().at("sensor.camera.rgb")
    assert_equal(len(b.tags), 3)
    assert_equal(b.attributes[0].recommended_values[0], "front")
    assert_equal(len(b.attributes[0].recommended_values), 8)
    _check_attributes(
        b,
        [
            ("sensor_tick", F, "0.0"),
            ("image_size_x", I, "800"),
            ("image_size_y", I, "600"),
            ("fov", F, "90.0"),
            ("lens_circle_falloff", F, "5.0"),
            ("lens_circle_multiplier", F, "0.0"),
            ("lens_k", F, "-1.0"),
            ("lens_kcube", F, "0.0"),
            ("lens_x_size", F, "0.08"),
            ("lens_y_size", F, "0.08"),
            ("use_ray_tracing", B, "true"),
            ("enable_postprocess_effects", B, "true"),
            ("post_process_profile", S, "Default"),
        ],
    )
    # Without its post-process switch, a camera stops at ray tracing.
    assert_equal(make_camera_definition("depth").size(), 13)


def test_normals_and_dvs_definitions() raises:
    var library = default_blueprint_library()
    assert_equal(library.at("sensor.camera.normals").size(), 13)
    var dvs = library.at("sensor.camera.dvs")
    assert_equal(dvs.size(), 22)
    assert_equal(dvs.attribute("use_log").value, "True")
    assert_true(dvs.attribute("use_log").as_bool())
    assert_equal(dvs.attribute("refractory_period_ns").as_int(), 0)
    assert_equal(dvs.attribute("log_eps").value, "0.001")


def test_fisheye_definition() raises:
    var b = default_blueprint_library().at("sensor.camera.rgb_fisheye")
    var expected: List[Tuple[String, Int, String]] = [
        ("sensor_tick", F, "0.0"),
        ("camera_model", S, "perspective"),
        ("k0", F, "0.083092"),
        ("k1", F, "0.011121"),
        ("k2", F, "0.008587"),
        ("k3", F, "0.000854"),
        ("image_size_x", I, "800"),
        ("image_size_y", I, "600"),
        ("fov", F, "90.0"),
        ("focal_length", F, "0.0"),
        ("equirectangular", B, "false"),
        ("fov_mask", B, "false"),
        ("fov_fade_size", F, "0.0"),
        ("longitude_offset", F, "0.0"),
        ("perspective", B, "false"),
        ("lens_circle_falloff", F, "5.0"),
        ("lens_circle_multiplier", F, "0.0"),
        ("lens_k", F, "-1.0"),
        ("lens_kcube", F, "0.0"),
        ("lens_x_size", F, "0.08"),
        ("lens_y_size", F, "0.08"),
        ("exposure_mode", S, "histogram"),
        ("exposure_compensation", F, "0.0"),
        ("shutter_speed", F, "200.0"),
        ("iso", F, "100.0"),
        ("fstop", F, "1.4"),
        ("enable_postprocess_effects", B, "true"),
        ("gamma", F, "2.2"),
        ("motion_blur_intensity", F, "0.45"),
        ("motion_blur_max_distortion", F, "0.35"),
        ("lens_flare_intensity", F, "0.1"),
        ("bloom_intensity", F, "0.675"),
        ("motion_blur_min_object_screen_size", F, "0.1"),
        ("exposure_min_bright", F, "10.0"),
        ("exposure_max_bright", F, "12.0"),
        ("exposure_speed_up", F, "3.0"),
        ("exposure_speed_down", F, "1.0"),
        ("calibration_constant", F, "16.0"),
        ("focal_distance", F, "1000.0"),
        ("min_fstop", F, "1.2"),
        ("blade_count", I, "5"),
        ("blur_amount", F, "1.0"),
        ("blur_radius", F, "0.0"),
        ("slope", F, "0.88"),
        ("toe", F, "0.55"),
        ("shoulder", F, "0.26"),
        ("black_clip", F, "0.0"),
        ("white_clip", F, "0.04"),
        ("temp", F, "6500.0"),
        ("tint", F, "0.0"),
        ("chromatic_aberration_intensity", F, "0.0"),
        ("chromatic_aberration_offset", F, "0.0"),
    ]
    _check_attributes(b, expected)
    var mode = b.attribute("exposure_mode")
    assert_true(mode.restrict_to_recommended)
    assert_equal(mode.recommended_values[1], "manual")
    var depth = default_blueprint_library().at("sensor.camera.depth_fisheye")
    assert_equal(depth.size(), 23)


def test_lidar_definitions() raises:
    var library = default_blueprint_library()
    _check_attributes(
        library.at("sensor.lidar.ray_cast"),
        [
            ("sensor_tick", F, "0.0"),
            ("channels", I, "64"),
            ("range", F, "50.0"),
            ("points_per_second", I, "600000"),
            ("rotation_frequency", F, "60.0"),
            ("upper_fov", F, "10.0"),
            ("lower_fov", F, "-30.0"),
            ("atmosphere_attenuation_rate", F, "0.004"),
            ("noise_seed", I, "0"),
            ("dropoff_general_rate", F, "0.45"),
            ("dropoff_intensity_limit", F, "0.8"),
            ("dropoff_zero_intensity", F, "0.4"),
            ("noise_stddev", F, "0.0"),
            ("horizontal_fov", F, "360.0"),
        ],
    )
    _check_attributes(
        library.at("sensor.lidar.ray_cast_semantic"),
        [
            ("sensor_tick", F, "0.0"),
            ("channels", I, "64"),
            ("range", F, "50.0"),
            ("points_per_second", I, "600000"),
            ("rotation_frequency", F, "60.0"),
            ("upper_fov", F, "10.0"),
            ("lower_fov", F, "-30.0"),
            ("horizontal_fov", F, "360.0"),
        ],
    )
    _check_attributes(
        library.at("sensor.lidar.hss_lidar"),
        [
            ("sensor_tick", F, "0.0"),
            ("channels", I, "128"),
            ("range", F, "200"),
            ("rotation_frequency", F, "20"),
            ("upper_fov", F, "12.9"),
            ("lower_fov", F, "-12.5"),
            ("atmosphere_attenuation_rate", F, "0.004"),
            ("noise_seed", I, "0"),
            ("dropoff_general_rate", F, "0.45"),
            ("dropoff_intensity_limit", F, "0.8"),
            ("dropoff_zero_intensity", F, "0.4"),
            ("noise_stddev", F, "0.0"),
            ("horizontal_fov", F, "120.0"),
            ("horizontal_resolution", F, "0.1"),
        ],
    )
    with assert_raises(contains="LiDAR id is not valid: sonar"):
        _ = make_lidar_definition("sonar")


def test_other_sensor_definitions() raises:
    var library = default_blueprint_library()
    var radar = library.at("sensor.other.radar")
    # No role names for the radar, the GNSS and the IMU.
    assert_equal(len(radar.attributes[0].recommended_values), 1)
    _check_attributes(
        radar,
        [
            ("sensor_tick", F, "0.0"),
            ("horizontal_fov", F, "30"),
            ("vertical_fov", F, "30"),
            ("range", F, "100"),
            ("points_per_second", I, "1500"),
            ("noise_seed", I, "0"),
        ],
    )
    var gnss = library.at("sensor.other.gnss")
    assert_equal(gnss.size(), 10)
    assert_equal(gnss.attributes[4].id, "noise_lat_stddev")
    assert_equal(gnss.attributes[9].id, "noise_alt_bias")
    var imu = library.at("sensor.other.imu")
    assert_equal(imu.size(), 13)
    assert_equal(imu.attributes[12].id, "noise_gyro_bias_z")
    var obstacle = library.at("sensor.other.obstacle")
    _check_attributes(
        obstacle,
        [
            ("sensor_tick", F, "0.0"),
            ("distance", F, "5.0"),
            ("hit_radius", F, "0.5"),
            ("only_dynamics", B, "false"),
            ("debug_linetrace", B, "false"),
        ],
    )
    assert_equal(len(obstacle.attributes[0].recommended_values), 8)
    assert_equal(library.at("sensor.other.collision").size(), 2)
    assert_equal(library.at("sensor.other.lane_invasion").size(), 2)
    var v2x = library.at("sensor.other.v2x")
    assert_equal(v2x.size(), 33)
    assert_equal(v2x.attribute("scenario").value, "highway")
    assert_true(v2x.attribute("path_loss_model").restrict_to_recommended)
    assert_equal(v2x.attributes[32].id, "noise_vel_stddev_x")
    assert_equal(v2x.attribute("receiver_sensitivity").as_float(), -99)
    var custom = library.at("sensor.other.v2x_custom")
    assert_equal(custom.size(), 16)
    assert_equal(custom.attributes[15].id, "custom_fading_stddev")


def test_vehicle_definition() raises:
    var b = default_blueprint_library().at("vehicle.lincoln.mkz")
    var roles = b.attributes[0].recommended_values.copy()
    assert_equal(len(roles), 3)
    assert_equal(roles[2], "ego_vehicle")
    assert_equal(b.attributes[0].value, "autopilot")
    _check_attributes(
        b,
        [
            ("color", 4, "255,255,255"),
            ("sticky_control", B, "true"),
            ("terramechanics", B, "false"),
            ("ros2_ackermann_control", B, "false"),
            ("object_type", S, ""),
            ("base_type", S, "car"),
            ("special_type", S, ""),
            ("number_of_wheels", I, "4"),
            ("generation", I, "2"),
            ("has_dynamic_doors", B, "true"),
            ("has_lights", B, "true"),
        ],
    )
    assert_equal(len(b.attributes[2].recommended_values), 5)
    assert_false(b.attribute("generation").is_modifiable)
    assert_equal(len(catalog_colors()), 5)
    assert_equal(len(vehicle_catalog()), 12)
    var cola = default_blueprint_library().at("vehicle.carlacola.actors")
    assert_equal(cola.attribute("base_type").value, "truck")
    assert_false(cola.attribute("has_lights").as_bool())
    var cop = default_blueprint_library().at("vehicle.dodgecop.charger")
    assert_equal(cop.attribute("special_type").value, "emergency")


def test_vehicle_with_drivers_and_no_colors() raises:
    var p = VehicleParameters(
        "Make",
        "Bike",
        "bicycle",
        "",
        "",
        2,
        1,
        False,
        False,
        List[Color](),
        [0, 1, 2],
    )
    var b = make_vehicle_definition(p)
    assert_equal(b.id, "vehicle.make.bike")
    assert_false(b.contains_attribute("color"))
    var drivers = b.attribute("driver_id")
    assert_true(drivers.restrict_to_recommended)
    assert_equal(drivers.as_int(), 0)
    assert_equal(len(drivers.recommended_values), 3)
    assert_equal(b.attribute("number_of_wheels").as_int(), 2)


def test_pedestrian_definitions() raises:
    var catalog = pedestrian_catalog()
    assert_equal(len(catalog), 37)
    assert_equal(catalog[0].id, "0015")
    assert_equal(catalog[36].id, "0051")
    var library = default_blueprint_library()
    var adult = library.at("walker.pedestrian.0015")
    assert_equal(adult.attributes[0].value, "pedestrian")
    _check_attributes(
        adult,
        [
            ("speed", F, "0.0"),
            ("is_invincible", B, "true"),
            ("gender", S, "other"),
            ("generation", I, "2"),
            ("age", S, "adult"),
        ],
    )
    assert_equal(adult.attribute("speed").recommended_values[2], "2.8")
    var child = library.at("walker.pedestrian.0048")
    assert_equal(child.attribute("age").value, "child")
    var p = PedestrianParameters(
        "X9", GENDER_FEMALE, AGE_ADULT, 1, List[Float32]()
    )
    var b = make_pedestrian_definition(p)
    assert_equal(b.id, "walker.pedestrian.x9")
    assert_false(b.contains_attribute("speed"))
    assert_equal(b.attribute("gender").value, "female")
    assert_true(GENDER_OTHER.is_valid())
    assert_true(AGE_CHILD.is_valid())
    assert_false(PedestrianGender(3).is_valid())
    assert_false(PedestrianAge(-1).is_valid())
    with assert_raises(contains="gender or age is not valid"):
        _ = make_pedestrian_definition(
            PedestrianParameters(
                "1", PedestrianGender(3), AGE_ADULT, 1, List[Float32]()
            )
        )
    with assert_raises(contains="gender or age is not valid"):
        _ = make_pedestrian_definition(
            PedestrianParameters(
                "1", GENDER_OTHER, PedestrianAge(4), 1, List[Float32]()
            )
        )


def test_other_definitions() raises:
    var library = default_blueprint_library()
    var trigger = library.at("static.trigger.friction")
    assert_equal(trigger.attribute("friction").value, "3.5f")
    assert_equal(trigger.attribute("friction").as_float(), 3.5)
    assert_equal(trigger.attribute("extent_z").as_float(), 1)
    var mesh = library.at("static.prop.mesh")
    assert_equal(mesh.attribute("mass").as_float(), 0)
    assert_equal(mesh.attribute("scale").as_float(), 1)
    var generic = make_generic_definition("Util", "Actor", "Empty")
    assert_equal(generic.id, "util.actor.empty")
    assert_equal(generic.tags[2], "empty")
    assert_equal(generic.size(), 2)


# --- the weather --------------------------------------------------------------


def _fields(w: WeatherParameters) -> List[Float32]:
    return [
        w.cloudiness,
        w.precipitation,
        w.precipitation_deposits,
        w.wind_intensity,
        w.sun_azimuth_angle.to(DEGREE),
        w.sun_altitude_angle.to(DEGREE),
        w.fog_density,
        w.fog_distance.value,
        w.fog_falloff,
        w.wetness,
        w.scattering_intensity,
        w.mie_scattering_scale,
        w.rayleigh_scattering_scale,
        w.dust_storm,
    ]


def test_weather_defaults() raises:
    var w = WeatherParameters()
    var f = _fields(w)
    for i in range(14):
        if i == 12:
            assert_almost_equal(f[i], 0.0331, atol=1e-7)
        else:
            assert_equal(f[i], 0)


def test_weather_presets_are_carlas_table() raises:
    # CARLA's `WeatherParameters.cpp`, row by row.
    var table: List[List[Float32]] = [
        [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 1, 0.03, 0.0331, 0],
        [5, 0, 0, 10, -1, 45, 2, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [60, 0, 0, 10, -1, 45, 3, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [5, 0, 50, 10, -1, 45, 3, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [60, 0, 50, 10, -1, 45, 3, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [60, 60, 60, 60, -1, 45, 3, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [100, 100, 90, 100, -1, 45, 7, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [20, 30, 50, 30, -1, 45, 3, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [5, 0, 0, 10, -1, 15, 2, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [60, 0, 0, 10, -1, 15, 3, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [5, 0, 50, 10, -1, 15, 2, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [60, 0, 50, 10, -1, 15, 2, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [60, 60, 60, 60, -1, 15, 3, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [100, 100, 90, 100, -1, 15, 7, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [20, 30, 50, 30, -1, 15, 2, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [5, 0, 0, 10, -1, -90, 60, 75, 1, 0, 1, 0.03, 0.0331, 0],
        [60, 0, 0, 10, -1, -90, 60, 0.75, 0.1, 0, 1, 0.03, 0.0331, 0],
        [5, 0, 50, 10, -1, -90, 60, 75, 1, 60, 1, 0.03, 0.0331, 0],
        [60, 0, 50, 10, -1, -90, 60, 0.75, 0.1, 60, 1, 0.03, 0.0331, 0],
        [60, 30, 50, 30, -1, -90, 60, 0.75, 0.1, 60, 1, 0.03, 0.0331, 0],
        [80, 60, 60, 60, -1, -90, 60, 0.75, 0.1, 80, 1, 0.03, 0.0331, 0],
        [100, 100, 90, 100, -1, -90, 100, 0.75, 0.1, 100, 1, 0.03, 0.0331, 0],
        [100, 0, 0, 100, -1, 45, 2, 0.75, 0.1, 0, 1, 0.03, 0.0331, 100],
    ]
    var names = weather_preset_names()
    assert_equal(len(names), 23)
    for row in range(23):
        var f = _fields(weather_preset(names[row]))
        for i in range(14):
            # The angles and the fog distance pass through a unit scale.
            assert_almost_equal(f[i], table[row][i], atol=1e-5, msg=names[row])
    with assert_raises(contains="No weather preset is named Sunny"):
        _ = weather_preset("Sunny")


def test_weather_compares_every_field() raises:
    var base = weather_preset("ClearNoon")
    assert_true(base == weather_preset("ClearNoon"))
    for i in range(14):
        var w = base
        if i == 0:
            w.cloudiness += 1
        elif i == 1:
            w.precipitation += 1
        elif i == 2:
            w.precipitation_deposits += 1
        elif i == 3:
            w.wind_intensity += 1
        elif i == 4:
            w.sun_azimuth_angle = Angle(10, DEGREE)
        elif i == 5:
            w.sun_altitude_angle = Angle(10, DEGREE)
        elif i == 6:
            w.fog_density += 1
        elif i == 7:
            w.fog_distance = Length(9, METER)
        elif i == 8:
            w.fog_falloff += 1
        elif i == 9:
            w.wetness += 1
        elif i == 10:
            w.scattering_intensity += 1
        elif i == 11:
            w.mie_scattering_scale += 1
        elif i == 12:
            w.rayleigh_scattering_scale += 1
        else:
            w.dust_storm += 1
        assert_false(w == base, String(i))


def test_weather_clamps_and_screens() raises:
    var high = WeatherParameters(
        150, 150, 150, 150, 400, 100, 150, 5, 2, 150, 150, 9, 9, 150
    )
    var f = _fields(high.clamped())
    var top: List[Float32] = [
        100,
        100,
        100,
        100,
        360,
        90,
        100,
        5,
        2,
        100,
        100,
        5,
        2,
        100,
    ]
    for i in range(14):
        assert_almost_equal(f[i], top[i], atol=1e-4)
    var low = WeatherParameters(
        -5, -5, -5, -5, -5, -100, -5, -5, -5, -5, -5, -5, -5, -5
    )
    f = _fields(low.clamped())
    for i in range(14):
        var want = Float32(-90) if i == 5 else Float32(0)
        assert_almost_equal(f[i], want, atol=1e-4)
    var rain = weather_preset("MidRainyNoon")
    assert_almost_equal(rain.rain_screen_weight(), 0.6, atol=1e-7)
    assert_equal(rain.dust_screen_weight(), 0)
    var dust = weather_preset("DustStorm")
    assert_equal(dust.rain_screen_weight(), 0)
    assert_equal(dust.dust_screen_weight(), 1)
    var text = String(weather_preset("ClearNoon"))
    assert_true(text.startswith("WeatherParameters(cloudiness=5.0"))
    assert_true("dust_storm=0.0)" in text)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
