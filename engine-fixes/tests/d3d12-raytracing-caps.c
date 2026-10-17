/* What a D3D12 game is told about ray tracing: the adapter, the raytracing tier
   (D3D12_OPTIONS5) and the features RT paths commonly also need. Built with mingw,
   run under the game's renderer; prints one line per fact. */
#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include <dxgi1_4.h>
#include <d3d12.h>

static const GUID IID_F = {0x7b7166ec,0x21c7,0x44ae,{0xb2,0x1a,0xc9,0xae,0x32,0x1a,0xe3,0x69}};
static const GUID IID_Dev = {0x189819f1,0x1db6,0x4b57,{0xbe,0x54,0x18,0x21,0x33,0x9b,0x85,0xf7}};

int main(void)
{
    IDXGIFactory *f = 0; IDXGIAdapter *a = 0; ID3D12Device *d = 0; DXGI_ADAPTER_DESC desc;
    HRESULT hr = CreateDXGIFactory(&IID_F, (void **)&f);
    if (FAILED(hr) || IDXGIFactory_EnumAdapters(f, 0, &a) == DXGI_ERROR_NOT_FOUND) { printf("no adapter %08lx\n", hr); return 1; }
    IDXGIAdapter_GetDesc(a, &desc);
    printf("adapter vendor 0x%04x device 0x%04x %ls\n", desc.VendorId, desc.DeviceId, desc.Description);
    hr = D3D12CreateDevice((IUnknown *)a, D3D_FEATURE_LEVEL_12_0, &IID_Dev, (void **)&d);
    printf("D3D12CreateDevice %08lx\n", hr);
    if (FAILED(hr)) return 1;

    D3D12_FEATURE_DATA_D3D12_OPTIONS5 o5 = {0};
    hr = ID3D12Device_CheckFeatureSupport(d, D3D12_FEATURE_D3D12_OPTIONS5, &o5, sizeof(o5));
    printf("OPTIONS5 %08lx raytracing tier %d (10 = 1.0, 11 = 1.1) render passes %d\n", hr, o5.RaytracingTier, o5.RenderPassesTier);

    D3D12_FEATURE_DATA_D3D12_OPTIONS7 o7 = {0};
    hr = ID3D12Device_CheckFeatureSupport(d, D3D12_FEATURE_D3D12_OPTIONS7, &o7, sizeof(o7));
    printf("OPTIONS7 %08lx mesh shader tier %d sampler feedback %d\n", hr, o7.MeshShaderTier, o7.SamplerFeedbackTier);

    D3D12_FEATURE_DATA_SHADER_MODEL sm = { D3D_SHADER_MODEL_6_6 };
    hr = ID3D12Device_CheckFeatureSupport(d, D3D12_FEATURE_SHADER_MODEL, &sm, sizeof(sm));
    printf("SHADER_MODEL %08lx highest 0x%x\n", hr, sm.HighestShaderModel);

    D3D12_FEATURE_DATA_D3D12_OPTIONS o = {0};
    hr = ID3D12Device_CheckFeatureSupport(d, D3D12_FEATURE_D3D12_OPTIONS, &o, sizeof(o));
    printf("OPTIONS %08lx resource binding tier %d tiled resources %d\n", hr, o.ResourceBindingTier, o.TiledResourcesTier);
    fflush(stdout);
    return 0;
}
