/* Stand-in for Valve's steamclient64.dll, for checking the ntdll detour without
 * Steam. It exports CreateInterface under the same name lsteamclient.dll does, so
 * a working detour rewrites it into a jump to lsteamclient's. Its DllMain counts
 * itself into fake_dllmain_calls, a name lsteamclient does not export, so the
 * count stays readable and shows whether the detour suppressed DllMain. */
#include <windows.h>

__declspec(dllexport) volatile LONG fake_dllmain_calls = 0;

__declspec(dllexport) void *CreateInterface(const char *name, int *rc)
{
    (void)name;
    if (rc) *rc = 0;
    return (void *)0xfeedface;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *reserved)
{
    (void)inst; (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) InterlockedIncrement(&fake_dllmain_calls);
    return TRUE;
}
