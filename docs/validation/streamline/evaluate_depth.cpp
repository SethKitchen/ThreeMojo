// Evaluate DLSS Super Resolution (Streamline 2.14.16) on a scene where the depth matters, to settle the range
// and the sense of the depth that Streamline reads.
//
// A disc with its own texture circles in front of a static textured background. Depth tells DLSS which layer
// a pixel belongs to where the disc uncovers the background. The program feeds DLSS the same frames with
// five encodings of the depth, and measures the error against the true image near the disc's edge:
//   correct   hardware depth, 0 to 1, nearer is smaller (Direct3D)
//   flat      one value everywhere
//   inverted  nearer is larger, with depthInverted false
//   ndc       the OpenGL range, -1 to 1 (what ThreeMojo's rasterizer holds)
//   flagged   the correct depth, with depthInverted true
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

#define CHECK(x) do { HRESULT _hr = (x); if (FAILED(_hr)) { std::printf("FAILED 0x%lx at %d: %s\n", (unsigned long)_hr, __LINE__, #x); std::exit(2);} } while (0)

static const UINT OUT_W = 640, OUT_H = 360, REN_W = 427, REN_H = 240;
static const int FRAMES = 60;
static const double PI = 3.14159265358979323846;
static const double PATH_R = 90, DISC_R = 70, W_ANG = 0.045;
static const double CX0 = 320, CY0 = 180;

static double halton(int index, int base) {
    double f = 1, r = 0;
    while (index > 0) { f /= base; r += f * (index % base); index /= base; }
    return r;
}

static void pattern(double x, double y, const double f[3][2][2], float rgb[3]) {
    for (int c = 0; c < 3; ++c) {
        double a = std::sin(2 * PI * (f[c][0][0] * x + f[c][0][1] * y) + 0.7 * c);
        double b = std::sin(2 * PI * (f[c][1][0] * x + f[c][1][1] * y) + 1.3 * c);
        rgb[c] = (float)(0.5 + 0.25 * a + 0.25 * b);
    }
}
static const double BG[3][2][2] = {{{0.11, 0.07}, {-0.05, 0.13}}, {{0.08, -0.12}, {0.14, 0.04}}, {{0.1, 0.1}, {-0.13, 0.06}}};
static const double FG[3][2][2] = {{{0.2, 0.05}, {-0.04, 0.18}}, {{0.06, -0.2}, {0.19, 0.03}}, {{0.15, 0.15}, {-0.17, 0.09}}};

static void discCenter(int t, double& cx, double& cy) { cx = CX0 + PATH_R * std::cos(W_ANG * t); cy = CY0 + PATH_R * std::sin(W_ANG * t); }

