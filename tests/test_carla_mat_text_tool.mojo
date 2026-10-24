# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""UModel `.mat` and `.props.txt` text, as JSON.

The strings are the objects `json.dumps` writes for the same files: a
`.mat` map with `_others` last, and a `.props.txt` parent, vectors,
scalars and blend flags.
"""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import ProcessResult, run_program
from tools.carla_mat_text import mat_text, props_text


def _dir() raises -> String:
    """Return an empty temporary directory."""
    return mkdtemp(prefix="test mat text ")


def _remove(root: String) raises:
    """Remove a temporary directory."""
    var result = run_program(["rm", "-rf", root], 10)
    if result.status != 0:
        raise Error(result.output)


def _text(root: String, name: String, text: String) raises -> String:
    """Write `text` and return its path."""
    var path = root + "/" + name
    Path(path).write_text(text)
    return path


def _bytes(root: String, name: String, var data: List[UInt8]) raises -> String:
    """Write `data` and return its path."""
    var path = root + "/" + name
    Path(path).write_bytes(Span(data))
    return path


def _cli(var arguments: List[String]) raises -> ProcessResult:
    """Run the built material-text program."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(tool_mojo())
    command.append("carla_mat_text")
    command.extend(arguments^)
    return run_program(command, 30, merge_errors=False)


def test_mat_pairs_keep_later_values_and_other_keys() raises:
    var root = _dir()
    var path = _text(
        root,
        "Red.mat",
        "\n  Diffuse=T_Red\nOther[0]=logo\nskip\nDiffuse=T_Blue\n"
        + "Other[1]=banner\n=bare\n",
    )
    assert_equal(
        mat_text(path),
        '{"Diffuse": "T_Blue", "": "bare", "_others": ["logo", "banner"]}',
    )
    _remove(root)


def test_a_literal_others_key_keeps_its_place() raises:
    var root = _dir()
    var path = _text(
        root, "Red.mat", "_others=kept\nDiffuse= Red\nother=stay\nOther=logo\n"
    )
    assert_equal(
        mat_text(path),
        '{"_others": ["logo"], "Diffuse": " Red", "other": "stay"}',
    )
    _remove(root)


def test_props_read_the_parent_parameters_and_blend() raises:
    var root = _dir()
    var path = _text(
        root,
        "Glass.props.txt",
        "Parent = Material'/Game/Carla/Glass.Glass'\n"
        + "Name=Roughness } ParameterValue = 0.35\n"
        + "Name=Base Color } ParameterValue = { R=0.1, G=0.2, B=0.3, A=1 }\n"
        + "BlendMode = BLEND_Masked\n",
    )
    assert_equal(
        props_text(path),
        '{"parent": "/Game/Carla/Glass.Glass", "vectors": {"Base Color": '
        + '[0.1, 0.2, 0.3, 1.0]}, "scalars": {"Roughness": 0.35}, '
        + '"translucent": false, "masked": true}',
    )
    _remove(root)


def test_props_keep_both_blend_flags_and_a_small_number() raises:
    var root = _dir()
    var path = _text(
        root,
        "Paint.props.txt",
        "noise\nParent = Material'/Game/Ok.Ok'\n"
        + "Name=Opacity } ParameterValue = 1.25e-1\n"
        + "Name=Tint } ParameterValue = { R=-1.5e-2, G=0, B=1.5, A=1 }\n"
        + "BlendMode = BLEND_Translucent\nBlendMode = BLEND_Masked\n",
    )
    assert_equal(
        props_text(path),
        '{"parent": "/Game/Ok.Ok", "vectors": {"Tint": [-0.015, 0.0, 1.5, '
        + '1.0]}, "scalars": {"Opacity": 0.125}, "translucent": true, '
        + '"masked": true}',
    )
    _remove(root)


def test_a_bad_parent_and_a_bare_scalar_stay_empty() raises:
    var root = _dir()
    var path = _text(
        root,
        "Bad.props.txt",
        "Note = Material'/Game/Nope.Nope'\nParent = '/missing'\n"
        + "Name=Opacity } ParameterValue = 0.5\n"
        + "Name=A } B } ParameterValue = { R=1, G=2, B=3, A=4 }\n",
    )
    assert_equal(
        props_text(path),
        '{"parent": "", "vectors": {}, "scalars": {"Opacity": 0.5}, '
        + '"translucent": false, "masked": false}',
    )
    _remove(root)


