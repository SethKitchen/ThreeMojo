// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
//
// The native Streamline host: it runs DLSS Super Resolution or DLSS Ray
// Reconstruction on the frames of a bundle that extensions/streamline/bundle.mojo
// wrote, and writes the last output frame back.
//
//   threemojo_streamline.exe FRAMES RESULT
//
// A path of "-" is the standard input for FRAMES and the standard output for
// RESULT. The report and any error go to the standard error.
//
// It opens a Direct3D 12 device on the first NVIDIA adapter, loads
// sl.interposer with manual hooking, and plays the frames the number of times
// that the bundle asks for. Each frame uploads its buffers, tags them, sets
// its constants, and calls slEvaluateFeature. The plugins and the NGX runtime
// must sit beside the program. build.bat puts them there.
//
// The exit status is 0 on success, 1 for a wrong command line, 2 for a bundle
// that cannot be read, 3 when Streamline refuses, and 4 for a Direct3D error.
#define NOMINMAX
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <DirectXPackedVector.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <io.h>
#include <map>
#include <string>
#include <vector>

#include <sl.h>
#include <sl_consts.h>
#include <sl_dlss.h>
#include <sl_dlss_d.h>

using Microsoft::WRL::ComPtr;
using namespace DirectX::PackedVector;

static void fail(int status, const char* message) {
    std::fprintf(stderr, "threemojo_streamline: %s\n", message);
    std::exit(status);
}

