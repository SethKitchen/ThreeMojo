// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Independent fixture adapter for Arm astcenc 5.3.0 (Apache-2.0).
#include "astcenc.h"
#include <cstdint>
#include <cstring>

extern "C" {
void* reference_context(unsigned size, unsigned profile) {
    astcenc_config config;
    auto p = profile == 0 ? ASTCENC_PRF_LDR :
             profile == 1 ? ASTCENC_PRF_LDR_SRGB : ASTCENC_PRF_HDR;
    if (astcenc_config_init(p, size, size, 1, ASTCENC_PRE_FASTEST,
                           ASTCENC_FLG_DECOMPRESS_ONLY, &config)) return nullptr;
    astcenc_context* ctx = nullptr;
    if (astcenc_context_alloc(&config, 1, &ctx)) return nullptr;
    return ctx;
}
void reference_free(void* ctx) { astcenc_context_free((astcenc_context*)ctx); }
int reference_block(void* ctx, const uint8_t* block, unsigned* meta,
                    void* pixels, unsigned size, unsigned profile) {
    astcenc_block_info info {};
    if (astcenc_get_block_info((astcenc_context*)ctx, block, &info)) return -1;
    meta[0] = info.is_error_block;
    meta[1] = info.is_constant_block;
    meta[2] = info.is_hdr_block;
    meta[3] = info.is_dual_plane_block;
    meta[4] = info.partition_count;
    meta[5] = info.partition_index;
    meta[6] = info.dual_plane_component;
    for (unsigned i=0; i<4; i++) meta[7+i] = info.color_endpoint_modes[i];
    meta[11] = info.color_level_count;
    meta[12] = info.weight_level_count;
    meta[13] = info.weight_x;
    meta[14] = info.weight_y;
    if (info.is_error_block) return 1;
    void* slices[] = {pixels};
    astcenc_image image {size, size, 1,
        profile == 2 ? ASTCENC_TYPE_F16 : ASTCENC_TYPE_U8, slices};
    astcenc_swizzle swizzle {ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_A};
    return astcenc_decompress_image((astcenc_context*)ctx, block, 16, &image, &swizzle, 0);
}
}