def test_crlf_and_a_bad_byte_still_parse() raises:
    var root = _dir()
    var text = (
        "Parent = Material'/Game/Carla/Glass.Glass'\r\n"
        + "Name=Roughness } ParameterValue = 0.35\r\n"
        + "Name=Base Color } ParameterValue = { R=0.1, G=0.2, B=0.3, A=1 }\r\n"
        + "BlendMode = BLEND_Masked\r\n"
    )
    var data = List[UInt8]()
    for byte in text.as_bytes():
        data.append(byte)
    data.append(0xFF)
    var path = _bytes(root, "Glass.props.txt", data^)
    assert_equal(
        props_text(path),
        '{"parent": "/Game/Carla/Glass.Glass", "vectors": {"Base Color": '
        + '[0.1, 0.2, 0.3, 1.0]}, "scalars": {"Roughness": 0.35}, '
        + '"translucent": false, "masked": true}',
    )
    _remove(root)


def test_unicode_text_matches_json_dumps() raises:
    var root = _dir()
    var data = List[UInt8]()
    var head = "Diffuse=caf"
    for byte in head.as_bytes():
        data.append(byte)
    data.append(0xC3)
    data.append(0xA9)
    data.append(0xF0)
    data.append(0x9F)
    data.append(0x98)
    data.append(0x80)
    data.append(13)
    data.append(10)
    var name = "Name="
    for byte in name.as_bytes():
        data.append(byte)
    data.append(0xC3)
    data.append(0xA9)
    data.append(10)
    var other = "Other="
    for byte in other.as_bytes():
        data.append(byte)
    data.append(0xFF)
    data.append(10)
    var bad = "Bad="
    for byte in bad.as_bytes():
        data.append(byte)
    data.append(0xC3)
    data.append(0x28)
    data.append(10)
    var path = _bytes(root, "Red.mat", data^)
    assert_equal(
        mat_text(path),
        '{"Diffuse": "caf\\u00e9\\ud83d\\ude00", "Name": "\\u00e9", "Bad": '
        + '"\\ufffd(", "_others": ["\\ufffd"]}',
    )
    _remove(root)


def test_a_missing_file_is_an_error() raises:
    var root = _dir()
    with assert_raises():
        _ = mat_text(root + "/missing.mat")
    with assert_raises():
        _ = props_text(root + "/missing.props.txt")
    _remove(root)


def _args(first: String, second: String) -> List[String]:
    """Return two command arguments."""
    var arguments = List[String]()
    arguments.append(first)
    arguments.append(second)
    return arguments^


def test_the_command_prints_the_file_and_refuses_bad_use() raises:
    var root = _dir()
    var mat = _text(root, "Red.mat", "Diffuse=T_Blue\n")
    var props = _text(
        root, "Glass.props.txt", "BlendMode = BLEND_Translucent\n"
    )
    var mat_result = _cli(_args("mat", mat))
    assert_equal(mat_result.status, 0)
    assert_equal(mat_result.errors, "")
    assert_equal(mat_result.output, '{"Diffuse": "T_Blue", "_others": []}\n')
    var prop_result = _cli(_args("props", props))
    assert_equal(prop_result.status, 0)
    assert_equal(prop_result.errors, "")
    assert_equal(prop_result.output.find('{"parent": "'), 0)
    assert_equal(
        prop_result.output,
        '{"parent": "", "vectors": {}, "scalars": {}, "translucent": true, '
        + '"masked": false}\n',
    )
    var usage = _cli(List[String]())
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_mat_text mat|props FILE\n")
    var refused = _cli(_args("nope", mat))
    assert_equal(refused.status, 2)
    assert_equal(refused.errors, "usage: carla_mat_text mat|props FILE\n")
    var failed = _cli(_args("mat", root + "/missing.mat"))
    assert_equal(failed.status, 1)
    assert_true(failed.errors.startswith("carla_mat_text:"))
    assert_true(failed.errors.find("Crashpad") < 0)
    _remove(root)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_mat_text"], 120
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
