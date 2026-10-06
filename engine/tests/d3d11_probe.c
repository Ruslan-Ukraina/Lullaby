/* Creates a D3D11 device and reports which renderer answered, for checking a
 * renderer setup without a game: DXMT goes through winemetal.dll, wined3d does
 * not load it. Exit status: 0 the device came from DXMT, 1 it came from
 * something else, 2 no device at all. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

int main(void)
{
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    IDXGIDevice *dxgi = NULL;
    IDXGIAdapter *adapter = NULL;
    DXGI_ADAPTER_DESC desc;
    D3D_FEATURE_LEVEL level = 0;
    HRESULT hr;

    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                           D3D11_SDK_VERSION, &device, &level, &context);
    printf("D3D11CreateDevice hr=%#lx feature level %#x\n", (unsigned long)hr, (unsigned)level);
    if (FAILED(hr)) return 2;

    if (SUCCEEDED(ID3D11Device_QueryInterface(device, &IID_IDXGIDevice, (void **)&dxgi))
        && SUCCEEDED(IDXGIDevice_GetAdapter(dxgi, &adapter))
        && SUCCEEDED(IDXGIAdapter_GetDesc(adapter, &desc)))
        printf("adapter: %ls (vendor %#x, device %#x)\n", desc.Description,
               (unsigned)desc.VendorId, (unsigned)desc.DeviceId);

    printf("winemetal.dll %s, wined3d.dll %s\n",
           GetModuleHandleA("winemetal.dll") ? "loaded" : "not loaded",
           GetModuleHandleA("wined3d.dll") ? "loaded" : "not loaded");
    return GetModuleHandleA("winemetal.dll") ? 0 : 1;
}
