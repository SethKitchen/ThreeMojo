#!/usr/bin/env python3
"""Generate and verify independent GLES 3.0 fixtures for ThreeMojo issue 614.

Uses only Python's standard library and the system's libEGL.so.1. Mesa's
software renderer executes the reference shaders. No ThreeMojo or Mojo code
is imported or run. Integer readback uses RGBA32UI, never a float intermediary.
"""
from __future__ import annotations

import argparse
import ctypes as C
import ctypes.util
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import struct
import sys
import time

U32 = (1 << 32) - 1
HERE = Path(__file__).resolve().parent
VERTEX = """#version 300 es
precision highp float;
void main() {
    vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
"""
PREFIX = """#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;
layout(location = 0) out uvec4 result;
"""


class GLES:
    """A headless, software-only GLES context with checked API calls."""

    def __init__(self):
        os.environ["LIBGL_ALWAYS_SOFTWARE"] = "1"
        os.environ["EGL_PLATFORM"] = "surfaceless"
        os.environ["MESA_SHADER_CACHE_DISABLE"] = "true"
        self.egl = C.CDLL(ctypes.util.find_library("EGL") or "libEGL.so.1")
        self.functions = {}
        I, U, P = C.c_int, C.c_uint, C.c_void_p
        self.E("eglGetDisplay", P, [P])
        self.E("eglInitialize", U, [P, C.POINTER(I), C.POINTER(I)])
        self.E("eglChooseConfig", U, [P, C.POINTER(I), C.POINTER(P), I, C.POINTER(I)])
        self.E("eglBindAPI", U, [U])
        self.E("eglCreateContext", P, [P, P, P, C.POINTER(I)])
        self.E("eglCreatePbufferSurface", P, [P, P, C.POINTER(I)])
        self.E("eglMakeCurrent", U, [P, P, P, P])
        self.E("eglDestroyContext", U, [P, P])
        self.E("eglDestroySurface", U, [P, P])
        self.E("eglTerminate", U, [P])
        self.E("eglGetError", U, [])
        self.E("eglGetProcAddress", P, [C.c_char_p])
        self.display = self.egl.eglGetDisplay(None)
        major, minor = I(), I()
        self.require(self.egl.eglInitialize(self.display, C.byref(major), C.byref(minor)), "eglInitialize")
        attrs = (I * 13)(0x3033, 1, 0x3040, 0x40, 0x3024, 8, 0x3023, 8, 0x3022, 8, 0x3021, 8, 0x3038)
        config, count = P(), I()
        self.require(self.egl.eglChooseConfig(self.display, attrs, C.byref(config), 1, C.byref(count)), "eglChooseConfig")
        if count.value != 1:
            raise RuntimeError("No ES3 pbuffer EGL configuration")
        self.require(self.egl.eglBindAPI(0x30A0), "eglBindAPI")
        self.context = self.egl.eglCreateContext(self.display, config, None, (I * 3)(0x3098, 3, 0x3038))
        self.require(self.context, "eglCreateContext")
        self.surface = self.egl.eglCreatePbufferSurface(self.display, config, (I * 5)(0x3057, 1, 0x3056, 1, 0x3038))
        self.require(self.surface, "eglCreatePbufferSurface")
        self.require(self.egl.eglMakeCurrent(self.display, self.surface, self.surface, self.context), "eglMakeCurrent")
        signatures = {
            "glGetString": (C.c_char_p, [U]), "glGetError": (U, []),
            "glCreateShader": (U, [U]), "glShaderSource": (None, [U, I, C.POINTER(C.c_char_p), C.POINTER(I)]),
            "glCompileShader": (None, [U]), "glGetShaderiv": (None, [U, U, C.POINTER(I)]),
            "glGetShaderInfoLog": (None, [U, I, C.POINTER(I), P]), "glDeleteShader": (None, [U]),
            "glCreateProgram": (U, []), "glAttachShader": (None, [U, U]), "glLinkProgram": (None, [U]),
            "glGetProgramiv": (None, [U, U, C.POINTER(I)]), "glGetProgramInfoLog": (None, [U, I, C.POINTER(I), P]),
            "glUseProgram": (None, [U]), "glDeleteProgram": (None, [U]),
            "glGenTextures": (None, [I, C.POINTER(U)]), "glBindTexture": (None, [U, U]),
            "glTexImage2D": (None, [U, I, I, I, I, I, U, U, P]),
            "glTexParameteri": (None, [U, U, I]), "glDeleteTextures": (None, [I, C.POINTER(U)]),
            "glActiveTexture": (None, [U]),
            "glGenFramebuffers": (None, [I, C.POINTER(U)]), "glBindFramebuffer": (None, [U, U]),
            "glFramebufferTexture2D": (None, [U, U, U, U, I]), "glCheckFramebufferStatus": (U, [U]),
            "glDeleteFramebuffers": (None, [I, C.POINTER(U)]),
            "glGenVertexArrays": (None, [I, C.POINTER(U)]), "glBindVertexArray": (None, [U]),
            "glDeleteVertexArrays": (None, [I, C.POINTER(U)]),
            "glViewport": (None, [I, I, I, I]), "glDrawArrays": (None, [U, I, I]),
            "glReadPixels": (None, [I, I, I, I, U, U, P]), "glFinish": (None, []),
            "glGetUniformLocation": (I, [U, C.c_char_p]),
            "glUniform1ui": (None, [I, U]), "glUniform1i": (None, [I, I]),
            "glUniform1f": (None, [I, C.c_float]), "glUniform2f": (None, [I, C.c_float, C.c_float]),
            "glUniform2ui": (None, [I, U, U]), "glUniform3ui": (None, [I, U, U, U]),
            "glUniform4ui": (None, [I, U, U, U, U]),
        }
        for name, (ret, args) in signatures.items():
            address = self.egl.eglGetProcAddress(name.encode())
            if not address:
                raise RuntimeError("Missing GLES entrypoint " + name)
            setattr(self, name, C.CFUNCTYPE(ret, *args)(address))
        self.provenance = {"egl_version": f"{major.value}.{minor.value}"}
        for field, enum in [("vendor", 0x1F00), ("renderer", 0x1F01), ("version", 0x1F02), ("shading_language_version", 0x8B8C)]:
            self.provenance[field] = self.glGetString(enum).decode()
        if not self.provenance["version"].startswith("OpenGL ES 3."):
            raise RuntimeError("Reference requires OpenGL ES 3")
        self.vertex = self.shader(0x8B31, VERTEX)
        self.vao, self.output, self.fbo = U(), U(), U()
        self.glGenVertexArrays(1, C.byref(self.vao)); self.glBindVertexArray(self.vao)
        self.glGenTextures(1, C.byref(self.output)); self.glBindTexture(0x0DE1, self.output)
        # GL_RGBA32UI storage and GL_RGBA_INTEGER/GL_UNSIGNED_INT transfer.
        self.glTexImage2D(0x0DE1, 0, 0x8D70, 1, 1, 0, 0x8D99, 0x1405, None)
        self.glTexParameteri(0x0DE1, 0x2801, 0x2600); self.glTexParameteri(0x0DE1, 0x2800, 0x2600)
        self.glGenFramebuffers(1, C.byref(self.fbo)); self.glBindFramebuffer(0x8D40, self.fbo)
        self.glFramebufferTexture2D(0x8D40, 0x8CE0, 0x0DE1, self.output, 0)
        if self.glCheckFramebufferStatus(0x8D40) != 0x8CD5:
            raise RuntimeError("RGBA32UI framebuffer is incomplete")
        self.glViewport(0, 0, 1, 1)
        self.check("initialize GLES")

    def E(self, name, ret, args):
        function = getattr(self.egl, name); function.restype = ret; function.argtypes = args

    def require(self, ok, action):
        if not ok:
            raise RuntimeError(f"{action}: EGL error 0x{self.egl.eglGetError():04x}")

    def check(self, action):
        error = self.glGetError()
        if error:
            raise RuntimeError(f"{action}: GL error 0x{error:04x}")

    def shader(self, kind, source):
        shader = self.glCreateShader(kind)
        encoded = C.c_char_p(source.encode("utf-8"))
        self.glShaderSource(shader, 1, C.byref(encoded), None); self.glCompileShader(shader)
        ok = C.c_int(); self.glGetShaderiv(shader, 0x8B81, C.byref(ok))
        if not ok.value:
            message = C.create_string_buffer(16384)
            self.glGetShaderInfoLog(shader, len(message), None, message)
            raise RuntimeError(message.value.decode() + "\n" + source)
        return shader

    def render(self, case):
        fragment = self.shader(0x8B30, case["fragment_source"])
        program = self.glCreateProgram()
        self.glAttachShader(program, self.vertex); self.glAttachShader(program, fragment); self.glLinkProgram(program)
        ok = C.c_int(); self.glGetProgramiv(program, 0x8B82, C.byref(ok))
        if not ok.value:
            message = C.create_string_buffer(16384); self.glGetProgramInfoLog(program, len(message), None, message)
            raise RuntimeError(message.value.decode())
        self.glUseProgram(program)
        for name, uniform in case["uniforms"].items():
            loc = self.glGetUniformLocation(program, name.encode())
            if loc == -1:
                continue  # GLSL optimizes inactive inputs away.
            kind, value = uniform["type"], uniform["value"]
            if kind == "uint": self.glUniform1ui(loc, value)
            elif kind in ("int", "bool", "sampler2D"): self.glUniform1i(loc, value)
            elif kind == "float": self.glUniform1f(loc, value)
            elif kind == "vec2": self.glUniform2f(loc, *value)
            elif kind == "uvec2": self.glUniform2ui(loc, *value)
            elif kind == "uvec3": self.glUniform3ui(loc, *value)
            elif kind == "uvec4": self.glUniform4ui(loc, *value)
            else: raise ValueError(kind)
        texture = None
        if "texture" in case:
            texture = self.texture(case["texture"])
        self.glDrawArrays(0x0004, 0, 3); self.glFinish()
        output = (C.c_uint * 4)()
        self.glReadPixels(0, 0, 1, 1, 0x8D99, 0x1405, output)
        self.check(case["id"])
        words = list(output)
        self.glDeleteProgram(program); self.glDeleteShader(fragment)
        if texture is not None: self.glDeleteTextures(1, C.byref(texture))
        return words

    def texture(self, description):
        tex = C.c_uint(); self.glGenTextures(1, C.byref(tex)); self.glActiveTexture(0x84C0); self.glBindTexture(0x0DE1, tex)
        for level in range(5):
            width, height = max(1, 16 >> level), max(1, 8 >> level)
            pixels = [component for y in range(height) for x in range(width) for component in texel(level, x, y)]
            data = (C.c_float * len(pixels))(*pixels)
            # Binary fractions are exact in RGBA16F. GLES 3.0 supports filtering it.
            self.glTexImage2D(0x0DE1, level, 0x881A, width, height, 0, 0x1908, 0x1406, data)
        filters = {"nearest_mipmap_nearest": 0x2700, "nearest_mipmap_linear": 0x2702, "linear_mipmap_linear": 0x2703}
        wraps = {"clamp": 0x812F, "repeat": 0x2901, "mirror": 0x8370}
        self.glTexParameteri(0x0DE1, 0x2801, filters[description["min_filter"]])
        self.glTexParameteri(0x0DE1, 0x2800, 0x2601 if description["min_filter"].startswith("linear") else 0x2600)
        self.glTexParameteri(0x0DE1, 0x2802, wraps[description["wrap_s"]])
        self.glTexParameteri(0x0DE1, 0x2803, wraps[description["wrap_t"]])
        self.glTexParameteri(0x0DE1, 0x813D, 4)
        self.check("upload texture")
        return tex

    def close(self):
        self.glDeleteShader(self.vertex)
        self.glDeleteFramebuffers(1, C.byref(self.fbo)); self.glDeleteTextures(1, C.byref(self.output))
        self.glDeleteVertexArrays(1, C.byref(self.vao))
        self.egl.eglMakeCurrent(self.display, None, None, None)
        self.egl.eglDestroySurface(self.display, self.surface); self.egl.eglDestroyContext(self.display, self.context)
        self.egl.eglTerminate(self.display)


