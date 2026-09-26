// Build: fetch PVRTDecompress.cpp and PVRTDecompress.h from the PowerVR SDK
// (github.com/powervr-graphics/Native_SDK, framework/PVRCore/texture, MIT
// licence) beside this file, then g++ -std=c++17 make_reference.cpp
// PVRTDecompress.cpp -o make_reference && ./make_reference
// Writes PVRTC fixtures and what Imagination's PVRTDecompress makes of them.
// Each case: a deterministic pseudo-random payload of a size and a mode.
// Output: <name>.bin (the payload) and reference.json (the RGBA bytes).
#include "PVRTDecompress.h"
#include <cstdio>
#include <cstdint>
#include <vector>
#include <string>
#include <algorithm>

static uint32_t state = 12345;
static uint8_t next_byte() {
	state = state * 1103515245u + 12345u;
	return static_cast<uint8_t>(state >> 16);
}

int main() {
	struct Case { const char* name; uint32_t w, h, two_bit; };
	Case cases[] = {
		{ "4bpp_8x8", 8, 8, 0 },
		{ "4bpp_16x8", 16, 8, 0 },
		{ "4bpp_32x32", 32, 32, 0 },
		{ "4bpp_4x4", 4, 4, 0 },
		{ "2bpp_16x8", 16, 8, 1 },
		{ "2bpp_32x16", 32, 16, 1 },
		{ "2bpp_8x4", 8, 4, 1 },
	};
	FILE* json = std::fopen("reference.json", "w");
	std::fprintf(json, "{");
	bool first = true;
	for (const Case& c : cases) {
		uint32_t bw = c.two_bit ? 8 : 4, bh = 4;
		uint32_t wb = std::max(c.w / bw, 2u), hb = std::max(c.h / bh, 2u);
		std::vector<uint8_t> data(wb * hb * 8);
		for (auto& b : data) b = next_byte();
		std::string bin = std::string(c.name) + ".bin";
		FILE* f = std::fopen(bin.c_str(), "wb");
		std::fwrite(data.data(), 1, data.size(), f);
		std::fclose(f);
		std::vector<uint8_t> out(c.w * c.h * 4);
		pvr::PVRTDecompressPVRTC(data.data(), c.two_bit, c.w, c.h, out.data());
		std::fprintf(json, "%s\"%s\":[", first ? "" : ",", c.name);
		for (size_t i = 0; i < out.size(); i++) std::fprintf(json, "%s%u", i ? "," : "", out[i]);
		std::fprintf(json, "]");
		first = false;
	}
	std::fprintf(json, "}\n");
	std::fclose(json);
	return 0;
}
