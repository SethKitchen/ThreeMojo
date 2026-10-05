// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Optional x86-64/AVX reference experiment; not a Mojo runtime dependency.
#include <cstdint>
#include <cstring>
#include <cmath>
#include "ImfDwaCompressorSimd.h"
static_assert(OPENEXR_VERSION_MAJOR==3 && OPENEXR_VERSION_MINOR==1 && OPENEXR_VERSION_PATCH==5, "Pin OpenEXR 3.1.5");
extern "C" void compare_dct(const float *input, float *scalar, float *sse, float *avx) {
    alignas(32) float a[64],b[64],c[64];
    std::memcpy(a,input,sizeof a); std::memcpy(b,input,sizeof b); std::memcpy(c,input,sizeof c);
    Imf_3_1::dctInverse8x8_scalar<0>(a);
    Imf_3_1::dctInverse8x8_sse2<0>(b);
    Imf_3_1::dctInverse8x8_avx<0>(c);
    std::memcpy(scalar,a,sizeof a);std::memcpy(sse,b,sizeof b);std::memcpy(avx,c,sizeof c);
}
