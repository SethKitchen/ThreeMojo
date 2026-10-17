// Probe of the real Streamline 2.14.16 DLSS and DLSS-RR plugins on this machine.
// It prints what ThreeMojo's extensions/streamline must agree with.
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <cstdio>
#include <cstddef>
#include <vector>
#include <string>

#include <sl.h>
#include <sl_consts.h>
#include <sl_dlss.h>
#include <sl_dlss_d.h>

using Microsoft::WRL::ComPtr;

static const char* modeName(sl::DLSSMode m) {
    switch (m) {
        case sl::DLSSMode::eOff: return "Off";
        case sl::DLSSMode::eMaxPerformance: return "MaxPerformance";
        case sl::DLSSMode::eBalanced: return "Balanced";
        case sl::DLSSMode::eMaxQuality: return "MaxQuality";
        case sl::DLSSMode::eUltraPerformance: return "UltraPerformance";
        case sl::DLSSMode::eUltraQuality: return "UltraQuality";
        case sl::DLSSMode::eDLAA: return "DLAA";
        default: return "?";
    }
}

static void logCb(sl::LogType type, const char* msg) {
    std::printf("  [sl %d] %s", (int)type, msg);
}

static void ident(sl::float4x4& m) {
    m.setRow(0, sl::float4(1, 0, 0, 0)); m.setRow(1, sl::float4(0, 1, 0, 0));
    m.setRow(2, sl::float4(0, 0, 1, 0)); m.setRow(3, sl::float4(0, 0, 0, 1));
}

