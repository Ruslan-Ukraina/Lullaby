/* Does the engine answer that hardware GPU scheduling (HAGS) is on? (patches/engine ENG-02)
 *
 * NVIDIA Streamline asks KMTQAITYPE_WDDM_2_7_CAPS of the adapter and offers DLSS Frame Generation
 * only when HwSchSupported, HwSchEnabled and HwSchEnabledByDefault are set. This asks the same, the
 * same way (D3DKMTOpenAdapterFromGdiDisplayName, D3DKMTQueryAdapterInfo, from gdi32), and prints the
 * three flags. Value 0x7 with the patch; without it Wine answers "type 70 not handled" and the flags
 * are not set. Exit status 0 when all three are set, 1 when not, 2 when the query itself failed.
 *
 * The structures are written out here: mingw-w64 has no d3dkmthk.h. Layouts are Windows'.
 *   x86_64-w64-mingw32-gcc -O2 -o d3dkmt-hags-caps.exe d3dkmt-hags-caps.c */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

typedef UINT D3DKMT_HANDLE;

typedef struct
{
    WCHAR DeviceName[32];
    D3DKMT_HANDLE hAdapter;
    LUID AdapterLuid;
    UINT VidPnSourceId;
} OPENADAPTERFROMGDIDISPLAYNAME;

typedef struct
{
    D3DKMT_HANDLE hAdapter;
    UINT Type;
    void *pPrivateDriverData;
    UINT PrivateDriverDataSize;
} QUERYADAPTERINFO;

#define KMTQAITYPE_WDDM_2_7_CAPS 70

typedef LONG (WINAPI *open_fn)(OPENADAPTERFROMGDIDISPLAYNAME *);
typedef LONG (WINAPI *query_fn)(QUERYADAPTERINFO *);

int main(void)
{
    HMODULE gdi = LoadLibraryA("gdi32.dll");
    open_fn open_adapter = gdi ? (open_fn)GetProcAddress(gdi, "D3DKMTOpenAdapterFromGdiDisplayName") : NULL;
    query_fn query = gdi ? (query_fn)GetProcAddress(gdi, "D3DKMTQueryAdapterInfo") : NULL;
    OPENADAPTERFROMGDIDISPLAYNAME open = { L"\\\\.\\DISPLAY1" };
    QUERYADAPTERINFO info = { 0 };
    UINT caps = 0;
    LONG status;

    if (!open_adapter || !query) { puts("d3dkmt-hags-caps: gdi32 has no D3DKMT entry points"); return 2; }
    status = open_adapter(&open);
    if (status) { printf("d3dkmt-hags-caps: OpenAdapterFromGdiDisplayName failed, %08lx\n", (unsigned long)status); return 2; }
    info.hAdapter = open.hAdapter;
    info.Type = KMTQAITYPE_WDDM_2_7_CAPS;
    info.pPrivateDriverData = &caps;
    info.PrivateDriverDataSize = sizeof(caps);
    status = query(&info);
    if (status) { printf("d3dkmt-hags-caps: QueryAdapterInfo(WDDM_2_7_CAPS) failed, %08lx\n", (unsigned long)status); return 2; }
    printf("d3dkmt-hags-caps: value %#x  HwSchSupported %u  HwSchEnabled %u  HwSchEnabledByDefault %u\n",
           caps, caps & 1, (caps >> 1) & 1, (caps >> 2) & 1);
    return (caps & 7) == 7 ? 0 : 1;
}
