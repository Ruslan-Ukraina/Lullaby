/* Highball patch candidates on a Dormison engine, no game needed (docs/HIGHBALL_5A.md).
 *
 *   x86_64-w64-mingw32-gcc -O1 -o probe.exe highball-probe.c -lpsapi -lgdi32 -luser32
 *   WINEPREFIX=<scratch prefix> runners/current/wine/bin/wine probe.exe
 *
 * Run it once with HKCU\Software\Wine\Mac Driver\RetinaMode=y for the screen line. */
#include <windows.h>
#include <psapi.h>
#include <stdio.h>

static void *gs_ptr(unsigned off) { void *v; __asm__ volatile("movq %%gs:(%1),%0" : "=r"(v) : "r"((unsigned long long)off)); return v; }
static DWORD gs_dword(unsigned off) { DWORD v; __asm__ volatile("movl %%gs:(%1),%0" : "=r"(v) : "r"((unsigned long long)off)); return v; }

int main(void)
{
    /* 0008: GetCurrentFiber() is the intrinsic read of %gs:0x20 */
    void *fiber = ConvertThreadToFiber((void *)0x1234);
    void *teb = NtCurrentTeb();
    printf("fiber: ConvertThreadToFiber=%p  TEB->FiberData=%p  %%gs:0x20=%p  -> %s\n",
           fiber, ((NT_TIB *)teb)->FiberData, gs_ptr(0x20),
           gs_ptr(0x20) == fiber ? "OK" : "WRONG (Highball 0008/0009 applies)");
    /* 0011: MSVC code reads LastError at %gs:0x68 */
    SetLastError(1234);
    DWORD api = GetLastError(), raw = gs_dword(0x68);
    printf("lasterror: GetLastError=%lu  %%gs:0x68=%lu  -> %s\n", api, raw,
           raw == 1234 ? "OK" : "WRONG (Highball 0011/0016 applies)");
    /* 0020: HORZRES against the other ways of asking for the screen size */
    HDC dc = GetDC(NULL);
    printf("screen: GetSystemMetrics=%dx%d  DESKTOPHORZRES=%dx%d  HORZRES=%dx%d -> %s\n",
           GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN),
           GetDeviceCaps(dc, DESKTOPHORZRES), GetDeviceCaps(dc, DESKTOPVERTRES),
           GetDeviceCaps(dc, HORZRES), GetDeviceCaps(dc, VERTRES),
           GetDeviceCaps(dc, HORZRES) == GetSystemMetrics(SM_CXSCREEN) ? "OK" : "DIFFERS (Highball 0020 applies)");
    ReleaseDC(NULL, dc);
    /* 0018: commit charge */
    PROCESS_MEMORY_COUNTERS_EX pmc = { sizeof(pmc) };
    GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS *)&pmc, sizeof(pmc));
    printf("memory: WorkingSet=%llu MB  PagefileUsage=%llu MB  PrivateUsage=%llu MB -> %s\n",
           (unsigned long long)pmc.WorkingSetSize >> 20, (unsigned long long)pmc.PagefileUsage >> 20,
           (unsigned long long)pmc.PrivateUsage >> 20,
           pmc.PagefileUsage > 4ull * pmc.WorkingSetSize + (512ull << 20) ? "INFLATED (Highball 0018 applies)" : "OK");
    return 0;
}