// The true color at an output point of frame t, and whether the disc covers it.
static void truth(double x, double y, int t, float rgb[3], bool& inside) {
    double cx, cy; discCenter(t, cx, cy);
    inside = (x - cx) * (x - cx) + (y - cy) * (y - cy) < DISC_R * DISC_R;
    if (inside) pattern(x - cx, y - cy, FG, rgb); else pattern(x, y, BG, rgb);
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
    wchar_t exe[MAX_PATH]; GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring dir(exe); dir = dir.substr(0, dir.find_last_of(L"\\/"));
    const wchar_t* paths[] = {dir.c_str()};
    sl::Feature features[] = {sl::kFeatureDLSS};
    sl::Preferences pref{};
    pref.logLevel = sl::LogLevel::eOff;
    pref.pathsToPlugins = paths; pref.numPathsToPlugins = 1; pref.pathToLogsAndData = dir.c_str();
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
    auto upload = [&](Tex& t, const std::vector<uint8_t>& data, UINT bytesPerRow) {
        uint8_t* p = nullptr; t.upload->Map(0, nullptr, (void**)&p);
        for (UINT y = 0; y < t.rows; ++y) std::memcpy(p + t.fp.Offset + (size_t)y * t.fp.Footprint.RowPitch, data.data() + (size_t)y * bytesPerRow, bytesPerRow);
        t.upload->Unmap(0, nullptr);
        barrier(t, D3D12_RESOURCE_STATE_COPY_DEST);
        D3D12_TEXTURE_COPY_LOCATION dst{}, src{};
        dst.pResource = t.res.Get(); dst.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX; dst.SubresourceIndex = 0;
        src.pResource = t.upload.Get(); src.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; src.PlacedFootprint = t.fp;
        cl->CopyTextureRegion(&dst, 0, 0, 0, &src, nullptr);
        barrier(t, SRV);
    };

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
    base.cameraMotionIncluded = sl::Boolean::eTrue; base.motionVectors3D = sl::Boolean::eFalse;
    base.orthographicProjection = sl::Boolean::eFalse; base.motionVectorsDilated = sl::Boolean::eFalse;
    base.motionVectorsJittered = sl::Boolean::eFalse;
    base.mvecScale = sl::float2(1.f / REN_W, 1.f / REN_H);
    const double scaleX = (double)OUT_W / REN_W, scaleY = (double)OUT_H / REN_H;

    enum Mode { CORRECT, FLAT, INVERTED, NDC, FLAGGED };
    const char* names[] = {"correct (0..1, nearer smaller)", "flat", "inverted (nearer larger)", "ndc (-1..1)", "correct, depthInverted flag true"};
    struct Result { double all, edge; std::vector<float> image; };

    auto run = [&](uint32_t viewportId, Mode mode, Result& r) -> bool {
        sl::ViewportHandle viewport(viewportId);
        sl::DLSSOptions opt{};
        opt.mode = sl::DLSSMode::eMaxQuality; opt.outputWidth = OUT_W; opt.outputHeight = OUT_H;
        opt.colorBuffersHDR = sl::Boolean::eTrue; opt.useAutoExposure = sl::Boolean::eTrue;
        if (slDLSSSetOptions(viewport, opt) != sl::Result::eOk) { std::printf("SetOptions failed\n"); return false; }
        for (int frame = 0; frame < FRAMES; ++frame) {
            int i = frame % 32 + 1; double jx = halton(i, 2) - 0.5, jy = halton(i, 3) - 0.5;
            double cx, cy, px, py; discCenter(frame, cx, cy); discCenter(frame > 0 ? frame - 1 : 0, px, py);
            std::vector<uint8_t> color(REN_W * REN_H * 8), mv(REN_W * REN_H * 4), dp(REN_W * REN_H * 4);
            for (UINT y = 0; y < REN_H; ++y) for (UINT x = 0; x < REN_W; ++x) {
                float rgb[3]; bool inside;
                truth((x + 0.5 + jx) * scaleX, (y + 0.5 + jy) * scaleY, frame, rgb, inside);
                uint16_t* c = (uint16_t*)&color[(y * REN_W + x) * 8];
                for (int ch = 0; ch < 3; ++ch) c[ch] = XMConvertFloatToHalf(rgb[ch]);
                c[3] = XMConvertFloatToHalf(1.f);
                // Where the content was a frame ago: the disc moved by (cx - px, cy - py).
                uint16_t* m = (uint16_t*)&mv[(y * REN_W + x) * 4];
                m[0] = XMConvertFloatToHalf(inside ? (float)(-(cx - px) / scaleX) : 0.f);
                m[1] = XMConvertFloatToHalf(inside ? (float)(-(cy - py) / scaleY) : 0.f);
                float zNear = 0.4f, zFar = 0.9f, d = inside ? zNear : zFar;
                switch (mode) {
                    case CORRECT: case FLAGGED: break;
                    case FLAT: d = 0.5f; break;
                    case INVERTED: d = 1.f - d; break;
                    case NDC: d = 2.f * d - 1.f; break;
                }
                ((float*)dp.data())[y * REN_W + x] = d;
            }
            CHECK(alloc->Reset()); CHECK(cl->Reset(alloc.Get(), nullptr));
            upload(colorIn, color, REN_W * 8); upload(mvec, mv, REN_W * 4); upload(depth, dp, REN_W * 4);
            sl::Constants k = base;
            k.jitterOffset = sl::float2((float)(-jx), (float)(-jy));
            k.depthInverted = mode == FLAGGED ? sl::Boolean::eTrue : sl::Boolean::eFalse;
            k.reset = frame == 0 ? sl::Boolean::eTrue : sl::Boolean::eFalse;
            sl::FrameToken* token = nullptr; uint32_t idx = (uint32_t)frame;
            if (slGetNewFrameToken(token, &idx) != sl::Result::eOk) return false;
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
            queue->ExecuteCommandLists(1, lists); flush();
        }
        uint8_t* p = nullptr; colorOut.upload->Map(0, nullptr, (void**)&p);
        r.image.assign(OUT_W * OUT_H * 3, 0);
        double cx, cy; discCenter(FRAMES - 1, cx, cy);
        double sumAll = 0, sumEdge = 0; long nAll = 0, nEdge = 0;
        for (UINT y = 0; y < OUT_H; ++y) for (UINT x = 0; x < OUT_W; ++x) {
            const uint16_t* c = (const uint16_t*)(p + colorOut.fp.Offset + (size_t)y * colorOut.fp.Footprint.RowPitch + x * 8);
            float t[3]; bool inside; truth(x + 0.5, y + 0.5, FRAMES - 1, t, inside);
            double dist = std::sqrt((x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy));
            for (int ch = 0; ch < 3; ++ch) {
                float v = XMConvertHalfToFloat(c[ch]); r.image[(y * OUT_W + x) * 3 + ch] = v;
                if (x < 16 || x >= OUT_W - 16 || y < 16 || y >= OUT_H - 16) continue;
                double e = (v - t[ch]) * (v - t[ch]); sumAll += e; ++nAll;
                if (std::fabs(dist - DISC_R) < 14) { sumEdge += e; ++nEdge; }
            }
        }
        colorOut.upload->Unmap(0, nullptr);
        r.all = sumAll / nAll; r.edge = sumEdge / nEdge;
        slFreeResources(sl::kFeatureDLSS, viewport);
        return true;
    };
    auto writePPM = [&](const char* name, const std::vector<float>& img) {
        FILE* f = std::fopen(name, "wb"); std::fprintf(f, "P6\n%u %u\n255\n", OUT_W, OUT_H);
        for (float v : img) std::fputc((int)std::lround(std::min(1.f, std::max(0.f, v)) * 255), f);
        std::fclose(f);
    };

    std::printf("Depth encodings, a disc circling over a static background, %d frames\n", FRAMES);
    std::printf("%-36s %-14s %-14s\n", "depth", "MSE whole", "MSE near edge");
    for (int m = 0; m < 5; ++m) {
        Result r; if (!run((uint32_t)m, (Mode)m, r)) return 3;
        std::printf("%-36s %-14.6f %-14.6f\n", names[m], r.all, r.edge);
        char name[64]; std::snprintf(name, sizeof name, "depth_%d.ppm", m); writePPM(name, r.image);
    }
    std::vector<float> truthImg(OUT_W * OUT_H * 3);
    for (UINT y = 0; y < OUT_H; ++y) for (UINT x = 0; x < OUT_W; ++x) { float t[3]; bool in; truth(x + 0.5, y + 0.5, FRAMES - 1, t, in); for (int c = 0; c < 3; ++c) truthImg[(y * OUT_W + x) * 3 + c] = t[c]; }
    writePPM("depth_truth.ppm", truthImg);
    slShutdown();
    return 0;
}
