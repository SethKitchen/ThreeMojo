// Evaluate DLSS Super Resolution (Streamline 2.14.16) on a synthetic scene, to settle the conventions
// that the headers leave open: the sign of the jitter and the direction of the motion vectors.
//
// The scene is a sum of sinusoids that the render grid cannot hold without jitter. Each frame samples
// it at the render pixel centers plus a known Halton offset. DLSS sees that offset with each of four
// sign choices, and the motion with each of two. The error against the analytic image says which
// choice DLSS needs: the right one accumulates the samples, the wrong one smears them.
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
#include <algorithm>

#include <sl.h>
#include <sl_consts.h>
#include <sl_dlss.h>
#include <sl_matrix_helpers.h>

using Microsoft::WRL::ComPtr;
using namespace DirectX::PackedVector;

#define CHECK(x) do { HRESULT _hr = (x); if (FAILED(_hr)) { std::printf("FAILED 0x%lx at %s:%d: %s\n", (unsigned long)_hr, __FILE__, __LINE__, #x); std::exit(2);} } while (0)

static const UINT OUT_W = 640, OUT_H = 360;
static const UINT REN_W = 427, REN_H = 240;  // Quality: 2/3 of each side, rounded
static const int FRAMES = 48;
static const double PI = 3.14159265358979323846;

static double halton(int index, int base) {
    double f = 1, r = 0;
    while (index > 0) { f /= base; r += f * (index % base); index /= base; }
    return r;
}

// The scene, in output pixel coordinates. Three channels of two sinusoids each, frequencies in cycles
// per output pixel. The render grid is 1.5 output pixels apart, so its Nyquist is 0.333 an axis.
static void scene(double x, double y, double vx, double vy, double t, float rgb[3]) {
    x -= vx * t; y -= vy * t;
    static const double f[3][2][2] = {
        {{0.31, 0.12}, {-0.08, 0.40}},
        {{0.18, -0.35}, {0.41, 0.05}},
        {{0.27, 0.27}, {-0.38, 0.14}},
    };
    for (int c = 0; c < 3; ++c) {
        double a = std::sin(2 * PI * (f[c][0][0] * x + f[c][0][1] * y) + 0.7 * c);
        double b = std::sin(2 * PI * (f[c][1][0] * x + f[c][1][1] * y) + 1.3 * c);
        rgb[c] = (float)(0.5 + 0.25 * a + 0.25 * b);
    }
}

static void identity(sl::float4x4& m) {
    m.setRow(0, sl::float4(1, 0, 0, 0)); m.setRow(1, sl::float4(0, 1, 0, 0));
    m.setRow(2, sl::float4(0, 0, 1, 0)); m.setRow(3, sl::float4(0, 0, 0, 1));
}

struct Tex {
    ComPtr<ID3D12Resource> res, upload;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT fp{};
    UINT rows = 0; UINT64 rowSize = 0, total = 0;
    D3D12_RESOURCE_STATES state = D3D12_RESOURCE_STATE_COMMON;
};

