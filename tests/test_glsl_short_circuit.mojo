# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact GLES3 controls for unsigned short-circuit and conditional effects."""

from materials.glsl import compile_shader_material
from tests.test_glsl import VERTEX, run
from std.testing import TestSuite, assert_equal, assert_raises


def test_short_and_false() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;bool b=false&&bump(n);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(0u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_or_true() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;bool b=true||bump(n);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(0u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_and_true() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;bool b=true&&bump(n);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(1u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_or_false() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;bool b=false||bump(n);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(1u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_xor_eager() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;bool b=false^^bump(n);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(1u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_runtime_and_0() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0xffffffffu;bool b=flag&&bump(n);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(4294967295u)))));}\n"
        ),
    )
    program.set_uniform("flag", Float32(0))
    assert_equal(run(program)[0], Float32(1))


def test_short_runtime_or_0() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0xffffffffu;bool b=flag||bump(n);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(0u)))));}\n"
        ),
    )
    program.set_uniform("flag", Float32(0))
    assert_equal(run(program)[0], Float32(1))


def test_short_runtime_ternary_0() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;uint b=flag?add(n,1u):add(n,2u);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(2u)))));}\n"
        ),
    )
    program.set_uniform("flag", Float32(0))
    assert_equal(run(program)[0], Float32(1))


def test_short_runtime_and_1() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0xffffffffu;bool b=flag&&bump(n);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(0u)))));}\n"
        ),
    )
    program.set_uniform("flag", Float32(1))
    assert_equal(run(program)[0], Float32(1))


def test_short_runtime_or_1() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0xffffffffu;bool b=flag||bump(n);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(4294967295u)))));}\n"
        ),
    )
    program.set_uniform("flag", Float32(1))
    assert_equal(run(program)[0], Float32(1))


def test_short_runtime_ternary_1() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;uint b=flag?add(n,1u):add(n,2u);"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(1u)))));}\n"
        ),
    )
    program.set_uniform("flag", Float32(1))
    assert_equal(run(program)[0], Float32(1))


def test_short_while_63() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;while(n<63u&&bump(n)){}"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(63u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_do_63() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;do{}while(n<63u&&bump(n));"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(63u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_while_64() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;while(n<64u&&bump(n)){}"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(64u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_do_64() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;do{}while(n<64u&&bump(n));"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(64u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_while_65() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;while(n<65u&&bump(n)){}"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(65u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_do_65() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;do{}while(n<65u&&bump(n));"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(65u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_while_256() raises:
    var program = compile_shader_material(
        VERTEX,
        (
            "uniform bool flag;\nbool bump(inout uint n){n++;return"
            " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
            " main(){ uvec4 result;uint n=0u;while(n<256u&&bump(n)){}"
            " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(256u)))));}\n"
        ),
    )
    assert_equal(run(program)[0], Float32(1))


def test_short_do_257_bodies_is_explicit_exhaustion() raises:
    # The condition increments n after each body, so n=256 takes 257 bodies.
    with assert_raises(contains="must provably stop within 256"):
        _ = compile_shader_material(
            VERTEX,
            (
                "uniform bool flag;\nbool bump(inout uint n){n++;return"
                " true;}\nuint add(inout uint n,uint v){n+=v;return n;}\nvoid"
                " main(){ uvec4 result;uint n=0u;do{}while(n<256u&&bump(n));"
                " result=uvec4(n);gl_FragColor=vec4(float(all(equal(result,uvec4(256u)))));}\n"
            ),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
