// Run DLSS Super Resolution (Streamline 2.14.16) on the frames that `docs/validation/streamline/streamline.mojo --frames DIR`
// wrote: ThreeMojo's jittered renders, their depth, and the jitter that frame_constants hands to Streamline.
// It measures the error against the full-size render for the jitter as given and for its negative.
//
//   evaluate_frames.exe DIR OUTDIR
#define NOMINMAX
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <DirectXPackedVector.h>
#include <cstdio>
#include <cmath>
#include <cfloat>
#include <vector>
#include <string>
#include <fstream>
#include <algorithm>

#include <sl.h>
#include <sl_consts.h>
#include <sl_dlss.h>
#include <sl_matrix_helpers.h>

using Microsoft::WRL::ComPtr;
using namespace DirectX::PackedVector;

#define CHECK(x) do { HRESULT _hr = (x); if (FAILED(_hr)) { std::printf("FAILED 0x%lx at %d: %s\n", (unsigned long)_hr, __LINE__, #x); std::exit(2);} } while (0)

static std::vector<uint8_t> readAll(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) { std::printf("cannot read %s\n", path.c_str()); std::exit(4); }
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

struct Tex {
    ComPtr<ID3D12Resource> res, upload;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT fp{};
    UINT rows = 0; UINT64 rowSize = 0, total = 0;
    D3D12_RESOURCE_STATES state = D3D12_RESOURCE_STATE_COMMON;
};

static void identity(sl::float4x4& m) {
    m.setRow(0, sl::float4(1, 0, 0, 0)); m.setRow(1, sl::float4(0, 1, 0, 0));
    m.setRow(2, sl::float4(0, 0, 1, 0)); m.setRow(3, sl::float4(0, 0, 0, 1));
}

static void writePPM(const std::string& path, const std::vector<uint8_t>& rgba, UINT w, UINT h) {
    FILE* f = std::fopen(path.c_str(), "wb"); std::fprintf(f, "P6\n%u %u\n255\n", w, h);
    for (size_t i = 0; i < (size_t)w * h; ++i) std::fwrite(&rgba[i * 4], 1, 3, f);
    std::fclose(f);
}

static double mse(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b, UINT w, UINT h) {
    double sum = 0; long n = 0;
    for (UINT y = 16; y < h - 16; ++y) for (UINT x = 16; x < w - 16; ++x) for (int c = 0; c < 3; ++c) {
        double d = (a[((size_t)y * w + x) * 4 + c] - b[((size_t)y * w + x) * 4 + c]) / 255.0; sum += d * d; ++n;
    }
    return sum / n;
}