int main() {
    wchar_t exe[MAX_PATH];
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring dir(exe);
    dir = dir.substr(0, dir.find_last_of(L"\\/"));
    const wchar_t* paths[] = {dir.c_str()};
    sl::Feature features[] = {sl::kFeatureDLSS};
    sl::Preferences pref{};
    pref.logLevel = sl::LogLevel::eOff;
    pref.pathsToPlugins = paths; pref.numPathsToPlugins = 1;
    pref.pathToLogsAndData = dir.c_str();
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
    sl::AdapterInfo ai{}; ai.deviceLUID = (uint8_t*)&desc.AdapterLuid; ai.deviceLUIDSizeInBytes = sizeof(LUID);
    std::printf("DLSS supported: %d\n", (int)slIsFeatureSupported(sl::kFeatureDLSS, ai));

    D3D12_COMMAND_QUEUE_DESC qd{}; qd.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    ComPtr<ID3D12CommandQueue> queue; CHECK(dev->CreateCommandQueue(&qd, IID_PPV_ARGS(&queue)));
    ComPtr<ID3D12CommandAllocator> alloc; CHECK(dev->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&alloc)));
    ComPtr<ID3D12GraphicsCommandList> cl; CHECK(dev->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, alloc.Get(), nullptr, IID_PPV_ARGS(&cl)));
    cl->Close();
    ComPtr<ID3D12Fence> fence; CHECK(dev->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)));
    HANDLE evt = CreateEvent(nullptr, FALSE, FALSE, nullptr);
    UINT64 fenceValue = 0;
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
    makeTex(depth, DXGI_FORMAT_R32_FLOAT, REN_W, REN_H, D3D12_RESOURCE_FLAG_NONE, SRV, false);
    makeTex(mvec, DXGI_FORMAT_R16G16_FLOAT, REN_W, REN_H, D3D12_RESOURCE_FLAG_NONE, SRV, false);
    makeTex(colorIn, DXGI_FORMAT_R16G16B16A16_FLOAT, REN_W, REN_H, D3D12_RESOURCE_FLAG_NONE, SRV, false);
    makeTex(colorOut, DXGI_FORMAT_R16G16B16A16_FLOAT, OUT_W, OUT_H, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, true);

    auto barrier = [&](Tex& t, D3D12_RESOURCE_STATES to) {
        if (t.state == to) return;
        D3D12_RESOURCE_BARRIER b{}; b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        b.Transition.pResource = t.res.Get(); b.Transition.StateBefore = t.state; b.Transition.StateAfter = to;
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        cl->ResourceBarrier(1, &b); t.state = to;
    };
    auto upload = [&](Tex& t, const std::vector<uint8_t>& rowsData, UINT bytesPerRow) {
        uint8_t* p = nullptr; t.upload->Map(0, nullptr, (void**)&p);
        for (UINT y = 0; y < t.rows; ++y) std::memcpy(p + t.fp.Offset + (size_t)y * t.fp.Footprint.RowPitch, rowsData.data() + (size_t)y * bytesPerRow, bytesPerRow);
        t.upload->Unmap(0, nullptr);
        barrier(t, D3D12_RESOURCE_STATE_COPY_DEST);
        D3D12_TEXTURE_COPY_LOCATION dst{}, src{};
        dst.pResource = t.res.Get(); dst.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX; dst.SubresourceIndex = 0;
        src.pResource = t.upload.Get(); src.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; src.PlacedFootprint = t.fp;
        cl->CopyTextureRegion(&dst, 0, 0, 0, &src, nullptr);
        barrier(t, SRV);
    };

    // Camera: row-major, row-vector, left-handed, depth 0 to 1, as sl_matrix_helpers.h builds them.
    const float zn = 0.1f, zf = 100.f, fov = 1.0f, aspect = (float)OUT_W / OUT_H;
    const float fy = 1.f / std::tan(fov / 2), fx = fy / aspect;
    sl::Constants base{};
    base.cameraViewToClip.setRow(0, sl::float4(fx, 0, 0, 0));
    base.cameraViewToClip.setRow(1, sl::float4(0, fy, 0, 0));
    base.cameraViewToClip.setRow(2, sl::float4(0, 0, zf / (zf - zn), 1));
    base.cameraViewToClip.setRow(3, sl::float4(0, 0, -zn * zf / (zf - zn), 0));
    sl::matrixFullInvert(base.clipToCameraView, base.cameraViewToClip);
    identity(base.clipToPrevClip); identity(base.prevClipToClip); identity(base.clipToLensClip);
    base.cameraPinholeOffset = sl::float2(0, 0);
    base.cameraPos = sl::float3(0, 0, 0); base.cameraUp = sl::float3(0, 1, 0);
    base.cameraRight = sl::float3(1, 0, 0); base.cameraFwd = sl::float3(0, 0, 1);
    base.cameraNear = zn; base.cameraFar = zf; base.cameraFOV = fov; base.cameraAspectRatio = aspect;
    base.motionVectorsInvalidValue = FLT_MIN;
    base.depthInverted = sl::Boolean::eFalse; base.cameraMotionIncluded = sl::Boolean::eTrue;
    base.motionVectors3D = sl::Boolean::eFalse; base.orthographicProjection = sl::Boolean::eFalse;
    base.motionVectorsDilated = sl::Boolean::eFalse; base.motionVectorsJittered = sl::Boolean::eFalse;
    base.mvecScale = sl::float2(1.f / REN_W, 1.f / REN_H);

    const double scaleX = (double)OUT_W / REN_W, scaleY = (double)OUT_H / REN_H;

    struct Result { double mse; std::vector<float> image; };
    auto run = [&](uint32_t viewportId, double sx, double sy, double mvSign, double vx, double vy, bool jitter, Result& result) -> bool {
        sl::ViewportHandle viewport(viewportId);
        sl::DLSSOptions opt{};
        opt.mode = sl::DLSSMode::eMaxQuality; opt.outputWidth = OUT_W; opt.outputHeight = OUT_H;
        opt.colorBuffersHDR = sl::Boolean::eTrue; opt.useAutoExposure = sl::Boolean::eTrue;
        if (slDLSSSetOptions(viewport, opt) != sl::Result::eOk) { std::printf("SetOptions failed\n"); return false; }

        for (int frame = 0; frame < FRAMES; ++frame) {
            double jx = 0, jy = 0;
            if (jitter) { int i = frame % 32 + 1; jx = halton(i, 2) - 0.5; jy = halton(i, 3) - 0.5; }
            std::vector<uint8_t> color(REN_W * REN_H * 8), mv(REN_W * REN_H * 4), dp(REN_W * REN_H * 4);
            for (UINT y = 0; y < REN_H; ++y) for (UINT x = 0; x < REN_W; ++x) {
                float rgb[3];
                scene((x + 0.5 + jx) * scaleX, (y + 0.5 + jy) * scaleY, vx, vy, frame, rgb);
                uint16_t* c = (uint16_t*)&color[(y * REN_W + x) * 8];
                c[0] = XMConvertFloatToHalf(rgb[0]); c[1] = XMConvertFloatToHalf(rgb[1]);
                c[2] = XMConvertFloatToHalf(rgb[2]); c[3] = XMConvertFloatToHalf(1.f);
                // The content moves by (vx, vy) output pixels a frame, so a pixel was at minus that a frame ago.
                uint16_t* m = (uint16_t*)&mv[(y * REN_W + x) * 4];
                m[0] = XMConvertFloatToHalf((float)(mvSign * -vx / scaleX));
                m[1] = XMConvertFloatToHalf((float)(mvSign * -vy / scaleY));
                ((float*)dp.data())[y * REN_W + x] = 0.5f;
            }
            CHECK(alloc->Reset()); CHECK(cl->Reset(alloc.Get(), nullptr));
            upload(colorIn, color, REN_W * 8); upload(mvec, mv, REN_W * 4); upload(depth, dp, REN_W * 4);

            sl::Constants k = base;
            k.jitterOffset = sl::float2((float)(sx * jx), (float)(sy * jy));
            k.reset = frame == 0 ? sl::Boolean::eTrue : sl::Boolean::eFalse;
            sl::FrameToken* token = nullptr; uint32_t idx = (uint32_t)frame;
            if (slGetNewFrameToken(token, &idx) != sl::Result::eOk) { std::printf("token failed\n"); return false; }
            if (slSetConstants(k, *token, viewport) != sl::Result::eOk) { std::printf("slSetConstants failed\n"); return false; }

            sl::Extent renExt{0, 0, REN_W, REN_H}, outExt{0, 0, OUT_W, OUT_H};
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
            queue->ExecuteCommandLists(1, lists);
            flush();
        }

        uint8_t* p = nullptr; colorOut.upload->Map(0, nullptr, (void**)&p);
        result.image.assign(OUT_W * OUT_H * 3, 0);
        double sum = 0; long n = 0;
        for (UINT y = 0; y < OUT_H; ++y) for (UINT x = 0; x < OUT_W; ++x) {
            const uint16_t* c = (const uint16_t*)(p + colorOut.fp.Offset + (size_t)y * colorOut.fp.Footprint.RowPitch + x * 8);
            float rgb[3]; scene(x + 0.5, y + 0.5, vx, vy, FRAMES - 1, rgb);
            for (int ch = 0; ch < 3; ++ch) {
                float v = XMConvertHalfToFloat(c[ch]);
                result.image[(y * OUT_W + x) * 3 + ch] = v;
                if (x >= 16 && x < OUT_W - 16 && y >= 16 && y < OUT_H - 16) { sum += (v - rgb[ch]) * (v - rgb[ch]); ++n; }
            }
        }
        colorOut.upload->Unmap(0, nullptr);
        result.mse = sum / n;
        slFreeResources(sl::kFeatureDLSS, viewport);
        return true;
    };

    auto writePPM = [&](const char* name, const std::vector<float>& img) {
        FILE* f = std::fopen(name, "wb"); std::fprintf(f, "P6\n%u %u\n255\n", OUT_W, OUT_H);
        for (float v : img) { int b = (int)std::lround(std::min(1.f, std::max(0.f, v)) * 255); std::fputc(b, f); }
        std::fclose(f);
    };
    // Bilinear upsample of one unjittered render, and the analytic image, for reference.
    auto reference = [&](double vx, double vy, std::vector<float>& bilinear, std::vector<float>& truth) -> double {
        std::vector<float> ren(REN_W * REN_H * 3);
        for (UINT y = 0; y < REN_H; ++y) for (UINT x = 0; x < REN_W; ++x) scene((x + 0.5) * scaleX, (y + 0.5) * scaleY, vx, vy, FRAMES - 1, &ren[(y * REN_W + x) * 3]);
        bilinear.assign(OUT_W * OUT_H * 3, 0); truth.assign(OUT_W * OUT_H * 3, 0);
        double sum = 0; long n = 0;
        for (UINT y = 0; y < OUT_H; ++y) for (UINT x = 0; x < OUT_W; ++x) {
            double u = (x + 0.5) / scaleX - 0.5, v = (y + 0.5) / scaleY - 0.5;
            int x0 = (int)std::floor(u), y0 = (int)std::floor(v); double fu = u - x0, fv = v - y0;
            auto at = [&](int xx, int yy, int ch) { xx = std::min<int>(std::max(xx, 0), REN_W - 1); yy = std::min<int>(std::max(yy, 0), REN_H - 1); return ren[(yy * REN_W + xx) * 3 + ch]; };
            float t[3]; scene(x + 0.5, y + 0.5, vx, vy, FRAMES - 1, t);
            for (int ch = 0; ch < 3; ++ch) {
                float b = (float)((1 - fu) * (1 - fv) * at(x0, y0, ch) + fu * (1 - fv) * at(x0 + 1, y0, ch) + (1 - fu) * fv * at(x0, y0 + 1, ch) + fu * fv * at(x0 + 1, y0 + 1, ch));
                bilinear[(y * OUT_W + x) * 3 + ch] = b; truth[(y * OUT_W + x) * 3 + ch] = t[ch];
                if (x >= 16 && x < OUT_W - 16 && y >= 16 && y < OUT_H - 16) { sum += (b - t[ch]) * (b - t[ch]); ++n; }
            }
        }
        return sum / n;
    };

    std::vector<float> bil, truth;
    double refMse = reference(0, 0, bil, truth);
    std::printf("bilinear upsample of one render, MSE vs truth (static): %.6f\n", refMse);
    writePPM("static_truth.ppm", truth); writePPM("static_bilinear.ppm", bil);

    std::printf("\nA. Static scene, jitter signs (jitterOffset = sx*applied x, sy*applied y)\n");
    uint32_t vp = 0; double best = 1e9; int bsx = 1, bsy = 1;
    for (int sx : {1, -1}) for (int sy : {1, -1}) {
        Result r; if (!run(vp++, sx, sy, 1, 0, 0, true, r)) return 3;
        std::printf("  sx=%+d sy=%+d  MSE %.6f\n", sx, sy, r.mse);
        char name[64]; std::snprintf(name, sizeof name, "static_sx%+d_sy%+d.ppm", sx, sy); writePPM(name, r.image);
        if (r.mse < best) { best = r.mse; bsx = sx; bsy = sy; }
    }
    { Result r; if (!run(vp++, 0, 0, 1, 0, 0, true, r)) return 3; std::printf("  jitter applied, jitterOffset=0   MSE %.6f\n", r.mse); }
    { Result r; if (!run(vp++, 0, 0, 1, 0, 0, false, r)) return 3; std::printf("  no jitter at all                 MSE %.6f\n", r.mse); }
    std::printf("  best: sx=%+d sy=%+d\n", bsx, bsy);

    std::printf("\nB. Content moving by (0.8, 0.35) output pixels a frame, motion vector sign\n");
    const double vx = 0.8, vy = 0.35;
    double refB = reference(vx, vy, bil, truth);
    std::printf("  bilinear upsample of one render, MSE %.6f\n", refB);
    for (int sx : {1, -1}) for (int sy : {1, -1}) for (int ms : {1, -1}) {
        Result r; if (!run(vp++, sx, sy, ms, vx, vy, true, r)) return 3;
        std::printf("  sx=%+d sy=%+d mvSign=%+d  MSE %.6f\n", sx, sy, ms, r.mse);
        if (sx == bsx && sy == bsy) { char name[64]; std::snprintf(name, sizeof name, "moving_mv%+d.ppm", ms); writePPM(name, r.image); }
    }
    { Result r; if (!run(vp++, bsx, bsy, 0, vx, vy, true, r)) return 3; std::printf("  best jitter, zero motion vectors  MSE %.6f\n", r.mse); }
    writePPM("moving_truth.ppm", truth); writePPM("moving_bilinear.ppm", bil);
    slShutdown();
    return 0;
}
