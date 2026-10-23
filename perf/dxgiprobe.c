/* What a game is told about video memory: DXGI adapter description and the memory budget. Console program.
 *   dxgiprobe.exe        prints one line per adapter */
#define COBJMACROS
#include <windows.h>
#include <dxgi1_4.h>
#include <stdio.h>

static const GUID IID_Adapter3 = {0x645967a4, 0x1392, 0x4310, {0xa7, 0x98, 0x80, 0x53, 0xce, 0x3e, 0x93, 0xfd}};

int main(void)
{
    IDXGIFactory1 *factory;
    IDXGIAdapter1 *adapter;
    UINT i;

    if (FAILED(CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&factory))) { puts("no DXGI factory"); return 1; }
    for (i = 0; SUCCEEDED(IDXGIFactory1_EnumAdapters1(factory, i, &adapter)); i++)
    {
        DXGI_ADAPTER_DESC1 d;
        IDXGIAdapter3 *a3;
        char name[128];

        IDXGIAdapter1_GetDesc1(adapter, &d);
        WideCharToMultiByte(CP_ACP, 0, d.Description, -1, name, sizeof(name), NULL, NULL);
        printf("adapter %u: %s vendor=0x%04x device=0x%04x dedicated=%llu MB dedicated_system=%llu MB shared_system=%llu MB flags=0x%x\n",
               i, name, d.VendorId, d.DeviceId, (unsigned long long)(d.DedicatedVideoMemory >> 20),
               (unsigned long long)(d.DedicatedSystemMemory >> 20), (unsigned long long)(d.SharedSystemMemory >> 20), d.Flags);
        if (SUCCEEDED(IDXGIAdapter1_QueryInterface(adapter, &IID_Adapter3, (void **)&a3)))
        {
            DXGI_QUERY_VIDEO_MEMORY_INFO m;
            if (SUCCEEDED(IDXGIAdapter3_QueryVideoMemoryInfo(a3, 0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &m)))
                printf("  local:     budget=%llu MB current=%llu MB available_for_reservation=%llu MB\n", (unsigned long long)(m.Budget >> 20),
                       (unsigned long long)(m.CurrentUsage >> 20), (unsigned long long)(m.AvailableForReservation >> 20));
            if (SUCCEEDED(IDXGIAdapter3_QueryVideoMemoryInfo(a3, 0, DXGI_MEMORY_SEGMENT_GROUP_NON_LOCAL, &m)))
                printf("  non-local: budget=%llu MB current=%llu MB available_for_reservation=%llu MB\n", (unsigned long long)(m.Budget >> 20),
                       (unsigned long long)(m.CurrentUsage >> 20), (unsigned long long)(m.AvailableForReservation >> 20));
            IDXGIAdapter3_Release(a3);
        }
        IDXGIAdapter1_Release(adapter);
    }
    return 0;
}