int main(int argc, char** argv) {
    if (argc < 3) { std::printf("usage: evaluate_frames DIR OUTDIR\n"); return 1; }
    std::string dir = argv[1], outDir = argv[2];
    UINT renW, renH, outW, outH; int count;
    std::vector<double> jx, jy;
    {
        std::ifstream m(dir + "/meta.txt");
        m >> renW >> renH >> outW >> outH >> count;
        for (int i = 0; i < count; ++i) { double a, b; m >> a >> b; jx.push_back(a); jy.push_back(b); }
    }
    std::printf("render %ux%u -> output %ux%u, %d jitter phases\n", renW, renH, outW, outH, count);
    std::vector<std::vector<uint8_t>> colors, depths;
    for (int i = 0; i < count; ++i) {
        colors.push_back(readAll(dir + "/color_" + std::to_string(i) + ".rgba"));
        depths.push_back(readAll(dir + "/depth_" + std::to_string(i) + ".u16"));
    }
    std::vector<uint8_t> nativeImg = readAll(dir + "/native.rgba"), fallbackImg = readAll(dir + "/fallback.rgba");

    wchar_t exe[MAX_PATH]; GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring wdir(exe); wdir = wdir.substr(0, wdir.find_last_of(L"\\/"));
    const wchar_t* paths[] = {wdir.c_str()};
    sl::Feature features[] = {sl::kFeatureDLSS};
    sl::Preferences pref{};
    pref.logLevel = sl::LogLevel::eOff;
    pref.pathsToPlugins = paths; pref.numPathsToPlugins = 1; pref.pathToLogsAndData = wdir.c_str();
    pref.flags = sl::PreferenceFlags::eUseManualHooking | sl::PreferenceFlags::eDisableCLStateTracking;
    pref.featuresToLoad = features; pref.numFeaturesToLoad = 1;
    pref.engine = sl::EngineType::eCustom; pref.engineVersion = "ThreeMojo-probe";
    pref.projectId = "5b1c2d6e-0f0a-4a53-9a07-3f6ab4c3d2f1";
    pref.renderAPI = sl::RenderAPI::eD3D12;
    if (slInit(pref) != sl::Result::eOk) { std::printf("slInit failed\n"); return 1; }

    ComPtr<IDXGIFactory6> factory; CHECK(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    ComPtr<IDXGIAdapter1> adapter; DXGI_ADAPTER_DESC1 desc{};
    for (UINT i = 0; factory->EnumAdapterByGpuPreference(i, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(&adapter)) == S_OK; ++i) {
        adapter->GetDesc1(&desc);
        if (!(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) && desc.VendorId == 0x10DE) break;
        adapter.Reset();
    }
    ComPtr<ID3D12Device> dev; CHECK(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&dev)));
    if (slSetD3DDevice(dev.Get()) != sl::Result::eOk) { std::printf("slSetD3DDevice failed\n"); return 1; }

    D3D12_COMMAND_QUEUE_DESC qd{}; qd.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    ComPtr<ID3D12CommandQueue> queue; CHECK(dev->CreateCommandQueue(&qd, IID_PPV_ARGS(&queue)));
    ComPtr<ID3D12CommandAllocator> alloc; CHECK(dev->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&alloc)));
    ComPtr<ID3D12GraphicsCommandList> cl; CHECK(dev->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc.Get(), nullptr, IID_PPV_ARGS(&cl)));
    cl->Close();
    ComPtr<ID3D12Fence> fence; CHECK(dev->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)));
    HANDLE evt = CreateEvent(nullptr, FALSE, FALSE, nullptr); UINT64 fenceValue = 0;
    auto flush = [&]() { queue->Signal(fence.Get(), ++fenceValue); fence->SetEventOnCompletion(fenceValue, evt); WaitForSingleObject(evt, INFINITE); };

    D3D12_HEAP_PROPERTIES defHeap{D3D12_HEAP_TYPE_DEFAULT}, upHeap{D3D12_HEAP_TYPE_UPLOAD}, rbHeap{D3D12_HEAP_TYPE_READBACK};
    auto makeTex = [&](Tex& t, DXGI_FORMAT fmt, UINT w, UINT h, D3D12_RESOURCE_FLAGS flags, D3D12_RESOURCE_STATES initial, bool readback) {
        D3D12_RESOURCE_DESC rd{}; rd.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D; rd.Width = w; rd.Height = h;
        rd.DepthOrArraySize = 1; rd.MipLevels = 1; rd.Format = fmt; rd.SampleDesc.Count = 1; rd.Flags = flags;
        CHECK(dev->CreateCommittedResource(&defHeap, D3D12_HEAP_FLAG_NONE, &rd, initial, nullptr, IID_PPV_ARGS(&t.res)));
        dev->GetCopyableFootprints(&rd, 0, 1, 0, &t.fp, &t.rows, &t.rowSize, &t.total);
        D3D12_RESOURCE_DESC bd{}; bd.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER; bd.Width = t.total; bd.Height = 1;
        bd.DepthOrArraySize = 1; bd.MipLevels = 1; bd.SampleDesc.Count = 1; bd.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
        CHECK(dev->CreateCommittedResource(readback ? &rbHeap : &upHeap, D3D12_HEAP_FLAG_NONE, &bd,
              readback ? D3D12_RESOURCE_STATE_COPY_DEST : D3D12_RESOURCE_STATE_GENERIC_READ, nullptr, IID_PPV_ARGS(&t.upload)));
        t.state = initial;
    };
    const D3D12_RESOURCE_STATES SRV = D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE | D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE;
    Tex depth, mvec, colorIn, colorOut;
    makeTex(depth, DXGI_FORMAT_R32_FLOAT, renW, renH, D3D12_RESOURCE_FLAG_NONE, SRV, false);
    makeTex(mvec, DXGI_FORMAT_R16G16_FLOAT, renW, renH, D3D12_RESOURCE_FLAG_NONE, SRV, false);
    makeTex(colorIn, DXGI_FORMAT_R8G8B8A8_UNORM, renW, renH, D3D12_RESOURCE_FLAG_NONE, SRV, false);
    makeTex(colorOut, DXGI_FORMAT_R8G8B8A8_UNORM, outW, outH, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, true);

    auto barrier = [&](Tex& t, D3D12_RESOURCE_STATES to) {
        if (t.state == to) return;
        D3D12_RESOURCE_BARRIER b{}; b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        b.Transition.pResource = t.res.Get(); b.Transition.StateBefore = t.state; b.Transition.StateAfter = to;
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        cl->ResourceBarrier(1, &b); t.state = to;
    };
    auto upload = [&](Tex& t, const uint8_t* data, UINT bytesPerRow) {
        uint8_t* p = nullptr; t.upload->Map(0, nullptr, (void**)&p);
        for (UINT y = 0; y < t.rows; ++y) std::memcpy(p + t.fp.Offset + (size_t)y * t.fp.Footprint.RowPitch, data + (size_t)y * bytesPerRow, bytesPerRow);
        t.upload->Unmap(0, nullptr);
        barrier(t, D3D12_RESOURCE_STATE_COPY_DEST);
        D3D12_TEXTURE_COPY_LOCATION dst{}, src{};
        dst.pResource = t.res.Get(); dst.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX; dst.SubresourceIndex = 0;
        src.pResource = t.upload.Get(); src.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; src.PlacedFootprint = t.fp;
        cl->CopyTextureRegion(&dst, 0, 0, 0, &src, nullptr);
        barrier(t, SRV);
    };

    // The camera of docs/validation/streamline/streamline.mojo: 40 degrees, near 0.1, far 100. Row-major, row vectors, depth 0 to 1.
    const float zn = 0.1f, zf = 100.f, fov = 40.f * 3.14159265f / 180.f, aspect = (float)outW / outH;
    const float fy = 1.f / std::tan(fov / 2), fx = fy / aspect;
    sl::Constants base{};
    base.cameraViewToClip.setRow(0, sl::float4(fx, 0, 0, 0));
    base.cameraViewToClip.setRow(1, sl::float4(0, fy, 0, 0));
    base.cameraViewToClip.setRow(2, sl::float4(0, 0, zf / (zf - zn), 1));
    base.cameraViewToClip.setRow(3, sl::float4(0, 0, -zn * zf / (zf - zn), 0));
    sl::matrixFullInvert(base.clipToCameraView, base.cameraViewToClip);
    identity(base.clipToPrevClip); identity(base.prevClipToClip); identity(base.clipToLensClip);
    base.cameraPinholeOffset = sl::float2(0, 0);
    base.cameraPos = sl::float3(0, 0.95f, 2.75f); base.cameraUp = sl::float3(0, 1, 0);
    base.cameraRight = sl::float3(1, 0, 0); base.cameraFwd = sl::float3(0, 0, 1);
    base.cameraNear = zn; base.cameraFar = zf; base.cameraFOV = fov; base.cameraAspectRatio = aspect;
    base.motionVectorsInvalidValue = FLT_MIN;
    base.depthInverted = sl::Boolean::eFalse; base.cameraMotionIncluded = sl::Boolean::eTrue;
    base.motionVectors3D = sl::Boolean::eFalse; base.orthographicProjection = sl::Boolean::eFalse;
    base.motionVectorsDilated = sl::Boolean::eFalse; base.motionVectorsJittered = sl::Boolean::eFalse;
    base.mvecScale = sl::float2(1.f / renW, 1.f / renH);

    std::vector<uint8_t> zeroMv((size_t)renW * renH * 4, 0);
    const int FRAMES = count * 3;

    auto run = [&](uint32_t viewportId, double sign, bool giveJitter, std::vector<uint8_t>& image) -> bool {
        sl::ViewportHandle viewport(viewportId);
        sl::DLSSOptions opt{};
        opt.mode = sl::DLSSMode::eBalanced; opt.outputWidth = outW; opt.outputHeight = outH;
        opt.colorBuffersHDR = sl::Boolean::eFalse; opt.useAutoExposure = sl::Boolean::eTrue;
        // The render size DLSS wants for this mode and output.
        sl::DLSSOptimalSettings s{};
        slDLSSGetOptimalSettings(opt, s);
        if (s.optimalRenderWidth != renW || s.optimalRenderHeight != renH)
            std::printf("WARNING: DLSS wants %ux%u, the frames are %ux%u\n", s.optimalRenderWidth, s.optimalRenderHeight, renW, renH);
        if (slDLSSSetOptions(viewport, opt) != sl::Result::eOk) { std::printf("SetOptions failed\n"); return false; }
        for (int frame = 0; frame < FRAMES; ++frame) {
            int i = frame % count;
            std::vector<float> dp((size_t)renW * renH);
            for (size_t k = 0; k < dp.size(); ++k) dp[k] = (depths[i][2 * k] | (depths[i][2 * k + 1] << 8)) / 65535.f;
            CHECK(alloc->Reset()); CHECK(cl->Reset(alloc.Get(), nullptr));
            upload(colorIn, colors[i].data(), renW * 4);
            upload(mvec, zeroMv.data(), renW * 4);
            upload(depth, (const uint8_t*)dp.data(), renW * 4);

            sl::Constants k = base;
            k.jitterOffset = giveJitter ? sl::float2((float)(sign * jx[i]), (float)(sign * jy[i])) : sl::float2(0, 0);
            k.reset = frame == 0 ? sl::Boolean::eTrue : sl::Boolean::eFalse;
            sl::FrameToken* token = nullptr; uint32_t idx = (uint32_t)frame;
            if (slGetNewFrameToken(token, &idx) != sl::Result::eOk) { std::printf("token failed\n"); return false; }
            if (slSetConstants(k, *token, viewport) != sl::Result::eOk) { std::printf("slSetConstants failed\n"); return false; }

            sl::Extent renExt{0, 0, renW, renH}, outExt{0, 0, outW, outH};
            sl::Resource rDepth(sl::ResourceType::eTex2d, depth.res.Get(), (uint32_t)SRV);
            sl::Resource rMvec(sl::ResourceType::eTex2d, mvec.res.Get(), (uint32_t)SRV);
            sl::Resource rIn(sl::ResourceType::eTex2d, colorIn.res.Get(), (uint32_t)SRV);
            sl::Resource rOut(sl::ResourceType::eTex2d, colorOut.res.Get(), (uint32_t)D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
            sl::ResourceTag tDepth(&rDepth, sl::kBufferTypeDepth, sl::ResourceLifecycle::eOnlyValidNow, &renExt);
            sl::ResourceTag tMvec(&rMvec, sl::kBufferTypeMotionVectors, sl::ResourceLifecycle::eOnlyValidNow, &renExt);
            sl::ResourceTag tIn(&rIn, sl::kBufferTypeScalingInputColor, sl::ResourceLifecycle::eOnlyValidNow, &renExt);
            sl::ResourceTag tOut(&rOut, sl::kBufferTypeScalingOutputColor, sl::ResourceLifecycle::eOnlyValidNow, &outExt);
            const sl::BaseStructure* inputs[] = {&viewport, &tDepth, &tMvec, &tIn, &tOut};
            sl::Result er = slEvaluateFeature(sl::kFeatureDLSS, *token, inputs, 5, (sl::CommandBuffer*)cl.Get());
            if (er != sl::Result::eOk) { std::printf("slEvaluateFeature -> %d at frame %d\n", (int)er, frame); return false; }
            if (frame == FRAMES - 1) {
                barrier(colorOut, D3D12_RESOURCE_STATE_COPY_SOURCE);
                D3D12_TEXTURE_COPY_LOCATION dst{}, src{};
                dst.pResource = colorOut.upload.Get(); dst.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; dst.PlacedFootprint = colorOut.fp;
                src.pResource = colorOut.res.Get(); src.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX; src.SubresourceIndex = 0;
                cl->CopyTextureRegion(&dst, 0, 0, 0, &src, nullptr);
                barrier(colorOut, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
            }
            CHECK(cl->Close());
            ID3D12CommandList* lists[] = {cl.Get()};
            queue->ExecuteCommandLists(1, lists); flush();
        }
        uint8_t* p = nullptr; colorOut.upload->Map(0, nullptr, (void**)&p);
        image.assign((size_t)outW * outH * 4, 255);
        for (UINT y = 0; y < outH; ++y) std::memcpy(&image[(size_t)y * outW * 4], p + colorOut.fp.Offset + (size_t)y * colorOut.fp.Footprint.RowPitch, outW * 4);
        colorOut.upload->Unmap(0, nullptr);
        slFreeResources(sl::kFeatureDLSS, viewport);
        return true;
    };

    std::printf("fallback (EASU + RCAS of one unjittered render): MSE vs native %.6f\n", mse(fallbackImg, nativeImg, outW, outH));
    std::vector<uint8_t> asGiven, flipped, none;
    if (!run(0, 1, true, asGiven)) return 3;
    std::printf("DLSS, jitter as frame_constants gives it:        MSE vs native %.6f\n", mse(asGiven, nativeImg, outW, outH));
    if (!run(1, -1, true, flipped)) return 3;
    std::printf("DLSS, the opposite sign:                         MSE vs native %.6f\n", mse(flipped, nativeImg, outW, outH));
    if (!run(2, 0, false, none)) return 3;
    std::printf("DLSS, jitter not given:                          MSE vs native %.6f\n", mse(none, nativeImg, outW, outH));
    writePPM(outDir + "/dlss.ppm", asGiven, outW, outH);
    writePPM(outDir + "/dlss_flipped.ppm", flipped, outW, outH);
    writePPM(outDir + "/dlss_nojitter.ppm", none, outW, outH);
    writePPM(outDir + "/native.ppm", nativeImg, outW, outH);
    writePPM(outDir + "/fallback.ppm", fallbackImg, outW, outH);
    slShutdown();
    return 0;
}