#define CHECK(x)                                                                        \
    do {                                                                                \
        HRESULT hr_ = (x);                                                              \
        if (FAILED(hr_)) {                                                              \
            std::fprintf(stderr, "threemojo_streamline: 0x%lx from %s\n",               \
                         (unsigned long)hr_, #x);                                       \
            std::exit(4);                                                               \
        }                                                                               \
    } while (0)

// The bundle, read front to back. Every field is four little-endian bytes.
struct Reader {
    std::vector<uint8_t> bytes;
    size_t at = 0;
    uint32_t word() {
        if (at + 4 > bytes.size()) fail(2, "the bundle is cut short");
        uint32_t value;
        std::memcpy(&value, &bytes[at], 4);
        at += 4;
        return value;
    }
    float number() {
        uint32_t value = word();
        float result;
        std::memcpy(&result, &value, 4);
        return result;
    }
    void matrix(sl::float4x4& out) {
        // Matrix4.elements and sl::float4x4 hold the same sixteen floats.
        float values[16];
        for (float& value : values) value = number();
        std::memcpy(&out, values, sizeof(values));
    }
    const float* floats(size_t count) {
        if (at + 4 * count > bytes.size()) fail(2, "the bundle is cut short");
        const float* start = reinterpret_cast<const float*>(&bytes[at]);
        at += 4 * count;
        return start;
    }
};

struct Buffer {
    uint32_t type = 0, width = 0, height = 0, channels = 0;
    const float* values = nullptr;
};

struct Frame {
    sl::Constants constants{};
    std::vector<Buffer> buffers;
};

struct Texture {
    ComPtr<ID3D12Resource> resource, staging;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
    UINT rows = 0;
    UINT64 row_size = 0, total = 0;
    DXGI_FORMAT format = DXGI_FORMAT_UNKNOWN;
    UINT width = 0, height = 0, channels = 0;
    D3D12_RESOURCE_STATES state = D3D12_RESOURCE_STATE_COMMON;
};

static sl::Boolean flag_of(uint32_t flags, int bit) {
    return (flags >> bit) & 1 ? sl::Boolean::eTrue : sl::Boolean::eFalse;
}

static DXGI_FORMAT format_for(uint32_t channels) {
    if (channels == 1) return DXGI_FORMAT_R32_FLOAT;
    if (channels == 2) return DXGI_FORMAT_R16G16_FLOAT;
    return DXGI_FORMAT_R16G16B16A16_FLOAT;
}

int main(int argc, char** argv) {
    if (argc != 3) fail(1, "usage: threemojo_streamline FRAMES RESULT");
    auto started = std::chrono::steady_clock::now();
    FILETIME created_ft, exited_ft, kernel_ft, user_ft, now_ft;
    GetProcessTimes(GetCurrentProcess(), &created_ft, &exited_ft, &kernel_ft, &user_ft);
    GetSystemTimePreciseAsFileTime(&now_ft);
    auto ticks = [](FILETIME f) { return ((uint64_t)f.dwHighDateTime << 32) | f.dwLowDateTime; };
    const double launch = (double)(ticks(now_ft) - ticks(created_ft)) * 1e-7;
    auto since = [&]() { return std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count(); };
    // The interposer prints to the standard output. Keep the real one for
    // the result, and send everything else written there to the standard
    // error.
    int result_fd = -1;
    if (std::strcmp(argv[2], "-") == 0) {
        std::fflush(stdout);
        result_fd = _dup(_fileno(stdout));
        if (result_fd < 0 || _dup2(_fileno(stderr), _fileno(stdout)) != 0) fail(2, "cannot keep the standard output");
        _setmode(result_fd, _O_BINARY);
    }

    Reader in;
    {
        if (std::strcmp(argv[1], "-") == 0) {
            // A pipe from WSL 2 is much faster than a file on the other
            // side of the 9P bridge.
            _setmode(_fileno(stdin), _O_BINARY);
            char chunk[1 << 16];
            size_t got;
            while ((got = std::fread(chunk, 1, sizeof(chunk), stdin)) > 0)
                in.bytes.insert(in.bytes.end(), chunk, chunk + got);
        } else {
            std::ifstream file(argv[1], std::ios::binary);
            if (!file) fail(2, "cannot read the bundle");
            in.bytes.assign(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
        }
    }
    if (in.bytes.size() < 188 || std::memcmp(in.bytes.data(), "TMSL", 4) != 0)
        fail(2, "this is not a Streamline bundle");
    in.at = 4;
    if (in.word() != 1) fail(2, "the bundle's version is not 1");
    const uint32_t feature_id = in.word();
    const uint32_t mode = in.word(), preset = in.word(), normal_roughness = in.word();
    const uint32_t flags = in.word();
    const float pre_exposure = in.number(), exposure_scale = in.number();
    const uint32_t render_w = in.word(), render_h = in.word();
    const uint32_t output_w = in.word(), output_h = in.word();
    const uint32_t passes = in.word(), count = in.word();
    sl::float4x4 world_to_view, view_to_world;
    in.matrix(world_to_view);
    in.matrix(view_to_world);
    if (feature_id != sl::kFeatureDLSS && feature_id != sl::kFeatureDLSS_RR)
        fail(2, "the feature is not Super Resolution or Ray Reconstruction");
    if (count == 0 || passes == 0) fail(2, "the bundle has no frame to play");
    const sl::Feature feature = feature_id;

    std::vector<Frame> frames(count);
    for (Frame& frame : frames) {
        sl::Constants& k = frame.constants;
        in.matrix(k.cameraViewToClip);
        in.matrix(k.clipToCameraView);
        in.matrix(k.clipToPrevClip);
        in.matrix(k.prevClipToClip);
        k.clipToLensClip.setRow(0, sl::float4(1, 0, 0, 0));
        k.clipToLensClip.setRow(1, sl::float4(0, 1, 0, 0));
        k.clipToLensClip.setRow(2, sl::float4(0, 0, 1, 0));
        k.clipToLensClip.setRow(3, sl::float4(0, 0, 0, 1));
        k.jitterOffset.x = in.number();
        k.jitterOffset.y = in.number();
        k.mvecScale.x = in.number();
        k.mvecScale.y = in.number();
        k.cameraPinholeOffset = sl::float2(0, 0);
        for (sl::float3* axis : {&k.cameraPos, &k.cameraUp, &k.cameraRight, &k.cameraFwd}) {
            axis->x = in.number();
            axis->y = in.number();
            axis->z = in.number();
        }
        k.cameraNear = in.number();
        k.cameraFar = in.number();
        k.cameraFOV = in.number();
        k.cameraAspectRatio = in.number();
        k.motionVectorsInvalidValue = FLT_MIN;
        const uint32_t marks = in.word();
        k.depthInverted = flag_of(marks, 0);
        k.cameraMotionIncluded = flag_of(marks, 1);
        k.motionVectors3D = flag_of(marks, 2);
        k.reset = flag_of(marks, 3);
        k.orthographicProjection = flag_of(marks, 4);
        k.motionVectorsDilated = flag_of(marks, 5);
        k.motionVectorsJittered = flag_of(marks, 6);
        const uint32_t buffers = in.word();
        for (uint32_t index = 0; index < buffers; ++index) {
            Buffer buffer;
            buffer.type = in.word();
            buffer.width = in.word();
            buffer.height = in.word();
            buffer.channels = in.word();
            if (buffer.channels < 1 || buffer.channels > 4) fail(2, "a buffer has a wrong channel count");
            buffer.values = in.floats((size_t)buffer.width * buffer.height * buffer.channels);
            frame.buffers.push_back(buffer);
        }
    }
    if (in.at != in.bytes.size()) fail(2, "the bundle is longer than its frames");

    const double read_at = since();
    // NGX starts nvngx_update.exe, which would inherit the standard handles
    // and hold the caller's pipes open for seconds after this program ends.
    for (DWORD which : {STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE}) {
        HANDLE handle = GetStdHandle(which);
        if (handle != nullptr && handle != INVALID_HANDLE_VALUE) SetHandleInformation(handle, HANDLE_FLAG_INHERIT, 0);
    }
    if (result_fd >= 0) {
        HANDLE handle = (HANDLE)_get_osfhandle(result_fd);
        if (handle != INVALID_HANDLE_VALUE) SetHandleInformation(handle, HANDLE_FLAG_INHERIT, 0);
    }
    // Streamline first, then the device, as manual hooking asks.
    wchar_t exe[MAX_PATH];
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring folder(exe);
    folder = folder.substr(0, folder.find_last_of(L"\\/"));
    const wchar_t* plugin_paths[] = {folder.c_str()};
    sl::Feature to_load[] = {feature};
    sl::Preferences preferences{};
    preferences.logLevel = sl::LogLevel::eOff;
    preferences.pathsToPlugins = plugin_paths;
    preferences.numPathsToPlugins = 1;
    preferences.pathToLogsAndData = folder.c_str();
    preferences.flags = sl::PreferenceFlags::eUseManualHooking | sl::PreferenceFlags::eDisableCLStateTracking;
    preferences.featuresToLoad = to_load;
    preferences.numFeaturesToLoad = 1;
    preferences.engine = sl::EngineType::eCustom;
    preferences.engineVersion = "ThreeMojo";
    preferences.projectId = "5b1c2d6e-0f0a-4a53-9a07-3f6ab4c3d2f1";
    preferences.renderAPI = sl::RenderAPI::eD3D12;
    if (slInit(preferences) != sl::Result::eOk) fail(3, "slInit failed");
    const double init_at = since();

    ComPtr<IDXGIFactory6> factory;
    CHECK(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    ComPtr<IDXGIAdapter1> adapter;
    DXGI_ADAPTER_DESC1 description{};
    for (UINT index = 0;
         factory->EnumAdapterByGpuPreference(index, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(&adapter)) == S_OK;
         ++index) {
        adapter->GetDesc1(&description);
        if (!(description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) && description.VendorId == 0x10DE) break;
        adapter.Reset();
    }
    if (!adapter) fail(3, "there is no NVIDIA adapter");
    ComPtr<ID3D12Device> device;
    CHECK(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&device)));
    const double device_at = since();
    if (slSetD3DDevice(device.Get()) != sl::Result::eOk) fail(3, "slSetD3DDevice failed");
    const double plugins_at = since();
    sl::AdapterInfo adapter_info{};
    adapter_info.deviceLUID = (uint8_t*)&description.AdapterLuid;
    adapter_info.deviceLUIDSizeInBytes = sizeof(LUID);
    if (slIsFeatureSupported(feature, adapter_info) != sl::Result::eOk) fail(3, "the GPU does not support the feature");

    D3D12_COMMAND_QUEUE_DESC queue_description{};
    queue_description.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    ComPtr<ID3D12CommandQueue> queue;
    CHECK(device->CreateCommandQueue(&queue_description, IID_PPV_ARGS(&queue)));
    ComPtr<ID3D12CommandAllocator> allocator;
    CHECK(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator)));
    ComPtr<ID3D12GraphicsCommandList> list;
    CHECK(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator.Get(), nullptr, IID_PPV_ARGS(&list)));
    CHECK(list->Close());
    ComPtr<ID3D12Fence> fence;
    CHECK(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)));
    HANDLE event = CreateEvent(nullptr, FALSE, FALSE, nullptr);
    UINT64 fence_value = 0;
    auto finish = [&]() {
        CHECK(queue->Signal(fence.Get(), ++fence_value));
        CHECK(fence->SetEventOnCompletion(fence_value, event));
        WaitForSingleObject(event, INFINITE);
    };

    D3D12_HEAP_PROPERTIES device_heap{D3D12_HEAP_TYPE_DEFAULT}, upload_heap{D3D12_HEAP_TYPE_UPLOAD},
        readback_heap{D3D12_HEAP_TYPE_READBACK};
    auto make = [&](Texture& t, UINT channels, UINT width, UINT height, bool output) {
        t.format = output ? DXGI_FORMAT_R16G16B16A16_FLOAT : format_for(channels);
        t.width = width;
        t.height = height;
        t.channels = channels;
        D3D12_RESOURCE_DESC rd{};
        rd.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        rd.Width = width;
        rd.Height = height;
        rd.DepthOrArraySize = 1;
        rd.MipLevels = 1;
        rd.Format = t.format;
        rd.SampleDesc.Count = 1;
        rd.Flags = output ? D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS : D3D12_RESOURCE_FLAG_NONE;
        t.state = output ? D3D12_RESOURCE_STATE_UNORDERED_ACCESS : D3D12_RESOURCE_STATE_COPY_DEST;
        CHECK(device->CreateCommittedResource(&device_heap, D3D12_HEAP_FLAG_NONE, &rd, t.state, nullptr,
                                              IID_PPV_ARGS(&t.resource)));
        device->GetCopyableFootprints(&rd, 0, 1, 0, &t.footprint, &t.rows, &t.row_size, &t.total);
        D3D12_RESOURCE_DESC bd{};
        bd.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
        bd.Width = t.total;
        bd.Height = 1;
        bd.DepthOrArraySize = 1;
        bd.MipLevels = 1;
        bd.SampleDesc.Count = 1;
        bd.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
        CHECK(device->CreateCommittedResource(output ? &readback_heap : &upload_heap, D3D12_HEAP_FLAG_NONE, &bd,
                                              output ? D3D12_RESOURCE_STATE_COPY_DEST
                                                     : D3D12_RESOURCE_STATE_GENERIC_READ,
                                              nullptr, IID_PPV_ARGS(&t.staging)));
    };
    auto barrier = [&](Texture& t, D3D12_RESOURCE_STATES to) {
        if (t.state == to) return;
        D3D12_RESOURCE_BARRIER b{};
        b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        b.Transition.pResource = t.resource.Get();
        b.Transition.StateBefore = t.state;
        b.Transition.StateAfter = to;
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        list->ResourceBarrier(1, &b);
        t.state = to;
    };
    const D3D12_RESOURCE_STATES readable =
        D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE;
    auto upload = [&](Texture& t, const Buffer& buffer) {
        uint8_t* mapped = nullptr;
        CHECK(t.staging->Map(0, nullptr, (void**)&mapped));
        for (UINT y = 0; y < t.height; ++y) {
            uint8_t* row = mapped + t.footprint.Offset + (size_t)y * t.footprint.Footprint.RowPitch;
            const float* source = buffer.values + (size_t)y * t.width * t.channels;
            for (UINT x = 0; x < t.width; ++x) {
                const float* texel = source + (size_t)x * t.channels;
                if (t.format == DXGI_FORMAT_R32_FLOAT) {
                    std::memcpy(row + 4 * x, texel, 4);
                } else if (t.format == DXGI_FORMAT_R16G16_FLOAT) {
                    HALF* out = reinterpret_cast<HALF*>(row + 4 * x);
                    out[0] = XMConvertFloatToHalf(texel[0]);
                    out[1] = XMConvertFloatToHalf(texel[1]);
                } else {
                    HALF* out = reinterpret_cast<HALF*>(row + 8 * x);
                    for (UINT c = 0; c < 4; ++c)
                        out[c] = XMConvertFloatToHalf(c < t.channels ? texel[c] : 1.0f);
                }
            }
        }
        t.staging->Unmap(0, nullptr);
        barrier(t, D3D12_RESOURCE_STATE_COPY_DEST);
        D3D12_TEXTURE_COPY_LOCATION destination{}, source{};
        destination.pResource = t.resource.Get();
        destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        source.pResource = t.staging.Get();
        source.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
        source.PlacedFootprint = t.footprint;
        list->CopyTextureRegion(&destination, 0, 0, 0, &source, nullptr);
        barrier(t, readable);
    };

    sl::ViewportHandle viewport(0);
    if (feature == sl::kFeatureDLSS) {
        sl::DLSSOptions options{};
        options.mode = (sl::DLSSMode)mode;
        options.outputWidth = output_w;
        options.outputHeight = output_h;
        options.preExposure = pre_exposure;
        options.exposureScale = exposure_scale;
        options.colorBuffersHDR = flag_of(flags, 0);
        options.useAutoExposure = flag_of(flags, 1);
        options.alphaUpscalingEnabled = flag_of(flags, 2);
        options.dlaaPreset = options.qualityPreset = options.balancedPreset = options.performancePreset =
            options.ultraPerformancePreset = options.ultraQualityPreset = (sl::DLSSPreset)preset;
        if (slDLSSSetOptions(viewport, options) != sl::Result::eOk) fail(3, "slDLSSSetOptions failed");
    } else {
        sl::DLSSDOptions options{};
        options.mode = (sl::DLSSMode)mode;
        options.outputWidth = output_w;
        options.outputHeight = output_h;
        options.preExposure = pre_exposure;
        options.exposureScale = exposure_scale;
        options.colorBuffersHDR = flag_of(flags, 0);
        options.alphaUpscalingEnabled = flag_of(flags, 2);
        options.normalRoughnessMode = (sl::DLSSDNormalRoughnessMode)normal_roughness;
        options.worldToCameraView = world_to_view;
        options.cameraViewToWorld = view_to_world;
        options.dlaaPreset = options.qualityPreset = options.balancedPreset = options.performancePreset =
            options.ultraPerformancePreset = options.ultraQualityPreset = (sl::DLSSDPreset)preset;
        if (slDLSSDSetOptions(viewport, options) != sl::Result::eOk) fail(3, "slDLSSDSetOptions failed");
    }

    const double ready_at = since();
    double first_at = ready_at;
    std::map<uint32_t, Texture> inputs;
    Texture output;
    make(output, 4, output_w, output_h, true);
    const uint32_t total = count * passes;
    for (uint32_t step = 0; step < total; ++step) {
        Frame& frame = frames[step % count];
        CHECK(allocator->Reset());
        CHECK(list->Reset(allocator.Get(), nullptr));
        std::vector<sl::Resource> resources;
        resources.reserve(frame.buffers.size() + 1);
        std::vector<sl::ResourceTag> tags;
        tags.reserve(frame.buffers.size() + 1);
        std::vector<sl::Extent> extents;
        extents.reserve(frame.buffers.size() + 1);
        for (const Buffer& buffer : frame.buffers) {
            Texture& t = inputs[buffer.type];
            if (!t.resource) make(t, buffer.channels, buffer.width, buffer.height, false);
            if (t.width != buffer.width || t.height != buffer.height || t.channels != buffer.channels)
                fail(2, "a buffer changes its size between frames");
            upload(t, buffer);
            extents.push_back(sl::Extent{0, 0, buffer.width, buffer.height});
            resources.emplace_back(sl::ResourceType::eTex2d, t.resource.Get(), (uint32_t)readable);
            tags.emplace_back(&resources.back(), buffer.type, sl::ResourceLifecycle::eOnlyValidNow, &extents.back());
        }
        extents.push_back(sl::Extent{0, 0, output_w, output_h});
        resources.emplace_back(sl::ResourceType::eTex2d, output.resource.Get(),
                               (uint32_t)D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
        tags.emplace_back(&resources.back(), sl::kBufferTypeScalingOutputColor, sl::ResourceLifecycle::eOnlyValidNow,
                          &extents.back());

        sl::Constants constants = frame.constants;
        if (step >= count) constants.reset = sl::Boolean::eFalse;
        sl::FrameToken* token = nullptr;
        uint32_t index = step;
        if (slGetNewFrameToken(token, &index) != sl::Result::eOk) fail(3, "slGetNewFrameToken failed");
        if (slSetConstants(constants, *token, viewport) != sl::Result::eOk) fail(3, "slSetConstants failed");
        std::vector<const sl::BaseStructure*> evaluate_inputs{&viewport};
        for (sl::ResourceTag& tag : tags) evaluate_inputs.push_back(&tag);
        sl::Result result = slEvaluateFeature(feature, *token, evaluate_inputs.data(),
                                              (uint32_t)evaluate_inputs.size(), (sl::CommandBuffer*)list.Get());
        if (result != sl::Result::eOk) {
            std::fprintf(stderr, "threemojo_streamline: slEvaluateFeature returned %d at frame %u\n", (int)result,
                         step);
            return 3;
        }
        if (step + 1 == total) {
            barrier(output, D3D12_RESOURCE_STATE_COPY_SOURCE);
            D3D12_TEXTURE_COPY_LOCATION destination{}, source{};
            destination.pResource = output.staging.Get();
            destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
            destination.PlacedFootprint = output.footprint;
            source.pResource = output.resource.Get();
            source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
            list->CopyTextureRegion(&destination, 0, 0, 0, &source, nullptr);
            barrier(output, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
        }
        CHECK(list->Close());
        ID3D12CommandList* lists[] = {list.Get()};
        queue->ExecuteCommandLists(1, lists);
        finish();
        if (step == 0) first_at = since();
    }
    const double frames_at = since();

    std::vector<uint8_t> out(16 + (size_t)output_w * output_h * 16);
    auto put = [&](size_t at, uint32_t word) { std::memcpy(&out[at], &word, 4); };
    std::memcpy(out.data(), "TMSR", 4);
    put(4, 1);
    put(8, output_w);
    put(12, output_h);
    uint8_t* mapped = nullptr;
    CHECK(output.staging->Map(0, nullptr, (void**)&mapped));
    size_t at = 16;
    for (UINT y = 0; y < output_h; ++y) {
        const HALF* row = reinterpret_cast<const HALF*>(mapped + output.footprint.Offset +
                                                        (size_t)y * output.footprint.Footprint.RowPitch);
        for (UINT x = 0; x < 4 * output_w; ++x, at += 4) {
            float value = XMConvertHalfToFloat(row[x]);
            std::memcpy(&out[at], &value, 4);
        }
    }
    output.staging->Unmap(0, nullptr);
    slFreeResources(feature, viewport);
    slShutdown();
    if (result_fd >= 0) {
        size_t written = 0;
        while (written < out.size()) {
            int chunk = _write(result_fd, out.data() + written, (unsigned)std::min<size_t>(out.size() - written, 1 << 20));
            if (chunk <= 0) fail(2, "cannot write the result");
            written += (size_t)chunk;
        }
        _close(result_fd);
    } else {
        std::ofstream file(argv[2], std::ios::binary);
        file.write(reinterpret_cast<const char*>(out.data()), (std::streamsize)out.size());
        if (!file) fail(2, "cannot write the result");
    }
    std::fprintf(stderr, "%s: %u frames, %u passes, %ux%u to %ux%u, %.3f s: launch %.3f, read %.3f, slInit %.3f, device %.3f,"
                " slSetD3DDevice %.3f, options %.3f, first frame %.3f, other frames %.3f, write %.3f\n",
                feature == sl::kFeatureDLSS ? "Super Resolution" : "Ray Reconstruction", count, passes, render_w,
                render_h, output_w, output_h, since(), launch, read_at, init_at - read_at, device_at - init_at,
                plugins_at - device_at, ready_at - plugins_at, first_at - ready_at, frames_at - first_at,
                since() - frames_at);
    return 0;
}