def uniform(kind, value):
    return {"type": kind, "value": value}


def uint_case(name, body, expected, *, declarations="", uniforms=None, category="uint"):
    return {"id": name, "category": category, "fragment_source": PREFIX + declarations + "\nvoid main() {\n" + body + "\n}\n",
            "uniforms": uniforms or {}, "expected": [x & U32 for x in expected], "comparison": "exact_uint32"}


def uint_cases():
    cases = []
    add = cases.append
    add(uint_case("uint_literal_boundaries", "result = uvec4(16777215u, 16777216u, 16777217u, 4294967295u);", [16777215,16777216,16777217,U32]))
    add(uint_case("uint_literal_sign_boundary", "result = uvec4(2147483647u, 2147483648u, 2147483649u, 0xffffffffu);", [2147483647,2147483648,2147483649,U32]))
    add(uint_case("uint_const_wrap", "result = uvec4(4294967295u + 1u, 0u - 1u, 0x80000000u * 2u, -1u);", [0,U32,0,U32]))
    add(uint_case("uint_constructors", "result = uvec4(uint(-1), uint(true), uint(false), uint(16777216.0));", [U32,1,0,16777216]))
    add(uint_case("uint_join_uvec2_uvec3", "uvec2 a = uvec2(16777217u, 2147483649u); uvec3 b = uvec3(a, 4294967295u); result = uvec4(b, 2147483648u);", [16777217,2147483649,U32,2147483648]))
    add(uint_case("uint_constructor_splat", "uvec4 a = uvec4(16777217u); result = a;", [16777217]*4))
    add(uint_case("uint_swizzle_join", "uvec4 a = uvec4(16777217u, 2147483648u, 2147483649u, 4294967295u); result = uvec4(a.wz, a.xy);", [U32,2147483649,16777217,2147483648]))
    add(uint_case("uint_swizzle_assignment", "uvec4 a = uvec4(16777217u, 2147483648u, 2147483649u, 4294967295u); a.xy = a.wz; result = a;", [U32,2147483649,2147483649,U32]))
    decl = "uniform uint uA; uniform uint uB; uniform uvec4 uV; uniform uvec4 uW; uniform bool uFlag; uniform int uIndex;\n"
    a,b = U32,16777217
    v = [0,16777217,2147483648,U32]; w=[1,16777216,2147483649,U32-1]
    inputs={"uA":uniform("uint",a),"uB":uniform("uint",b),"uV":uniform("uvec4",v),"uW":uniform("uvec4",w),"uFlag":uniform("bool",1),"uIndex":uniform("int",2)}
    def runtime(name, body, expect, changes=None, extra=""):
        add(uint_case(name,body,expect,declarations=decl+extra,uniforms=inputs | (changes or {})))
    runtime("uint_uniform_exact", "result = uV;", v)
    runtime("uint_uniform_wrap", "result = uvec4(uA + 1u, 0u - uA, uA * uB, -uA);", [0,1,-b,1])
    runtime("uint_uniform_div_rem", "result = uvec4(uA / uB, uA % uB, uA / 2147483648u, uA % 2147483648u);", [a//b,a%b,1,2147483647])
    runtime("uint_uniform_vector_arithmetic", "result = (uV + uW) * uvec4(1u, 3u, 2u, 4u);", [(x+y)*m for x,y,m in zip(v,w,[1,3,2,4])])
    runtime("uint_uniform_vector_div_rem", "result = (uV / uvec4(1u, 3u, 2u, 65537u)) + (uV % uvec4(1u, 3u, 2u, 65537u));", [x//d+x%d for x,d in zip(v,[1,3,2,65537])])
    runtime("uint_uniform_bitwise", "result = uvec4(uA & uB, uA | uB, uA ^ uB, ~uB);", [a&b,a|b,a^b,~b])
    runtime("uint_uniform_shift_widths", "result = uvec4(uA >> 0u, uA >> 1u, uA >> 16u, uA >> 31u);", [a,a>>1,a>>16,a>>31])
    runtime("uint_uniform_shift_left", "result = uvec4(uB << 0, uB << 1, uB << 16, uB << 31);", [b,b<<1,b<<16,b<<31])
    runtime("uint_vector_shift", "result = uV >> uvec4(0u, 1u, 16u, 31u);", [0,16777217>>1,2147483648>>16,1])
    runtime("uint_vector_shift_scalar", "result = uV << 1u;", [x<<1 for x in v])
    runtime("uint_scalar_minmaxclamp", "result = uvec4(min(uA, uB), max(uA, uB), clamp(uA, 16777216u, 2147483649u), clamp(uB, 2147483648u, uA));", [b,a,2147483649,2147483648])
    runtime("uint_vector_min", "result = min(uV, uW);", list(map(min,v,w)))
    runtime("uint_vector_max", "result = max(uV, uW);", list(map(max,v,w)))
    runtime("uint_vector_min_scalar", "result = min(uV, 2147483648u);", [min(x,2147483648) for x in v])
    runtime("uint_vector_max_scalar", "result = max(uV, 16777217u);", [max(x,16777217) for x in v])
    runtime("uint_vector_clamp_scalar", "result = clamp(uV, 16777216u, 2147483649u);", [min(max(x,16777216),2147483649) for x in v])
    low=[0,16777216,2147483647,2147483648]; high=[1,16777218,2147483649,U32-1]
    runtime("uint_vector_clamp_vector", "result = clamp(uV, uvec4(0u, 16777216u, 2147483647u, 2147483648u), uvec4(1u, 16777218u, 2147483649u, 4294967294u));", [min(max(x,l),h) for x,l,h in zip(v,low,high)])
    runtime("uint_scalar_comparisons", "result = uvec4(uint(uA > uB), uint(uB < uA), uint(uA == 4294967295u), uint(uB != 16777216u));", [1,1,1,1])
    runtime("uint_scalar_equal_order", "result = uvec4(uint(uA <= uB), uint(uA >= uB), uint(uB == 16777216u), uint(uA != uA));", [0,1,0,0])
    for fn, op in [("lessThan",lambda x,y:x<y),("lessThanEqual",lambda x,y:x<=y),("greaterThan",lambda x,y:x>y),("greaterThanEqual",lambda x,y:x>=y),("equal",lambda x,y:x==y),("notEqual",lambda x,y:x!=y)]:
        runtime("uint_vector_"+fn, "result = uvec4("+fn+"(uV, uW));", [int(op(x,y)) for x,y in zip(v,w)])
    runtime("uint_vector_equal_identity", "result = uvec4(equal(uV, uV));", [1]*4)
    for flag in (0,1):
        runtime(f"uint_if_join_{flag}", "uvec4 x; if (uFlag) { x = uV; } else { x = uW; } result = x;", v if flag else w, {"uFlag":uniform("bool",flag)})
        runtime(f"uint_ternary_select_{flag}", "result = uFlag ? uV : uW;", v if flag else w, {"uFlag":uniform("bool",flag)})
    runtime("uint_runtime_swizzle", "uvec4 x = uV; x.zw = uW.yx; result = x.wzyx;", [1,16777216,16777217,0])
    runtime("uint_runtime_vector_index", "result = uvec4(uV[uIndex], uV[3], uW[uIndex - 1], uW[0]);", [2147483648,U32,16777216,1])
    runtime("uint_runtime_array_read", "uint a[4] = uint[4](uV.x, uV.y, uV.z, uV.w); result = uvec4(a[uIndex], a[1], a[3], a[0]);", [2147483648,16777217,U32,0])
    runtime("uint_runtime_array_write", "uint a[4] = uint[4](uV.x, uV.y, uV.z, uV.w); a[uIndex] = uB; result = uvec4(a[0], a[1], a[2], a[3]);", [0,16777217,16777217,U32])
    runtime("uint_runtime_uvec_array", "uvec4 a[2] = uvec4[2](uV, uW); result = a[uIndex - 1];", w, {"uIndex":uniform("int",2)})
    runtime("uint_function_return", "result = pick(uV, uW, uFlag);", v, extra="uvec4 pick(uvec4 a, uvec4 b, bool flag) { if (flag) { return a; } return b; }\n")
    runtime("uint_function_inout_out", "uint a = uA; uint b = 0u; adjust(a, uB, b); result = uvec4(a, b, uA, uB);", [a+b,a-b,a,b], extra="void adjust(inout uint a, uint step, out uint b) { b = a - step; a += step; }\n")
    runtime("uint_struct_field_join", "Pair p = Pair(uA, uV); result = uvec4(p.a, p.b.yzw);", [a,v[1],v[2],v[3]], extra="struct Pair { uint a; uvec4 b; };\n")
    # Keep the increment separate: constructor argument order is not specified.
    runtime("uint_arithmetic_compound", "uint a = uA; a += 2u; a -= 3u; a *= 3u; a /= 2u; uint before = a; ++a; result = uvec4(before, a, 0u, 0u);", [2147483645,2147483646,0,0])
    runtime("uint_bitwise_compound", "uint a = uA; a &= uB; a |= 0x80000000u; a ^= 1u; a >>= 1; a <<= 1; a %= 65537u; result = uvec4(a, uA, uB, 0u);", [(((((a&b)|0x80000000)^1)>>1)<<1)%65537,a,b,0])
    runtime("uint_fragment_runtime_path", "uint pixel = uint(gl_FragCoord.x); result = uV + uvec4(pixel);", v)
    add(uint_case("uint_uniform_uvec2", "result = uvec4(uPair, uPair.yx);", [16777217, U32, U32, 16777217], declarations="uniform uvec2 uPair;\n", uniforms={"uPair":uniform("uvec2", [16777217,U32])}))
    add(uint_case("uint_uniform_uvec3", "result = uvec4(uTriple, uTriple[1]);", [16777217,2147483649,U32,2147483649], declarations="uniform uvec3 uTriple;\n", uniforms={"uTriple":uniform("uvec3",[16777217,2147483649,U32])}))
    add(uint_case("uint_const_minmaxclamp", "result = uvec4(min(4294967295u, 16777217u), max(2147483647u, 2147483648u), clamp(4294967295u, 16777216u, 2147483649u), clamp(16777217u, 2147483648u, 4294967295u));", [16777217,2147483648,2147483649,2147483648]))
    add(uint_case("uint_const_div_rem_shift", "result = uvec4(4294967295u / 16777217u, 4294967295u % 16777217u, 4294967295u >> 31u, 16777217u << 31u);", [255,16776960,1,2147483648]))
    add(uint_case("uint_int_uint_const_roundtrip", "result = uvec4(uint(int(0x80000001u)), uint(int(0xffffffffu)), uint(int(0x80000000u)), uint(int(0x7fffffffu)));", [0x80000001,U32,0x80000000,0x7fffffff]))
    signed_values=[0x80000001,U32,0x80000000,0x7fffffff]
    signed_inputs={"uV":uniform("uvec4",signed_values)}
    runtime("uint_ivec_variable_roundtrip", "ivec4 a = ivec4(uV); ivec4 b = a; result = uvec4(b);", signed_values, signed_inputs)
    runtime("uint_ivec_swizzle_roundtrip", "ivec4 a = ivec4(uV); ivec2 b = a.wz; ivec2 c = a.xy; result = uvec4(ivec4(b,c));", [signed_values[i] for i in (3,2,0,1)], signed_inputs)
    runtime("uint_int_scalar_variable_roundtrip", "int a = int(uV.x); int b = a; result = uvec4(uint(b), uint(int(uV.y)), uint(int(uV.z)), uint(int(uV.w)));", signed_values, signed_inputs)
    runtime("uint_int_function_roundtrip", "result = uvec4(uint(signed_pass(int(uV.x))), uint(signed_pass(int(uV.y))), uint(signed_pass(int(uV.z))), uint(signed_pass(int(uV.w))));", signed_values, signed_inputs, extra="int signed_pass(int x) { int y = x; return y; }\n")
    runtime("uint_ivec_function_roundtrip", "result = uvec4(signed_pass(ivec4(uV)));", signed_values, signed_inputs, extra="ivec4 signed_pass(ivec4 x) { ivec4 y = x; return y; }\n")
    runtime("uint_ivec_inout_roundtrip", "ivec4 a = ivec4(uV); signed_pass(a); result = uvec4(a);", list(reversed(signed_values)), signed_inputs, extra="void signed_pass(inout ivec4 x) { x = x.wzyx; }\n")
    runtime("uint_int_signed_comparison", "ivec4 a = ivec4(uV); result = uvec4(lessThan(a, ivec4(0)));", [1,1,1,0], signed_inputs)
    runtime("uint_bool_high_bit", "result = uvec4(uint(bool(uV.x)), uint(bool(uV.y)), uint(bool(uV.z)), uint(bool(uV.w)));", [1,1,1,1], signed_inputs)
    runtime("uint_bvec_high_bit", "result = uvec4(bvec4(uV));", [1,1,1,1], signed_inputs)
    bit_sets = ([0,1,0x80000000,0x7f800000], [0x7fc00001,0xff800000,U32,0x007fffff])
    for index,values in enumerate(bit_sets):
        update={"uV":uniform("uvec4",values)}
        prefix=f"uint_payload_{index}"
        literal=", ".join(f"0x{x:08x}u" for x in values)
        add(uint_case(prefix+"_constant", "result = uvec4("+literal+");", values))
        runtime(prefix+"_uniform", "result = uV;", values, update)
        runtime(prefix+"_variable", "uvec4 a = uV; uvec4 b = a; result = b;", values, update)
        runtime(prefix+"_swizzle", "uvec2 a = uV.wz; uvec2 b = uV.xy; result = uvec4(a,b);", [values[i] for i in (3,2,0,1)], update)
        runtime(prefix+"_function", "result = pass_value(uV);", values, update, extra="uvec4 pass_value(uvec4 x) { uvec4 local = x; return local; }\n")
        runtime(prefix+"_inout", "uvec4 a = uV; pass_value(a); result = a;", [x+1 for x in values], update, extra="void pass_value(inout uvec4 x) { x += uvec4(1u); }\n")
        runtime(prefix+"_array", "uint a[4] = uint[4](uV.x,uV.y,uV.z,uV.w); result = uvec4(a[0],a[1],a[uIndex],a[3]);", values, update)
        runtime(prefix+"_bool", "result = uvec4(bvec4(uV));", [int(x!=0) for x in values], update)
        runtime(prefix+"_minimum", "result = min(uV, 0x80000000u);", [min(x,0x80000000) for x in values], update)
        runtime(prefix+"_ivec_roundtrip", "ivec4 a = ivec4(uV); result = uvec4(a);", values, update)
        for flag in (0,1):
            runtime(prefix+f"_select_{flag}", "result = uFlag ? uV : uV.wzyx;", values if flag else list(reversed(values)), update | {"uFlag":uniform("bool",flag)})
    return cases


def loop_cases():
    cases=[]
    for count in (63,64,65,128,256):
        for kind in ("while","do"):
            body="uint i = 0u; uint total = 0u;\n"
            inner="i += 1u; total += i;"
            body += f"while (i < {count}u) {{ {inner} }}" if kind=="while" else f"do {{ {inner} }} while (i < {count}u);"
            body += "\nresult = uvec4(i, total, 0u, 1u);"
            cases.append(uint_case(f"{kind}_finite_{count}",body,[count,count*(count+1)//2,0,1],category="loops"))
            declaration="bool condition(uint i, inout uint calls) { calls += 1u; return i < "+str(count)+"u; }\n"
            body="uint i = 0u; uint total = 0u; uint calls = 0u;\n"
            body += "while (condition(i, calls)) { "+inner+" }" if kind=="while" else "do { "+inner+" } while (condition(i, calls));"
            body += "\nresult = uvec4(i, total, calls, 1u);"
            cases.append(uint_case(f"{kind}_condition_effects_{count}",body,[count,count*(count+1)//2,count+(kind=="while"),1],declarations=declaration,category="loops"))
            declaration="uniform uint gain; uniform uint limit;\n"
            body="uint i = 0u; uint total = 4294967290u;\n"
            inner="i += 1u; total += gain;"
            body += "while (i < limit) { "+inner+" }" if kind=="while" else "do { "+inner+" } while (i < limit);"
            body += "\nresult = uvec4(i, total, gain, limit);"
            cases.append(uint_case(f"{kind}_runtime_bound_{count}",body,[count,U32-5+count*16777217,16777217,count],declarations=declaration,uniforms={"gain":uniform("uint",16777217),"limit":uniform("uint",count)},category="loops"))
    for kind in ("while","do"):
        head="uint i = 0u; uint total = 0u; uint calls = 0u;\n"
        loop="i += 1u; if (i == 65u) { break; } if ((i % 2u) == 0u) { continue; } total += i;"
        body = head + ("while (condition(i,calls)) { "+loop+" }" if kind=="while" else "do { "+loop+" } while (condition(i,calls));")
        body += "result = uvec4(i,total,calls,1u);"
        cases.append(uint_case(f"{kind}_break_continue",body,[65,sum(range(1,65,2)),65 if kind=="while" else 64,1],declarations="bool condition(uint i, inout uint calls) { calls += 1u; return i < 256u; }\n",category="loops"))
    cases.append(uint_case("while_zero_body","uint i = 0u; uint calls = 0u; while (condition(i,calls)) { i += 1u; } result = uvec4(i,calls,0u,1u);",[0,1,0,1],declarations="bool condition(uint i, inout uint calls) { calls += 1u; return false; }\n",category="loops"))
    cases.append(uint_case("do_minimum_one_body","uint i = 0u; uint calls = 0u; do { i += 1u; } while (condition(i,calls)); result = uvec4(i,calls,0u,1u);",[1,1,0,1],declarations="bool condition(uint i, inout uint calls) { calls += 1u; return false; }\n",category="loops"))
    cases.append(uint_case("while_nested_16_by_16","uint outer = 0u; uint total = 0u; while (outer < 16u) { uint inner = 0u; while (inner < 16u) { inner += 1u; total += 1u; } outer += 1u; } result = uvec4(outer,total,0u,1u);",[16,256,0,1],category="loops"))
    return cases


def texel(level, x, y):
    return [(level+1)/8, x/16, y/8, 1.0]


def wrap_index(index, size, mode):
    if mode=="clamp": return min(max(index,0),size-1)
    if mode=="repeat": return index % size
    at = index % (2*size)
    return at if at < size else 2*size-1-at


def sample_level(level, uv, texture, linear):
    width,height=max(1,16>>level),max(1,8>>level)
    if not linear:
        x=wrap_index(math.floor(uv[0]*width),width,texture["wrap_s"])
        y=wrap_index(math.floor(uv[1]*height),height,texture["wrap_t"])
        return texel(level,x,y)
    atx,aty=uv[0]*width-0.5,uv[1]*height-0.5
    x,y=math.floor(atx),math.floor(aty); fx,fy=atx-x,aty-y
    value=[0.0]*4
    for dx,wx in ((0,1-fx),(1,fx)):
        for dy,wy in ((0,1-fy),(1,fy)):
            color=texel(level,wrap_index(x+dx,width,texture["wrap_s"]),wrap_index(y+dy,height,texture["wrap_t"]))
            for lane in range(4): value[lane]+=wx*wy*color[lane]
    return value


def texture_expected(uv, dx, dy, texture):
    rho=max(math.hypot(dx[0]*16,dx[1]*8),math.hypot(dy[0]*16,dy[1]*8))
    lod=max(0.0,min(4.0,math.log2(rho))) if rho>0 else 0.0
    filtering=texture["min_filter"]
    if filtering=="nearest_mipmap_nearest":
        return sample_level(min(4,math.floor(lod+0.5)),uv,texture,False),lod
    low=math.floor(lod); high=min(4,low+1); fraction=lod-low
    a=sample_level(low,uv,texture,filtering=="linear_mipmap_linear")
    b=sample_level(high,uv,texture,filtering=="linear_mipmap_linear")
    return [x*(1-fraction)+y*fraction for x,y in zip(a,b)],lod


def texture_cases():
    cases=[]
    declaration="uniform sampler2D source; uniform vec2 uv; uniform vec2 dx; uniform vec2 dy;\n"
    def add(name, uv, dx, dy, filtering="nearest_mipmap_nearest", wrap="clamp", body=None, eval_uv=None, eval_dx=None, eval_dy=None):
        texture={"internal_format":"RGBA16F","base_width":16,"base_height":8,"levels":5,"texel_formula":"[(level+1)/8, x/16, y/8, 1]","min_filter":filtering,"mag_filter":"linear" if filtering.startswith("linear") else "nearest","wrap_s":wrap,"wrap_t":wrap}
        # GLSL inputs are floats. Record the actual round-trippable values.
        f32=lambda x:struct.unpack("<f",struct.pack("<f",x))[0]
        uv=list(map(f32,uv));dx=list(map(f32,dx));dy=list(map(f32,dy))
        want,lod=texture_expected(eval_uv or uv,eval_dx or dx,eval_dy or dy,texture)
        cases.append({"id":name,"category":"textureGrad","fragment_source":PREFIX+declaration+"void main() { "+(body or "result = floatBitsToUint(textureGrad(source, uv, dx, dy));")+" }\n", "uniforms":{"source":uniform("sampler2D",0),"uv":uniform("vec2",uv),"dx":uniform("vec2",dx),"dy":uniform("vec2",dy)},"texture":texture,"expected":want,"analytic_lod":lod,"comparison":"float32_absolute","absolute_tolerance":2e-6})
    uv=(0.34375,0.6875)
    for level in range(5): add(f"textureGrad_mip_{level}",uv,(2**level/16,0),(0,2**level/8))
    add("textureGrad_zero",uv,(0,0),(0,0))
    add("textureGrad_magnification",uv,(1/64,0),(0,1/32))
    add("textureGrad_minification_clamp",uv,(8,0),(0,8))
    add("textureGrad_dx_dominates",uv,(1/2,0),(0,1/8))
    add("textureGrad_dy_dominates",uv,(1/16,0),(0,1))
    add("textureGrad_rectangular_x",uv,(1/8,0),(0,0))
    add("textureGrad_rectangular_y",uv,(0,1/8),(0,0))
    add("textureGrad_negative_gradients",uv,(-1/4,0),(0,-1/2))
    add("textureGrad_swapped_derivatives",uv,(0,1/2),(1/4,0))
    add("textureGrad_diagonal",uv,(0.15,0.4),(0,0)) # Texel-space vector (2.4,3.2), length 4.
    add("textureGrad_nearest_below_mip_switch",uv,(2**1.25/16,0),(0,0))
    add("textureGrad_nearest_above_mip_switch",uv,(2**1.75/16,0),(0,0))
    add("textureGrad_trilinear_half",uv,(2**1.5/16,0),(0,0),"nearest_mipmap_linear")
    add("textureGrad_bilinear",(0.375,0.625),(1/16,0),(0,1/8),"linear_mipmap_linear")
    add("textureGrad_trilinear_bilinear",(0.375,0.625),(2**1.5/16,0),(0,0),"linear_mipmap_linear")
    add("textureGrad_uv_lower_left",(0.03125,0.0625),(0,0),(0,0))
    add("textureGrad_uv_upper_right",(0.96875,0.9375),(0,0),(0,0))
    add("textureGrad_uv_clamp",(-0.25,1.25),(0,0),(0,0))
    add("textureGrad_uv_repeat",(1.34375,-0.3125),(0,0),(0,0),wrap="repeat")
    add("textureGrad_uv_mirror",(1.34375,-0.3125),(0,0),(0,0),wrap="mirror")
    add("textureGrad_uv_transform_fixed_grad",(0.125,0.25),(1/16,0),(0,1/8),body="result = floatBitsToUint(textureGrad(source, uv * 2.0 + vec2(0.125,0.125), dx, dy));",eval_uv=(0.375,0.625))
    add("textureGrad_uv_transform_scaled_grad",(0.125,0.25),(1/16,0),(0,1/8),body="result = floatBitsToUint(textureGrad(source, uv * 2.0 + vec2(0.125,0.125), dx * 2.0, dy * 2.0));",eval_uv=(0.375,0.625),eval_dx=(1/8,0),eval_dy=(0,1/4))
    # Constants prove the parser path; uniforms above prove runtime inputs.
    add("textureGrad_constant_arguments",uv,(1/4,0),(0,1/2),body="result = floatBitsToUint(textureGrad(source, vec2(0.34375,0.6875), vec2(0.25,0.0), vec2(0.0,0.5)));" )
    return cases


def compare(case, words):
    if case["comparison"]=="exact_uint32":
        actual=words
        passed=actual==case["expected"]
    else:
        actual=list(struct.unpack("<4f",struct.pack("<4I",*words)))
        passed=all(math.isfinite(x) and abs(x-y)<=case["absolute_tolerance"] for x,y in zip(actual,case["expected"]))
    return passed,actual


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,default=HERE/"fixtures")
    parser.add_argument("--verify",type=Path,help="Verify a recorded fixtures.json without rewriting it")
    parser.add_argument("--case", help="Run only the named fixture")
    args=parser.parse_args()
    if args.case and not args.verify:
        parser.error("--case requires --verify; generation always writes the full catalog")
    start=time.monotonic()
    if args.verify:
        previous=json.loads(args.verify.read_text(encoding="utf-8"));cases=previous["cases"]
    else:
        cases=uint_cases()+loop_cases()+texture_cases()
    if args.case:
        cases = [case for case in cases if case["id"] == args.case]
        if not cases: parser.error("Unknown fixture: " + args.case)
    gl=GLES(); failures=[]; records=[]
    print(json.dumps(gl.provenance,sort_keys=True),flush=True)
    try:
        for case in cases:
            case_start = time.monotonic()
            words=gl.render(case); passed,actual=compare(case,words)
            record=dict(case,observed=actual,readback_uint32=words,readback_little_endian_hex=struct.pack("<4I",*words).hex(),passed=passed,elapsed_seconds=time.monotonic()-case_start)
            records.append(record)
            if not passed: failures.append({"id":case["id"],"expected":case["expected"],"actual":actual})
            print(("PASS " if passed else "FAIL ")+case["id"]+" "+json.dumps(actual),flush=True)
    finally:
        gl.close()
    elapsed=time.monotonic()-start
    counts={category:sum(c["category"]==category for c in cases) for category in ("uint","loops","textureGrad")}
    report={"schema":"threemojo-glsl614-gles3-reference-v1","generated_at_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"reference":{"method":"Python ctypes, surfaceless EGL, GLES shaders executed by Mesa software rasterizer","api_shader_version":"#version 300 es","readback":"GL_RGBA32UI framebuffer; GL_RGBA_INTEGER / GL_UNSIGNED_INT; float samples encoded with floatBitsToUint","driver":gl.provenance,"python":sys.version,"platform":platform.platform(),"generator_sha256":sha256(Path(__file__)),"source_checkout_commit":"e53600eb4b0551bbe9900ea0e8b7151e49553a2d","source_checkout_role":"Read-only context only. No ThreeMojo implementation imports or executions.","issue":"https://github.com/SethKitchen/ThreeMojo/issues/614","specification":"https://registry.khronos.org/OpenGL/specs/es/3.0/GLSL_ES_Specification_3.00.pdf","texture_reference":"https://registry.khronos.org/OpenGL-Refpages/es3.0/html/textureGrad.xhtml"},"summary":{"count":len(records),"counts":counts,"passed":len(records)-len(failures),"failed":len(failures),"elapsed_seconds":elapsed},"vertex_source":VERTEX,"cases":records}
    if not args.verify:
        args.output.mkdir(parents=True,exist_ok=True)
        shaders=args.output/"shaders";shaders.mkdir(exist_ok=True)
        (shaders/"fullscreen.vert").write_text(VERTEX,encoding="utf-8")
        for case in records: (shaders/(case["id"]+".frag")).write_text(case["fragment_source"],encoding="utf-8")
        (args.output/"fixtures.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n",encoding="utf-8")
        with (args.output/"expected_uint32.tsv").open("w",encoding="utf-8") as f:
            f.write("id\tr\tg\tb\ta\tlittle_endian_hex\n")
            for case in records:
                if case["comparison"]=="exact_uint32": f.write(case["id"]+"\t"+"\t".join(map(str,case["expected"]))+"\t"+struct.pack("<4I",*case["expected"]).hex()+"\n")
        with (args.output/"expected_float32.tsv").open("w",encoding="utf-8") as f:
            f.write("id\tr\tg\tb\ta\tabs_tolerance\tanalytic_lod\n")
            for case in records:
                if case["comparison"]=="float32_absolute": f.write(case["id"]+"\t"+"\t".join(map(str,case["expected"]))+"\t"+str(case["absolute_tolerance"])+"\t"+str(case["analytic_lod"])+"\n")
    print(json.dumps(report["summary"],sort_keys=True),flush=True)
    if failures:
        print(json.dumps(failures,indent=2),file=sys.stderr)
        return 1
    return 0


if __name__=="__main__":
    raise SystemExit(main())