int main() {
    std::printf("sizeof DLSSOptions=%zu DLSSDOptions=%zu Constants=%zu float4x4=%zu Boolean=%zu\n",
                sizeof(sl::DLSSOptions), sizeof(sl::DLSSDOptions), sizeof(sl::Constants),
                sizeof(sl::float4x4), sizeof(sl::Boolean));
    std::printf("offsetof DLSSOptions: mode=%zu outW=%zu outH=%zu sharp=%zu pre=%zu expScale=%zu hdr=%zu autoExp=%zu alpha=%zu dlaa=%zu uq=%zu\n",
                offsetof(sl::DLSSOptions, mode), offsetof(sl::DLSSOptions, outputWidth),
                offsetof(sl::DLSSOptions, outputHeight), offsetof(sl::DLSSOptions, sharpness),
                offsetof(sl::DLSSOptions, preExposure), offsetof(sl::DLSSOptions, exposureScale),
                offsetof(sl::DLSSOptions, colorBuffersHDR), offsetof(sl::DLSSOptions, useAutoExposure),
                offsetof(sl::DLSSOptions, alphaUpscalingEnabled), offsetof(sl::DLSSOptions, dlaaPreset),
                offsetof(sl::DLSSOptions, ultraQualityPreset));
    std::printf("Constants defaults: depthInverted=%d minRelLinDepthSep=%g jitter=(%g,%g)\n",
                (int)sl::Constants{}.depthInverted, sl::Constants{}.minRelativeLinearDepthObjectSeparation,
                sl::Constants{}.jitterOffset.x, sl::Constants{}.jitterOffset.y);

    wchar_t exe[MAX_PATH];
    GetModuleFileNameW(nullptr, exe, MAX_PATH);
    std::wstring dir(exe);
    dir = dir.substr(0, dir.find_last_of(L"\\/"));
    const wchar_t* paths[] = {dir.c_str()};
    sl::Feature features[] = {sl::kFeatureDLSS, sl::kFeatureDLSS_RR};

    sl::Preferences pref{};
    pref.showConsole = false;
    pref.logLevel = sl::LogLevel::eVerbose;
    pref.pathsToPlugins = paths;
    pref.numPathsToPlugins = 1;
    pref.pathToLogsAndData = dir.c_str();
    pref.logMessageCallback = logCb;
    pref.flags = sl::PreferenceFlags::eUseManualHooking | sl::PreferenceFlags::eDisableCLStateTracking;
    pref.featuresToLoad = features;
    pref.numFeaturesToLoad = 2;
    pref.engine = sl::EngineType::eCustom;
    pref.engineVersion = "ThreeMojo-probe";
    pref.projectId = "ab4c32fc-e49c-4973-aad2-dc1786489490";
    pref.renderAPI = sl::RenderAPI::eD3D12;

    sl::Result r = slInit(pref);
    std::printf("slInit -> %d\n", (int)r);
    if (r != sl::Result::eOk) return 1;

    ComPtr<IDXGIFactory6> factory;
    CreateDXGIFactory1(IID_PPV_ARGS(&factory));
    ComPtr<IDXGIAdapter1> adapter;
    DXGI_ADAPTER_DESC1 desc{};
    for (UINT i = 0; factory->EnumAdapterByGpuPreference(i, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(&adapter)) == S_OK; ++i) {
        adapter->GetDesc1(&desc);
        if (!(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) && desc.VendorId == 0x10DE) break;
        adapter.Reset();
    }
    if (!adapter) { std::printf("no NVIDIA adapter\n"); return 2; }
    std::wprintf(L"adapter: %s\n", desc.Description);

    ComPtr<ID3D12Device> device;
    HRESULT hr = D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&device));
    std::printf("D3D12CreateDevice -> 0x%lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 3;

    r = slSetD3DDevice(device.Get());
    std::printf("slSetD3DDevice -> %d\n", (int)r);

    sl::AdapterInfo ai{};
    ai.deviceLUID = (uint8_t*)&desc.AdapterLuid;
    ai.deviceLUIDSizeInBytes = sizeof(LUID);
    for (auto f : features) {
        sl::Result s = slIsFeatureSupported(f, ai);
        bool loaded = false;
        slIsFeatureLoaded(f, loaded);
        sl::FeatureVersion ver{};
        slGetFeatureVersion(f, ver);
        sl::FeatureRequirements req{};
        slGetFeatureRequirements(f, req);
        std::printf("feature %u supported=%d loaded=%d version sl=%u.%u.%u ngx=%u.%u.%u  requires OS %u.%u.%u driver %u.%u.%u\n",
                    (unsigned)f, (int)s, (int)loaded, ver.versionSL.major, ver.versionSL.minor, ver.versionSL.build,
                    ver.versionNGX.major, ver.versionNGX.minor, ver.versionNGX.build,
                    req.osVersionDetected.major, req.osVersionDetected.minor, req.osVersionDetected.build,
                    req.driverVersionDetected.major, req.driverVersionDetected.minor, req.driverVersionDetected.build);
    }

    for (auto f : features) {
        sl::FeatureRequirements req{};
        slGetFeatureRequirements(f, req);
        std::printf("requirements %u: flags=0x%x maxViewports=%u maxThreads=%u tags:", (unsigned)f,
                    (unsigned)req.flags, req.maxNumViewports, req.maxNumCPUThreads);
        for (uint32_t i = 0; i < req.numRequiredTags; ++i) std::printf(" %u", req.requiredTags[i]);
        std::printf("\n");
    }
    {
        sl::ViewportHandle vp(0);
        for (int m = 0; m < 8; ++m) {
            sl::DLSSOptions o{};
            o.mode = (sl::DLSSMode)m; o.outputWidth = 1920; o.outputHeight = 1080;
            std::printf("SR SetOptions mode=%d -> %d\n", m, (int)slDLSSSetOptions(vp, o));
        }
        for (int p = 0; p < 17; ++p) {
            sl::DLSSOptions o{};
            o.mode = sl::DLSSMode::eMaxQuality; o.outputWidth = 1920; o.outputHeight = 1080;
            o.qualityPreset = (sl::DLSSPreset)p;
            std::printf("SR SetOptions qualityPreset=%d -> %d\n", p, (int)slDLSSSetOptions(vp, o));
        }
        for (int m = 0; m < 8; ++m) {
            sl::DLSSDOptions o{};
            o.mode = (sl::DLSSMode)m; o.outputWidth = 1920; o.outputHeight = 1080;
            ident(o.worldToCameraView); ident(o.cameraViewToWorld);
            std::printf("RR SetOptions mode=%d -> %d\n", m, (int)slDLSSDSetOptions(vp, o));
        }
        for (int p = 0; p < 17; ++p) {
            sl::DLSSDOptions o{};
            o.mode = sl::DLSSMode::eMaxQuality; o.outputWidth = 1920; o.outputHeight = 1080;
            ident(o.worldToCameraView); ident(o.cameraViewToWorld);
            o.qualityPreset = (sl::DLSSDPreset)p;
            std::printf("RR SetOptions qualityPreset=%d -> %d\n", p, (int)slDLSSDSetOptions(vp, o));
        }
        sl::DLSSState st{};
        sl::DLSSOptions o{}; o.mode = sl::DLSSMode::eMaxQuality; o.outputWidth = 3840; o.outputHeight = 2160;
        slDLSSSetOptions(vp, o);
        std::printf("SR GetState -> %d vram=%llu\n", (int)slDLSSGetState(vp, st), (unsigned long long)st.estimatedVRAMUsageInBytes);
    }
    const sl::DLSSMode modes[] = {sl::DLSSMode::eOff, sl::DLSSMode::eMaxPerformance, sl::DLSSMode::eBalanced, sl::DLSSMode::eMaxQuality,
                                  sl::DLSSMode::eUltraPerformance, sl::DLSSMode::eUltraQuality, sl::DLSSMode::eDLAA};
    const uint32_t sizes[][2] = {{3840, 2160}, {2560, 1440}, {1920, 1080}, {1280, 720}, {1000, 563}};
    std::printf("\nkind\tmode\tout_w\tout_h\tresult\trender_w\trender_h\tmin_w\tmin_h\tmax_w\tmax_h\tsharp\n");
    for (auto& sz : sizes) {
        for (auto m : modes) {
            sl::DLSSOptions o{};
            o.mode = m; o.outputWidth = sz[0]; o.outputHeight = sz[1];
            sl::DLSSOptimalSettings s{};
            sl::Result g = slDLSSGetOptimalSettings(o, s);
            std::printf("SR\t%s\t%u\t%u\t%d\t%u\t%u\t%u\t%u\t%u\t%u\t%g\n", modeName(m), sz[0], sz[1], (int)g,
                        s.optimalRenderWidth, s.optimalRenderHeight, s.renderWidthMin, s.renderHeightMin,
                        s.renderWidthMax, s.renderHeightMax, s.optimalSharpness);
            sl::DLSSDOptions d{};
            d.mode = m; d.outputWidth = sz[0]; d.outputHeight = sz[1];
            sl::DLSSDOptimalSettings ds{};
            sl::Result gd = slDLSSDGetOptimalSettings(d, ds);
            std::printf("RR\t%s\t%u\t%u\t%d\t%u\t%u\t%u\t%u\t%u\t%u\t%g\n", modeName(m), sz[0], sz[1], (int)gd,
                        ds.optimalRenderWidth, ds.optimalRenderHeight, ds.renderWidthMin, ds.renderHeightMin,
                        ds.renderWidthMax, ds.renderHeightMax, ds.optimalSharpness);
        }
    }
    slShutdown();
    return 0;
}
