# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Subprocess entry points for tools/check_portability.py."""

from extensions.humanoid.skeleton.head.face_model import FaceModel
from extensions.humanoid.skeleton.head.hair.styles import (
    LAYERED,
    HairStyleFile,
    hair_style_path,
)
from extensions.humanoid.skeleton.head.skin.scan import scan_model
from test_scratch import TestScratch, temporary_path
from std.ffi import external_call
from std.os import getenv
from std.pathlib import Path
from std.testing import assert_equal, assert_true
from std.time import sleep


def _scratch() raises:
    var saved_root = getenv("THREEMOJO_TEST_TMPDIR", "\x00")
    var saved_tmp = getenv("TMPDIR", "\x00")
    try:
        with TestScratch():
            var root = temporary_path("")
            var contents = getenv("THREEMOJO_PORTABILITY_CONTENTS", "fixture")
            Path(temporary_path("same.bin")).write_text(contents)
            with TestScratch():
                assert_equal(temporary_path(""), root)
            assert_equal(Path(temporary_path("same.bin")).read_text(), contents)
            Path(getenv("THREEMOJO_PORTABILITY_MARKER")).write_text(root)
            if getenv("THREEMOJO_PORTABILITY_FAIL") == "yes":
                raise Error("expected direct-process failure")
            var release = getenv("THREEMOJO_PORTABILITY_RELEASE")
            if release != "":
                while not Path(release).exists():
                    sleep(0.01)
                assert_equal(
                    Path(temporary_path("same.bin")).read_text(), contents
                )
            var destination = getenv("THREEMOJO_PORTABILITY_CHDIR")
            if destination != "":
                assert_equal(
                    external_call["chdir", Int32](
                        destination.as_c_string_span().ptr()
                    ),
                    0,
                )
    except error:
        assert_equal(getenv("THREEMOJO_TEST_TMPDIR", "\x00"), saved_root)
        assert_equal(getenv("TMPDIR", "\x00"), saved_tmp)
        raise error
    assert_equal(getenv("THREEMOJO_TEST_TMPDIR", "\x00"), saved_root)
    assert_equal(getenv("TMPDIR", "\x00"), saved_tmp)


def main() raises:
    var action = getenv("THREEMOJO_PORTABILITY_ACTION")
    if action == "face":
        var model = scan_model()
        assert_true(model.vertex_count() > 0)
    elif action == "hair":
        var hair = HairStyleFile(hair_style_path(LAYERED))
        assert_true(hair.count > 0)
    elif action == "explicit":
        var model = FaceModel(getenv("THREEMOJO_PORTABILITY_MODEL"))
        assert_true(model.vertex_count() > 0)
    elif action == "scratch":
        _scratch()
    else:
        raise Error("Unknown portability action")
    print("PORTABILITY PASS")
